import type { CommandRunResult, EngineInterface, PluginOptions, Register } from 'claude-code'

import { apply, composeText, consumeDecision, idleSnapshot, live, loadSnapshot, publish, statusText, syncCheck, timelineText, writeReport } from './adapter'
import type { Io, Snapshot } from './adapter'
import { findingActions } from './core/actions'
import type { Action } from './core/actions'
import { classifyBash } from './core/bash'
import { HELP, followUp, parseArgs, planCommand } from './core/commands'
import type { Bare, Parsed } from './core/commands'
import { parseOnOff, parsePhaseModel, parsePhaseModels, parseUiMode } from './core/config'
import type { UiMode } from './core/config'
import type { Draft } from './core/events'
import { ONLY_USER, phaseLabel } from './core/machine'
import type { Command } from './core/machine'
import { evaluate } from './core/rules'
import type { RuleContext } from './core/rules'
import { SECTION_ID } from './core/section'
import { suggestion, transitionToast, turnLine } from './core/view'
import type { View } from './core/view'
import { hintProps } from './ui/hint'
import { renderBand } from './ui/band'
import { PANE_ID, renderPane } from './ui/pane'
import { REASON_HINT } from './ui/band'
import type { GameButton } from './ui/band'
import { REASON_KEY } from './ui/kit'
import { renderQuestion } from './ui/question'
import { spinnerProps } from './ui/spinner'

type Api = EngineInterface

// Module state. A hot reload runs register() again and session.start fires again, so
// nothing here has to outlive a reload.
let options: PluginOptions = {}
let current: Promise<Snapshot> | null = null
let root = ''
// The out of plan path a scope drift choice is waiting on (set when a write is denied).
let pendingDrift: string | null = null
// Whether a person is at the prompt (session.start says so); the first run question is
// never asked without one.
let interactive = false
let paneOpen = false
// The last phase announced, so a toast goes out once per transition and never at load.
let lastPhase: string | null | undefined
// The game: whether its pane is open, the best score, and a banner Temper hands to it.
const GAME_ID = 'temper-game'
let gameOpen = false
let gameBest = 0
let gameSeed = 1
let gameBanner: { text: string; until: number } | null = null
// What the Start Button says: Start before the first game, Again after a game over.
let gameStatus: 'ready' | 'running' | 'over' = 'ready'
// The two lines the person reads when the game opens. The second is for a pane that did not get the keys.
const GAME_KEYS_TEXT = 'The game is open. Press s to start, w to jump, q or Esc to leave.'
const GAME_FOCUS_TEXT = 'The game is open. Press Ctrl+X, then Tab, to give it the keys. Then press s to start, w to jump, q or Esc to leave.'
// Where the session draws (session.start says so); the game needs the terminal or the desktop app.
let drawSurface: string | null = null

const MODE_LABELS: Array<[UiMode, string]> = [
  ['full', 'Full: bar, buttons and pane'],
  ['minimal', 'Minimal: phases only'],
  ['off', 'Off: show nothing'],
]

// `$` is spelled only in this file, as `$.noun.method(...)` at each call site, so the
// adapter and the pure core stay free of it.
function makeIo($: Api): Io {
  return {
    read: path => $.fs.read(path).then(t => (typeof t === 'string' ? t : null)),
    list: path => $.fs.list(path),
    write: (path, text) => $.fs.write(path, text),
    storeGet: key => $.store.get(key),
    storeSet: (key, value) => $.store.set(key, value),
    version: () => $.session.version().then(v => v.version),
    setRun: async run => {
      await $.state.set({ plugin: 'temper', key: 'run' } as const, run)
    },
    setMode: async mode => {
      await $.state.set({ plugin: 'temper', key: 'mode' } as const, mode)
    },
  }
}

// A failed load is a no-run snapshot (nothing enforced), never a thrown error.
function load($: Api): Promise<Snapshot> {
  return loadSnapshot(makeIo($), options).catch(() => idleSnapshot(options, false))
}

function ensure($: Api): Promise<Snapshot> {
  current ??= load($)
  return current
}

