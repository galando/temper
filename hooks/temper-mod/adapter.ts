// Adapter helpers: everything that touches Claude Code's `$` (files, store, state,
// version) so register.tsx can stay wiring only. The pure rules live in core/.
//
// Where state lives (mods-plan 3.3): phase history is append only event files under
// `.temper/specs/{slug}/events/`, one file per event, written once with a unique name.
// Verdicts and criteria status are read, never written, from `.temper/gates.json` and
// `.temper/status.json`. The folded RunState is cached in this module and mirrored to
// `$.state` so drawing and compaction see it.

import type { PluginOptions } from 'claude-code'

import { parseEnforcement, parseMaxLoops, parseOnOff, parseUiMode, versionAtLeast } from './core/config'
import type { UiMode } from './core/config'
import { mergeCriteria, parseCriteria, parseStatus, parseTitle, progress } from './core/criteria'
import type { MergedCriterion } from './core/criteria'
import { encodeEvent, eventFileName, readEvents, stamp } from './core/events'
import type { Draft, TemperEvent } from './core/events'
import { parseBuildState, parseFindings, parseGates, phaseFromStage } from './core/gates'
import type { Finding } from './core/gates'
import { buildView } from './core/view'
import type { View } from './core/view'
import { decide, initialState, phaseLabel, reduce } from './core/machine'
import type { Command, RunState, Verdicts } from './core/machine'
import { planFileList, taskProgress } from './core/planfiles'
import { renderReport } from './core/report'
import { sectionText } from './core/section'
import type { DecisionKind } from './core/bash'
import type { TemperRun } from '../../types'

// Everything the adapter needs from Claude Code, as plain functions. register.tsx builds
// one from `$` (the module scan only follows `$` inside the file that spells it), which
// also lets this file be tested without an engine.
export type Io = {
  // File text, or null when the file is missing or unreadable.
  read: (path: string) => Promise<string | null>
  list: (path: string) => Promise<Array<{ name: string; kind: string }>>
  write: (path: string, text: string) => Promise<void>
  storeGet: (key: string) => Promise<unknown>
  storeSet: (key: string, value: unknown) => Promise<void>
  version: () => Promise<string | undefined>
  setRun: (run: TemperRun) => Promise<void>
  // The live mode, mirrored so a redraw sees a change at once.
  setMode: (mode: UiMode) => Promise<void>
}

export type Snapshot = {
  // True below the minimum Claude Code version or when it cannot be read: nothing acts.
  inert: boolean
  enforcement: 'on' | 'off'
  mode: UiMode
  prAttribution: 'on' | 'off'
  slug: string | null
  specDir: string
  state: RunState
  verdicts: Verdicts
  planFiles: string[]
  title: string | null
  criteria: MergedCriterion[]
  findings: Finding[]
  // "task N of M": see taskProgress in core/planfiles.ts (ticked rows in tasks.md, or
  // the numeric `task` in build-state.json when the orchestrator sets one).
  task: { n: number; of: number } | null
  unreadable: string[]
  // Unconsumed human decision events per kind, for the CLI decision guard.
  humanDecisions: Partial<Record<DecisionKind, number>>
}

const OWN_PREFIX = 'ev:'
const USED_PREFIX = 'used:'
const STATE_ROOT = '.temper'
const REPORT_PATH = `${STATE_ROOT}/report.md`

const str = (options: PluginOptions, key: string): string | undefined => {
  const v = options[key]
  return typeof v === 'string' ? v : undefined
}

// Values changed live (`/temper mode`, `/temper enforcement`) win over the options of this
// load until the config change reloads the module with the new options.
export const live: { mode?: UiMode; enforcement?: 'on' | 'off' } = {}

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
    slug: null,
    specDir: '',
    state: initialState(parseMaxLoops('', str(options, 'fixMaxLoops'))),
    verdicts: {},
    planFiles: [],
    title: null,
    criteria: [],
    findings: [],
    task: null,
    unreadable: [],
    humanDecisions: {},
  }
}

const readText = (io: Io, path: string): Promise<string | null> => io.read(path).catch(() => null)

async function readEventFiles(io: Io, dir: string): Promise<Array<{ name: string; text: string }>> {
  const entries = await io.list(dir).catch(() => [])
  const out: Array<{ name: string; text: string }> = []
  for (const entry of entries) {
    if (entry.kind !== 'file' || !entry.name.endsWith('.json')) continue
    const text = await readText(io, `${dir}/${entry.name}`)
    out.push({ name: entry.name, text: text ?? '' })
  }
  return out
}

