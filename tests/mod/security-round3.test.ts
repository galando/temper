// Tests beside review-exploits-3.test.ts: the legitimate flows that stay allowed, the forward
// guard on state advance, the commit forms, and the deny texts.
import { describe, expect, test } from 'claude-code/testing'

import { classifyBash, gitCreatesCommit } from '../../hooks/temper-mod/core/bash'
import { evaluate, nextStage } from '../../hooks/temper-mod/core/rules'
import type { RuleContext } from '../../hooks/temper-mod/core/rules'
import { stateAt } from './helpers'

const ctx: RuleContext = { specDir: '.temper/specs/pw', planFiles: [] }
type P = Parameters<typeof stateAt>[0]
const PASS = { verdict: 'PASS' as const, ts: 999_999_999 }
const run = (phase: P, command: string, c: RuleContext = ctx, verdicts = {}) => evaluate(stateAt(phase, [], verdicts), c, { tool: 'Bash', input: { command } })
const denied = (r: ReturnType<typeof run>) => 'deny' in r

describe('plain calls stay allowed while a run is active', () => {
  const ok = [
    'cd dir && path/scripts/temper gate check',
    'cd /Users/x/dev/temper && scripts/temper gate check',
    'S=/p; $S/scripts/temper gate check',
    'scripts/temper gate $STAGE',
    'scripts/temper evidence add --stage build --claim "$(cat note.txt)" --label HEURISTIC',
    'scripts/temper evidence run --stage build --claim x --phase red -- bash scripts/tests/test-temper.sh',
    'scripts/temper evidence list --stage review',
    'scripts/temper state get next_stage',
    // (complexity and base_sha are set in Plan and Build only, in the form the orchestrator uses: tests/mod/hardening.test.ts)
    'scripts/temper state set task 2',
    'scripts/temper state set regression_test tests/a.test.ts',
    'scripts/temper report',
    'scripts/temper status --json',
    'scripts/temper config get autonomy.enabled',
    'scripts/temper model --all',
    // The Build agent records evidence and edits a file with a python program in one command. The program
    // does not name the script, so only the plain evidence call mentions it.
    `cd /private/tmp/pr-demo; T=/Users/x/plugin/scripts/temper; $T evidence add --stage build --claim "unit tests" --cmd "npm test" --exit 1 --phase red --label PROVEN 2>&1 | tail -3\npython3 - <<'EOF'\np='src/users.js'\ns=open(p).read()\ns=s.replace("const users = new Map()", "const users = new Map()\\nconst loop = 1")\nopen(p,'w').write(s)\nEOF`,
    `cd /tmp/pr-demo && /Users/x/plugin/scripts/temper evidence add --stage build --claim "tests" --exit 0 --phase green --label PROVEN | tail -2\npython3 - <<'PY'\nimport json\nd=json.load(open('.temper/specs/pw/build-context.json'))\nd['init']=True\njson.dump(d,open('.temper/specs/pw/build-context.json','w'))\nPY`,
    // A script found by a command substitution, then used for reads.
    'T=$(command -v temper 2>/dev/null | tail -1); echo $T; $T state get stage; $T state get next_stage; $T state get spec_path; $T gate plan',
    'T=$(ls -d "$PWD"/scripts/temper); $T state get next_stage',
    'T=$(command -v temper || echo scripts/temper); $T gate review; $T report; $T status --json; $T config get autonomy.enabled; $T model --all',
    'T=$(which temper | head -1); $T evidence add --stage build --claim "unit tests" --label PROVEN',
    'T=$(ls scripts/temper); $T state set task 2; $T state set regression_test t.js',
    // Readers that mention the script or a decision word.
    `sed -n '/override/p' scripts/temper`,
    `awk '/accept/ {print NR": "$0}' scripts/temper`,
    'nl scripts/temper | grep advance',
    'cat scripts/temper | head -20',
    'head -50 scripts/temper',
    'tail -n 30 scripts/temper',
    'less scripts/temper',
    'wc -l scripts/temper',
    'diff scripts/temper /tmp/other',
    'grep -n "state advance" scripts/temper',
    'rg "evidence accept" scripts/',
    'git log --grep="state advance" --oneline',
    'python3 -m pytest tests -k "temper and accept"',
    'ls -la /Users/x/dev/temper && echo override',
  ]
  for (const cmd of ok) test(cmd, () => expect(denied(run('review', cmd, ctx, { review: PASS }))).toBe(false))
})

