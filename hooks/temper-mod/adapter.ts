// Adapter helpers: everything that touches Claude Code's `$` (files, store, state, version), so register.tsx stays
// wiring only. The pure rules live in core/.
//
// Where state lives (ADR 0013): the mod reads one file of the CLI's, `.temper/view.json`, and never writes it. The CLI
// writes it after every command that may change the run. The person's decisions are the mod's own: kept in the plugin
// store, one list per run, each stamped with the CLI's run id and step (core/decisions.ts).

import type { PluginOptions } from 'claude-code'

import { parseEnforcement, parseOnOff, parseUiMode, versionAtLeast } from './core/config'
import type { UiMode } from './core/config'
import { allowedCalls, currentAnswer, decisionsOf, describe, driftOf, parseBook, restartFor } from './core/decisions'
import type { At, Decision, DriftState } from './core/decisions'
import { renderReport } from './core/report'
import type { RunFacts } from './core/rules'
import { VIEW_VERSION, parseRunView } from './core/runview'
import type { RunView } from './core/runview'
import { sectionText } from './core/section'
import { cliStage } from './core/stages'
import { buildView } from './core/view'
import type { View } from './core/view'
import type { TemperRun } from '../../types'

// Everything the adapter needs from Claude Code, as plain functions. register.tsx builds one from `$` (the module scan
// only follows `$` inside the file that spells it), which also lets this file be tested without an engine.
export type Io = {
  // File text, or null when the file is missing or unreadable.
  read: (path: string) => Promise<string | null>
  // A text the mod keeps for the project in its store (the mod writes no file), and reads back.
  keep: (name: string, text: string) => Promise<void>
  kept: (name: string) => Promise<string | null>
  storeGet: (key: string) => Promise<unknown>
  storeSet: (key: string, value: unknown) => Promise<void>
  storeDelete: (key: string) => Promise<void>
  version: () => Promise<string | undefined>
  setRun: (run: TemperRun) => Promise<void>
  // The live mode, mirrored so a redraw sees a change at once.
  setMode: (mode: UiMode) => Promise<void>
  // Where the Temper script is (pluginCliFrom). Left out: the plain `scripts/temper`.
  cli?: string
}

export type Snapshot = {
  // True below the minimum Claude Code version or when it cannot be read: nothing acts.
  inert: boolean
  enforcement: 'on' | 'off'
  mode: UiMode
  prAttribution: 'on' | 'off'
  // view.json is of a version this mod does not read, or names a stage it does not know: it blocks nothing.
  failOpen: boolean
  // The one line shown under the bar when the mod cannot read the run as it should; null when all is well.
  line: string | null
  // view.json as read; null with no run.
  view: RunView | null
  slug: string | null
  // The command that started the run (`temper` or `fix`). A /temper:fix run is left to commands/fix.md.
  runCommand: string | null
  specDir: string
  // The run as the guard reads it; null when no /temper run is active.
  run: RunFacts | null
  // The CLI's run id and step: where a new decision is stamped, and what an old one is read against.
  at: At
  // The person's decisions in this run, oldest first, and the latest gate answer at this step.
  decisions: Decision[]
  answer: Extract<Decision, { kind: 'gate' }> | null
  // The calls the person's answers at this step map to, and those of the CLI's own action (see RuleContext).
  allowed: string[]
  restart: boolean
  drift: DriftState
}

export const VIEW_PATH = '.temper/view.json'
const REPORT = 'report.md'
// The store keys of the decisions: one list per run (`dec:<run id>`), the runs kept (oldest first), and the ids a call
// spent (`used:<id>`).
const BOOK = 'dec:'
const RUNS = 'decruns'
const USED = 'used:'
const MAX_RUNS = 40

const str = (options: PluginOptions, key: string): string | undefined => {
  const v = options[key]
  return typeof v === 'string' ? v : undefined
}

// Values changed live (`/temper:temper mode`, `/temper:temper enforcement`) win over the options of this load until the
// config change reloads the module with the new options.
export const live: { mode?: UiMode; enforcement?: 'on' | 'off'; paneOpen?: boolean } = {}

