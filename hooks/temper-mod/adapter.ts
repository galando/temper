// Adapter helpers: everything that touches Claude Code's `$` (files, store, state,
// version) so register.tsx can stay wiring only. The pure rules live in core/.
//
// Where state lives (mods-plan 3.3): phase history is append only event files under
// `.temper/specs/{slug}/events/`, one file per event, written once with a unique name.
// Verdicts and criteria status are read, never written, from `.temper/gates.json` and
// `.temper/status.json`. The folded RunState is cached in this module and mirrored to
// `$.state` so drawing and compaction see it.

import type { PluginOptions } from 'claude-code'

import { parseEnforcement, parseMaxLoops, parseOnOff, parseUiMode, readConfigValue, versionAtLeast } from './core/config'
import type { UiMode } from './core/config'
import { mergeCriteria, parseCriteria, parseStatus, parseTitle, progress } from './core/criteria'
import type { MergedCriterion } from './core/criteria'
import { encodeEvent, eventFileName, readEvents, stamp } from './core/events'
import type { Draft, Phase, TemperEvent } from './core/events'
import { stageOf } from './core/cli'
import { cliPhase, parseBuildState, parseFindings, parseGates, phaseFromStage, samePhase } from './core/gates'
import type { Finding } from './core/gates'
import { buildView } from './core/view'
import type { View } from './core/view'
import { decide, initialState, phaseLabel, reduce } from './core/machine'
import type { Command, RunState, Verdicts } from './core/machine'
import { planFileList, taskProgress, tasksLeft } from './core/planfiles'
import { renderReport } from './core/report'
import { sectionText } from './core/section'
import type { DecisionKind } from './core/bash'
import type { CommitFacts, HumanDecision } from './core/rules'
import { normalizePath } from './core/paths'
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
  // Waits ms milliseconds (the engine's clock: the mod reads no global timer).
  pause: (ms: number) => Promise<void>
  // Where the Temper script is (pluginCliFrom): the button prompts of the published view name the CLI by it.
  // Left out: the plain `scripts/temper`.
  cli?: string
}

// A choice of the person (a move) that no mirror call has recorded in the CLI yet.
export type PendingMove = { id: string; draft: Draft }

// How the mod's picture of the run compares with the CLI state (build-state.json). The CLI is the truth
// for WHERE the run is: the phase of the folded state is always derived from it. Events only say WHO decided.
export type Sync = {
  // The phase the CLI is at; null when the mod cannot tell.
  cli: Phase | 'done' | null
  // The one line shown under the bar when something does not agree; null when all is well.
  line: string | null
  // The person's move that is not mirrored yet (key 1 records it again). Reused, never recreated.
  pending: PendingMove | null
  // The mod cannot tell where the run is: it blocks nothing and writes nothing.
  failOpen: boolean
  // The CLI looks reset (it is earlier than checks that passed): phase rules do not block writes.
  looksReset: boolean
}

export const NO_SYNC: Sync = { cli: null, line: null, pending: null, failOpen: false, looksReset: false }

export type Snapshot = {
  // True below the minimum Claude Code version or when it cannot be read: nothing acts.
  inert: boolean
  sync: Sync
  enforcement: 'on' | 'off'
  mode: UiMode
  prAttribution: 'on' | 'off'
  slug: string | null
  // autonomy.enabled in .claude/temper.config.
  autonomyEnabled: boolean
  // phases.design: true in .claude/temper.config (design is switched on for medium and complex runs).
  designRequired: boolean
  // The run's complexity from build-state.json (decides whether Plan is followed by design).
  complexity: string | null
  // The CLI's next stage, as written in build-state.json (the mod's phases are coarser: design is Plan).
  cliNext: string | null
  // The run's own branch and the command that started it (build-state.json): the CLI commit gate's
  // Build checkpoint carve-out reads both.
  branch: string | null
  runCommand: string | null
  // intent.md exists in the spec folder (the commit gate then wants an intent verdict).
  hasIntent: boolean
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
  // Tasks of tasks.md that are not done; null when tasks.md has no task headings.
  tasksLeft: number | null
  unreadable: string[]
  // Check wrote config-suggestions.json in the spec folder (offers "Review config suggestions").
  configSuggestions: boolean
  // Unconsumed human decision events per kind, for the CLI decision guard.
  humanDecisions: HumanDecision[]
}

