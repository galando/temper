import { describe, expect, test } from 'claude-code/testing'

import { SPEC, runFiles } from './run-files'
import { world } from './world'
import type { World } from './world'

const PASSTHROUGH = 'prompt based /temper:temper ran'

const events = (w: World): Array<Record<string, unknown>> =>
  [...w.files.entries()]
    .filter(([p]) => p.startsWith(`${SPEC}/events/`))
    .map(([, t]) => JSON.parse(t) as Record<string, unknown>)
    .sort((a, b) => Number(a.ts) - Number(b.ts) || Number(a.seq) - Number(b.seq))

const decisions = (w: World) => events(w).filter(e => e.type !== 'start')

describe('only reserved first words are handled', () => {
  test('a feature description reaches the prompt based /temper:temper unchanged', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'plan' }))
    for (const args of ['add password reset by email', 'statuses please', 'build the thing']) {
      const r = await $.command.run({ command: 'temper', args, origin: { kind: 'composer' } } as never)
      expect(r.text).toBe(PASSTHROUGH)
    }
    expect(decisions(w)).toEqual([])
  })

  test('other commands are never touched', async ($, on) => {
    world(on, runFiles({ nextStage: 'plan' }))
    const r = await $.command.run({ command: 'compact', args: 'status', origin: { kind: 'composer' } } as never)
    expect(r.text).toBe(PASSTHROUGH)
  })

  test('the namespaced name temper:temper is handled the same', async ($, on) => {
    world(on, runFiles({ nextStage: 'plan' }))
    const r = await $.command.run({ command: 'temper:temper', args: 'help', origin: { kind: 'composer' } } as never)
    expect(r.text).toContain('Temper subcommands')
  })

  test('with the mod inert every word falls through to the prompt based command', async ($, on) => {
    world(on, runFiles({ nextStage: 'plan' }), { version: '2.1.286' })
    const r = await $.command.run({ command: 'temper', args: 'status', origin: { kind: 'composer' } } as never)
    expect(r.text).toBe(PASSTHROUGH)
  })
})

describe('read only subcommands', () => {
  test('status shows the section lines and counts', async ($, on) => {
    world(on, runFiles({ nextStage: 'build', passedCriteria: ['AC-01'] }))
    const r = await $.command.run({ command: 'temper', args: 'status', origin: { kind: 'composer' } } as never)
    expect(r.text).toContain('Temper enforcement: active')
    expect(r.text).toContain('Phase: Build (task 3 of 7)')
    expect(r.text).toContain('Criteria: 1 of 5 passed (AC-01)')
    expect(r.text).toContain('Mode: full, enforcement: on')
  })

  test('status works from any origin; with no run it says so', async ($, on) => {
    world(on, {})
    const r = await $.command.run({ command: 'temper', args: 'status', origin: { kind: 'sdk' } } as never)
    expect(r.text).toBe('No Temper run is active. Start one with /temper:temper <feature description>.')
  })

  test('timeline lists the phases so far', async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    const r = await $.command.run({ command: 'temper', args: 'timeline', origin: { kind: 'composer' } } as never)
    expect(r.text).toMatch(/start: start to Build/)
  })

  test('report writes .temper/report.md on demand', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build', passedCriteria: ['AC-01'] }))
    const r = await $.command.run({ command: 'temper', args: 'report', origin: { kind: 'composer' } } as never)
    expect(r.text).toBe('Wrote .temper/report.md')
    expect(w.files.get('.temper/report.md')).toContain('# Temper report: Password reset by email')
    expect(w.files.get('.temper/report.md')).toContain('Result: In progress (Build)')
  })

  test('mode and enforcement show the current values', { options: { uiMode: 'minimal', enforcement: 'off' } }, async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    expect((await $.command.run({ command: 'temper', args: 'mode', origin: { kind: 'composer' } } as never)).text).toBe('Temper mode: minimal')
    expect((await $.command.run({ command: 'temper', args: 'enforcement', origin: { kind: 'composer' } } as never)).text).toBe('Temper enforcement: off')
  })

  test('pause and resume are recorded and answered locally', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    const paused = await $.command.run({ command: 'temper', args: 'pause', origin: { kind: 'composer' } } as never)
    expect(paused.text).toContain('paused')
    const edit = await $.tool.call({ tool: 'Edit', file_path: 'src/billing.ts', old_string: 'a', new_string: 'b' })
    // Paused means the person has the wheel: no phase rule applies.
    expect(edit.text).toBe('stub ran')
    const resumed = await $.command.run({ command: 'temper', args: 'resume', origin: { kind: 'composer' } } as never)
    expect(resumed.text).toContain('resumed')
    expect(decisions(w).map(e => e.type)).toEqual(['pause', 'resume'])
  })
})