// One toast per phase transition, in full mode, never at the first load.
function announce($: Api, snap: Snapshot): void {
  const phase = snap.state.phase
  if (lastPhase !== undefined && phase !== lastPhase && phase !== null && !snap.inert) {
    // The game, if it is open, shows this line for a while. The toast is the normal single one.
    const where = phase === 'done' ? 'the run is done' : `${phaseLabel(phase)} is open`
    gameBanner = { text: `Temper: ${where}. Press Esc to go back.`, until: Date.now() + 20000 }
    const toast = snap.mode === 'full' ? transitionToast(snap.state.history[snap.state.history.length - 1]) : null
    if (toast) $.ui.toast(toast)
  }
  lastPhase = phase
}

// Takes a snapshot an `apply` produced as the current one.
function adopt($: Api, snap: Snapshot): Snapshot {
  current = Promise.resolve(snap)
  announce($, snap)
  return snap
}

async function refresh($: Api): Promise<Snapshot> {
  current = load($)
  const snap = await current
  await publish(makeIo($), snap).catch(() => undefined)
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

// ---- The game --------------------------------------------------------------------

// `game` is a plain string option (on or off), checked here and never as a picker.
const gameOn = (): boolean => parseOnOff(typeof options.game === 'string' ? options.game : undefined, 'on') === 'on'

// The Client element exists on the terminal and the desktop app only.
const GAME_SURFACES = ['terminal', 'desktop']

// The line Temper hands to the game: a new phase for a short while, else a gate that waits for the
// person (the first action is an approval or a move on).
function bannerFor(view: View | null): string | null {
  if (gameBanner && Date.now() < gameBanner.until) return gameBanner.text
  if (view === null || view.phase === null || view.phase === 'done') return null
  const first = view.actions?.primary[0]
  const waits = first?.command === 'approve' || first?.command === 'next'
  return waits ? `Temper: ${phaseLabel(view.phase)} is ready. Press Esc to go back.` : null
}

// Keeps the best score the game posted. This is the one place the game touches the plugin store.
async function saveBest($: Api, score: number): Promise<void> {
  if (!Number.isFinite(score) || score < 0 || score > 10000000 || score <= gameBest) return
  gameBest = Math.floor(score)
  await $.store.set('gameBest', gameBest)
}

// Opens or closes the game pane. Only an action of the person calls this: the command or the band
// button. Both ask for the keys (`focus`); the surface decides.
async function toggleGame($: Api): Promise<string> {
  if (!gameOn()) return 'The game is off. Set game to on in /config.'
  if (drawSurface === null || !GAME_SURFACES.includes(drawSurface)) return 'The game needs the terminal or the desktop app.'
  if (gameOpen) {
    await $.ui.close({ id: GAME_ID })
    gameOpen = false
    return 'The game is closed.'
  }
  const stored = await $.store.get('gameBest')
  gameBest = typeof stored === 'number' ? stored : 0
  gameSeed = (Date.now() & 0x7fffffff) >>> 0
  gameStatus = 'ready'
  // The pane asks for the keyboard and for Esc to close it. The surface grants the keys only
  // while the prompt has them over an empty composer, so the text below says what is true.
  const placed = await $.ui.open({ id: GAME_ID, title: 'Temper Run', focus: true, closeOnEscape: true })
  gameOpen = placed.isPlaced
  if (!placed.isPlaced) return 'The game needs a wider terminal.'
  const held = (await $.ui.panes().catch(() => [])).some(p => p.id === GAME_ID && p.isFocused)
  return held ? GAME_KEYS_TEXT : GAME_FOCUS_TEXT
}

// Presses of the game's Buttons. Each one writes one counter in $.state, so the pane draws again
// and the game sees the new value. Nothing is written on a frame.
async function readCtl($: Api): Promise<{ jump: number; start: number }> {
  const read = await $.state.get({ plugin: 'temper', key: 'game' } as const).catch(() => null)
  return read?.value ?? { jump: 0, start: 0 }
}

async function pressGame($: Api, which: 'jump' | 'start'): Promise<void> {
  const cur = await readCtl($)
  if (which === 'start') gameStatus = 'running'
  await $.state.set({ plugin: 'temper', key: 'game' } as const, { jump: cur.jump + (which === 'jump' ? 1 : 0), start: cur.start + (which === 'start' ? 1 : 0) })
}

// The Quit Button: close the pane, as Esc does.
async function quitGame($: Api): Promise<void> {
  await $.ui.close({ id: GAME_ID })
  gameOpen = false
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
    await closePane($)
    return 'The Temper pane is closed.'
  }
  return (await openPane($)) ? 'The Temper pane is open.' : 'The Temper pane needs a wider terminal.'
}

