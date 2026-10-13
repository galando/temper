// The guard of ADR 0012 (core/rules.ts), unit by unit: the stage write table, Scope drift, and the table of what only the
// person's move at the CLI's current step lets through. The CLI's files give the stage, the verdicts and the skips; the
// person's choices come from the question dialogs.
import { describe, expect, test } from 'claude-code/testing'

import type { Move, MoveKind } from '../../hooks/temper-mod/core/decisions'
import { ONLY_USER, evaluate } from '../../hooks/temper-mod/core/rules'
import type { RuleContext, RuleResult, RunFacts } from '../../hooks/temper-mod/core/rules'
import type { Stage } from '../../hooks/temper-mod/core/stages'
import { stateAt } from './helpers'

const SPEC = '.temper/specs/pw'
const CLI = 'scripts/temper'
const PLAN_FILES = ['src/app.ts', 'hooks/core/*.ts', 'docs/guide/']

const isDeny = (r: RuleResult): r is Extract<RuleResult, { deny: string }> => 'deny' in r

type Over = Partial<RunFacts>
function ctx(stage: Stage, o: { move?: { kind: MoveKind; to?: Stage }; facts?: Over; accepts?: string[]; restart?: boolean; drift?: RuleContext['drift']; nothingToLose?: boolean } = {}): RuleContext {
  const run = stateAt(stage, { specDir: SPEC, planFiles: PLAN_FILES, ...(o.facts ?? {}) })
  const move: Move | null = o.move ? ({ id: 'm1', run: 'r', step: 3, stage, ts: 1, reason: 'r', ...o.move } as Move) : null
  return {
    run,
    move,
    accepts: o.accepts ?? [],
    restart: o.restart ?? false,
    drift: o.drift ?? { added: [], allowOnce: [] },
    ...(o.nothingToLose !== undefined ? { nothingToLose: o.nothingToLose } : {}),
  }
}
const write = (c: RuleContext, path: string, tool = 'Write') => evaluate(c, { tool, input: tool === 'NotebookEdit' ? { notebook_path: path } : { file_path: path } })
const bash = (c: RuleContext, command: string) => evaluate(c, { tool: 'Bash', input: { command } })

describe('the stage write table: 6 stages x 3 tools x allowed and disallowed', () => {
  const TABLE: Array<{ stage: Stage; allowed: string; disallowed: string }> = [
    { stage: 'intent', allowed: `${SPEC}/intent.md`, disallowed: 'src/app.ts' },
    { stage: 'plan', allowed: `${SPEC}/plan.md`, disallowed: 'src/app.ts' },
    { stage: 'design', allowed: `${SPEC}/design.md`, disallowed: 'src/app.ts' },
    { stage: 'build', allowed: 'src/app.ts', disallowed: 'src/billing.ts' },
    { stage: 'review', allowed: `${SPEC}/review-notes.md`, disallowed: 'src/app.ts' },
    { stage: 'check', allowed: `${SPEC}/check-notes.md`, disallowed: 'src/app.ts' },
  ]
  for (const row of TABLE) {
    for (const tool of ['Write', 'Edit', 'NotebookEdit']) {
      test(`${row.stage} ${tool} allows ${row.allowed}`, () => expect('allow' in write(ctx(row.stage), row.allowed, tool)).toBe(true))
      test(`${row.stage} ${tool} denies ${row.disallowed}, with a Next: clause`, () => {
        const r = write(ctx(row.stage), row.disallowed, tool)
        expect(isDeny(r)).toBe(true)
        if (isDeny(r)) {
          expect(r.deny.startsWith('Temper: ')).toBe(true)
          expect(r.deny).toContain('Next: ')
          expect(r.deny).toContain(row.disallowed)
        }
      })
    }
  }

  test('a refusal names the Temper gate question, never a bar or a typed command', () => {
    for (const stage of ['intent', 'plan', 'design', 'review', 'check'] as const) {
      const r = write(ctx(stage), 'src/app.ts')
      expect(isDeny(r) && r.deny).toContain('`Temper gate`')
      expect(isDeny(r) && r.deny).not.toMatch(/Temper bar|press \d|key \d|\/temper:temper/)
    }
  })

  test('Plan allows the spec files, ADRs and context files but not other spec files', () => {
    for (const p of [`${SPEC}/intent.md`, `${SPEC}/tasks.md`, `${SPEC}/design.md`, `${SPEC}/plan-context.json`, 'docs/decisions/0009-mods.md']) expect('allow' in write(ctx('plan'), p)).toBe(true)
    expect(isDeny(write(ctx('plan'), `${SPEC}/report.md`))).toBe(true)
  })

  test('Build allows test files, plan globs and folders', () => {
    for (const p of ['src/app.test.ts', 'tests/unit/x.test.ts', 'hooks/core/a.ts', 'docs/guide/page.md', 'pkg/test_thing.py', `${SPEC}/tasks.md`]) expect('allow' in write(ctx('build'), p, 'Edit')).toBe(true)
    expect(isDeny(write(ctx('build'), 'hooks/core/sub/a.ts', 'Edit'))).toBe(true)
  })

  test('absolute paths inside the root and traversal are normalised', () => {
    const c = { ...ctx('plan'), root: '/repo' }
    expect('allow' in write(c, `/repo/${SPEC}/plan.md`)).toBe(true)
    expect(isDeny(write(c, `/repo/${SPEC}/../../../src/app.ts`))).toBe(true)
  })

  test('other tools, no run, the commit stage and a run saved for later pass through', () => {
    expect('allow' in evaluate(ctx('plan'), { tool: 'Read', input: { file_path: 'src/app.ts' } })).toBe(true)
    expect('allow' in write({ ...ctx('plan'), run: null }, 'src/app.ts')).toBe(true)
    expect('allow' in write(ctx('commit'), 'src/app.ts')).toBe(true)
    expect('allow' in write(ctx('plan', { move: { kind: 'pause' } }), 'src/app.ts')).toBe(true)
  })

  test('a saved run still keeps Temper own files', () => {
    expect(isDeny(write(ctx('build', { move: { kind: 'pause' } }), '.temper/gates.json'))).toBe(true)
  })
})

