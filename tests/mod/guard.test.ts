// The guard of ADR 0013 (core/rules.ts), unit by unit: the stage write table, Scope drift, and what only the person may
// cause: a call that is one the person's answer at the CLI's current step maps to, word for word, as the CLI wrote it
// in the question's options (the CLI's real views, scripts/selftest/view-fixtures.ts), or one of the CLI's own action.
import { describe, expect, test } from 'claude-code/testing'

import { ONLY_USER, evaluate } from '../../hooks/temper-mod/core/rules'
import type { RuleContext, RuleResult, RunFacts } from '../../hooks/temper-mod/core/rules'
import type { Stage } from '../../hooks/temper-mod/core/stages'
import { STAGES } from '../../hooks/temper-mod/core/stages'
import { parseRunView } from '../../hooks/temper-mod/core/runview'
import { stateAt } from './helpers'
import { deriveView, nextCalls, optionCalls, runFiles, shownOf } from './run-files'
import { CLI_SEQ, denyText, world } from './world'

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

  // WP12: the approval is bound to the intent as shown; from Build on a change to it needs a step back to Plan and a
  // new approval, so no tool writes the run's intent.md. Before the approval the agents of Intent and Plan write it.
  test('a write to the run\'s intent.md is refused at Build, Review, Check and Commit and allowed at Intent, Plan and Design', () => {
    for (const tool of ['Write', 'Edit']) {
      for (const stage of ['intent', 'plan', 'design'] as const) expect('allow' in write(ctx(stage), `${SPEC}/intent.md`, tool)).toBe(true)
      for (const stage of ['build', 'review', 'check', 'commit'] as const) {
        const r = write(ctx(stage), `${SPEC}/intent.md`, tool)
        expect(isDeny(r)).toBe(true)
        if (isDeny(r)) {
          expect(r.deny.startsWith('Temper: ')).toBe(true)
          expect(r.deny).toContain('Plan')
        }
      }
    }
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
    expect('allow' in bash(ctx('intent', { allowed: optionCalls('intent-ask', 'Continue to Plan (Recommended)') }), adv('intent', 'plan'))).toBe(true)
    // WP12: the approving advance carries the digests the question showed; the click lets that call through, word for word
    const shown = shownOf('plan-pass', 'Ask me at every stage')
    expect('allow' in bash(ctx('plan', { allowed: optionCalls('plan-pass', 'Ask me at every stage') }), adv('plan', 'build') + shown)).toBe(true)
    expect(isDeny(bash(ctx('plan', { allowed: optionCalls('plan-pass', 'Ask me at every stage') }), adv('plan', 'build')))).toBe(true)
    // The script by any path: the words after it are the call.
    expect('allow' in bash(ctx('plan', { allowed: optionCalls('plan-pass', 'Ask me at every stage') }), 'cd x && /a/b/scripts/temper state advance plan_complete build' + shown)).toBe(true)
    // Another next stage than the answer names is another call.
    expect(isDeny(bash(ctx('plan', { allowed: optionCalls('plan-pass', 'Ask me at every stage') }), adv('plan', 'design')))).toBe(true)
    const design = optionCalls('design-plan-pass', 'Continue to Design (Recommended)')
    expect('allow' in bash(ctx('plan', { allowed: design }), adv('plan', 'design') + shownOf('design-plan-pass', 'Continue to Design (Recommended)'))).toBe(true)
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
    const back = optionCalls('review-fail', 'Loop back to Build')
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

  test('arming autonomy needs the Approve and build answer at the plan gate', () => {
    // WP12: the arming call carries the digests the question showed (--shown), so it is read from the option
    const arm = optionCalls('plan-pass-autonomy', 'Approve and build (Recommended)').find(c => c.includes('run_mode autonomous'))!
      .replace(/^\S+/, CLI)
    expect('allow' in bash(ctx('plan', { allowed: optionCalls('plan-pass-autonomy', 'Approve and build (Recommended)') }), arm)).toBe(true)
    expect(isDeny(bash(ctx('plan', { allowed: optionCalls('plan-pass-autonomy', 'Ask me at every stage') }), arm))).toBe(true)
    expect(isDeny(bash(ctx('build'), arm))).toBe(true)
    expect('allow' in bash(ctx('build'), `${CLI} state set run_mode interactive`)).toBe(true)
  })

  // WP24: the rule's loop back to Build is gone: at a failed Review the CLI's own move is the repair in the stage, or a
  // recorded stop (the park call) where the repair may not start (this fixture is no repository with a reviewed HEAD)
  test('WP24 the run to the commit: its own moves keep the mode, and Review never loops back by rule: its own move is the repair in the stage or a park', () => {
    const own = nextCalls('armed-build-pass')
    expect(own.map(c => c.replace(/^\S+ /, ''))).toEqual(['state advance build_complete review'])
    for (const c of own) expect('allow' in bash(ctx('build', { allowed: own }), c.replace(/^\S+/, CLI))).toBe(true)
    const move = nextCalls('armed-review-fail')
    expect(move.length === 1 && /repair start --stage review$|park --verdict PARKED-NEEDS-DECISION /.test(move[0]!) && !move[0]!.includes('state loop')).toBe(true)
    expect('allow' in bash(ctx('review', { allowed: move }), move[0]!.replace(/^\S+/, CLI))).toBe(true)
    expect(isDeny(bash(ctx('review'), `${CLI} state loop review build --reason x`))).toBe(true)
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

  test('clearing the run during a run needs the person\'s Start over or the commit steps; at Intent too (WP17)', () => {
    expect(isDeny(bash(ctx('build'), `${CLI} state archive`))).toBe(true)
    expect('allow' in bash(ctx('build', { restart: true }), `${CLI} state archive`)).toBe(true)
    expect('allow' in bash(ctx('build', { restart: true }), `${CLI} state init next`)).toBe(true)
    expect(isDeny(bash(ctx('build', { restart: true }), `${CLI} state init next --command fix`))).toBe(true)
    // WP17: a trivial request is the CLI's verdict (`temper intent trivial`), closed by the flow; no state clear is let
    // through at Intent, for an agent or the session, with the trivial window open or not
    expect(isDeny(bash(ctx('intent', { facts: { step: 0, trivialExit: true } }), `${CLI} state clear`))).toBe(true)
    expect(isDeny(bash(ctx('intent', { facts: { step: 0 } }), `${CLI} state clear`))).toBe(true)
    expect(isDeny(bash(ctx('intent', { facts: { step: 2 } }), `${CLI} state clear`))).toBe(true)
    const steps = nextCalls('commit-record')
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
    expect(STAGES.filter(s => s !== 'commit' && s !== 'pipeline').join(' ')).toBe(seq)
    expect(STAGES.slice(-2).join(' ')).toBe('commit pipeline')   // the optional Pipeline stage follows Commit (9.7.5)
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
    // The commit steps come after the report and the person's answer about the page (scripts/flow.py, the end of the run).
    const c = ctx('commit', { allowed: nextCalls('commit-record') })
    // WP12: the intent is the approved one; the CLI completes it (`intent complete`), no tool writes it
    expect(isDeny(write(c, `${SPEC}/intent.md`))).toBe(true)
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
    const back = ctx('check', { allowed: optionCalls('check-fail', 'Loop back to Build') })
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

// WP17: the trivial window. After `temper intent trivial` the run state holds the verdict and the view says
// guard.trivial_exit: the Intent agent may then make the one change outside the spec folder. The window is Intent's
// only; the record .temper/trivial.json, which holds the commit to the bound, is the CLI's to write, the window open or
// not.
describe('the trivial window: the Intent agent writes the one change while the verdict is recorded', () => {
  const open = (stage: Stage = 'intent') => ctx(stage, { facts: { step: 0, trivialExit: true } })
  test('while the trivial window is open the Intent agent may write a project file; with it closed it is refused', () => {
    for (const tool of ['Write', 'Edit']) {
      expect('allow' in write(open(), 'src/app.ts', tool), tool).toBe(true)
      expect('allow' in write(open(), 'README.md', tool), tool).toBe(true)
      expect(isDeny(write(ctx('intent', { facts: { step: 0, trivialExit: false } }), 'src/app.ts', tool)), tool).toBe(true)
    }
    // the window is Intent's: the flag at a later stage opens nothing
    for (const stage of ['plan', 'design', 'review', 'check'] as const) {
      expect(isDeny(write(open(stage), 'src/app.ts')), stage).toBe(true)
    }
  })
  test('the record of the verdict, .temper/trivial.json, is refused to a tool and to a shell write, the window open or not', () => {
    const f = '.temper/trivial.json'
    const guarded = (r: RuleResult): boolean => isDeny(r) && r.deny.startsWith('Temper: ') && r.deny.includes('by hand')
    for (const c of [open(), ctx('intent'), ctx('plan'), ctx('build'), ctx('check')]) {
      for (const tool of ['Write', 'Edit']) expect(guarded(write(c, f, tool)), `${c.run?.stage} ${tool}`).toBe(true)
      expect(guarded(write(c, `/repo/${f}`)), `${c.run?.stage} absolute`).toBe(true)
      for (const cmd of [`echo '{}' > ${f}`, `printf x >> ${f}`, `rm ${f}`, `rm -f ${f}`, `cp /tmp/t.json ${f}`]) {
        expect(guarded(bash(c, cmd)), `${c.run?.stage}: ${cmd}`).toBe(true)
      }
    }
    for (const cmd of ['rm .temper/triv*.json', 'rm -f .temper/t?ivial.json']) {
      expect(isDeny(bash(open(), cmd)), cmd).toBe(true)
    }
  })
  test('the verdict is the CLI\'s: state set trivial, or a path below it, is refused, the window open or not', () => {
    for (const c of [ctx('intent', { facts: { step: 0 } }), open(), ctx('build')]) {
      for (const key of ['trivial', 'trivial.why', 'trivial.dirty_before']) {
        expect(isDeny(bash(c, `${CLI} state set ${key} x`)), `${c.run?.stage}: ${key}`).toBe(true)
      }
    }
  })
})

// 9.8.5 (WP08, M14): the files of the CLI that can turn a gate row are guarded like the gate verdicts: the store of
// reused passes and the Design answers (WP21: the per command check of the plan and its two stores are gone).
describe('the files that turn a gate row', () => {
  const FILES = [
    '.git/temper-results.json', '.temper/decisions.json',
    '.temper/check/ahead.json',
  ]
  const guarded = (r: RuleResult): boolean => isDeny(r) && r.deny.startsWith('Temper: ') && r.deny.includes('by hand')
  for (const f of FILES) {
    test(`during a run a Write, a Bash redirect and an rm of ${f} are refused`, () => {
      for (const stage of ['plan', 'build', 'check'] as const) {
        for (const tool of ['Write', 'Edit']) expect(guarded(write(ctx(stage), f, tool)), `${stage} ${tool}`).toBe(true)
        expect(guarded(write(ctx(stage), `/repo/${f}`)), `${stage} absolute`).toBe(true)
        for (const cmd of [`echo '{}' > ${f}`, `printf x >> ${f}`, `rm ${f}`, `rm -f ${f}`]) {
          expect(guarded(bash(ctx(stage), cmd)), `${stage}: ${cmd}`).toBe(true)
        }
      }
    })
  }
  test('rm .temper/*.json, and a glob that spells only the new files, are refused', () => {
    for (const cmd of ['rm .temper/*.json', 'rm -f .temper/[dp]*.json', 'rm .temper/deci*.json', 'rm .git/temper-*.json']) {
      expect(isDeny(bash(ctx('build'), cmd)), cmd).toBe(true)
    }
  })
})

// 9.8.5 (WP10): one budget in the CLI. Only the person grants more repeats, at the question at the limit (run.budget,
// option grant-more); the record of the repeats, .temper/budget.json, is the CLI's to write.
describe('the budget: only the person grants more, and its record is the CLI\'s', () => {
  const GRANT = `${CLI} budget grant --key gate:check --reason "{reason}"`
  const grant = (key: string, reason = 'x'): string => `${CLI} budget grant --key ${key} --reason "${reason}"`
  test('budget grant outside the person\'s answer is refused, at every stage of a run', () => {
    for (const stage of ['plan', 'build', 'review', 'check'] as const) {
      expect(bash(ctx(stage), grant(`gate:${stage}`, 'the next try is different')), stage).toEqual({ deny: ONLY_USER })
    }
    // no other call of an answer lets it through: the step back of the same question is not a grant
    const back = optionCalls('check-fail', 'Loop back to Build')
    expect(bash(ctx('check', { allowed: back }), grant('gate:check'))).toEqual({ deny: ONLY_USER })
  })

  test('budget grant passes as the call of the answer, word for word: the same key, one reason', () => {
    const c = ctx('check', { allowed: [GRANT] })
    expect('allow' in bash(c, grant('gate:check', 'I changed something outside the run'))).toBe(true)
    const other = "cd x && /a/b/scripts/temper budget grant --key gate:check --reason 'the next try is different'"
    expect('allow' in bash(c, other)).toBe(true)
    for (const cmd of [
      grant('gate:build'),
      grant('group:G1'),
      `${grant('gate:check')} --key gate:build`,
      `${grant('gate:check')} && ${grant('gate:check', 'y')} --key task:1`,
    ]) {
      expect(isDeny(bash(c, cmd)), cmd).toBe(true)
    }
  })

  test('an unquoted glob that could spell budget or grant is refused; printing the record is not the person\'s', () => {
    for (const cmd of [`${CLI} b?dget grant --key gate:check --reason x`, `${CLI} budget gr?nt --key gate:check`]) {
      expect(isDeny(bash(ctx('check'), cmd)), cmd).toBe(true)
    }
    expect('allow' in bash(ctx('check'), `${CLI} budget`)).toBe(true)
  })

  test('during a run a write of .temper/budget.json is refused: an editing tool, a redirect, an rm, a glob', () => {
    const f = '.temper/budget.json'
    const guarded = (r: RuleResult): boolean => isDeny(r) && r.deny.startsWith('Temper: ') && r.deny.includes('by hand')
    for (const stage of ['plan', 'build', 'review', 'check'] as const) {
      for (const tool of ['Write', 'Edit']) expect(guarded(write(ctx(stage), f, tool)), `${stage} ${tool}`).toBe(true)
      expect(guarded(write(ctx(stage), `/repo/${f}`)), `${stage} absolute`).toBe(true)
      for (const cmd of [`echo '{}' > ${f}`, `printf x >> ${f}`, `rm ${f}`, `rm -f ${f}`, `cp /tmp/b.json ${f}`]) {
        expect(guarded(bash(ctx(stage), cmd)), `${stage}: ${cmd}`).toBe(true)
      }
    }
    for (const cmd of ['rm .temper/bu?get.json', 'rm -f .temper/budg*.json']) {
      expect(isDeny(bash(ctx('build'), cmd)), cmd).toBe(true)
    }
  })
})

// 9.8.5 (WP20): "Go on anyway" at the red base question (base.red) is a recorded skip of the suite: only the
// person's answer runs `baseline accept-red`, word for word as the option wrote it. The baseline's own calls (start,
// clean) are the CLI's and pass.
describe('the red base: only the person goes on anyway', () => {
  const ACCEPT = `${CLI} baseline accept-red --reason '{reason}'`
  const accept = (reason = 'the base was red before this run'): string => `${CLI} baseline accept-red --reason '${reason}'`
  test('baseline accept-red outside the person\'s answer is refused, at every stage of a run', () => {
    for (const stage of ['intent', 'plan', 'build', 'review', 'check'] as const) {
      expect(bash(ctx(stage), accept()), stage).toEqual({ deny: ONLY_USER })
    }
    // the call of another answer does not let it through
    const back = optionCalls('check-fail', 'Loop back to Build')
    expect(bash(ctx('check', { allowed: back }), accept())).toEqual({ deny: ONLY_USER })
  })

  test('baseline accept-red passes as the call of the answer, word for word, with one reason', () => {
    const c = ctx('intent', { allowed: [ACCEPT] })
    expect('allow' in bash(c, accept('I know the base is red'))).toBe(true)
    for (const cmd of [`${accept()} && ${accept('again')}`, `${accept()}; ${CLI} override check --reason x`]) {
      expect(isDeny(bash(c, cmd)), cmd).toBe(true)
    }
  })

  test('an unquoted glob that could spell accept-red is refused; the baseline\'s own calls are the CLI\'s', () => {
    expect(isDeny(bash(ctx('intent'), `${CLI} baseline accept-r?d --reason x`))).toBe(true)
    for (const cmd of [`${CLI} baseline start`, `${CLI} baseline start --again`, `${CLI} baseline clean`]) {
      expect('allow' in bash(ctx('intent'), cmd), cmd).toBe(true)
    }
  })
})

// 9.8.5 (WP22, step 11): "Run it anyway" (`--fresh`), a check run whatever the reuse store holds, is the person's
// option only: it passes as the call of the answer, word for word. The same calls without the flag are the CLI's.
describe('run it anyway: only the person runs a check whatever the store holds', () => {
  const FRESH = [`${CLI} check run --fresh`, `${CLI} check build-checks --fresh`, `${CLI} group gate G1 --fresh`,
    `${CLI} group gate G1 --timeout-s 60 --fresh`, `${CLI} integrate --fresh`]
  test('a --fresh call outside the person\'s answer is refused, at every stage of a run', () => {
    for (const stage of ['build', 'review', 'check', 'commit'] as const) {
      for (const cmd of FRESH) expect(bash(ctx(stage), cmd), `${stage}: ${cmd}`).toEqual({ deny: ONLY_USER })
    }
    const back = optionCalls('check-fail', 'Loop back to Build')
    expect(bash(ctx('check', { allowed: back }), `${CLI} check run --fresh`)).toEqual({ deny: ONLY_USER })
  })

  test('it passes as the call of the answer, word for word; without the flag the calls are the CLI\'s', () => {
    const c = ctx('check', { allowed: [`${CLI} check run --fresh`] })
    expect('allow' in bash(c, `${CLI} check run --fresh`)).toBe(true)
    for (const cmd of [`${CLI} integrate --fresh`, `${CLI} group gate G1 --fresh`, `${CLI} check build-checks --fresh`]) {
      expect(isDeny(bash(c, cmd)), cmd).toBe(true)
    }
    expect('allow' in bash(ctx('check'), `${CLI} check run`)).toBe(true)
    for (const cmd of [`${CLI} group gate G1`, `${CLI} group gate G1 --timeout-s 60`, `${CLI} integrate`, `${CLI} check build-checks`]) {
      expect('allow' in bash(ctx('build'), cmd), cmd).toBe(true)
    }
  })

  test('an unquoted glob that could spell --fresh is refused', () => {
    for (const cmd of [`${CLI} check run --fr?sh`, `${CLI} integrate --fre*`]) expect(isDeny(bash(ctx('check'), cmd)), cmd).toBe(true)
  })
})

// 9.8.5 (WP22): the reuse store decides gate rows: a pass kept there is a check that is not run again, a failure kept
// there is a check that is not run again either. It is one file in the git common folder, shared by every worktree of
// the clone, and only the CLI's runner writes it, the byproduct list in it included.
describe('the reuse store: a write to temper-results.json in the git folder is refused', () => {
  const STORE = '.git/temper-results.json'
  const guarded = (r: RuleResult): boolean => isDeny(r) && r.deny.startsWith('Temper: ')
  // the store as a session in the project folder, in a group worktree under .claude/worktrees/ and by an absolute path
  // names it
  const PATHS = [STORE, `/repo/${STORE}`, `../../../${STORE}`, `/repo/.claude/worktrees/temper-pw-G1/../../../${STORE}`]
  test('an editing tool is refused at every stage of a run, from the project folder and from a group worktree', () => {
    for (const stage of ['intent', 'plan', 'design', 'build', 'review', 'check', 'commit'] as const) {
      for (const p of PATHS) {
        for (const tool of ['Write', 'Edit']) expect(guarded(write(ctx(stage), p, tool)), `${stage} ${tool} ${p}`).toBe(true)
      }
    }
  })
  test('a shell write is refused: a redirect, tee, cp, mv, sed -i, truncate and rm', () => {
    for (const stage of ['build', 'check', 'commit'] as const) {
      for (const p of PATHS) {
        for (const cmd of [`echo '{}' > ${p}`, `printf x >> ${p}`, `: > ${p}`, `echo '{}' | tee ${p}`, `cp /tmp/kept.json ${p}`,
          `mv /tmp/kept.json ${p}`, `sed -i 's/fail/pass/' ${p}`, `truncate -s 0 ${p}`, `rm -f ${p}`]) {
          expect(guarded(bash(ctx(stage), cmd)), `${stage}: ${cmd}`).toBe(true)
        }
      }
    }
  })
})

// 9.8.5 (WP23): the failure record decides the next step at a failed Build gate (its class) and counts toward what
// a rule does; one file of the evidence folder, written only by scripts/failure.py through the CLI. A step back
// leaves it.
describe('the failure record: a write to .temper/evidence/failures.json is refused', () => {
  const FILE = '.temper/evidence/failures.json'
  const guarded = (r: RuleResult): boolean => isDeny(r) && r.deny.startsWith('Temper: ')
  const PATHS = [FILE, `/repo/${FILE}`, `/repo/.claude/worktrees/temper-pw-G1/../../../${FILE}`]
  test('an editing tool is refused at every stage of a run', () => {
    for (const stage of ['intent', 'plan', 'design', 'build', 'review', 'check', 'commit'] as const) {
      for (const p of PATHS) {
        for (const tool of ['Write', 'Edit']) expect(guarded(write(ctx(stage), p, tool)), `${stage} ${tool} ${p}`).toBe(true)
      }
    }
  })
  test('a shell write is refused: a redirect, tee, cp, mv, sed -i, truncate and rm', () => {
    for (const stage of ['build', 'check', 'commit'] as const) {
      for (const p of PATHS) {
        for (const cmd of [`echo '[]' > ${p}`, `printf x >> ${p}`, `: > ${p}`, `echo '[]' | tee ${p}`, `cp /tmp/none.json ${p}`,
          `mv /tmp/none.json ${p}`, `sed -i 's/environment/code/' ${p}`, `truncate -s 0 ${p}`, `rm -f ${p}`]) {
          expect(guarded(bash(ctx(stage), cmd)), `${stage}: ${cmd}`).toBe(true)
        }
      }
    }
  })
})

// 9.8.5 (WP21): "Go on anyway" at plan.command skips the check of one command the plan wrote, with a reason: only the
// person's answer runs `baseline skip`. The run of the plan's commands (`baseline plan`) is the CLI's and passes.
describe('a command the plan wrote: only the person skips its check', () => {
  const SKIP = `${CLI} baseline skip --cmd 'make check' --reason '{reason}'`
  const skip = (reason = 'the check needs the staging data'): string => `${CLI} baseline skip --cmd 'make check' --reason '${reason}'`
  test('baseline skip outside the person\'s answer is refused, at Plan and at Build', () => {
    for (const stage of ['plan', 'build'] as const) {
      expect(bash(ctx(stage), skip()), stage).toEqual({ deny: ONLY_USER })
    }
  })
  test('baseline skip passes as the call of the answer; baseline plan is the CLI\'s', () => {
    expect('allow' in bash(ctx('plan', { allowed: [SKIP] }), skip())).toBe(true)
    for (const cmd of [`${CLI} baseline plan`, `${CLI} baseline plan --cmd 'make check'`]) {
      expect('allow' in bash(ctx('plan'), cmd), cmd).toBe(true)
    }
  })
})

// 9.8.5 (WP24): a finding is repaired in its stage. `repair start` is the person's unless it is the CLI's own action;
// `repair commit`, `close` and `revert` pass only as calls of the action the view names (the fixer's after call, the
// recheck's, the CLI's revert). Inside a repair window (the view's guard.adhoc_kind `repair`) the write rule is
// Build's: a planned file or a test passes, any other path is scope drift; the small change window still allows any
// path.
describe('WP24: the repair in the stage', () => {
  const REPAIR = { adhocStage: 'review', ...({ adhocKind: 'repair' } as unknown as Over) }
  test('repair start typed by an agent or the session is refused, at Review and at Check', () => {
    for (const stage of ['review', 'check'] as const) {
      for (const cmd of [`${CLI} repair start --stage ${stage}`, `${CLI} repair start --stage ${stage} --again`]) {
        expect(isDeny(bash(ctx(stage), cmd)), cmd).toBe(true)
      }
    }
  })
  test('repair start passes as the CLI\'s own action, and the Repair again answer as the person\'s', () => {
    const own = `${CLI} repair start --stage review`
    expect('allow' in bash(ctx('review', { allowed: [own] }), own)).toBe(true)
    const again = `${CLI} repair start --stage review --again`
    expect('allow' in bash(ctx('review', { allowed: [again] }), again)).toBe(true)
    expect(isDeny(bash(ctx('review', { allowed: [own] }), again))).toBe(true)
  })
  test('repair commit, close and revert pass only as calls of the action the view names', () => {
    for (const word of ['commit', 'close', 'revert']) {
      const cmd = `${CLI} repair ${word}`
      expect(isDeny(bash(ctx('review'), cmd)), cmd).toBe(true)
      expect('allow' in bash(ctx('review', { allowed: [cmd] }), cmd), cmd).toBe(true)
    }
  })
  test('the fixer\'s test runs and the status are no decision: repair test and repair status pass', () => {
    for (const cmd of [`${CLI} repair test 1 --phase red -- sh unit/app.test.sh`, `${CLI} repair test 1 --phase green -- sh unit/app.test.sh`,
      `${CLI} repair status`]) {
      expect('allow' in bash(ctx('review', { facts: REPAIR }), cmd), cmd).toBe(true)
    }
  })
  test('inside a repair window a write outside the plan is refused with the scope drift text; a planned file and a test pass', () => {
    for (const tool of ['Write', 'Edit']) {
      const r = write(ctx('review', { facts: REPAIR }), 'src/billing.ts', tool)
      expect(isDeny(r) && r.drift, tool).toBe('src/billing.ts')
      for (const word of ['scope drift', 'src/billing.ts', 'add to plan', 'revert', 'allow once']) expect(isDeny(r) && r.deny, `${tool} ${word}`).toContain(word)
      expect('allow' in write(ctx('review', { facts: REPAIR }), 'src/app.ts', tool), tool).toBe(true)
      expect('allow' in write(ctx('review', { facts: REPAIR }), 'unit/app.test.ts', tool), tool).toBe(true)
    }
    const atCheck = { adhocStage: 'check', ...({ adhocKind: 'repair' } as unknown as Over) }
    expect(isDeny(write(ctx('check', { facts: atCheck }), 'src/billing.ts'))).toBe(true)
    expect('allow' in write(ctx('check', { facts: atCheck }), 'src/app.ts')).toBe(true)
  })
  test('adhoc close inside a repair window is refused: repair commit ends it; in a small change window it passes', () => {
    for (const stage of ['review', 'check'] as const) {
      const facts = { adhocStage: stage, ...({ adhocKind: 'repair' } as unknown as Over) }
      for (const cmd of [`${CLI} adhoc close`, `${CLI} adhoc close && ${CLI} next --json`]) {
        const r = bash(ctx(stage, { facts }), cmd)
        expect(isDeny(r) && r.deny.includes('repair commit'), `${stage}: ${cmd}`).toBe(true)
      }
      expect('allow' in bash(ctx(stage, { facts: { adhocStage: stage } }), `${CLI} adhoc close`), stage).toBe(true)
    }
  })
  test('inside a repair window the drift ask the scope drift text names passes the guard (the CLI takes it from the fixer)', () => {
    for (const stage of ['review', 'check'] as const) {
      const facts = { adhocStage: stage, ...({ adhocKind: 'repair' } as unknown as Over) }
      const r = write(ctx(stage, { facts }), 'src/billing.ts')
      const named = isDeny(r) ? /(\S*temper drift ask --path src\/billing\.ts) /.exec(r.deny)?.[1] : undefined
      expect(named, stage).toBeDefined()
      expect('allow' in bash(ctx(stage, { facts }), `${named} --why 'the fix needs it' --change 'one line'`), stage).toBe(true)
    }
  })
  test('the control: a small change window still allows any path', () => {
    for (const stage of ['review', 'check'] as const) {
      expect('allow' in write(ctx(stage, { facts: { adhocStage: stage } }), 'src/billing.ts'), stage).toBe(true)
      const small = { adhocStage: stage, ...({ adhocKind: 'small' } as unknown as Over) }
      expect('allow' in write(ctx(stage, { facts: small }), 'src/billing.ts'), stage).toBe(true)
    }
  })
})

// The same through the real hook: the mod reads guard.adhoc_kind of the view the CLI wrote (core/runview.ts,
// adapter.ts).
describe('WP24: the repair window is read from the view', () => {
  const START = { cwd: '/repo', surface: null, isInteractive: false } as const
  const files = (kind: string | null): Record<string, string> => {
    const f = runFiles({ nextStage: 'review', gates: { intent: 'PASS', plan: 'PASS', build: 'PASS', review: 'FAIL' } })
    const v = JSON.parse(deriveView(p => f[p]) ?? '{}') as { guard: Record<string, unknown> }
    v.guard.adhoc_stage = 'review'
    if (kind !== null) v.guard.adhoc_kind = kind
    return { ...f, '.temper/view.json': JSON.stringify(v) }
  }
  test('parseRunView reads adhoc_kind beside adhoc_stage', () => {
    const rv = parseRunView(files('repair')['.temper/view.json'] as string)
    expect(rv?.guard?.adhocStage).toBe('review')
    expect((rv?.guard as unknown as Record<string, unknown> | null | undefined)?.adhocKind).toBe('repair')
  })
  test('an agent\'s write outside the plan is scope drift in a repair window, and passes in a small change window', async ($, on) => {
    world(on, files('repair'), { projectRoot: '/repo' })
    await $.session.start(START)
    const outside = denyText(await $.tool.call({ tool: 'Write', file_path: 'src/billing.ts', content: 'x', agentId: 'agent' } as never))
    const planned = denyText(await $.tool.call({ tool: 'Write', file_path: 'src/app.ts', content: 'x', agentId: 'agent' } as never))
    expect([outside.includes('scope drift'), planned]).toEqual([true, ''])
  })
  test('the control: in a small change window the same write passes', async ($, on) => {
    world(on, files(null), { projectRoot: '/repo' })
    await $.session.start(START)
    expect(denyText(await $.tool.call({ tool: 'Write', file_path: 'src/billing.ts', content: 'x', agentId: 'agent' } as never))).toBe('')
  })
})

// 9.8.5 (WP25): `plan patch` stays the person's in every form (a command line, a file outside the approved set); `plan
// amend` is no person only call: its whole effect is bounded by the CLI whoever calls it (blocker B3 of
// docs/plans/one-go/evidence/red-safety.md), so an agent's call passes the guard and the CLI's own refusals hold it.
// The record of the amendments and patches is the CLI's to write.
describe('WP25: the plan amendment and the plan patch', () => {
  const PATCHES = [
    `${CLI} plan patch G1 --cmd 'make test-g1'`,
    `${CLI} plan patch task 2 --cmd 'make test-2'`,
    `${CLI} plan patch integration --cmd 'make all'`,
    `${CLI} plan patch task 2 --add-file src/billing.ts`,
  ]
  test('plan patch typed by an agent or the session stays refused, in every form, at Plan and at Build', () => {
    for (const stage of ['plan', 'build'] as const) {
      for (const cmd of PATCHES) expect(isDeny(bash(ctx(stage), cmd)), `${stage}: ${cmd}`).toBe(true)
    }
    // the answer for one patch is no answer for another
    const picked = `${CLI} plan patch task 2 --add-file src/billing.ts`
    expect(isDeny(bash(ctx('build', { allowed: [picked] }), `${CLI} plan patch task 2 --add-file src/other.ts`))).toBe(true)
    expect(isDeny(bash(ctx('build', { allowed: [picked] }), `${CLI} plan patch task 3 --add-file src/billing.ts`))).toBe(true)
  })
  test('plan patch task N --add-file F passes as the call of the person\'s answer, word for word', () => {
    const picked = `${CLI} plan patch task 2 --add-file src/billing.ts`
    expect('allow' in bash(ctx('build', { allowed: [picked] }), picked)).toBe(true)
  })
  test('plan amend typed by an agent passes the guard: the CLI\'s own refusals are what hold it', () => {
    for (const cmd of [`${CLI} plan amend task 2 --add-file src/app.ts`, `${CLI} plan amend task 2 --add-file src/app.ts --failure F3`]) {
      expect('allow' in bash(ctx('build'), cmd), cmd).toBe(true)
    }
  })
  test('during a run a write of .temper/evidence/amendments.json is refused: an editing tool, a redirect, an rm', () => {
    const f = '.temper/evidence/amendments.json'
    const guarded = (r: RuleResult): boolean => isDeny(r) && r.deny.startsWith('Temper: ')
    for (const stage of ['plan', 'build', 'review', 'check'] as const) {
      for (const tool of ['Write', 'Edit']) expect(guarded(write(ctx(stage), f, tool)), `${stage} ${tool}`).toBe(true)
      expect(guarded(write(ctx(stage), `/repo/${f}`)), `${stage} absolute`).toBe(true)
      for (const cmd of [`echo '[]' > ${f}`, `printf x >> ${f}`, `rm -f ${f}`]) {
        expect(guarded(bash(ctx(stage), cmd)), `${stage}: ${cmd}`).toBe(true)
      }
    }
  })
})
