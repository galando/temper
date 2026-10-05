// Loop back and the Commit button, in the CLI-truth design: the person's Loop back is the loop the CLI
// keeps (`state loop` keeps the budget and clears the evidence of the stages that are redone), and the
// guard lets that one call through only for the person's own back decision.
import { describe, expect, test } from 'claude-code/testing'

import { classifyBash } from '../../hooks/temper-mod/core/bash'
import { doneActions } from '../../hooks/temper-mod/core/actions'
import { CLI, loopCommand } from '../../hooks/temper-mod/core/cli'
import { followUp } from '../../hooks/temper-mod/core/commands'
import { evaluate } from '../../hooks/temper-mod/core/rules'
import type { HumanDecision } from '../../hooks/temper-mod/core/rules'
import { person, stateAt } from './helpers'

const ctx = { specDir: '.temper/specs/pw', planFiles: [] as string[] }
const bash = (command: string) => ({ tool: 'Bash', input: { command } })
const back: HumanDecision = { id: 'b1', kind: 'back', phase: 'plan' }
const draft = { type: 'back', to: 'plan', reason: "it's a bad plan", ...person } as const

describe('the loop the CLI keeps for a Loop back', () => {
  test('the mirror prompt runs state loop first, then state set next_stage, and stops when the budget is spent', () => {
    const text = followUp(draft, null, CLI, 'build') ?? ''
    expect(text).toContain("`scripts/temper state loop build plan --reason 'it'\\''s a bad plan'`")
    expect(text).toContain('If it prints BLOCKED')
    expect(text.indexOf('state loop')).toBeLessThan(text.indexOf('state set next_stage plan'))
    expect(text.endsWith('Do this now. Reply with one short line.')).toBe(true)
  })

  test('Fix is the Check stage of the CLI', () => {
    expect(loopCommand('fix', 'plan', 'x')).toBe(`${CLI} state loop check plan --reason 'x'`)
  })

  test('without the phase left, only the step is mirrored (as before)', () => {
    const text = followUp(draft) ?? ''
    expect(text).not.toContain('state loop')
    expect(text).toContain('state set next_stage plan')
  })

  test('the guard lets state loop through while the person back decision waits, and keeps that decision for the step', () => {
    const loop = loopCommand('build', 'plan', 'why')
    // The guard sees the phase the CLI is at (build): the person's back decision to Plan waits for its mirror calls.
    const r = evaluate(stateAt('build'), { ...ctx, humanDecisions: [back] }, bash(loop))
    expect('allow' in r).toBe(true)
    // Not spent: the step that follows spends it.
    expect('consume' in r && r.consume).toBeFalsy()
    expect('loopIds' in r && r.loopIds).toEqual(['b1'])
    const set = evaluate(stateAt('build'), { ...ctx, humanDecisions: [back] }, bash(`${CLI} state set next_stage plan`))
    expect('allow' in set && set.eventIds).toEqual(['b1'])
  })

  test('a model that loops on its own is refused: no decision, a decision for another stage, or a stage that is not plain', () => {
    const loop = loopCommand('build', 'plan', 'why')
    expect('deny' in evaluate(stateAt('build'), { ...ctx, humanDecisions: [] }, bash(loop))).toBe(true)
    expect('deny' in evaluate(stateAt('build'), { ...ctx, humanDecisions: [{ id: 'b2', kind: 'back', phase: 'intent' }] }, bash(loop))).toBe(true)
    expect('deny' in evaluate(stateAt('build'), { ...ctx, humanDecisions: [back] }, bash(`${CLI} state loop build "$T" --reason x`))).toBe(true)
    expect('deny' in evaluate(stateAt('build'), { ...ctx, humanDecisions: [{ id: 'a1', kind: 'advance', phase: 'plan' }] }, bash(loop))).toBe(true)
    // The loop leaves the stage the run is at, and a decision is used once.
    expect('deny' in evaluate(stateAt('review'), { ...ctx, humanDecisions: [back] }, bash(loop))).toBe(true)
    expect('deny' in evaluate(stateAt('build'), { ...ctx, humanDecisions: [back], loopedDecisions: ['b1'] }, bash(loop))).toBe(true)
  })

  test('state init stays refused, even with a back decision', () => {
    expect('deny' in evaluate(stateAt('plan'), { ...ctx, humanDecisions: [back] }, bash(`${CLI} state init x`))).toBe(true)
  })

  test('state loop is still not a decision call, and its target is read', () => {
    const c = classifyBash(`${CLI} state loop check fix --reason x`)
    expect(c.decisions).toEqual([])
    expect(c.stateOps).toEqual([{ op: 'loop', from: 'check', to: 'fix' }])
  })
})

