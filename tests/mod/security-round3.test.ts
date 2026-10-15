// Tests beside review-exploits-3.test.ts: the legitimate flows that stay allowed, the forward
// guard on state advance, the commit forms the guard leaves to the native hook, and the deny texts.
import { describe, expect, test } from 'claude-code/testing'

import { check as evaluate } from './helpers'
import type { OldCtx as RuleContext } from './helpers'
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
    'scripts/temper evidence run --stage build --claim x --phase red -- bash scripts/selftest/test-temper.sh',
    'scripts/temper evidence list --stage review',
    'scripts/temper state get next_stage',
    // (complexity and base_sha are set in Plan and Build only, in the form the orchestrator uses: see hardening.test.ts)
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

describe('the calls only the person may cause, and the shell', () => {
  test('a plan file that quotes the call in a here document is still allowed', () => {
    const cmd = `cat > .temper/specs/pw/plan.md <<'EOF'\nThe person runs scripts/temper state advance plan_complete build.\nEOF`
    expect(denied(run('plan', cmd))).toBe(false)
  })

  test('a here document is text: a call quoted in it is not a call', () => {
    expect(denied(run('plan', `cat > notes.md <<'EOF'\nscripts/temper override plan --reason x\nEOF`))).toBe(false)
  })

  test('state init and state loop are refused while a run is active, state get is not', () => {
    expect(denied(run('build', 'scripts/temper state init x'))).toBe(true)
    expect(denied(run('build', 'scripts/temper state loop review build --reason x'))).toBe(true)
    expect(denied(run('build', 'scripts/temper state get next_stage'))).toBe(false)
  })

  test('the deny names where the user decides (the Temper gate question), and no typed command', () => {
    const r = run('plan', 'scripts/temper override plan --reason x')
    expect('deny' in r && r.deny).toContain('`Temper gate`')
    expect('deny' in r && r.deny).not.toContain('/temper:temper')
  })
})

describe('guarded names are compared without regard to case', () => {
  for (const f of ['.TEMPER/gates.json', '.temper/Gates.JSON', '.Temper/specs/pw/Events/1.json', '.temper/BUILD-STATE.json', '.temper/Overrides.json', '.temper/STATUS.json']) {
    test(`Write ${f}`, () => expect(evaluate(stateAt('build'), { ...ctx, planFiles: ['**'] }, { tool: 'Write', input: { file_path: f } })).toHaveProperty('deny'))
    test(`redirect to ${f}`, () => expect(denied(run('build', `echo {} > ${f}`))).toBe(true))
  }
})

describe('state advance and state set next_stage (#42)', () => {
  // ADR 0013: leaving Intent or Plan and a step back are the person's; every other advance follows the stage's own
  // verdict, and the CLI refuses one that does not (a stage it is not at, a next stage that is not the run's, a failed
  // check nobody skipped): scripts/selftest/temper-cases-8.sh holds those cases.
  const adv = (stage: string, next: string) => `scripts/temper state advance ${stage}_complete ${next}`
  test('intent and plan always need the person, even after a passed check', () => {
    expect(run('intent', adv('intent', 'plan'))).toHaveProperty('deny')
    expect(run('plan', adv('plan', 'build'))).toHaveProperty('deny')
  })
  test('a later advance is left to the CLI', () => {
    expect('deny' in run('build', adv('build', 'review'))).toBe(false)
    expect('deny' in run('review', adv('review', 'check'))).toBe(false)
  })
  test('state set next_stage: a step back needs the person; the stage the run is at changes nothing', () => {
    expect(run('build', 'scripts/temper state set next_stage plan')).toHaveProperty('deny')
    expect('deny' in run('build', 'scripts/temper state set next_stage build')).toBe(false)
  })
  test('every refusal ends with Next:', () => {
    const r = run('plan', adv('plan', 'build'))
    expect('deny' in r && r.deny).toMatch(/Next: /)
  })
})

describe('commit forms (#44)', () => {
  // ADR 0013: every commit goes to the native pre-commit hook, the commit gate, and the hook decides. The guard refuses
  // only what switches the hook off: --no-verify (or -n) and a change of core.hooksPath. A commit the hook does not check
  // (a merge, a cherry-pick, git plumbing) is a known limit (known-limits.test.ts).
  for (const c of ['git commit -m x', 'git commit -am x', 'git commit -m "-n"', 'git --no-pager commit -m x', 'git config core.hooksPath', 'git config --get core.hooksPath', 'git -c core.pager=cat log']) {
    test(`to the hook: ${c}`, () => expect(denied(run('build', c))).toBe(false))
  }
  for (const c of ['git commit --no-verify -m x', 'git commit -nm x', 'git commit -m x -n', 'git -c core.hooksPath=/dev/null commit -m x', 'git config core.hooksPath /tmp/h', 'git config --unset core.hooksPath', 'cd sub && git commit -n -m x']) {
    test(`refused: ${c}`, () => {
      const r = run('build', c)
      expect('deny' in r && r.deny).toMatch(/pre-commit hook|native commit gate/)
    })
  }
  test('saved for later or at Done, the hook still may not be switched off', () => {
    expect('deny' in evaluate(stateAt('build', [{ type: 'pause', origin: 'person', author: 'u' }]), ctx, { tool: 'Bash', input: { command: 'git commit --no-verify -m x' } })).toBe(true)
    expect('deny' in evaluate(stateAt('done'), ctx, { tool: 'Bash', input: { command: 'git commit --no-verify -m x' } })).toBe(true)
  })
  test('with no run, the hook is the person\'s', () => {
    expect('deny' in evaluate(null, ctx, { tool: 'Bash', input: { command: 'git commit --no-verify -m x' } })).toBe(false)
  })
})
