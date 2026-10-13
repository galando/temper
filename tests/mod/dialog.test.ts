// End to end, through the test world and its fake CLI (ADR 0012): the person decides only in the question dialogs,
// the mod reads the answer from the dialog's result and keeps it for the CLI's run and step, and the guard lets through
// what that answer allows at that step, and nothing more. Every wait point of the flow audit is here.
import { describe, expect, test } from 'claude-code/testing'

import { ONLY_USER } from '../../hooks/temper-mod/core/rules'
import { SPEC, runFiles } from './run-files'
import { COMPOSE, world } from './world'
import type { World } from './world'

const CLI = '/home/u/.claude/plugins/temper/scripts/temper'
const START = { cwd: '/repo', surface: 'terminal', isInteractive: true } as const
type Api = {
  session: { start: (a: unknown) => Promise<unknown> }
  command: { run: (a: unknown) => Promise<{ text?: string }> }
  tool: { call: (a: unknown) => Promise<{ deny?: string; text?: string }> }
  prompt: { compose: (a: unknown) => Promise<{ sections: Array<{ text: string }> }> }
}
const sh = async (api: Api, command: string) => (await api.tool.call({ tool: 'Bash', command })).deny
const write = async (api: Api, path: string) => (await api.tool.call({ tool: 'Write', file_path: `/repo/${path}`, content: 'x' })).deny
const ask = (api: Api, header = 'Temper gate', question = 'What next?', options: string[] = ['Continue', 'Save for later']) =>
  api.tool.call({ tool: 'AskUserQuestion', questions: [{ question, header, multiSelect: false, options: options.map(label => ({ label, description: label })) }] })
const system = async (api: Api) => (await api.prompt.compose(COMPOSE)).sections.at(-1)?.text ?? ''
const decisions = (w: World): Array<{ kind: string; stage: string; step: number }> => Object.entries(w.store).filter(([k]) => k.startsWith('dec:')).flatMap(([, v]) => v as Array<{ kind: string; stage: string; step: number }>)
const state = (w: World): Record<string, unknown> => JSON.parse(w.files.get('.temper/build-state.json') ?? '{}') as Record<string, unknown>
const gates = (w: World, g: Record<string, 'PASS' | 'FAIL'>) => w.files.set('.temper/gates.json', JSON.stringify(Object.fromEntries(Object.entries(g).map(([k, v]) => [k, { verdict: v }]))))

function begin(on: Parameters<typeof world>[0], next: string, g: Record<string, 'PASS' | 'FAIL'> = {}, answers: string[] = [], extra: Record<string, string> = {}): World {
  const files = { ...runFiles({ gates: g }), ...extra }
  files['.temper/build-state.json'] = JSON.stringify({ spec: 'pw', spec_path: SPEC, command: 'temper', branch: 'feature/pw', next_stage: next, run_id: 'run-pw', step: 3, run_mode: 'interactive', ...JSON.parse(extra['.temper/build-state.json'] ?? '{}') })
  files['/repo/.git/HEAD'] = 'ref: refs/heads/feature/pw\n'
  return world(on, files, { fakeCli: true, projectRoot: '/repo', answers })
}

