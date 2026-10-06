// Test world: the fake engine beneath the plugin's tests. This file is test only: it runs under
// `claude plugin test` and is never loaded in a session. Files live in a Map the fs.* hooks answer
// from; a file write records back into it.
import type { On } from 'claude-code'

export type World = {
  files: Map<string, string>
  writes: string[]
  // Every real file write the plugin made (the mod makes none: it keeps its records in the store).
  fsWrites: string[]
  reads: string[]
  store: Record<string, unknown>
  // Project relative files that exist but cannot be read (chmod 000): a read answers EACCES, not ENOENT.
  unreadable?: Set<string>
  // True: every file write the plugin makes fails (a read only folder).
  failWrites?: boolean
  // Prompts the mod submitted to Claude, in order.
  prompts: string[]
  // The path of every fs call exactly as the plugin gave it (reads and lists and writes).
  rawPaths: string[]
  // How many of the next `state advance|set` calls the fake CLI refuses (see fakeCli).
  cliFailures?: number
  // How many of the next `git commit` calls the fake CLI fails (see fakeCli).
  commitFailures?: number
  // The folder the engine is in now, after a `cd` (see WorldOptions.projectRoot).
  cwdNow?: string
  // Commands that reached the engine's own command run (after the plugin's hooks), in order.
  commandRuns: Array<{ command: string; args: string; origin: string }>
  // Drafts the mod put in the prompt box (`$.prompt.fill`), in order.
  filled: Array<{ text: string; mode: string | undefined }>
  // Questions the mod asked the person through the engine's dialog, in order.
  asked: string[]
  // Answers the person gives, in order; empty means nobody answers (a `-p` run).
  answers: string[]
  // What the mod showed or did through the engine's UI calls.
  toasts: string[]
  opened: string[]
  // Whether each pane open asked for the keys.
  openArgs: Array<{ id: string; focus: boolean; closeOnEscape: boolean }>
  closed: string[]
  invalidated: number
  suggestions: string[]
  // Config rows (`temper.uiMode`, ...) the mod listed and the values it set, in order.
  rows: Array<{ key: string; value: string; isLocked: boolean }>
  configSets: Array<{ key: string; value: unknown }>
  // The props the engine's own drawing received after the plugins' hooks, per component.
  rendered: Array<{ component: string; props: Record<string, unknown> }>
}

export type WorldOptions = {
  version?: string | null
  cwd?: string
  // Initial store entries (the mod's own event ids live under `ev:`).
  store?: Record<string, unknown>
  // Answers the person gives to the mod's questions, in order.
  answers?: string[]
  // Config rows the mod can list; a locked one is an administrator's.
  rows?: Array<{ key: string; value: string; isLocked: boolean }>
  // False answers every pane open with "not placed" (a narrow terminal).
  placed?: boolean
  // True: the surface grants the keyboard to a pane that asks for it (an empty composer).
  // Left out: it refuses, as it does while the composer holds text.
  grantFocus?: boolean
  // Answer every directory listing with something that is not a list.
  brokenList?: boolean
  // False: the prompt box refuses a draft (a dialog or the game pane holds the keys).
  fillable?: boolean
  // Only files under this folder exist (see `outside`); a relative path is read from `w.cwdNow`.
  projectRoot?: string
  // True: the engine's Bash runs `scripts/temper state advance|set` against .temper/build-state.json
  // like the real CLI does (see fakeCli).
  fakeCli?: boolean
  // The folder that holds `.temper/` and `.claude/` (an absolute path under another folder finds none of them).
  runAt?: string
}

// The CLI moves the run to a stage (what a mirror call does): build-state.json next_stage. The mod
// reads it on its next refresh (a status command, a turn end).
export function cliTo(w: World, next: string): void {
  const d = JSON.parse(w.files.get('.temper/build-state.json') ?? '{}') as Record<string, unknown>
  w.files.set('.temper/build-state.json', JSON.stringify({ ...d, next_stage: next }))
}

