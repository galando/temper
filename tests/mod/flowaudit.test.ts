// The flow audit of PR #97: every point where a run waits for the person offers a click in every setup (no mod; the
// mod in full, minimal and off modes; enforcement on and off), the guard accepts the move chosen, and no text points
// at a button that does not exist or names a typed command. Each test failed on the code before its fix; the finding
// number of the audit is in its name.
import { describe, expect, test } from 'claude-code/testing'

import { gateAnswer } from '../../hooks/temper-mod/core/gateanswer'
import { decide, ONLY_USER, ONLY_USER_ASK } from '../../hooks/temper-mod/core/machine'
import { actionsFor, doneActions, nextStep, pendingLines, reasonAsk } from '../../hooks/temper-mod/core/actions'
import { sectionText } from '../../hooks/temper-mod/core/section'
import { evaluate } from '../../hooks/temper-mod/core/rules'
import { SPEC, runFiles } from './run-files'
import { COMPOSE, world } from './world'
import type { World } from './world'
import { stateAt } from './helpers'

const CLI = '/home/u/.claude/plugins/temper/scripts/temper'
const START = { cwd: '/repo', surface: 'terminal', isInteractive: false } as const
const BAND = { hasSurvey: false, isWorking: false, maxRows: 12, bodyColumns: 120, scroll: { offset: 0, bodyRows: 12 }, view: {} } as const
type Mounted = { press: (a: { key: string }) => Promise<void>; input: (a: { key: string; text: string }) => Promise<void>; drawn: () => Promise<unknown> }
type Api = {
  ui: { mount: (a: unknown) => Promise<Mounted> }
  session: { start: (a: unknown) => Promise<unknown> }
  command: { run: (a: unknown) => Promise<{ text?: string }> }
  tool: { call: (a: unknown) => Promise<{ deny?: string }> }
  prompt: { compose: (a: unknown) => Promise<{ sections: Array<{ text: string }> }> }
}
const band = (api: Api) => api.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', props: BAND })
const bar = async (api: Api) => JSON.stringify(await (await band(api)).drawn())
const sh = async (api: Api, command: string) => (await api.tool.call({ tool: 'Bash', command })).deny
const write = async (api: Api, path: string) => (await api.tool.call({ tool: 'Write', file_path: `/repo/${path}`, content: 'x' })).deny
const gate = (question: string, options: string[]) => ({
  tool: 'AskUserQuestion',
  questions: [{ question, header: 'Temper gate', multiSelect: false, options: options.map(label => ({ label, description: label })) }],
})
const result = (answer: string, header = 'Temper gate', q = 'Q?') => ({ result: { questions: [{ question: q, header }], answers: { [q]: answer } } })
const system = async (api: Api) => (await api.prompt.compose(COMPOSE)).sections.at(-1)?.text ?? ''
const LATER = '2999-01-01T00:00:00Z'

function run(on: Parameters<typeof world>[0], state: Record<string, unknown>, gates: Record<string, 'PASS' | 'FAIL'> = {}, extra: Record<string, string> = {}, answers: string[] = []): World {
  const files = { ...runFiles({ gates }), ...extra }
  files['.temper/build-state.json'] = JSON.stringify({ spec: 'pw', spec_path: SPEC, command: 'temper', branch: 'feature/pw', ...state })
  files['/repo/.git/HEAD'] = 'ref: refs/heads/feature/pw\n'
  return world(on, files, { fakeCli: true, projectRoot: '/repo', answers })
}
const ALL_DONE = ['## Tasks', '### Task 1: t1', '- [x] done', ''].join('\n')

describe('finding 10: texts for Claude name no missing key and no typed command', () => {
  test('the Next line names key 1 with buttons, the Temper gate question without, and never a typed command', () => {
    for (const p of ['intent', 'plan', 'build', 'review', 'check', 'fix'] as const) {
      for (const ctx of [{ ready: true, tasksDone: true, allChecksPass: true, hasFindings: true }, {}]) {
        expect(nextStep(p, ctx), p).not.toContain('/temper:')
        const none = nextStep(p, { ...ctx, buttons: false })
        expect(none, p).not.toMatch(/key \d|press \d/i)
        expect(none, p).not.toContain('/temper:')
      }
    }
    expect(nextStep('plan', { ready: true })).toBe('ask the user to continue to Build (key 1 on the Temper bar)')
    expect(nextStep('plan', { ready: true, buttons: false })).toBe('ask the user with AskUserQuestion, header `Temper gate`: continue to Build')
  })

  test('the system prompt in minimal mode names the Temper gate question, not key 1', { options: { uiMode: 'minimal' } }, async ($, on) => {
    const api = $ as unknown as Api
    run(on, { stage: 'intent_complete', next_stage: 'plan' }, { intent: 'PASS', plan: 'PASS' })
    await api.session.start(START)
    const text = await system(api)
    expect(text).toContain('Next: ask the user with AskUserQuestion, header `Temper gate`: continue to Build')
    expect(text).not.toMatch(/key 1|press 1|\/temper:temper approve/i)
  })

  test('a refused advance names the bar in full mode and the Temper gate question in minimal and off', async ($, on) => {
    const api = $ as unknown as Api
    run(on, { stage: 'intent_complete', next_stage: 'plan' }, { intent: 'PASS', plan: 'PASS' })
    await api.session.start(START)
    expect(await sh(api, `${CLI} state advance plan_complete build`)).toBe(ONLY_USER)
    expect(ONLY_USER).not.toMatch(/press 1|\/temper:/)
  })

  for (const uiMode of ['minimal', 'off']) {
    test(`a refused advance in ${uiMode} mode`, { options: { uiMode } }, async ($, on) => {
      const api = $ as unknown as Api
      run(on, { stage: 'intent_complete', next_stage: 'plan' }, { intent: 'PASS', plan: 'PASS' })
      await api.session.start(START)
      expect(await sh(api, `${CLI} state advance plan_complete build`)).toBe(ONLY_USER_ASK)
      expect(await write(api, 'src/app.ts')).toContain('AskUserQuestion, header `Temper gate`')
    })
  }

  test('the step back refusal names no Go back button and no typed command', () => {
    const r = evaluate(stateAt('review'), { specDir: SPEC, planFiles: [] }, { tool: 'Bash', input: { command: `${CLI} state advance plan_complete build` } })
    const text = 'deny' in r ? r.deny : ''
    expect(text).toContain('cannot move the run to an earlier stage')
    expect(text).not.toContain('Go back')
    expect(text).not.toContain('/temper:')
  })

  test('no deny of the guard names a typed /temper:temper command', () => {
    const calls = [
      { tool: 'Write', input: { file_path: 'src/app.ts' } },
      { tool: 'Bash', input: { command: `${CLI} state set next_stage build` } },
      { tool: 'Bash', input: { command: `${CLI} state set run_mode autonomous` } },
      { tool: 'Bash', input: { command: 'git commit -m x' } },
      { tool: 'Bash', input: { command: `${CLI} override build --reason x` } },
      { tool: 'Bash', input: { command: `X=override; ${CLI} $X build --reason y` } },
    ]
    for (const phase of ['intent', 'plan', 'build', 'review', 'check', 'fix'] as const) {
      for (const buttons of [true, false]) {
        for (const call of calls) {
          const r = evaluate(stateAt(phase), { specDir: SPEC, planFiles: [], buttons, commit: { stagedSpecsOnly: false, checkpoint: false } }, call)
          if ('deny' in r) {
            expect(r.deny, `${phase} ${JSON.stringify(call)}`).not.toContain('/temper:temper')
            expect(r.deny, `${phase} ${JSON.stringify(call)}`).not.toMatch(/key 1|press 1/i)
          }
        }
      }
    }
  })
})

