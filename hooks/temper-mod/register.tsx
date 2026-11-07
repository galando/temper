import type { CommandRunResult, EngineInterface, PluginOptions, Register } from 'claude-code'

import { FIX_RUN, VIEW_PATH, composeText, idleSnapshot, keepDecision, keptReport, live, loadSnapshot, publish, reportText, settingsFrom, spendDecision, statusText, timelineText, viewOf, writeReport } from './adapter'
import type { Io, Snapshot } from './adapter'
import { cliArgv } from './core/argv'
import { pluginCliFrom } from './core/cli'
import { HELP, parseArgs } from './core/commands'
import type { Parsed } from './core/commands'
import { parsePhaseModel, parsePhaseModels, versionAtLeast } from './core/config'
import type { UiMode } from './core/config'
import { answeredResult, answersIn } from './core/answers'
import { evaluate } from './core/rules'
import { readShell } from './core/shell'
import { evaluateSession, factsOf, featureWhy, requestOf, skillChosen } from './core/session'
import { dialogQuestions, dialogQuestionsAll, drive, driveFix, driverThrew, logRows, slugOf } from './core/driver'
import type { AgentEnd, DriveEnd, GoAgent, GoQuestion, Port } from './core/driver'
import type { RuleContext } from './core/rules'
import { SECTION_ID } from './core/section'
import { isTemperAgent, stageToast, turnLine } from './core/view'
import type { View } from './core/view'
import { hintProps } from './ui/hint'
import { renderBand } from './ui/band'
import { PANE_ID, renderPane } from './ui/pane'
import { renderQuestion } from './ui/question'
import { spinnerProps } from './ui/spinner'

type Api = EngineInterface

// Module state. A hot reload runs register() again and session.start fires again, so
// nothing here has to outlive a reload.
let options: PluginOptions = {}
let current: Promise<Snapshot> | null = null
let root = ''
// The answer and the time of each agent the run driver launched, by agent id (from turn.complete).
const agentEnds = new Map<string, AgentEnd>()
let paneOpen = false
// The person closed the pane by hand (its close mark, or /temper:temper pane): the mod does not open it for them again
// in this session; /temper:temper pane does.
let paneShut = false
// The last stage announced, so a toast goes out once per stage change and never at load.
let lastStage: string | null | undefined

// One toast. Every toast of the mod goes through here.
function showToast($: Api, text: string): void {
  $.ui.toast(text)
}

// The mod writes no file. The report it makes at Done is kept in the plugin store, under the full path it stands for
// (`vf:<path>`). Past VF_MAX kept texts the oldest is dropped, so the store (4 MiB for every project on the machine)
// never fills up.
const VF = 'vf:'
const VF_LIST = 'vflist'
const VF_MAX = 40

async function keepText($: Api, full: string, text: string): Promise<void> {
  await $.store.set(VF + full, text)
  const raw = await $.store.get(VF_LIST)
  const list = (Array.isArray(raw) ? raw.filter((p): p is string => typeof p === 'string') : []).filter(p => p !== full)
  list.push(full)
  while (list.length > VF_MAX) await $.store.delete(VF + (list.shift() as string))
  await $.store.set(VF_LIST, list)
}

// `$` is spelled only in this file, at each call site, so the adapter and the pure core
// stay free of it.
function makeIo($: Api): Io {
  // A relative path means the project the session started in, even after Claude ran `cd` in a Bash
  // call: without this the files of the run are not found and the band goes away.
  const abs = (path: string): string => (root && !path.startsWith('/') ? `${root.replace(/\/$/, '')}/${path}` : path)
  return {
    read: path => $.fs.read(abs(path)).then(t => (typeof t === 'string' ? t : null)),
    keep: (name, text) => keepText($, abs(`.temper/${name}`), text),
    kept: async name => {
      const text = await $.store.get(VF + abs(`.temper/${name}`))
      return typeof text === 'string' ? text : null
    },
    storeGet: key => $.store.get(key),
    storeSet: (key, value) => $.store.set(key, value),
    storeDelete: key => $.store.delete(key),
    version: () => $.session.version().then(v => v.version),
    setRun: async run => {
      await $.state.set({ plugin: 'temper', key: 'run' } as const, run)
    },
    setMode: async mode => {
      await $.state.set({ plugin: 'temper', key: 'mode' } as const, mode)
    },
    cli: pluginCli(),
  }
}
// The last snapshot that held a run. Enforcement is sticky: once the mod has seen a run in progress, a view.json that
// turns missing, unreadable or corrupt (chmod 000, a delete, a git clean) does not end it.
// The last known state keeps applying until the file reads again, the person turns enforcement off, or the mod reloads.
let lastRun: Snapshot | null = null

const LOST_STATE =
  'Temper state: .temper/view.json is missing or unreadable. The last known state still applies. Run temper next, which writes it again, or turn Temper enforcement off in /config.'

// The last known run, when it was in progress; null when it was over (Done) or never seen.
function heldRun(): Snapshot | null {
  const r = lastRun
  if (r === null || r.inert || r.failOpen || r.run === null || r.run.stage === 'commit') return null
  // The settings are the live ones (the person may have turned enforcement off since); the run is the last known.
  return { ...r, ...settingsFrom(options), line: LOST_STATE }
}