// The stages of the CLI, in order (STAGE_SEQ_TEMPER in scripts/temper).
export const CLI_SEQ = ['intent', 'plan', 'design', 'build', 'review', 'check']

// The part of scripts/temper the mod depends on: `state advance <stage>_complete <next>` and
// `state set next_stage <stage>` against .temper/build-state.json. Same checks as cmd_state_advance.
// The script may be named by a quoted full path ("/a b/scripts/temper" state ...). Null for any other
// command (the stub answers it).
export function fakeCli(w: World, command: string): { result: string; text: string; isError?: boolean } | null {
  const path = '.temper/build-state.json'
  // A refused call (the CLI exits with an error): a test sets w.cliFailures to refuse the next calls.
  if (/scripts\/temper["']?\s+state\s+(?:advance|set)/.test(command) && (w.cliFailures ?? 0) > 0) {
    w.cliFailures = (w.cliFailures ?? 0) - 1
    return { result: 'FAIL: refused', text: 'FAIL: refused', isError: true }
  }
  // `git commit` that fails (an index lock, a hook): a test sets w.commitFailures to fail the next commits.
  if (/\bgit\s+commit\b/.test(command) && (w.commitFailures ?? 0) > 0) {
    w.commitFailures = (w.commitFailures ?? 0) - 1
    return { result: 'fatal: Unable to create index.lock', text: 'fatal: Unable to create index.lock', isError: true }
  }
  // `...; exit 1`: the call takes effect and the command still ends in an error (the engine reports isError).
  const failsAfter = /;\s*exit\s+[1-9]/.test(command)
  const read = (): Record<string, unknown> => JSON.parse(w.files.get(path) ?? '{}') as Record<string, unknown>
  const save = (d: Record<string, unknown>) => w.files.set(path, JSON.stringify(d))
  const adv = /scripts\/temper["']?\s+state\s+advance\s+([^\s;]+)\s+([^\s;]+)/.exec(command)
  if (adv) {
    const [, stage, next] = adv as unknown as [string, string, string]
    if (!CLI_SEQ.some(s => stage === `${s}_complete`) && stage !== 'started') return { result: `FAIL: unknown stage '${stage}'`, text: `FAIL: unknown stage '${stage}'`, isError: true }
    save({ ...read(), stage, next_stage: next })
    // `...; exit 1`: the call took effect and the command still ends in an error (the engine reports isError).
    return { result: `OK: advanced to ${stage} (next: ${next})`, text: `OK: advanced to ${stage} (next: ${next})`, ...(failsAfter ? { isError: true } : {}) }
  }
  // `git checkout -b <branch>`: the current branch changes.
  const checkout = /\bgit\s+checkout\s+-b\s+(\S+)/.exec(command)
  if (checkout) {
    w.files.set('/repo/.git/HEAD', `ref: refs/heads/${checkout[1]}\n`)
    return { result: `Switched to a new branch '${checkout[1]}'`, text: `Switched to a new branch '${checkout[1]}'` }
  }
  const set = /scripts\/temper["']?\s+state\s+set\s+next_stage\s+([^\s;]+)/.exec(command)
  if (set) {
    save({ ...read(), next_stage: set[1] })
    return { result: `OK: next_stage = ${set[1]}`, text: `OK: next_stage = ${set[1]}`, ...(failsAfter ? { isError: true } : {}) }
  }
  return failsAfter ? { result: 'exit 1', text: 'exit 1', isError: true } : null
}

export const denyText = (r: { deny?: string }): string => r.deny ?? ''

// The engine hands fs hooks absolute paths under the session's directory; the test world
// keys files by their project relative path. The last .temper/ or .claude/ folder in the path
// starts the key, so a checkout that itself sits under a .claude folder (a git worktree in
// .claude/worktrees) keys its files the same way.
const rel = (p: string): string => {
  const at = [...p.matchAll(/(?:^|\/)(?=\.(?:temper|claude)\/)/g)].pop()
  return at === undefined ? p : p.slice(at.index + at[0].length)
}

export function world(on: On, files: Record<string, string> = {}, opts: WorldOptions = {}): World {
  const w: World = { files: new Map(Object.entries(files)), writes: [], fsWrites: [], reads: [], prompts: [], rawPaths: [], commandRuns: [], filled: [], asked: [], answers: [...(opts.answers ?? [])], toasts: [], opened: [], openArgs: [], closed: [], invalidated: 0, suggestions: [], rows: [...(opts.rows ?? [])], configSets: [], rendered: [], store: { ...(opts.store ?? {}) } }
  const panes = new Map<string, boolean>()
  // The plugin store, in memory and live: a test reads what the mod stored from `w.store`.
  // The mod keeps its records (events, the report) in the store as `vf:<full path>` (see makeIo). The world
  // shows each one in `w.files` and `w.writes` too, so a test reads what the mod recorded the same way for
  // a kept text and for a file, and `failWrites` fails a kept text as it fails a file write.
  on('store.get', ($, e) => ({ value: w.store[e.key] }))
  on('store.set', ($, e) => {
    if (e.key.startsWith('vf:')) {
      if (w.failWrites) return { deny: `EACCES: ${e.key.slice(3)}` }
      w.files.set(rel(e.key.slice(3)), String(e.value))
      w.writes.push(rel(e.key.slice(3)))
    }
    w.store[e.key] = e.value
    return { value: undefined }
  })
  on('store.delete', ($, e) => {
    if (e.key.startsWith('vf:')) w.files.delete(rel(e.key.slice(3)))
    delete w.store[e.key]
    return { value: undefined }
  })
  on('store.keys', () => ({ value: Object.keys(w.store) }))
  // With `projectRoot` set, only files under it exist. A relative path is read from the folder the
  // engine is in now (`w.cwdNow`, as after a `cd` in a Bash call), so a read that forgot the project
  // root finds nothing, as it does in a real session.
  const outside = (path: string): boolean => {
    if (!opts.projectRoot) return false
    const full = path.startsWith('/') ? path : `${w.cwdNow ?? opts.projectRoot}/${path}`
    return !(full === opts.projectRoot || full.startsWith(`${opts.projectRoot}/`))
  }
  // With `runAt` set, `.temper/` and `.claude/` exist only directly under it.
  const elsewhere = (path: string): boolean => !!opts.runAt && path.startsWith('/') && /\/\.(?:temper|claude)\//.test(path) && !new RegExp(`^${opts.runAt}/\\.(?:temper|claude)/`).test(path)
  on('fs.read', ($, e) => {
    w.rawPaths.push(e.path)
    w.reads.push(rel(e.path))
    if (outside(e.path) || elsewhere(e.path)) return { deny: `ENOENT: ${e.path}` }
    if (w.unreadable?.has(rel(e.path))) return { deny: `EACCES: ${e.path}` }
    const text = w.files.get(rel(e.path))
    return text === undefined ? { deny: `ENOENT: ${e.path}` } : { value: text }
  })
  on('fs.write', ($, e) => {
    w.rawPaths.push(e.path)
    w.fsWrites.push(e.path)
    if (outside(e.path) || w.failWrites) return { deny: `EACCES: ${e.path}` }
    w.files.set(rel(e.path), e.text)
    w.writes.push(rel(e.path))
    return { value: undefined }
  })
  on('fs.list', ($, e) => {
    w.rawPaths.push(e.path)
    if (outside(e.path)) return { deny: `ENOENT: ${e.path}` }
    if (opts.brokenList) return { value: 5 as never }
    const prefix = rel(e.path).replace(/\/$/, '') + '/'
    const names = [...w.files.keys()].filter(k => k.startsWith(prefix) && !k.slice(prefix.length).includes('/'))
    if (names.length === 0) return { deny: `ENOENT: ${e.path}` }
    return { value: names.map(k => ({ name: k.slice(prefix.length), kind: 'file' as const, size: 0, mtimeMs: 0, isLink: false })) }
  })
  on('fs.stat', ($, e) => ({ value: { kind: 'dir' as const, size: 0, mtimeMs: 0, isLink: false, realPath: opts.cwd ?? '/repo' } }))
  on('session.version', () => {
    if (opts.version === null) return { deny: 'no version' }
    const v = opts.version ?? '2.1.288'
    return { value: { version: v, base: v } }
  })
  // The engine's own drawing: `ref: 0` is the original, as the engine would draw it.
  on('ui.render', ($, e) => {
    w.rendered.push({ component: e.component, props: { ...e.props } })
    return { type: 'engine', ref: 0 } as never
  })
  on('config.list', () => ({ value: w.rows.map(r => ({ ...r, label: r.key, kind: 'choice' as const, provider: { plugin: 'temper', tier: 'user' as const } })) as never }))
  on('config.set', ($, e) => {
    // The harness has no implementation of its own to pass a config write to (it says a test
    // answers it here), so the world records the call and answers it. The mod itself never
    // hooks config.set; it only calls it, on the person's own mode or enforcement command or their
    // answer to the first run mode question.
    w.configSets.push({ key: e.key, value: e.value })
    return { value: e.value }
  })
  on('ui.open', ($, e) => {
    w.opened.push(e.id)
    w.openArgs.push({ id: e.id, focus: e.focus === true, closeOnEscape: e.closeOnEscape === true })
    panes.set(e.id, e.focus === true && opts.grantFocus === true)
    return { value: opts.placed === false ? { isPlaced: false as const, reason: 'narrow' } : { isPlaced: true as const } } as never
  })
  on('ui.close', ($, e) => {
    w.closed.push(e.id)
    panes.delete(e.id)
    return { value: undefined }
  })
  // The open panes and whether each holds the keyboard.
  on('ui.panes', () => ({ value: [...panes].map(([id, isFocused]) => ({ id, title: id, isShown: true, isFocused, isPlaced: true })) as never }))
  on('ui.toast', ($, e) => {
    w.toasts.push(e.text)
    return { value: undefined }
  })
  on('ui.invalidate', () => {
    w.invalidated += 1
    return { value: undefined }
  })
  on('prompt.suggest', ($, e) => {
    w.suggestions.push(e.text)
    return { isShown: true } as never
  })
  // The engine's own tool.call: reaching it means the plugin let the call through.
  on('tool.call', ($, e) => {
    if (e.tool === 'AskUserQuestion') {
      const questions = (e as unknown as { questions?: Array<{ question: string }> }).questions ?? []
      const question = questions[0]?.question ?? ''
      w.asked.push(question)
      const answer = w.answers.shift()
      if (answer === undefined) return { deny: 'no one to ask' }
      return { result: { questions, answers: { [question]: answer } }, text: answer } as never
    }
    if (opts.fakeCli && e.tool === 'Bash') {
      const out = fakeCli(w, String((e as unknown as { command?: string }).command ?? ''))
      if (out !== null) return out as never
    }
    return { result: 'stub ran', text: 'stub ran' } as never
  })
  on('prompt.submit', ($, e) => {
    w.prompts.push(e.text)
    return { text: e.text }
  })
  on('prompt.fill', ($, e) => {
    if (opts.fillable === false) return { isFilled: false, refusal: 'dialog', draft: { text: '', cursor: 0 } } as never
    w.filled.push({ text: e.text, mode: e.mode })
    return { isFilled: true, draft: { text: e.text, cursor: e.text.length } } as never
  })
  on('attribution.text', ($, e) => ({ text: e.text }))
  on('command.run', ($, e) => {
    w.commandRuns.push({ command: e.command, args: e.args, origin: (e.origin as { kind?: string } | undefined)?.kind ?? '' })
    return { text: 'prompt based /temper:temper ran' }
  })
  on('prompt.compose', () => ({ sections: [{ id: 'intro', text: 'You are Claude.', scope: 'shared' as const }] }))
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  on('classic.SessionStart', () => ({}))
  return w
}

// A full prompt.compose input, as the engine builds one.
export const COMPOSE = { model: 'm', promptModel: 'm', surfaces: [], tools: [], outputStyle: null, traits: [] } as const
