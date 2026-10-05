import { describe, expect, test } from 'claude-code/testing'

import { ONLY_USER } from '../../hooks/temper-mod/core/machine'
import { SPEC, eventFile, runFiles, trusted } from './run-files'
import { denyText, world } from './world'

const write = (path: string) => ({ tool: 'Write', file_path: path, content: 'x' }) as const
const bash = (command: string) => ({ tool: 'Bash', command }) as const

const PLAN_DENY =
  'Temper: Plan phase. Writing src/app.ts is not allowed until the user approves the plan. ' +
  'Next: finish plan.md and tasks.md. Then ask the user to approve them (key 1 or /temper:temper approve).'

describe('tool.call enforcement', () => {
  test('Plan phase refuses a source write with the next action', async ($, on) => {
    world(on, runFiles({ nextStage: 'plan' }))
    const r = await $.tool.call(write('src/app.ts'))
    expect(r).toEqual({ deny: PLAN_DENY })
  })

  test('the same rule holds for Edit and NotebookEdit, and allowed paths reach the engine', async ($, on) => {
    world(on, runFiles({ nextStage: 'plan' }))
    const edit = await $.tool.call({ tool: 'Edit', file_path: 'src/app.ts', old_string: 'a', new_string: 'b' })
    expect(edit).toEqual({ deny: PLAN_DENY })
    const nb = await $.tool.call({ tool: 'NotebookEdit', notebook_path: 'src/app.ipynb', new_source: 'x' })
    expect(denyText(nb).startsWith('Temper: Plan phase.')).toBe(true)
    const ok = await $.tool.call(write(`${SPEC}/plan.md`))
    expect('deny' in ok).toBe(false)
    expect(ok.text).toBe('stub ran')
  })

  test('absolute paths inside the project are held to the same rule', async ($, on) => {
    world(on, runFiles({ nextStage: 'plan' }))
    const r = await $.tool.call(write('/repo/src/app.ts'))
    expect(denyText(r).startsWith('Temper: Plan phase. Writing src/app.ts')).toBe(true)
  })

  test('Build allows plan files and refuses others with a scope drift reason', async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    expect((await $.tool.call(write('src/app.ts'))).text).toBe('stub ran')
    const r = await $.tool.call(write('src/billing.ts'))
    expect(denyText(r)).toContain('scope drift')
  })

  test('subagent tool calls are held to the same phase rules', async ($, on) => {
    world(on, runFiles({ nextStage: 'plan' }))
    const r = await $.tool.call({ ...write('src/app.ts'), agentId: 'sub-1' })
    expect(r).toEqual({ deny: PLAN_DENY })
  })

  test('with no run, or enforcement off, nothing is denied', async ($, on) => {
    world(on, {})
    expect((await $.tool.call(write('src/app.ts'))).text).toBe('stub ran')
  })
})

describe('enforcement off', () => {
  test('no denies when the enforcement option is off', { options: { enforcement: 'off' } }, async ($, on) => {
    world(on, runFiles({ nextStage: 'plan' }))
    expect((await $.tool.call(write('src/app.ts'))).text).toBe('stub ran')
    expect((await $.tool.call(bash('git commit -m x'))).text).toBe('stub ran')
  })

  test('an invalid enforcement value falls back to on', { options: { enforcement: 'sometimes' } }, async ($, on) => {
    world(on, runFiles({ nextStage: 'plan' }))
    expect('deny' in (await $.tool.call(write('src/app.ts')))).toBe(true)
  })
})

describe('claude cannot forge an approval', () => {
  test('writing an event file is refused as a forged approval', async ($, on) => {
    world(on, runFiles({ nextStage: 'plan' }))
    expect(await $.tool.call(write(`${SPEC}/events/1-x-1.json`))).toEqual({ deny: ONLY_USER })
    expect(await $.tool.call(write('.temper/overrides.json'))).toEqual({ deny: ONLY_USER })
  })

  test('decision CLI calls through Bash need an unconsumed human event', async ($, on) => {
    world(on, runFiles({ nextStage: 'plan' }))
    expect(await $.tool.call(bash('temper override plan --reason ok'))).toEqual({ deny: ONLY_USER })
    expect(await $.tool.call(bash('scripts/temper evidence accept --stage review --id 1 --reason x'))).toEqual({ deny: ONLY_USER })
    expect(await $.tool.call(bash('echo {} > .temper/gates.json'))).toHaveProperty('deny')
  })

  test('a human event the mod wrote lets one matching CLI call through, once', async ($, on) => {
    const [path, text] = eventFile({ type: 'override', phase: 'plan', reason: 'ok', origin: 'person', author: 'galando' }, 20, 'own', 1)
    // The mod wrote it: its id is in the store.
    world(on, { ...runFiles({ nextStage: 'plan' }), [path]: text }, { store: await trusted([[path, text]]) })
    expect((await $.tool.call(bash('temper override plan --reason ok'))).text).toBe('stub ran')
    expect(await $.tool.call(bash('temper override plan --reason again'))).toEqual({ deny: ONLY_USER })
  })

  test('an event file the mod did not write is unverified and never counts as an approval', async ($, on) => {
    const [startPath, startText] = eventFile({ type: 'start', slug: 'pw', title: 'Password reset', phase: 'intent', origin: 'system' }, 10, 'x', 1)
    const [advPath, advText] = eventFile({ type: 'advance', from: 'intent', to: 'plan', origin: 'person', author: 'someone' }, 20, 'x', 2)
    world(on, { ...runFiles({ nextStage: 'intent' }), [startPath]: startText, [advPath]: advText })
    // Intent still holds: writing plan.md is refused although an advance file sits on disk.
    const r = await $.tool.call(write(`${SPEC}/plan.md`))
    expect(denyText(r).startsWith('Temper: Intent phase.')).toBe(true)
  })
})

