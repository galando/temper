import { describe, expect, test } from 'claude-code/testing'

import { classifyBash } from '../../hooks/temper-mod/core/bash'
import { ONLY_USER } from '../../hooks/temper-mod/core/rules'
import { check as evaluate, stateAt } from './helpers'
import type { OldCtx as RuleContext, OldDecision as HumanDecision } from './helpers'

// A reason inside a shell command, as the orchestrator writes it: single quoted, quotes escaped, newlines flattened.
const shellQuote = (text: string): string => `'${text.replace(/\r?\n/g, ' ').replace(/'/g, "'\\''")}'`
const overrideCommand = (stage: string, reason: string): string => `scripts/temper override ${stage} --reason ${shellQuote(reason)}`
const acceptCommand = (id: string, reason: string): string => `scripts/temper evidence accept --stage review --id ${id} --reason ${shellQuote(reason)}`

const ctx: RuleContext = { specDir: '.temper/specs/pw', planFiles: [] }
const blocked = (c: string) => classifyBash(c).protectedWrites.length > 0
const run = (state: ReturnType<typeof stateAt> | null, command: string, humanDecisions: readonly HumanDecision[] = []) =>
  evaluate(state, { ...ctx, humanDecisions }, { tool: 'Bash', input: { command } })
const denied = (r: ReturnType<typeof run>): string => ('deny' in r ? r.deny : '')

// The arming call at a stage, with the person's move at that step (the Autonomous answer is an `arm` move).
import { evaluate as evaluateNew } from '../../hooks/temper-mod/core/rules'
import { ctxOf } from './helpers'
function evaluateWithMove(stage: Parameters<typeof stateAt>[0], c: RuleContext, kind: 'arm' | 'approve') {
  const base = ctxOf(stateAt(stage), c)
  const move = { id: 'm', run: 'r', step: 3, stage: base.run?.stage ?? 'plan', ts: 1, kind, reason: '' } as const
  return evaluateNew({ ...base, move }, { tool: 'Bash', input: { command: 'scripts/temper state set run_mode autonomous' } })
}

describe('assignments resolve in order, to any depth', () => {
  const must = [
    'A=.temper B=$A/gates.json; echo {} > $B',
    'A=.temper; B=$A/specs; C=$B/pw; D=$C/events; echo {} > $D/1.json',
    'export A=.temper; export B=$A/gates.json; echo {} > $B',
    'declare -x A=.temper; declare B=$A/status.json; echo {} > $B',
    'local A=.temper; B=$A/overrides.json; echo {} > $B',
    'readonly A=.temper/gates.json; echo {} > $A',
    'typeset A=.temper/build-state.json; echo {} > $A',
    'A=.temper/gates.json env B=$A true; echo {} > $A',
    'A=.temper; B=${A}/gates.json; echo {} > ${B}',
    'A=.temper; cd $A; echo {} > gates.json',
    'A=.temper; B=gates; C=$B.json; echo {} > $A/$C',
    'F=.temper/gates.json; echo {} > $F; F=ok.md; echo {} > $F',
    'A=x; A=.temper/gates.json; echo {} > $A',
  ]
  for (const c of must) test(`blocks: ${c}`, () => expect(blocked(c)).toBe(true))

  test('a later assignment does not rescue an earlier write', () => {
    expect(blocked('F=.temper/gates.json; echo {} > $F; F=ok.md')).toBe(true)
  })
  test('an assignment that is overridden before the use is not a write to the old value', () => {
    expect(blocked('F=.temper/gates.json; F=ok.md; echo {} > $F')).toBe(false)
  })
})