const OWN_PREFIX = 'ev:'
const USED_PREFIX = 'used:'
const STATE_ROOT = '.temper'
const REPORT_PATH = `${STATE_ROOT}/report.md`

const str = (options: PluginOptions, key: string): string | undefined => {
  const v = options[key]
  return typeof v === 'string' ? v : undefined
}

// Values changed live (`/temper:temper mode`, `/temper:temper enforcement`) win over the options of this
// load until the config change reloads the module with the new options.
export const live: { mode?: UiMode; enforcement?: 'on' | 'off'; paneExpanded?: boolean; paneOpen?: boolean } = {}

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
    sync: NO_SYNC,
    ...settingsFrom(options),
    slug: null,
    autonomyEnabled: false,
    designRequired: false,
    complexity: null,
    cliNext: null,
    branch: null,
    runCommand: null,
    hasIntent: false,
    specDir: '',
    state: initialState(parseMaxLoops('', str(options, 'fixMaxLoops'))),
    verdicts: {},
    planFiles: [],
    title: null,
    criteria: [],
    findings: [],
    task: null,
    tasksLeft: null,
    unreadable: [],
    configSuggestions: false,
    humanDecisions: [],
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
  // Every advance the person makes pays for its own mirror call (`state advance <stage>_complete`):
  // the guard checks every advance since the third review, so every one needs its event in the pool.
  // Fix has no CLI stage of its own, so a move out of Fix has nothing to mirror.
  if (ev.type === 'advance' && ev.from !== 'fix') return 'advance'
  if (ev.type === 'back') return 'back'
  return null
}

// A digest of the exact text of an event file. The store keeps it under `ev:{id}`, so trust
// follows the content, not just the name: rewriting a trusted file in place (same name,
// different text) makes it untrusted. SHA-256 where the environment has it, else FNV-1a.
export async function digestText(text: string): Promise<string> {
  try {
    const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text))
    return 'sha256:' + [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('')
  } catch {
    let h = 0x811c9dc5
    for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 0x01000193) >>> 0
    return 'fnv:' + h.toString(16)
  }
}

async function isOwn(io: Io, id: string, text: string): Promise<boolean> {
  try {
    return (await io.storeGet(OWN_PREFIX + id)) === (await digestText(text))
  } catch {
    return false
  }
}

// Event names are `{ts}-{session}-{seq}.json`. This module has no session id call, so a
// random id per load stands in: two loads never share a name.
const SESSION = (Math.random().toString(16).slice(2) + '00000000').slice(0, 8)
// The phase an event decided, so a CLI call is matched only to a decision made for it.
function decisionOf(ev: TemperEvent, kind: DecisionKind): HumanDecision {
  // The CLI names Fix by its Check stage, as the follow up command does.
  if (ev.type === 'override') return { id: ev.id, kind, phase: stageOf(ev.phase) }
  if (ev.type === 'back') return { id: ev.id, kind, phase: stageOf(ev.to) }
  if (ev.type === 'accept') return { id: ev.id, kind, phase: 'review', findingId: ev.findingId }
  if (ev.type === 'advance') return { id: ev.id, kind, phase: ev.from }
  return { id: ev.id, kind }
}

const FLOW_ORDER: readonly Phase[] = ['intent', 'plan', 'build', 'review', 'check']

