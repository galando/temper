import type { CommandRunResult, EngineInterface, PluginOptions, Register } from 'claude-code'

import { apply, commitFacts, composeText, consumeDecision, idleSnapshot, live, loadSnapshot, publish, runFingerprint, settingsFrom, statusText, syncCheck, timelineText, writeReport } from './adapter'
import type { Io, Snapshot } from './adapter'
import { findingActions } from './core/actions'
import type { Action } from './core/actions'
import { classifyBash } from './core/bash'
import { pluginCliFrom, stageOf } from './core/cli'
import { HELP, followUp, parseArgs, planCommand } from './core/commands'
import type { Bare, Parsed } from './core/commands'
import { parseGameMode, parseOnOff, parsePhaseModel, parsePhaseModels, parseUiMode, versionAtLeast } from './core/config'
import type { GameMode, UiMode } from './core/config'
import type { Draft } from './core/events'
import { ONLY_USER, phaseLabel } from './core/machine'
import type { Command } from './core/machine'
import { normalizePath } from './core/paths'
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
import { CARD_BG, FG } from './ui/palette'
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
// The line the person reads when the game opens. It is always this one. Whether the keys reach the
// game, the game finds out by itself (it draws a hint after 3 seconds with no key).
const GAME_KEYS_TEXT = 'The game is open. Press r to run, w to jump, s to duck, q or Esc to leave.'
// The type of the counters in $.state key game (types/index.d.ts has the same shape).
type GameCtl = { jumpCount: number; duckCount: number; startCount: number }
// After a game over the Run Button says Run again.
let gameOver = false
// Where the session draws (session.start says so); the game needs the terminal or the desktop app.
let drawSurface: string | null = null

const MODE_LABELS: Array<[UiMode, string]> = [
  ['full', 'Full: bar, buttons and pane'],
  ['minimal', 'Minimal: phases only'],
  ['off', 'Off: show nothing'],
]

// One toast. Every toast of the mod goes through here.
function showToast($: Api, text: string): void {
  $.ui.toast(text)
}

// The mod writes no file. What it records (the decision events and the report) is kept in the plugin
// store, under the full path it stands for: `vf:<path>` holds the text, `vfdir:<folder>` the names in
// a folder. Reads and lists see a kept text as a file, and still read real files (event files a run
// wrote before 9.6.2), so the adapter and the core work on paths as before.
const VF = 'vf:'
const VF_DIR = 'vfdir:'
// The folders with kept texts, oldest first. Past VF_MAX_DIRS the oldest folder is dropped from the store,
// so the store (4 MiB for every project on the machine) never fills up. A run keeps its events in one folder.
const VF_DIRS = 'vfdirs'
const VF_MAX_DIRS = 40

function splitPath(full: string): [string, string] {
  const cut = full.lastIndexOf('/')
  return cut < 0 ? ['', full] : [full.slice(0, cut), full.slice(cut + 1)]
}

async function keptNames($: Api, dir: string): Promise<string[]> {
  const names = await $.store.get(VF_DIR + dir)
  return Array.isArray(names) ? names.filter((n): n is string => typeof n === 'string') : []
}

async function keepText($: Api, full: string, text: string): Promise<void> {
  const [dir, name] = splitPath(full)
  await $.store.set(VF + full, text)
  const names = await keptNames($, dir)
  if (!names.includes(name)) await $.store.set(VF_DIR + dir, [...names, name])
  const raw = await $.store.get(VF_DIRS)
  const dirs = (Array.isArray(raw) ? raw.filter((d): d is string => typeof d === 'string') : []).filter(d => d !== dir)
  dirs.push(dir)
  while (dirs.length > VF_MAX_DIRS) {
    const old = dirs.shift() as string
    for (const n of await keptNames($, old)) await $.store.delete(VF + old + '/' + n)
    await $.store.delete(VF_DIR + old)
  }
  await $.store.set(VF_DIRS, dirs)
}