// Opened unasked (a session start): only where it would dock. Where it would only wait
// undrawn, it is closed again so it does not pop up later.
async function autoOpenPane($: Api, snap: Snapshot): Promise<void> {
  if (snap.mode !== 'full' || snap.state.phase === null || snap.state.phase === 'done') return
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

// ---- Decisions by the person: buttons -------------------------------------------

async function askReason($: Api, what: string): Promise<string> {
  try {
    return (await $.ui.ask(`What is the reason for ${what}?`, { options: ['I accept the risk', 'It is not a real issue'], header: 'Reason' })).trim()
  } catch {
    return ''
  }
}

// Records a decision as the given origin; a person's button press is the person's own.
async function decideAs($: Api, command: Bare, origin: 'person' | 'model'): Promise<{ error?: string; events: Draft[] }> {
  const fresh = await refresh($)
  const done = await apply(makeIo($), options, fresh, { ...command, origin, author: 'user' } as Command)
  adopt($, done.snap)
  return { error: done.error, events: done.events }
}

// prompt.submit is allowed here (a button press runs outside any held turn).
async function submitText($: Api, text: string | null): Promise<void> {
  if (text) await $.prompt.submit({ text }).then(() => undefined, () => undefined)
}

// The band's 9: focus the reason field so the person types the reason and presses Enter. When the
// field cannot take the focus (a different site), fall back to the question dialog.
async function focusReason($: Api, requestId: string): Promise<boolean> {
  const moved = await $.ui.focus({ requestId, key: REASON_KEY }).catch(() => undefined)
  return moved !== undefined && !('deny' in moved && moved.deny)
}

// Enter in the band's reason field: an empty reason is refused, a real one records the override.
async function runReason($: Api, text: string): Promise<void> {
  const reason = text.trim()
  if (!reason) {
    $.ui.toast(REASON_HINT)
    return
  }
  const done = await decideAs($, { type: 'override', reason }, 'person')
  if (done.error) {
    $.ui.toast(done.error)
    return
  }
  for (const draft of done.events) await submitText($, followUp(draft, (await ensure($)).complexity))
}

// Key 0 and the pane's "More actions" button. With the pane closed it opens the pane with the full
// list. With the pane open it shows or hides the list. When no pane can seat (a narrow terminal)
// the band shows the extra actions in a third row, and the same key hides them again.
async function showMore($: Api): Promise<void> {
  if (!paneOpen && !(live.paneExpanded ?? false)) {
    live.paneExpanded = true
    await openPane($)
  } else {
    live.paneExpanded = !(live.paneExpanded ?? false)
  }
  await refresh($)
  $.ui.invalidate('ui.render')
}

async function runAction($: Api, action: Action, requestId?: string): Promise<void> {
  if (action.id === 'play') {
    $.ui.toast(await toggleGame($))
    return
  }
  if (action.id === 'more' || action.id === 'more-actions') {
    await showMore($)
    return
  }
  if (action.id === 'more-narrow') {
    // A narrow band keeps the list in its own third row: no pane is opened.
    live.paneExpanded = !(live.paneExpanded ?? false)
    await refresh($)
    $.ui.invalidate('ui.render')
    return
  }
  if (action.id === 'override' && requestId !== undefined && (await focusReason($, requestId))) return
  if (action.prompt) {
    await submitText($, action.prompt)
    return
  }
  if (!action.command) return
  let args = action.command
  if (action.asksReason) {
    const reason = await askReason($, action.label.toLowerCase())
    if (!reason) {
      $.ui.toast(`${action.label} needs a reason.`)
      return
    }
    args = `${action.command} ${reason}`
  }
  const parsed = parseArgs(args)
  if (parsed === null) return
  const plan = planCommand(parsed, pendingDrift)
  if (plan.kind === 'error') {
    $.ui.toast(plan.text)
    return
  }
  if (plan.kind === 'local') return
  const done = await decideAs($, plan.command, 'person')
  if (done.error) {
    $.ui.toast(done.error)
    return
  }
  for (const draft of done.events) await submitText($, followUp(draft, (await ensure($)).complexity))
}

async function runFindingAction($: Api, kind: 'fix' | 'accept' | 'explain', id: string): Promise<void> {
  const [fix, , explain] = findingActions(id)
  if (kind === 'fix') return submitText($, fix?.prompt ?? null)
  if (kind === 'explain') return submitText($, explain?.prompt ?? null)
  const reason = await askReason($, `accepting finding ${id}`)
  if (!reason) {
    $.ui.toast('Accept needs a reason.')
    return
  }
  const done = await decideAs($, { type: 'acceptFinding', id, reason }, 'person')
  if (done.error) {
    $.ui.toast(done.error)
    return
  }
  for (const draft of done.events) await submitText($, followUp(draft, (await ensure($)).complexity))
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
  const result = await $.config.set({ key, value })
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
  $.ui.toast(`Temper enforcement: ${value}`)
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
    $.ui.toast('Temper mode is full. To change it, use /temper:temper mode <full|minimal|off>.')
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

// ---- Scope drift ---------------------------------------------------------------------

// Asks the person what to do about a write outside the plan, through the engine's own
// dialog. Null when nobody can be asked (`claude -p`) or the dialog was dismissed.
async function askDrift($: Api, path: string): Promise<{ choice: 'add' | 'revert' | 'allow-once'; reason: string } | null> {
  try {
    const answer = await $.ui.ask(`${path} is not in the plan. What do you want to do?`, {
      options: ['Add to plan', 'Revert', 'Allow once'],
      header: 'Scope drift',
    })
    if (answer === 'Add to plan') return { choice: 'add', reason: '' }
    if (answer === 'Revert') return { choice: 'revert', reason: '' }
    if (answer !== 'Allow once') return null
    // Allow once needs a reason: ask again while the answer is empty, then give up.
    for (let tries = 0; tries < 3; tries++) {
      const reason = (
        await $.ui.ask(`What is the reason to allow ${path} once?`, { options: ['Needed for this task', 'Short test'], header: 'Reason' })
      ).trim()
      if (reason) return { choice: 'allow-once', reason }
    }
    return null
  } catch {
    return null
  }
}

// A write outside the plan: offer the three choices and log the decision as an event.
// Returns the deny text, or null when the person let the write through.
async function resolveDrift($: Api, snap: Snapshot, path: string, fallback: string): Promise<string | null> {
  pendingDrift = path
  const choice = await askDrift($, path)
  if (choice === null) return fallback
  const io = makeIo($)
  const done = await apply(io, options, snap, { type: 'drift', path, choice: choice.choice, reason: choice.reason, origin: 'person', author: 'user' })
  adopt($, done.snap)
  if (done.error) return `Temper: scope drift on ${path} is not recorded. ${done.error}`
  pendingDrift = null
  if (choice.choice === 'revert') {
    // prompt.submit cannot be called from a tool.call hook (the engine says it would wait
    // on this very turn), so the instruction rides in the deny text Claude reads next.
    return `Temper: scope drift. The user chose to revert ${path}. It stays out of the plan. Next: restore ${path} to its committed state. Then continue inside the plan files.`
  }
  // Add to plan, or allow once: the decision now lets this write through.
  const again = evaluate(done.snap.state, ruleContext(done.snap, await rootOf($)), { tool: 'Edit', input: { file_path: path } })
  if ('deny' in again) return again.deny
  if (again.consume === 'drift' && again.driftPath) {
    adopt($, (await apply(io, options, done.snap, { type: 'useDrift', path: again.driftPath, origin: 'system' })).snap)
  }
  return null
}

function ruleContext(snap: Snapshot, rootDir: string): RuleContext {
  return { root: rootDir, specDir: snap.specDir, planFiles: snap.planFiles, humanDecisions: snap.humanDecisions, autonomyEnabled: snap.autonomyEnabled }
}

// The one place this module denies. Returns the deny text, or null to pass the call on.
async function guard($: Api, tool: string, input: Record<string, unknown>): Promise<string | null> {
  let snap = await ensure($)
  if (snap.inert || snap.enforcement === 'off') return null
  const io = makeIo($)
  const command = typeof input.command === 'string' ? input.command : ''
  if (tool === 'Bash' && classifyBash(command).commits) {
    // The commit gate reads the CLI's latest verdict, so reload before deciding.
    snap = adopt($, await syncCheck(io, options, await refresh($), false))
  }
  const r = evaluate(snap.state, ruleContext(snap, await rootOf($)), { tool, input })
  if ('deny' in r) return r.drift ? resolveDrift($, snap, r.drift, r.deny) : r.deny
  if (r.consume === 'drift' && r.driftPath) {
    adopt($, (await apply(io, options, snap, { type: 'useDrift', path: r.driftPath, origin: 'system' })).snap)
  } else if (r.consume && r.consume !== 'drift' && r.eventIds) {
    // Every human event a chained command matched is spent, not only the first.
    for (const id of r.eventIds) await consumeDecision(io, id)
    await refresh($)
  }
  return null
}

// `/temper:temper <reserved word>`: null means "not mine", and the prompt based command runs.
async function handleTemper($: Api, parsed: Parsed, originKind: string): Promise<CommandRunResult | null> {
  const snap = await ensure($)
  if (snap.inert) return null
  // Every word that changes state needs the person's own composer: the decisions, pause and
  // resume, and a mode or enforcement change. Checked before anything else, so a refusal never
  // depends on the arguments. The read only words (status, timeline, help, report) and
  // showing the current mode stay open to any origin.
  const changes: readonly string[] = ['approve', 'next', 'back', 'override', 'accept', 'drift', 'pause', 'resume']
  const changesState = changes.includes(parsed.word) || ((parsed.word === 'mode' || parsed.word === 'enforcement') && parsed.rest.trim() !== '')
  if (changesState && originKind !== 'composer') return { text: ONLY_USER }

  const plan = planCommand(parsed, pendingDrift)
  if (plan.kind === 'error') return { text: plan.text }

  if (plan.kind === 'local') {
    switch (plan.word) {
      case 'help':
        return { text: HELP }
      case 'status':
        return { text: statusText(await refresh($)) }
      case 'timeline':
        return { text: timelineText(await refresh($)) }
      case 'report':
        if (snap.slug === null) return { text: 'No run is active. There is no report to write.' }
        await writeReport(makeIo($), await refresh($))
        return { text: 'Wrote .temper/report.md' }
      case 'pr':
        // Claude writes the description: the prompt based command handles it.
        return null
      case 'play':
        // Only the person opens the game. It works in every mode, because the person asked.
        if (originKind !== 'composer') return { text: 'Only the user can open the game. Next: ask the user to run /temper:temper play.' }
        return { text: await toggleGame($) }
      case 'mode': {
        const wanted = plan.rest.trim().toLowerCase()
        if (wanted === '') return { text: interactive ? await askMode($) : `Temper mode: ${snap.mode}` }
        if (wanted !== 'full' && wanted !== 'minimal' && wanted !== 'off') return { text: 'Usage: /temper:temper mode <full|minimal|off>' }
        return { text: await switchMode($, parseUiMode(wanted)) }
      }
      case 'enforcement': {
        const wanted = plan.rest.trim().toLowerCase()
        if (wanted === '') return { text: `Temper enforcement: ${snap.enforcement}` }
        if (wanted !== 'on' && wanted !== 'off') return { text: 'Usage: /temper:temper enforcement <on|off>' }
        return { text: await switchEnforcement($, wanted) }
      }
      default:
        if (snap.mode !== 'full') return { text: 'The pane shows in full mode only. Use /temper:temper mode full.' }
        return { text: await togglePane($) }
    }
  }

  // A decision: only the person's own composer creates one. The event is the record the
  // commit gate and the rules trust; Claude's part (mirroring it in the CLI, continuing
  // the phase) is the prompt based /temper:temper, which runs next. prompt.submit is not used
  // here: the engine refuses it from inside command.run.
  const done = await decideAs($, plan.command, originKind === 'composer' ? 'person' : 'model')
  if (done.error) return { text: done.error }
  if (plan.command.type === 'pause' || plan.command.type === 'resume') {
    return { text: `The run is ${plan.command.type === 'pause' ? 'paused. You have control' : 'resumed'}.` }
  }
  return null
}

async function afterGateCheck($: Api): Promise<void> {
  adopt($, await syncCheck(makeIo($), options, await refresh($), true))
}

// The phase and effort a step runs with, from the phaseModels option; null leaves the step
// exactly as the engine built it.
async function phasePick($: Api, agentId: string | undefined): Promise<{ model?: string; effort?: 'low' | 'medium' | 'high' | 'xhigh' | 'max' } | null> {
  const raw = options.phaseModels
  if (agentId !== undefined || typeof raw !== 'string' || raw.trim() === '') return null
  const snap = await ensure($)
  if (snap.inert || snap.state.phase === null || snap.state.phase === 'done') return null
  const pick = parsePhaseModel(parsePhaseModels(raw)[snap.state.phase])
  return pick.model || pick.effort ? pick : null
}

const REVIEWERS = ['temper-review', 'temper:temper-review']

// Wiring only. Every hook fails open: an exception passes the call through, except the
// detected violation, which is the one place this module denies.
export const register: Register = (on, opts) => {
  options = opts
  current = null
  root = ''
  pendingDrift = null
  interactive = false
  paneOpen = false
  lastPhase = undefined
  gameOpen = false
  gameBest = 0
  gameBanner = null
  gameStatus = 'ready'
  drawSurface = null
  live.mode = undefined
  live.enforcement = undefined
  live.paneExpanded = undefined

  on('session.start', async ($, e, next) => {
    root = e.cwd
    drawSurface = e.surface
    interactive = e.isInteractive
    await refresh($)
      .then(snap => autoOpenPane($, snap))
      .catch(() => undefined)
    return next(e)
  })

  on('classic.SessionStart', async ($, e, next) => {
    if (e.cwd) root = e.cwd
    await refresh($).catch(() => undefined)
    return next(e)
  })

  // Only the reserved first words of /temper:temper are handled here; anything else (a feature
  // description) goes on to the prompt based command unchanged. Bare /temper:temper toggles the
  // pane while a run is active.
  on('command.run', async ($, e, next) => {
    if (e.command !== 'temper' && e.command !== 'temper:temper') return next(e)
    const parsed = parseArgs(e.args)
    // Only the person's own composer counts here: a command from any other origin never marks
    // the question answered and never opens the dialog. /temper:temper mode handles the
    // question itself (an explicit mode applies at once, a bare one asks once) and either way
    // counts as the first run answer.
    const isPerson = e.origin?.kind === 'composer'
    if (isPerson) {
      if (parsed?.word === 'mode') await markModeAsked($, parsed.rest.trim() !== '').catch(() => undefined)
      else await firstRunAsk($).catch(() => undefined)
    }
    if (parsed === null) {
      const snap = await ensure($).catch(() => null)
      const isBare = e.args.trim() === ''
      if (isBare && snap && !snap.inert && snap.mode === 'full' && snap.state.phase !== null && snap.state.phase !== 'done') {
        return { text: await togglePane($) }
      }
      return next(e)
    }
    const out = await handleTemper($, parsed, e.origin?.kind ?? '').catch(() => null)
    return out ?? next(e)
  })

  // One Temper line on a generated pull request description, while a run is on and the
  // prAttribution option is on.
  on('attribution.text', { kind: 'pr' }, async ($, e, next) => {
    const result = await next(e)
    try {
      const snap = await ensure($)
      if (snap.inert || snap.prAttribution !== 'on' || snap.slug === null) return result
      return { text: `${result.text}\n\nMade with Temper. The phases have gates. The report is in .temper/report.md.` }
    } catch {
      return result
    }
  })

  // Subagent calls arrive here too (e.agentId names the loop); they are held to the same
  // phase rules as the main loop.
  on('tool.call', async ($, e, next) => {
    const deny = await guard($, e.tool, { ...e }).catch(() => null)
    if (deny !== null) return { deny }
    const result = await next(e)
    const cmd = 'command' in e && typeof e.command === 'string' ? e.command : ''
    if (e.tool === 'Bash' && /\btemper["']?\s+gate\s+check\b/.test(cmd)) await afterGateCheck($).catch(() => undefined)
    return result
  })

  // One session scope section, last, rebuilt from the cached state on every request, so it
  // survives /compact by construction. Absent when the mod is inert: with no marker line
  // the skills announce that enforcement is off here.
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

  // The phase bar: six phases, and in full mode the actions (digit hotkeys). Off draws
  // nothing; a survey holding the band is left alone.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const ui = await readUi($).catch(() => null)
    if (ui === null) return next(e)
    const band = renderBand(
      $.ui.resolve(e),
      ui.view,
      ui.mode,
      action => runAction($, action, e.requestId).catch(() => undefined),
      reason => runReason($, reason).catch(() => undefined),
      e.props.bodyColumns,
      // The game button shows only while Claude works, and only when the game is on.
      { show: e.props.isWorking && gameOn(), open: gameOpen } satisfies GameButton,
    )
    return band ?? next(e)
  })

  // The game pane: the Client element exists on the terminal and the desktop app only. The module
  // runs on its own frame clock, so nothing here redraws it per frame.
  on('ui.render', { component: 'Pane', requestId: GAME_ID }, async ($, e, next) => {
    const kit = $.ui.resolve(e)
    // The table of another surface holds a Client that draws nothing, so the surface decides.
    if ((e.surface !== 'terminal' && e.surface !== 'desktop') || !('Client' in kit)) {
      const { Text } = kit
      return <Text>The game needs the terminal or the desktop app.</Text>
    }
    const ui = await readUi($).catch(() => null)
    const { Client, Box, Button } = kit
    const ctl = await readCtl($)
    return (
      <Box flexDirection="column">
        <Client
          key="game"
          module="./ui/game-client.tsx"
          props={{ best: gameBest, banner: bannerFor(ui?.view ?? null), seed: gameSeed, jumpCount: ctl.jump, startCount: ctl.start }}
        />
        <Box flexDirection="row" columnGap={2}>
          <Button key="game-jump" label="Jump" hotkey="w" plain onPress={() => pressGame($, 'jump').catch(() => undefined)} />
          <Button key="game-start" label={gameStatus === 'over' ? 'Again' : 'Start'} hotkey="s" plain onPress={() => pressGame($, 'start').catch(() => undefined)} />
          <Button key="game-quit" label="Quit" hotkey="q" plain onPress={() => quitGame($).catch(() => undefined)} />
        </Box>
      </Box>
    )
  })

  // The score the game posts when a game ends. The data is input, so it is checked.
  on('ui.message', async ($, e, next) => {
    if (e.element !== 'game') return next(e)
    const data = e.data
    if (typeof data === 'object' && data !== null && (data as { kind?: unknown }).kind === 'game-over') {
      await saveBest($, Number((data as { score?: unknown }).score)).catch(() => undefined)
      // The Start Button now says Again. One redraw for each game over, never one per frame.
      gameStatus = 'over'
      $.ui.invalidate('ui.render')
    }
    return {}
  })

  // A pane closed by its own mark: forget it, so the next toggle opens it again.
  on('ui.close', async ($, e, next) => {
    if (e.id === GAME_ID) {
      gameOpen = false
      gameStatus = 'ready'
    }
    if (e.id === PANE_ID) {
      paneOpen = false
      live.paneOpen = false
    }
    return next(e)
  })

  on('ui.render', { component: 'Pane', requestId: PANE_ID }, async ($, e, next) => {
    const ui = await readUi($).catch(() => null)
    if (ui === null || ui.mode !== 'full') return next(e)
    return renderPane(
      $.ui.resolve(e),
      ui.view,
      action => runAction($, action).catch(() => undefined),
      (kind, id) => runFindingAction($, kind, id).catch(() => undefined),
      e.props.placement === 'inline',
    )
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

  // One Temper line above the engine's dialog, which stays exactly once in the tree.
  on('ui.render', { component: 'AskUserQuestion' }, async ($, e, next) => {
    const engine = await next(e)
    const ui = await readUi($).catch(() => null)
    if (ui === null || ui.mode !== 'full') return engine
    return renderQuestion($.ui.resolve(e), ui.view, engine) ?? engine
  })

  // A line beneath the answer (phase, progress, next step), and the next action offered
  // as a suggestion (Tab to take). Nothing is submitted.
  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    try {
      if (e.agentId !== undefined || e.reason !== 'answer') return result
      const snap = await refresh($)
      const ui = await readUi($)
      if (ui === null || ui.mode !== 'full' || snap.inert) return result
      const idea = suggestion(ui.view)
      if (idea) await $.prompt.suggest({ text: idea }).then(() => undefined, () => undefined)
      const line = turnLine(ui.view)
      return line ? { ...result, text: line } : result
    } catch {
      return result
    }
  })

  // Optional: a model or effort per phase (userConfig phaseModels, "build=sonnet:high").
  // Empty means the step is passed on exactly as the engine built it.
  on('turn.step', async function* ($, e, next) {
    const pick = await phasePick($, e.agentId).catch(() => null)
    return yield* next(pick ? { ...e, ...pick } : e)
  })

  // Optional: a reviewer model for the Temper review agent (userConfig reviewerModel).
  on('agent.spawn', async (_$, e, next) => {
    const model = typeof options.reviewerModel === 'string' ? options.reviewerModel.trim() : ''
    if (!model || !REVIEWERS.includes(e.subagentType)) return next(e)
    return next({ ...e, model })
  })
}
