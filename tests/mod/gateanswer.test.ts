// The gate asked as a question (found in a user test): with the bar in a mode that draws no buttons, the person had to
// type /temper:temper approve. Now the orchestrator asks the gate in Claude Code's own question dialog, header
// `Temper gate`, and the mod records the person's answer as the decision the typed command would record.
import { describe, expect, test } from 'claude-code/testing'

import { gateAnswer, resumeAnswer } from '../../hooks/temper-mod/core/gateanswer'
import { parseArgs, planCommand } from '../../hooks/temper-mod/core/commands'
import { ONLY_USER } from '../../hooks/temper-mod/core/machine'
import { SPEC, runFiles } from './run-files'
import { COMPOSE, world } from './world'
import type { World } from './world'

const START = { cwd: '/repo', surface: null, isInteractive: true } as const
const CLI = '/home/u/.claude/plugins/temper/scripts/temper'
type Api = {
  session: { start: (a: unknown) => Promise<unknown> }
  command: { run: (a: unknown) => Promise<{ text?: string }> }
  tool: { call: (a: unknown) => Promise<{ deny?: string }> }
}

const QUESTION = 'The intent check passed. What next?'
const result = (answer: string, header = 'Temper gate', q = QUESTION, notes?: string) => ({
  result: { questions: [{ question: q, header }], answers: { [q]: answer }, ...(notes !== undefined ? { annotations: { [q]: { notes } } } : {}) },
})

describe('reading the Temper gate answer', () => {
  test('Continue to the next phase approves at Intent and Plan, and moves on after them', () => {
    expect(gateAnswer(result('Continue to Plan (Recommended)'), 'intent')).toEqual({ type: 'approve' })
    expect(gateAnswer(result('Continue to Plan'), 'intent')).toEqual({ type: 'approve' })
    expect(gateAnswer(result('continue to build (recommended)'), 'plan')).toEqual({ type: 'approve' })
    // Design is part of Plan: the Plan gate continues to Design, the Design gate to Build.
    expect(gateAnswer(result('Continue to Design (Recommended)'), 'plan')).toEqual({ type: 'approve' })
    expect(gateAnswer(result('Continue to Review (Recommended)'), 'build')).toEqual({ type: 'advance' })
    expect(gateAnswer(result('Continue to Check'), 'review')).toEqual({ type: 'advance' })
    expect(gateAnswer(result('Continue to Commit'), 'check')).toEqual({ type: 'advance' })
  })

  test('Save for later pauses', () => {
    expect(gateAnswer(result('Save for later'), 'intent')).toEqual({ type: 'pause' })
    expect(gateAnswer(result('Save for later'), 'review')).toEqual({ type: 'pause' })
  })

  test('another header, another phase, a typed message, no run or a done run is no decision', () => {
    expect(gateAnswer(result('Continue to Plan', 'Library'), 'intent')).toBeNull()
    expect(gateAnswer(result('Continue to Plan', 'Scope drift'), 'intent')).toBeNull()
    expect(gateAnswer(result('Continue to Build (Recommended)'), 'intent')).toBeNull()
    expect(gateAnswer(result('Continue to Plan (Recommended)'), 'build')).toBeNull()
    expect(gateAnswer(result('Please rename the criterion AC-02'), 'intent')).toBeNull()
    expect(gateAnswer(result('Continue to Plan please'), 'intent')).toBeNull()
    expect(gateAnswer(result('Continue to Plan'), null)).toBeNull()
    expect(gateAnswer(result('Save for later'), 'done')).toBeNull()
    expect(gateAnswer(undefined, 'intent')).toBeNull()
    expect(gateAnswer({ result: 'stub ran' }, 'intent')).toBeNull()
  })

  test('Loop back and Override with no reason record nothing', () => {
    expect(gateAnswer(result('Loop back to Plan'), 'build')).toBeNull()
    expect(gateAnswer(result('Loop back to Build (Recommended)'), 'review')).toBeNull()
    expect(gateAnswer(result('Override and continue'), 'review')).toBeNull()
    expect(gateAnswer(result('Override and continue', 'Temper gate', QUESTION, '   '), 'review')).toBeNull()
  })

  test('Loop back and Override with the person\'s typed reason record it', () => {
    expect(gateAnswer(result('Loop back to Plan: the API changed'), 'build')).toEqual({ type: 'back', to: 'plan', reason: 'the API changed' })
    expect(gateAnswer(result('Override and continue - the flaky test is tracked'), 'review')).toEqual({ type: 'override', reason: 'the flaky test is tracked' })
    // The note the person added to the choice is a reason too.
    expect(gateAnswer(result('Loop back to Build', 'Temper gate', QUESTION, 'R-1 is real'), 'review')).toEqual({ type: 'back', to: 'build', reason: 'R-1 is real' })
    expect(gateAnswer(result('Override and continue', 'Temper gate', QUESTION, 'I accept the risk'), 'check')).toEqual({ type: 'override', reason: 'I accept the risk' })
  })

  test('a step back goes only to an earlier phase', () => {
    expect(gateAnswer(result('Loop back to Review: why'), 'build')).toBeNull()
    expect(gateAnswer(result('Loop back to Fix: why'), 'check')).toBeNull()
    expect(gateAnswer(result('Loop back to Planning: why'), 'build')).toBeNull()
  })

  test('the reason question: the move is in the question, the person\'s answer is the reason, Cancel is no decision', () => {
    const loop = 'Loop back to Plan. What is the reason?'
    const skip = 'Override and continue. What is the reason?'
    expect(gateAnswer(result('The tasks miss the email step', 'Temper gate', loop), 'build')).toEqual({ type: 'back', to: 'plan', reason: 'The tasks miss the email step' })
    expect(gateAnswer(result('I accept the risk', 'Temper gate', skip), 'review')).toEqual({ type: 'override', reason: 'I accept the risk' })
    expect(gateAnswer(result('Cancel', 'Temper gate', skip), 'review')).toBeNull()
    expect(gateAnswer(result('The tasks miss the email step', 'Temper gate', loop), 'intent')).toBeNull()
  })
})