describe('the reader exemption does not cover a program that runs something', () => {
  const bad = [
    `awk 'BEGIN{system("scripts/temper override plan --reason x")}'`,
    `sed 's/x/scripts\\/temper override plan --reason x/e' f`,
    `awk 'BEGIN{print "scripts/temper override plan --reason x" | "sh"}'`,
  ]
  for (const cmd of bad) test(cmd, () => expect(denied(run('plan', cmd))).toBe(true))
})

describe('shell indirection around the script fails closed', () => {
  const bad = [
    // A python program that names the script and a decision word is refused, plain call or not.
    `python3 - <<'PY'\nimport subprocess\nsubprocess.run(['scripts/temper','override','plan','--reason','x'])\nPY`,
    `scripts/temper gate plan\npython3 - <<'PY'\nimport os\nos.system('scripts/temper state clear')\nPY`,
    // A script found by a substitution is still refused for anything that is not a plain read.
    'T=$(ls scripts/temper); $T state advance plan_complete build',
    'T=$(ls scripts/temper); $T override plan --reason x',
    'T=$(ls scripts/temper); $T state set next_stage build',
    'T=$(ls scripts/temper); $T evidence accept --stage review --id 1 --reason x',
    'T=$(ls scripts/temper); $T state clear',
    'T=$(ls scripts/temper); $T $(echo override) plan --reason x',
    `scripts/temper $'over\\x72ide' plan --reason x`,
    'scripts/temper ${V:-override} plan --reason x',
    'scripts/temper "$(printf override)" plan --reason x',
    'scripts/temper $(echo state) advance plan_complete build',
    'scripts/temper state "$X" plan_complete build',
    'scripts/temper state set "$K" build',
    'scripts/TEMPER override plan --reason x',
    `bash <(cat scripts/temper) override plan --reason x`,
    `cat scripts/temper > /tmp/t`,
    `cat scripts/temper | tee /tmp/t`,
    'cp scripts/temper /tmp/t',
    `printf '%s\\n' 'scripts/temper state clear' > /tmp/x.sh; bash /tmp/x.sh`,
    `echo 'scripts/temper state init x' > /tmp/y; sh /tmp/y`,
    `cat > run.sh <<'EOF'\nscripts/temper evidence accept --stage review --id 1 --reason x\nEOF`,
    `env -S 'scripts/temper state advance plan_complete build'`,
    `find . -exec scripts/temper override plan --reason x {} +`,
    `git -c alias.x='!scripts/temper override plan --reason x' x`,
    `fish -c 'scripts/temper override plan --reason x'`,
  ]
  for (const cmd of bad) {
    test(cmd.replace(/\n/g, '\\n'), () => {
      const r = run('plan', cmd)
      expect(denied(r)).toBe(true)
      if ('deny' in r) expect(r.deny).toMatch(/Next: /)
    })
  }

  test('the deny names the buttons and the subcommands', () => {
    const r = run('plan', `scripts/temper $'over\\x72ide' plan --reason x`)
    expect('deny' in r && r.deny).toContain('/temper:temper')
    expect('deny' in r && r.deny).toContain('buttons')
  })

  // The refusal gives the true reason: a subcommand that cannot be read is not called a decision word.
  const reason = (cmd: string): string => {
    const r = run('plan', cmd)
    return 'deny' in r ? r.deny : ''
  }
  test('a subcommand picked by a variable is refused for that reason, not for a decision word', () => {
    for (const cmd of [
      'P=/opt/temper; for c in report status bands; do echo "== $c"; $P/scripts/temper $c 2>&1 | head -20; done',
      'scripts/temper $c',
      'scripts/temper state "$X" plan_complete build',
      `scripts/temper $'over\\x72ide' plan --reason x`,
      'T=$(ls scripts/temper); $T $c',
    ]) {
      expect(classifyBash(cmd).opaqueWhy).toBe('dynamic')
      const d = reason(cmd)
      expect(d).toContain('in a form Temper cannot read: a variable, a substitution or an escaped string')
      expect(d).not.toContain('decision word')
      expect(d).toContain('Next: run each scripts/temper call with its words written out')
    }
  })
  test('a hidden launch with no decision word is refused for what it hides', () => {
    const cmd = `python3 -c "import subprocess; subprocess.run(['scripts/temper', 'gate'])" $(cat f)`
    expect(classifyBash(cmd).opaqueWhy).toBe('hidden')
    const d = reason(cmd)
    expect(d).toContain('hides part of what it runs')
    expect(d).not.toContain('decision word')
  })
  test('a launch Temper cannot read that holds a decision word keeps the decision word text', () => {
    for (const cmd of ['T=$(ls scripts/temper); $T override plan --reason x', `echo 'scripts/temper override plan --reason x' | bash /dev/./stdin`, 'tempe[r] override plan --reason x']) {
      expect(classifyBash(cmd).opaqueWhy).toBe('decision')
      expect(reason(cmd)).toContain('it holds a decision word')
    }
  })
  test('a command that is not opaque has no reason', () => {
    expect(classifyBash('scripts/temper gate plan').opaqueWhy).toBeNull()
  })

  test('a plan file that quotes the call in a heredoc is still allowed', () => {
    const cmd = `cat > .temper/specs/pw/plan.md <<'EOF'\nThe person runs scripts/temper state advance plan_complete build.\nEOF`
    expect(denied(run('plan', cmd))).toBe(false)
  })

  test('state init and state loop are refused while a run is active, state get is not', () => {
    expect(denied(run('build', 'scripts/temper state init x'))).toBe(true)
    expect(denied(run('build', 'scripts/temper state loop review build --reason x'))).toBe(true)
    expect(denied(run('build', 'scripts/temper state get next_stage'))).toBe(false)
  })
})

