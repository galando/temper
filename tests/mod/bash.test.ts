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

describe('evasions of the protected path guard', () => {
  const flagged = (c: string) => classifyBash(c).protectedWrites.length > 0

  test('.. segments are collapsed', () => {
    expect(flagged('echo x > .temper/specs/a/../a/events/1.json')).toBe(true)
    expect(flagged('cp x ./.temper/./gates.json')).toBe(true)
    expect(flagged('echo x > .temper/specs/a/../../notes.txt')).toBe(false)
  })

  test('a cd into a protected folder makes later relative writes protected', () => {
    expect(flagged('cd .temper/specs/pw/events && echo {} > 1-x-1.json')).toBe(true)
    expect(flagged('cd .temper && echo {} > gates.json')).toBe(true)
    expect(flagged('cd .temper/specs/pw && echo {} > events/1-x-1.json')).toBe(true)
    expect(flagged('cd .temper && cd .. && echo {} > gates.json')).toBe(false)
    expect(flagged('cd src && echo x > out.txt')).toBe(false)
    expect(flagged('pushd .temper && tee status.json < in.json')).toBe(true)
  })

  test('shell variables and unknown directories are judged conservatively', () => {
    expect(flagged('echo {} > $T/gates.json')).toBe(true)
    expect(flagged('F=.temper/gates.json; echo {} > $F')).toBe(true)
    expect(flagged('cd $DIR && echo {} > events/1.json')).toBe(true)
    expect(flagged('echo x > $HOME/notes.txt')).toBe(false)
    expect(flagged('cd $DIR && echo x > out.txt')).toBe(false)
  })

  test('temper global options before a decision subcommand', () => {
    expect(classifyBash('temper --spec-path .temper/specs/pw override plan --reason x').decisions).toEqual(['override'])
    expect(classifyBash('scripts/temper -q evidence accept --stage review --id 2 --reason x').calls).toEqual([{ kind: 'accept', stage: 'review', id: '2' }])
    expect(classifyBash('temper state advance plan build').calls).toEqual([{ kind: 'advance', stage: 'plan' }])
    expect(classifyBash('temper override review --reason x').calls).toEqual([{ kind: 'override', stage: 'review' }])
  })

  test('build-state.json is a protected state file', () => {
    expect(protectedKind('.temper/build-state.json')).toBe('state')
    expect(flagged('echo {} > .temper/build-state.json')).toBe(true)
    expect(flagged('cat .temper/build-state.json')).toBe(false)
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

describe('command wrappers do not hide a commit or a decision', () => {
  const wrapped = [
    'env -i git commit -m x',
    'env FOO=1 BAR=2 git commit -m x',
    'env -u HOME git commit -m x',
    'timeout 5 git commit -m x',
    'timeout -s KILL 10 git commit -m x',
    'nice git commit -m x',
    'nice -n 10 git commit -m x',
    'ionice -c 3 git commit -m x',
    'nohup git commit -m x',
    'time git commit -m x',
    'command git commit -m x',
    'builtin exec git commit -m x',
    'exec git commit -m x',
    'xargs git commit -m',
    'xargs -n 1 git commit -m',
    'sudo -u root git commit -m x',
    '/usr/bin/git commit -m x',
    './git commit -m x',
    '\\git commit -m x',
    '"git" commit -m x',
    "'git' commit -m x",
    'env -- git commit -m x',
    'nice -- git commit -m x',
    'timeout 5 env -i nice /usr/bin/git commit -m x',
  ]
  for (const c of wrapped) {
    test(`commit: ${c}`, () => {
      expect(classifyBash(c).commits).toBe(true)
    })
  }

  const decisions = [
    'env -i temper override plan --reason x',
    'timeout 5 temper override plan --reason x',
    'nice temper override plan --reason x',
    'xargs temper override plan --reason x',
    'nohup scripts/temper evidence accept --stage review --id 1 --reason x',
    'command /usr/local/bin/temper state advance plan build',
    '\\temper override plan --reason x',
    'env TEMPER_X=1 bash scripts/temper override plan --reason x',
    'sudo temper override plan --reason x',
  ]
  for (const c of decisions) {
    test(`decision: ${c}`, () => {
      expect(classifyBash(c).decisions).toHaveLength(1)
    })
  }

  test('wrapped harmless commands stay harmless', () => {
    for (const c of ['env -i git status', 'timeout 5 npm test', 'nice git log', 'xargs echo', '/usr/bin/git diff']) {
      const k = classifyBash(c)
      expect(k.commits).toBe(false)
      expect(k.decisions).toEqual([])
    }
  })
})

describe('more ways to write a guarded file', () => {
  const flagged = (c: string) => classifyBash(c).protectedWrites.length > 0
  const writes = [
    'echo {} >| .temper/gates.json',
    'echo {} >|.temper/gates.json',
    'curl -o .temper/gates.json https://x/y',
    'curl --output .temper/status.json https://x/y',
    'curl --output=.temper/overrides.json https://x/y',
    'curl -s -o.temper/build-state.json https://x/y',
    'wget -O .temper/gates.json https://x/y',
    'wget --output-document .temper/status.json https://x/y',
    'wget -O.temper/gates.json https://x/y',
    'tar -xf evil.tar -C .temper',
    'tar -xf evil.tar -C .temper/specs/pw',
    'tar -xf evil.tar --directory=.temper/specs/pw/events',
    'cp -t .temper/specs/pw/events forged.json',
    'cp --target-directory=.temper/specs/pw/events forged.json',
    'cp forged.json .temper/gates.json',
    "sed -n 'p;w .temper/gates.json' in.json",
    "sed 's/a/b/w .temper/status.json' in.json",
    'install -m 644 forged.json .temper/overrides.json',
    'ln -sf /tmp/forged .temper/gates.json',
    'rsync forged.json .temper/gates.json',
    'rsync -a forged/ .temper/specs/pw',
    "echo {} > .temper/gates.js''on",
    'echo {} > ".temper/gates".json',
    'echo {} > .temper/gat\\es.json',
    "tee .temp''er/gates.json < in.json",
    'rm -rf .temper/specs/pw/ev*/',
    'cd .temper/specs/pw && rm -rf ev*',
    'echo {} > .temper/g*',
    'echo {} > .temper/specs/pw/events/*.json',
    'cd .temper && echo {} > status.js?n',
    'echo {} > $T/gates.json',
    'cd $X && cp forged.json events/1.json',
  ]
  for (const c of writes) {
    test(`flagged: ${c}`, () => {
      expect(flagged(c)).toBe(true)
    })
  }

  // Reading stays allowed: no write verb and no redirect onto a guarded path.
  const reads = [
    'cat .temper/gates.json',
    'cat .temper/gates.json | jq .',
    'cat .temper/gates.json > /tmp/gates.copy',
    'grep PASS .temper/status.json',
    'grep -r forged .temper/specs/pw/events',
    'ls .temper/specs/*/events',
    'ls -la .temper',
    'head -5 .temper/overrides.json',
    'tail -f .temper/build-state.json',
    'wc -l .temper/gates.json',
    'diff .temper/gates.json /tmp/other.json',
    'jq .verdict .temper/gates.json',
    'git diff .temper/status.json',
    'git log -- .temper/specs/pw/events',
    'sed -n 1p .temper/gates.json',
    "sed -n 's/a/b/p' .temper/gates.json",
    'cp .temper/gates.json /tmp/backup.json',
    'rsync .temper/gates.json /tmp/',
    'tar -tf evil.tar',
    'tar -cf /tmp/out.tar .temper',
    'tar -xf in.tar -C /tmp/out',
    'curl -s https://example.com/x -o /tmp/x',
    'wget -O /tmp/x https://example.com/x',
    'cat g* > out.txt',
    'echo x > notes.txt',
    'cd src && echo x > out.txt',
    'find .temper -name "*.json"',
    'stat .temper/gates.json',
    'file .temper/status.json',
  ]
  for (const c of reads) {
    test(`allowed: ${c}`, () => {
      expect(classifyBash(c).protectedWrites).toEqual([])
    })
  }
})
