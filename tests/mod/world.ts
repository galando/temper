// Test world: stands in for the engine beneath the plugin. Files live in a Map the
// fs.* hooks answer from; fs.write records back into it. Not a test file.
import type { On } from 'claude-code'

export type World = {
  files: Map<string, string>
  writes: string[]
  reads: string[]
  store: Record<string, unknown>
  // Prompts the mod submitted to Claude, in order.
  prompts: string[]
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
}

export const denyText = (r: { deny?: string }): string => r.deny ?? ''

// The engine hands fs hooks absolute paths under the session's directory; the test world
// keys files by their project relative path.
const rel = (p: string): string => /(?:^|\/)((?:\.temper|\.claude)\/.*)$/.exec(p)?.[1] ?? p

export function world(on: On, files: Record<string, string> = {}, opts: WorldOptions = {}): World {
  const w: World = { files: new Map(Object.entries(files)), writes: [], reads: [], prompts: [], asked: [], answers: [...(opts.answers ?? [])], toasts: [], opened: [], openArgs: [], closed: [], invalidated: 0, suggestions: [], rows: [...(opts.rows ?? [])], configSets: [], rendered: [], store: { ...(opts.store ?? {}) } }
  const panes = new Map<string, boolean>()
  // The plugin store, in memory and live: a test reads what the mod stored from `w.store`.
  on('store.get', ($, e) => ({ value: w.store[e.key] }))
  on('store.set', ($, e) => {
    w.store[e.key] = e.value
    return { value: undefined }
  })
  on('store.delete', ($, e) => {
    delete w.store[e.key]
    return { value: undefined }
  })
  on('store.keys', () => ({ value: Object.keys(w.store) }))
  on('fs.read', ($, e) => {
    w.reads.push(rel(e.path))
    const text = w.files.get(rel(e.path))
    return text === undefined ? { deny: `ENOENT: ${e.path}` } : { value: text }
  })
  on('fs.write', ($, e) => {
    w.files.set(rel(e.path), e.text)
    w.writes.push(rel(e.path))
    return { value: undefined }
  })
  on('fs.list', ($, e) => {
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
    return { result: 'stub ran', text: 'stub ran' } as never
  })
  on('prompt.submit', ($, e) => {
    w.prompts.push(e.text)
    return { text: e.text }
  })
  on('attribution.text', ($, e) => ({ text: e.text }))
  on('command.run', () => ({ text: 'prompt based /temper:temper ran' }))
  on('prompt.compose', () => ({ sections: [{ id: 'intro', text: 'You are Claude.', scope: 'shared' as const }] }))
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  on('classic.SessionStart', () => ({}))
  return w
}

// A full prompt.compose input, as the engine builds one.
export const COMPOSE = { model: 'm', promptModel: 'm', surfaces: [], tools: [], outputStyle: null, traits: [] } as const
