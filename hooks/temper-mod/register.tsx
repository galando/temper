import type { CommandRunResult, EngineInterface, PluginOptions, Register } from 'claude-code'

import { FIX_RUN, VIEW_PATH, composeText, idleSnapshot, keepDecision, keptReport, live, loadSnapshot, publish, reportText, settingsFrom, spendDecision, statusText, timelineText, viewOf, writeReport } from './adapter'
import type { Io, Snapshot } from './adapter'
import { pluginCliFrom } from './core/cli'
import { HELP, NEEDS_PERSON, parseArgs } from './core/commands'
import type { Parsed } from './core/commands'
import { parsePhaseModel, parsePhaseModels, parseUiMode, versionAtLeast } from './core/config'
import type { UiMode } from './core/config'
import { answersIn } from './core/answers'
import { evaluate } from './core/rules'
import { readShell } from './core/shell'
import type { RuleContext } from './core/rules'
import { SECTION_ID } from './core/section'
import { stageToast, turnLine } from './core/view'
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
// Whether a person is at the prompt (session.start says so); the first run question is
// never asked without one.
let interactive = false
let paneOpen = false
// The last stage announced, so a toast goes out once per stage change and never at load.
let lastStage: string | null | undefined

const MODE_LABELS: Array<[UiMode, string]> = [
  ['full', 'Full: the bar with every detail, and the pane'],
  ['minimal', 'Minimal: the stages only'],
  ['off', 'Off: show nothing'],
]

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
  'Temper state: .temper/view.json is missing or unreadable. The last known state still applies. Run temper next, which writes it again, or turn enforcement off with /temper:temper enforcement off.'

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
  announce($, snap)
  return snap
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
// Whether Claude is working, as the band and the hint last saw it: Go on waits while it is.
let working = false

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
    await closePane($)
    return 'The Temper pane is closed.'
  }
  return (await openPane($)) ? 'The Temper pane is open.' : 'The Temper pane needs a wider terminal.'
}

