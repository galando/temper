// Adapter helpers: everything that touches Claude Code's `$` (files, store, state, version), so register.tsx stays
// wiring only. The pure rules live in core/.
//
// Where state lives (ADR 0012): where the run is, its verdicts, skips, loops and groups are the CLI's files, read and
// never written. The person's decisions are the mod's own: kept in the plugin store, one list per run, each stamped with
// the CLI's run id and step (core/decisions.ts). The mod keeps no run state of its own.

import type { PluginOptions } from 'claude-code'

import { parseEnforcement, parseOnOff, parseUiMode, readConfigValue, versionAtLeast } from './core/config'
import type { UiMode } from './core/config'
import { mergeCriteria, parseCriteria, parseStatus, parseTitle } from './core/criteria'
import type { MergedCriterion } from './core/criteria'
import { parseBuildState, parseFindings, parseGates, parseGroups, parseLoops, parseSkips } from './core/clifiles'
import type { Finding, Gates, GroupRow, Loop, Skips } from './core/clifiles'
import { approvedPlanFiles, currentMove, acceptsAt, decisionsOf, describe, driftOf, parseBook, restartFor } from './core/decisions'
import type { At, Decision, DriftState, Move } from './core/decisions'
import { planFileList, taskProgress, tasksLeft } from './core/planfiles'
import { parseUsage, renderReport } from './core/report'
import type { UsageRow } from './core/report'
import type { RunFacts } from './core/rules'
import { sectionText } from './core/section'
import { cliStage, stageIndex, stageLabel } from './core/stages'
import type { Stage } from './core/stages'
import { buildView } from './core/view'
import type { View } from './core/view'
import type { TemperRun } from '../../types'

// Everything the adapter needs from Claude Code, as plain functions. register.tsx builds one from `$` (the module scan
// only follows `$` inside the file that spells it), which also lets this file be tested without an engine.
export type Io = {
  // File text, or null when the file is missing or unreadable.
  read: (path: string) => Promise<string | null>
  list: (path: string) => Promise<Array<{ name: string; kind: string }>>
  write: (path: string, text: string) => Promise<void>
  storeGet: (key: string) => Promise<unknown>
  storeSet: (key: string, value: unknown) => Promise<void>
  storeDelete: (key: string) => Promise<void>
  version: () => Promise<string | undefined>
  setRun: (run: TemperRun) => Promise<void>
  // The live mode, mirrored so a redraw sees a change at once.
  setMode: (mode: UiMode) => Promise<void>
  // Waits ms milliseconds (the engine's clock: the mod reads no global timer).
  pause: (ms: number) => Promise<void>
  // Where the Temper script is (pluginCliFrom). Left out: the plain `scripts/temper`.
  cli?: string
}

export type Snapshot = {
  // True below the minimum Claude Code version or when it cannot be read: nothing acts.
  inert: boolean
  enforcement: 'on' | 'off'
  mode: UiMode
  prAttribution: 'on' | 'off'
  // The CLI's next stage is no name the mod knows: it blocks nothing until the state reads again.
  failOpen: boolean
  // The one line shown under the bar when the mod cannot read the run as it should; null when all is well.
  line: string | null
  slug: string | null
  // The command that started the run (`temper` or `fix`). A /temper:fix run is left to commands/fix.md.
  runCommand: string | null
  specDir: string
  // The CLI's `next_stage` as written.
  cliNext: string | null
  // The run as the guard reads it; null when no /temper run is active.
  run: RunFacts | null
  // The CLI's run id and step: where a new decision is stamped, and what an old one is read against.
  at: At
  title: string | null
  criteria: MergedCriterion[]
  findings: Finding[]
  gates: Gates
  skips: Skips
  loops: Loop[]
  groups: GroupRow[] | null
  task: { n: number; of: number } | null
  tasksLeft: number | null
  usage: UsageRow[]
  // Check wrote config-suggestions.json in the spec folder.
  configSuggestions: boolean
  // The person's decisions in this run, oldest first, and the move that counts at this step.
  decisions: Decision[]
  move: Move | null
  accepts: string[]
  restart: boolean
  drift: DriftState
}