export function settingsFrom(options: PluginOptions) {
  return {
    mode: live.mode ?? parseUiMode(str(options, 'uiMode')),
    enforcement: live.enforcement ?? parseEnforcement(str(options, 'enforcement')),
    prAttribution: parseOnOff(str(options, 'prAttribution'), 'on'),
  }
}

export function idleSnapshot(options: PluginOptions, inert: boolean): Snapshot {
  return {
    inert,
    ...settingsFrom(options),
    failOpen: false,
    line: null,
    view: null,
    slug: null,
    runCommand: null,
    specDir: '',
    run: null,
    at: { run: '', step: -1 },
    decisions: [],
    answer: null,
    allowed: [],
    restart: false,
    drift: { added: [], allowOnce: [] },
  }
}

const readText = (io: Io, path: string): Promise<string | null> => io.read(path).catch(() => null)

async function usedIds(io: Io, book: readonly Decision[]): Promise<Set<string>> {
  const used = new Set<string>()
  for (const d of book) if (d.kind === 'drift' && d.choice === 'allow-once') if (await io.storeGet(USED + d.id).catch(() => undefined)) used.add(d.id)
  return used
}

// The decisions kept for one run.
export async function readBook(io: Io, run: string): Promise<Decision[]> {
  return parseBook(await io.storeGet(BOOK + run).catch(() => undefined))
}

// Keeps one decision of the person, stamped with the CLI's run and step. The store holds the decisions of the last
// MAX_RUNS runs on this machine; an older run's list is dropped.
export async function keepDecision(io: Io, at: At, stage: string, body: Record<string, unknown> & { kind: Decision['kind'] }): Promise<Decision> {
  const now = Date.now()
  const d = { ...body, id: `${now.toString(36)}-${Math.random().toString(36).slice(2, 10)}`, run: at.run, step: at.step, stage, ts: now } as Decision
  await io.storeSet(BOOK + at.run, [...(await readBook(io, at.run)), d])
  const raw = await io.storeGet(RUNS).catch(() => undefined)
  const runs = (Array.isArray(raw) ? raw.filter((r): r is string => typeof r === 'string') : []).filter(r => r !== at.run)
  runs.push(at.run)
  while (runs.length > MAX_RUNS) {
    const old = runs.shift() as string
    await io.storeDelete(BOOK + old).catch(() => undefined)
  }
  await io.storeSet(RUNS, runs)
  return d
}

// An Allow once answer a write used: it counts once.
export async function spendDecision(io: Io, id: string): Promise<void> {
  await io.storeSet(USED + id, 1)
}

const CANNOT_TELL = 'Temper state: the mod cannot tell where the run is. It does not block anything until the state can be read.'
const NEWER = `Temper state: .temper/view.json is not of version ${VIEW_VERSION}, the one this mod reads. It draws nothing and blocks nothing; update Temper.`

export async function loadSnapshot(io: Io, options: PluginOptions): Promise<Snapshot> {
  const version = await io.version().catch(() => undefined)
  if (!versionAtLeast(version)) return idleSnapshot(options, true)
  const idle = idleSnapshot(options, false)
  const text = await readText(io, VIEW_PATH)
  if (text === null) return idle
  const rv = parseRunView(text)
  if (rv === null) {
    // A view of another version is no view: fail open. Text that is not a view at all is no run (the last run read is
    // held, see register.tsx).
    let other = false
    try {
      const v = (JSON.parse(text) as { version?: unknown }).version
      other = v !== undefined && v !== VIEW_VERSION
    } catch {
      other = false
    }
    return other ? { ...idle, failOpen: true, line: NEWER } : idle
  }
  if (rv.run === null) return idle
  // A /temper:fix run: the mod stands aside. commands/fix.md asks every gate in the conversation and the native commit
  // hook gates the commit; the mod draws no bar, refuses nothing and records nothing for it.
  if (rv.run.command === 'fix' || rv.guard?.fixRun === true) return { ...idle, view: rv, slug: rv.run.slug, specDir: rv.run.spec, runCommand: 'fix' }

  const stage = cliStage(rv.run.stage)
  const g = rv.guard
  const at: At = { run: rv.run.id, step: rv.run.step }
  const book = await readBook(io, at.run)
  const used = await usedIds(io, book)
  const run: RunFacts | null =
    stage === null || g === null
      ? null
      : { stage, step: g.step, specDir: g.spec, planFiles: g.planFiles, groupedActive: g.grouped, trivialExit: g.trivialExit }
  return {
    ...idle,
    failOpen: run === null,
    line: run === null ? CANNOT_TELL : null,
    view: rv,
    slug: rv.run.slug,
    runCommand: rv.run.command,
    specDir: rv.run.spec,
    run,
    at,
    decisions: decisionsOf(book, at.run),
    answer: currentAnswer(book, at, rv.ask?.question.question ?? null),
    allowed: [...allowedCalls(book, at), ...rv.next.calls, ...rv.next.steps],
    restart: restartFor(book, at) !== null,
    drift: driftOf(book, at.run, used),
  }
}