describe('Skip with a reason: the advance that follows it', () => {
  const skip = { type: 'override', phase: 'plan', reason: 'reviewed offline', ...person } as const
  const advancePlan = bash(`${CLI} state advance plan_complete build`)

  test('the skip is the go-ahead: the orchestrator advance out of the skipped Plan passes with no second approval', () => {
    const s = stateAt('plan', [skip])
    expect(s.phase).toBe('build')
    // The guard sees the phase the CLI is at: still the skipped Plan, until this advance runs.
    expect('allow' in evaluate({ ...s, phase: 'plan' }, { ...ctx, humanDecisions: [] }, advancePlan)).toBe(true)
    // A skip is for the stage the run is at: at Build the same call is refused (it would move the run back).
    expect('deny' in evaluate(s, { ...ctx, humanDecisions: [] }, advancePlan)).toBe(true)
  })

  test('without a skip the same call is refused', () => {
    expect('deny' in evaluate(stateAt('build'), { ...ctx, humanDecisions: [] }, advancePlan)).toBe(true)
  })

  test('only the skipped stage and only the next stage: no other advance, no wrong target', () => {
    const s = stateAt('plan', [skip])
    expect('deny' in evaluate(s, { ...ctx, humanDecisions: [] }, bash(`${CLI} state advance intent_complete plan`))).toBe(true)
    expect('deny' in evaluate(s, { ...ctx, humanDecisions: [] }, bash(`${CLI} state advance plan_complete review`))).toBe(true)
    expect('deny' in evaluate(s, { ...ctx, humanDecisions: [] }, bash(`${CLI} state advance build_complete review`))).toBe(true)
  })

  test('a later step back to Plan ends the skip: the new plan needs its own approval', () => {
    const s = stateAt('plan', [skip, { type: 'back', to: 'plan', reason: 'rework', ...person }])
    expect(s.phase).toBe('plan')
    expect('deny' in evaluate(s, { ...ctx, humanDecisions: [] }, advancePlan)).toBe(true)
  })

  test('a skip of Intent opens the advance out of Intent, and a medium run goes through design', () => {
    const s = { ...stateAt('intent', [{ type: 'override', phase: 'intent', reason: 'ok', ...person }]), phase: 'intent' as const }
    expect('allow' in evaluate(s, { ...ctx, humanDecisions: [] }, bash(`${CLI} state advance intent_complete plan`))).toBe(true)
    const medium = { ...stateAt('plan', [skip]), phase: 'plan' as const }
    const c = { ...ctx, complexity: 'medium', humanDecisions: [] as HumanDecision[] }
    expect('allow' in evaluate(medium, c, bash(`${CLI} state advance plan_complete design`))).toBe(true)
    expect('allow' in evaluate(medium, c, bash(`${CLI} state advance design_complete build`))).toBe(true)
  })
})