// Whether the folder the mod reads the run from has been seen to hold one (see load).
let rootVerified = false
// Where the session began (session.start); used to look for the CLI's root again.
let sessionCwd = ''

// A failed load never throws. With no run it is a no-run snapshot (nothing enforced); a run that was in progress
// stays enforced (see lastRun).
async function load($: Api): Promise<Snapshot> {
  // After a hot reload no session.start has run yet: the project root comes back from `$.state`.
  if (!root) root = await rememberedRoot($)
  let snap: Snapshot | null = await loadSnapshot(makeIo($), options).catch(() => null)
  if (snap !== null && snap.slug === null && !snap.inert && lastRun === null && !rootVerified && sessionCwd) {
    // No run in the folder the mod chose at the first session start. A run the CLI starts later may live in a folder
    // above it (the CLI root): look again before deciding there is none.
    const found = await locateRoot($, sessionCwd)
    if (found !== null && found !== root) {
      root = found
      await $.state.set({ plugin: 'temper', key: 'root' } as const, root).catch(() => undefined)
      snap = await loadSnapshot(makeIo($), options).catch(() => null)
    }
  }
  if (snap !== null && snap.slug !== null) {
    lastRun = snap
    rootVerified = true
    return snap
  }
  const held = heldRun()
  if (held !== null) {
    lastRun = held
    return held
  }
  lastRun = null
  return snap ?? idleSnapshot(options, false)
}

// ---- The project root ------------------------------------------------------------------------
// The folder of the project is fixed once. A session folder reported later (after Claude ran `cd` into
// the plugin folder, or another repo, and a hot reload started the session there) never replaces it:
// view.json and the report are always read and kept under the first root. `$.state` keeps it across a hot reload.

async function rememberedRoot($: Api): Promise<string> {
  const read = await $.state.get({ plugin: 'temper', key: 'root' } as const).catch(() => null)
  return typeof read?.value === 'string' ? read.value : ''
}

// The nearest folder at or above `cwd` that holds .temper/view.json; null when none does.
async function locateRoot($: Api, cwd: string): Promise<string | null> {
  let dir = cwd.replace(/\/+$/, '')
  for (let i = 0; i < 12 && dir !== ''; i++) {
    if ((await $.fs.read(`${dir}/${VIEW_PATH}`).catch(() => undefined)) !== undefined) return dir
    dir = dir.slice(0, Math.max(0, dir.lastIndexOf('/')))
  }
  return null
}

// Session start: keep the remembered root; the first time, find it and remember it.
async function settleRoot($: Api, cwd: string | undefined): Promise<void> {
  const known = await rememberedRoot($)
  if (known) {
    root = known
    return
  }
  if (!cwd) return
  // An inert mod (a version below the minimum) touches no Temper file, not even to find the root.
  const version = await $.session.version().then(v => v.version).catch(() => undefined)
  if (!versionAtLeast(version)) {
    root = cwd
    return
  }
  const found = await locateRoot($, cwd)
  root = found ?? cwd
  rootVerified = found !== null
  // No run was found: the root is the session folder for now, and a run that starts above it is looked for later (see load).
  sessionCwd = found === null ? cwd : ''
  await $.state.set({ plugin: 'temper', key: 'root' } as const, root).catch(() => undefined)
}

function ensure($: Api): Promise<Snapshot> {
  current ??= load($)
  return current
}

// One toast per stage change, in full mode, never at the first load.
function announce($: Api, snap: Snapshot): void {
  const stage = snap.run?.stage ?? null
  if (lastStage !== undefined && stage !== lastStage && stage !== null && !snap.inert) {
    const toast = snap.mode === 'full' ? stageToast(stage) : null
    if (toast) showToast($, toast)
  }
  lastStage = stage
}

// The run reached Done since the stage last announced: its report is kept, so /temper:temper report shows it after the
// run state is gone.
function reachedDone(snap: Snapshot): boolean {
  return snap.run?.stage === 'commit' && !snap.inert && snap.runCommand !== 'fix' && lastStage !== undefined && lastStage !== null && lastStage !== 'commit'
}

// Takes a snapshot as the current one. A run it holds is the last known run too.
function adopt($: Api, snap: Snapshot): Snapshot {
  current = Promise.resolve(snap)
  if (snap.slug !== null) lastRun = snap
  if (reachedDone(snap)) void writeReport(makeIo($), snap).catch(() => undefined)
  announce($, snap)
  return snap
}

async function refresh($: Api): Promise<Snapshot> {
  current = load($)
  const snap = await current
  await publish(makeIo($), snap).catch(() => undefined)
  if (reachedDone(snap)) await writeReport(makeIo($), snap).catch(() => undefined)
  const started = startedHere(snap)
  announce($, snap)
  if (started) await autoOpenPane($, snap).catch(() => undefined)
  return snap
}

// A run the mod first sees after it saw none in this session (a run started with /temper:temper,
// a door or `temper state init`): the pane opens for it as it does at a session start.
function startedHere(snap: Snapshot): boolean {
  return lastStage === null && !snap.inert && snap.run !== null && snap.run.stage !== 'commit'
}

// The session's directory, to make absolute tool paths project relative: the cwd the
// session reported, else where `.` resolves.
async function rootOf($: Api): Promise<string> {
  if (root) return root
  const stat = await $.fs.stat('.', { resolve: true }).catch(() => undefined)
  return stat?.realPath ?? ''
}