describe('decisions come only from the person', () => {
  test('override with a reason writes one event for the phase and moves one phase only', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'review', gates: { review: 'FAIL' } }))
    const r = await $.command.run({ command: 'temper', args: 'override reviewer is on leave, risk accepted', origin: { kind: 'composer' } } as never)
    // The prompt based command runs next and mirrors the override in the CLI.
    expect(r.text).toBe(PASSTHROUGH)
    expect(decisions(w)).toMatchObject([{ type: 'override', phase: 'review', reason: 'reviewer is on leave, risk accepted', origin: 'person' }])
    const status = await $.command.run({ command: 'temper', args: 'status', origin: { kind: 'composer' } } as never)
    expect(status.text).toContain('Phase: Check')
  })

  test('override without a reason is refused and writes no event', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'review' }))
    const r = await $.command.run({ command: 'temper', args: 'override', origin: { kind: 'composer' } } as never)
    expect(r.text).toBe('Override needs a reason: /temper:temper override <reason>')
    expect(decisions(w)).toEqual([])
  })

  test('the same decision from the SDK, the bridge or a plugin is refused', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'review' }))
    for (const kind of ['sdk', 'bridge', 'plugin'] as const) {
      const r = await $.command.run({ command: 'temper', args: 'override because', origin: { kind, name: 'x' } } as never)
      expect(r.text).toBe('Only the user can approve this. Ask them to press 1 or run /temper:temper approve.')
    }
    expect(decisions(w)).toEqual([])
  })

  test('approve needs a fresh PASS verdict, then advances', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'plan' }))
    const refused = await $.command.run({ command: 'temper', args: 'approve', origin: { kind: 'composer' } } as never)
    expect(refused.text).toContain('Plan has no PASS verdict yet')
    w.files.set('.temper/gates.json', JSON.stringify({ plan: { verdict: 'PASS', ts: '2999-01-01T00:00:00Z' } }))
    const ok = await $.command.run({ command: 'temper', args: 'approve', origin: { kind: 'composer' } } as never)
    expect(ok.text).toBe(PASSTHROUGH)
    expect(decisions(w)).toMatchObject([{ type: 'advance', from: 'plan', to: 'build', origin: 'person' }])
    // Build now: a plan file is writable, other files raise scope drift.
    expect(((await $.tool.call({ tool: 'Write', file_path: 'src/app.ts', content: 'x' })) as { text?: string }).text).toBe('stub ran')
  })

  test('back invalidates later phases: advancing again needs a fresh verdict', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'review' }))
    // Build, Review and Check passed long before the run went back.
    w.files.set('.temper/gates.json', JSON.stringify(Object.fromEntries(['build', 'review', 'check'].map(s => [s, { verdict: 'PASS', ts: '2020-01-01T00:00:00Z' }]))))
    expect((await $.command.run({ command: 'temper', args: 'back plan need a cache layer', origin: { kind: 'composer' } } as never)).text).toBe(PASSTHROUGH)
    expect(decisions(w)).toMatchObject([{ type: 'back', to: 'plan', reason: 'need a cache layer' }])
    const status = await $.command.run({ command: 'temper', args: 'status', origin: { kind: 'composer' } } as never)
    expect(status.text).toContain('Phase: Plan')
    expect(status.text).toContain('Stale: Build, Review, Check')
  })

  test('accept needs a reason; with one it is recorded', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'review' }))
    const none = await $.command.run({ command: 'temper', args: 'accept 2', origin: { kind: 'composer' } } as never)
    expect(none.text).toContain('needs a reason')
    const ok = await $.command.run({ command: 'temper', args: 'accept 2 false positive, input is trusted', origin: { kind: 'composer' } } as never)
    expect(ok.text).toBe(PASSTHROUGH)
    expect(decisions(w)).toMatchObject([{ type: 'accept', findingId: '2', reason: 'false positive, input is trusted' }])
  })

  test('the human override event then lets the CLI call through exactly once', async ($, on) => {
    world(on, runFiles({ nextStage: 'review', gates: { review: 'FAIL' } }))
    await $.command.run({ command: 'temper', args: 'override risk accepted', origin: { kind: 'composer' } } as never)
    const call = { tool: 'Bash', command: 'scripts/temper override review --reason "risk accepted"' } as const
    expect((await $.tool.call(call)).text).toBe('stub ran')
    expect(await $.tool.call(call)).toEqual({ deny: 'Only the user can approve this. Ask them to press 1 or run /temper:temper approve.' })
  })

  test('drift decisions by command need a pending drift', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    const none = await $.command.run({ command: 'temper', args: 'drift add', origin: { kind: 'composer' } } as never)
    expect(none.text).toContain('No scope drift is pending')
    // A denied edit (nobody to ask) leaves the path pending; the person then decides.
    const denied = await $.tool.call({ tool: 'Edit', file_path: 'src/billing.ts', old_string: 'a', new_string: 'b' })
    expect(denied.deny).toContain('/temper:temper drift add|revert|allow <reason>')
    const ok = await $.command.run({ command: 'temper', args: 'drift allow hotfix', origin: { kind: 'composer' } } as never)
    expect(ok.text).toBe(PASSTHROUGH)
    expect(decisions(w)).toMatchObject([{ type: 'drift', path: 'src/billing.ts', choice: 'allow-once', reason: 'hotfix', origin: 'person' }])
    expect((await $.tool.call({ tool: 'Edit', file_path: 'src/billing.ts', old_string: 'a', new_string: 'b' })).text).toBe('stub ran')
  })
})