describe('a gate is decided in the Temper gate question, and only there', () => {
  test('Intent: the advance is refused until the person answers Continue; then it goes through once', async ($, on) => {
    const api = $ as unknown as Api
    const w = begin(on, 'intent', { intent: 'PASS' }, ['Continue to Plan (Recommended)'])
    await api.session.start(START)
    expect(await sh(api, `${CLI} state advance intent_complete plan`)).toBe(ONLY_USER)
    await ask(api)
    expect(decisions(w).map(d => d.kind)).toEqual(['approve'])
    expect(await sh(api, `${CLI} state advance intent_complete plan`)).toBeUndefined()
    expect(state(w).next_stage).toBe('plan')
    // The run moved on: the approval was for the Intent step, and the Plan step needs its own.
    expect(await sh(api, `${CLI} state advance plan_complete build`)).toBe(ONLY_USER)
  })

  test('a typed approve records nothing: it goes on to the orchestrator, which asks the question', async ($, on) => {
    const api = $ as unknown as Api
    const w = begin(on, 'plan', { plan: 'PASS' })
    await api.session.start(START)
    await api.command.run({ command: 'temper:temper', args: 'approve', origin: { kind: 'composer' } })
    expect(decisions(w)).toEqual([])
    expect(w.commandRuns.map(c => c.args)).toContain('approve')
    expect(await sh(api, `${CLI} state advance plan_complete build`)).toBe(ONLY_USER)
  })

  test('an answer in a question with another header decides nothing', async ($, on) => {
    const api = $ as unknown as Api
    const w = begin(on, 'plan', { plan: 'PASS' }, ['Continue to Build'])
    await api.session.start(START)
    await ask(api, 'Something else')
    expect(decisions(w)).toEqual([])
  })

  test('the latest answer at a step replaces the earlier one', async ($, on) => {
    const api = $ as unknown as Api
    const w = begin(on, 'review', { plan: 'PASS', build: 'PASS', review: 'FAIL' }, ['Loop back to Build: the token bug is real', 'Override and continue: reviewed by hand'])
    await api.session.start(START)
    await ask(api)
    await ask(api)
    expect(await sh(api, `${CLI} state loop review build --reason x`)).toBeDefined()
    expect(await sh(api, `${CLI} override review --reason 'reviewed by hand'`)).toBeUndefined()
    expect(await sh(api, `${CLI} state advance review_complete check`)).toBeUndefined()
    // At Check the earlier step back counts for nothing.
    expect(await sh(api, `${CLI} state loop check build --reason x`)).toBeDefined()
  })

  test('a step back is let through once: back at the same stage later, it needs a new answer', async ($, on) => {
    const api = $ as unknown as Api
    const w = begin(on, 'review', { plan: 'PASS', build: 'PASS', review: 'FAIL' }, ['Loop back to Build: a real bug'])
    await api.session.start(START)
    await ask(api)
    expect(await sh(api, `${CLI} state loop review build --reason 'a real bug'`)).toBeUndefined()
    expect(state(w).next_stage).toBe('build')
    // The CLI cleared the verdicts it redoes; Build passes again, Review fails again.
    gates(w, { plan: 'PASS', build: 'PASS' })
    expect(await sh(api, `${CLI} state advance build_complete review`)).toBeUndefined()
    gates(w, { plan: 'PASS', build: 'PASS', review: 'FAIL' })
    expect(await sh(api, `${CLI} state loop review build --reason again`)).toBeDefined()
    expect(await sh(api, `${CLI} state advance review_complete check`)).toBe(ONLY_USER)
  })

  test('a skip made before a loop back does not count for the redone stage', async ($, on) => {
    const api = $ as unknown as Api
    const w = begin(on, 'review', { plan: 'PASS', build: 'PASS', review: 'FAIL' }, ['Override and continue: reviewed by hand', 'Loop back to Build: a test fails'])
    await api.session.start(START)
    await ask(api)
    expect(await sh(api, `${CLI} override review --reason 'reviewed by hand'`)).toBeUndefined()
    expect(await sh(api, `${CLI} state advance review_complete check`)).toBeUndefined()
    gates(w, { plan: 'PASS', build: 'PASS', check: 'FAIL' })
    await ask(api)
    expect(await sh(api, `${CLI} state loop check build --reason 'a test fails'`)).toBeUndefined()
    gates(w, { plan: 'PASS', build: 'PASS' })
    expect(await sh(api, `${CLI} state advance build_complete review`)).toBeUndefined()
    gates(w, { plan: 'PASS', build: 'PASS', review: 'FAIL' })
    expect(await sh(api, `${CLI} state advance review_complete check`)).toBe(ONLY_USER)
  })

  test('a new run on the same spec folder starts with no decision', async ($, on) => {
    const api = $ as unknown as Api
    const w = begin(on, 'plan', { plan: 'PASS' }, ['Continue to Build'])
    await api.session.start(START)
    await ask(api)
    // Start over: the person's answer, then the new run.
    w.files.set('.temper/build-state.json', JSON.stringify({ ...state(w), run_id: 'run-new', step: 1, next_stage: 'plan' }))
    expect(await sh(api, `${CLI} state advance plan_complete build`)).toBe(ONLY_USER)
  })
})

