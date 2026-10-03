import { describe, expect, test } from 'claude-code/testing'

import { ONLY_USER } from '../../hooks/temper-mod/core/machine'
import { SPEC, eventFile, runFiles } from './run-files'
import { denyText, world } from './world'

const write = (path: string) => ({ tool: 'Write', file_path: path, content: 'x' }) as const
const bash = (command: string) => ({ tool: 'Bash', command }) as const

const PLAN_DENY =
  'Temper: Plan phase. Writing src/app.ts is not allowed until the plan is approved. ' +
  'Next: finish plan.md and tasks.md, then ask the user to approve (key 1 or /temper approve).'

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
    world(on, { ...runFiles({ nextStage: 'plan' }), [path]: text }, { store: { 'ev:20-own-1': 1 } })
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

describe('git commit gate', () => {
  const FAIL_MSG = 'Temper: commit blocked, Check has not passed. Next: run the checks (key 1 in Check or /temper check).'

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