describe('finding 11: a move that did not go through, without buttons', () => {
  test('the line Claude reads has no key 1 in minimal mode, and tells Claude to run the steps again', { options: { uiMode: 'minimal' } }, async ($, on) => {
    const api = $ as unknown as Api
    run(on, { stage: 'intent_complete', next_stage: 'plan' }, { intent: 'PASS', plan: 'PASS' }, {}, ['Continue to Build (Recommended)'])
    await api.session.start(START)
    await api.tool.call(gate('The plan check passed. What next?', ['Continue to Build (Recommended)', 'Save for later']))
    const text = await system(api)
    expect(text).toContain("The user's move to Build is recorded but did not go through yet. Run its steps once more.")
    expect(text).not.toContain('Press 1')
  })

  test('full mode keeps the key', () => {
    expect(pendingLines({ type: 'advance', from: 'plan' }).idle).toBe('Your move to Build did not go through yet. Press 1 to finish it.')
  })
})

describe('finding 13: the reason question of a bar button fits the move', () => {
  test('each move has its own question and choices', () => {
    expect(reasonAsk('loop-back', 'Loop back to Plan')).toEqual({ question: 'Loop back to Plan. What is the reason?', options: ['The check found a real problem', 'The earlier step needs a change'] })
    expect(reasonAsk('restart', 'Start over').question).toBe('Start over. What is the reason?')
    expect(reasonAsk('restart', 'Start over').options).not.toContain('I accept the risk')
    expect(reasonAsk('override', 'Skip with a reason').options).toEqual(['I accept the risk', 'It is not a real issue'])
  })

  test('Start over from the bar menu asks the Start over question', { options: { moveCooldownMs: 0 } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = run(on, { stage: 'intent_complete', next_stage: 'plan' }, { intent: 'PASS' }, {}, ['This is the wrong feature'])
    await api.session.start(START)
    await (await band(api)).press({ key: 'action-more' })
    await (await band(api)).press({ key: 'action-restart' })
    expect(w.asked).toEqual(['Start over. What is the reason?'])
    expect(w.askedOptions[0]).toEqual(['This is the wrong feature', 'I want to start the work fresh'])
  })
})

describe('finding 14: the Build completion gate on FAIL', () => {
  test('key 1 at a failed Build with no task left runs Build again; the loop back to Plan stays in the menu', () => {
    const a = actionsFor('build', { gate: 'fail', task: { n: 1, of: 1 }, tasksLeft: 0 })
    expect(a.primary[0]?.label).toBe('Run Build again')
    expect(a.more.map(x => x.label)).toContain('Loop back to Plan')
  })

  test('the bar of a failed Build with every task done', async ($, on) => {
    const api = $ as unknown as Api
    run(on, { stage: 'plan_complete', next_stage: 'build' }, { plan: 'PASS', build: 'FAIL' }, { [`${SPEC}/tasks.md`]: ALL_DONE })
    await api.session.start(START)
    const text = await bar(api)
    expect(text).toContain('1 Run Build again')
    expect(text).not.toContain('1 Loop back to Plan')
  })
})

describe('finding 15: the group gate on the bar', () => {
  test('Change of a grouped checkpoint names the group', { options: { moveCooldownMs: 0 } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = run(on, { stage: 'plan_complete', next_stage: 'build', task: 3 }, { plan: 'PASS', build: 'FAIL' }, { '.temper/groups.json': '{}' })
    await api.session.start(START)
    expect(await bar(api)).toContain('Continue with the groups')
    await (await band(api)).press({ key: 'action-change' })
    expect(w.filled.map(f => f.text)).toEqual(['Change in this group: '])
  })
})

describe('finding 16: config suggestions after a passed Check', () => {
  test('the Done bar offers Review config suggestions when Check wrote them', async ($, on) => {
    const api = $ as unknown as Api
    run(on, { stage: 'review_complete', next_stage: 'check' }, { plan: 'PASS', build: 'PASS', review: 'PASS', check: 'PASS' }, { [`${SPEC}/config-suggestions.json`]: '[]' })
    await api.session.start(START)
    await sh(api, `${CLI} gate check`)
    const text = await bar(api)
    expect(text).toContain('Commit')
    expect(text).toContain('Review config suggestions')
  })

  test('without the file the Done bar has no such button', () => {
    expect(doneActions().primary.map(a => a.label)).toEqual(['Commit', 'Save for later'])
    expect(doneActions(undefined, true).primary.map(a => a.label)).toEqual(['Commit', 'Save for later', 'Review config suggestions'])
  })
})