// Makes the phase the CLI's. The events say who decided what; they never say where the run is. When
// the mod's phase and the CLI's differ, the CLI wins, for the display and for every deny:
//  - the person's last move is not mirrored yet: the CLI phase stays, one line says so, key 1 records it;
//  - the CLI moved ahead of the events (the orchestrator advanced it): follow it, write nothing;
//  - the CLI name is not one the mod knows: fail open, say so, block nothing;
//  - the CLI looks reset (earlier than a check that passed): do not block work those checks passed.
export function reconcile(state: RunState, nextStage: string | null, pending: PendingMove | null): { state: RunState; sync: Sync } {
  if (!state.started) return { state, sync: NO_SYNC }
  const cli = cliPhase(nextStage)
  if (cli === null) {
    return {
      state,
      sync: { cli: null, line: 'Temper state: the mod cannot tell where the run is. It does not block anything until the state can be read.', pending: null, failOpen: true, looksReset: false },
    }
  }
  let next = state
  let line: string | null = null
  let held: PendingMove | null = null
  let behind = false
  if (!samePhase(state.phase, cli)) {
    const ahead = state.phase === null ? -1 : state.phase === 'done' ? 5 : state.phase === 'fix' ? 4 : FLOW_ORDER.indexOf(state.phase)
    const at = cli === 'done' ? 5 : cli === 'fix' ? 4 : FLOW_ORDER.indexOf(cli)
    // The CLI is earlier than the person's own choices, with nothing waiting to be mirrored and no skip
    // that the orchestrator has yet to advance past: nobody asked for that. It looks reset.
    // Design is part of Plan in the mod: the person approved the plan, and the CLI is at its design stage.
    // That is the run going on (found live), not a reset.
    const designing = nextStage === 'design' && state.phase === 'build'
    behind = at >= 0 && ahead > at && pending === null && !designing && state.history[state.history.length - 1]?.kind !== 'override'
    next = { ...state, phase: cli, since: { ...state.since, ...(cli !== 'done' && state.since[cli] === undefined ? { [cli]: 0 } : {}) } }
    next.loopLimitReached = false
    if (pending !== null) {
      held = pending
      line = `Temper state: the run is at ${phaseLabel(cli)}. Your last choice is not recorded yet. Press 1 to record it.`
    }
  }
  // A check that passed later than the phase the CLI is at, or choices that went further than the CLI
  // says with nothing pending: the CLI state looks reset.
  let looksReset = behind
  if (cli !== 'done' && cli !== 'fix') {
    const at = FLOW_ORDER.indexOf(cli)
    looksReset = looksReset || (at >= 0 && FLOW_ORDER.some((p, i) => i > at && next.gate[p] === 'fresh'))
  }
  if (looksReset && line === null) line = `Temper state looks reset: the run is at ${phaseLabel(cli)}, but it went further before. Temper does not block work that already passed.`
  return { state: next, sync: { cli, line, pending: held, failOpen: false, looksReset } }
}

const BOOTSTRAP = { ts: 0, session: 'bootstrap', seq: 1 }
let seq = 0

