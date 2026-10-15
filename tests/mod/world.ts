// Test world: the fake engine beneath the plugin's tests. This file is test only: it runs under
// `claude plugin test` and is never loaded in a session. Files live in a Map the fs.* hooks answer
// from; a file write records back into it.
import type { On } from 'claude-code'

import { deriveView, planFiles } from './run-files'

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
  // How many of the next `state advance|set|clear` calls the fake CLI refuses (see fakeCli).
  cliFailures?: number
  // How many of the next `git commit` calls the fake CLI fails (see fakeCli).
  commitFailures?: number
  // True: the fake CLI prints BLOCKED for `state loop` (the loop budget is spent), as cmd_state_loop does.
  loopsBlocked?: boolean
  // The folder the engine is in now, after a `cd` (see WorldOptions.projectRoot).
  cwdNow?: string
  // Commands that reached the engine's own command run (after the plugin's hooks), in order.
  commandRuns: Array<{ command: string; args: string; origin: string }>
  // Drafts the mod put in the prompt box (`$.prompt.fill`), in order.
  filled: Array<{ text: string; mode: string | undefined }>
  // Questions the mod asked the person through the engine's dialog, in order, and the options of each.
  asked: string[]
  askedOptions: string[][]
  // Answers the person gives, in order; empty means nobody answers (a `-p` run). An answer with a note is the person's
  // note on the option (the dialog's annotation).
  answers: Answer[]
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

export type Answer = string | { label: string; note: string }

export type WorldOptions = {
  version?: string | null
  cwd?: string
  // Initial store entries (the mod's own event ids live under `ev:`).
  store?: Record<string, unknown>
  // Answers the person gives to the mod's questions, in order.
  answers?: Answer[]
  // Config rows the mod can list; a locked one is an administrator's.
  rows?: Array<{ key: string; value: string; isLocked: boolean }>
  // False answers every pane open with "not placed" (a narrow terminal).
  placed?: boolean
  // True: the surface grants the keyboard to a pane that asks for it (an empty composer).
  // Left out: it refuses, as it does while the composer holds text.
  grantFocus?: boolean
  // Answer every directory listing with something that is not a list.
  brokenList?: boolean
  // False: the prompt box refuses a draft (a dialog holds the keys).
  fillable?: boolean
  // Only files under this folder exist (see `outside`); a relative path is read from `w.cwdNow`.
  projectRoot?: string
  // True: the engine's Bash runs `scripts/temper state advance|set|clear` against .temper/build-state.json
  // like the real CLI does (see fakeCli).
  fakeCli?: boolean
  // The folder that holds `.temper/` and `.claude/` (an absolute path under another folder finds none of them).
  runAt?: string
}

// The CLI moves the run to a stage: build-state.json next_stage, and the view it writes. The mod reads it on its next
// refresh (a status command, a turn end).
export function cliTo(w: World, next: string): void {
  const d = JSON.parse(w.files.get('.temper/build-state.json') ?? '{}') as Record<string, unknown>
  w.files.set('.temper/build-state.json', JSON.stringify({ ...d, next_stage: next }))
  w.files.delete('.temper/view.json')
}

// The view the CLI wrote for the run in the world: a view.json the test set, else the one the world makes from the CLI's
// state (deriveView).
export function viewText(w: World): string | null {
  return w.files.get('.temper/view.json') ?? deriveView(p => w.files.get(p))
}

// The stages of the CLI, in order (STAGE_SEQ_TEMPER in scripts/temper).
export const CLI_SEQ = ['intent', 'plan', 'design', 'build', 'review', 'check']

// The part of scripts/temper the mod depends on, with the same moves as the real CLI (ADR 0012): `state advance`,
// `state set`, `state loop`, `state clear|archive|init`, `override` and `evidence accept`, against the .temper files.
// Every change of next_stage counts one step; a step back removes the verdicts and the skips of the stages it redoes.
// The script may be named by a quoted full path ("/a b/scripts/temper" state ...). Null for any other command (the stub
// answers it).
const SEQ_ALL = [...CLI_SEQ, 'commit']