describe('finding 17: the Plan gate when Design follows', () => {
  test('key 1 continues to Design, and the Next line says so', async ($, on) => {
    const api = $ as unknown as Api
    run(on, { stage: 'intent_complete', next_stage: 'plan', complexity: 'medium' }, { intent: 'PASS', plan: 'PASS' }, { '.claude/temper.config': 'phases:\n  design: true\n' })
    await api.session.start(START)
    expect(await bar(api)).toContain('1 Continue to Design. The plan is checked. Design opens and Claude designs.')
    expect(await system(api)).toContain('continue to Design')
  })

  test('without design on, it continues to Build', async ($, on) => {
    const api = $ as unknown as Api
    run(on, { stage: 'intent_complete', next_stage: 'plan', complexity: 'medium' }, { intent: 'PASS', plan: 'PASS' })
    await api.session.start(START)
    expect(await bar(api)).toContain('1 Continue to Build')
  })
})

describe('finding 19: a failed Check can loop back to Build in full mode', () => {
  test('the menu of the Fix step has Loop back to Build, until the fix limit', () => {
    expect(actionsFor('fix', {}).more.map(a => a.label)).toContain('Loop back to Build')
    expect(actionsFor('fix', { loopLimitReached: true }).more.map(a => a.label)).not.toContain('Loop back to Build')
  })

  test('the loop back to Build from a failed Check is recorded and its loop passes the guard', { options: { moveCooldownMs: 0 } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = run(on, { stage: 'review_complete', next_stage: 'check' }, { plan: 'PASS', build: 'PASS', review: 'PASS', check: 'FAIL' }, {}, ['The check found a real problem'])
    await api.session.start(START)
    await sh(api, `${CLI} gate check`)
    await (await band(api)).press({ key: 'action-more' })
    await (await band(api)).press({ key: 'action-loop-back' })
    expect(w.prompts.at(-1)).toContain('state loop check build')
    expect(await sh(api, `${CLI} state loop check build --reason 'The check found a real problem'`)).toBeUndefined()
    expect(await sh(api, `${CLI} state set next_stage build`)).toBeUndefined()
  })
})

describe('finding 20: a passed Check asks one question without buttons', () => {
  test('"Commit" at the Check gate is the move on', () => {
    expect(gateAnswer(result('Commit (Recommended)'), 'check')).toEqual({ type: 'advance' })
    expect(gateAnswer(result('Commit'), 'review')).toBeNull()
  })
})

describe('finding 23: a failed Intent check', () => {
  test('key 1 runs Intent again', () => {
    expect(actionsFor('intent', { gate: 'fail' }).primary[0]?.label).toBe('Run Intent again')
    expect(actionsFor('intent', { gate: 'none' }).primary[0]?.label).toBe('Start Intent')
  })
})

describe('finding 24: a refused press says what to click, with no typed command and no jargon', () => {
  test('every refusal of decide names no /temper:temper command and no gate command', () => {
    const states = [stateAt('intent'), stateAt('plan'), stateAt('build'), { ...stateAt('plan'), paused: true }, { ...stateAt('fix'), loopLimitReached: true, loops: 4 }, stateAt('review')]
    const cmds = [
      { type: 'advance' }, { type: 'approve' }, { type: 'back', to: 'plan', reason: '' }, { type: 'back', to: 'check', reason: 'x' },
      { type: 'override', reason: '' }, { type: 'acceptFinding', id: '1', reason: '' }, { type: 'restart', reason: '' }, { type: 'start', slug: 'x', title: 'x' },
    ] as const
    for (const s of states) {
      for (const c of cmds) {
        const d = decide(s, { ...c, origin: 'person' } as Parameters<typeof decide>[1])
        if ('error' in d) {
          expect(d.error, `${s.phase} ${c.type}`).not.toContain('/temper:')
          expect(d.error, `${s.phase} ${c.type}`).not.toContain('gate command')
        }
      }
    }
  })
})

describe('the section text without buttons (the orchestrator pages are checked by validate-docs.sh, check 8)', () => {
  test('the section text in off mode carries the Temper gate line and no key', () => {
    const text = sectionText({ enforcement: 'on', phase: 'review', title: null, progress: null, buttons: false, actionContext: { hasFindings: true } })
    expect(text).toContain('Temper buttons: none in this mode.')
    expect(text).toContain('loop back to Build, accept a finding, or override and continue')
    expect(text).not.toMatch(/key \d/)
  })
})

// ---- Batch B: the guard and the flow ------------------------------------------------------------

const PANE = { title: 'Temper', isFocused: false, bodyColumns: 80, placement: 'dock', scroll: { offset: 0, bodyRows: 20 }, view: {} } as const
const pane = (api: Api) => api.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'Pane', requestId: 'temper', props: PANE })
const typed = (api: Api, args: string) => api.command.run({ command: 'temper:temper', args, origin: { kind: 'composer' } })
const moves = (w: World): string[] =>
  [...w.files.entries()]
    .filter(([p]) => p.startsWith(`${SPEC}/events/`))
    .map(([, t]) => JSON.parse(t) as { type: string; ts: number; seq: number; from?: string; to?: string; phase?: string; stage?: string; origin?: string })
    .filter(e => e.type !== 'start')
    .sort((a, b) => a.ts - b.ts || a.seq - b.seq)
    .map(e => [e.type, e.from ?? e.phase ?? '', e.to ?? e.stage ?? '', e.origin ?? ''].join(':'))