// A decision event the person made that no CLI call has matched yet.
function humanKind(ev: TemperEvent): DecisionKind | null {
  if (ev.origin !== 'person') return null
  if (ev.type === 'override') return 'override'
  if (ev.type === 'accept') return 'accept'
  if (ev.type === 'advance' && (ev.from === 'intent' || ev.from === 'plan')) return 'advance'
  return null
}

async function isOwn(io: Io, id: string): Promise<boolean> {
  try {
    return (await io.storeGet(OWN_PREFIX + id)) === 1
  } catch {
    return false
  }
}

// Event names are `{ts}-{session}-{seq}.json`. This module has no session id call, so a
// random token per load stands in: two loads never share a name.
const SESSION = (globalThis.crypto?.randomUUID?.() ?? Math.random().toString(16).slice(2) + '00000000').replace(/-/g, '').slice(0, 8)
let seq = 0

export async function loadSnapshot(io: Io, options: PluginOptions): Promise<Snapshot> {
  const version = await io.version().catch(() => undefined)
  if (!versionAtLeast(version)) return idleSnapshot(options, true)

  const cfg = settingsFrom(options)
  const maxLoops = parseMaxLoops((await readText(io, '.claude/temper.config')) ?? '', str(options, 'fixMaxLoops'))
  const bs = parseBuildState((await readText(io, `${STATE_ROOT}/build-state.json`)) ?? '')
  if (!bs) return { ...idleSnapshot(options, false), state: initialState(maxLoops) }

  const specDir = bs.specPath
  const verdicts = parseGates((await readText(io, `${STATE_ROOT}/gates.json`)) ?? '')
  const intentText = (await readText(io, `${specDir}/intent.md`)) ?? ''
  const title = parseTitle(intentText) ?? bs.spec

  const own = new Set<string>()
  const fold = (events: readonly TemperEvent[]) => reduce(events, verdicts, { maxLoops, isTrusted: ev => own.has(ev.id) })

  const read = readEvents(await readEventFiles(io, `${specDir}/events`))
  const unreadable = read.unreadable
  let events = read.events
  // One store key per event id: an event file whose id is not here was not written by
  // this mod, so it is unverified and never counts as an approval.
  for (const ev of events) if (await isOwn(io, ev.id)) own.add(ev.id)
  let state = fold(events)

  // A run the CLI began before the mod saw it: enter it once, at the phase the CLI
  // recorded. The start event is written by the mod itself, so it is a trusted record.
  if (!events.some(e => e.type === 'start')) {
    const phase = phaseFromStage(bs.nextStage)
    if (phase !== 'done') {
      const start = await writeEvent(io, specDir, { type: 'start', slug: bs.spec, title, phase, origin: 'system' })
      events = [...events, start]
      own.add(start.id)
      state = fold(events)
    }
  }

  const planText = (await readText(io, `${specDir}/plan.md`)) ?? ''
  const tasksText = (await readText(io, `${specDir}/tasks.md`)) ?? ''
  const status = parseStatus((await readText(io, `${STATE_ROOT}/status.json`)) ?? '')

  const humanDecisions: Partial<Record<DecisionKind, number>> = {}
  for (const ev of events) {
    const kind = humanKind(ev)
    if (kind && own.has(ev.id) && !(await io.storeGet(USED_PREFIX + ev.id))) {
      humanDecisions[kind] = (humanDecisions[kind] ?? 0) + 1
    }
  }

  return {
    inert: false,
    ...cfg,
    slug: bs.spec,
    specDir,
    state,
    verdicts,
    planFiles: planFileList(planText, tasksText),
    title,
    criteria: mergeCriteria(parseCriteria(intentText), status),
    findings: parseFindings((await readText(io, `${STATE_ROOT}/evidence/review.json`)) ?? ''),
    task: taskProgress(tasksText, bs.task),
    unreadable: unreadable.map(u => u.name),
    humanDecisions,
  }
}

// Writes one event file, once, under a unique name, and records its id in `$.store` (one
// key per id) so a later load can tell its own events from files it did not write.
export async function writeEvent(io: Io, specDir: string, draft: Draft): Promise<TemperEvent> {
  seq += 1
  const ev = stamp(draft, { ts: Date.now(), session: SESSION, seq })
  await io.write(`${specDir}/events/${eventFileName(ev)}`, encodeEvent(ev))
  await io.storeSet(OWN_PREFIX + ev.id, 1)
  return ev
}

