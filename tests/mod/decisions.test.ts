// The person's decisions (ADR 0013), pure: a gate answer counts only at its run and step, the latest answer at a step
// wins (an accepted finding keeps counting beside it), a drift answer counts for the run and the path, and a spent Allow
// once is spent. What the store holds is read strictly: a malformed record is no decision.
import { describe, expect, test } from 'claude-code/testing'

import type { Decision } from '../../hooks/temper-mod/core/decisions'
import { allowedCalls, currentAnswer, decisionsOf, describe as describeDecision, driftOf, parseBook, restartFor } from '../../hooks/temper-mod/core/decisions'

const at = { run: 'r1', step: 4 }
const d = (over: Record<string, unknown> & { kind: Decision['kind'] }): Decision =>
  ({ id: `d${Math.random().toString(36).slice(2, 8)}`, run: 'r1', step: 4, stage: 'review', ts: 10, reason: '', ...over }) as Decision
const gate = (label: string, move: string, calls: string[], over: Record<string, unknown> = {}): Decision => d({ kind: 'gate', label, move, calls, steps: [], ...over })

describe('currentAnswer: the gate answer made at the CLI run and step', () => {
  test('an answer at this run and step counts', () => {
    const m = gate('Override and continue', 'override', ['t override review --reason "{reason}"'], { reason: 'x' })
    expect(currentAnswer([m], at)?.id).toBe(m.id)
  })
  test('an answer of an earlier step does not count', () => {
    expect(currentAnswer([gate('Override and continue', 'override', [], { step: 3 })], at)).toBeNull()
  })
  test('an answer of another run does not count, at the same step', () => {
    expect(currentAnswer([gate('Override and continue', 'override', [], { run: 'r0' })], at)).toBeNull()
  })
  test('the latest answer at the step replaces the earlier ones', () => {
    const back = gate('Loop back to Build', 'back', [], { ts: 10 })
    const skip = gate('Override and continue', 'override', [], { ts: 20 })
    expect(currentAnswer([skip, back], at)?.label).toBe('Override and continue')
  })
  test('a restart or a drift answer is not a gate answer', () => {
    expect(currentAnswer([d({ kind: 'restart', calls: [] }), d({ kind: 'drift', path: 'a', choice: 'add' })], at)).toBeNull()
  })
})

describe('allowedCalls: what the answers at this step let through', () => {
  test('the latest answer\'s calls and steps', () => {
    const m = gate('Commit', 'advance', ['t gate commit'], { steps: ['git add -- x', 't state clear'] })
    expect(allowedCalls([m], at)).toEqual(['t gate commit', 'git add -- x', 't state clear'])
  })
  test('an earlier answer at the step gives way to the latest, but an accepted finding keeps counting', () => {
    const acc1 = gate('Accept finding 1', 'accept', ['t evidence accept --stage review --id 1 --reason "{reason}"'], { ts: 1 })
    const acc2 = gate('Accept finding 2', 'accept', ['t evidence accept --stage review --id 2 --reason "{reason}"'], { ts: 2 })
    const back = gate('Loop back to Build', 'back', ['t state loop review build --reason "{reason}"'], { ts: 3 })
    expect(allowedCalls([acc1, acc2, back], at).sort()).toEqual(
      ['t evidence accept --stage review --id 1 --reason "{reason}"', 't evidence accept --stage review --id 2 --reason "{reason}"', 't state loop review build --reason "{reason}"'].sort(),
    )
    const pause = gate('Save for later', 'pause', [], { ts: 4 })
    expect(allowedCalls([back, pause], at)).toEqual([])
  })
  test('nothing from another step', () => {
    expect(allowedCalls([gate('Override and continue', 'override', ['t override review --reason "{reason}"'], { step: 3 })], at)).toEqual([])
  })
})

describe('restartFor', () => {
  test('a restart counts for its run at its step, and not at a later step or for another run', () => {
    expect(restartFor([d({ kind: 'restart', step: 1, calls: [] })], { run: 'r1', step: 1 })).not.toBeNull()
    expect(restartFor([d({ kind: 'restart', step: 1, calls: [] })], { run: 'r1', step: 2 })).toBeNull()
    expect(restartFor([d({ kind: 'restart', step: 1, calls: [] })], { run: 'r2', step: 1 })).toBeNull()
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
  const good = { id: 'a', run: 'r1', step: 1, stage: 'plan', ts: 1, kind: 'gate', label: 'Continue to Build', move: 'approve', calls: ['t state advance plan_complete build'], steps: [], reason: '' }
  test('a well formed record is kept', () => {
    expect(parseBook([good])).toHaveLength(1)
  })
  const bad: Record<string, unknown> = {
    'not a list': { ...good },
    'an unknown kind': [{ ...good, kind: 'approve' }],
    'a step that is no number': [{ ...good, step: '1' }],
    'no reason': [{ ...good, reason: undefined }],
    'a gate answer with no calls': [{ ...good, calls: undefined }],
    'a gate answer with a call that is no text': [{ ...good, calls: [1] }],
    'a gate answer with no label': [{ ...good, label: undefined }],
    'a restart with no calls': [{ ...good, kind: 'restart', calls: 'x' }],
    'a drift answer with no path': [{ ...good, kind: 'drift', choice: 'add' }],
    'a drift answer with an unknown choice': [{ ...good, kind: 'drift', path: 'a', choice: 'ignore' }],
  }
  for (const [name, raw] of Object.entries(bad)) test(`${name}: no decision`, () => expect(parseBook(raw)).toEqual([]))
})

describe('the words a decision reads as', () => {
  test('each kind names what the person chose', () => {
    expect(describeDecision(gate('Loop back to Build', 'back', [], { stage: 'check', reason: 'flaky' }))).toBe('check: Loop back to Build (flaky)')
    expect(describeDecision(d({ kind: 'restart', calls: [] }))).toBe('started over')
    expect(describeDecision(d({ kind: 'drift', path: 'src/a.ts', choice: 'allow-once', reason: '' }))).toBe('src/a.ts: allowed once')
  })
  test('decisionsOf lists one run, oldest first', () => {
    const a = gate('Continue to Plan', 'approve', [], { stage: 'intent', ts: 5 })
    const b = gate('Continue to Build', 'approve', [], { stage: 'plan', ts: 3 })
    expect(decisionsOf([a, b, gate('Save for later', 'pause', [], { run: 'r0' })], 'r1').map(x => x.id)).toEqual([b.id, a.id])
  })
})