export async function loadSnapshot(io: Io, options: PluginOptions): Promise<Snapshot> {
  const version = await io.version().catch(() => undefined)
  if (!versionAtLeast(version)) return idleSnapshot(options, true)

  const cfg = settingsFrom(options)
  const configText = (await readText(io, '.claude/temper.config')) ?? ''
  const maxLoops = parseMaxLoops(configText, str(options, 'fixMaxLoops'))
  const autonomyEnabled = readConfigValue(configText, 'autonomy.enabled') === 'true'
  const designRequired = readConfigValue(configText, 'phases.design') === 'true'
  const statePath = `${STATE_ROOT}/build-state.json`
  let raw = await readText(io, statePath)
  let bs = parseBuildState(raw ?? '')
  // The CLI rewrites build-state.json in place, so a read in that instant sees an empty or cut file (found live: the
  // bar said "No Temper run is active" at Done). A file that exists but does not read as a run is read again
  // before the mod decides there is no run. A file that is missing is a run that ended.
  for (let i = 0; i < 4 && bs === null && raw !== null; i++) {
    await io.pause(60).catch(() => undefined)
    raw = await readText(io, statePath)
    bs = parseBuildState(raw ?? '')
  }
  if (!bs) return { ...idleSnapshot(options, false), state: initialState(maxLoops) }

  const specDir = bs.specPath
  const verdicts = parseGates((await readText(io, `${STATE_ROOT}/gates.json`)) ?? '')
  const intentText = (await readText(io, `${specDir}/intent.md`)) ?? ''
  const title = parseTitle(intentText) ?? bs.spec

  const own = new Set<string>()
  const fold = (events: readonly TemperEvent[]) => reduce(events, verdicts, { maxLoops, isTrusted: ev => own.has(ev.id) })

  const files = await readEventFiles(io, `${specDir}/events`)
  const textOf = new Map(files.map(f => [f.name, f.text]))
  const read = readEvents(files)
  const unreadable = read.unreadable
  let events = read.events
  // One store key per event id: an event file whose id is not here was not written by
  // this mod, so it is unverified and never counts as an approval.
  for (const ev of events) if (await isOwn(io, ev.id, textOf.get(eventFileName(ev)) ?? '')) own.add(ev.id)
  let state = fold(events)

  // A run the CLI began before the mod saw it: enter it once, at the phase the CLI
  // recorded. The start event is written by the mod itself, so it is a trusted record.
  // The bootstrap start has one fixed name (ts 0, session "bootstrap", seq 1), so entering a run
  // again overwrites that file instead of adding another: a lost or unwritable store cannot pile
  // up start files, and a planted or edited file under that name is replaced with a genuine one.
  // A next_stage the CLI does not use gives no phase to start at: nothing is guessed (never Intent).
  if (!state.started) {
    const phase = cliPhase(bs.nextStage)
    if (phase !== null && phase !== 'done') {
      const start = await writeEvent(io, specDir, { type: 'start', slug: bs.spec, title, phase, origin: 'system' }, BOOTSTRAP)
      events = [...events.filter(e => e.id !== start.id), start]
      own.add(start.id)
      state = fold(events)
    }
  }

  const planText = (await readText(io, `${specDir}/plan.md`)) ?? ''
  const tasksText = (await readText(io, `${specDir}/tasks.md`)) ?? ''
  const status = parseStatus((await readText(io, `${STATE_ROOT}/status.json`)) ?? '')

  // A decision belongs to the plan it approved: when the run later goes back to that stage or an earlier one (a step
  // back the mod trusts), a decision for that stage that was never spent is stale. It is not an approval for the
  // plan that is made again.
  let open: Array<{ hd: HumanDecision; ev: TemperEvent; stage: number; stalable: boolean }> = []
  for (const ev of events) {
    if (ev.type === 'back' && own.has(ev.id)) {
      const t = FLOW_ORDER.indexOf(ev.to === 'fix' ? 'check' : ev.to)
      open = open.filter(o => !o.stalable || o.stage < t)
    }
    const kind = humanKind(ev)
    if (kind && own.has(ev.id) && !(await io.storeGet(USED_PREFIX + ev.id))) {
      const stage = ev.type === 'advance' ? ev.from : ev.type === 'override' ? ev.phase : ev.type === 'accept' ? 'review' : null
      open.push({ hd: decisionOf(ev, kind), ev, stage: stage === null ? -1 : FLOW_ORDER.indexOf(stage === 'fix' ? 'check' : stage), stalable: kind !== 'back' })
    }
  }
  const humanDecisions: HumanDecision[] = open.map(o => o.hd)
  // A move of the person that no mirror call has recorded yet: the latest one is the one to record.
  let pendingMove: PendingMove | null = null
  for (const o of open) if (o.ev.type === 'advance' || o.ev.type === 'back' || o.ev.type === 'override') pendingMove = { id: o.ev.id, draft: o.ev }

  const sync = reconcile(state, bs.nextStage, pendingMove)
  state = sync.state

  return {
    inert: false,
    sync: sync.sync,
    ...cfg,
    slug: bs.spec,
    autonomyEnabled,
    designRequired,
    complexity: bs.complexity,
    cliNext: bs.nextStage,
    branch: bs.branch,
    runCommand: bs.command,
    hasIntent: intentText !== '',
    specDir,
    state,
    verdicts,
    planFiles: planFileList(planText, tasksText),
    title,
    criteria: mergeCriteria(parseCriteria(intentText), status),
    findings: parseFindings((await readText(io, `${STATE_ROOT}/evidence/review.json`)) ?? ''),
    task: taskProgress(tasksText, bs.task),
    tasksLeft: tasksLeft(tasksText),
    unreadable: unreadable.map(u => u.name),
    configSuggestions: (await io.list(specDir).catch(() => [])).some(e => e.kind === 'file' && e.name === 'config-suggestions.json'),
    humanDecisions,
  }
}

