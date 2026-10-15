// End to end, through the test world and its fake CLI (ADR 0013): the person decides only in the question dialogs, asked
// exactly as the CLI's view gives them; the mod reads the answer from the dialog's result and keeps it for the CLI's run
// and step, and the guard lets through the calls that answer maps to at that step, and nothing more. Every wait point of
// the flow audit is here.
import { describe, expect, test } from 'claude-code/testing'

import { ONLY_USER } from '../../hooks/temper-mod/core/rules'
import { SPEC, questionOf, runFiles } from './run-files'
import { COMPOSE, viewText, world } from './world'
import type { Answer, World } from './world'

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
// The question `temper next --json` gives now, asked exactly as given (or its More options, accept, reason or resume
// question).
const ask = (api: Api, w: World, which: Parameters<typeof questionOf>[1] = {}) =>
  api.tool.call({ tool: 'AskUserQuestion', questions: [{ ...questionOf(viewText(w) ?? '', which), multiSelect: false }] })
// A question Claude wrote itself.
const askRaw = (api: Api, header: string, question: string, options: string[]) =>
  api.tool.call({ tool: 'AskUserQuestion', questions: [{ question, header, multiSelect: false, options: options.map(label => ({ label, description: label })) }] })
const why = (label: string, note: string): Answer => ({ label, note })
const system = async (api: Api) => (await api.prompt.compose(COMPOSE)).sections.at(-1)?.text ?? ''
const decisions = (w: World): Array<{ kind: string; move?: string; stage: string; step: number }> =>
  Object.entries(w.store).filter(([k]) => k.startsWith('dec:')).flatMap(([, v]) => v as Array<{ kind: string; move?: string; stage: string; step: number }>)
const state = (w: World): Record<string, unknown> => JSON.parse(w.files.get('.temper/build-state.json') ?? '{}') as Record<string, unknown>
const gates = (w: World, g: Record<string, 'PASS' | 'FAIL'>) => {
  w.files.set('.temper/gates.json', JSON.stringify(Object.fromEntries(Object.entries(g).map(([k, v]) => [k, { verdict: v }]))))
  w.files.delete('.temper/view.json')
}
const FINDINGS = JSON.stringify([{ claim: 'src/app.ts:12 the token never expires', severity: 'critical' }, { claim: 'src/mail.ts:4 the subject', severity: 'critical' }])

function begin(on: Parameters<typeof world>[0], next: string, g: Record<string, 'PASS' | 'FAIL'> = {}, answers: Answer[] = [], extra: Record<string, string> = {}): World {
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
    await ask(api, w)
    expect(decisions(w).map(d => d.move)).toEqual(['approve'])
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
    const w = begin(on, 'plan', { plan: 'PASS' }, ['Continue to Build (Recommended)'])
    await api.session.start(START)
    const q = questionOf(viewText(w) ?? '')
    await askRaw(api, 'Something else', q.question, q.options.map(o => o.label))
    expect(decisions(w)).toEqual([])
  })

  test('a question Claude reworded decides nothing, and the call stays refused', async ($, on) => {
    const api = $ as unknown as Api
    const w = begin(on, 'plan', { plan: 'PASS' }, ['Continue to Build (Recommended)'])
    await api.session.start(START)
    await askRaw(api, 'Temper gate', 'The plan looks good. Shall I go on to Build?', ['Continue to Build (Recommended)', 'Save for later'])
    expect(decisions(w)).toEqual([])
    expect(await sh(api, `${CLI} state advance plan_complete build`)).toBe(ONLY_USER)
  })

  test('the latest answer at a step replaces the earlier one', async ($, on) => {
    const api = $ as unknown as Api
    const w = begin(on, 'review', { plan: 'PASS', build: 'PASS', review: 'FAIL' }, [why('Loop back to Build (Recommended)', 'the token bug is real'), why('Override and continue', 'reviewed by hand')])
    await api.session.start(START)
    await ask(api, w)
    await ask(api, w)
    expect(await sh(api, `${CLI} state loop review build --reason x`)).toBeDefined()
    expect(await sh(api, `${CLI} override review --reason 'reviewed by hand'`)).toBeUndefined()
    expect(await sh(api, `${CLI} state advance review_complete check`)).toBeUndefined()
    // At Check the earlier step back counts for nothing.
    expect(await sh(api, `${CLI} state loop check build --reason x`)).toBeDefined()
  })

  test('a step back is let through once: back at the same stage later, it needs a new answer', async ($, on) => {
    const api = $ as unknown as Api
    const w = begin(on, 'review', { plan: 'PASS', build: 'PASS', review: 'FAIL' }, [why('Loop back to Build (Recommended)', 'a real bug')])
    await api.session.start(START)
    await ask(api, w)
    expect(await sh(api, `${CLI} state loop review build --reason 'a real bug'`)).toBeUndefined()
    expect(state(w).next_stage).toBe('build')
    // The CLI cleared the verdicts it redoes; Build passes again, Review fails again.
    gates(w, { plan: 'PASS', build: 'PASS' })
    expect(await sh(api, `${CLI} state advance build_complete review`)).toBeUndefined()
    gates(w, { plan: 'PASS', build: 'PASS', review: 'FAIL' })
    expect(await sh(api, `${CLI} state loop review build --reason again`)).toBeDefined()
  })

  test('a new run on the same spec folder starts with no decision', async ($, on) => {
    const api = $ as unknown as Api
    const w = begin(on, 'plan', { plan: 'PASS' }, ['Continue to Build (Recommended)'])
    await api.session.start(START)
    await ask(api, w)
    // Start over: the person's answer, then the new run.
    w.files.set('.temper/build-state.json', JSON.stringify({ ...state(w), run_id: 'run-new', step: 1, next_stage: 'plan' }))
    expect(await sh(api, `${CLI} state advance plan_complete build`)).toBe(ONLY_USER)
  })
})