describe('write constructs that cannot be checked fail closed when state is named', () => {
  const must = [
    'echo {} > $(echo .temper/gates.json)',
    'echo {} > `echo .temper/gates.json`',
    'tee >(cat > .temper/gates.json) < in',
    'echo {} > .temper/g*',
    'echo {} > .temper/gates.js?n',
    'echo {} > .temper/gates.json{,.bak}',
    'echo {} > .temper/{gates,status}.json',
    'echo {} > .temper/specs/*/events/1.json',
    'cp x $UNKNOWN; echo .temper',
    'dd if=in of=.temper/gates.json',
    'dd if=in of=$D; echo .temper',
    'truncate -s 0 .temper/overrides.json',
    'touch .temper/gates.json',
    'touch .temper/{a,gates.json}',
    'tee a.json .temper/gates.json < in',
    'tee a.json .temper/status.json b.json < in',
    'sed -i s/a/b/ x.txt .temper/gates.json',
    "sed -i '' 's/a/b/' .temper/gates.json",
    "sed -i -e 's/a/b/' .temper/status.json",
    "perl -i -pe 's/a/b/' .temper/overrides.json",
    'cp a b .temper/gates.json',
    'install -D x .temper/specs/pw/events/1-x-1.json',
    'ln -sf /dev/null .temper/overrides.json',
    "sh -c 'echo {} > .temper/gates.json'",
    'bash -c "echo {} > .temper/gates.json"',
    'eval "echo {} > .temper/gates.json"',
    "A=.temper; eval \"echo {} > $A/gates.json\"",
    'python3 -c "open(\'.temper/gates.json\',\'w\').write(\'{}\')"',
    "perl -e 'open F, \">.temper/gates.json\"'",
    "node -e \"require('fs').writeFileSync('.temper/status.json','{}')\"",
    "ruby -e 'File.write(\".temper/overrides.json\", \"[]\")'",
    'cat <<EOF > .temper/gates.json\n{}\nEOF',
    'cat > .temper/gates.json <<EOF\n{}\nEOF',
    'echo {} | tee .temper/gates.json',
    'echo {} > .temper/gates.json 2>&1',
    'echo {} &> .temper/gates.json',
    'echo {} >> .temper/status.json',
  ]
  for (const c of must) test(`blocks: ${c.replace(/\n/g, '\\n')}`, () => expect(blocked(c)).toBe(true))

  test('the deny says how to do it legitimately', () => {
    const r = run(stateAt('build'), 'echo {} > $(echo .temper/gates.json)')
    expect(denied(r)).toContain('Next: ')
    expect(denied(r)).toContain('scripts/temper')
  })
  test('a name that cannot be known is refused even when the command names nothing', () => {
    expect(blocked('echo {} > $G')).toBe(true)
    expect(blocked('echo {} > "$OUT"')).toBe(true)
  })
})

describe('whole folders are protected', () => {
  const must = [
    'rm -rf .temper',
    'rm -rf .temper/',
    'rm -rf .temper/specs',
    'rm -rf .temper/specs/pw',
    'rm -rf .temper/specs/pw/events',
    'rm -r -f ./.temper/../.temper',
    'mv .temper /tmp/x',
    'mv .temper/specs /tmp/x',
    'mv .temper/specs/pw /tmp/x',
    'mv /tmp/gates.json .temper/',
    'mv /tmp/x .temper/specs/pw/events/',
    'mv /tmp/a/* .temper/',
    'cp -r /tmp/forged/. .temper/',
    'cp /tmp/gates.json .temper/',
    'cp /tmp/x $F .temper/',
    'rsync -a --delete /tmp/empty/ .temper/',
    'rsync -a /tmp/forged/ .temper/specs/pw/',
    'find .temper -delete',
    'find .temper/specs -type f -delete',
    'find .temper -name "*.json" -exec rm {} +',
    'tar -xf evil.tar -C .temper',
    'unlink .temper/gates.json',
    'shred -u .temper/overrides.json',
    'rm .temper/*.json',
    'rm -rf .temper/s*',
  ]
  for (const c of must) test(`blocks: ${c}`, () => expect(blocked(c)).toBe(true))

  test('the folder deny names the legitimate way', () => {
    expect(denied(run(stateAt('build'), 'rm -rf .temper'))).toContain('scripts/temper state archive')
  })
})