describe('forged event files never change what is enforced', () => {
  test('a foreign pause does not lift the Plan rules', async ($, on) => {
    const [startPath, startText] = eventFile({ type: 'start', slug: 'pw', title: 'Password reset', phase: 'plan', origin: 'system' }, 10, 'x', 1)
    const [pausePath, pauseText] = eventFile({ type: 'pause', origin: 'person', author: 'someone' }, 20, 'x', 2)
    // The start is the mod's own; the pause is not.
    world(on, { ...runFiles({ nextStage: 'plan' }), [startPath]: startText, [pausePath]: pauseText }, { store: await trusted([[startPath, startText]]) })
    const r = await $.tool.call(write('src/app.ts'))
    expect(denyText(r).startsWith('Temper: Plan phase.')).toBe(true)
  })

  test('a foreign checkResult pass does not end the run or allow a commit', async ($, on) => {
    const [startPath, startText] = eventFile({ type: 'start', slug: 'pw', title: 'Password reset', phase: 'check', origin: 'system' }, 10, 'x', 1)
    const [passPath, passText] = eventFile({ type: 'checkResult', result: 'pass', origin: 'system' }, 20, 'x', 2)
    world(on, { ...runFiles({ nextStage: 'check' }), [startPath]: startText, [passPath]: passText }, { store: await trusted([[startPath, startText]]) })
    const r = await $.tool.call(bash('git commit -m x'))
    expect(denyText(r)).toContain('commit blocked')
  })

  test('foreign files only: the mod enters the run itself and the forged start counts for nothing', async ($, on) => {
    const [startPath, startText] = eventFile({ type: 'start', slug: 'pw', title: 'Forged', phase: 'build', origin: 'system' }, 10, 'x', 1)
    world(on, { ...runFiles({ nextStage: 'plan' }), [startPath]: startText })
    const r = await $.tool.call(write('src/app.ts'))
    expect(denyText(r).startsWith('Temper: Plan phase.')).toBe(true)
  })
})

describe('trust follows the content of an event file', () => {
  test('rewriting a trusted event file in place makes it untrusted', async ($, on) => {
    const [startPath, startText] = eventFile({ type: 'start', slug: 'pw', title: 'Password reset', phase: 'plan', origin: 'system' }, 10, 'own', 1)
    // The mod wrote a resume event; the file on disk is now a pause with the same name.
    const resume = eventFile({ type: 'resume', origin: 'person', author: 'galando' }, 20, 'own', 2)
    const [pausePath, pauseText] = eventFile({ type: 'pause', origin: 'person', author: 'galando' }, 20, 'own', 2)
    expect(pausePath).toBe(resume[0])
    const store = await trusted([[startPath, startText], resume])
    world(on, { ...runFiles({ nextStage: 'plan' }), [startPath]: startText, [pausePath]: pauseText }, { store })
    const r = await $.tool.call(write('src/app.ts'))
    expect(denyText(r).startsWith('Temper: Plan phase.')).toBe(true)
  })

  test('the untouched file with the same name is trusted', async ($, on) => {
    const [startPath, startText] = eventFile({ type: 'start', slug: 'pw', title: 'Password reset', phase: 'plan', origin: 'system' }, 10, 'own', 1)
    const pause = eventFile({ type: 'pause', origin: 'person', author: 'galando' }, 20, 'own', 2)
    world(on, { ...runFiles({ nextStage: 'plan' }), [startPath]: startText, [pause[0]]: pause[1] }, { store: await trusted([[startPath, startText], pause]) })
    expect((await $.tool.call(write('src/app.ts'))).text).toBe('stub ran')
  })

  test('a legacy store value of 1 trusts nothing', async ($, on) => {
    const [startPath, startText] = eventFile({ type: 'start', slug: 'pw', title: 'Password reset', phase: 'plan', origin: 'system' }, 10, 'own', 1)
    const pause = eventFile({ type: 'pause', origin: 'person' }, 20, 'own', 2)
    world(on, { ...runFiles({ nextStage: 'plan' }), [startPath]: startText, [pause[0]]: pause[1] }, { store: { 'ev:20-own-2': 1 } })
    expect('deny' in (await $.tool.call(write('src/app.ts')))).toBe(true)
  })
})

