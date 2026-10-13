// The person's decisions (ADR 0012), pure: a move counts only at its run and step, the latest move at a step wins, an
// accept counts at its step for its finding, a drift answer counts for the run and the path, and a spent decision is
// spent. What the store holds is read strictly: a malformed record is no decision.
import { describe, expect, test } from 'claude-code/testing'

import type { Decision } from '../../hooks/temper-mod/core/decisions'
import { acceptsAt, currentMove, decisionsOf, describe as describeDecision, driftOf, parseBook, restartFor } from '../../hooks/temper-mod/core/decisions'

const at = { run: 'r1', step: 4 }
const d = (over: Partial<Decision> & { kind: Decision['kind'] }): Decision => ({ id: `d${Math.random().toString(36).slice(2, 8)}`, run: 'r1', step: 4, stage: 'review', ts: 10, reason: '', ...over }) as Decision

describe('currentMove: the move made at the CLI run and step', () => {
  test('a move at this run and step counts', () => {
    const m = d({ kind: 'override', reason: 'x' })
    expect(currentMove([m], at)?.id).toBe(m.id)
  })
  test('a move of an earlier step does not count', () => {
    expect(currentMove([d({ kind: 'override', step: 3, reason: 'x' })], at)).toBeNull()
  })
  test('a move of another run does not count, at the same step', () => {
    expect(currentMove([d({ kind: 'override', run: 'r0', reason: 'x' })], at)).toBeNull()
  })
  test('the latest move at the step replaces the earlier ones', () => {
    const back = d({ kind: 'back', to: 'build', reason: 'bug', ts: 10 })
    const skip = d({ kind: 'override', reason: 'by hand', ts: 20 })
    expect(currentMove([skip, back], at)?.kind).toBe('override')
  })
  test('an accept, a restart or a drift answer is not a move', () => {
    expect(currentMove([d({ kind: 'accept', findingId: '1', reason: 'x' }), d({ kind: 'restart', reason: 'x' })], at)).toBeNull()
  })
  test('a spent move is no move, and does not let an older one through', () => {
    const keep = d({ kind: 'keep', reason: 'x', ts: 20 })
    const older = d({ kind: 'override', reason: 'x', ts: 10 })
    expect(currentMove([older, keep], at, new Set([keep.id]))).toBeNull()
  })
})

describe('acceptsAt and restartFor', () => {
  test('an accept counts at its step only', () => {
    const now = d({ kind: 'accept', findingId: '2', reason: 'x' })
    const before = d({ kind: 'accept', findingId: '1', step: 3, reason: 'x' })
    expect(acceptsAt([now, before], at).map(a => a.findingId)).toEqual(['2'])
  })
  test('a restart counts for its run at any step, and not for another run', () => {
    expect(restartFor([d({ kind: 'restart', step: 1, reason: 'x' })], 'r1')).not.toBeNull()
    expect(restartFor([d({ kind: 'restart', reason: 'x' })], 'r2')).toBeNull()
  })
})

describe('driftOf: the Scope drift answers of the run', () => {
  test('the last answer for a path is the one that counts', () => {
    const book = [d({ kind: 'drift', path: 'src/a.ts', choice: 'add', ts: 1 }), d({ kind: 'drift', path: 'src/a.ts', choice: 'revert', ts: 2 })]
    expect(driftOf(book, 'r1', new Set())).toEqual({ added: [], allowOnce: [] })
  })
  test('an added path counts at every step of the run', () => {
    expect(driftOf([d({ kind: 'drift', path: 'src/a.ts', choice: 'add', step: 1 })], 'r1', new Set()).added).toEqual(['src/a.ts'])
  })
  test('Allow once is there until it is used', () => {
    const once = d({ kind: 'drift', path: 'src/a.ts', choice: 'allow-once' })
    expect(driftOf([once], 'r1', new Set()).allowOnce).toEqual([{ id: once.id, path: 'src/a.ts' }])
    expect(driftOf([once], 'r1', new Set([once.id])).allowOnce).toEqual([])
  })
  test('another run\'s answers do not count', () => {
    expect(driftOf([d({ kind: 'drift', path: 'src/a.ts', choice: 'add', run: 'r0' })], 'r1', new Set()).added).toEqual([])
  })
})

describe('parseBook: only well formed decisions', () => {
  const good = { id: 'a', run: 'r1', step: 1, stage: 'plan', ts: 1, kind: 'approve', reason: '' }
  test('a well formed record is kept', () => {
    expect(parseBook([good])).toHaveLength(1)
  })
  const bad: Record<string, unknown> = {
    'not a list': { ...good },
    'an unknown kind': [{ ...good, kind: 'approve-all' }],
    'an unknown stage': [{ ...good, stage: 'fix' }],
    'a step that is no number': [{ ...good, step: '1' }],
    'no reason': [{ ...good, reason: undefined }],
    'a step back with no target': [{ ...good, kind: 'back' }],
    'a step back to no stage': [{ ...good, kind: 'back', to: 'nowhere' }],
    'an accept with no finding': [{ ...good, kind: 'accept' }],
    'a drift answer with no path': [{ ...good, kind: 'drift', choice: 'add' }],
    'a drift answer with an unknown choice': [{ ...good, kind: 'drift', path: 'a', choice: 'ignore' }],
  }
  for (const [name, raw] of Object.entries(bad)) test(`${name}: no decision`, () => expect(parseBook(raw)).toEqual([]))
})

describe('the words a decision reads as', () => {
  test('each kind names what the person chose', () => {
    expect(describeDecision(d({ kind: 'back', stage: 'check', to: 'build', reason: 'flaky' }))).toBe('went back from check to build (flaky)')
    expect(describeDecision(d({ kind: 'override', stage: 'review', reason: 'by hand' }))).toBe('skipped review (by hand)')
    expect(describeDecision(d({ kind: 'approve', stage: 'plan' }))).toBe('approved plan')
    expect(describeDecision(d({ kind: 'drift', path: 'src/a.ts', choice: 'allow-once', reason: '' }))).toBe('src/a.ts: allowed once')
  })
  test('decisionsOf lists one run, oldest first', () => {
    const a = d({ kind: 'approve', stage: 'intent', ts: 5 })
    const b = d({ kind: 'approve', stage: 'plan', ts: 3 })
    expect(decisionsOf([a, b, d({ kind: 'pause', run: 'r0' })], 'r1').map(x => x.id)).toEqual([b.id, a.id])
  })
})