describe('every wait point of the flow audit', () => {
  test('Check FAIL: Override and continue skips Check, and the run goes on to the commit stage', async ($, on) => {
    const api = $ as unknown as Api
    const w = begin(on, 'check', { plan: 'PASS', build: 'PASS', review: 'PASS', check: 'FAIL' }, ['Override and continue: the flaky test is known'])
    await api.session.start(START)
    expect(await sh(api, `${CLI} override check --reason x`)).toBe(ONLY_USER)
    await ask(api)
    expect(await sh(api, `${CLI} override check --reason 'the flaky test is known'`)).toBeUndefined()
    expect(await sh(api, `${CLI} state advance check_complete commit`)).toBeUndefined()
    expect(state(w).next_stage).toBe('commit')
  })

  test('Check FAIL: Loop back to Build, with the reason asked in a second question', async ($, on) => {
    const api = $ as unknown as Api
    begin(on, 'check', { plan: 'PASS', build: 'PASS', review: 'PASS', check: 'FAIL' }, ['Loop back to Build', 'the date parser is wrong'])
    await api.session.start(START)
    await ask(api)
    // No reason yet: nothing is let through.
    expect(await sh(api, `${CLI} state loop check build --reason x`)).toBeDefined()
    await ask(api, 'Temper gate', 'Loop back to Build. What is the reason?', ['the date parser is wrong', 'Cancel'])
    expect(await sh(api, `${CLI} state loop check build --reason 'the date parser is wrong'`)).toBeUndefined()
  })

  test('Review: Accept finding 1 lets that one accept through', async ($, on) => {
    const api = $ as unknown as Api
    begin(on, 'review', { plan: 'PASS', build: 'PASS', review: 'FAIL' }, ['Accept finding 1: not a real issue'])
    await api.session.start(START)
    await ask(api)
    expect(await sh(api, `${CLI} evidence accept --stage review --id 1 --reason 'not a real issue'`)).toBeUndefined()
    expect(await sh(api, `${CLI} evidence accept --stage review --id 2 --reason x`)).toBe(ONLY_USER)
  })

  test('the Design gate: Loop back to Plan, or Override and continue', async ($, on) => {
    const api = $ as unknown as Api
    const extra = { '.claude/temper.config': 'phases:\n  design: true\n', '.temper/build-state.json': JSON.stringify({ complexity: 'medium', stage: 'plan_complete' }) }
    begin(on, 'design', { plan: 'PASS', design: 'FAIL' }, ['Override and continue: the platform team owns it'], extra)
    await api.session.start(START)
    expect(await sh(api, `${CLI} state advance design_complete build`)).toBe(ONLY_USER)
    await ask(api)
    expect(await sh(api, `${CLI} override design --reason 'the platform team owns it'`)).toBeUndefined()
    expect(await sh(api, `${CLI} state advance design_complete build`)).toBeUndefined()
  })

  test('the Design gate: Loop back to Plan', async ($, on) => {
    const api = $ as unknown as Api
    const extra = { '.claude/temper.config': 'phases:\n  design: true\n', '.temper/build-state.json': JSON.stringify({ complexity: 'medium' }) }
    const w = begin(on, 'design', { plan: 'PASS', design: 'FAIL' }, ['Loop back to Plan: the API changed'], extra)
    await api.session.start(START)
    await ask(api)
    expect(await sh(api, `${CLI} state loop design plan --reason 'the API changed'`)).toBeUndefined()
    expect(state(w).next_stage).toBe('plan')
    // The redone plan needs its own approval.
    gates(w, { plan: 'PASS' })
    expect(await sh(api, `${CLI} state advance plan_complete design`)).toBe(ONLY_USER)
  })

  test('arming autonomy: Autonomous arms the run and approves the plan; Stage by stage only approves', async ($, on) => {
    const api = $ as unknown as Api
    const cfg = { '.claude/temper.config': 'autonomy:\n  enabled: true\n' }
    const w = begin(on, 'plan', { plan: 'PASS' }, ['Autonomous: run the rest unattended'], cfg)
    await api.session.start(START)
    expect(await sh(api, `${CLI} state set run_mode autonomous`)).toContain('only the user can turn on autonomous mode')
    await ask(api)
    expect(await sh(api, `${CLI} state set run_mode autonomous`)).toBeUndefined()
    expect(await sh(api, `${CLI} state advance plan_complete build`)).toBeUndefined()
    expect(state(w).run_mode).toBe('autonomous')
  })

  test('an armed run loops back to Build by itself after a failed Check, and keeps every write rule', async ($, on) => {
    const api = $ as unknown as Api
    const cfg = { '.claude/temper.config': 'autonomy:\n  enabled: true\n', '.temper/build-state.json': JSON.stringify({ run_mode: 'autonomous' }) }
    const w = begin(on, 'check', { plan: 'PASS', build: 'PASS', review: 'PASS', check: 'FAIL' }, [], cfg)
    await api.session.start(START)
    expect(await sh(api, `${CLI} state loop check build --reason 'a test fails'`)).toBeUndefined()
    gates(w, { plan: 'PASS', build: 'PASS' })
    expect(await sh(api, `${CLI} state advance build_complete review`)).toBeUndefined()
    expect(await write(api, 'src/app.ts')).toContain('Review stage')
    expect(await system(api)).not.toContain('looks reset')
    gates(w, { plan: 'PASS', build: 'PASS', review: 'PASS' })
    expect(await sh(api, `${CLI} state advance review_complete check`)).toBeUndefined()
    expect(await write(api, 'src/app.ts')).toContain('Check only runs checks')
    expect(await sh(api, `${CLI} state loop check plan --reason x`)).toBeDefined()
  })

  test("a parked group: Keep the agent's commits lets one reopen with --accept-foreign through", async ($, on) => {
    const api = $ as unknown as Api
    begin(on, 'build', { plan: 'PASS' }, ["Keep the agent's commits: the commit is the change we wanted"], { '.temper/groups.json': '{}' })
    await api.session.start(START)
    const reopen = `${CLI} group reopen G1 --accept-foreign abc123 --reason 'wanted'`
    expect(await sh(api, reopen)).toBe(ONLY_USER)
    await ask(api)
    expect(await sh(api, reopen)).toBeUndefined()
    expect(await sh(api, reopen)).toBe(ONLY_USER)
  })

  test('the commit gate FAIL after the run is done: Override and commit', async ($, on) => {
    const api = $ as unknown as Api
    begin(on, 'commit', { plan: 'PASS', build: 'PASS', review: 'PASS', check: 'PASS' }, ['Override and commit: design.md is empty on purpose'])
    await api.session.start(START)
    expect(await sh(api, `${CLI} override design --reason x`)).toContain('Override and commit')
    await ask(api)
    expect(await sh(api, `${CLI} override design --reason 'design.md is empty on purpose'`)).toBeUndefined()
  })

  test('Save for later gives the person control until the run moves on', async ($, on) => {
    const api = $ as unknown as Api
    const w = begin(on, 'build', { plan: 'PASS' }, ['Save for later'])
    await api.session.start(START)
    expect(await write(api, 'src/other.ts')).toContain('scope drift')
    await ask(api)
    expect(await write(api, 'src/other.ts')).toBeUndefined()
    expect(await system(api)).toContain('saved the run for later')
    // The run moves on (the person took it up again and Build passed): the rules hold again.
    gates(w, { plan: 'PASS', build: 'PASS' })
    w.files.set('.temper/build-state.json', JSON.stringify({ ...state(w), next_stage: 'review', step: 4 }))
    await sh(api, 'true')
    expect(await write(api, 'src/other.ts')).toContain('Review stage')
  })

  test('Start over: the Temper resume answer lets the run state go', async ($, on) => {
    const api = $ as unknown as Api
    begin(on, 'build', { plan: 'PASS' }, ['Start over'])
    await api.session.start(START)
    expect(await sh(api, `${CLI} state archive`)).toContain('do not clear or archive')
    await ask(api, 'Temper resume', 'A saved run of another feature is here. What now?', ['Continue from Build (Recommended)', 'Start over'])
    expect(await sh(api, `${CLI} state archive`)).toBeUndefined()
  })

  test('Scope drift: Add to plan lets the file through; Allow once lets one write through', async ($, on) => {
    const api = $ as unknown as Api
    begin(on, 'build', { plan: 'PASS' }, ['Add to plan', 'Allow once'])
    await api.session.start(START)
    const drift = (path: string) => ask(api, 'Scope drift', `Outside the plan: ${path}\nWhy: it is needed\nChange: one line`, ['Add to plan', 'Revert', 'Allow once'])
    await drift('src/extra.ts')
    expect(await write(api, 'src/extra.ts')).toBeUndefined()
    expect(await write(api, 'src/extra.ts')).toBeUndefined()
    await drift('src/once.ts')
    expect(await write(api, 'src/once.ts')).toBeUndefined()
    expect(await write(api, 'src/once.ts')).toContain('scope drift')
  })

  test('a /temper:fix run: the mod stands aside', async ($, on) => {
    const api = $ as unknown as Api
    begin(on, 'fix', {}, [], { '.temper/build-state.json': JSON.stringify({ command: 'fix' }) })
    await api.session.start(START)
    expect(await write(api, 'src/anything.ts')).toBeUndefined()
    expect(await sh(api, `${CLI} override check --reason x`)).toBeUndefined()
    expect(await system(api)).toContain('a /temper:fix run')
  })

  test('with enforcement off nothing is refused, and an answer is still kept for the report', { options: { enforcement: 'off' } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = begin(on, 'plan', { plan: 'PASS' }, ['Continue to Build'])
    await api.session.start(START)
    expect(await write(api, 'src/app.ts')).toBeUndefined()
    expect(await sh(api, `${CLI} state advance plan_complete build`)).toBeUndefined()
    await ask(api)
    expect(decisions(w).length).toBe(0)
  })

  test('headless (nobody answers): the run stops at the first gate', async ($, on) => {
    const api = $ as unknown as Api
    begin(on, 'intent', { intent: 'PASS' })
    await api.session.start({ ...START, isInteractive: false })
    await ask(api)
    expect(await sh(api, `${CLI} state advance intent_complete plan`)).toBe(ONLY_USER)
  })
})