describe('finding 2: the loop budget is spent', () => {
  test('full mode: after a BLOCKED loop the step back is void, and the skip moves the run on', { options: { moveCooldownMs: 0 } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = run(on, { stage: 'plan_complete', next_stage: 'build' }, { plan: 'PASS', build: 'FAIL' })
    w.loopsBlocked = true
    await api.session.start(START)
    await typed(api, 'back plan the plan misses a step')
    const loop = await api.tool.call({ tool: 'Bash', command: `${CLI} state loop build plan --reason 'the plan misses a step'` })
    expect(loop.deny).toBeUndefined()
    // The bar is back at a failed Build, with nothing waiting to be recorded.
    expect(await bar(api)).not.toContain('did not go through')
    await typed(api, 'override the plan is fine, ship it')
    expect(await sh(api, `${CLI} override build --reason 'the plan is fine, ship it'`)).toBeUndefined()
    expect(await sh(api, `${CLI} state advance build_complete review`)).toBeUndefined()
  })

  test('minimal mode: after a BLOCKED loop the Override answer is recorded', { options: { uiMode: 'minimal', moveCooldownMs: 0 } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = run(on, { stage: 'plan_complete', next_stage: 'build' }, { plan: 'PASS', build: 'FAIL' }, {}, ['Loop back to Plan: the plan misses a step', 'Override and continue: ship it'])
    w.loopsBlocked = true
    await api.session.start(START)
    await api.tool.call(gate('Build failed. What next?', ['Loop back to Plan', 'Override and continue', 'Save for later']))
    await sh(api, `${CLI} state loop build plan --reason 'the plan misses a step'`)
    await api.tool.call(gate('The loop back is used up. What next?', ['Override and continue', 'Save for later']))
    expect(moves(w)).toEqual(['back::plan:person', 'override:build::person'])
    expect(await sh(api, `${CLI} override build --reason 'ship it'`)).toBeUndefined()
    expect(await sh(api, `${CLI} state advance build_complete review`)).toBeUndefined()
  })

  test('a spent loop is not offered again: key 1 at a failed Review skips, and the menu has no loop back', async ($, on) => {
    const api = $ as unknown as Api
    const loops = JSON.stringify({ version: 1, active_loops: [{ id: 'loop-1', from_stage: 'review', to_stage: 'build', reason: 'x', iteration: 2, max_iterations: 2 }], history: [] })
    run(on, { stage: 'build_complete', next_stage: 'review' }, { plan: 'PASS', build: 'PASS', review: 'FAIL' }, { '.temper/feedback-loops.json': loops })
    await api.session.start(START)
    const text = await bar(api)
    expect(text).toContain('1 Skip with a reason. Loop back is used up.')
    expect(text).not.toContain('Loop back to Build')
  })
})

describe('finding 3: a saved run, taken up again', () => {
  test('minimal mode: Save for later, then Continue at the gate is recorded with the resume', { options: { uiMode: 'minimal', moveCooldownMs: 0 } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = run(on, { stage: 'intent_complete', next_stage: 'plan' }, { intent: 'PASS', plan: 'PASS' }, {}, ['Save for later', 'Continue to Build (Recommended)'])
    await api.session.start(START)
    await api.tool.call(gate('The plan check passed. What next?', ['Continue to Build (Recommended)', 'Save for later']))
    await api.tool.call(gate('The plan check passed. What next?', ['Continue to Build (Recommended)', 'Save for later']))
    expect(moves(w)).toEqual(['pause:::person', 'resume:::person', 'advance:plan:build:person'])
    expect(await sh(api, `${CLI} state advance plan_complete build`)).toBeUndefined()
  })

  test('full mode: key 1 on a saved run takes it up and moves on, and the bar says it is saved', { options: { moveCooldownMs: 0 } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = run(on, { stage: 'intent_complete', next_stage: 'plan' }, { intent: 'PASS', plan: 'PASS' })
    await api.session.start(START)
    await typed(api, 'pause')
    expect(await bar(api)).toContain('The run is saved for later; a choice takes it up again. 1 Continue to Build')
    await (await band(api)).press({ key: 'action-continue' })
    expect(moves(w)).toEqual(['pause:::person', 'resume:::person', 'advance:plan:build:person'])
    expect(w.toasts.join('|')).not.toContain('saved for later')
  })

  test('a bare /temper:temper of the person on a saved run records the resume and goes to the orchestrator', async ($, on) => {
    const api = $ as unknown as Api
    const w = run(on, { stage: 'intent_complete', next_stage: 'plan' }, { intent: 'PASS', plan: 'PASS' })
    await api.session.start(START)
    await typed(api, 'pause')
    await typed(api, '')
    expect(moves(w)).toEqual(['pause:::person', 'resume:::person'])
    expect(w.commandRuns.at(-1)?.args).toBe('')
  })
})

describe('finding 4: arming autonomy at the plan gate', () => {
  test('"Stage by stage" and "Autonomous" approve the plan; not at the Design gate', () => {
    expect(gateAnswer(result('Stage by stage (Recommended)'), 'plan')).toEqual({ type: 'approve' })
    expect(gateAnswer(result('Autonomous: run the rest unattended'), 'plan')).toEqual({ type: 'approve' })
    expect(gateAnswer(result('Autonomous: run the rest unattended'), 'plan', { atDesign: true })).toBeNull()
    expect(gateAnswer(result('Autonomous: run the rest unattended'), 'build')).toBeNull()
  })

  test('full mode: the arming answer lets the plan advance and state set run_mode autonomous through', async ($, on) => {
    const api = $ as unknown as Api
    const w = run(on, { stage: 'intent_complete', next_stage: 'plan' }, { intent: 'PASS', plan: 'PASS' }, { '.claude/temper.config': 'autonomy:\n  enabled: true\n' }, ['Autonomous: run the rest unattended'])
    await api.session.start(START)
    expect(await sh(api, `${CLI} state set run_mode autonomous`)).toContain('only the user can turn on autonomous mode')
    await api.tool.call(gate('The plan check passed. How should the rest run?', ['Stage by stage (Recommended)', 'Autonomous: run the rest unattended', 'Save for later']))
    expect(moves(w)).toEqual(['advance:plan:build:person'])
    expect(await sh(api, `${CLI} state advance plan_complete build`)).toBeUndefined()
    expect(await sh(api, `${CLI} state set run_mode autonomous`)).toBeUndefined()
  })
})