describe('every wait point of the flow audit', () => {
  test('Check FAIL: Override and continue skips Check, and the run goes on to the commit stage', async ($, on) => {
    const api = $ as unknown as Api
    const w = begin(on, 'check', { plan: 'PASS', build: 'PASS', review: 'PASS', check: 'FAIL' }, [why('Override and continue', 'the flaky test is known')])
    await api.session.start(START)
    expect(await sh(api, `${CLI} override check --reason x`)).toBe(ONLY_USER)
    await ask(api, w)
    expect(await sh(api, `${CLI} override check --reason 'the flaky test is known'`)).toBeUndefined()
    expect(await sh(api, `${CLI} state advance check_complete commit`)).toBeUndefined()
    expect(state(w).next_stage).toBe('commit')
  })

  test('Check FAIL: Loop back to Build, with the reason asked in a second question', async ($, on) => {
    const api = $ as unknown as Api
    const w = begin(on, 'check', { plan: 'PASS', build: 'PASS', review: 'PASS', check: 'FAIL' }, ['Loop back to Build (Recommended)', 'the date parser is wrong'])
    await api.session.start(START)
    await ask(api, w)
    // No reason yet: nothing is let through.
    expect(await sh(api, `${CLI} state loop check build --reason x`)).toBeDefined()
    // The reason question, as the CLI wrote it; a typed answer is the reason.
    await ask(api, w, { reasonOf: 'Loop back to Build (Recommended)' })
    expect(await sh(api, `${CLI} state loop check build --reason 'the date parser is wrong'`)).toBeUndefined()
  })

  test('Review: Accept finding 1 lets that one accept through', async ($, on) => {
    const api = $ as unknown as Api
    const w = begin(on, 'review', { plan: 'PASS', build: 'PASS', review: 'FAIL' }, [why('Accept finding 1', 'not a real issue')], { '.temper/evidence/review.json': FINDINGS })
    await api.session.start(START)
    await ask(api, w, { accept: true })
    expect(await sh(api, `${CLI} evidence accept --stage review --id 1 --reason 'not a real issue'`)).toBeUndefined()
    expect(await sh(api, `${CLI} evidence accept --stage review --id 2 --reason x`)).toBe(ONLY_USER)
  })

  test('the Design gate: Loop back to Plan, or Override and continue', async ($, on) => {
    const api = $ as unknown as Api
    const extra = { '.claude/temper.config': 'phases:\n  design: true\n', '.temper/build-state.json': JSON.stringify({ complexity: 'medium', stage: 'plan_complete' }) }
    const w = begin(on, 'design', { plan: 'PASS', design: 'FAIL' }, [why('Override and continue', 'the platform team owns it')], extra)
    await api.session.start(START)
    expect(await sh(api, `${CLI} override design --reason x`)).toBe(ONLY_USER)
    await ask(api, w)
    expect(await sh(api, `${CLI} override design --reason 'the platform team owns it'`)).toBeUndefined()
    expect(await sh(api, `${CLI} state advance design_complete build`)).toBeUndefined()
  })

  test('the Design gate: Loop back to Plan', async ($, on) => {
    const api = $ as unknown as Api
    const extra = { '.claude/temper.config': 'phases:\n  design: true\n', '.temper/build-state.json': JSON.stringify({ complexity: 'medium' }) }
    const w = begin(on, 'design', { plan: 'PASS', design: 'FAIL' }, [why('Loop back to Plan', 'the API changed')], extra)
    await api.session.start(START)
    await ask(api, w)
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
    await ask(api, w)
    expect(await sh(api, `${CLI} state set run_mode autonomous`)).toBeUndefined()
    expect(await sh(api, `${CLI} state advance plan_complete build`)).toBeUndefined()
    expect(state(w).run_mode).toBe('autonomous')
  })

  test('an armed run loops back to Build by itself after a failed Check, and keeps every write rule', async ($, on) => {
    const api = $ as unknown as Api
    const cfg = { '.claude/temper.config': 'autonomy:\n  enabled: true\n', '.temper/build-state.json': JSON.stringify({ run_mode: 'autonomous' }) }
    const w = begin(on, 'check', { plan: 'PASS', build: 'PASS', review: 'PASS', check: 'FAIL' }, [], cfg)
    await api.session.start(START)
    // The armed run's own move is the call the CLI wrote, word for word; another reason is another call.
    const own = (JSON.parse(viewText(w) ?? '{}') as { next: { calls: string[] } }).next.calls[0] ?? ''
    expect(own).toContain('state loop check build')
    expect(await sh(api, `${CLI} state loop check build --reason 'my own words'`)).toBeDefined()
    expect(await sh(api, own.replace(/^\S+/, CLI))).toBeUndefined()
    gates(w, { plan: 'PASS', build: 'PASS' })
    expect(await sh(api, `${CLI} state advance build_complete review`)).toBeUndefined()
    expect(await write(api, 'src/app.ts')).toContain('Review stage')
    expect(await system(api)).not.toContain('looks reset')
    gates(w, { plan: 'PASS', build: 'PASS', review: 'PASS' })
    expect(await sh(api, `${CLI} state advance review_complete check`)).toBeUndefined()
    expect(await write(api, 'src/app.ts')).toContain('Check only runs checks')
    expect(await sh(api, `${CLI} state loop check plan --reason x`)).toBeDefined()
  })

  test('the commit gate FAIL after the run is done: Override and commit', async ($, on) => {
    const api = $ as unknown as Api
    const w = begin(on, 'commit', { plan: 'PASS', build: 'PASS', review: 'PASS', check: 'PASS', commit: 'FAIL' }, [why('Override and commit', 'reviewed by hand')])
    await api.session.start(START)
    expect(await sh(api, `${CLI} override review --reason x`)).toContain('Override and commit')
    await ask(api, w)
    expect(await sh(api, `${CLI} override review --reason 'reviewed by hand'`)).toBeUndefined()
  })

  test('Save for later stops the run: the system prompt says so, and every rule still holds', async ($, on) => {
    const api = $ as unknown as Api
    const w = begin(on, 'build', { plan: 'PASS', build: 'PASS' }, ['Save for later'])
    await api.session.start(START)
    expect(await write(api, 'src/other.ts')).toContain('scope drift')
    await ask(api, w)
    expect(await system(api)).toContain('saved the run for later')
    expect(await write(api, 'src/other.ts')).toContain('scope drift')
    expect(await sh(api, 'git commit --no-verify -m x')).toContain('pre-commit hook')
  })

  test('Start over: the Temper resume answer lets the run state go', async ($, on) => {
    const api = $ as unknown as Api
    const w = begin(on, 'build', { plan: 'PASS' }, ['Start over'])
    await api.session.start(START)
    expect(await sh(api, `${CLI} state archive`)).toContain('do not clear or archive')
    await ask(api, w, { restart: true })
    expect(await sh(api, `${CLI} state archive`)).toBeUndefined()
  })

  test('Scope drift: Add to plan lets the file through; Allow once lets one write through', async ($, on) => {
    const api = $ as unknown as Api
    begin(on, 'build', { plan: 'PASS' }, ['Add to plan', 'Allow once'])
    await api.session.start(START)
    const drift = (path: string) => askRaw(api, 'Scope drift', `Outside the plan: ${path}\nWhy: it is needed\nChange: one line`, ['Add to plan', 'Revert', 'Allow once'])
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
    const w = begin(on, 'plan', { plan: 'PASS' }, ['Continue to Build (Recommended)'])
    await api.session.start(START)
    expect(await write(api, 'src/app.ts')).toBeUndefined()
    await ask(api, w)
    expect(decisions(w).length).toBe(1)
    expect(await sh(api, `${CLI} state advance plan_complete build`)).toBeUndefined()
  })

  test('headless (nobody answers): the run stops at the first gate', async ($, on) => {
    const api = $ as unknown as Api
    const w = begin(on, 'intent', { intent: 'PASS' })
    await api.session.start({ ...START, isInteractive: false })
    await ask(api, w)
    expect(await sh(api, `${CLI} state advance intent_complete plan`)).toBe(ONLY_USER)
  })
})