describe('legitimate flows still pass', () => {
  const ok = [
    "cd /tmp/pr-demo; S=.temper/specs/pwreset\npython3 - <<'EOF'\np='.temper/specs/pwreset/intent.md'\nopen(p,'w').write('x')\nEOF\ncat > $S/tasks.md <<'EOF'\n# Tasks\nEOF",
    "S=.temper/specs/pw; cat > $S/plan.md <<'EOF'\n## Files to Modify\nEOF",
    'S=.temper/specs/pw; echo x >> $S/intent.md',
    'S=.temper/specs/pw; cp draft.md $S/tasks.md',
    'cp draft.md .temper/specs/pw/tasks.md',
    'cp draft.md .temper/specs/pw/',
    'mv draft.md .temper/specs/pw/plan.md',
    'scripts/temper gate intent --spec-path .temper/specs/pw',
    'scripts/temper evidence add --stage build --claim x --exit 0',
    'scripts/temper evidence run --stage build --claim t -- npm test',
    'scripts/temper state set complexity medium',
    'scripts/temper state set base_sha abc123',
    'scripts/temper state set regression_test test/x.test.js',
    'scripts/temper state get next_stage',
    'scripts/temper status --json',
    'cat .temper/gates.json',
    'cat .temper/gates.json | jq .',
    'grep -r PASS .temper/specs/pw/events',
    'ls -la .temper .temper/specs/*/events',
    'head -3 .temper/overrides.json; tail -3 .temper/status.json',
    'diff .temper/gates.json /tmp/old.json',
    'jq .verdict .temper/gates.json > /tmp/verdict.txt',
    'cp -r .temper/specs/pw /tmp/backup',
    'cp .temper/gates.json /tmp/gates.copy',
    'rsync -a .temper/ /tmp/backup/',
    'tar -cf /tmp/out.tar .temper',
    'tar -xf in.tar -C /tmp/out',
    'find .temper -name "*.json"',
    'find . -name "*.tmp" -delete',
    'rm -rf node_modules dist',
    'rm /tmp/scratch.txt',
    'npm test 2>&1 | tee /tmp/out.log',
    'git status && git diff -- .temper/status.json',
    'echo done > notes.txt',
    'S=.temper/specs/pw; wc -l $S/intent.md',
    "cd /private/tmp/pr-demo; f=.temper/specs/pwreset/intent.md; sed -i '' 's/^\\*\\*Status:\\*\\* draft/**Status:** accepted/' $f; head -9 $f",
    "sed -i 's/a*b/c/g' .temper/specs/pw/intent.md",
    "sed -i -e 's/a*b/c/' -e 's/x/y/' .temper/specs/pw/plan.md",
    "perl -i -pe 's/a*/b/' .temper/specs/pw/tasks.md",
    'for f in src/*.js; do echo $f > /tmp/list.txt; done',
  ]
  for (const c of ok) test(`allowed: ${c.split('\n')[0]}`, () => expect(blocked(c)).toBe(false))
})

describe('decision calls with repeated flags are refused', () => {
  const h = { id: 'e1', kind: 'accept' as const, phase: 'review', findingId: '1' }
  const acc = (flags: string) => `scripts/temper evidence accept ${flags}`
  const bad = [
    acc('--stage review --id 1 --id 2 --reason x'),
    acc('--id 1 --stage review --stage plan --reason x'),
    acc('--id 1 --stage review --reason x --reason y'),
    acc('--id=1 --id=2 --stage review --reason x'),
    acc('--id 1 --id=2 --stage review --reason x'),
    'scripts/temper override plan --reason a --reason b',
  ]
  for (const c of bad) {
    test(`refused: ${c}`, () => {
      const decisions: HumanDecision[] = [h, { id: 'e2', kind: 'override', phase: 'plan' }]
      expect('deny' in run(stateAt('review'), c, decisions)).toBe(true)
    })
  }

  test('a flag name inside the reason text is not a flag', () => {
    const r = run(stateAt('review'), acc('--stage review --id 1 --reason "see --id 2 and --stage plan"'), [h])
    expect('allow' in r).toBe(true)
  })

  test('the mod reads the id the CLI reads', () => {
    // Read like the CLI: a flag takes the next word whatever it is, so this accepts finding 5.
    const c = classifyBash(acc('--stage review --reason --id --id 5'))
    expect(c.calls[0]?.id).toBe('5')
    expect(run(stateAt('review'), acc('--stage review --reason --id --id 5'), [h])).toEqual({ deny: ONLY_USER })
  })
})

