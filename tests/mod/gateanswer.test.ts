// The answer in a Temper gate question (ADR 0012), pure: what each choice decides at each stage, the reason a step back,
// a skip, an accept or a kept commit needs, and the answers that decide nothing.
import { describe, expect, test } from 'claude-code/testing'

import { gateAnswer, resumeAnswer } from '../../hooks/temper-mod/core/gateanswer'
import type { Stage } from '../../hooks/temper-mod/core/stages'

const Q = 'What next?'
const result = (answer: string, o: { header?: string; question?: string; note?: string } = {}) => {
  const question = o.question ?? Q
  return { result: { questions: [{ question, header: o.header ?? 'Temper gate' }], answers: { [question]: answer }, ...(o.note ? { annotations: { [question]: { notes: o.note } } } : {}) } }
}
const at = (stage: Stage, answer: string, o: Parameters<typeof result>[1] = {}, design = false) => gateAnswer(result(answer, o), stage, { design })

describe('Continue leaves a gate', () => {
  test('at Intent and Plan it is an approval (only the person leaves them)', () => {
    expect(at('intent', 'Continue to Plan (Recommended)')).toEqual({ kind: 'approve', reason: '' })
    expect(at('plan', 'Continue to Build')).toEqual({ kind: 'approve', reason: '' })
  })
  test('after them it is an advance', () => {
    expect(at('build', 'Continue to Review')).toEqual({ kind: 'advance', reason: '' })
    expect(at('review', 'Continue')).toEqual({ kind: 'advance', reason: '' })
  })
  test('Continue to a stage that is not next decides nothing', () => {
    expect(at('build', 'Continue to Check')).toBeNull()
    expect(at('intent', 'Continue to Build')).toBeNull()
  })
  test('at Plan, Continue to Build still goes on when the run has Design', () => {
    expect(at('plan', 'Continue to Build', {}, true)).toEqual({ kind: 'approve', reason: '' })
    expect(at('plan', 'Continue to Design', {}, true)).toEqual({ kind: 'approve', reason: '' })
  })
  test('Commit is the answer of a passed Check only', () => {
    expect(at('check', 'Commit')).toEqual({ kind: 'advance', reason: '' })
    expect(at('review', 'Commit')).toBeNull()
  })
})

describe('the arming answers are for the Plan gate', () => {
  test('Stage by stage approves; Autonomous arms', () => {
    expect(at('plan', 'Stage by stage (Recommended)')).toEqual({ kind: 'approve', reason: '' })
    expect(at('plan', 'Autonomous: run to the commit and park')).toEqual({ kind: 'arm', reason: '' })
  })
  test('at another stage they decide nothing', () => {
    expect(at('build', 'Autonomous')).toBeNull()
    expect(at('intent', 'Stage by stage')).toBeNull()
  })
})

describe('a step back, a skip, an accept and a kept commit need the person\'s reason', () => {
  test('the reason after the choice', () => {
    expect(at('review', 'Loop back to Build: the token bug is real')).toEqual({ kind: 'back', to: 'build', reason: 'the token bug is real' })
    expect(at('check', 'Override and continue - the lint rule is wrong')).toEqual({ kind: 'override', reason: 'the lint rule is wrong' })
    expect(at('review', 'Accept finding 3: known, tracked in #12')).toEqual({ kind: 'accept', findingId: '3', reason: 'known, tracked in #12' })
    expect(at('build', "Keep the agent's commits: the commit is the change we wanted")).toEqual({ kind: 'keep', reason: 'the commit is the change we wanted' })
  })
  test('the reason in the note the person added', () => {
    expect(at('review', 'Loop back to Build', { note: 'the token bug' })).toEqual({ kind: 'back', to: 'build', reason: 'the token bug' })
  })
  test('with no reason they decide nothing', () => {
    expect(at('review', 'Loop back to Build')).toBeNull()
    expect(at('check', 'Override and continue')).toBeNull()
    expect(at('review', 'Accept finding 3')).toBeNull()
  })
  test('the reason question: the move is in the question, the answer is the reason', () => {
    expect(at('review', 'it fails on empty input', { question: 'Loop back to Build. What is the reason?' })).toEqual({ kind: 'back', to: 'build', reason: 'it fails on empty input' })
    expect(at('review', 'Cancel', { question: 'Loop back to Build. What is the reason?' })).toBeNull()
  })
  test('a step back goes to an earlier stage only', () => {
    expect(at('build', 'Loop back to Check: x')).toBeNull()
    expect(at('build', 'Loop back to Build: x')).toBeNull()
    expect(at('check', 'Loop back to Plan: the API changed')).toEqual({ kind: 'back', to: 'plan', reason: 'the API changed' })
  })
  test('Design is a stage to step back to only in a run that has it', () => {
    expect(at('build', 'Loop back to Design: x')).toBeNull()
    expect(at('build', 'Loop back to Design: x', {}, true)).toEqual({ kind: 'back', to: 'design', reason: 'x' })
  })
  test('accept is for Review, and for a numbered finding', () => {
    expect(at('check', 'Accept finding 3: x')).toBeNull()
    expect(at('review', 'Accept finding abc: x')).toBeNull()
  })
  test('keep is for Build', () => {
    expect(at('review', "Keep the agent's commits: x")).toBeNull()
  })
})

describe('the commit stage', () => {
  test('Override and commit with a reason; Save for later', () => {
    expect(at('commit', 'Override and commit: the hook is broken on this host')).toEqual({ kind: 'commitOverride', reason: 'the hook is broken on this host' })
    expect(at('commit', 'Save for later')).toEqual({ kind: 'pause', reason: '' })
  })
  test('nothing else decides anything there', () => {
    expect(at('commit', 'Override and commit')).toBeNull()
    expect(at('commit', 'Continue')).toBeNull()
    expect(at('commit', 'Override and continue: x')).toBeNull()
  })
})

describe('answers that decide nothing', () => {
  test('a question with another header', () => {
    expect(at('plan', 'Continue to Build', { header: 'Something else' })).toBeNull()
  })
  test('a typed message that names no move', () => {
    expect(at('plan', 'yes go ahead')).toBeNull()
    expect(at('plan', '')).toBeNull()
  })
  test('no run, or no dialog result', () => {
    expect(gateAnswer(result('Continue'), null)).toBeNull()
    expect(gateAnswer({ text: 'Continue' }, 'plan')).toBeNull()
    expect(gateAnswer(undefined, 'plan')).toBeNull()
  })
  test('Save for later pauses at any stage', () => {
    for (const s of ['intent', 'plan', 'build', 'review', 'check'] as const) expect(at(s, 'Save for later')).toEqual({ kind: 'pause', reason: '' })
  })
})

describe('Start over, in the Temper resume question', () => {
  test('the choice with the person\'s note, or the question as the reason', () => {
    expect(resumeAnswer(result('Start over', { header: 'Temper resume', note: 'wrong feature' }))).toEqual({ reason: 'wrong feature' })
    expect(resumeAnswer(result('Start over (Recommended)', { header: 'Temper resume', question: 'The saved run is for another feature.' }))).toEqual({ reason: 'chosen in the question: The saved run is for another feature.' })
  })
  test('another choice, or the gate header, is no restart', () => {
    expect(resumeAnswer(result('Resume', { header: 'Temper resume' }))).toBeNull()
    expect(resumeAnswer(result('Start over'))).toBeNull()
  })
})