describe('a stage command is a door into /temper', () => {
  test('a run with Design: Plan goes on to Design, not past it', async ($, on) => {
    const api = $ as unknown as Api
    const extra = { '.claude/temper.config': 'phases:\n  design: true\n', '.temper/build-state.json': JSON.stringify({ complexity: 'medium' }) }
    const w = begin(on, 'plan', { intent: 'PASS', plan: 'PASS' }, ['Continue to Design (Recommended)'], extra)
    await api.session.start(START)
    await ask(api, w)
    expect(await sh(api, `${CLI} state advance plan_complete build`)).toBe(ONLY_USER)
    expect(await sh(api, `${CLI} state advance plan_complete design`)).toBeUndefined()
    expect(state(w).next_stage).toBe('design')
  })

  test('a door walks the earlier gates by the same answers: Intent, then Plan, then the stage', async ($, on) => {
    const api = $ as unknown as Api
    const w = begin(on, 'intent', { intent: 'PASS' }, ['Continue to Plan (Recommended)', 'Continue to Build (Recommended)'])
    await api.session.start(START)
    await ask(api, w)
    expect(await sh(api, `${CLI} state advance intent_complete plan`)).toBeUndefined()
    gates(w, { intent: 'PASS', plan: 'PASS' })
    await ask(api, w)
    expect(await sh(api, `${CLI} state advance plan_complete build`)).toBeUndefined()
    expect(state(w).next_stage).toBe('build')
  })
})