function redo(w: World, to: string): void {
  const from = SEQ_ALL.indexOf(to)
  if (from < 0) return
  const gone = new Set(SEQ_ALL.slice(from))
  const gates = JSON.parse(w.files.get('.temper/gates.json') ?? '{}') as Record<string, unknown>
  w.files.set('.temper/gates.json', JSON.stringify(Object.fromEntries(Object.entries(gates).filter(([k]) => !gone.has(k)))))
  if (w.files.has('.temper/overrides.json')) {
    const rows = JSON.parse(w.files.get('.temper/overrides.json') ?? '[]') as Array<{ stage?: string }>
    w.files.set('.temper/overrides.json', JSON.stringify(rows.filter(r => !gone.has(r.stage ?? ''))))
  }
}

export function fakeCli(w: World, command: string): { result: string; text: string; isError?: boolean } | null {
  const path = '.temper/build-state.json'
  // A refused call (the CLI exits with an error): a test sets w.cliFailures to refuse the next calls.
  if (/scripts\/temper["']?\s+state\s+(?:advance|set|clear)/.test(command) && (w.cliFailures ?? 0) > 0) {
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
  // A move of the CLI writes the view again: a view.json the test set gives way to the one made from the state.
  const save = (d: Record<string, unknown>) => {
    w.files.set(path, JSON.stringify(d))
    w.files.delete('.temper/view.json')
  }
  const ok = (text: string) => ({ result: text, text, ...(failsAfter ? { isError: true } : {}) })
  // Moves next_stage; a change counts one step.
  const move = (d: Record<string, unknown>, next: string): Record<string, unknown> =>
    d.next_stage === next ? d : { ...d, next_stage: next, step: (typeof d.step === 'number' ? d.step : 0) + 1 }
  const adv = /scripts\/temper["']?\s+state\s+advance\s+([^\s;]+)\s+([^\s;]+)/.exec(command)
  if (adv) {
    const [, stage, next] = adv as unknown as [string, string, string]
    if (!CLI_SEQ.some(s => stage === `${s}_complete`) && stage !== 'started') return { result: `FAIL: unknown stage '${stage}'`, text: `FAIL: unknown stage '${stage}'`, isError: true }
    // Leaving Plan records the files the person approved (approved_files), as the CLI does.
    const d = read()
    const spec = typeof d.spec_path === 'string' ? d.spec_path : '.temper/specs/pw'
    const approved = stage === 'plan_complete' ? { approved_files: planFiles(w.files.get(`${spec}/plan.md`) ?? '', w.files.get(`${spec}/tasks.md`) ?? '') } : {}
    save(move({ ...d, stage, ...approved }, next))
    return ok(`OK: advanced to ${stage} (next: ${next})`)
  }
  // `git checkout -b <branch>`: the current branch changes.
  const checkout = /\bgit\s+checkout\s+-b\s+(\S+)/.exec(command)
  if (checkout) {
    w.files.set('/repo/.git/HEAD', `ref: refs/heads/${checkout[1]}\n`)
    return { result: `Switched to a new branch '${checkout[1]}'`, text: `Switched to a new branch '${checkout[1]}'` }
  }
  // `state loop <from> <to>`: BLOCKED when the budget is spent (exit 1, nothing moves), else the run goes back to <to>.
  const loop = /scripts\/temper["']?\s+state\s+loop\s+([^\s;]+)\s+([^\s;]+)/.exec(command)
  // A loop chained with `; exit 1` stays the stand in for a call that failed and changed nothing (see hardening.test.ts).
  if (loop && !failsAfter) {
    if (w.loopsBlocked) {
      const text = `BLOCKED: max iterations (2) reached for ${loop[1]}->${loop[2]}`
      return { result: text, text, isError: true }
    }
    redo(w, loop[2] as string)
    save(move(read(), loop[2] as string))
    return { result: `OK: loop ${loop[1]}->${loop[2]} iteration 1/2`, text: `OK: loop ${loop[1]}->${loop[2]} iteration 1/2` }
  }
  const set = /scripts\/temper["']?\s+state\s+set\s+(\S+)\s+([^\s;]+)/.exec(command)
  if (set) {
    const [, key, value] = set as unknown as [string, string, string]
    const d = read()
    if (key === 'next_stage') {
      if (d.next_stage === value) return ok(`OK: next_stage = ${value} (unchanged)`)
      if (SEQ_ALL.indexOf(value) >= 0 && SEQ_ALL.indexOf(value) < SEQ_ALL.indexOf(String(d.next_stage))) redo(w, value)
      save(move(read(), value))
      return ok(`OK: next_stage = ${value}`)
    }
    save({ ...d, [key]: value })
    return ok(`OK: ${key} = ${value}`)
  }
  // `override <stage> --reason ..`: the skip is recorded.
  const skip = /scripts\/temper["']?\s+override\s+([^\s;]+)/.exec(command)
  if (skip) {
    const rows = JSON.parse(w.files.get('.temper/overrides.json') ?? '[]') as unknown[]
    w.files.set('.temper/overrides.json', JSON.stringify([...rows, { stage: skip[1], reason: 'r', by: 'u', ts: 't' }]))
    w.files.delete('.temper/view.json')
    return ok(`OK: override recorded for '${skip[1]}'`)
  }
  // `state clear` and `state archive`: the run state goes, as cmd_state_clear removes it (the spec folder stays).
  if (/scripts\/temper["']?\s+state\s+(?:clear|archive)\b/.test(command)) {
    for (const name of ['build-state.json', 'feedback-loops.json', 'gates.json', 'overrides.json', 'view.json']) w.files.delete(`.temper/${name}`)
    for (const key of [...w.files.keys()]) if (key.startsWith('.temper/evidence/')) w.files.delete(key)
    return ok('OK: run state cleared')
  }
  // `state init <slug>`: a new run, at step 0, with a new run id.
  const init = /scripts\/temper["']?\s+state\s+init\s+([^\s;]+)/.exec(command)
  if (init) {
    w.files.delete('.temper/gates.json')
    w.files.delete('.temper/overrides.json')
    w.files.delete('.temper/view.json')
    const slug = init[1] as string
    save({ stage: 'started', spec: slug, spec_path: `.temper/specs/${slug}`, command: 'temper', next_stage: 'intent', run_mode: 'interactive', run_id: `run-${Math.random().toString(16).slice(2, 10)}`, step: 0 })
    return ok(`OK: state initialized for ${slug}`)
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
  const w: World = { files: new Map(Object.entries(files)), writes: [], fsWrites: [], reads: [], prompts: [], rawPaths: [], commandRuns: [], filled: [], asked: [], askedOptions: [], answers: [...(opts.answers ?? [])], toasts: [], opened: [], openArgs: [], closed: [], invalidated: 0, suggestions: [], rows: [...(opts.rows ?? [])], configSets: [], rendered: [], store: { ...(opts.store ?? {}) } }
  const panes = new Map<string, boolean>()
  // The plugin store, in memory and live: a test reads what the mod stored from `w.store`.
  // The mod keeps its records (events, the report) in the store as `vf:<full path>` (see makeIo). The world
  // shows each one in `w.files` and `w.writes` too, so a test reads what the mod recorded the same way for
  // a kept text and for a file, and `failWrites` fails every store write as it fails a file write.
  on('store.get', ($, e) => ({ value: w.store[e.key] }))
  on('store.set', ($, e) => {
    if (w.failWrites) return { deny: `EACCES: ${e.key.startsWith('vf:') ? e.key.slice(3) : e.key}` }
    if (e.key.startsWith('vf:')) {
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
    // The view the CLI writes after every change: read as the CLI's state stands now, unless the test set one. An
    // unreadable run state stands for a view that cannot be read either.
    if (rel(e.path) === '.temper/view.json') {
      if (w.unreadable?.has('.temper/build-state.json')) return { deny: `EACCES: ${e.path}` }
      const text = viewText(w)
      return text === null ? { deny: `ENOENT: ${e.path}` } : { value: text }
    }
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
      w.askedOptions.push((questions[0] as { options?: Array<{ label?: string }> } | undefined)?.options?.map(o => o.label ?? '') ?? [])
      const answer = w.answers.shift()
      if (answer === undefined) return { deny: 'no one to ask' }
      const label = typeof answer === 'string' ? answer : answer.label
      const annotations = typeof answer === 'string' ? {} : { annotations: { [question]: { notes: answer.note } } }
      return { result: { questions, answers: { [question]: label }, ...annotations }, text: label } as never
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