// The CLI gate wants a design verdict (PASS, or a person's override of design) exactly when the spec has a design.md
// (scripts/temper gate_commit, the checkpoint carve-out). Without a design.md nothing is asked.
async function designSatisfied(io: Io, snap: Snapshot): Promise<boolean> {
  if ((await readText(io, `${snap.specDir}/design.md`)) === null) return true
  try {
    const gates = JSON.parse((await readText(io, `${STATE_ROOT}/gates.json`)) ?? '{}') as { design?: { verdict?: unknown } }
    if (gates.design?.verdict === 'PASS') return true
  } catch {
    // an unreadable gates.json holds no verdict
  }
  try {
    const rows = JSON.parse((await readText(io, `${STATE_ROOT}/overrides.json`)) ?? '[]') as unknown
    return Array.isArray(rows) && rows.some(r => typeof r === 'object' && r !== null && (r as { stage?: unknown }).stage === 'design')
  } catch {
    return false
  }
}

// The spec files a run writes once it has an intent; a run that holds one of them has something to lose.
const RUN_ARTIFACTS = ['intent.md', 'plan.md', 'tasks.md', 'design.md']

// The TRIVIAL exit of the orchestrator: a `state clear` of a run that never left Intent. Read fresh for the call, so a
// file written a moment ago counts. True only when the CLI's files and the spec folder all say so:
//  - build-state.json: Intent is next, and its stage shows no completed step (`state init` writes `started`);
//  - gates.json holds no verdict, and overrides.json is an empty list (each may also be missing);
//  - the spec folder holds none of intent.md, plan.md, tasks.md and design.md, as a text or as a name in its listing.
// A gates.json or overrides.json that does not read counts as missing (the guard refuses a command that removes or locks
// either while a run is active); one that reads but is not what the CLI writes keeps the run. The mod's own record is
// checked by the rule (core/rules.ts).
export async function nothingToLose(io: Io, specDir: string): Promise<boolean> {
  // The parsed text of a file, or undefined when it does not read.
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
  // A spec folder that is not there yet (the TRIVIAL run wrote nothing) lists as empty.
  const entries = await io.list(specDir).catch(() => [])
  return Array.isArray(entries) && !entries.some(e => RUN_ARTIFACTS.includes(e.name))
}

// The facts of the CLI commit gate that the mod can read (see CommitFacts in core/rules.ts). `root` is the
// project folder; the current branch comes from .git/HEAD. Never throws: a fact that cannot be read is false.
export async function commitFacts(io: Io, snap: Snapshot, root: string, staged: { all: boolean; paths: string[] }): Promise<CommitFacts> {
  // Compared as the CLI gate compares (a case sensitive grep for ^.temper/specs/): `.TEMPER/SPECS` is not it.
  const specs = !staged.all && staged.paths.length > 0 && staged.paths.every(p => normalizePath(p, root).startsWith('.temper/specs/'))
  const dir = root.replace(/\/$/, '')
  const head = (await readText(io, `${dir}/.git/HEAD`)) ?? ''
  const cur = /^ref:\s*refs\/heads\/(.+?)\s*$/.exec(head)?.[1] ?? null
  const s = snap.state
  const satisfied = (p: 'intent' | 'plan') => snap.verdicts[p]?.verdict === 'PASS' || s.overrides.some(o => o.phase === p)
  let checkpoint = false
  let hint: string | undefined
  if (snap.sync.cli === 'build' && snap.runCommand === 'temper' && snap.branch !== null) {
    if (cur !== snap.branch) {
      hint = `A Build checkpoint commit needs the run's branch ${snap.branch}, and you are on ${cur ?? 'no branch'}.`
    } else if (satisfied('plan') && (!snap.hasIntent || satisfied('intent')) && (await designSatisfied(io, snap))) {
      let rows: unknown = []
      try {
        rows = JSON.parse((await readText(io, `${STATE_ROOT}/evidence/build.json`)) ?? '[]')
      } catch {
        rows = []
      }
      const hits = (Array.isArray(rows) ? rows : []).filter(r => typeof r === 'object' && r !== null && (r as { phase?: unknown }).phase === 'green' && String((r as { claim?: unknown }).claim ?? '').toLowerCase().includes('test'))
      const last = hits[hits.length - 1] as { exit_code?: unknown } | undefined
      checkpoint = last !== undefined && Number(last.exit_code) === 0
      if (!checkpoint) hint = 'A Build checkpoint commit needs a green test run on record.'
    }
  }
  return { stagedSpecsOnly: specs, checkpoint, ...(hint ? { hint } : {}) }
}