describe('finding 5: an armed autonomous run that fails a check', () => {
  const armed = { '.claude/temper.config': 'autonomy:\n  enabled: true\n' }
  const approved = async (api: Api, w: World) => {
    // The person approved the plan earlier in this run (the bar's Continue), and the run went on to Review.
    await (await band(api)).press({ key: 'action-continue' })
    expect(await sh(api, `${CLI} state advance plan_complete build`)).toBeUndefined()
    const d = JSON.parse(w.files.get('.temper/build-state.json') ?? '{}') as Record<string, unknown>
    w.files.set('.temper/build-state.json', JSON.stringify({ ...d, next_stage: 'review', stage: 'build_complete', run_mode: 'autonomous' }))
    w.files.set('.temper/gates.json', JSON.stringify({ plan: { verdict: 'PASS', ts: LATER }, build: { verdict: 'PASS', ts: LATER }, review: { verdict: 'FAIL', ts: LATER } }))
    await typed(api, 'status')
  }

  test('the loop back to Build passes the guard, and the run follows the CLI back to Build', { options: { moveCooldownMs: 0 } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = run(on, { stage: 'intent_complete', next_stage: 'plan' }, { intent: 'PASS', plan: 'PASS' }, armed)
    await api.session.start(START)
    await approved(api, w)
    expect(await sh(api, `${CLI} state loop review build --reason 'R-1 is real'`)).toBeUndefined()
    expect(await sh(api, `${CLI} state set next_stage build`)).toBeUndefined()
    await typed(api, 'status')
    const text = await system(api)
    expect(text).toContain('Phase: Build')
    expect(text).not.toContain('looks reset')
    // Never back to Plan unattended.
    expect(await sh(api, `${CLI} state loop build plan --reason x`)).toBeDefined()
  })

  test('without the armed run mode the same loop is refused', { options: { moveCooldownMs: 0 } }, async ($, on) => {
    const api = $ as unknown as Api
    run(on, { stage: 'build_complete', next_stage: 'review' }, { plan: 'PASS', build: 'PASS', review: 'FAIL' }, armed)
    await api.session.start(START)
    expect(await sh(api, `${CLI} state loop review build --reason x`)).toBeDefined()
  })

  test('the park report may be written in any phase', async ($, on) => {
    const api = $ as unknown as Api
    run(on, { stage: 'build_complete', next_stage: 'review' }, { plan: 'PASS', build: 'PASS', review: 'FAIL' })
    await api.session.start(START)
    expect(await write(api, '.temper/autonomy-report.md')).toBeUndefined()
    expect(await write(api, '.temper/other.md')).toBeDefined()
  })
})

describe('finding 6: the Design gate', () => {
  const cfg = { '.claude/temper.config': 'phases:\n  design: true\n', [`${SPEC}/design.md`]: '# Design\n' }
  const verdicts = (design: 'PASS' | 'FAIL') => ({ '.temper/gates.json': JSON.stringify({ intent: { verdict: 'PASS', ts: LATER }, plan: { verdict: 'PASS', ts: LATER }, design: { verdict: design, ts: LATER } }) })
  const atDesign = { stage: 'plan_complete', next_stage: 'design', complexity: 'medium' }

  test('a failed design: key 1 loops back to Plan, never Continue to Build', async ($, on) => {
    const api = $ as unknown as Api
    run(on, atDesign, {}, { ...cfg, ...verdicts('FAIL') })
    await api.session.start(START)
    const text = await bar(api)
    expect(text).toContain('1 Loop back to Plan')
    expect(text).not.toContain('Continue to Build')
  })

  test('a passed design: key 1 continues to Build', async ($, on) => {
    const api = $ as unknown as Api
    run(on, atDesign, {}, { ...cfg, ...verdicts('PASS') })
    await api.session.start(START)
    expect(await bar(api)).toContain('1 Continue to Build')
  })

  test('the loop back to Plan is recorded and its loop from design passes the guard', { options: { moveCooldownMs: 0 } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = run(on, atDesign, {}, { ...cfg, ...verdicts('FAIL') }, ['The check found a real problem'])
    await api.session.start(START)
    await (await band(api)).press({ key: 'action-loop-back' })
    expect(moves(w)).toEqual(['back::plan:person'])
    expect(w.prompts.at(-1)).toContain('state loop design plan')
    expect(await sh(api, `${CLI} state loop design plan --reason 'The check found a real problem'`)).toBeUndefined()
    expect(await sh(api, `${CLI} state set next_stage plan`)).toBeUndefined()
  })

  test('Loop back to Plan is an answer at the Design gate', () => {
    expect(gateAnswer(result('Loop back to Plan: the API changed'), 'plan', { atDesign: true })).toEqual({ type: 'back', to: 'plan', reason: 'the API changed' })
    expect(gateAnswer(result('Loop back to Plan: the API changed'), 'plan')).toBeNull()
  })

  test('a skip at the Design gate is mirrored as override design, and the design advance follows it', { options: { moveCooldownMs: 0 } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = run(on, atDesign, {}, { ...cfg, ...verdicts('FAIL') })
    await api.session.start(START)
    await (await band(api)).input({ key: 'override-reason', text: 'the concern is owned by the platform team' })
    expect(moves(w)).toEqual(['override:plan:design:person'])
    expect(w.prompts.at(-1)).toContain('override design')
    expect(w.commandRuns.at(-1)?.args).toBe('continue design')
    expect(await sh(api, `${CLI} override design --reason 'the concern is owned by the platform team'`)).toBeUndefined()
    expect(await sh(api, `${CLI} state advance design_complete build`)).toBeUndefined()
  })

  test('without a pass or a skip the design advance is refused', async ($, on) => {
    const api = $ as unknown as Api
    run(on, atDesign, {}, { ...cfg, ...verdicts('FAIL') })
    await api.session.start(START)
    expect(await sh(api, `${CLI} state advance design_complete build`)).toBeDefined()
  })
})

describe('finding 8: the pane Fix button of a finding', () => {
  test('Fix loops back to Build for that finding; Build may then write the file', { options: { moveCooldownMs: 0 } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = run(on, { stage: 'build_complete', next_stage: 'review' }, { plan: 'PASS', build: 'PASS', review: 'FAIL' }, { '.temper/evidence/review.json': JSON.stringify([{ severity: 'high', claim: 'src/app.ts: token never expires' }]) })
    await api.session.start(START)
    expect(await write(api, 'src/app.ts')).toBeDefined()
    await (await pane(api)).press({ key: 'fix-1' })
    expect(moves(w)).toEqual(['back::build:person'])
    expect(w.prompts.at(-1)).toContain('state loop review build')
    expect(w.prompts.at(-1)).toContain('fix review finding 1: src/app.ts: token never expires')
    expect(await sh(api, `${CLI} state loop review build --reason 'fix review finding 1'`)).toBeUndefined()
    expect(await sh(api, `${CLI} state set next_stage build`)).toBeUndefined()
    expect(await write(api, 'src/app.ts')).toBeUndefined()
  })
})