// What the drawing hooks read: the view and the live mode, from `$.state`, so a write
// to either redraws the sites that read it. Null before the mod has published.
async function readUi($: Api): Promise<{ view: View; mode: UiMode } | null> {
  const run = await $.state.get({ plugin: 'temper', key: 'run' } as const)
  const mode = await $.state.get({ plugin: 'temper', key: 'mode' } as const)
  if (!run.value || !mode.value) return null
  return { view: run.value.view, mode: mode.value }
}

// ---- Pane ------------------------------------------------------------------------

async function openPane($: Api): Promise<boolean> {
  const placed = await $.ui.open({ id: PANE_ID, title: 'Temper' })
  paneOpen = placed.isPlaced
  live.paneOpen = placed.isPlaced
  return placed.isPlaced
}

async function closePane($: Api): Promise<void> {
  await $.ui.close({ id: PANE_ID })
  paneOpen = false
  live.paneOpen = false
}

async function togglePane($: Api): Promise<string> {
  if (paneOpen) {
    paneShut = true
    await closePane($)
    return 'The Temper pane is closed.'
  }
  paneShut = false
  return (await openPane($)) ? 'The Temper pane is open.' : 'The Temper pane needs a wider terminal.'
}

// Opens the pane where the surface places it now. Where it would only wait undrawn, it is
// closed again so it does not pop up later.
async function placeOrDrop($: Api): Promise<void> {
  const placed = await $.ui.open({ id: PANE_ID, title: 'Temper' })
  if (placed.isPlaced) {
    paneOpen = true
    live.paneOpen = true
  } else {
    await $.ui.close({ id: PANE_ID })
    paneOpen = false
    live.paneOpen = false
  }
}

// Opened unasked, in full mode, for a run in progress: at a session start, and when a run
// starts later in the session (see refresh). The engine places an unasked pane only on a
// wide terminal.
async function autoOpenPane($: Api, snap: Snapshot): Promise<void> {
  if (paneOpen || paneShut || snap.mode !== 'full' || snap.run === null || snap.run.stage === 'commit') return
  await placeOrDrop($)
}

// The person's own /temper:temper with a run word (a feature description, a decision word,
// or nothing), in full mode: the pane opens as their command, which the engine places at any
// width. A run they start has no state yet; the pane draws it once the CLI writes it.
async function openForPerson($: Api): Promise<void> {
  const snap = await ensure($)
  if (paneOpen || paneShut || snap.inert || snap.mode !== 'full' || snap.runCommand === 'fix') return
  await placeOrDrop($)
}
// ---- The person's answers ---------------------------------------------------------------

// Claude asks every gate in Claude Code's own question dialog, exactly as `temper next --json` gives it (ADR 0013). The
// person's answer is read from the dialog's result, after the call ran, matched exactly against the question view.json
// holds (core/answers.ts), and kept as a decision stamped with the CLI's run and step. Claude then carries the answer
// out in the same turn; nothing is sent to Claude here. Only the result counts: it is what the dialog returned after the
// person chose.
async function recordAnswers($: Api, result: unknown): Promise<void> {
  const snap = await refresh($)
  if (snap.inert || snap.run === null || snap.view === null) return
  const io = makeIo($)
  const stage = snap.run.stage
  let kept = false
  for (const a of answersIn(result, snap.view)) {
    if (a.kind === 'gate') await keepDecision(io, snap.at, a.stage || stage, { kind: 'gate', label: a.option.label, move: a.option.move ?? '', calls: a.option.calls, steps: a.option.steps, reason: a.reason, ask: a.ask })
    else if (a.kind === 'restart') await keepDecision(io, snap.at, stage, { kind: 'restart', calls: a.option.calls, reason: '' })
    else await keepDecision(io, snap.at, stage, { kind: 'drift', path: a.path, choice: a.choice, reason: a.reason })
    kept = true
  }
  if (kept) adopt($, await refresh($))
}

// ---- The guard ---------------------------------------------------------------------------

export const MOD_CLI = pluginCliFrom((import.meta as { url?: string }).url)

function pluginCli(): string {
  return MOD_CLI
}

function ruleContext(snap: Snapshot, rootDir: string): RuleContext {
  return { run: snap.run, allowed: snap.allowed, restart: snap.restart, drift: snap.drift, root: rootDir, cli: pluginCli(), fixRun: snap.runCommand === 'fix' }
}

const GUARD_ERROR =
  'Temper: the guard hit an error while it checked this command, and a run is active. Temper does not pass a command it could not check. ' +
  'Next: run the command again. If it keeps failing, ask the user (the user can turn Temper enforcement off in /config).'

// A guard that threw: Bash is refused while a run is active (a command the guard cannot read is the one to refuse),
// every other tool passes (the mod must not make Temper worse than without it).
function failedGuard(tool: string): Guarded {
  const r = lastRun
  const active = r !== null && !r.inert && r.enforcement !== 'off' && !r.failOpen && r.run !== null
  return { deny: tool === 'Bash' && active ? GUARD_ERROR : null }
}