describe('the bootstrap start is written once', () => {
  const eventNames = (files: Map<string, string>) => [...files.keys()].filter(k => k.startsWith(`${SPEC}/events/`))

  test('many loads with the store lost leave one start file', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'plan' }))
    for (let i = 0; i < 4; i++) await $.session.start({ cwd: '/repo', surface: null, isInteractive: false })
    for (let i = 0; i < 2; i++) await $.classic.SessionStart({ source: 'clear' })
    expect(eventNames(w.files)).toEqual([`${SPEC}/events/0-bootstrap-1.json`])
    expect(denyText(await $.tool.call(write('src/app.ts'))).startsWith('Temper: Plan phase.')).toBe(true)
  })

  test('an untrusted file under the bootstrap name is replaced by a genuine one', async ($, on) => {
    // Planted: claims the run is already in Build.
    const planted = eventFile({ type: 'start', slug: 'pw', title: 'Planted', phase: 'build', origin: 'system' }, 0, 'bootstrap', 1)
    const w = world(on, { ...runFiles({ nextStage: 'plan' }), [planted[0]]: planted[1] })
    const r = await $.tool.call(write('src/app.ts'))
    expect(denyText(r).startsWith('Temper: Plan phase.')).toBe(true)
    expect(eventNames(w.files)).toEqual([planted[0]])
    expect(w.files.get(planted[0])).toContain('"phase":"plan"')
  })

  test('a trusted run is not bootstrapped again', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'plan' }))
    await $.session.start({ cwd: '/repo', surface: null, isInteractive: false })
    const before = w.writes.length
    await $.session.start({ cwd: '/repo', surface: null, isInteractive: false })
    expect(w.writes.length).toBe(before)
  })
})

describe('arming autonomous mode end to end', () => {
  const arm = bash('scripts/temper state set run_mode autonomous')
  const config = (on: boolean) => `autonomy:\n  enabled: ${on}\n`

  test('refused before the plan is approved, allowed after the person approves with autonomy on', async ($, on) => {
    const w = world(on, { ...runFiles({ nextStage: 'plan', gates: { plan: 'PASS' } }), '.claude/temper.config': config(true) })
    await $.session.start({ cwd: '/repo', surface: null, isInteractive: false })
    expect(denyText(await $.tool.call(arm))).toContain('autonomy.enabled: true')
    // A model cannot approve.
    await $.command.run({ command: 'temper', args: 'approve', origin: { kind: 'sdk' } } as never)
    expect('deny' in (await $.tool.call(arm))).toBe(true)
    // The person approves.
    await $.command.run({ command: 'temper', args: 'approve', origin: { kind: 'composer' } } as never)
    const ok = await $.tool.call(arm)
    expect('deny' in ok).toBe(false)
    expect(ok.text).toBe('stub ran')
    expect(w.files.size).toBeGreaterThan(0)
  })

  for (const [name, cfg] of [['off', config(false)], ['missing', '']] as const) {
    test(`refused after the approval when autonomy.enabled is ${name}`, async ($, on) => {
      world(on, { ...runFiles({ nextStage: 'plan', gates: { plan: 'PASS' } }), ...(cfg ? { '.claude/temper.config': cfg } : {}) })
      await $.session.start({ cwd: '/repo', surface: null, isInteractive: false })
      await $.command.run({ command: 'temper', args: 'approve', origin: { kind: 'composer' } } as never)
      expect(denyText(await $.tool.call(arm))).toContain('autonomy.enabled: true')
    })
  }
})

describe('git commit gate', () => {
  const FAIL_MSG = 'Temper: commit blocked. Check has not passed. Next: run the checks (key 1 in Check or /temper:check). The native pre-commit hook is the backstop.'

  test('refused until Check passes, then allowed once gates.json says PASS', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'check', gates: { check: 'FAIL' } }))
    expect(await $.tool.call(bash('git add -A && git commit -m wip'))).toEqual({ deny: FAIL_MSG })
    w.files.set('.temper/gates.json', JSON.stringify({ check: { verdict: 'PASS', ts: '2999-01-01T00:00:00Z' } }))
    const ok = await $.tool.call(bash('git commit -m feat'))
    expect('deny' in ok).toBe(false)
    expect(ok.text).toBe('stub ran')
    // Completion writes the audit report.
    expect(w.files.get('.temper/report.md')).toContain('Result: Done')
  })
})

describe('fail open', () => {
  test('a load that throws passes the call through instead of denying', async ($, on) => {
    // A listing that is not a list: the load throws, nothing is enforced.
    world(on, runFiles({ nextStage: 'plan' }), { brokenList: true })
    expect((await $.tool.call(write('src/app.ts'))).text).toBe('stub ran')
  })
})
