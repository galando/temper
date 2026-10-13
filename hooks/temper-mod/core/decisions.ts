// The person's decisions (ADR 0012, ADR 0013). Each one is an answer read from the result of a question dialog the
// person answered (core/answers.ts), never from what Claude sends, and the mod keeps it in its own store, stamped with
// the CLI's run id and step. A gate answer counts only at that step: when the CLI moves the run on, back, or starts a new
// one, it is spent by itself. Pure.

import type { DriftChoice } from './answers'

type Stamp = { id: string; run: string; step: number; stage: string; ts: number }

export type Decision =
  // A gate answer: the option's label and move, and the exact calls and steps it maps to.
  // `ask`: the CLI's question it answered (a step may ask more than one: Build's groups, an accepted finding).
  | (Stamp & { kind: 'gate'; label: string; move: string; calls: string[]; steps: string[]; reason: string; ask?: string })
  // Start over: the saved run state may go, until the next state init begins a new run.
  | (Stamp & { kind: 'restart'; calls: string[]; reason: string })
  // A Scope drift answer: counts for the run and the path. Allow once is used by one write.
  | (Stamp & { kind: 'drift'; path: string; choice: DriftChoice; reason: string })

// Where the CLI is: the run and the step a new decision is stamped with, and old ones are read against.
export type At = { run: string; step: number }

const latestFirst = (a: Decision, b: Decision): number => b.ts - a.ts

type Gate = Extract<Decision, { kind: 'gate' }>

const gatesAt = (book: readonly Decision[], at: At): Gate[] =>
  book.filter((d): d is Gate => d.kind === 'gate' && d.run === at.run && d.step === at.step).sort(latestFirst)

// The answer that counts now: the latest gate answer at the CLI's run and step, to the question the CLI asks now. While
// no question is asked (Claude carries the answer out) the latest answer at the step counts.
export const currentAnswer = (book: readonly Decision[], at: At, asked: string | null = null): Gate | null => {
  const latest = gatesAt(book, at)[0] ?? null
  return latest !== null && asked !== null && latest.ask !== undefined && latest.ask !== asked ? null : latest
}

// The calls the person's answers allow at this step: those of the latest answer, and of every finding accepted at it.
export function allowedCalls(book: readonly Decision[], at: At): string[] {
  const gates = gatesAt(book, at)
  const counted = [...(gates[0] ? [gates[0]] : []), ...gates.slice(1).filter(d => d.move === 'accept')]
  return counted.flatMap(d => [...d.calls, ...d.steps])
}

// The person's Start over for this run, if any.
export function restartFor(book: readonly Decision[], run: string): Extract<Decision, { kind: 'restart' }> | null {
  return book.filter((d): d is Extract<Decision, { kind: 'restart' }> => d.kind === 'restart' && d.run === run).sort(latestFirst)[0] ?? null
}

export type DriftState = { added: string[]; allowOnce: Array<{ id: string; path: string }> }

// The Scope drift answers of this run: the paths added to the plan, and the Allow once answers not used yet. The last
// answer for a path is the one that counts.
export function driftOf(book: readonly Decision[], run: string, used: ReadonlySet<string>): DriftState {
  const last = new Map<string, Extract<Decision, { kind: 'drift' }>>()
  for (const d of [...book].sort((a, b) => a.ts - b.ts)) if (d.kind === 'drift' && d.run === run) last.set(d.path, d)
  const out: DriftState = { added: [], allowOnce: [] }
  for (const d of last.values()) {
    if (d.choice === 'add') out.added.push(d.path)
    if (d.choice === 'allow-once' && !used.has(d.id)) out.allowOnce.push({ id: d.id, path: d.path })
  }
  return out
}

// The decisions of one run, oldest first: the report and the pane list them.
export const decisionsOf = (book: readonly Decision[], run: string): Decision[] => book.filter(d => d.run === run).sort((a, b) => a.ts - b.ts)

// How a decision reads in the report, the pane and `/temper:temper timeline`.
export function describe(d: Decision): string {
  const why = d.reason ? ` (${d.reason})` : ''
  switch (d.kind) {
    case 'gate':
      return `${d.stage}: ${d.label}${why}`
    case 'restart':
      return `started over${why}`
    case 'drift': {
      const word = d.choice === 'add' ? 'added to the plan' : d.choice === 'revert' ? 'reverted' : 'allowed once'
      return `${d.path}: ${word}${why}`
    }
  }
}

const strings = (v: unknown): v is string[] => Array.isArray(v) && v.every(x => typeof x === 'string')

// The decisions kept in the store, from what the store holds: anything that is not a well formed decision is left out.
export function parseBook(raw: unknown): Decision[] {
  if (!Array.isArray(raw)) return []
  return raw.filter((d): d is Decision => {
    if (typeof d !== 'object' || d === null) return false
    const o = d as Record<string, unknown>
    if (!(typeof o.id === 'string' && typeof o.run === 'string' && typeof o.step === 'number' && typeof o.stage === 'string' && typeof o.ts === 'number')) return false
    if (typeof o.reason !== 'string') return false
    if (o.kind === 'gate') return typeof o.label === 'string' && typeof o.move === 'string' && strings(o.calls) && strings(o.steps) && (o.ask === undefined || typeof o.ask === 'string')
    if (o.kind === 'restart') return strings(o.calls)
    if (o.kind === 'drift') return typeof o.path === 'string' && (o.choice === 'add' || o.choice === 'revert' || o.choice === 'allow-once')
    return false
  })
}
