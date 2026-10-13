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
type Mounted = { press: (a: { key: string }) => Promise<void>; drawn: () => Promise<unknown> }
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