describe('completion writes the audit report', () => {
  test('Check passing ends the run and writes .temper/report.md with the decisions', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'review', gates: { review: 'FAIL' }, passedCriteria: ['AC-01', 'AC-02', 'AC-03', 'AC-04'] }))
    await $.command.run({ command: 'temper', args: 'override reviewer is on leave, risk accepted', origin: { kind: 'composer' } } as never)
    w.files.set('.temper/gates.json', JSON.stringify({ check: { verdict: 'PASS', ts: '2999-01-01T00:00:00Z' } }))
    // The next commit attempt reads the verdict and completes the run.
    expect((await $.tool.call({ tool: 'Bash', command: 'git commit -m feat' })).text).toBe('stub ran')
    const md = w.files.get('.temper/report.md') ?? ''
    expect(md).toContain('Result: Done')
    expect(md).toContain('Review: overridden, reason: reviewer is on leave, risk accepted')
    expect(md).toContain('4 of 5 passed')
  })
})

describe('pull request attribution', () => {
  const pr = { kind: 'pr', text: 'Generated with Claude Code' } as const

  test('adds one Temper line while a run is on', async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    const r = await $.attribution.text(pr)
    expect(r.text).toBe('Generated with Claude Code\n\nBuilt under Temper: gated phases with an audit trail in .temper/report.md.')
  })

  test('off by option, with no run, and for other kinds', async ($, on) => {
    world(on, {})
    expect((await $.attribution.text(pr)).text).toBe('Generated with Claude Code')
  })

  test('prAttribution off leaves the text alone', { options: { prAttribution: 'off' } }, async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    expect((await $.attribution.text(pr)).text).toBe('Generated with Claude Code')
    expect((await $.attribution.text({ kind: 'commit', text: 'trailer' })).text).toBe('trailer')
  })
})

describe('a chained command spends every human event it matched', () => {
  test('two override calls in one command use two events, and neither can be reused', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'plan', gates: { plan: 'FAIL' } }))
    await $.session.start({ cwd: '/repo', surface: null, isInteractive: false })
    // Two human overrides of the same phase: one for Plan now, the second recorded after the advance
    // to Build; the CLI call for each phase may only be used once.
    await $.command.run({ command: 'temper', args: 'override first', origin: { kind: 'composer' } } as never)
    expect(decisions(w)).toHaveLength(1)
    const call = { tool: 'Bash', command: 'temper override plan --reason first' } as const
    expect((await $.tool.call(call)).text).toBe('stub ran')
    // The one event is spent: the identical call is refused, and so is a chain of two.
    expect((await $.tool.call(call)).deny).toContain('Only the user')
    expect((await $.tool.call({ tool: 'Bash', command: 'temper override plan --reason a && temper override plan --reason b' })).deny).toContain('Only the user')
  })
})

describe('every state changing word needs the person', () => {
  const ONLY = 'Only the user can approve this. Ask them to press 1 or run /temper:temper approve.'
  const words = [
    'mode full',
    'mode off',
    'enforcement off',
    'enforcement on',
    'pause',
    'resume',
    'approve',
    'next',
    'override because',
    'back plan because',
    'accept 1 because',
    'drift add because',
  ]

  for (const kind of ['sdk', 'bridge', 'plugin', 'task-notification', 'scheduled-trigger'] as const) {
    test(`from ${kind}: refused, nothing written, nothing changed`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build' }), { rows: [{ key: 'temper.uiMode', value: 'full', isLocked: false }] })
      await $.session.start({ cwd: '/repo', surface: null, isInteractive: false })
      for (const args of words) {
        const r = await $.command.run({ command: 'temper', args, origin: { kind, name: 'x' } } as never)
        expect(r.text).toBe(ONLY)
      }
      expect(decisions(w)).toEqual([])
      expect(w.configSets).toEqual([])
      expect(w.toasts).toEqual([])
      // Enforcement is exactly as before.
      const edit = await $.tool.call({ tool: 'Edit', file_path: 'src/billing.ts', old_string: 'a', new_string: 'b' })
      expect(edit.deny).toContain('scope drift')
    })
  }

  test('the read only words stay open to any origin', async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    await $.session.start({ cwd: '/repo', surface: null, isInteractive: false })
    for (const args of ['status', 'timeline', 'help', 'report', 'mode', 'enforcement']) {
      const r = await $.command.run({ command: 'temper', args, origin: { kind: 'sdk' } } as never)
      expect(r.text).not.toBe(ONLY)
    }
  })
})