const cliNext = (w: World) => (JSON.parse(w.files.get('.temper/build-state.json') ?? '{}') as { next_stage?: string }).next_stage
const sh = async (api: Api, command: string) => (await api.tool.call({ tool: 'Bash', command })).deny
const ask = (question: string, options: string[]) => ({
  tool: 'AskUserQuestion',
  questions: [{ question, header: 'Temper gate', multiSelect: false, options: options.map(label => ({ label, description: label })) }],
})
const atIntent = (on: Parameters<typeof world>[0], answers: string[] = []): World => {
  const files = runFiles({ nextStage: 'intent', gates: { intent: 'PASS' } })
  files['/repo/.git/HEAD'] = 'ref: refs/heads/main\n'
  return world(on, files, { fakeCli: true, projectRoot: '/repo', answers })
}
const events = (w: World): string[] =>
  [...w.files.entries()]
    .filter(([p]) => p.startsWith(`${SPEC}/events/`))
    .map(([, t]) => JSON.parse(t) as { type: string; origin?: string; from?: string; to?: string; reason?: string })
    .filter(e => e.type !== 'start')
    .map(e => `${e.type}:${e.from ?? ''}:${e.to ?? ''}:${e.reason ?? ''}:${e.origin ?? ''}`)

describe('the gate in the question dialog, in minimal mode', () => {
  test('the system prompt says the bar has no buttons, in minimal and off modes only', { options: { uiMode: 'minimal' } }, async ($, on) => {
    atIntent(on)
    const text = (await $.prompt.compose(COMPOSE)).sections.at(-1)?.text ?? ''
    expect(text.split('\n')[1]).toBe('Temper buttons: none in this mode. At a gate, ask with AskUserQuestion, header `Temper gate`.')
  })

  test('off mode has the line too', { options: { uiMode: 'off' } }, async ($, on) => {
    atIntent(on)
    expect((await $.prompt.compose(COMPOSE)).sections.at(-1)?.text ?? '').toContain('Temper buttons: none in this mode.')
  })

  test('full mode has no such line', async ($, on) => {
    atIntent(on)
    expect((await $.prompt.compose(COMPOSE)).sections.at(-1)?.text ?? '').not.toContain('Temper buttons')
  })

  test('"Continue to Plan" at the Intent gate lets the On Continue steps and the state advance through', { options: { uiMode: 'minimal' } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = atIntent(on, ['Continue to Plan (Recommended)'])
    await api.session.start(START)
    await api.tool.call(ask('The intent check passed. What next?', ['Continue to Plan (Recommended)', 'Save for later']))
    expect(events(w)).toEqual(['advance:intent:plan::person'])
    // Nothing is sent to Claude: the orchestrator does the On Continue steps in the same turn.
    expect(w.prompts).toEqual([])
    expect(w.commandRuns).toEqual([])
    expect(await sh(api, 'git add .temper/specs/pw/')).toBeUndefined()
    expect(await sh(api, 'git commit -m "docs(intent): accept pw"')).toBeUndefined()
    expect(await sh(api, `${CLI} state advance intent_complete plan`)).toBeUndefined()
    expect(cliNext(w)).toBe('plan')
    // The decision is used once: it does not approve the Plan.
    expect(await sh(api, `${CLI} state advance plan_complete build`)).toBe(ONLY_USER)
  })

  test('without that answer the state advance is still refused', { options: { uiMode: 'minimal' } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = atIntent(on)
    await api.session.start(START)
    // Nobody answered: the dialog was refused.
    await api.tool.call(ask('The intent check passed. What next?', ['Continue to Plan (Recommended)', 'Save for later']))
    expect(events(w)).toEqual([])
    expect(await sh(api, `${CLI} state advance intent_complete plan`)).toBe(ONLY_USER)
    expect(cliNext(w)).toBe('intent')
  })

  test('an answer the caller wrote into the question, another header, or another phase records nothing', { options: { uiMode: 'minimal' } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = atIntent(on, ['Continue to Plan', 'Continue to Build (Recommended)'])
    await api.session.start(START)
    await api.tool.call({ ...ask('Q1?', ['Continue to Plan', 'Save for later']), questions: [{ question: 'Q1?', header: 'Library', multiSelect: false, options: [{ label: 'Continue to Plan', description: 'x' }, { label: 'Save for later', description: 'y' }] }] })
    await api.tool.call(ask('Q2?', ['Continue to Build (Recommended)', 'Save for later']))
    await api.tool.call({ ...ask('Q3?', ['Continue to Plan', 'Save for later']), answers: { 'Q3?': 'Continue to Plan' } })
    expect(events(w)).toEqual([])
    expect(await sh(api, `${CLI} state advance intent_complete plan`)).toBe(ONLY_USER)
  })

  test('a second answer while the first move waits to be recorded records nothing more', { options: { uiMode: 'minimal' } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = atIntent(on, ['Continue to Plan (Recommended)', 'Save for later'])
    await api.session.start(START)
    await api.tool.call(ask('The intent check passed. What next?', ['Continue to Plan (Recommended)', 'Save for later']))
    await api.tool.call(ask('The intent check passed. What now?', ['Continue to Plan (Recommended)', 'Save for later']))
    expect(events(w)).toEqual(['advance:intent:plan::person'])
  })

  test('"Save for later" pauses the run', { options: { uiMode: 'minimal' } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = atIntent(on, ['Save for later'])
    await api.session.start(START)
    await api.tool.call(ask('The intent check passed. What next?', ['Continue to Plan (Recommended)', 'Save for later']))
    expect(events(w)).toEqual(['pause::::person'])
  })

  test('with enforcement off the answer is recorded the same way', { options: { uiMode: 'off', enforcement: 'off' } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = atIntent(on, ['Continue to Plan (Recommended)'])
    await api.session.start(START)
    await api.tool.call(ask('The intent check passed. What next?', ['Continue to Plan (Recommended)', 'Save for later']))
    expect(events(w)).toEqual(['advance:intent:plan::person'])
    expect(await sh(api, `${CLI} state advance intent_complete plan`)).toBeUndefined()
  })
})