// Writes one event file, once, under a unique name, and records a digest of its text in
// `$.store` (one key per id) so a later load can tell its own events from files it did not
// write, or from one that was rewritten afterwards.
export async function writeEvent(io: Io, specDir: string, draft: Draft, fixed?: { ts: number; session: string; seq: number }): Promise<TemperEvent> {
  seq += 1
  const ev = stamp(draft, fixed ?? { ts: Date.now(), session: SESSION, seq })
  const text = encodeEvent(ev)
  await io.write(`${specDir}/events/${eventFileName(ev)}`, text)
  await io.storeSet(OWN_PREFIX + ev.id, await digestText(text))
  return ev
}

// The CLI's own files that a decision call changes (the state, the overrides, the ledger, the verdicts), as one text.
// A call that ends in an error may still have done its work (`state advance ...; exit 1`): when this text differs
// from the one taken before the call, the decision was used.
export async function runFingerprint(io: Io): Promise<string> {
  const parts: string[] = []
  for (const name of ['build-state.json', 'overrides.json', 'gates.json', 'feedback-loops.json']) parts.push(`${name}:${(await readText(io, `${STATE_ROOT}/${name}`)) ?? '-'}`)
  const entries = await io.list(`${STATE_ROOT}/evidence`).catch(() => [])
  for (const e of entries.filter(x => x.kind === 'file').sort((a, b) => a.name.localeCompare(b.name))) parts.push(`evidence/${e.name}:${(await readText(io, `${STATE_ROOT}/evidence/${e.name}`)) ?? '-'}`)
  return parts.join('\n')
}

// Marks one human event as matched by a CLI call, so it authorizes that call only once.
export async function consumeDecision(io: Io, eventId: string): Promise<void> {
  await io.storeSet(USED_PREFIX + eventId, 1)
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

// Keeps the report (the mod writes no file: see makeIo) and returns its text.
export async function writeReport(io: Io, snap: Snapshot): Promise<string> {
  const md = renderReport({
    state: snap.state,
    criteria: snap.criteria,
    generatedAt: Date.now(),
    unreadable: snap.unreadable,
  })
  await io.write(REPORT_PATH, md)
  return md
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
    sync: snap.sync.line,
    actionContext: {
      ready: s.phase !== null && s.phase !== 'done' ? s.gate[s.phase] === 'fresh' : false,
      allChecksPass: s.gate.check === 'fresh',
      hasFindings: snap.findings.length > 0,
    },
  })
}

export const viewOf = (snap: Snapshot, cli?: string): View =>
  buildView({ state: snap.state, title: snap.title, criteria: snap.criteria, findings: snap.findings, task: snap.task, tasksLeft: snap.tasksLeft, sync: snap.sync.line, pending: snap.sync.pending !== null, enforcement: snap.enforcement, configSuggestions: snap.configSuggestions, expanded: live.paneExpanded ?? false, paneOpen: live.paneOpen ?? false, ...(cli !== undefined ? { cli } : {}) })

// Mirrors the folded state into `$.state` for drawing and compaction.
export async function publish(io: Io, snap: Snapshot): Promise<void> {
  await io.setRun({ slug: snap.slug, phase: snap.state.phase, title: snap.title, summary: composeText(snap), view: viewOf(snap, io.cli) })
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

// `/temper:temper status`: the section text plus the counts a person wants at a glance.
export function statusText(snap: Snapshot): string {
  if (snap.state.phase === null) return 'No Temper run is active. Start one with /temper:temper <feature description>.'
  const s = snap.state
  const lines = [composeText(snap)]
  lines.push(`Mode: ${snap.mode}, enforcement: ${snap.enforcement}`)
  if (s.loops > 0) lines.push(`Check to Fix loops: ${s.loops} (limit ${s.maxLoops})`)
  if (s.overrides.length > 0) lines.push(`Overrides: ${s.overrides.length}`)
  if (s.accepted.length > 0) lines.push(`Accepted findings: ${s.accepted.length}`)
  if (s.drift.length > 0) lines.push(`Scope drift decisions: ${s.drift.length}`)
  if (s.unverified.length > 0) lines.push(`Event files that Temper does not trust: ${s.unverified.length}`)
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