describe('Scope drift in Build', () => {
  test('a path outside the plan is denied naming scope drift, the three answers and the path', () => {
    const r = write(ctx('build'), 'src/billing.ts', 'Edit')
    expect(isDeny(r) && r.drift).toBe('src/billing.ts')
    for (const word of ['scope drift', 'src/billing.ts', 'add to plan', 'revert', 'allow once']) expect(isDeny(r) && r.deny).toContain(word)
  })

  test('Add to plan lets the path through; Allow once lets one write through and spends the answer', () => {
    expect('allow' in write(ctx('build', { drift: { added: ['src/billing.ts'], allowOnce: [] } }), 'src/billing.ts')).toBe(true)
    expect(write(ctx('build', { drift: { added: [], allowOnce: [{ id: 'd1', path: 'src/billing.ts' }] } }), 'src/billing.ts')).toEqual({ allow: true, use: 'd1' })
  })
})

describe('what only the person may cause, at the step the run is at', () => {
  const adv = (s: string, n: string) => `${CLI} state advance ${s}_complete ${n}`

  test('leaving Intent and Plan needs the person (Continue, an arming answer, or a skip), even after a passed check', () => {
    expect(bash(ctx('intent', { facts: { verdicts: { intent: 'PASS' } } }), adv('intent', 'plan'))).toEqual({ deny: ONLY_USER })
    expect(bash(ctx('plan', { facts: { verdicts: { plan: 'PASS' } } }), adv('plan', 'build'))).toEqual({ deny: ONLY_USER })
    for (const kind of ['approve', 'arm', 'override'] as const) {
      expect('allow' in bash(ctx('intent', { move: { kind } }), adv('intent', 'plan'))).toBe(true)
      expect('allow' in bash(ctx('plan', { move: { kind } }), adv('plan', 'build'))).toBe(true)
    }
    // Save for later or a step back is no approval.
    expect(isDeny(bash(ctx('plan', { move: { kind: 'pause' } }), adv('plan', 'build')))).toBe(true)
    expect(isDeny(bash(ctx('plan', { move: { kind: 'back', to: 'intent' } }), adv('plan', 'build')))).toBe(true)
  })

  test('every later stage follows its own verdict or the person skip', () => {
    for (const [s, n] of [['design', 'build'], ['build', 'review'], ['review', 'check'], ['check', 'commit']] as const) {
      expect(isDeny(bash(ctx(s), adv(s, n)))).toBe(true)
      expect(isDeny(bash(ctx(s, { facts: { verdicts: { [s]: 'FAIL' } } }), adv(s, n)))).toBe(true)
      expect('allow' in bash(ctx(s, { facts: { verdicts: { [s]: 'PASS' } } }), adv(s, n))).toBe(true)
      expect('allow' in bash(ctx(s, { facts: { skipped: new Set([s]) } }), adv(s, n))).toBe(true)
      expect('allow' in bash(ctx(s, { move: { kind: 'override' } }), adv(s, n))).toBe(true)
      // The person's Continue after a failed check is no skip.
      expect(isDeny(bash(ctx(s, { move: { kind: 'advance' }, facts: { verdicts: { [s]: 'FAIL' } } }), adv(s, n)))).toBe(true)
    }
  })

  test('an advance is for the stage the run is at, to its next stage only', () => {
    const c = ctx('review', { facts: { verdicts: { build: 'PASS', review: 'PASS' } } })
    expect(isDeny(bash(c, adv('build', 'review')))).toBe(true)
    expect(isDeny(bash(c, adv('review', 'commit')))).toBe(true)
    expect(isDeny(bash(c, adv('review', 'build')))).toBe(true)
    expect(isDeny(bash(c, `${CLI} state advance started build`))).toBe(true)
  })

  test('an advance to a name that is no stage gets the next stage named (the CLI calls the end commit)', () => {
    const r = bash(ctx('check', { facts: { verdicts: { check: 'PASS' } } }), adv('check', 'done'))
    expect(isDeny(r) && r.deny).toContain('state advance check_complete commit')
  })

  test('Plan goes on to Design only when the run has one', () => {
    const approved = { move: { kind: 'approve' as const } }
    expect('allow' in bash(ctx('plan', { ...approved, facts: { complexity: 'simple' } }), adv('plan', 'build'))).toBe(true)
    expect(isDeny(bash(ctx('plan', { ...approved, facts: { complexity: 'simple' } }), adv('plan', 'design')))).toBe(true)
    expect('allow' in bash(ctx('plan', { ...approved, facts: { complexity: 'medium', designRequired: true } }), adv('plan', 'design'))).toBe(true)
    expect(isDeny(bash(ctx('plan', { ...approved, facts: { complexity: 'medium', designRequired: true } }), adv('plan', 'build')))).toBe(true)
    // Design not switched on: a medium run may go either way.
    expect('allow' in bash(ctx('plan', { ...approved, facts: { complexity: 'medium' } }), adv('plan', 'build'))).toBe(true)
  })

  test('a chained advance takes its second stage from its own verdict, never from the approval', () => {
    const c = ctx('plan', { move: { kind: 'approve' }, facts: { complexity: 'medium', designRequired: true } })
    expect(isDeny(bash(c, `${adv('plan', 'design')} && ${adv('design', 'build')}`))).toBe(true)
  })

  test('a skip needs the person skip of the stage the run is at', () => {
    expect(bash(ctx('review'), `${CLI} override review --reason x`)).toEqual({ deny: ONLY_USER })
    expect('allow' in bash(ctx('review', { move: { kind: 'override' } }), `${CLI} override review --reason x`)).toBe(true)
    expect(isDeny(bash(ctx('review', { move: { kind: 'override' } }), `${CLI} override check --reason x`))).toBe(true)
    expect('allow' in bash(ctx('design', { move: { kind: 'override' } }), `${CLI} override design --reason x`)).toBe(true)
  })

  test('a step back needs the person step back to that stage; a loop leaves the stage the run is at', () => {
    const back = ctx('review', { move: { kind: 'back', to: 'build' } })
    expect('allow' in bash(back, `${CLI} state loop review build --reason x`)).toBe(true)
    expect('allow' in bash(back, `${CLI} state set next_stage build`)).toBe(true)
    expect(isDeny(bash(back, `${CLI} state loop review plan --reason x`))).toBe(true)
    expect(isDeny(bash(back, `${CLI} state loop check build --reason x`))).toBe(true)
    expect(isDeny(bash(ctx('review'), `${CLI} state loop review build --reason x`))).toBe(true)
    expect(isDeny(bash(ctx('review'), `${CLI} state set next_stage build`))).toBe(true)
    expect('allow' in bash(ctx('design', { move: { kind: 'back', to: 'plan' } }), `${CLI} state loop design plan --reason x`)).toBe(true)
  })

  test('state set next_stage to the stage the run is at changes nothing, and needs no one', () => {
    expect('allow' in bash(ctx('build'), `${CLI} state set next_stage build`)).toBe(true)
  })

  test('accepting a finding needs the person answer for that finding, in Review', () => {
    const c = ctx('review', { accepts: ['1'] })
    expect('allow' in bash(c, `${CLI} evidence accept --stage review --id 1 --reason x`)).toBe(true)
    expect(isDeny(bash(c, `${CLI} evidence accept --stage review --id 2 --reason x`))).toBe(true)
    expect(isDeny(bash(c, `${CLI} evidence accept --stage check --id 1 --reason x`))).toBe(true)
    expect(isDeny(bash(ctx('check', { accepts: ['1'] }), `${CLI} evidence accept --stage review --id 1 --reason x`))).toBe(true)
  })

  test('arming autonomy needs the Autonomous answer at the plan gate, and autonomy enabled', () => {
    const arm = `${CLI} state set run_mode autonomous`
    expect('allow' in bash(ctx('plan', { move: { kind: 'arm' }, facts: { autonomyEnabled: true } }), arm)).toBe(true)
    expect(isDeny(bash(ctx('plan', { move: { kind: 'arm' } }), arm))).toBe(true)
    expect(isDeny(bash(ctx('plan', { move: { kind: 'approve' }, facts: { autonomyEnabled: true } }), arm))).toBe(true)
    expect(isDeny(bash(ctx('build', { facts: { autonomyEnabled: true } }), arm))).toBe(true)
    expect('allow' in bash(ctx('build'), `${CLI} state set run_mode interactive`)).toBe(true)
  })

  test('an armed run loops back to Build by itself after a failed Review or Check, never further', () => {
    const armed = (s: Stage) => ctx(s, { facts: { runMode: 'autonomous', autonomyEnabled: true } })
    expect('allow' in bash(armed('review'), `${CLI} state loop review build --reason x`)).toBe(true)
    expect('allow' in bash(armed('check'), `${CLI} state loop check build --reason x`)).toBe(true)
    expect(isDeny(bash(armed('check'), `${CLI} state loop check plan --reason x`))).toBe(true)
    expect(isDeny(bash(armed('build'), `${CLI} state loop build plan --reason x`))).toBe(true)
    // Armed with autonomy switched off since: no loop by itself.
    expect(isDeny(bash(ctx('review', { facts: { runMode: 'autonomous' } }), `${CLI} state loop review build --reason x`))).toBe(true)
  })

  test("keeping a task agent's commits needs the person answer, once", () => {
    const reopen = `${CLI} group reopen G1 --accept-foreign abc123 --reason x`
    expect(bash(ctx('build'), reopen)).toEqual({ deny: ONLY_USER })
    expect(bash(ctx('build', { move: { kind: 'keep' } }), reopen)).toEqual({ allow: true, use: 'm1' })
  })

  test('after the run is done an override is the person Override and commit', () => {
    expect(isDeny(bash(ctx('commit'), `${CLI} override check --reason x`))).toBe(true)
    expect('allow' in bash(ctx('commit', { move: { kind: 'commitOverride' } }), `${CLI} override check --reason x && ${CLI} override review --reason x`)).toBe(true)
  })

  test('clearing the run during a run needs the person Start over, or the TRIVIAL exit', () => {
    expect(isDeny(bash(ctx('build'), `${CLI} state archive`))).toBe(true)
    expect('allow' in bash(ctx('build', { restart: true }), `${CLI} state archive`)).toBe(true)
    expect('allow' in bash(ctx('build', { restart: true }), `${CLI} state init next`)).toBe(true)
    expect('allow' in bash(ctx('intent', { facts: { step: 0 }, nothingToLose: true }), `${CLI} state clear`)).toBe(true)
    expect(isDeny(bash(ctx('intent', { facts: { step: 2 }, nothingToLose: true }), `${CLI} state clear`))).toBe(true)
    expect('allow' in bash(ctx('commit'), `${CLI} state archive`)).toBe(true)
  })

  test('the CLI own keys are refused, and the orchestrator keys only in their stage and form', () => {
    for (const key of ['stage', 'branch', 'spec_path', 'command', 'run_id', 'step']) expect(isDeny(bash(ctx('build'), `${CLI} state set ${key} x`))).toBe(true)
    expect('allow' in bash(ctx('plan'), `${CLI} state set complexity medium`)).toBe(true)
    expect(isDeny(bash(ctx('build'), `${CLI} state set complexity medium`))).toBe(true)
    expect('allow' in bash(ctx('build'), `${CLI} state set base_sha 0123abcd`)).toBe(true)
    expect(isDeny(bash(ctx('review'), `${CLI} state set base_sha 0123abcd`))).toBe(true)
  })
})