// The one place this module denies. A decision the call spends (an Allow once answer) is spent here, when the call is
// let through.
// `trivialExit`: the call is a `state clear` of a run that never left Intent (view.json's trivial_exit). Once it ran, the
// run it cleared is not held any more (see lastRun), so the work that follows is not judged against a run that is gone.
type Guarded = { deny: string | null; trivialExit?: boolean }

// 9.8.0: the run and step at which the person chose a skill option (Grill Me, Teach Me): until the run moves on, the
// session asks the skill's own questions (core/session.ts). Kept in the plugin store, not in module state: the engine
// loads the mod again between turns.
const SKILL = 'skill:'
// 9.8.0: what the person typed after /temper:temper, per project, kept in the plugin store (module state does not
// survive the engine loading the mod again between turns), with the conversation that typed it: only that
// conversation's state init is held to it.
const REQUEST = 'request:'
type Kept = { session: string; text: string }
const keptRequest = (v: unknown): Kept | null => {
  const k = v as Partial<Kept> | null | undefined
  return k !== null && typeof k === 'object' && typeof k.session === 'string' && typeof k.text === 'string' ? (k as Kept) : null
}

async function skillActive(io: Io, snap: Snapshot): Promise<boolean> {
  const at = await io.storeGet(SKILL + snap.at.run).catch(() => undefined)
  return typeof at === 'number' && at === snap.at.step
}

async function guard($: Api, tool: string, input: Record<string, unknown>, main = false): Promise<Guarded> {
  // A Bash call may run the CLI, so it is judged on the run as the files say now; a write on the run last read. The main
  // session's question and agent launch are judged on the view as it is now too (an agent's own calls may have moved it).
  const snap = tool === 'Bash' || (main && (tool === 'AskUserQuestion' || tool === 'Agent' || tool === 'Task')) ? await refresh($) : await ensure($)
  // Fail open: when the mod cannot tell where the run is, it never blocks Temper.
  if (snap.inert || snap.enforcement === 'off' || snap.failOpen) return { deny: null }
  const command = typeof input.command === 'string' ? input.command : ''
  // A `state clear` at Intent (the TRIVIAL exit), as view.json says now.
  const clearable = tool === 'Bash' && snap.run?.trivialExit === true && readShell(command).calls.some(w => w[0] === 'state' && w[1] === 'clear')
  const rootDir = await rootOf($)
  const rc = ruleContext(snap, rootDir)
  const r = evaluate(rc, { tool, input })
  if ('deny' in r) return { deny: r.deny }
  // The main session (no agent id) relays the CLI and the person: it runs the CLI and reads, launches the CLI's agent and
  // asks the CLI's question (core/session.ts).
  if (main) {
    const s = evaluateSession(rc, factsOf(snap.view, tool === 'AskUserQuestion' && (await skillActive(makeIo($), snap))), { tool, input })
    if ('deny' in s) return { deny: s.deny }
    // The run's request as the person typed it (kept at /temper:temper, below): a state init carries it whole.
    if (tool === 'Bash') {
      const kept = keptRequest(await makeIo($).storeGet(REQUEST + root).catch(() => undefined))
      const here = kept === null ? null : await $.session.id().catch(() => null)
      const why = featureWhy(command, kept !== null && kept.session === here ? kept.text : null)
      if (why !== null) return { deny: why }
    }
  }
  if (r.use !== undefined) {
    await spendDecision(makeIo($), r.use)
    adopt($, await refresh($))
  }
  return { deny: null, ...(clearable ? { trivialExit: true } : {}) }
}

// ---- The run driver (9.8.0, round 5) ------------------------------------------------------------
// The mod carries a /temper:temper run itself: core/driver.ts decides, these functions reach the engine. A hook's own time
// is bounded, a `$` call's is not, so the driver waits on its agents with `$` calls (a short sleep run by the host).

const WAIT_MS = 90 * 60_000

// One call of the CLI in the project: the plugin's own scripts/temper, run by its path with the call's words as its
// arguments, never through a shell (core/argv.ts). A call that is not one (another program, or a line that needs a
// shell) is not run here: it fails with exit 126, and the run goes on in the conversation. Streamed, so a long call
// (Check's suite and mutation score inside `temper go`) has no time cap; leaving the loop at the person's interrupt ends
// the child.
// At the person's interrupt the engine aborts a running child, and reading it throws ("aborted", seen in an interactive
// terminal): that is the interrupt, answered as one (exit 130), never as a failed call the conversation should take up.
async function hostRun($: Api, cwd: string, call: string, signal: AbortSignal | undefined): Promise<{ code: number; out: string }> {
  const argv = cliArgv(call, pluginCli())
  if (argv === null) return { code: 126, out: `Temper: the mod runs only the plugin's own CLI with plain arguments; this call goes to the conversation: ${call.slice(0, 200)}` }
  let out = ''
  try {
    const child = $.process.spawn({ argv, cwd })
    for await (const piece of child) {
      out += piece.text
      if (signal?.aborted === true) return { code: 130, out }
    }
    const end = await child.result
    return { code: end.code ?? 1, out }
  } catch (x) {
    if (signal?.aborted === true) return { code: 130, out }
    throw x
  }
}