describe('finding 12: accepting one finding without buttons', () => {
  test('"Accept finding N" with a reason, and the reason question', () => {
    expect(gateAnswer(result('Accept finding 1: the token is short lived anyway'), 'review')).toEqual({ type: 'acceptFinding', id: '1', reason: 'the token is short lived anyway' })
    expect(gateAnswer(result('Accept finding 2'), 'review')).toBeNull()
    expect(gateAnswer(result('It is not a real issue', 'Temper gate', 'Accept finding 2. What is the reason?'), 'review')).toEqual({ type: 'acceptFinding', id: '2', reason: 'It is not a real issue' })
    expect(gateAnswer(result('Accept finding 1: x'), 'build')).toBeNull()
  })

  test('minimal mode: the answer lets the evidence accept call through once', { options: { uiMode: 'minimal' } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = run(on, { stage: 'build_complete', next_stage: 'review' }, { plan: 'PASS', build: 'PASS', review: 'FAIL' }, { '.temper/evidence/review.json': JSON.stringify([{ severity: 'high', claim: 'x' }]) }, ['It is not a real issue'])
    await api.session.start(START)
    expect(await sh(api, `${CLI} evidence accept --stage review --id 1 --reason 'It is not a real issue'`)).toBeDefined()
    await api.tool.call(gate('Accept finding 1. What is the reason?', ['It is not a real issue', 'I accept the risk', 'Cancel']))
    expect(moves(w)).toEqual(['accept:::person'])
    expect(await sh(api, `${CLI} evidence accept --stage review --id 1 --reason 'It is not a real issue'`)).toBeUndefined()
  })
})

describe('U1: the commit gate FAIL after the run is done', () => {
  const done = async (api: Api) => {
    await api.session.start(START)
    await sh(api, `${CLI} gate check`)
  }

  test('Claude cannot record an override the person did not choose', async ($, on) => {
    const api = $ as unknown as Api
    run(on, { stage: 'review_complete', next_stage: 'check' }, { plan: 'PASS', build: 'PASS', review: 'PASS', check: 'PASS' })
    await done(api)
    expect(await bar(api)).toContain('Commit')
    expect(await sh(api, `${CLI} override design --reason 'no design needed'`)).toContain('"Override and commit"')
  })

  test('"Override and commit" with a reason lets the overrides of one command through, once', async ($, on) => {
    const api = $ as unknown as Api
    const w = run(on, { stage: 'review_complete', next_stage: 'check' }, { plan: 'PASS', build: 'PASS', review: 'PASS', check: 'PASS' }, {}, ['I accept the risk'])
    await done(api)
    await api.tool.call(gate('Override and commit. What is the reason?', ['I accept the risk', 'It is not a real issue', 'Cancel']))
    expect(moves(w).at(-1)).toBe('override:check:commit:person')
    expect(await sh(api, `${CLI} override design --reason 'I accept the risk'; ${CLI} override intent --reason 'I accept the risk'`)).toBeUndefined()
    expect(await sh(api, `${CLI} override design --reason 'again'`)).toBeDefined()
  })

  test('the answer is read at Done, and nowhere else', () => {
    expect(gateAnswer(result('Override and commit: I accept the risk'), 'done')).toEqual({ type: 'override', reason: 'I accept the risk', stage: 'commit' })
    expect(gateAnswer(result('Override and commit'), 'done')).toBeNull()
    expect(gateAnswer(result('Override and commit: x'), 'check')).toBeNull()
  })
})

// ---- Batch C: fix runs, parked groups, standalone commands --------------------------------------

function fixRun(on: Parameters<typeof world>[0], next: string, gates: Record<string, 'PASS' | 'FAIL'> = {}, extra: Record<string, string> = {}): World {
  const files: Record<string, string> = { ...runFiles({ gates }), ...extra }
  for (const name of ['plan.md', 'tasks.md', 'intent.md']) delete files[`${SPEC}/${name}`]
  files[`${SPEC}/rca.md`] = '# RCA\n'
  files['.temper/build-state.json'] = JSON.stringify({ spec: 'pw', spec_path: SPEC, command: 'fix', branch: 'fix/pw', stage: next === 'rca' ? 'started' : 'rca_complete', next_stage: next })
  files['/repo/.git/HEAD'] = 'ref: refs/heads/fix/pw\n'
  return world(on, files, { fakeCli: true, projectRoot: '/repo' })
}

describe('finding 1: a /temper:fix run with the mod, enforcement on', () => {
  for (const uiMode of ['full', 'minimal', 'off']) {
    test(`${uiMode} mode: the mod stands aside, so every step of fix.md goes through`, { options: { uiMode } }, async ($, on) => {
      const api = $ as unknown as Api
      fixRun(on, 'rca', { build: 'FAIL' })
      await api.session.start(START)
      expect(await write(api, 'src/cart.py')).toBeUndefined()
      expect(await sh(api, `${CLI} state advance rca_complete fix`)).toBeUndefined()
      expect(await sh(api, `${CLI} override build --reason 'flaky test tracked'`)).toBeUndefined()
      expect(await sh(api, `${CLI} state advance fix_complete review`)).toBeUndefined()
      expect(await sh(api, `${CLI} state loop review fix --reason 'the fix is not enough'`)).toBeUndefined()
      expect(await write(api, 'src/cart.py')).toBeUndefined()
      expect(await sh(api, 'git commit -m "fix(cart): x"')).toBeUndefined()
    })
  }

  test('the bar draws nothing for a fix run, and Claude reads that the bar stands aside', async ($, on) => {
    const api = $ as unknown as Api
    fixRun(on, 'fix')
    await api.session.start(START)
    expect(await bar(api)).not.toContain('Fix the failures')
    expect(await system(api)).toContain('Phase: a /temper:fix run. The Temper bar and its guard stand aside for it')
    expect((await typed(api, 'approve')).text).toContain('a /temper:fix run')
  })

  test('a /temper run held from before does not apply to the fix run that replaced it', async ($, on) => {
    const api = $ as unknown as Api
    const w = run(on, { stage: 'intent_complete', next_stage: 'plan' }, { intent: 'PASS' })
    await api.session.start(START)
    expect(await write(api, 'src/cart.py')).toBeDefined()
    w.files.set('.temper/build-state.json', JSON.stringify({ spec: 'bug', spec_path: '.temper/specs/bug', command: 'fix', stage: 'started', next_stage: 'rca' }))
    await typed(api, 'status')
    expect(await write(api, 'src/cart.py')).toBeUndefined()
  })
})