// Marks the oldest unconsumed human event of `kind` as matched by a CLI call.
export async function consumeDecision(io: Io, snap: Snapshot, kind: DecisionKind): Promise<void> {
  const { events } = readEvents(await readEventFiles(io, `${snap.specDir}/events`))
  for (const ev of events) {
    if (humanKind(ev) !== kind || !(await isOwn(io, ev.id)) || (await io.storeGet(USED_PREFIX + ev.id))) continue
    await io.storeSet(USED_PREFIX + ev.id, 1)
    return
  }
}

export type Applied = { snap: Snapshot; error?: string; events: Draft[] }

// Runs one command through the machine; on success writes its events, reloads the
// snapshot, and writes `.temper/report.md` when the run reached Done.
export async function apply(io: Io, options: PluginOptions, snap: Snapshot, command: Command): Promise<Applied> {
  const decision = decide(snap.state, command)
  if ('error' in decision) return { snap, error: decision.error, events: [] }
  for (const draft of decision.events) await writeEvent(io, snap.specDir, draft)
  const next = await loadSnapshot(io, options)
  await publish(io, next)
  if (next.state.phase === 'done' && snap.state.phase !== 'done') await writeReport(io, next)
  return { snap: next, events: decision.events }
}

export async function writeReport(io: Io, snap: Snapshot): Promise<void> {
  const md = renderReport({
    state: snap.state,
    criteria: snap.criteria,
    generatedAt: Date.now(),
    unreadable: snap.unreadable,
  })
  await io.write(REPORT_PATH, md)
}

export function composeText(snap: Snapshot): string {
  const s = snap.state
  return sectionText({
    enforcement: snap.enforcement,
    phase: s.phase,
    title: snap.title,
    task: snap.task,
    progress: snap.criteria.length > 0 ? progress(snap.criteria) : null,
    paused: s.paused,
    loopLimitReached: s.loopLimitReached,
    stale: s.stale,
    actionContext: {
      ready: s.phase !== null && s.phase !== 'done' ? s.gate[s.phase] === 'fresh' : false,
      allChecksPass: s.gate.check === 'fresh',
    },
  })
}

export const viewOf = (snap: Snapshot): View =>
  buildView({ state: snap.state, title: snap.title, criteria: snap.criteria, findings: snap.findings, task: snap.task, enforcement: snap.enforcement })

// Mirrors the folded state into `$.state` for drawing and compaction.
export async function publish(io: Io, snap: Snapshot): Promise<void> {
  await io.setRun({ slug: snap.slug, phase: snap.state.phase, title: snap.title, summary: composeText(snap), view: viewOf(snap) })
  await io.setMode(snap.mode)
}

// Check results are read from the CLI's verdict, never decided here. A fresh PASS ends
// the run; a fresh FAIL (only when `includeFail`, after `temper gate check` ran) enters Fix.
export async function syncCheck(io: Io, options: PluginOptions, snap: Snapshot, includeFail: boolean): Promise<Snapshot> {
  if (snap.state.phase !== 'check') return snap
  const gate = snap.state.gate.check
  const result = gate === 'fresh' ? 'pass' : gate === 'fail' && includeFail ? 'fail' : null
  if (result === null) return snap
  return (await apply(io, options, snap, { type: 'checkResult', result, origin: 'system' })).snap
}

const iso = (ts: number): string => new Date(ts).toISOString()

// `/temper status`: the section text plus the counts a person wants at a glance.
export function statusText(snap: Snapshot): string {
  if (snap.state.phase === null) return 'No Temper run is active. Start one with /temper <feature description>.'
  const s = snap.state
  const lines = [composeText(snap)]
  lines.push(`Mode: ${snap.mode}, enforcement: ${snap.enforcement}`)
  if (s.loops > 0) lines.push(`Check to Fix loops: ${s.loops} (limit ${s.maxLoops})`)
  if (s.overrides.length > 0) lines.push(`Overrides: ${s.overrides.length}`)
  if (s.accepted.length > 0) lines.push(`Accepted findings: ${s.accepted.length}`)
  if (s.drift.length > 0) lines.push(`Scope drift decisions: ${s.drift.length}`)
  if (s.unverified.length > 0) lines.push(`Unverified event files (not counted): ${s.unverified.length}`)
  if (snap.unreadable.length > 0) lines.push(`Unreadable event files: ${snap.unreadable.join(', ')}`)
  return lines.join('\n')
}

export function timelineText(snap: Snapshot): string {
  const h = snap.state.history
  if (h.length === 0) return 'No phases yet.'
  return h
    .map(r => `${iso(r.ts)}  ${r.kind}: ${r.from ? phaseLabel(r.from) : 'start'} to ${phaseLabel(r.to)}`)
    .join('\n')
}