const STATE_ROOT = '.temper'
const REPORT_PATH = `${STATE_ROOT}/report.md`
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

const NO_DRIFT: DriftState = { added: [], allowOnce: [] }

export function idleSnapshot(options: PluginOptions, inert: boolean): Snapshot {
  return {
    inert,
    ...settingsFrom(options),
    failOpen: false,
    line: null,
    slug: null,
    runCommand: null,
    specDir: '',
    cliNext: null,
    run: null,
    at: { run: '', step: -1 },
    title: null,
    criteria: [],
    findings: [],
    gates: {},
    skips: {},
    loops: [],
    groups: null,
    task: null,
    tasksLeft: null,
    usage: [],
    configSuggestions: false,
    decisions: [],
    move: null,
    accepts: [],
    restart: false,
    drift: NO_DRIFT,
  }
}

const readText = (io: Io, path: string): Promise<string | null> => io.read(path).catch(() => null)

async function usedIds(io: Io, book: readonly Decision[]): Promise<Set<string>> {
  const used = new Set<string>()
  for (const d of book) if (d.kind === 'keep' || d.kind === 'drift') if (await io.storeGet(USED + d.id).catch(() => undefined)) used.add(d.id)
  return used
}

// The decisions kept for one run.
export async function readBook(io: Io, run: string): Promise<Decision[]> {
  return parseBook(await io.storeGet(BOOK + run).catch(() => undefined))
}