describe('guarded names are compared without regard to case', () => {
  for (const f of ['.TEMPER/gates.json', '.temper/Gates.JSON', '.Temper/specs/pw/Events/1.json', '.temper/BUILD-STATE.json', '.temper/Overrides.json', '.temper/STATUS.json']) {
    test(`Write ${f}`, () => expect(evaluate(stateAt('build'), { ...ctx, planFiles: ['**'] }, { tool: 'Write', input: { file_path: f } })).toHaveProperty('deny'))
    test(`redirect to ${f}`, () => expect(denied(run('build', `echo {} > ${f}`))).toBe(true))
  }
})

describe('links to Temper state are refused', () => {
  for (const cmd of ['ln -s .temper /tmp/t', 'ln .temper/gates.json /tmp/g', 'ln -s .temper/specs /tmp/s', 'ln -s ../.TEMPER t', 'ln -sf $PWD/.temper/overrides.json o']) {
    test(cmd, () => expect(denied(run('build', cmd))).toBe(true))
  }
  test('an ordinary link is not', () => expect(denied(run('build', 'ln -s src/a.ts /tmp/a'))).toBe(false))
})

describe('state advance and state set next_stage need a decision or a passed check (#42)', () => {
  test('nextStage follows STAGE_SEQ_TEMPER, with design only for medium and complex', () => {
    expect(nextStage('intent', null)).toBe('plan')
    expect(nextStage('plan', 'simple')).toBe('build')
    expect(nextStage('plan', null)).toBe('build')
    expect(nextStage('plan', 'medium')).toBe('design')
    expect(nextStage('plan', 'complex')).toBe('design')
    expect(nextStage('design', 'complex')).toBe('build')
    expect(nextStage('build', null)).toBe('review')
    expect(nextStage('review', null)).toBe('check')
    expect(nextStage('check', null)).toBe('commit')
    expect(nextStage('started', null)).toBe(null)
  })

  const adv = (stage: string, next: string) => `scripts/temper state advance ${stage}_complete ${next}`
  test('the five reviewer examples are refused', () => {
    for (const c of [adv('review', 'build'), 'scripts/temper state advance started build', adv('design', 'build'), adv('check', 'commit'), adv('build', 'commit')]) {
      expect(run('plan', c)).toHaveProperty('deny')
    }
  })

  test('the legitimate sequence after each check passed', () => {
    expect('deny' in run('build', adv('build', 'review'), ctx, { build: PASS })).toBe(false)
    expect('deny' in run('review', adv('review', 'check'), ctx, { review: PASS })).toBe(false)
    expect('deny' in run('check', adv('check', 'commit'), ctx, { check: PASS })).toBe(false)
  })

  test('without the verdict the same calls are refused, and a failing check is not a pass', () => {
    expect(run('build', adv('build', 'review'))).toHaveProperty('deny')
    expect(run('build', adv('build', 'review'), ctx, { build: { verdict: 'FAIL', ts: 999_999_999 } })).toHaveProperty('deny')
    expect(run('check', adv('check', 'commit'), ctx, { check: { verdict: 'FAIL', ts: 999_999_999 } })).toHaveProperty('deny')
  })

  test('a passed check does not allow a jump or the wrong next stage', () => {
    expect(run('build', adv('build', 'check'), ctx, { build: PASS })).toHaveProperty('deny')
    expect(run('build', adv('build', 'commit'), ctx, { build: PASS })).toHaveProperty('deny')
    expect(run('build', adv('review', 'check'), ctx, { build: PASS, review: PASS })).toHaveProperty('deny')
  })

  test('intent and plan always need the person, even after a passed check', () => {
    expect(run('intent', adv('intent', 'plan'), ctx, { intent: PASS })).toHaveProperty('deny')
    expect(run('plan', adv('plan', 'build'), ctx, { plan: PASS })).toHaveProperty('deny')
  })

  test('a person decision pays for its own move and no other', () => {
    const c: RuleContext = { ...ctx, humanDecisions: [{ id: 'e', kind: 'advance', phase: 'build' }] }
    expect('allow' in run('review', adv('build', 'review'), c)).toBe(true)
    expect(run('review', adv('review', 'check'), c)).toHaveProperty('deny')
    expect(run('review', adv('build', 'commit'), c)).toHaveProperty('deny')
  })

  test('design follows the plan only for a medium or complex run', () => {
    const state = stateAt('build', [], { plan: PASS })
    const call = { tool: 'Bash', input: { command: adv('design', 'build') } }
    expect('allow' in evaluate(state, { ...ctx, complexity: 'complex' }, call)).toBe(true)
    expect(evaluate(state, { ...ctx, complexity: 'simple' }, call)).toHaveProperty('deny')
    expect(evaluate(state, ctx, call)).toHaveProperty('deny')
  })

  test('state set next_stage: the exact next stage after a passed check, else the person', () => {
    expect('deny' in run('build', 'scripts/temper state set next_stage review', ctx, { build: PASS })).toBe(false)
    expect(run('build', 'scripts/temper state set next_stage check', ctx, { build: PASS })).toHaveProperty('deny')
    expect(run('build', 'scripts/temper state set next_stage review')).toHaveProperty('deny')
    expect('allow' in run('build', 'scripts/temper state set next_stage plan', { ...ctx, humanDecisions: [{ id: 'e', kind: 'back', phase: 'plan' }] })).toBe(true)
  })

  test('every refusal ends with Next:', () => {
    const r = run('plan', adv('review', 'build'))
    expect('deny' in r && r.deny).toMatch(/Next: /)
  })
})