// The report of the run as it stands, not kept.
export function reportText(snap: Snapshot): string {
  if (snap.view === null) return 'No Temper run is active. There is no report to show.'
  return renderReport({ view: snap.view, decisions: snap.decisions, generatedAt: Date.now() })
}

// Keeps the report (the mod writes no file) and returns its text.
export async function writeReport(io: Io, snap: Snapshot): Promise<string> {
  const md = reportText(snap)
  await io.keep(REPORT, md)
  return md
}

// The report kept last in this project, for `/temper:temper report` with no run active. Null when there is none.
export async function keptReport(io: Io): Promise<string | null> {
  const text = await io.kept(REPORT).catch(() => null)
  return text !== null && text.trim() !== '' ? text : null
}

// The line of the system prompt for a /temper:fix run, where the mod stands aside (see loadSnapshot).
export const FIX_RUN = 'Phase: a /temper:fix run. The Temper bar and its guard stand aside for it: ask every gate in the conversation, as commands/fix.md says.'

export function composeText(snap: Snapshot): string {
  if (snap.runCommand === 'fix' && snap.run === null) {
    return sectionText({ enforcement: snap.enforcement, view: null }).replace('Phase: none. No Temper run is active.', FIX_RUN)
  }
  return sectionText({ enforcement: snap.enforcement, view: snap.run === null ? null : viewOf(snap), line: snap.line })
}

const EMPTY: RunView = parseRunView(JSON.stringify({ version: VIEW_VERSION, run: null })) as RunView

export const viewOf = (snap: Snapshot): View =>
  buildView({ view: snap.view ?? EMPTY, decisions: snap.decisions, answer: snap.answer, enforcement: snap.enforcement, line: snap.line, paneOpen: live.paneOpen ?? false })

// Mirrors the run into `$.state` for drawing and compaction.
export async function publish(io: Io, snap: Snapshot): Promise<void> {
  const v = viewOf(snap)
  await io.setRun({ slug: snap.slug, stage: v.stage, title: v.title, summary: composeText(snap), view: v })
  await io.setMode(snap.mode)
}

const iso = (ts: number): string => new Date(ts).toISOString()

// `/temper:temper status`: the section text plus the counts a person wants at a glance.
export function statusText(snap: Snapshot): string {
  if (snap.runCommand === 'fix' && snap.run === null) return FIX_RUN
  if (snap.run === null || snap.view === null) return snap.line ?? 'No Temper run is active. Start one with /temper:temper <feature description>.'
  const lines = [composeText(snap)]
  lines.push(`Mode: ${snap.mode}, enforcement: ${snap.enforcement}`)
  const skipped = snap.view.skips.map(s => s.stage)
  if (skipped.length > 0) lines.push(`Skipped: ${skipped.join(', ')}`)
  for (const l of snap.view.loops) lines.push(`Loop ${l.from} to ${l.to}: ${l.iteration} of ${l.max}`)
  if (snap.decisions.length > 0) lines.push(`Your decisions in this run: ${snap.decisions.length} (/temper:temper timeline lists them)`)
  return lines.join('\n')
}

// `/temper:temper timeline`: the person's decisions in this run, oldest first.
export function timelineText(snap: Snapshot): string {
  if (snap.decisions.length === 0) return 'No decisions yet in this run.'
  return snap.decisions.map(d => `${iso(d.ts)}  ${describe(d)}`).join('\n')
}