// A short wait between looks at the driver's agents: a child of the host, so the hook's own time does not run.
async function hostPause($: Api, cwd: string, seconds: number, signal?: AbortSignal): Promise<void> {
  try {
    const child = $.process.spawn({ argv: ['sleep', String(seconds)], cwd })
    for await (const piece of child) void piece
  } catch (x) {
    if (signal?.aborted !== true) throw x
  }
}

async function hostSpawn($: Api, a: GoAgent): Promise<string | null> {
  const label = a.type.replace(/^temper:temper-/, '')
  const s = await $.agent.spawn({ subagentType: a.type, prompt: a.prompt, description: `Temper ${label}`, ...(a.model ? { model: a.model } : {}) })
  return 'agentId' in s && typeof s.agentId === 'string' ? s.agentId : null
}

// Waits until every agent of `ids` has ended (its turn.complete, or a status other than running), at most WAIT_MS, or
// until the person interrupts.
async function hostWait($: Api, cwd: string, ids: string[], signal: AbortSignal | undefined): Promise<Record<string, AgentEnd>> {
  const out: Record<string, AgentEnd> = {}
  if (ids.length === 0) {
    await hostPause($, cwd, 5, signal)
    return out
  }
  const start = await $.clock.now()
  while ((await $.clock.now()) - start < WAIT_MS && signal?.aborted !== true) {
    const list = await $.agent.list().catch(() => [])
    let open = 0
    for (const id of ids) {
      if (id in out) continue
      const kept = agentEnds.get(id)
      const info = list.find(x => x.id === id)
      if (kept !== undefined) out[id] = kept
      else if (info !== undefined && info.status !== 'running' && info.status !== 'pending') out[id] = { text: '', ms: null }
      else open++
    }
    if (open === 0) break
    await hostPause($, cwd, 2, signal)
  }
  // An answer that came after the status changed is the agent's own: take it when it is there now.
  for (const id of ids) {
    const kept = agentEnds.get(id)
    if (kept !== undefined) out[id] = kept
  }
  return out
}

// The question the driver is asking now: the tool.call hook below gives its dialog each option's description and preview,
// which `$.ui.ask` cannot carry.
let asking: GoQuestion | null = null

async function hostAsk($: Api, q: GoQuestion): Promise<string | null> {
  asking = q
  try {
    const a = await $.ui.ask(q.question, { options: q.options.map(o => o.label).slice(0, 4), header: q.header })
    return typeof a === 'string' && a !== '' ? a : null
  } finally {
    asking = null
  }
}

// Several questions in one dialog (the Blocking questions): `$.ui.ask` raises the first, the tool.call hook below puts
// them all in and keeps every answer. When the engine kept the first question only, the rest are asked one at a time.
let askingAll: GoQuestion[] | null = null
let allAnswers: Record<string, string> | null = null

async function hostAskAll($: Api, qs: GoQuestion[]): Promise<Array<string | null>> {
  if (qs.length <= 1) return qs.length === 0 ? [] : [await hostAsk($, qs[0]!)]
  askingAll = qs
  allAnswers = null
  let first: string | null
  try {
    const a = await $.ui.ask(qs[0]!.question, { options: qs[0]!.options.map(o => o.label).slice(0, 4), header: qs[0]!.header })
    first = typeof a === 'string' && a !== '' ? a : null
  } finally {
    askingAll = null
  }
  const got = allAnswers as Record<string, string> | null
  allAnswers = null
  if (got === null) {
    const rest: Array<string | null> = []
    for (const q of qs.slice(1)) rest.push(first === null ? null : await hostAsk($, q))
    return [first, ...rest]
  }
  return qs.map((q, i) => {
    const v = got[q.question]
    return typeof v === 'string' && v !== '' ? v : i === 0 ? first : null
  })
}

async function hostRecord($: Api, q: GoQuestion, label: string): Promise<void> {
  await recordAnswers($, { result: { questions: [{ header: q.header, question: q.question, options: q.options, multiSelect: false }], answers: { [q.question]: label } } })
}

// The run driver hands a run to the prompt based command (9.8.1): the command's event goes on unchanged, as the person
// typed it, and the hand back is one note the model reads after the command's text (its `context`), the words the page
// takes (`next`, `discuss <text>`, `chose <label>`: commands/temper.md, "Arguments"). The person's words are not rewritten.
function handBack(result: CommandRunResult, args: string): CommandRunResult {
  const note = `Temper hand back from the mod's run driver: take these as the arguments of this command in place of the ones typed: ${args}`
  return { ...result, context: [...(result.context ?? []), note] }
}

async function driveRun($: Api, cwd: string, request: string | null, signal: AbortSignal | undefined, fix = false): Promise<DriveEnd> {
  const port: Port = {
    run: call => hostRun($, cwd, call, signal),
    spawn: a => hostSpawn($, a),
    wait: ids => hostWait($, cwd, ids, signal),
    ask: q => hostAsk($, q),
    askAll: qs => hostAskAll($, qs),
    record: (q, label) => hostRecord($, q, label),
    show: async text => {
      // `$.ui.log` appends one line: the terminal draws a line break inside it as a mark and cuts the line at 2000
      // characters, so a panel or a report (many rows, thousands of characters) is logged a row at a time.
      if (text.trim() !== '') for (const row of logRows(text)) $.ui.log(row)
      adopt($, await refresh($))
    },
    stopped: () => signal?.aborted === true,
  }
  if (fix && request !== null) return driveFix(port, pluginCli(), request)
  return drive(port, pluginCli(), request, request === null ? null : slugOf(request))
}