// Opened unasked (a session start): only where it would dock. Where it would only wait
// undrawn, it is closed again so it does not pop up later.
async function autoOpenPane($: Api, snap: Snapshot): Promise<void> {
  if (snap.mode !== 'full' || snap.run === null || snap.run.stage === 'commit') return
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
// ---- Modes (config rows) ------------------------------------------------------------

type RowKey = 'temper.uiMode' | 'temper.enforcement'

// Changes one of the mod's config rows the way the person changing it in /config does:
// refused when an administrator locked it, else written (and the module reloads with the
// new option). Returns the refusal text, or null when it took.
async function setRow($: Api, key: RowKey, label: string, value: string): Promise<string | null> {
  const rows = await $.config.list()
  const row = rows.find(r => r.key === key)
  if (row?.isLocked) return `Your organization set Temper's ${label} to ${String(row.value)}. Ask your admin to change it.`
  // Each key is written as fixed text, so a reader (and the plugin directory) sees which setting changes.
  const result = key === 'temper.uiMode' ? await $.config.set({ key: 'temper.uiMode', value: value }) : await $.config.set({ key: 'temper.enforcement', value: value })
  return result.deny ?? null
}

async function switchMode($: Api, mode: UiMode): Promise<string> {
  const refused = await setRow($, 'temper.uiMode', 'mode', mode)
  if (refused) return refused
  live.mode = mode
  if (mode !== 'full' && paneOpen) await closePane($)
  await refresh($)
  $.ui.invalidate('ui.render')
  return `Temper mode: ${mode}`
}

async function switchEnforcement($: Api, value: 'on' | 'off'): Promise<string> {
  const refused = await setRow($, 'temper.enforcement', 'enforcement', value)
  if (refused) return refused
  live.enforcement = value
  await refresh($)
  $.ui.invalidate('ui.render')
  showToast($, `Temper enforcement: ${value}`)
  return `Temper enforcement: ${value}`
}

// Asks the person for a mode: the first interactive run (once, remembered in the store),
// or `/temper:temper mode` with no argument. Dismissed means full.
async function askMode($: Api): Promise<string> {
  let picked: UiMode | null = null
  try {
    const answer = await $.ui.ask('How much do you want Temper to show?', { options: MODE_LABELS.map(([, label]) => label), header: 'Temper mode' })
    picked = MODE_LABELS.find(([mode, label]) => answer === label || answer.trim().toLowerCase().startsWith(mode))?.[0] ?? null
  } catch {
    picked = null
  }
  if (picked === null) {
    live.mode = 'full'
    await refresh($)
    showToast($, 'Temper mode is full.')
    return 'Temper mode: full'
  }
  return switchMode($, picked)
}

// Records that the mode question needs no first run ask. An explicit choice always counts; a
// bare /temper:temper mode counts only where the question can be asked (never in a `-p` run, whose
// store is the same machine wide one).
async function markModeAsked($: Api, isExplicit: boolean): Promise<void> {
  if (isExplicit || interactive) await $.store.set('modeAsked', 1)
}

async function firstRunAsk($: Api): Promise<void> {
  if (!interactive) return
  if (await $.store.get('modeAsked')) return
  await $.store.set('modeAsked', 1)
  await askMode($)
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
    if (a.kind === 'gate') await keepDecision(io, snap.at, a.stage || stage, { kind: 'gate', label: a.option.label, move: a.option.move ?? '', calls: a.option.calls, steps: a.option.steps, reason: a.reason })
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
  'Next: run the command again. If it keeps failing, ask the user (the user can turn enforcement off with /temper:temper enforcement off).'

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

async function guard($: Api, tool: string, input: Record<string, unknown>): Promise<Guarded> {
  // A Bash call may run the CLI, so it is judged on the run as the files say now; a write on the run last read.
  const snap = tool === 'Bash' ? await refresh($) : await ensure($)
  // Fail open: when the mod cannot tell where the run is, it never blocks Temper.
  if (snap.inert || snap.enforcement === 'off' || snap.failOpen) return { deny: null }
  const command = typeof input.command === 'string' ? input.command : ''
  // A `state clear` at Intent (the TRIVIAL exit), as view.json says now.
  const clearable = tool === 'Bash' && snap.run?.trivialExit === true && readShell(command).calls.some(w => w[0] === 'state' && w[1] === 'clear')
  const rootDir = await rootOf($)
  const r = evaluate(ruleContext(snap, rootDir), { tool, input })
  if ('deny' in r) return { deny: r.deny }
  if (r.use !== undefined) {
    await spendDecision(makeIo($), r.use)
    adopt($, await refresh($))
  }
  return { deny: null, ...(clearable ? { trivialExit: true } : {}) }
}

// ---- /temper:temper -------------------------------------------------------------------------

async function handleTemper($: Api, parsed: Parsed, originKind: string): Promise<CommandRunResult | null> {
  const snap = await ensure($)
  if (snap.inert) return null
  // A change of what Temper shows or enforces is the person's own, from the prompt box. The words that only show
  // something stay open to any origin.
  const changes = (parsed.word === 'mode' || parsed.word === 'enforcement') && parsed.rest.trim() !== ''
  if (changes && originKind !== 'composer') return { text: NEEDS_PERSON }
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
    case 'mode': {
      const wanted = parsed.rest.trim().toLowerCase()
      if (wanted === '') return { text: interactive ? await askMode($) : `Temper mode: ${snap.mode}` }
      if (wanted !== 'full' && wanted !== 'minimal' && wanted !== 'off') return { text: 'Usage: /temper:temper mode <full|minimal|off>' }
      return { text: await switchMode($, parseUiMode(wanted)) }
    }
    case 'enforcement': {
      const wanted = parsed.rest.trim().toLowerCase()
      if (wanted === '') return { text: `Temper enforcement: ${snap.enforcement}` }
      if (wanted !== 'on' && wanted !== 'off') return { text: 'Usage: /temper:temper enforcement <on|off>' }
      return { text: await switchEnforcement($, wanted) }
    }
    case 'pane':
      if (snap.mode !== 'full') return { text: 'The pane shows in full mode only. Use /temper:temper mode full.' }
      return { text: await togglePane($) }
  }
}

// The band's Go on: the orchestrator's own Resume, `/temper:temper` with no words. Claude reads where the run is and
// asks the gate question again. It decides nothing. `prompt.submit` refuses a text that starts with a slash, so the
// command is run as a command.
async function goOn($: Api): Promise<void> {
  if (working) {
    showToast($, 'Claude is working. Wait for the answer.')
    return
  }
  await $.command.run({ command: 'temper:temper', args: '' }).then(
    () => undefined,
    () => undefined,
  )
}

const REVIEWERS = ['temper-review', 'temper:temper-review']

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
// review agent from the reviewerModel option. Null leaves the step exactly as the engine built it.
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
  interactive = false
  paneOpen = false
  lastStage = undefined
  working = false
  live.mode = undefined
  live.enforcement = undefined
  live.paneOpen = undefined
  reviewerIds.clear()

  on('session.start', async ($, e, next) => {
    await settleRoot($, e.cwd)
    current = null
    interactive = e.isInteractive
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
    if (e.command !== 'temper' && e.command !== 'temper:temper') return next(e)
    const parsed = parseArgs(e.args)
    // Only the person's own composer counts here: a command from any other origin never marks the question answered and
    // never opens the dialog. /temper:temper mode handles the question itself.
    if (e.origin?.kind === 'composer') {
      if (parsed?.word === 'mode') await markModeAsked($, parsed.rest.trim() !== '').catch(() => undefined)
      else await firstRunAsk($).catch(() => undefined)
    }
    if (parsed === null) return next(e)
    const out = await handleTemper($, parsed, e.origin?.kind ?? '').catch(() => null)
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
    const g = await guard($, e.tool, { ...e }).catch(() => failedGuard(e.tool))
    if (g.deny !== null) return { deny: g.deny }
    let result
    try {
      result = await next(e)
    } finally {
      // After the TRIVIAL exit ran (or failed): the cleared run is no longer held, and the run is read again. When the
      // clear did not take effect, build-state.json is still there and the run reads back as it was.
      if (g.trivialExit) {
        lastRun = null
        await refresh($).catch(() => undefined)
      }
    }
    const errored = (result as { isError?: boolean }).isError === true
    // A command may have moved the run (the CLI), and an answer is a decision: read the run again.
    if (e.tool === 'AskUserQuestion' && !errored) await recordAnswers($, result).catch(() => undefined)
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

  // The bar: the stage timeline, and in full mode the status and details of the stage and the Go on button. Off draws
  // nothing; a survey holding the band is left alone.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const ui = await readUi($).catch(() => null)
    if (ui === null) return next(e)
    const band = renderBand(
      $.ui.resolve(e),
      ui.view,
      ui.mode,
      { goOn: () => goOn($).catch(() => undefined) },
      e.props.bodyColumns,
      e.props.isWorking,
    )
    working = e.props.isWorking
    return band ?? next(e)
  })

  // A pane closed by its own mark: forget it, so the next toggle opens it again.
  on('ui.close', async ($, e, next) => {
    if (e.id === PANE_ID) {
      paneOpen = false
      live.paneOpen = false
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
    working = e.props.isWorking
    return props === null ? next(e) : next({ ...e, props })
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