// `$` is spelled only in this file, as `$.noun.method(...)` at each call site, so the
// adapter and the pure core stay free of it.
function makeIo($: Api): Io {
  // A relative path means the project the session started in, even after Claude ran `cd` in a Bash
  // call: without this the files of the run are not found and the band goes away.
  const abs = (path: string): string => (root && !path.startsWith('/') ? `${root.replace(/\/$/, '')}/${path}` : path)
  return {
    read: async path => {
      const full = abs(path)
      const kept = await $.store.get(VF + full)
      if (typeof kept === 'string') return kept
      return $.fs.read(full).then(t => (typeof t === 'string' ? t : null))
    },
    list: async path => {
      const full = abs(path).replace(/\/$/, '')
      const kept = await keptNames($, full)
      let onDisk: Array<{ name: string; kind: string }>
      try {
        onDisk = await $.fs.list(full)
      } catch (err) {
        if (kept.length === 0) throw err
        onDisk = []
      }
      // A listing that is not a list is passed on as it came, so a broken load fails open as before.
      if (!Array.isArray(onDisk)) return onDisk
      const seen = new Set(onDisk.map(entry => entry.name))
      return [...onDisk, ...kept.filter(n => !seen.has(n)).map(n => ({ name: n, kind: 'file' }))]
    },
    write: (path, text) => keepText($, abs(path), text),
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

// The last snapshot that held a run. Enforcement is sticky: once the mod has seen a run in progress, a
// build-state.json that turns missing, unreadable or corrupt (chmod 000, a delete, a git clean) does not end it.
// The last known state keeps applying until the file reads again, the person turns enforcement off, or the mod reloads.
let lastRun: Snapshot | null = null

const LOST_STATE =
  'Temper state: .temper/build-state.json is missing or unreadable. The last known state still applies. Restore the file, or turn enforcement off with /temper:temper enforcement off.'

// The last known run, when it was in progress; null when it was over (Done) or never seen.
function heldRun(): Snapshot | null {
  const r = lastRun
  if (r === null || r.inert || r.sync.failOpen) return null
  const phase = r.state.phase
  if (phase === null || phase === 'done') return null
  // The settings are the live ones (the person may have turned enforcement off since); the run is the last known.
  return { ...r, ...settingsFrom(options), sync: { ...r.sync, line: LOST_STATE } }
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
// the files of the run (build-state.json, gates.json, events, report) are always read and written under
// the first root. `$.state` keeps it across a hot reload.

async function rememberedRoot($: Api): Promise<string> {
  const read = await $.state.get({ plugin: 'temper', key: 'root' } as const).catch(() => null)
  return typeof read?.value === 'string' ? read.value : ''
}

// The nearest folder at or above `cwd` that holds .temper/build-state.json; null when none does.
async function locateRoot($: Api, cwd: string): Promise<string | null> {
  let dir = cwd.replace(/\/+$/, '')
  for (let i = 0; i < 12 && dir !== ''; i++) {
    if ((await $.fs.read(`${dir}/.temper/build-state.json`).catch(() => undefined)) !== undefined) return dir
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

// One toast per phase transition, in full mode, never at the first load.
function announce($: Api, snap: Snapshot): void {
  const phase = snap.state.phase
  if (lastPhase !== undefined && phase !== lastPhase && phase !== null && !snap.inert) {
    // The game, if it is open, shows this line for a while. The toast is the normal single one.
    const where = phase === 'done' ? 'the run is done' : `${phaseLabel(phase)} is open`
    gameBanner = { text: `Temper: ${where}. Press Esc to go back.`, until: Date.now() + 20000 }
    const toast = snap.mode === 'full' ? transitionToast(snap.state.history[snap.state.history.length - 1]) : null
    if (toast) showToast($, toast)
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
const gameMode = (): GameMode => parseGameMode(typeof options.game === 'string' ? options.game : undefined)
// The command works in `on` and `command`. Offers (band, pane, hint) show in `on` only.
const gameOn = (): boolean => gameMode() !== 'off'
const gameOffered = (): boolean => gameMode() === 'on'
// Whether Claude is working, as the band and the hint last saw it. The pane has no such prop.
let working = false

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
// Only a real number counts: a string, an array or a boolean is refused, not converted.
async function saveBest($: Api, score: unknown): Promise<void> {
  if (typeof score !== 'number' || !Number.isFinite(score)) return
  const whole = Math.floor(score)
  if (whole < 0 || whole > 99999 || whole <= gameBest) return
  gameBest = whole
  await $.store.set('gameBest', gameBest)
}

// The pane draws its game offer from `working`. When the band or the hint sees a change, redraw once.
async function noteWorking($: Api, now: boolean): Promise<void> {
  if (working === now) return
  working = now
  $.ui.invalidate('ui.render')
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
  gameSeed = seedFor(0)
  gameOver = false
  // The pane asks for the keyboard and for Esc to close it. The surface may or may not grant the
  // keys; the game draws a hint by itself when no key comes.
  const placed = await $.ui.open({ id: GAME_ID, title: 'Temper Run', focus: true, closeOnEscape: true, rows: 14 })
  gameOpen = placed.isPlaced
  if (!placed.isPlaced) return 'The game needs a wider terminal.'
  return GAME_KEYS_TEXT
}

// A seed for a run: the clock. A test sets the plugin option `gameSeed` (a number) to get a run it
// knows; each new run then adds the count of the Run presses, so the seeds differ.
function seedFor(salt: number): number {
  const fixed = typeof options.gameSeed === 'string' || typeof options.gameSeed === 'number' ? Number(options.gameSeed) : NaN
  if (Number.isFinite(fixed)) return (Math.floor(fixed) + salt * 7919) >>> 0
  return ((Date.now() & 0x7fffffff) + salt) >>> 0
}

// The key presses that reached the pane's Buttons, as counters in $.state (key game). The drawing
// reads them as props, compares them with the values it saw last, and applies each new press once.
// A press is one write; the frame clock writes nothing here.
async function readCtl($: Api): Promise<GameCtl> {
  const read = await $.state.get({ plugin: 'temper', key: 'game' } as const).catch(() => null)
  return read?.value ?? { jumpCount: 0, duckCount: 0, startCount: 0 }
}

async function pressGame($: Api, which: 'jumpCount' | 'duckCount' | 'startCount'): Promise<void> {
  const cur = await readCtl($)
  if (which === 'startCount') gameOver = false
  await $.state.set({ plugin: 'temper', key: 'game' } as const, { ...cur, [which]: cur[which] + 1 })
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
//
// A button passes `drawnPhase`, the phase it was drawn for. When the run has moved since, the press
// is stale and is ignored, and a move that follows another within a second is the same press twice.
// Neither records an event. A typed command passes none.
const STALE = 'That step is already done.'
let lastMoveAt = 0
const MOVES = new Set(['approve', 'advance', 'back', 'override'])
async function decideAs($: Api, command: Bare, origin: 'person' | 'model', drawnPhase?: string | null): Promise<{ error?: string; events: Draft[] }> {
  const fresh = await refresh($)
  if (drawnPhase !== undefined && drawnPhase !== null) {
    if (fresh.state.phase !== drawnPhase) return { error: STALE, events: [] }
    // A test sets the plugin option `moveCooldownMs` (like `gameSeed`); nobody else needs to.
    const cooldown = Number.isFinite(Number(options.moveCooldownMs)) && options.moveCooldownMs !== undefined ? Number(options.moveCooldownMs) : 1000
    if (MOVES.has(command.type) && Date.now() - lastMoveAt < cooldown) return { error: STALE, events: [] }
  }
  const done = await apply(makeIo($), options, fresh, { ...command, origin, author: 'user' } as Command)
  adopt($, done.snap)
  if (!done.error && MOVES.has(command.type)) lastMoveAt = Date.now()
  return { error: done.error, events: done.events }
}

// One decision button at a time: a second press while the first runs is dropped at once, with no
// toast and no event. The lock is taken before the first await.
const pressing = new Set<string>()
const LOCK: Record<string, string> = { approve: 'move', next: 'move', back: 'move', override: 'move', accept: 'accept', pause: 'pause', resume: 'pause', drift: 'drift' }
async function withLock(word: string | undefined, run: () => Promise<void>): Promise<void> {
  const key = word === undefined ? undefined : LOCK[word]
  if (key === undefined) return run()
  if (pressing.has(key)) return
  pressing.add(key)
  try {
    await run()
  } finally {
    pressing.delete(key)
  }
}

// prompt.submit is allowed here (a button press runs outside any held turn).
// The Temper script in the plugin folder, as a full path. The mod file sits at
// <plugin>/hooks/temper-mod/register.tsx, so the root is two folders up. Anything else (an
// unexpected location) gives the plain `scripts/temper`, and the prompt then says where to look.
function pluginCli(): string {
  return pluginCliFrom((import.meta as { url?: string }).url)
}

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
function runReason($: Api, text: string, drawnPhase?: string | null): Promise<void> {
  // The lock is taken here, before any await: two Enter presses at once record one skip.
  return withLock('override', () => runReasonLocked($, text, drawnPhase))
}

async function runReasonLocked($: Api, text: string, drawnPhase?: string | null): Promise<void> {
  const reason = text.trim()
  if (!reason) {
    showToast($, REASON_HINT)
    return
  }
  const done = await decideAs($, { type: 'override', reason }, 'person', drawnPhase)
  if (done.error) {
    showToast($, done.error)
    return
  }
  const launched = await handOver($, done.events)
  // The step is skipped: the orchestrator runs the next one.
  if (!launched) await resumeRun($)
}

// Tells Claude about decisions the person just made. A move forward goes to the orchestrator as
// `/temper:temper continue <stage>`: the person approved <stage>, the decision event exists, and the
// orchestrator does the "On Continue" steps of that stage exactly as written (state advance, status flip,
// branch, commit of the artifacts) and launches the next stage. The guard lets its `state advance` through
// once, because the matching decision exists. Anything else (back, override, accept) keeps the mirror
// prompt. Returns whether the orchestrator was launched.
async function handOver($: Api, drafts: readonly Draft[]): Promise<boolean> {
  let launched = false
  for (const draft of drafts) {
    if (draft.type === 'advance' && draft.from !== 'fix') {
      // Design is part of Plan in the mod. When the plan was approved and the CLI is at its design stage, this
      // Continue approves the design: the orchestrator does the On Continue steps of Design.
      const stage = draft.from === 'plan' && (await ensure($)).cliNext === 'design' ? 'design' : draft.from
      await continueStage($, stage)
      launched = true
    } else {
      const snap = await ensure($)
      // The phase a step back left, from the run's own history: the CLI loop is from -> to.
      const left = draft.type === 'back' ? ([...snap.state.history].reverse().find(step => step.kind === 'back' && step.to === draft.to)?.from ?? null) : null
      await submitText($, followUp(draft, snap.complexity, pluginCli(), left))
      // A skip is a move on, like a Continue: the CLI is still at the skipped stage, so the orchestrator does
      // that stage's On Continue steps (`state advance`, which the guard lets through for a skip) and launches
      // the next stage. Fix is the Check stage of the CLI.
      if (draft.type === 'override') {
        await continueStage($, stageOf(draft.phase))
        launched = true
      }
    }
  }
  return launched
}

// Key 1 when the person's last move is not recorded in the CLI: the same pending decision, the same
// mirror prompt, once more. No new event is written, and the decision stays single use. When the run
// has moved by now, there is nothing to record.
async function recordAgain($: Api): Promise<void> {
  const snap = await refresh($)
  const pending = snap.sync.pending
  if (pending === null) {
    showToast($, 'That step is already done.')
    return
  }
  // A call that took the decision and never ran must not keep it away from the mirror call.
  reservedDecisions.delete(pending.id)
  if (!(await handOver($, [pending.draft]))) await resumeRun($)
}

// Key 0 (and the pane's More button): show or hide the menu of the other options. The band and the
// pane both draw it, with the digits 1 to 9, in place of the main buttons. No pane is opened.
async function showMore($: Api, expanded?: boolean): Promise<void> {
  live.paneExpanded = expanded ?? !(live.paneExpanded ?? false)
  await refresh($)
  $.ui.invalidate('ui.render')
}

// A button that needs a stage to run ends with the orchestrator's own Resume: `/temper:temper` with no
// arguments. Its brief for the stage (agents/*.md) is then the one that runs, not a prompt of ours.
// `prompt.submit` refuses a text that starts with a slash, so the command is run as a command.
async function resumeRun($: Api): Promise<void> {
  await $.command.run({ command: 'temper:temper', args: '' }).then(ignore, ignore)
}

// `/temper:temper continue <stage>`: the orchestrator does the On Continue steps of a stage the person approved.
// Each command is written out in full, so the plugin directory can read every command the mod runs. A stage
// that is none of these runs nothing.
async function continueStage($: Api, stage: string): Promise<void> {
  switch (stage) {
    case 'intent':
      await $.command.run({ command: 'temper:temper', args: 'continue intent' }).then(ignore, ignore)
      return
    case 'plan':
      await $.command.run({ command: 'temper:temper', args: 'continue plan' }).then(ignore, ignore)
      return
    case 'design':
      await $.command.run({ command: 'temper:temper', args: 'continue design' }).then(ignore, ignore)
      return
    case 'build':
      await $.command.run({ command: 'temper:temper', args: 'continue build' }).then(ignore, ignore)
      return
    case 'review':
      await $.command.run({ command: 'temper:temper', args: 'continue review' }).then(ignore, ignore)
      return
    case 'check':
      await $.command.run({ command: 'temper:temper', args: 'continue check' }).then(ignore, ignore)
      return
    default:
      return
  }
}

function ignore(): undefined {
  return undefined
}

// Puts a draft in the prompt box so the person types the rest and presses Enter. The press itself
// never moves the phase and writes no event.
async function fillDraft($: Api, text: string): Promise<void> {
  const filled = await $.prompt.fill({ text, mode: 'replace' }).catch(() => undefined)
  showToast($, filled?.isFilled ? 'Type your message. Press Enter to send it.' : 'Close the pane, then type your message.')
}

function runAction($: Api, action: Action, requestId?: string, drawnPhase?: string | null): Promise<void> {
  return withLock(action.command?.split(' ')[0], () => runActionLocked($, action, requestId, drawnPhase))
}

async function runActionLocked($: Api, action: Action, requestId?: string, drawnPhase?: string | null): Promise<void> {
  if (action.id === 'play') {
    showToast($, await toggleGame($))
    return
  }
  if (action.id === 'more' || action.id === 'more-actions' || action.id === 'more-narrow') {
    await showMore($)
    return
  }
  // A choice from the menu leaves the menu: the main buttons come back.
  if (live.paneExpanded) await showMore($, false)
  if (action.record) {
    await recordAgain($)
    return
  }
  if (action.id === 'override' && requestId !== undefined && (await focusReason($, requestId))) return
  if (action.fill !== undefined) {
    await fillDraft($, action.fill)
    return
  }
  // The original "Save for later" at the Commit question: nothing to record, the work stays as it is.
  if (action.id === 'save-done') {
    showToast($, 'Saved. Commit when you are ready.')
    return
  }
  if (action.resume && !action.command && !action.prompt) {
    if (working) {
      showToast($, 'Claude is working. Wait for the answer, then press 1.')
      return
    }
    await resumeRun($)
    return
  }
  if (action.prompt && !action.command) {
    await submitText($, action.prompt)
    return
  }
  if (!action.command) return
  let args = action.command
  if (action.asksReason) {
    const reason = await askReason($, action.label.toLowerCase())
    if (!reason) {
      showToast($, `${action.label} needs a reason.`)
      return
    }
    args = `${action.command} ${reason}`
  }
  const parsed = parseArgs(args)
  if (parsed === null) return
  const plan = planCommand(parsed, pendingDrift)
  if (plan.kind === 'error') {
    showToast($, plan.text)
    return
  }
  if (plan.kind === 'local') return
  const done = await decideAs($, plan.command, 'person', drawnPhase)
  if (done.error) {
    showToast($, done.error)
    return
  }
  const launched = await handOver($, done.events)
  // The prompt of an action that both records and asks (Stop), then the stage the orchestrator runs.
  if (action.prompt) await submitText($, action.prompt)
  if (action.resume && !launched) await resumeRun($)
}

async function runFindingAction($: Api, kind: 'fix' | 'accept' | 'explain', id: string): Promise<void> {
  const [fix, , explain] = findingActions(id)
  if (kind === 'fix') return submitText($, fix?.prompt ?? null)
  if (kind === 'explain') return submitText($, explain?.prompt ?? null)
  const reason = await askReason($, `accepting finding ${id}`)
  if (!reason) {
    showToast($, 'Accept needs a reason.')
    return
  }
  const done = await decideAs($, { type: 'acceptFinding', id, reason }, 'person')
  if (done.error) {
    showToast($, done.error)
    return
  }
  await handOver($, done.events)
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
    showToast($, 'Temper mode is full. To change it, use /temper:temper mode <full|minimal|off>.')
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
  if (done.error) return `Temper: scope drift on ${path} is not recorded. ${done.error} Next: ask the user to choose again (/temper:temper drift add|revert|allow <reason>).`
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
  return { root: rootDir, specDir: snap.specDir, planFiles: snap.planFiles, humanDecisions: snap.humanDecisions, autonomyEnabled: snap.autonomyEnabled, designRequired: snap.designRequired, complexity: snap.complexity, failOpenWrites: snap.sync.looksReset }
}

// What the guard decided for one call: a deny text, or null to pass it on. `ids` are the human decisions
// the call took. They are spent only when the call ran and succeeded (see the tool.call hook).
// `fingerprint` is the CLI's files before a call that took decisions or a loop: after a call that ended in an error it
// says whether the call took effect anyway. `loopIds` are back decisions a `state loop` call used.
type Guarded = { deny: string | null; ids: string[]; undoStaged?: { all: boolean; paths: string[] }; loopIds?: string[]; fingerprint?: string }

// The shell's folder, carried from one Bash call to the next (the engine keeps it). A folder outside the project, or one
// that cannot be read, is taken as the project root: the engine puts the shell back there.
let bashCwd = ''
const loopedDecisions = new Set<string>()

function carryCwd(after: string | null, rootDir: string): string {
  if (after === null || after === '') return ''
  if (!after.startsWith('/')) return after
  const rel = normalizePath(after, rootDir)
  return rel.startsWith('/') || rel.startsWith('..') ? '' : rel
}

const GUARD_ERROR =
  'Temper: the guard hit an error while it checked this command, and a run is active. Temper does not pass a command it could not check. ' +
  'Next: run the command again. If it keeps failing, ask the user (the user can turn enforcement off with /temper:temper enforcement off).'

// A guard that threw: Bash is refused while a run is active (a command the guard cannot read is the one to refuse),
// every other tool passes (the mod must not make Temper worse than without it).
function failedGuard(tool: string): Guarded {
  const r = lastRun
  const active = r !== null && !r.inert && r.enforcement !== 'off' && !r.sync.failOpen && r.state.phase !== null && r.state.phase !== 'done'
  return tool === 'Bash' && active ? { deny: GUARD_ERROR, ids: [] } : { deny: null, ids: [] }
}

// The one place this module denies.
async function guard($: Api, tool: string, input: Record<string, unknown>): Promise<Guarded> {
  let snap = await ensure($)
  // Fail open: when the mod cannot tell where the run is, it never blocks Temper (the mod must not make
  // Temper worse than without it).
  if (snap.inert || snap.enforcement === 'off' || snap.sync.failOpen) return { deny: null, ids: [] }
  const io = makeIo($)
  const command = typeof input.command === 'string' ? input.command : ''
  const cls = tool === 'Bash' ? classifyBash(command, bashCwd) : null
  // What this session staged with `git add` so far: a commit of spec files only is the artifact chain.
  if (cls) {
    staged.all = staged.all || cls.staged.all
    staged.paths.push(...cls.staged.paths)
  }
  if (cls?.commits) {
    // The commit gate reads the CLI's latest verdict, so reload before deciding.
    snap = adopt($, await syncCheck(io, options, await refresh($), false))
  }
  const root = await rootOf($)
  const commit = cls?.commits ? await commitFacts(io, snap, root, staged) : undefined
  // From here to the reservation there is no await: a parallel call cannot slip in between. A
  // decision a running call has reserved is not offered to this one.
  const ctx = { ...ruleContext(snap, root), cwd: bashCwd, loopedDecisions: [...loopedDecisions], ...(commit ? { commit } : {}) }
  const r = evaluate(snap.state, { ...ctx, humanDecisions: (ctx.humanDecisions ?? []).filter(decision => !reservedDecisions.has(decision.id)) }, { tool, input })
  // A commit that went through starts the next staging from nothing. If the commit then fails (an index lock,
  // a hook), the files are still staged: tool.call gives the list back (found live: the retry was refused).
  let undoStaged: Guarded['undoStaged']
  if (cls?.commits && !('deny' in r)) {
    undoStaged = { all: staged.all, paths: [...staged.paths] }
    staged.all = false
    staged.paths = []
  }
  if ('deny' in r) return { deny: r.drift ? await resolveDrift($, snap, r.drift, r.deny) : r.deny, ids: [] }
  // The command will run: the shell's folder is where it leaves it.
  if (cls) bashCwd = carryCwd(cls.cwdAfter, root)
  // A `state loop` call used the person's back decision once: a second one needs another decision.
  const loopIds = r.loopIds ?? []
  for (const id of loopIds) loopedDecisions.add(id)
  if (r.consume === 'drift' && r.driftPath) {
    adopt($, (await apply(io, options, snap, { type: 'useDrift', path: r.driftPath, origin: 'system' })).snap)
  } else if (r.consume && r.consume !== 'drift' && r.eventIds) {
    // Every human event a chained command matched is reserved at once, so a parallel call cannot use
    // it too. It is spent after the call ran, also when the call ended in an error but changed the CLI's files (see
    // tookEffect). A call that failed and changed nothing, or never ran, gives the decision back, and the person's
    // choice stays pending (key 1 records it again).
    for (const id of r.eventIds) reservedDecisions.add(id)
    return { deny: null, ids: r.eventIds, ...(undoStaged ? { undoStaged } : {}), ...(loopIds.length > 0 ? { loopIds } : {}), fingerprint: await runFingerprint(io).catch(() => '') }
  }
  return { deny: null, ids: [], ...(undoStaged ? { undoStaged } : {}), ...(loopIds.length > 0 ? { loopIds, fingerprint: await runFingerprint(io).catch(() => '') } : {}) }
}

// After a call that ended in an error: did it change the CLI's files all the same (`state advance ...; exit 1`)?
// The decision it used is then spent, as for a call that ended well. The exit status says nothing about the effect.
async function tookEffect($: Api, g: Guarded): Promise<boolean> {
  if (g.fingerprint === undefined || g.fingerprint === '') return false
  const after = await runFingerprint(makeIo($)).catch(() => g.fingerprint)
  return after !== g.fingerprint
}

// A `state loop` call that failed with no effect gives the back decision's one use back.
function releaseLoops(g: Guarded, failed: boolean): void {
  if (failed) for (const id of g.loopIds ?? []) loopedDecisions.delete(id)
}

// A commit call that failed did not use the staged files: the list the guard cleared comes back.
function restoreStaged(g: Guarded, failed: boolean): void {
  if (!failed || !g.undoStaged) return
  staged.all = staged.all || g.undoStaged.all
  staged.paths = [...g.undoStaged.paths, ...staged.paths]
}

// After a call that took decisions: spend them when it succeeded, give them back when it failed.
async function settle($: Api, ids: string[], failed: boolean): Promise<void> {
  const io = makeIo($)
  if (failed) {
    for (const id of ids) reservedDecisions.delete(id)
  } else {
    // An id stays in `reservedDecisions` once spent: a call that read its snapshot before the spend
    // must still not use the event again.
    for (const id of ids) await consumeDecision(io, id)
  }
  await refresh($)
}

// The files `git add` staged in this session (see guard). Unknown at the start: not an artifact commit.
const staged: { all: boolean; paths: string[] } = { all: false, paths: [] }

// Decision events a tool call has taken (see guard). An id stays here once spent: event ids are
// unique, and a call that read its snapshot before the spend must still not use the event again.
const reservedDecisions = new Set<string>()
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
        if (snap.slug === null) return { text: 'No run is active. There is no report to show.' }
        return { text: await writeReport(makeIo($), await refresh($)) }
      case 'pr':
      case 'discuss':
      case 'continue':
        // Claude writes the description, answers the message, or does the On Continue steps of a stage the
        // person already approved (the decision event exists): the prompt based command handles it. The
        // mod records nothing here.
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

// The model and effort a step runs with: on the main loop from the phaseModels option, in the Temper review agent
// from the reviewerModel option. Null leaves the step exactly as the engine built it. The spawn of an agent is never
// changed: the reviewer model applies to the steps of that agent only.
async function phasePick($: Api, agentId: string | undefined): Promise<{ model?: string; effort?: 'low' | 'medium' | 'high' | 'xhigh' | 'max' } | null> {
  if (agentId !== undefined) {
    const model = typeof options.reviewerModel === 'string' ? options.reviewerModel.trim() : ''
    return model && (await isReviewer($, agentId)) ? { model } : null
  }
  const raw = options.phaseModels
  if (typeof raw !== 'string' || raw.trim() === '') return null
  const snap = await ensure($)
  if (snap.inert || snap.state.phase === null || snap.state.phase === 'done') return null
  const pick = parsePhaseModel(parsePhaseModels(raw)[snap.state.phase])
  return pick.model || pick.effort ? pick : null
}

// Wiring only. Every hook fails open: an exception passes the call through, except the
// detected violation, which is the one place this module denies.
export const register: Register = (on, opts) => {
  options = opts
  current = null
  root = ''
  lastRun = null
  rootVerified = false
  sessionCwd = ''
  bashCwd = ''
  loopedDecisions.clear()
  pendingDrift = null
  lastMoveAt = 0
  pressing.clear()
  staged.all = false
  staged.paths = []
  interactive = false
  paneOpen = false
  lastPhase = undefined
  gameOpen = false
  gameBest = 0
  gameOver = false
  gameBanner = null
  working = false
  drawSurface = null
  live.mode = undefined
  live.enforcement = undefined
  live.paneExpanded = undefined
  reviewerIds.clear()

  on('session.start', async ($, e, next) => {
    await settleRoot($, e.cwd)
    current = null
    drawSurface = e.surface
    interactive = e.isInteractive
    reservedDecisions.clear()
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
      // Only the person's own bare /temper:temper toggles the pane. The same words from a plugin (the
      // button that launches a stage) go on to the orchestrator.
      if (isBare && isPerson && snap && !snap.inert && snap.mode === 'full' && snap.state.phase !== null && snap.state.phase !== 'done') {
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
      return { text: `${result.text}\n\nMade with Temper. The phases have gates. /temper:temper report shows the report.` }
    } catch {
      return result
    }
  })

  // Subagent calls arrive here too (e.agentId names the loop); they are held to the same
  // phase rules as the main loop.
  on('tool.call', async ($, e, next) => {
    const g = await guard($, e.tool, { ...e }).catch((): Guarded => failedGuard(e.tool))
    if (g.deny !== null) return { deny: g.deny }
    let result
    try {
      result = await next(e)
    } catch (err) {
      const failed = !(await tookEffect($, g).catch(() => false))
      await settle($, g.ids, failed).catch(() => undefined)
      releaseLoops(g, failed)
      restoreStaged(g, true)
      throw err
    }
    const errored = (result as { isError?: boolean }).isError === true
    restoreStaged(g, errored)
    // An error status is not "nothing happened": the decision is given back only when the CLI's files did not change.
    const failed = errored && !(g.ids.length + (g.loopIds?.length ?? 0) > 0 && (await tookEffect($, g).catch(() => false)))
    releaseLoops(g, failed)
    if (g.ids.length > 0) await settle($, g.ids, failed).catch(() => undefined)
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
      action => runAction($, action, e.requestId, ui.view.phase).catch(() => undefined),
      reason => runReason($, reason, ui.view.phase).catch(() => undefined),
      e.props.bodyColumns,
      // The game button shows only while Claude works, and only when the game is on.
      { show: e.props.isWorking && gameOffered(), open: gameOpen } satisfies GameButton,
    )
    await noteWorking($, e.props.isWorking)
    return band ?? next(e)
  })

  // The game pane: the Client element exists on the terminal and the desktop app only. The module
  // runs on its own frame clock, so nothing here redraws it per frame.
  on('ui.render', { component: 'Pane', requestId: GAME_ID }, async ($, e, next) => {
    // The table of another surface holds a Client that draws nothing, so the surface decides.
    if (e.surface !== 'terminal' && e.surface !== 'desktop') {
      const { Box, Text } = $.ui.resolve(e)
      return (
        <Box backgroundColor={CARD_BG}>
          <Text color={FG}>The game needs the terminal or the desktop app.</Text>
        </Box>
      )
    }
    const ui = await readUi($).catch(() => null)
    // The Client is taken straight from the element table, so its module path is the fixed text below.
    const { Client, Box, Button } = $.ui.resolve(e)
    const ctl = await readCtl($)
    const act = (fn: () => Promise<void>) => () => fn().catch(() => undefined)
    return (
      <Box flexDirection="column" backgroundColor={CARD_BG}>
        <Client
          key="game"
          module="./ui/game-client.tsx"
          props={{ ...ctl, seed: seedFor(ctl.startCount), best: gameBest, banner: bannerFor(ui?.view ?? null), compact: e.props.placement === 'inline' }}
        />
        <Box flexDirection="row" columnGap={1} flexWrap="wrap">
          <Button key="game-jump" label="w  Jump" hotkey="w" variant="primary" onPress={act(() => pressGame($, 'jumpCount'))} />
          <Button key="game-duck" label="s  Duck" hotkey="s" variant="primary" onPress={act(() => pressGame($, 'duckCount'))} />
          <Button key="game-run" label={gameOver ? 'r  Run again' : 'r  Run'} hotkey="r" variant="primary" onPress={act(() => pressGame($, 'startCount'))} />
          <Button key="game-quit" label="q  Quit" hotkey="q" variant="primary" onPress={act(() => quitGame($))} />
        </Box>
      </Box>
    )
  })

  // The score the game posts when a run ends. The data is input, so it is checked. The best score
  // goes to the store once for each game over, and the Run Button then says Run again.
  on('ui.message', async ($, e, next) => {
    if (e.element !== 'game') return next(e)
    const data = e.data
    if (typeof data === 'object' && data !== null && (data as { kind?: unknown }).kind === 'game-over') {
      await saveBest($, (data as { score?: unknown }).score).catch(() => undefined)
      gameOver = true
      $.ui.invalidate('ui.render')
    }
    return {}
  })

  // A pane closed by its own mark: forget it, so the next toggle opens it again.
  on('ui.close', async ($, e, next) => {
    if (e.id === GAME_ID) gameOpen = false
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
      action => runAction($, action, undefined, ui.view.phase).catch(() => undefined),
      (kind, id) => runFindingAction($, kind, id).catch(() => undefined),
      e.props.placement === 'inline',
      { show: working && gameOffered(), open: gameOpen },
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
    const props = ui !== null && ui.mode === 'full' ? hintProps(e.props, ui.view, e.surface, gameOffered()) : null
    await noteWorking($, e.props.isWorking)
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

  // Optional: a model or effort per phase (userConfig phaseModels, "build=sonnet:high"), and a model for the steps
  // of the Temper review agent (userConfig reviewerModel). Empty means the step is passed on exactly as the engine
  // built it.
  on('turn.step', async function* ($, e, next) {
    const pick = await phasePick($, e.agentId).catch(() => null)
    return yield* next(pick ? { ...e, ...pick } : e)
  })
}
