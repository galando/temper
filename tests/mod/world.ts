// Test world: stands in for the engine beneath the plugin. Files live in a Map the
// fs.* hooks answer from; fs.write records back into it. Not a test file.
import { mock } from 'claude-code/testing'
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
}

export type WorldOptions = {
  version?: string | null
  cwd?: string
  // Initial store entries (the mod's own event ids live under `ev:`).
  store?: Record<string, unknown>
  // Answers the person gives to the mod's questions, in order.
  answers?: string[]
  // Answer every directory listing with something that is not a list.
  brokenList?: boolean
}

export const denyText = (r: { deny?: string }): string => r.deny ?? ''

// The engine hands fs hooks absolute paths under the session's directory; the test world
// keys files by their project relative path.
const rel = (p: string): string => /(?:^|\/)((?:\.temper|\.claude)\/.*)$/.exec(p)?.[1] ?? p

export function world(on: On, files: Record<string, string> = {}, opts: WorldOptions = {}): World {
  const w: World = { files: new Map(Object.entries(files)), writes: [], reads: [], prompts: [], asked: [], answers: [...(opts.answers ?? [])], store: { ...(opts.store ?? {}) } }
  mock.store(on, w.store)
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
  on('command.run', () => ({ text: 'prompt based /temper ran' }))
  on('prompt.compose', () => ({ sections: [{ id: 'intro', text: 'You are Claude.', scope: 'shared' as const }] }))
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  on('classic.SessionStart', () => ({}))
  return w
}

// A full prompt.compose input, as the engine builds one.
export const COMPOSE = { model: 'm', promptModel: 'm', surfaces: [], tools: [], outputStyle: null, traits: [] } as const