describe('commits: the native pre-commit hook is the commit gate', () => {
  test('a plain git commit goes to the hook; --no-verify and a changed hooks path are refused', () => {
    expect('allow' in bash(ctx('build'), 'git commit -m x')).toBe(true)
    expect(isDeny(bash(ctx('build'), 'git commit --no-verify -m x'))).toBe(true)
    expect(isDeny(bash(ctx('build'), 'git -c core.hooksPath=/dev/null commit -m x'))).toBe(true)
  })

  test('a commit the hook does not check is refused while a run is active, not when saved or done', () => {
    for (const cmd of ['git merge other', 'git cherry-pick abc', 'git revert HEAD', 'git commit src/a.ts -m x']) {
      expect(isDeny(bash(ctx('build'), cmd))).toBe(true)
      expect('allow' in bash(ctx('build', { move: { kind: 'pause' } }), cmd)).toBe(true)
      expect('allow' in bash(ctx('commit'), cmd)).toBe(true)
    }
  })

  test('a git alias that runs a shell is refused while a run is active', () => {
    for (const cmd of [`git -c alias.x='!scripts/temper override plan --reason x' x`, `git config alias.x '!scripts/temper override plan --reason x'`]) {
      expect(isDeny(bash(ctx('plan'), cmd))).toBe(true)
    }
    expect('allow' in bash(ctx('plan'), 'git config user.name x')).toBe(true)
  })
})