// Whether the mod carries this /temper:temper: a request with no run active (a new run), or no words with a run of
// /temper active (taking it up again). A run word, a request while another run is active (its restart question), a
// /temper:fix run, an inert or switched off mod: the model loop of commands/temper.md, as before.
async function drives($: Api, args: string): Promise<{ request: string | null } | null> {
  const snap = await refresh($)
  if (snap.inert || snap.enforcement === 'off' || snap.failOpen || snap.runCommand === 'fix') return null
  const req = requestOf(args)
  const active = snap.slug !== null
  if (req !== null && !active) return { request: req }
  if (args.trim() === '' && active) return { request: null }
  return null
}

// ---- /temper:temper -------------------------------------------------------------------------

// Where the person changes the two settings: Claude Code's /config, the plugin's own options. The mod never writes them.
const MODE_WHERE = 'Change it in /config: Temper UI mode (full, minimal or off).'
const ENFORCEMENT_WHERE = 'Change it in /config: Temper enforcement (on or off).'

async function handleTemper($: Api, parsed: Parsed): Promise<CommandRunResult | null> {
  const snap = await ensure($)
  if (snap.inert) return null
  switch (parsed.word) {
    case 'help':
      return { text: HELP }
    case 'status':
      return { text: statusText(await refresh($)) }
    case 'timeline':
      return { text: timelineText(await refresh($)) }
    case 'report': {
      const fresh = await refresh($)
      if (fresh.slug === null || fresh.runCommand === 'fix') {
        const kept = await keptReport(makeIo($))
        return { text: kept === null ? 'No run is active. There is no report to show.' : `No run is active. The last report kept for this project:\n\n${kept}` }
      }
      // A run held from memory (its state file is gone) is shown but not kept.
      if (fresh.line === LOST_STATE) return { text: `${LOST_STATE}\n\n${reportText(fresh)}` }
      return { text: await writeReport(makeIo($), fresh) }
    }
    // The mod changes no setting: the two words say what is set and where the person changes it.
    case 'mode':
      return { text: `Temper mode: ${snap.mode}. ${MODE_WHERE}` }
    case 'enforcement':
      return { text: `Temper enforcement: ${snap.enforcement}. ${ENFORCEMENT_WHERE}` }
    case 'pane':
      if (snap.mode !== 'full') return { text: `The pane shows in full mode only. ${MODE_WHERE}` }
      return { text: await togglePane($) }
  }
}

// The Review agent and (9.7.6) the fresh reviewer of the plan run on reviewerModel when it is set.
const REVIEWERS = ['temper-review', 'temper:temper-review', 'temper-plan-review', 'temper:temper-plan-review']

// Whether each subagent seen at turn.step is the Temper review agent, by its id. The agent list is read once per id.
const reviewerIds = new Map<string, boolean>()

async function isReviewer($: Api, agentId: string): Promise<boolean> {
  const known = reviewerIds.get(agentId)
  if (known !== undefined) return known
  const agents = await $.agent.list()
  const found = agents.find(a => a.id === agentId)
  if (found === undefined) return false
  const yes = REVIEWERS.includes(found.type)
  reviewerIds.set(agentId, yes)
  return yes
}

// The model and effort a step runs with: on the main loop from the phaseModels option (keyed by stage), in the Temper
// review agent and the fresh plan reviewer from the reviewerModel option. Null leaves the step exactly as the engine built it.
async function phasePick($: Api, agentId: string | undefined): Promise<{ model?: string; effort?: 'low' | 'medium' | 'high' | 'xhigh' | 'max' } | null> {
  if (agentId !== undefined) {
    const model = typeof options.reviewerModel === 'string' ? options.reviewerModel.trim() : ''
    return model && (await isReviewer($, agentId)) ? { model } : null
  }
  const raw = options.phaseModels
  if (typeof raw !== 'string' || raw.trim() === '') return null
  const snap = await ensure($)
  if (snap.inert || snap.run === null || snap.run.stage === 'commit') return null
  const pick = parsePhaseModel(parsePhaseModels(raw)[snap.run.stage])
  return pick.model || pick.effort ? pick : null
}