describe('finding 7: a group parked on a task agent\'s commits', () => {
  test('"Keep the agent\'s commits" with a reason is the decision, in Build only', () => {
    expect(gateAnswer(result("Keep the agent's commits: the commit is the task's own work"), 'build')).toEqual({ type: 'override', reason: "the commit is the task's own work", stage: 'foreign-commit' })
    expect(gateAnswer(result("Keep the agent's commits"), 'build')).toBeNull()
    expect(gateAnswer(result('I accept the risk', 'Temper gate', "Keep the agent's commits. What is the reason?"), 'build')).toEqual({ type: 'override', reason: 'I accept the risk', stage: 'foreign-commit' })
    expect(gateAnswer(result("Keep the agent's commits: x"), 'review')).toBeNull()
  })

  for (const uiMode of ['full', 'minimal']) {
    test(`${uiMode} mode: the answer lets one reopen with --accept-foreign through, and moves nothing`, { options: { uiMode, moveCooldownMs: 0 } }, async ($, on) => {
      const api = $ as unknown as Api
      const w = run(on, { stage: 'plan_complete', next_stage: 'build', task: 2 }, { plan: 'PASS', build: 'FAIL' }, { '.temper/groups.json': '{}' }, ['The commits are right'])
      await api.session.start(START)
      const reopen = `${CLI} group reopen G1 --task 2 --accept-foreign abc1234 --reason 'The commits are right'`
      expect(await sh(api, reopen)).toBeDefined()
      await api.tool.call(gate("Keep the agent's commits. What is the reason?", ['The commits are right', 'I accept the risk', 'Cancel']))
      expect(moves(w)).toEqual(['override:build:foreign-commit:person'])
      // Build is not skipped and nothing waits to be recorded: the run stays at the group gate.
      expect(await bar(api)).not.toContain('did not go through')
      expect(await sh(api, `${CLI} override build --reason x`)).toBeDefined()
      expect(await sh(api, `${CLI} state advance build_complete review`)).toBeDefined()
      expect(await sh(api, reopen)).toBeUndefined()
      expect(await sh(api, reopen)).toBeDefined()
    })
  }
})

describe('finding 9: standalone /temper:build starts its run and walks it to Build by clicks', () => {
  test('with the mod: the two Temper gate answers move the new run to Build, and Build may write its plan files', { options: { uiMode: 'minimal' } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = run(on, { stage: 'started', next_stage: 'intent' }, { intent: 'PASS' }, {}, ['Continue to Plan (Recommended)', 'Continue to Build (Recommended)'])
    await api.session.start(START)
    expect(await write(api, 'src/app.ts')).toBeDefined()
    await api.tool.call(gate('The intent check passed. What next?', ['Continue to Plan (Recommended)', 'Save for later']))
    expect(await sh(api, `${CLI} state advance intent_complete plan`)).toBeUndefined()
    w.files.set('.temper/gates.json', JSON.stringify({ intent: { verdict: 'PASS', ts: LATER }, plan: { verdict: 'PASS', ts: LATER } }))
    await typed(api, 'status')
    await api.tool.call(gate('The plan check passed. What next?', ['Continue to Build (Recommended)', 'Save for later']))
    expect(await sh(api, `${CLI} state advance plan_complete build`)).toBeUndefined()
    await typed(api, 'status')
    expect(await write(api, 'src/app.ts')).toBeUndefined()
  })
})

describe('finding 25: standalone /temper:plan and /temper:check never write the run state by hand', () => {
  test('the guard refuses a hand written build-state.json, with or without a run', async ($, on) => {
    const api = $ as unknown as Api
    world(on, {}, { projectRoot: '/repo' })
    await api.session.start(START)
    expect(await write(api, '.temper/build-state.json')).toContain('use the temper CLI to change run state')
  })
})

// ---- Batch D: the second, independent audit -----------------------------------------------------

