// The guard of ADR 0013 (core/rules.ts), unit by unit: the stage write table, Scope drift, and what only the person may
// cause: a call that is one the person's answer at the CLI's current step maps to, word for word, as the CLI wrote it
// in the question's options (the CLI's real views, scripts/selftest/view-fixtures.ts), or one of the CLI's own action.
import { describe, expect, test } from 'claude-code/testing'

import { ONLY_USER, evaluate } from '../../hooks/temper-mod/core/rules'
import type { RuleContext, RuleResult, RunFacts } from '../../hooks/temper-mod/core/rules'
import type { Stage } from '../../hooks/temper-mod/core/stages'
import { STAGES } from '../../hooks/temper-mod/core/stages'
import { stateAt } from './helpers'
import { nextCalls, optionCalls } from './run-files'
import { CLI_SEQ } from './world'

const SPEC = '.temper/specs/pw'
const CLI = 'scripts/temper'
const PLAN_FILES = ['src/app.ts', 'hooks/core/*.ts', 'docs/guide/']

const isDeny = (r: RuleResult): r is Extract<RuleResult, { deny: string }> => 'deny' in r

type Over = Partial<RunFacts>
function ctx(stage: Stage, o: { allowed?: string[]; facts?: Over; restart?: boolean; drift?: RuleContext['drift'] } = {}): RuleContext {
  const run = stateAt(stage, { specDir: SPEC, planFiles: PLAN_FILES, ...(o.facts ?? {}) })
  return { run, allowed: o.allowed ?? [], restart: o.restart ?? false, drift: o.drift ?? { added: [], allowOnce: [] } }
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
    for (const p of ['src/app.test.ts', 'tests/unit/x.test.ts', 'hooks/core/a.ts', 'docs/guide/page.md', 'pkg/test_thing.py', `${SPEC}/plan.md`]) expect('allow' in write(ctx('build'), p, 'Edit')).toBe(true)
    expect(isDeny(write(ctx('build'), 'hooks/core/sub/a.ts', 'Edit'))).toBe(true)
    // tasks.md is the plan the person approved: from Design on it is the CLI's.
    expect(isDeny(write(ctx('build'), `${SPEC}/tasks.md`, 'Edit'))).toBe(true)
  })

  test('absolute paths inside the root and traversal are normalised', () => {
    const c = { ...ctx('plan'), root: '/repo' }
    expect('allow' in write(c, `/repo/${SPEC}/plan.md`)).toBe(true)
    expect(isDeny(write(c, `/repo/${SPEC}/../../../src/app.ts`))).toBe(true)
  })

  test('other tools and no run pass through; a run saved for later does not (it lifts no rule)', () => {
    expect('allow' in evaluate(ctx('plan'), { tool: 'Read', input: { file_path: 'src/app.ts' } })).toBe(true)
    expect('allow' in write({ ...ctx('plan'), run: null }, 'src/app.ts')).toBe(true)
    const saved = ctx('plan', { allowed: optionCalls('plan-pass', 'Save for later', { more: true }) })
    expect(isDeny(write(saved, 'src/app.ts'))).toBe(true)
    expect(isDeny(write(saved, '.temper/gates.json'))).toBe(true)
  })

  test('at Commit only the spec folder is written: the code is what Review and Check passed (round 4 of the release audit)', () => {
    expect(isDeny(write(ctx('commit'), 'src/app.ts'))).toBe(true)
    expect(isDeny(write(ctx('commit'), 'src/other.ts'))).toBe(true)
    expect('allow' in write(ctx('commit'), `${SPEC}/plan.md`)).toBe(true)
  })

  test('an accepted config suggestion is written into the project notes after Check passed', () => {
    for (const p of ['CLAUDE.md', 'AGENTS.md', '.claude/CLAUDE.md']) {
      expect('allow' in write(ctx('check'), p)).toBe(true)
      expect('allow' in write(ctx('commit'), p)).toBe(true)
    }
    expect(isDeny(write(ctx('check'), 'docs/CLAUDE.md'))).toBe(true)
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
  const adv = (st: string, n: string) => `${CLI} state advance ${st}_complete ${n}`

  test('leaving Intent and Plan needs the person, even after a passed check: the calls of the answer, word for word', () => {
    expect(bash(ctx('intent'), adv('intent', 'plan'))).toEqual({ deny: ONLY_USER })
    expect(bash(ctx('plan'), adv('plan', 'build'))).toEqual({ deny: ONLY_USER })
    expect('allow' in bash(ctx('intent', { allowed: optionCalls('intent-pass', 'Continue to Plan (Recommended)') }), adv('intent', 'plan'))).toBe(true)
    expect('allow' in bash(ctx('plan', { allowed: optionCalls('plan-pass', 'Continue to Build (Recommended)') }), adv('plan', 'build'))).toBe(true)
    // The script by any path: the words after it are the call.
    expect('allow' in bash(ctx('plan', { allowed: optionCalls('plan-pass', 'Continue to Build (Recommended)') }), 'cd x && /a/b/scripts/temper state advance plan_complete build')).toBe(true)
    // Another next stage than the answer names is another call.
    expect(isDeny(bash(ctx('plan', { allowed: optionCalls('plan-pass', 'Continue to Build (Recommended)') }), adv('plan', 'design')))).toBe(true)
    const design = optionCalls('design-plan-pass', 'Continue to Design (Recommended)')
    expect('allow' in bash(ctx('plan', { allowed: design }), adv('plan', 'design'))).toBe(true)
    expect(isDeny(bash(ctx('plan', { allowed: design }), adv('plan', 'build')))).toBe(true)
    // Save for later is no approval.
    expect(isDeny(bash(ctx('plan', { allowed: optionCalls('plan-pass', 'Save for later', { more: true }) }), adv('plan', 'build')))).toBe(true)
  })

  test('a later stage follows its own verdict: the CLI refuses an advance past a failed check, not the mod', () => {
    for (const [st, n] of [['design', 'build'], ['build', 'review'], ['review', 'check'], ['check', 'commit']] as const) expect('allow' in bash(ctx(st), adv(st, n))).toBe(true)
  })

  test('a skip needs the person\'s skip of that stage, with any reason in the placeholder', () => {
    const skip = optionCalls('build-fail', 'Override and continue')
    expect(bash(ctx('build'), `${CLI} override build --reason x`)).toEqual({ deny: ONLY_USER })
    expect('allow' in bash(ctx('build', { allowed: skip }), `${CLI} override build --reason "the flaky test is known"`)).toBe(true)
    expect(isDeny(bash(ctx('build', { allowed: skip }), `${CLI} override check --reason x`))).toBe(true)
    expect(isDeny(bash(ctx('build', { allowed: skip }), `${CLI} override build --reason x --reason y`))).toBe(true)
  })

  test('a step back needs the person\'s step back to that stage', () => {
    const back = optionCalls('review-fail', 'Loop back to Build (Recommended)')
    expect('allow' in bash(ctx('review', { allowed: back }), `${CLI} state loop review build --reason "a real bug"`)).toBe(true)
    expect(isDeny(bash(ctx('review', { allowed: back }), `${CLI} state loop review plan --reason x`))).toBe(true)
    expect(isDeny(bash(ctx('review'), `${CLI} state loop review build --reason x`))).toBe(true)
    expect(isDeny(bash(ctx('review'), `${CLI} state set next_stage build`))).toBe(true)
  })

  test('state set next_stage to the stage the run is at changes nothing, and a step forward is the CLI\'s to check', () => {
    expect('allow' in bash(ctx('build'), `${CLI} state set next_stage build`)).toBe(true)
    expect('allow' in bash(ctx('build'), `${CLI} state set next_stage review`)).toBe(true)
  })

  test('accepting a finding needs the person\'s answer for that finding', () => {
    const accept = optionCalls('review-fail', 'Accept finding 1', { accept: true })
    expect('allow' in bash(ctx('review', { allowed: accept }), `${CLI} evidence accept --stage review --id 1 --reason x`)).toBe(true)
    expect(isDeny(bash(ctx('review', { allowed: accept }), `${CLI} evidence accept --stage review --id 2 --reason x`))).toBe(true)
    expect(isDeny(bash(ctx('review', { allowed: accept }), `${CLI} evidence accept --stage check --id 1 --reason x`))).toBe(true)
  })

  test('arming autonomy needs the Autonomous answer at the plan gate', () => {
    const arm = `${CLI} state set run_mode autonomous`
    expect('allow' in bash(ctx('plan', { allowed: optionCalls('plan-pass-autonomy', 'Autonomous: run the rest unattended') }), arm)).toBe(true)
    expect(isDeny(bash(ctx('plan', { allowed: optionCalls('plan-pass-autonomy', 'Stage by stage (Recommended)') }), arm))).toBe(true)
    expect(isDeny(bash(ctx('build'), arm))).toBe(true)
    expect('allow' in bash(ctx('build'), `${CLI} state set run_mode interactive`)).toBe(true)
  })

  test('an armed run\'s own loop back is the CLI\'s action, word for word', () => {
    const own = nextCalls('armed-review-fail')
    expect(own.some(c => c.includes('state loop review build'))).toBe(true)
    const loop = (own[0] ?? '').replace(/^\S+/, CLI)
    expect('allow' in bash(ctx('review', { allowed: own }), loop)).toBe(true)
    expect(isDeny(bash(ctx('review', { allowed: own }), `${CLI} state loop review plan --reason x`))).toBe(true)
  })

  test("keeping a task agent's commits needs the person's answer", () => {
    const reopen = `${CLI} group reopen G1 --task 1 --accept-foreign abc123 --reason x`
    expect(bash(ctx('build'), reopen)).toEqual({ deny: ONLY_USER })
    expect('allow' in bash(ctx('build', { allowed: [`${CLI} group reopen G1 --task 1 --accept-foreign abc123 --reason "{reason}"`] }), reopen)).toBe(true)
  })

  test('after the run is done an override is the person\'s Override and commit', () => {
    expect(bash(ctx('commit'), `${CLI} override review --reason x`)).toHaveProperty('deny')
    const override = optionCalls('commit-fail', 'Override and commit')
    expect('allow' in bash(ctx('commit', { allowed: override }), `${CLI} override review --reason x && ${CLI} gate commit`)).toBe(true)
  })

  test('clearing the run during a run needs the person\'s Start over, or the TRIVIAL exit, or the commit steps', () => {
    expect(isDeny(bash(ctx('build'), `${CLI} state archive`))).toBe(true)
    expect('allow' in bash(ctx('build', { restart: true }), `${CLI} state archive`)).toBe(true)
    expect('allow' in bash(ctx('build', { restart: true }), `${CLI} state init next`)).toBe(true)
    expect(isDeny(bash(ctx('build', { restart: true }), `${CLI} state init next --command fix`))).toBe(true)
    expect('allow' in bash(ctx('intent', { facts: { step: 0, trivialExit: true } }), `${CLI} state clear`)).toBe(true)
    expect(isDeny(bash(ctx('intent', { facts: { step: 2 } }), `${CLI} state clear`))).toBe(true)
    const steps = nextCalls('commit-pass')
    expect('allow' in bash(ctx('commit', { allowed: steps }), `${CLI} state archive`)).toBe(true)
    expect('allow' in bash(ctx('commit', { allowed: steps }), `${CLI} state clear`)).toBe(true)
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

  test('saved, at Commit, or in a fix run, the hook still may not be switched off; with no run it is the person\'s', () => {
    for (const cmd of ['git commit --no-verify -m x', 'git config core.hooksPath /tmp/none']) {
      expect(isDeny(bash(ctx('build', { allowed: optionCalls('build-pass', 'Save for later') }), cmd))).toBe(true)
      expect(isDeny(bash(ctx('commit'), cmd))).toBe(true)
      expect('allow' in bash({ ...ctx('build'), run: null }, cmd)).toBe(true)
    }
  })
})

describe('the stage order is the CLI\'s', () => {
  // scripts/selftest/temper-cases-2.sh pins STAGE_SEQ_TEMPER to the same text, so a change on either side fails a test.
  test('the mod\'s stages and the fake CLI\'s are STAGE_SEQ_TEMPER, then commit', () => {
    const seq = 'intent plan design build review check'
    expect(STAGES.filter(s => s !== 'commit').join(' ')).toBe(seq)
    expect(STAGES.at(-1)).toBe('commit')
    expect(CLI_SEQ.join(' ')).toBe(seq)
  })
})

// The independent review of the one flow: each case below was let through before its fix.
describe('review of the one flow: what goes around a gate', () => {
  const none = (o: Partial<RuleContext> = {}): RuleContext => ({ run: null, allowed: [], restart: false, drift: { added: [], allowOnce: [] }, ...o })
  const OV = `${CLI} override review --reason sneaky`

  test('the printed lines of a parked group and everyday git still run; with no run git is the person\'s', () => {
    expect('allow' in bash(ctx('build'), 'git -C .claude/worktrees/temper-pw-T2 rebase --autostash --onto abc1234~1 abc1234')).toBe(true)
    expect('allow' in bash(ctx('build'), 'git status && git log --oneline -5')).toBe(true)
    expect('allow' in bash(ctx('build'), 'git rebase main')).toBe(true)
    expect('allow' in bash(none(), `git bisect run ${CLI} gate check`)).toBe(true)
  })

  test('at the commit stage nothing goes around the hook, and no move is Claude\'s', () => {
    const c = ctx('commit')
    for (const cmd of ['git commit --no-verify -am x', 'git config core.hooksPath /tmp/none', `${CLI} state set next_stage build`, `${CLI} state set run_mode autonomous`, `${CLI} state init pw --command temper`, `${CLI} state loop commit build --reason x`]) {
      expect(isDeny(bash(c, cmd)), cmd).toBe(true)
    }
    expect(isDeny(write(c, '.git/hooks/pre-commit'))).toBe(true)
    expect(isDeny(write(c, '.claude/temper.config'))).toBe(true)
  })
  test('legit at the commit stage: the Commit steps (writes, archive, a plain commit, clear)', () => {
    const c = ctx('commit', { allowed: nextCalls('commit-pass') })
    expect('allow' in write(c, `${SPEC}/intent.md`)).toBe(true)
    // Round 4 of the release audit: the code is what Review and Check passed; at Commit it is not written.
    expect(isDeny(write(c, 'src/anything.ts'))).toBe(true)
    for (const cmd of [`${CLI} state archive`, 'git add -A && git commit -m "feat: x"', `${CLI} state clear`, `${CLI} state set run_mode interactive`]) {
      expect('allow' in bash(c, cmd), cmd).toBe(true)
    }
  })

  test('a /temper:fix run: its moves are not judged, but nothing goes around the hook', () => {
    const fix = none({ fixRun: true })
    for (const cmd of ['git commit --no-verify -am x', 'git -c core.hooksPath=/dev/null commit -m x', 'echo exit 0 > .git/hooks/pre-commit']) {
      expect(isDeny(bash(fix, cmd)), cmd).toBe(true)
    }
    expect(isDeny(write(fix, '.claude/temper.config'))).toBe(true)
    expect(isDeny(write(fix, '.git/hooks/pre-commit'))).toBe(true)
    for (const cmd of [`${CLI} state loop check fix --reason x`, `${CLI} override check --reason x`, `git bisect run ${CLI} gate check`, 'git commit -m "fix: x"']) {
      expect('allow' in bash(fix, cmd), cmd).toBe(true)
    }
    expect('allow' in write(fix, 'src/app.ts')).toBe(true)
  })

  test('a step back and a move on in one command: the mod lets the step back through, the CLI refuses the move on', () => {
    // After the loop the run is at Build; `state advance check_complete commit` then fails in the CLI (advance_ok).
    const back = ctx('check', { allowed: optionCalls('check-fail', 'Loop back to Build (Recommended)') })
    expect('allow' in bash(back, `${CLI} state loop check build --reason x && ${CLI} state advance check_complete commit`)).toBe(true)
    expect(isDeny(bash(back, `${CLI} state loop check plan --reason x`))).toBe(true)
  })

  test('Save for later stops the run and lifts no rule', () => {
    const saved = (s: Stage) => ctx(s, { allowed: optionCalls('plan-pass', 'Save for later', { more: true }) })
    expect(isDeny(write(saved('intent'), 'src/app.ts'))).toBe(true)
    expect(isDeny(write(saved('plan'), 'CLAUDE.md'))).toBe(true)
    expect(isDeny(bash(saved('build'), 'git commit --no-verify -m x'))).toBe(true)
    expect(isDeny(bash(saved('build'), 'echo {} > .temper/gates.json'))).toBe(true)
  })

  test('Start over begins a run of the same command, never a fix run', () => {
    expect('allow' in bash(ctx('build', { restart: true }), `${CLI} state init pw --command temper`)).toBe(true)
    expect(isDeny(bash(ctx('build', { restart: true }), `${CLI} state init pw --command fix`))).toBe(true)
  })
})

describe('the store of the person\'s decisions', () => {
  test('the editing tools do not write the plugin data folder while a run is active', () => {
    const store = '/root/.claude/plugins/data/temper-inline/store.json'
    expect(isDeny(write(ctx('plan'), store))).toBe(true)
    expect('allow' in write({ ...ctx('plan'), run: null }, store)).toBe(true)
  })
})