describe('state commands that move or end the run', () => {
  const back = (to: string, id = 'b1'): HumanDecision => ({ id, kind: 'back', phase: to })

  test('a jump forward with state set next_stage is refused', () => {
    const r = run(stateAt('plan'), 'scripts/temper state set next_stage build')
    expect('deny' in r).toBe(true)
    expect(denied(r)).toContain('Only the user')
  })

  // ADR 0012: the step back counts at its step; the CLI's move to Plan ends that step, so it cannot be used again.
  test('next_stage back to the stage the person chose is allowed on that choice only', () => {
    const cmd = 'scripts/temper state set next_stage plan'
    expect('allow' in run(stateAt('build'), cmd, [back('plan')])).toBe(true)
    expect('deny' in run(stateAt('build'), cmd, [])).toBe(true)
  })

  test('a back decision for one stage does not authorize another', () => {
    expect('deny' in run(stateAt('build'), 'scripts/temper state set next_stage review', [back('plan')])).toBe(true)
    expect('deny' in run(stateAt('build'), 'scripts/temper state set next_stage intent', [back('plan')])).toBe(true)
    // The stage the run is at: the CLI changes nothing, so it needs no choice.
    expect('allow' in run(stateAt('build'), 'scripts/temper state set next_stage build', [])).toBe(true)
  })

  test('the other keys that move the run are refused with a Next: reason', () => {
    for (const key of ['stage', 'branch', 'spec_path']) {
      const r = run(stateAt('build'), `scripts/temper state set ${key} anything`, [back('plan')])
      expect(denied(r)).toContain('Next: ')
    }
    expect('deny' in run(stateAt('build'), 'scripts/temper state set run_mode autonomous')).toBe(true)
    expect('allow' in run(stateAt('build'), 'scripts/temper state set run_mode interactive')).toBe(true)
  })

  test('the keys the flows need stay allowed', () => {
    for (const k of ['task 2', 'base_sha abc1234', 'regression_test t.js']) {
      expect('allow' in run(stateAt('build'), `scripts/temper state set ${k}`)).toBe(true)
    }
    // The complexity is set while the plan is open, not after it.
    expect('allow' in run(stateAt('plan'), 'scripts/temper state set complexity medium')).toBe(true)
    expect('deny' in run(stateAt('build'), 'scripts/temper state set complexity medium')).toBe(true)
  })

  test('state clear and archive only after the run, or with no run', () => {
    for (const sub of ['clear', 'archive']) {
      const cmd = `scripts/temper state ${sub}`
      for (const phase of ['intent', 'plan', 'design', 'build', 'review', 'check'] as const) {
        expect(denied(run(stateAt(phase), cmd))).toContain('Next: ')
      }
      expect('allow' in run(stateAt('done'), cmd)).toBe(true)
      expect('allow' in run(null, cmd)).toBe(true)
    }
  })

  test('with enforcement not tracking a run nothing here applies', () => {
    expect('allow' in run(null, 'scripts/temper state set next_stage build')).toBe(true)
  })
})

describe('arming autonomous mode', () => {
  const arm = 'scripts/temper state set run_mode autonomous'
  const withAutonomy = { ...ctx, autonomyEnabled: true }
  const armed: RuleContext = { ...withAutonomy, humanDecisions: [{ id: 'a', kind: 'override', phase: 'foreign' }] }
  const go = (state: ReturnType<typeof stateAt> | null, c: RuleContext) => evaluate(state, c, { tool: 'Bash', input: { command: arm } })
  // ADR 0012: only the person's "Autonomous" answer at the plan gate arms the run (an `arm` move at that step).
  const at = (stage: Parameters<typeof stateAt>[0], c: RuleContext, kind: 'arm' | 'approve') =>
    go(stateAt(stage), { ...c, humanDecisions: [] }) && evaluateWithMove(stage, c, kind)
  void armed
  void at

  test('with no Autonomous answer it is refused with a Next: reason, whatever the config says', () => {
    for (const phase of ['intent', 'plan', 'build', 'review', 'check'] as const) {
      const r = go(stateAt(phase), withAutonomy)
      expect('deny' in r && r.deny).toContain('at the plan gate')
      expect('deny' in r && r.deny).toContain('autonomy.enabled: true')
      expect('deny' in r && r.deny).toContain('Next: ')
    }
  })

  test('the Autonomous answer at the plan gate arms it when autonomy is enabled', () => {
    expect('allow' in evaluateWithMove('plan', withAutonomy, 'arm')).toBe(true)
  })

  test('a plain approval of the plan does not arm it', () => {
    expect('deny' in evaluateWithMove('plan', withAutonomy, 'approve')).toBe(true)
  })

  test('with autonomy off in the config it is refused even with the Autonomous answer', () => {
    expect('deny' in evaluateWithMove('plan', { ...ctx, autonomyEnabled: false }, 'arm')).toBe(true)
  })

  test('interactive is always allowed', () => {
    for (const phase of ['intent', 'plan', 'build'] as const) {
      expect('allow' in evaluate(stateAt(phase), ctx, { tool: 'Bash', input: { command: 'scripts/temper state set run_mode interactive' } })).toBe(true)
    }
  })

  test('with no active run nothing is guarded', () => {
    expect('allow' in go(null, ctx)).toBe(true)
  })
})