describe('second audit 1: the CLI went on with no move of the person (a verdict was enough), then the person skips', () => {
  // The person approved the plan (the bar's Continue); then the orchestrator moved the CLI on by itself on passed checks.
  const lagged = async (api: Api, w: World, next: string, gates: Record<string, 'PASS' | 'FAIL'>, extra: Record<string, unknown> = {}) => {
    await (await band(api)).press({ key: 'action-continue' })
    expect(await sh(api, `${CLI} state advance plan_complete build`)).toBeUndefined()
    const d = JSON.parse(w.files.get('.temper/build-state.json') ?? '{}') as Record<string, unknown>
    w.files.set('.temper/build-state.json', JSON.stringify({ ...d, next_stage: next, ...extra }))
    w.files.set('.temper/gates.json', JSON.stringify(Object.fromEntries(Object.entries(gates).map(([k, v]) => [k, { verdict: v, ts: LATER }]))))
    await typed(api, 'status')
  }

  test('a failed Review: the skip is recorded, mirrored, and the advance out of Review goes through', { options: { moveCooldownMs: 0 } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = run(on, { stage: 'intent_complete', next_stage: 'plan' }, { intent: 'PASS', plan: 'PASS' })
    await api.session.start(START)
    await lagged(api, w, 'review', { plan: 'PASS', build: 'PASS', review: 'FAIL' })
    await (await band(api)).input({ key: 'override-reason', text: 'reviewed by hand' })
    expect(await sh(api, `${CLI} override review --reason 'reviewed by hand'`)).toBeUndefined()
    expect(await sh(api, `${CLI} state advance review_complete check`)).toBeUndefined()
  })

  test('minimal mode: the same with the Override answer', { options: { uiMode: 'minimal', moveCooldownMs: 0 } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = run(on, { stage: 'intent_complete', next_stage: 'plan' }, { intent: 'PASS', plan: 'PASS' }, {}, ['Continue to Build (Recommended)', 'Override and continue: reviewed by hand'])
    await api.session.start(START)
    await api.tool.call(gate('The plan check passed. What next?', ['Continue to Build (Recommended)', 'Save for later']))
    expect(await sh(api, `${CLI} state advance plan_complete build`)).toBeUndefined()
    const d = JSON.parse(w.files.get('.temper/build-state.json') ?? '{}') as Record<string, unknown>
    w.files.set('.temper/build-state.json', JSON.stringify({ ...d, next_stage: 'review' }))
    w.files.set('.temper/gates.json', JSON.stringify({ plan: { verdict: 'PASS', ts: LATER }, build: { verdict: 'PASS', ts: LATER }, review: { verdict: 'FAIL', ts: LATER } }))
    await typed(api, 'status')
    await api.tool.call(gate('The review found problems. What next?', ['Loop back to Build', 'Override and continue', 'Save for later']))
    expect(await sh(api, `${CLI} override review --reason 'reviewed by hand'`)).toBeUndefined()
    expect(await sh(api, `${CLI} state advance review_complete check`)).toBeUndefined()
  })

  test('a failed Check after such a run opens the Fix step, with a loop back to Build', { options: { moveCooldownMs: 0 } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = run(on, { stage: 'intent_complete', next_stage: 'plan' }, { intent: 'PASS', plan: 'PASS' })
    await api.session.start(START)
    await lagged(api, w, 'check', { plan: 'PASS', build: 'PASS', review: 'PASS', check: 'FAIL' })
    await sh(api, `${CLI} gate check`)
    const b = await band(api)
    const main = JSON.stringify(await b.drawn())
    expect(main).toContain('Fix the failures')
    await b.press({ key: 'action-more' })
    expect(await bar(api)).toContain('Loop back to Build')
  })
})

describe('second audit 2: accepting one finding in full mode, with no pane open', () => {
  test('the bar offers "Accept a finding": it asks which one and why, and records it', { options: { moveCooldownMs: 0 } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = run(on, { stage: 'build_complete', next_stage: 'review' }, { plan: 'PASS', build: 'PASS', review: 'FAIL' }, { '.temper/evidence/review.json': JSON.stringify([{ severity: 'high', claim: 'src/app.ts: token never expires' }]) }, ['Finding 1: src/app.ts: token never expires', 'It is not a real issue'])
    await api.session.start(START)
    await (await band(api)).press({ key: 'action-more' })
    await (await band(api)).press({ key: 'action-accept-finding' })
    expect(w.asked).toEqual(['Which finding do you accept?', 'Accept finding 1. What is the reason?'])
    expect(moves(w)).toEqual(['accept:::person'])
    expect(w.prompts.at(-1)).toContain('evidence accept --stage review --id 1')
  })
})

describe('second audit 8: a bare "Continue" is the move on', () => {
  test('"Continue" and "Continue (Recommended)" approve at Plan and move on after it', () => {
    expect(gateAnswer(result('Continue (Recommended)'), 'plan')).toEqual({ type: 'approve' })
    expect(gateAnswer(result('Continue'), 'review')).toEqual({ type: 'advance' })
  })
})

describe('second audit 9: a new answer while an earlier move waits to be recorded', () => {
  test('minimal mode: a different move is recorded; the same move again is not', { options: { uiMode: 'minimal', moveCooldownMs: 0 } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = run(on, { stage: 'plan_complete', next_stage: 'build' }, { plan: 'PASS', build: 'PASS' }, {}, ['Continue to Review (Recommended)', 'Continue to Review (Recommended)', 'Loop back to Plan: the plan is wrong after all'])
    await api.session.start(START)
    await api.tool.call(gate('Build passed. What next?', ['Continue to Review (Recommended)', 'Save for later']))
    await api.tool.call(gate('Build passed. What next?', ['Continue to Review (Recommended)', 'Save for later']))
    expect(moves(w)).toEqual(['advance:build:review:person'])
    await api.tool.call(gate('Build passed. What next?', ['Continue to Review (Recommended)', 'Loop back to Plan', 'Save for later']))
    expect(moves(w)).toEqual(['advance:build:review:person', 'back::plan:person'])
    expect(await sh(api, `${CLI} state loop build plan --reason 'the plan is wrong after all'`)).toBeUndefined()
    expect(await sh(api, `${CLI} state set next_stage plan`)).toBeUndefined()
  })
})

describe('second audit 11: the last group gate in full mode', () => {
  test('with every task done and the build check not run yet, the bar offers the group gate', async ($, on) => {
    const api = $ as unknown as Api
    run(on, { stage: 'plan_complete', next_stage: 'build' }, { plan: 'PASS' }, { '.temper/groups.json': '{}', [`${SPEC}/tasks.md`]: ALL_DONE })
    await api.session.start(START)
    const text = await bar(api)
    expect(text).toContain('Continue with the groups')
    expect(text).toContain('Stop')
  })
})

describe('second audit 15: Run Build again after a failed build check', () => {
  test('key 1 tells Claude what to mend, not only to resume', () => {
    const a = actionsFor('build', { gate: 'fail', task: { n: 1, of: 1 }, tasksLeft: 0 }).primary[0]
    expect(a?.label).toBe('Run Build again')
    expect(a?.prompt).toContain('failed build check')
  })
})

describe('second audit 16: the Next line of the Fix step waits for the person', () => {
  test('it asks the person, with buttons and without', () => {
    expect(nextStep('fix', {})).toContain('Temper bar')
    expect(nextStep('fix', {})).not.toMatch(/^fix the failed checks/)
    expect(nextStep('fix', { buttons: false })).toContain('`Temper gate`')
    expect(nextStep('fix', { buttons: false, allChecksPass: true })).toContain('continue to Check')
  })
})