// Start over (found in a user test): with the bar off the orchestrator told the person to use a "Start over" button that
// does not exist, and the mod refused Claude's own state init. Now the person chooses it in the `Temper resume` question
// (or the bar's menu, or /temper:temper restart <reason>), and the mod lets the reset through.
const RESUME_Q = 'The saved run does not fit. What now?'
const askResume = (options: string[]) => ({
  tool: 'AskUserQuestion',
  questions: [{ question: RESUME_Q, header: 'Temper resume', multiSelect: false, options: options.map(label => ({ label, description: label })) }],
})

describe('Start over', () => {
  test('the Temper resume answer "Start over" is a restart decision with a reason; anything else is none', () => {
    expect(resumeAnswer(result('Start over', 'Temper resume', RESUME_Q))).toEqual({ type: 'restart', reason: `chosen in the question: ${RESUME_Q}` })
    expect(resumeAnswer(result('Start over', 'Temper resume', RESUME_Q, 'wrong feature'))).toEqual({ type: 'restart', reason: 'wrong feature' })
    expect(resumeAnswer(result('Continue the saved run (Recommended)', 'Temper resume', RESUME_Q))).toBeNull()
    expect(resumeAnswer(result('Start over', 'Temper gate', RESUME_Q))).toBeNull()
  })

  test('/temper:temper restart <reason> is the same decision', () => {
    const parsed = parseArgs('restart the plan is for another feature')
    expect(parsed).not.toBeNull()
    if (parsed) expect(planCommand(parsed, null)).toEqual({ kind: 'command', command: { type: 'restart', reason: 'the plan is for another feature' } })
  })

  test('without the person\'s choice a reset of an active run is refused', async ($, on) => {
    const api = $ as unknown as Api
    atIntent(on)
    await api.session.start(START)
    expect(await sh(api, `${CLI} state init pw --command temper`)).toContain('Temper resume')
    expect(await sh(api, `${CLI} state archive`)).toContain('Temper resume')
  })

  test('after "Start over" the archive passes and one state init passes; a second init is refused', { options: { uiMode: 'off' } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = atIntent(on, ['Start over'])
    await api.session.start(START)
    await api.tool.call(askResume(['Continue the saved run (Recommended)', 'Start over', 'Cancel']))
    expect(events(w)).toEqual([`restart:::chosen in the question: ${RESUME_Q}:person`])
    expect(await sh(api, `${CLI} state archive`)).toBeUndefined()
    expect(await sh(api, `${CLI} state init pw --command temper`)).toBeUndefined()
    expect(await sh(api, `${CLI} state init pw --command temper`)).toBeDefined()
  })

  test('a reset chained with anything else is still refused', async ($, on) => {
    const api = $ as unknown as Api
    atIntent(on, ['Start over'])
    await api.session.start(START)
    await api.tool.call(askResume(['Start over', 'Cancel']))
    expect(await sh(api, `${CLI} state init pw --command temper && ${CLI} state advance intent_complete plan`)).toBeDefined()
  })
})
