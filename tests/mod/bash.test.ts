import { describe, expect, test } from 'claude-code/testing'

import { classifyBash, protectedKind } from '../../hooks/temper-mod/core/bash'

describe('git commit detection', () => {
  const commits = [
    'git commit -m "feat: x"',
    'git add -A && git commit -m wip',
    'git add . ; git commit',
    'npm test || git commit -m x',
    'git -c user.name=x commit -m y',
    'git -C ../other commit -m y',
    'git --no-pager commit --amend',
    'FOO=1 git commit -m x',
    'sudo git commit -m x',
    '(cd app && git commit -m x)',
    'echo hi | git commit -F -',
    'bash -c "git commit -m x"',
    'sh -c \'git commit -m x\'',
    'eval "git commit -m x"',
    'git add x\ngit commit -m y',
    'x=$(git commit -m y)',
  ]
  for (const c of commits) {
    test(`refuses: ${c.replace(/\n/g, '\\n')}`, () => {
      expect(classifyBash(c).commits).toBe(true)
    })
  }

  const harmless = [
    'git status',
    'git log --grep="git commit"',
    'echo "run git commit later"',
    'git commit-tree HEAD^{tree}',
    'git diff --stat',
    'gitk commit',
    'grep -r "git commit" docs',
    'git config alias.ci commit',
  ]
  for (const c of harmless) {
    test(`passes: ${c}`, () => {
      expect(classifyBash(c).commits).toBe(false)
    })
  }
})

describe('decision CLI calls', () => {
  test('override, evidence accept and state advance are recognised', () => {
    expect(classifyBash('temper override plan --reason ok').decisions).toEqual(['override'])
    expect(classifyBash('scripts/temper evidence accept --stage review --id 1 --reason x').decisions).toEqual(['accept'])
    expect(classifyBash('bash "$CLAUDE_PLUGIN_ROOT/scripts/temper" state advance plan').decisions).toEqual(['advance'])
    expect(classifyBash('cd x && $CLAUDE_PLUGIN_ROOT/scripts/temper override build --reason r').decisions).toEqual(['override'])
  })

  test('the CLI commands that only read or compute verdicts are not decisions', () => {
    for (const c of ['temper gate build', 'temper evidence add --stage build --claim x', 'temper evidence list', 'temper status --json', 'temper state loop check fix']) {
      expect(classifyBash(c).decisions).toEqual([])
    }
  })
})

describe('protected state paths', () => {
  test('protectedKind names the guarded file', () => {
    expect(protectedKind('.temper/specs/pw/events/1-x-1.json')).toBe('events')
    expect(protectedKind('/repo/.temper/specs/pw/events/')).toBe('events')
    expect(protectedKind('.temper/gates.json')).toBe('gates')
    expect(protectedKind('.temper/status.json')).toBe('status')
    expect(protectedKind('.temper/overrides.json')).toBe('overrides')
    expect(protectedKind('.temper/specs/pw/plan.md')).toBe(null)
    expect(protectedKind('src/events/gates.json')).toBe(null)
  })

  test('writes that name a protected path are flagged', () => {
    const writes = [
      'echo {} > .temper/gates.json',
      'echo x >> .temper/specs/pw/events/1-x-1.json',
      'tee .temper/status.json < in.json',
      'cp /tmp/a.json .temper/specs/pw/events/9-x-9.json',
      'rm -rf .temper/specs/pw/events',
      'sed -i s/FAIL/PASS/ .temper/gates.json',
      'python3 -c "open(\'.temper/overrides.json\',\'w\').write(\'{}\')"',
      'git add -A && echo x > .temper/gates.json',
      'mv a .temper/specs/pw/events/b.json',
    ]
    for (const c of writes) expect(classifyBash(c).protectedWrites.length).toBeGreaterThan(0)
  })

  test('reads of protected paths and writes elsewhere are not flagged', () => {
    const fine = [
      'cat .temper/gates.json',
      'ls .temper/specs/pw/events',
      'jq .verdict .temper/gates.json',
      'grep PASS .temper/status.json | head',
      'echo x > notes.txt',
      'temper gate check',
      'git status',
      'cat .temper/gates.json > /tmp/copy.json',
    ]
    for (const c of fine) expect(classifyBash(c).protectedWrites).toEqual([])
  })
})