describe('commit forms (#44)', () => {
  const commits = [
    'git commit -m x',
    'git cherry-pick abc',
    'git merge other',
    'git merge --no-ff other',
    'git revert HEAD',
    'git am patch.mbox',
    'git commit-tree HEAD^{tree} -m x',
    'git rebase --continue',
    'git pull',
    'git pull origin main',
    'git -c alias.c=commit c -m x',
    `git -c alias.x='!echo hi' x`,
    `ksh -c 'git commit -m x'`,
    `fish -c 'git cherry-pick abc'`,
    `find . -maxdepth 0 -exec git commit -m x \\;`,
    'git --no-pager commit -m x',
  ]
  for (const c of commits) test(`refused: ${c}`, () => {
    expect(classifyBash(c).commits).toBe(true)
    const r = run('build', c)
    expect('deny' in r && r.deny).toMatch(/commit blocked/)
  })
  const reads = [
    'git status',
    'git log --grep="git commit"',
    'git merge --abort',
    'git merge --quit',
    'git revert --abort',
    'git revert --quit',
    'git revert --skip',
    'git am --abort',
    'git am --skip',
    'git rebase --abort',
    'git rebase --skip',
    'git pull --ff-only',
    'git pull --rebase',
    'git push origin main',
    'git diff HEAD',
    'git show HEAD',
    'git branch -a',
    'git -c core.pager=cat log',
    'echo "git commit later"',
  ]
  for (const c of reads) test(`allowed: ${c}`, () => expect(classifyBash(c).commits).toBe(false))
  test('gitCreatesCommit reads text', () => {
    expect(gitCreatesCommit('x && git cherry-pick a')).toBe(true)
    expect(gitCreatesCommit('git push')).toBe(false)
  })
  test('the deny says the pre-commit hook is the backstop', () => {
    const r = run('build', 'git merge other')
    expect('deny' in r && r.deny).toContain('pre-commit')
  })
  test('while paused or at Done the commit forms are not blocked by the guard', () => {
    expect('deny' in evaluate(stateAt('build', [{ type: 'pause', origin: 'person', author: 'u' }]), ctx, { tool: 'Bash', input: { command: 'git merge other' } })).toBe(false)
  })
})