describe('commits: the native hook is the commit gate', () => {
  test('a plain commit goes to the hook; --no-verify is refused while a run is active', async ($, on) => {
    const api = $ as unknown as Api
    begin(on, 'build', { plan: 'PASS' })
    await api.session.start(START)
    expect(await sh(api, 'git add src/app.ts && git commit -m "feat: x"')).toBeUndefined()
    expect(await sh(api, 'git commit --no-verify -m x')).toContain('pre-commit hook')
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
      expect(text).toContain('ask the `Temper gate` question exactly as `temper next --json` gives it')
      expect(text).not.toMatch(/key \d|press \d|Temper bar|\/temper:temper approve/i)
    })
  }

  test('a chosen answer tells Claude to carry it out', async ($, on) => {
    const api = $ as unknown as Api
    const w = begin(on, 'review', { plan: 'PASS', build: 'PASS', review: 'FAIL' }, [why('Loop back to Build (Recommended)', 'a real bug')])
    await api.session.start(START)
    expect(await system(api)).toContain('ask the `Temper gate` question')
    await ask(api, w)
    expect(await system(api)).toContain('carry out the calls of that option')
  })
})

describe('Build is judged against the plan the person approved', () => {
  test('a plan.md widened at Build does not let a file outside the approved plan through', async ($, on) => {
    const api = $ as unknown as Api
    const w = begin(on, 'plan', { intent: 'PASS', plan: 'PASS' }, ['Continue to Build (Recommended)'])
    await api.session.start(START)
    await ask(api, w)
    expect(await sh(api, `${CLI} state advance plan_complete build`)).toBeUndefined()
    // At Build the spec folder is writable, plan.md too. A wildcard row added there must not widen the approved plan.
    expect(await write(api, `${SPEC}/plan.md`)).toBeUndefined()
    w.files.set(`${SPEC}/plan.md`, '### Files to Modify\n\n| File | Change |\n|---|---|\n| `src/app.ts` | edit |\n| `**/*` | anything |\n')
    await sh(api, 'git status')
    expect(await write(api, 'src/app.ts')).toBeUndefined()
    expect(await write(api, 'src/billing.ts')).toContain('scope drift')
  })

  test('a plan approved again after a loop back to Plan counts with its new files', async ($, on) => {
    const api = $ as unknown as Api
    const w = begin(on, 'plan', { intent: 'PASS', plan: 'PASS' }, ['Continue to Build (Recommended)', why('Loop back to Plan', 'the plan misses billing'), 'Continue to Build (Recommended)'])
    await api.session.start(START)
    await ask(api, w)
    expect(await sh(api, `${CLI} state advance plan_complete build`)).toBeUndefined()
    gates(w, { intent: 'PASS', plan: 'PASS', build: 'FAIL' })
    await ask(api, w)
    expect(await sh(api, `${CLI} state loop build plan --reason 'the plan misses billing'`)).toBeUndefined()
    w.files.set(`${SPEC}/plan.md`, '### Files to Modify\n\n| File | Change |\n|---|---|\n| `src/app.ts` | edit |\n| `src/billing.ts` | add |\n')
    gates(w, { intent: 'PASS', plan: 'PASS' })
    await ask(api, w)
    expect(await sh(api, `${CLI} state advance plan_complete build`)).toBeUndefined()
    expect(await write(api, 'src/billing.ts')).toBeUndefined()
  })
})
