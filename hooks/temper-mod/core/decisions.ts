// The person's decisions (ADR 0012). Each one comes from the result of a question dialog the person answered (a
// `Temper gate`, `Temper resume` or `Scope drift` question), never from what Claude sends, and the mod keeps it in its
// own store, stamped with the CLI's run id and step. A decision counts only for that run, and a move only at that step:
// when the CLI moves the run on, back, or starts a new one, the decision is spent by itself. Pure.

import type { Stage } from './stages'
import { isStage } from './stages'

// A move decides how the run goes on from the step it is at; the latest move at a step replaces the earlier ones.
//  approve         leave Intent or Plan (Continue, or the arming answer "Stage by stage")
//  advance         go on from a stage that follows its own verdict (Continue after Build, Review or Check; Commit)
//  override        skip the stage with a reason
//  back            go back to an earlier stage, with a reason (`to`)
//  arm             "Autonomous": approve the plan and arm the run
//  pause           Save for later: the person has control until the run moves on
//  keep            keep a task agent's commits in a parked group, with a reason
//  commitOverride  after the run is done, the person's Override and commit, with a reason
export type MoveKind = 'approve' | 'advance' | 'override' | 'back' | 'arm' | 'pause' | 'keep' | 'commitOverride'

export type DriftChoice = 'add' | 'revert' | 'allow-once'

type Stamp = { id: string; run: string; step: number; stage: Stage; ts: number }

export type Decision =
  | (Stamp & { kind: MoveKind; reason: string; to?: Stage })
  // An accepted review finding: counts at its step, for that finding.
  | (Stamp & { kind: 'accept'; findingId: string; reason: string })
  // Start over: the saved run state may go, until the next state init begins a new run.
  | (Stamp & { kind: 'restart'; reason: string })
  // A Scope drift answer: counts for the run and the path. Allow once is used by one write.
  | (Stamp & { kind: 'drift'; path: string; choice: DriftChoice; reason: string })

export type Move = Extract<Decision, { kind: MoveKind }>

// Where the CLI is: the run and the step a new decision is stamped with, and old ones are read against.
export type At = { run: string; step: number }

const MOVES: ReadonlySet<string> = new Set(['approve', 'advance', 'override', 'back', 'arm', 'pause', 'keep', 'commitOverride'])

export const isMove = (d: Decision): d is Move => MOVES.has(d.kind)

const latestFirst = (a: Decision, b: Decision): number => b.ts - a.ts

// The move that counts now: the latest one made at the CLI's run and step. `used` holds the ids already spent (keep).
export function currentMove(book: readonly Decision[], at: At, used: ReadonlySet<string> = new Set()): Move | null {
  const hit = book.filter(isMove).filter(d => d.run === at.run && d.step === at.step).sort(latestFirst)[0] ?? null
  return hit !== null && !used.has(hit.id) ? hit : null
}

// The findings the person accepted at this step.
export function acceptsAt(book: readonly Decision[], at: At): Array<Extract<Decision, { kind: 'accept' }>> {
  return book.filter((d): d is Extract<Decision, { kind: 'accept' }> => d.kind === 'accept' && d.run === at.run && d.step === at.step)
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
  const why = 'reason' in d && d.reason ? ` (${d.reason})` : ''
  switch (d.kind) {
    case 'approve':
      return `approved ${d.stage}`
    case 'advance':
      return `went on from ${d.stage}`
    case 'override':
      return `skipped ${d.stage}${why}`
    case 'back':
      return `went back from ${d.stage} to ${d.to ?? '?'}${why}`
    case 'arm':
      return `armed the autonomous run at ${d.stage}`
    case 'pause':
      return `saved the run for later at ${d.stage}`
    case 'keep':
      return `kept a task agent's commits${why}`
    case 'commitOverride':
      return `overrode the commit gate${why}`
    case 'accept':
      return `accepted finding ${d.findingId}${why}`
    case 'restart':
      return `started over${why}`
    case 'drift': {
      const word = d.choice === 'add' ? 'added to the plan' : d.choice === 'revert' ? 'reverted' : 'allowed once'
      return `${d.path}: ${word}${why}`
    }
  }
}

// The decisions kept in the store, from what the store holds: anything that is not a well formed decision is left out.
export function parseBook(raw: unknown): Decision[] {
  if (!Array.isArray(raw)) return []
  return raw.filter((d): d is Decision => {
    if (typeof d !== 'object' || d === null) return false
    const o = d as Record<string, unknown>
    if (!(typeof o.id === 'string' && typeof o.run === 'string' && typeof o.step === 'number' && typeof o.stage === 'string' && isStage(o.stage) && typeof o.ts === 'number')) return false
    if (typeof o.reason !== 'string') return false
    if (o.kind === 'back') return typeof o.to === 'string' && isStage(o.to)
    if (typeof o.kind === 'string' && MOVES.has(o.kind)) return true
    if (o.kind === 'accept') return typeof o.findingId === 'string'
    if (o.kind === 'restart') return true
    if (o.kind === 'drift') return typeof o.path === 'string' && (o.choice === 'add' || o.choice === 'revert' || o.choice === 'allow-once')
    return false
  })
}