describe('override and accept agree in every stage', () => {
  const stages = ['intent', 'plan', 'design', 'build', 'review', 'check'] as const
  for (const stage of stages) {
    test(`override in ${stage}: the call is allowed on the person's skip at that stage`, () => {
      const cmd = overrideCommand(stage, 'ship it')
      expect('allow' in run(stateAt(stage), cmd, [{ id: 'o1', kind: 'override', phase: stage }])).toBe(true)
      expect(run(stateAt(stage), cmd, [])).toEqual({ deny: ONLY_USER })
    })
  }

  test('accept in review, for the finding the person accepted', () => {
    const cmd = acceptCommand('4', 'false positive')
    expect('allow' in run(stateAt('review'), cmd, [{ id: 'a1', kind: 'accept', phase: 'review', findingId: '4' }])).toBe(true)
    expect('deny' in run(stateAt('review'), cmd, [{ id: 'a2', kind: 'accept', phase: 'review', findingId: '5' }])).toBe(true)
    expect('deny' in run(stateAt('check'), cmd, [{ id: 'a3', kind: 'accept', phase: 'review', findingId: '4' }])).toBe(true)
  })
})

describe('reasons are quoted so nothing in them is read as shell', () => {
  const reasons = [
    "it's fine",
    'say "hi"',
    'cost $(touch /tmp/pwned)',
    'cost `touch /tmp/pwned`',
    "'; rm -rf / #",
    'line one\nline two',
    'a && b || c; d | e > f',
    '$PWD ${LANG} $((1+1))',
    "x' --id 9 '",
  ]
  for (const reason of reasons) {
    test(`override reason ${JSON.stringify(reason)}`, () => {
      const cmd = overrideCommand('plan', reason)
      expect(cmd.includes('\n')).toBe(false)
      const c = classifyBash(cmd)
      // Parsed as one override call, no extra statement, no substitution, no write.
      expect(c.calls).toHaveLength(1)
      expect(c.calls[0]).toMatchObject({ kind: 'override', stage: 'plan', invalid: false })
      expect(c.protectedWrites).toEqual([])
      expect(c.commits).toBe(false)
      expect('allow' in run(stateAt('plan'), cmd, [{ id: 'o1', kind: 'override', phase: 'plan' }])).toBe(true)
    })

    test(`accept reason ${JSON.stringify(reason)}`, () => {
      const cmd = acceptCommand('3', reason)
      const c = classifyBash(cmd)
      expect(c.calls).toHaveLength(1)
      expect(c.calls[0]).toMatchObject({ kind: 'accept', id: '3', stage: 'review', invalid: false })
      expect(c.protectedWrites).toEqual([])
    })
  }

  test('shellQuote escapes single quotes and flattens newlines', () => {
    expect(shellQuote("it's")).toBe("'it'\\''s'")
    expect(shellQuote('a\nb')).toBe("'a b'")
    expect(shellQuote('')).toBe("''")
  })
})

describe('commits and decisions are found through structure, not only through patterns', () => {
  const commits = [
    '(git commit -m x)',
    '{ git commit -m x; }',
    'if true; then git commit -m x; fi',
    'for i in 1; do git commit -m x; done',
    'x=$(git commit -m y)',
    'echo `git commit -m y`',
    'A=1 B=2 git commit -m x',
    'git -c a=b -C . commit -m x',
    'bash -c "cd x && git commit -m y"',
    "sh -c 'git commit -m y'",
    'eval git commit -m y',
    'true && git commit -m y',
    'false || git commit -m y',
    'git add . ; git commit -m y',
    'sleep 1 &\ngit commit -m y',
    'xargs -I{} git commit -m {}',
  ]
  for (const c of commits) test(`commit: ${c.replace(/\n/g, '\\n')}`, () => expect(classifyBash(c).commits).toBe(true))
  const not = ['echo "git commit"', "echo 'git commit -m x'", 'grep -r "git commit" docs', 'git log --grep=commit', 'cat <<EOF\ngit commit -m x\nEOF']
  for (const c of not) test(`not a commit: ${c.replace(/\n/g, '\\n')}`, () => expect(classifyBash(c).commits).toBe(false))
})

describe('the person typed it, the model did not: ordinary people flows', () => {
  test('a model decision attempt through the CLI is refused for every decision kind', () => {
    for (const cmd of [
      'scripts/temper override plan --reason x',
      'scripts/temper evidence accept --stage review --id 1 --reason x',
      'scripts/temper state advance intent_complete plan',
      'scripts/temper state advance plan_complete build',
      'scripts/temper state set next_stage intent',
    ]) {
      expect(denied(run(stateAt('plan'), cmd, []))).toMatch(/Only the user|not at intent/)
    }
  })
})