describe('a medium run when the project never switched design on (found live: the orchestrator went plan to build)', () => {
  const approve: HumanDecision[] = [{ id: 'p1', kind: 'advance', phase: 'plan' }]
  const toBuild = bash(`${CLI} state advance plan_complete build`)
  const toDesign = bash(`${CLI} state advance plan_complete design`)
  // The guard sees the phase the CLI is at (plan) while the person's approval waits for its mirror call.
  const state = { ...stateAt('build', [], { plan: { verdict: 'PASS', ts: 999_999_999 } }), phase: 'plan' as const }

  test('phases.design absent: both next stages pass with the person approval', () => {
    const c = { ...ctx, complexity: 'medium', humanDecisions: approve }
    expect('allow' in evaluate(state, c, toBuild)).toBe(true)
    expect('allow' in evaluate(state, c, toDesign)).toBe(true)
  })

  test('phases.design: true: Build straight after a medium plan is refused', () => {
    expect('deny' in evaluate(state, { ...ctx, complexity: 'medium', designRequired: true, humanDecisions: approve }, toBuild)).toBe(true)
  })

  test('design on: the refusal names the stage that is next, not the person (the model had retried the same call 3 times)', () => {
    const r = evaluate(state, { ...ctx, complexity: 'medium', designRequired: true, humanDecisions: approve }, toBuild)
    expect('deny' in r && r.deny).toContain('the next stage of this run is design, not build')
    expect('deny' in r && r.deny).toContain('state advance plan_complete design')
    expect('deny' in r && r.deny).not.toContain('Only the user')
    // With no decision waiting it is still the person who must decide.
    const none = evaluate(state, { ...ctx, complexity: 'medium', designRequired: true, humanDecisions: [] }, toBuild)
    expect('deny' in none && none.deny).toContain('Only the user')
  })

  test('the Continue at the design check spends the person decision (found live: it stayed pending after Design)', () => {
    const c = { ...ctx, complexity: 'medium', designRequired: true, humanDecisions: approve }
    const r = evaluate(state, c, bash(`${CLI} state advance design_complete build`))
    expect('allow' in r && r.eventIds).toEqual(['p1'])
    // With no decision waiting the call still follows the plan approval and the design stage.
    expect('allow' in evaluate(state, { ...c, humanDecisions: [] }, bash(`${CLI} state advance design_complete build`))).toBe(true)
  })

  test('the person approval is still needed, and a simple run is not changed', () => {
    expect('deny' in evaluate(state, { ...ctx, complexity: 'medium', humanDecisions: [] }, toBuild)).toBe(true)
    expect('deny' in evaluate(state, { ...ctx, complexity: 'simple', humanDecisions: approve }, toDesign)).toBe(true)
  })
})

describe('a failed Check that loops through Fix and returns to Check (found live)', () => {
  const failed = { type: 'checkResult', result: 'fail', origin: 'system' } as const
  const back = { type: 'advance', from: 'fix', to: 'check', ...person } as const

  test('a verdict written while the run was in Fix counts for the Check it returns to', () => {
    // The drafts are stamped 10 s apart: the failure at 60 s, the person at 70 s, the new PASS at 65 s.
    const s = stateAt('check', [failed, back], { check: { verdict: 'PASS', ts: 65_000 } })
    expect(s.phase).toBe('check')
    expect(s.gate.check).toBe('fresh')
  })

  test('the verdict that failed, or an older one, does not count', () => {
    expect(stateAt('check', [failed, back], { check: { verdict: 'PASS', ts: 50_000 } }).gate.check).toBe('stale')
    expect(stateAt('check', [failed, back], { check: { verdict: 'FAIL', ts: 65_000 } }).gate.check).toBe('fail')
  })

  test('a plain advance into Check keeps its own entry time', () => {
    const s = stateAt('check', [], { check: { verdict: 'PASS', ts: 5_000 } })
    expect(s.gate.check).toBe('stale')
  })
})

describe('the Commit button at Done', () => {
  test('it tells the orchestrator to do its Commit steps, ending with state clear, and never pushes', () => {
    const text = doneActions().primary[0]?.prompt ?? ''
    expect(text).toContain('Commit section of commands/temper.md')
    for (const step of ['gate commit', 'Status completed', 'state archive', '.temper/specs', 'conventional commit', 'state clear', 'Do not push']) expect(text).toContain(step)
    expect(text.indexOf('state archive')).toBeLessThan(text.indexOf('state clear'))
  })
})