// Keeps one decision of the person, stamped with the CLI's run and step. The store holds the decisions of the last
// MAX_RUNS runs on this machine; an older run's list is dropped.
export async function keepDecision(io: Io, at: At, stage: Stage, body: Record<string, unknown> & { kind: Decision['kind'] }): Promise<Decision> {
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

// A decision a call spent (Keep the agent's commits, an Allow once answer): it counts once.
export async function spendDecision(io: Io, id: string): Promise<void> {
  await io.storeSet(USED + id, 1)
}

export async function loadSnapshot(io: Io, options: PluginOptions): Promise<Snapshot> {
  const version = await io.version().catch(() => undefined)
  if (!versionAtLeast(version)) return idleSnapshot(options, true)

  const configText = (await readText(io, '.claude/temper.config')) ?? ''
  const autonomyEnabled = readConfigValue(configText, 'autonomy.enabled') === 'true'
  const designRequired = readConfigValue(configText, 'phases.design') === 'true'
  const statePath = `${STATE_ROOT}/build-state.json`
  let raw = await readText(io, statePath)
  let bs = parseBuildState(raw ?? '')
  // The CLI rewrites build-state.json in place, so a read in that instant sees an empty or cut file (found live). A file
  // that exists but does not read as a run is read again before the mod decides there is none.
  for (let i = 0; i < 4 && bs === null && raw !== null; i++) {
    await io.pause(60).catch(() => undefined)
    raw = await readText(io, statePath)
    bs = parseBuildState(raw ?? '')
  }
  const idle = idleSnapshot(options, false)
  if (!bs) return idle
  // A /temper:fix run: the mod stands aside. commands/fix.md asks every gate in the conversation and the native commit
  // hook gates the commit; the mod draws no bar, refuses nothing and records nothing for it.
  if (bs.command === 'fix') return { ...idle, slug: bs.spec, specDir: bs.specPath, runCommand: 'fix', cliNext: bs.nextStage }

  const specDir = bs.specPath
  const stage = cliStage(bs.nextStage)
  const at: At = { run: bs.runId, step: bs.step }
  const book = await readBook(io, at.run)
  const used = await usedIds(io, book)
  const gates = parseGates((await readText(io, `${STATE_ROOT}/gates.json`)) ?? '')
  const skips = parseSkips((await readText(io, `${STATE_ROOT}/overrides.json`)) ?? '')
  const intentText = (await readText(io, `${specDir}/intent.md`)) ?? ''
  const planText = (await readText(io, `${specDir}/plan.md`)) ?? ''
  const tasksText = (await readText(io, `${specDir}/tasks.md`)) ?? ''
  const groupsText = await readText(io, `${STATE_ROOT}/groups.json`)
  const specFiles = (await io.list(specDir).catch(() => [])).filter(e => e.kind === 'file').map(e => e.name)
  const status = parseStatus((await readText(io, `${STATE_ROOT}/status.json`)) ?? '')
  const verdicts: RunFacts['verdicts'] = {}
  for (const [k, v] of Object.entries(gates)) verdicts[k as Stage] = v.verdict
  const run: RunFacts | null =
    stage === null
      ? null
      : {
          stage,
          step: bs.step,
          runMode: bs.runMode,
          complexity: bs.complexity,
          designRequired,
          // A design.md in the spec folder means the run has Design, as the CLI's commit gate reads it (it wants a
          // design verdict exactly then): a run started for an existing spec has no complexity yet.
          designSeen: stage === 'design' || gates.design !== undefined || specFiles.includes('design.md'),
          autonomyEnabled,
          groupedActive: groupsText !== null,
          verdicts,
          skipped: new Set(Object.keys(skips) as Stage[]),
          specDir,
          // While the plan is written (Intent, Plan) it is read as it is; from Design on, as the person approved it.
          planFiles: (stageIndex(stage) > stageIndex('plan') ? approvedPlanFiles(book, at.run) : null) ?? planFileList(planText, tasksText),
        }
  const decisions = decisionsOf(book, at.run)
  return {
    ...idle,
    failOpen: stage === null,
    line: stage === null ? 'Temper state: the mod cannot tell where the run is. It does not block anything until the state can be read.' : null,
    slug: bs.spec,
    runCommand: bs.command,
    specDir,
    cliNext: bs.nextStage,
    run,
    at,
    title: parseTitle(intentText) ?? bs.spec,
    criteria: mergeCriteria(parseCriteria(intentText), status),
    findings: parseFindings((await readText(io, `${STATE_ROOT}/evidence/review.json`)) ?? ''),
    gates,
    skips,
    loops: parseLoops((await readText(io, `${STATE_ROOT}/feedback-loops.json`)) ?? ''),
    groups: groupsText !== null || /^##\s+Group\s+G\d+/m.test(tasksText) ? parseGroups(tasksText, groupsText ?? '') : null,
    task: taskProgress(tasksText, bs.task),
    tasksLeft: tasksLeft(tasksText),
    usage: parseUsage((await readText(io, `${STATE_ROOT}/usage.json`)) ?? ''),
    configSuggestions: specFiles.includes('config-suggestions.json'),
    decisions,
    move: currentMove(book, at, used),
    accepts: acceptsAt(book, at).map(d => d.findingId),
    restart: restartFor(book, at.run) !== null,
    drift: driftOf(book, at.run, used),
  }
}

// The spec files a run writes once it has an intent; a run that holds one of them has something to lose.
const RUN_ARTIFACTS = ['intent.md', 'plan.md', 'tasks.md', 'design.md']

// The TRIVIAL exit of the orchestrator: a `state clear` of a run that never left Intent. Read fresh for the call, so a
// file written a moment ago counts. True only when the CLI's files and the spec folder all say so:
//  - build-state.json: Intent is next, and its stage shows no completed step (`state init` writes `started`);
//  - gates.json holds no verdict, and overrides.json is an empty list (each may also be missing);
//  - the spec folder holds none of intent.md, plan.md, tasks.md and design.md, as a text or as a name in its listing.
export async function nothingToLose(io: Io, specDir: string): Promise<boolean> {
  const json = async (path: string): Promise<unknown> => {
    const text = await readText(io, path)
    return text === null ? undefined : JSON.parse(text)
  }
  try {
    const bs = await json(`${STATE_ROOT}/build-state.json`)
    if (typeof bs !== 'object' || bs === null) return false
    const { stage, next_stage: next } = bs as { stage?: unknown; next_stage?: unknown }
    if (next !== 'intent' || typeof stage !== 'string' || stage.includes('_complete')) return false
    const gates = await json(`${STATE_ROOT}/gates.json`)
    if (gates !== undefined) {
      if (typeof gates !== 'object' || gates === null || Array.isArray(gates)) return false
      if (Object.values(gates).some(row => typeof row === 'object' && row !== null && 'verdict' in row)) return false
    }
    const rows = await json(`${STATE_ROOT}/overrides.json`)
    if (rows !== undefined && (!Array.isArray(rows) || rows.length > 0)) return false
  } catch {
    return false
  }
  for (const name of RUN_ARTIFACTS) if ((await readText(io, `${specDir}/${name}`)) !== null) return false
  const entries = await io.list(specDir).catch(() => [])
  return Array.isArray(entries) && !entries.some(e => RUN_ARTIFACTS.includes(e.name))
}

// The report of the run as it stands, not kept.
export function reportText(snap: Snapshot): string {
  return renderReport({
    slug: snap.slug,
    title: snap.title,
    stage: snap.run?.stage ?? null,
    gates: snap.gates,
    skips: snap.skips,
    loops: snap.loops,
    decisions: snap.decisions,
    criteria: snap.criteria,
    usage: snap.usage,
    generatedAt: Date.now(),
  })
}

// Keeps the report (the mod writes no file: see makeIo in register.tsx) and returns its text.
export async function writeReport(io: Io, snap: Snapshot): Promise<string> {
  const md = reportText(snap)
  await io.write(REPORT_PATH, md)
  return md
}

// The report kept last in this project, for `/temper:temper report` with no run active. Null when there is none.
export async function keptReport(io: Io): Promise<string | null> {
  const text = await readText(io, REPORT_PATH)
  return text !== null && text.trim() !== '' ? text : null
}

// The line of the system prompt for a /temper:fix run, where the mod stands aside (see loadSnapshot).
export const FIX_RUN = 'Phase: a /temper:fix run. The Temper bar and its guard stand aside for it: ask every gate in the conversation, as commands/fix.md says.'

export function composeText(snap: Snapshot): string {
  if (snap.runCommand === 'fix' && snap.run === null) {
    return sectionText({ enforcement: snap.enforcement, view: null }).replace('Phase: none. No Temper run is active.', FIX_RUN)
  }
  return sectionText({ enforcement: snap.enforcement, view: snap.run === null ? null : viewOf(snap), run: snap.run, line: snap.line })
}

export const viewOf = (snap: Snapshot): View =>
  buildView({
    run: snap.run,
    title: snap.title,
    gates: snap.gates,
    skips: snap.skips,
    loops: snap.loops,
    groups: snap.groups,
    findings: snap.findings,
    criteria: snap.criteria,
    task: snap.task,
    move: snap.move,
    decisions: snap.decisions,
    enforcement: snap.enforcement,
    configSuggestions: snap.configSuggestions,
    line: snap.line,
    paneOpen: live.paneOpen ?? false,
  })

// Mirrors the run into `$.state` for drawing and compaction.
export async function publish(io: Io, snap: Snapshot): Promise<void> {
  await io.setRun({ slug: snap.slug, stage: snap.run?.stage ?? null, title: snap.title, summary: composeText(snap), view: viewOf(snap) })
  await io.setMode(snap.mode)
}

const iso = (ts: number): string => new Date(ts).toISOString()

// `/temper:temper status`: the section text plus the counts a person wants at a glance.
export function statusText(snap: Snapshot): string {
  if (snap.runCommand === 'fix' && snap.run === null) return FIX_RUN
  if (snap.run === null) return snap.line ?? 'No Temper run is active. Start one with /temper:temper <feature description>.'
  const lines = [composeText(snap)]
  lines.push(`Mode: ${snap.mode}, enforcement: ${snap.enforcement}`)
  const skipped = Object.keys(snap.skips)
  if (skipped.length > 0) lines.push(`Skipped: ${skipped.map(s => stageLabel(s as Stage)).join(', ')}`)
  for (const l of snap.loops) lines.push(`Loop ${l.from} to ${l.to}: ${l.iteration} of ${l.max}`)
  if (snap.decisions.length > 0) lines.push(`Your decisions in this run: ${snap.decisions.length} (/temper:temper timeline lists them)`)
  return lines.join('\n')
}

// `/temper:temper timeline`: the person's decisions in this run, oldest first.
export function timelineText(snap: Snapshot): string {
  if (snap.decisions.length === 0) return 'No decisions yet in this run.'
  return snap.decisions.map(d => `${iso(d.ts)}  ${describe(d)}`).join('\n')
}

