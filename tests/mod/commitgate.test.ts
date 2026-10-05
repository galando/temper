// The mod's commit rule is never stricter than the CLI commit gate (`temper gate commit`): it lets
// through what the gate lets through (an artifact only commit in every phase, a Build checkpoint commit on
// the run's branch with a green test run, every commit after the checks passed) and refuses the rest with the
// reason. The original On Continue steps depend on it: the plan commit right after the branch is created.
import { describe, expect, test } from 'claude-code/testing'

import { SPEC, runFiles } from './run-files'
import { world } from './world'

const START = { cwd: '/repo', surface: null, isInteractive: false } as const
const T = '2999-01-01T00:00:00Z'

type Opts = { next: string; branch?: string; head?: string; command?: string; gates?: string[]; green?: 'green' | 'red' | 'none' }

// A run as the CLI leaves it after the plan was approved on the feature branch.
const files = (o: Opts): Record<string, string> => {
  const f = runFiles({ nextStage: o.next })
  f['.temper/build-state.json'] = JSON.stringify({
    stage: 'plan_complete',
    spec: 'pw',
    spec_path: SPEC,
    next_stage: o.next,
    command: o.command ?? 'temper',
    ...(o.branch === undefined ? { branch: 'feature/pw' } : { branch: o.branch }),
  })
  f['.temper/gates.json'] = JSON.stringify(Object.fromEntries((o.gates ?? ['intent', 'plan']).map(g => [g, { verdict: 'PASS', ts: T }])))
  f['/repo/.git/HEAD'] = `ref: refs/heads/${o.head ?? 'feature/pw'}\n`
  if (o.green === 'green') f['.temper/evidence/build.json'] = JSON.stringify([{ claim: 'unit tests', exit_code: 0, phase: 'green' }])
  if (o.green === 'red') f['.temper/evidence/build.json'] = JSON.stringify([{ claim: 'unit tests', exit_code: 1, phase: 'green' }])
  return f
}

const commit = async ($: unknown, command: string): Promise<string | undefined> =>
  (await ($ as { tool: { call: (a: unknown) => Promise<{ deny?: string }> } }).tool.call({ tool: 'Bash', command })).deny

describe('Build checkpoint commits (docs/decisions/0009)', () => {
  test('on the feature branch with a green test run: allowed', async ($, on) => {
    world(on, files({ next: 'build', green: 'green' }))
    await $.session.start(START)
    expect(await commit($, 'git commit -m "feat(pw): scenario [AC-01]"')).toBeUndefined()
  })

  test('on main: refused, and the reason names both branches', async ($, on) => {
    world(on, files({ next: 'build', green: 'green', head: 'main' }))
    await $.session.start(START)
    const deny = await commit($, 'git commit -m "feat(pw): scenario"')
    expect(deny).toContain('Temper: commit blocked.')
    expect(deny).toContain('feature/pw')
    expect(deny).toContain('main')
    expect(deny).toMatch(/Next: /)
  })

  test('with a red last test run, or none: refused with a reason', async ($, on) => {
    world(on, files({ next: 'build', green: 'red' }))
    await $.session.start(START)
    expect(await commit($, 'git commit -m x')).toContain('green test run')
  })

  test('another command than temper (a fix run) has no checkpoint carve-out', { options: {} }, async ($, on) => {
    world(on, files({ next: 'build', green: 'green', command: 'fix' }))
    await $.session.start(START)
    expect(await commit($, 'git commit -m x')).toContain('Temper: commit blocked.')
  })

  test('the plan gate must be satisfied', async ($, on) => {
    world(on, files({ next: 'build', green: 'green', gates: ['intent'] }))
    await $.session.start(START)
    expect(await commit($, 'git commit -m x')).toContain('Temper: commit blocked.')
  })

  test('after Build moved on (Review), a code commit faces every gate', async ($, on) => {
    world(on, files({ next: 'review', green: 'green', gates: ['intent', 'plan', 'build'] }))
    await $.session.start(START)
    expect(await commit($, 'git commit -m x')).toContain('Temper: commit blocked.')
  })
})

describe('artifact only commits pass in every phase', () => {
  for (const next of ['intent', 'plan', 'build', 'review', 'check']) {
    test(`${next}: git add of .temper/specs/ then git commit`, async ($, on) => {
      world(on, files({ next, head: 'main' }))
      await $.session.start(START)
      expect(await commit($, `git add ${SPEC}/`)).toBeUndefined()
      expect(await commit($, 'git commit -m "docs(plan): approve plan - pw"')).toBeUndefined()
    })
  }

  test('in one command', async ($, on) => {
    world(on, files({ next: 'review', head: 'main' }))
    await $.session.start(START)
    expect(await commit($, `git add ${SPEC}/intent.md ${SPEC}/plan.md && git commit -m "docs: x"`)).toBeUndefined()
  })

  test('one staged file outside .temper/specs/ makes it a code commit', async ($, on) => {
    world(on, files({ next: 'review', head: 'main' }))
    await $.session.start(START)
    await commit($, `git add ${SPEC}/plan.md`)
    await commit($, 'git add src/app.ts')
    expect(await commit($, 'git commit -m x')).toContain('Temper: commit blocked.')
  })

  for (const stage of ['git add -A', 'git add .', 'git add --all', 'git add -u']) {
    test(`${stage} stages everything`, async ($, on) => {
      world(on, files({ next: 'review', head: 'main' }))
      await $.session.start(START)
      await commit($, stage)
      expect(await commit($, 'git commit -m x'), stage).toContain('Temper: commit blocked.')
    })
  }

  test('git commit -am is a code commit', async ($, on) => {
    world(on, files({ next: 'review', head: 'main' }))
    await $.session.start(START)
    await commit($, `git add ${SPEC}/plan.md`)
    expect(await commit($, 'git commit -am x')).toContain('Temper: commit blocked.')
  })

  test('a commit that went through starts the next staging from nothing', async ($, on) => {
    world(on, files({ next: 'review', head: 'main' }))
    await $.session.start(START)
    await commit($, `git add ${SPEC}/plan.md`)
    expect(await commit($, 'git commit -m "docs: a"')).toBeUndefined()
    // Nothing is staged now as far as the mod saw: a second commit is not an artifact commit.
    expect(await commit($, 'git commit -m "feat: b"')).toContain('Temper: commit blocked.')
  })
})

describe('code commits stay refused before the checks passed, allowed after', () => {
  test('before Check passed', async ($, on) => {
    world(on, files({ next: 'review', gates: ['intent', 'plan', 'build'] }))
    await $.session.start(START)
    await commit($, 'git add src/app.ts')
    expect(await commit($, 'git commit -m x')).toContain('Temper: commit blocked.')
  })

  test('every gate passed (plan, build, review, check)', async ($, on) => {
    world(on, files({ next: 'check', gates: ['intent', 'plan', 'build', 'review', 'check'] }))
    await $.session.start(START)
    await commit($, 'git add src/app.ts')
    expect(await commit($, 'git commit -m x')).toBeUndefined()
  })
})