// Wiring only. Every hook fails open: an exception passes the call through, except the detected violation, which is the
// one place this module denies.
export const register: Register = (on, opts) => {
  options = opts
  current = null
  root = ''
  lastRun = null
  rootVerified = false
  sessionCwd = ''
  paneOpen = false
  paneShut = false
  lastStage = undefined
  live.paneOpen = undefined
  reviewerIds.clear()

  on('session.start', async ($, e, next) => {
    await settleRoot($, e.cwd)
    current = null
    await refresh($)
      .then(snap => autoOpenPane($, snap))
      .catch(() => undefined)
    return next(e)
  })

  on('classic.SessionStart', async ($, e, next) => {
    await settleRoot($, e.cwd)
    await refresh($).catch(() => undefined)
    return next(e)
  })

  // Only the words the mod answers are handled here; anything else (a feature description, a decision word, or nothing)
  // goes on to the prompt based command unchanged.
  on('command.run', async ($, e, next) => {
    if (e.command !== 'temper' && e.command !== 'temper:temper') {
      // A door (/temper:plan "...") or another command: no request is held to it.
      if (/^temper:/.test(e.command)) await makeIo($).storeDelete(REQUEST + root).catch(() => undefined)
      // 9.8.0: /temper:fix <bug> with no run active is carried by the mod as well; what needs a model goes to fix.md.
      if (e.command === 'temper:fix' || e.command === 'fix') {
        const bug = requestOf(e.args)
        const snap = bug === null ? null : await refresh($).catch(() => null)
        if (bug !== null && snap !== null && !snap.inert && snap.enforcement !== 'off' && !snap.failOpen && snap.slug === null) {
          const end = await driveRun($, root, bug, (next as { signal?: AbortSignal }).signal, true).catch((x: unknown) => driverThrew(x, (next as { signal?: AbortSignal }).signal?.aborted === true))
          const after = await refresh($).catch(() => null)
          if (after !== null) adopt($, after)
          if (end.kind === 'done') return { text: end.text }
          if (after === null || after.slug === null) return next(e)
          $.ui.log(`Temper: the fix goes on in the conversation (${end.why}).`)
          return handBack(await next(e), end.args)
        }
      }
      return next(e)
    }
    const req = requestOf(e.args)
    if (req !== null) {
      const session = await $.session.id().catch(() => null)
      if (session !== null) await makeIo($).storeSet(REQUEST + root, { session, text: req } satisfies Kept).catch(() => undefined)
    }
    const parsed = parseArgs(e.args)
    if (parsed === null) {
      // The person's own run word, from the prompt box, opens the pane in full mode; any other origin opens nothing.
      if (e.origin?.kind === 'composer') await openForPerson($).catch(() => undefined)
      // 9.8.0 (round 5): the mod carries the run itself, with no model in the main session; what needs a model goes on
      // in the prompt based command, from the same state. Any failure hands the run to that command as well.
      const d = await drives($, e.args).catch(() => null)
      if (d !== null) {
        const end = await driveRun($, root, d.request, (next as { signal?: AbortSignal }).signal).catch((x: unknown) => driverThrew(x, (next as { signal?: AbortSignal }).signal?.aborted === true))
        const after = await refresh($).catch(() => null)
        if (after !== null) adopt($, after)
        if (end.kind === 'done') return { text: end.text }
        // No run was started: the request goes on as the person typed it, and the prompt based command starts the run.
        if (d.request !== null && (after === null || after.slug === null)) return next(e)
        $.ui.log(`Temper: the run goes on in the conversation (${end.why}).`)
        return handBack(await next(e), end.args)
      }
      return next(e)
    }
    const out = await handleTemper($, parsed).catch(() => null)
    return out ?? next(e)
  })

  // One Temper line on a generated pull request description, while a run is on and the prAttribution option is on.
  on('attribution.text', { kind: 'pr' }, async ($, e, next) => {
    const result = await next(e)
    try {
      const snap = await ensure($)
      if (snap.inert || snap.prAttribution !== 'on' || snap.slug === null) return result
      return { text: `${result.text}\n\nMade with Temper. The phases have gates. /temper:temper report shows the report.` }
    } catch {
      return result
    }
  })

  // Subagent calls arrive here too (e.agentId names the loop); they are held to the same rules as the main loop.
  on('tool.call', async ($, e, next) => {
    const main = (e as { agentId?: unknown }).agentId === undefined
    const g = await guard($, e.tool, { ...e }, main).catch(() => failedGuard(e.tool))
    if (g.deny !== null) return { deny: g.deny }
    // The driver's own question: the dialog shows what each option does (the labels alone came through `$.ui.ask`).
    const raised = (e as { questions?: unknown }).questions
    const many = e.tool === 'AskUserQuestion' && askingAll !== null ? dialogQuestionsAll(raised, askingAll) : null
    const filled = many ?? (e.tool === 'AskUserQuestion' && asking !== null ? dialogQuestions(raised, asking) : null)
    let result
    try {
      result = await next(filled === null ? e : ({ ...e, questions: filled } as typeof e))
    } finally {
      // After the TRIVIAL exit ran (or failed): the cleared run is no longer held, and the run is read again. When the
      // clear did not take effect, build-state.json is still there and the run reads back as it was.
      if (g.trivialExit) {
        lastRun = null
        await refresh($).catch(() => undefined)
      }
    }
    const errored = (result as { isError?: boolean }).isError === true
    // Every answer of the driver's dialog of several questions, for hostAskAll.
    if (many !== null && !errored) {
      const r = answeredResult(result)
      if (r !== null) allAnswers = Object.fromEntries(Object.entries(r.answers as Record<string, unknown>).filter((kv): kv is [string, string] => typeof kv[1] === 'string'))
    }
    // A command may have moved the run (the CLI), and an answer is a decision: read the run again.
    if (e.tool === 'AskUserQuestion' && !errored) {
      // A skill option chosen (Grill Me, Teach Me): its questions are the session's to ask until the run moves on.
      if (main) {
        const snap = await ensure($).catch(() => null)
        if (snap !== null && skillChosen(snap.view, result) !== null) await makeIo($).storeSet(SKILL + snap.at.run, snap.at.step).catch(() => undefined)
      }
      await recordAnswers($, result).catch(() => undefined)
    }
    else if (e.tool === 'Bash') await refresh($).catch(() => undefined)
    return result
  }).catch(($, e, next) => {
    // The engine skips a hook that throws or outruns its budget, and the tool would run unguarded. In its place: what the
    // call already settled to, else the rule of a guard that could not check (Bash refused while a run is active, every
    // other tool passes). No `$` call here: a re-entered handler may not make one.
    if (next.called) return next(e)
    const g = failedGuard(e.tool)
    return g.deny !== null ? { deny: g.deny } : next(e)
  })

  // One session scope section, last, rebuilt from the cached state on every request, so it survives /compact by
  // construction. Absent when the mod is inert: with no marker line the skills announce that enforcement is off here.
  on('prompt.compose', async ($, e, next) => {
    const result = await next(e)
    try {
      const snap = await ensure($)
      if (snap.inert) return result
      const others = result.sections.filter(s => s.id !== SECTION_ID)
      return { sections: [...others, { id: SECTION_ID, text: composeText(snap), scope: 'session' as const }] }
    } catch {
      return result
    }
  })

  // The bar: the stage timeline, and in full mode the status and details of the stage. It has no button. Off draws
  // nothing; a survey holding the band is left alone.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const ui = await readUi($).catch(() => null)
    if (ui === null) return next(e)
    const band = renderBand($.ui.resolve(e), ui.view, ui.mode, e.props.bodyColumns)
    return band ?? next(e)
  })

  // A pane closed by its own mark: forget it, so the next toggle opens it again. Closed by the
  // person, it is not opened for them again in this session.
  on('ui.close', async ($, e, next) => {
    if (e.id === PANE_ID) {
      paneOpen = false
      live.paneOpen = false
      if (e.origin?.kind === 'person') paneShut = true
    }
    return next(e)
  })

  on('ui.render', { component: 'Pane', requestId: PANE_ID }, async ($, e, next) => {
    const ui = await readUi($).catch(() => null)
    if (ui === null || ui.mode !== 'full') return next(e)
    return renderPane($.ui.resolve(e), ui.view, e.props.placement === 'inline')
  })

  on('ui.render', { component: 'Spinner' }, async ($, e, next) => {
    const ui = await readUi($).catch(() => null)
    const props = ui !== null && ui.mode === 'full' ? spinnerProps(e.props, ui.view) : null
    return props === null ? next(e) : next({ ...e, props })
  })

  // The terminal draws a dim tail after the engine's hint line; other surfaces pass.
  on('ui.render', { component: 'PromptHint' }, async ($, e, next) => {
    const ui = await readUi($).catch(() => null)
    const props = ui !== null && ui.mode === 'full' ? hintProps(e.props, ui.view, e.surface) : null
    return props === null ? next(e) : next({ ...e, props })
  })

  // A Temper agent's message, drawn in full where the engine draws one dim line naming its sender (core/view.ts,
  // isTemperAgent). Other senders, the ctrl+o transcript and the mod's off mode keep the engine's drawing.
  on('ui.render', { component: 'UserMessage' }, async ($, e, next) => {
    const p = e.props as { text: string; isExpanded: boolean; from?: { name: string } }
    const sender = p.from?.name ?? ''
    if (p.isExpanded || !isTemperAgent(sender) || p.text.trim() === '') return next(e)
    const ui = await readUi($).catch(() => null)
    if (ui !== null && ui.mode === 'off') return next(e)
    const { Box, Text } = $.ui.resolve(e)
    return (
      <Box flexDirection="column">
        <Text dimColor>{`Message from @${sender}`}</Text>
        <Text>{p.text}</Text>
      </Box>
    )
  })

  // One Temper line above the engine's dialog, which stays exactly once in the tree.
  on('ui.render', { component: 'AskUserQuestion' }, async ($, e, next) => {
    const engine = await next(e)
    const ui = await readUi($).catch(() => null)
    if (ui === null || ui.mode !== 'full') return engine
    return renderQuestion($.ui.resolve(e), ui.view, engine) ?? engine
  })

  // A line beneath the answer (stage, progress, next stage). Nothing is submitted.
  on('turn.complete', async ($, e, next) => {
    // The answer and the time of each subagent, for the run driver that waits on it (9.8.0).
    if (typeof e.agentId === 'string' && e.agentId !== '') {
      agentEnds.set(e.agentId, { text: typeof e.answer === 'string' ? e.answer : '', ms: typeof e.durationMs === 'number' ? e.durationMs : null })
      if (agentEnds.size > 200) agentEnds.delete(agentEnds.keys().next().value as string)
    }
    const result = await next(e)
    try {
      if (e.agentId !== undefined || e.reason !== 'answer') return result
      const snap = await refresh($)
      if (snap.inert || snap.mode !== 'full') return result
      const line = turnLine(viewOf(snap))
      return line ? { ...result, text: line } : result
    } catch {
      return result
    }
  })

  // Optional: a model or effort per stage (userConfig phaseModels, "build=sonnet:high"), and a model for the steps of the
  // Temper review agent (userConfig reviewerModel). Empty means the step is passed on exactly as the engine built it.
  on('turn.step', async function* ($, e, next) {
    const pick = await phasePick($, e.agentId).catch(() => null)
    return yield* next(pick ? { ...e, ...pick } : e)
  })
}