describe('commits: the native hook is the commit gate', () => {
  test('a plain commit goes to the hook; --no-verify and a merge are refused while a run is active', async ($, on) => {
    const api = $ as unknown as Api
    begin(on, 'build', { plan: 'PASS' })
    await api.session.start(START)
    expect(await sh(api, 'git add src/app.ts && git commit -m "feat: x"')).toBeUndefined()
    expect(await sh(api, 'git commit --no-verify -m x')).toContain('pre-commit hook')
    expect(await sh(api, 'git merge other')).toContain('does not check')
  })
})

describe('the system prompt: one flow in every mode', () => {
  for (const uiMode of ['full', 'minimal', 'off']) {
    test(`${uiMode}: at a gate, Claude asks the Temper gate question; no key, no typed command`, { options: { uiMode } }, async ($, on) => {
      const api = $ as unknown as Api
      begin(on, 'plan', { plan: 'PASS' })
      await api.session.start(START)
      const text = await system(api)
      expect(text).toContain('Phase: Plan')
      expect(text).toContain('header `Temper gate`')
      expect(text).toContain('continue to Build')
      expect(text).not.toMatch(/key \d|press \d|Temper bar|\/temper:temper approve/i)
    })
  }

  test('a chosen answer tells Claude to carry it out', async ($, on) => {
    const api = $ as unknown as Api
    begin(on, 'review', { plan: 'PASS', build: 'PASS', review: 'FAIL' }, ['Loop back to Build: a real bug'])
    await api.session.start(START)
    expect(await system(api)).toContain('the Review check failed')
    await ask(api)
    expect(await system(api)).toContain('carry out that answer now')
  })
})
