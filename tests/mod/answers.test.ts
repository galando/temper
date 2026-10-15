// Reading the person's answer (ADR 0013): only an answer to the question the CLI wrote for this step counts, matched
// exactly (header, question and label), against the CLI's real views (scripts/selftest/view-fixtures.ts). A reworded
// question, a label with a word more, and a typed message are no move. A move that needs a reason counts once the
// reason is known: the person's note on the option, or any answer but Cancel to the reason question.
import { describe, expect, test } from 'claude-code/testing'

import { answersIn } from '../../hooks/temper-mod/core/answers'
import type { Answer } from '../../hooks/temper-mod/core/answers'
import { parseRunView } from '../../hooks/temper-mod/core/runview'
import type { RunView } from '../../hooks/temper-mod/core/runview'
import { questionOf, view } from './run-files'

const rv = (name: string): RunView => {
  const v = parseRunView(JSON.stringify(view(name)))
  if (v === null) throw new Error(`no view ${name}`)
  return v
}
type Q = { header: string; question: string; multiSelect?: boolean }
const result = (q: Q, answer: string, note?: string, extra: Record<string, unknown> = {}) => ({
  result: { questions: [q], answers: { [q.question]: answer }, ...(note !== undefined ? { annotations: { [q.question]: { notes: note } } } : {}), ...extra },
})
const gate = (a: Answer[]) => a.filter((x): x is Extract<Answer, { kind: 'gate' }> => x.kind === 'gate')
const asked = (name: string, which: Parameters<typeof questionOf>[1] = {}) => questionOf(JSON.stringify(view(name)), which)

describe('a gate question answered exactly', () => {
  test('Continue to Plan: the move and the exact calls the CLI wrote for it', () => {
    const q = asked('intent-pass')
    const a = gate(answersIn(result(q, 'Continue to Plan (Recommended)'), rv('intent-pass')))
    expect(a).toHaveLength(1)
    expect(a[0]?.option.move).toBe('approve')
    expect(a[0]?.option.calls.some(c => c.endsWith('temper state advance intent_complete plan'))).toBe(true)
  })

  test('the arming answer at the plan gate, with autonomy on', () => {
    const q = asked('plan-pass-autonomy')
    const a = gate(answersIn(result(q, 'Autonomous: run the rest unattended'), rv('plan-pass-autonomy')))
    expect(a[0]?.option.move).toBe('arm')
    expect(a[0]?.option.calls.some(c => c.endsWith('temper state set run_mode autonomous'))).toBe(true)
  })

  test('Save for later in the More options question', () => {
    const q = asked('plan-pass', { more: true })
    const a = gate(answersIn(result(q, 'Save for later'), rv('plan-pass')))
    expect(a[0]?.option.move).toBe('pause')
  })
})

describe('what is no answer', () => {
  const q = asked('intent-pass')
  const v = rv('intent-pass')
  const none: Record<string, unknown> = {
    'a reworded question': result({ ...q, question: 'Intent passed. Go on to Plan?' }, 'Continue to Plan (Recommended)'),
    'another header': result({ ...q, header: 'Temper' }, 'Continue to Plan (Recommended)'),
    'a header in other case': result({ ...q, header: 'temper gate' }, 'Continue to Plan (Recommended)'),
    'a label without (Recommended)': result(q, 'Continue to Plan'),
    'a label with a word more': result(q, 'Continue to Plan (Recommended), please'),
    'a typed message': result(q, 'yes, go on'),
    'an option that decides nothing': result(q, 'Grill Me'),
    'a dialog nobody answered': result(q, 'Continue to Plan (Recommended)', undefined, { afkTimeoutMs: 60000 }),
    'a request for another round': result(q, 'Continue to Plan (Recommended)', undefined, { followUp: true }),
    'a multi select question': result({ ...q, multiSelect: true }, 'Continue to Plan (Recommended)'),
    'an answer the caller wrote in its own input': { questions: [q], answers: { [q.question]: 'Continue to Plan (Recommended)' } },
    'no result at all': undefined,
  }
  for (const [name, r] of Object.entries(none)) test(name, () => expect(answersIn(r, v)).toEqual([]))

  test('the question of another step: the same words, but the view has moved on', () => {
    expect(answersIn(result(q, 'Continue to Plan (Recommended)'), rv('plan-pass'))).toEqual([])
  })
})

describe('a move that needs a reason', () => {
  const q = asked('build-fail')
  const v = rv('build-fail')
  test('chosen with no note: not yet a move', () => {
    expect(answersIn(result(q, 'Override and continue'), v)).toEqual([])
  })
  test('chosen with a note: the note is the reason', () => {
    const a = gate(answersIn(result(q, 'Override and continue', 'the flaky test is known'), v))
    expect(a[0]?.option.move).toBe('override')
    expect(a[0]?.reason).toBe('the flaky test is known')
  })
  test('the reason question: a listed reason, or a typed one, is the reason; Cancel is none', () => {
    const rq = asked('build-fail', { reasonOf: 'Override and continue' })
    expect(rq.question).toBe('Override and continue. What is the reason?')
    expect(gate(answersIn(result(rq, 'I accept the risk'), v))[0]?.reason).toBe('I accept the risk')
    expect(gate(answersIn(result(rq, 'the test needs a network'), v))[0]?.reason).toBe('the test needs a network')
    expect(answersIn(result(rq, 'Cancel'), v)).toEqual([])
  })
  test('Accept a finding: the accept question, with a reason', () => {
    const aq = asked('review-fail', { accept: true })
    const a = gate(answersIn(result(aq, 'Accept finding 1', 'a test covers it'), rv('review-fail')))
    expect(a[0]?.option.move).toBe('accept')
    expect(a[0]?.option.calls.some(c => c.includes('evidence accept --stage review --id 1'))).toBe(true)
  })
})

describe('Start over', () => {
  const q = asked('build-work', { restart: true })
  test('Start over is a restart; Cancel is none', () => {
    expect(answersIn(result(q, 'Start over'), rv('build-work')).map(a => a.kind)).toEqual(['restart'])
    expect(answersIn(result(q, 'Cancel'), rv('build-work'))).toEqual([])
  })
})
