// The guard's reader of a Bash command (core/shell.ts, ADR 0013): it finds the temper calls written out, a commit that
// switches the native hook off, a change of core.hooksPath, and the paths a command writes. It is not a shell parser:
// what it does not see is listed in known-limits.test.ts.
import { describe, expect, test } from 'claude-code/testing'

import { readShell, statements } from '../../hooks/temper-mod/core/shell'

describe('statements and words', () => {
  test('quotes keep their spaces and lose their quotes; operators end a statement', () => {
    expect(statements(`a 'b c' "d e"; f && g | h\ni`)).toEqual([['a', 'b c', 'd e'], ['f'], ['g'], ['h'], ['i']])
  })
  test('a word joined from quoted pieces is one word', () => {
    expect(statements(`scripts/temper ov''er"ri"de plan`)).toEqual([['scripts/temper', 'override', 'plan']])
  })
  test('a redirect is a word of its own, with its file descriptor dropped', () => {
    expect(statements('echo x 2>> log; ls &> out')).toEqual([['echo', 'x', '>>', 'log'], ['ls', '>', 'out']])
  })
  test('a substitution and a subshell end the statement around them', () => {
    expect(statements('echo $(scripts/temper gate plan) (ls)')).toEqual([['echo'], ['scripts/temper', 'gate', 'plan'], ['ls']])
  })
  test('${VAR} stays inside its word', () => {
    expect(statements('"${ROOT}/scripts/temper" gate plan')).toEqual([['${ROOT}/scripts/temper', 'gate', 'plan']])
  })
  test('the body of a here document is skipped, up to its end word', () => {
    expect(statements(`cat > a.md <<'EOF'\nscripts/temper override plan\nEOF\nls`)).toEqual([['cat', '>', 'a.md', '<<'], ['ls']])
    expect(statements(`cat <<-END\n\tx y\n\tEND\nls`)).toEqual([['cat', '<<'], ['ls']])
  })
})

describe('the temper calls', () => {
  test('each kind, by its words', () => {
    const r = readShell(
      [
        '/p/scripts/temper override plan --reason "a b"',
        'scripts/temper evidence accept --stage review --id 3 --reason x',
        'scripts/temper state advance plan_complete build',
        'scripts/temper state set next_stage build',
        'scripts/temper group reopen G1 --accept-foreign abc --reason x',
      ].join('\n'),
    )
    expect(r.calls).toEqual([
      { kind: 'override', stage: 'plan', invalid: false },
      { kind: 'accept', stage: 'review', id: '3', invalid: false },
      { kind: 'advance', stage: 'plan_complete', next: 'build' },
      { kind: 'back', stage: 'build' },
      { kind: 'override', stage: 'foreign-commit:G1', invalid: false },
    ])
  })
  test('a repeated flag makes the call invalid', () => {
    expect(readShell('scripts/temper evidence accept --stage review --id 1 --id 2').calls[0]?.invalid).toBe(true)
    expect(readShell('scripts/temper override plan --reason a --reason b').calls[0]?.invalid).toBe(true)
  })
  test('the state operations', () => {
    expect(readShell('scripts/temper state clear; scripts/temper state loop check build --reason x; scripts/temper state set complexity medium').stateOps).toEqual([
      { op: 'clear' },
      { op: 'loop', from: 'check', to: 'build' },
      { op: 'set', key: 'complexity', value: 'medium' },
    ])
  })
  test('a word that only ends in temper inside a longer word is no call', () => {
    expect(readShell('git commit -m "fix temper override"').calls).toEqual([])
    expect(readShell('ls .temper').calls).toEqual([])
  })
})

describe('the native hook', () => {
  test('--no-verify and -n on a commit, with -m taking its value', () => {
    for (const c of ['git commit --no-verify -m x', 'git commit -nm x', 'git commit -m x -n', 'git -C sub commit -n']) expect(readShell(c).noVerify, c).toBe(true)
    for (const c of ['git commit -m "-n"', 'git commit -am x', 'git commit -mn', 'git log -n 3']) expect(readShell(c).noVerify, c).toBe(false)
  })
  test('core.hooksPath set, unset or given to git; a read is no change', () => {
    for (const c of ['git config core.hooksPath /x', 'git config --unset core.hooksPath', 'git -c core.hooksPath=/dev/null commit -m x', 'GIT_CONFIG_KEY_0=core.hooksPath git commit -m x']) {
      expect(readShell(c).hooksPath, c).toBe(true)
    }
    for (const c of ['git config core.hooksPath', 'git config --get core.hooksPath', 'echo core.hooksPath']) expect(readShell(c).hooksPath, c).toBe(false)
  })
})

describe('the paths a command writes', () => {
  test('a redirect, and the files a writing program names', () => {
    expect(readShell('echo {} > a; ls >> b; rm -f c d; cp x y z; mv m n; tee t < i; sed -i s/a/b/ e; dd if=q of=r').writes).toEqual(['a', 'b', 'c', 'd', 'z', 'm', 'n', 't', 'e', 'r'])
  })
  test('a read writes nothing', () => {
    expect(readShell('cat .temper/gates.json; grep x < .temper/gates.json; jq . .temper/gates.json; ls -la .temper').writes).toEqual([])
    expect(readShell('cp .temper/gates.json /tmp/g; npm test 2>&1 | tail').writes).toEqual(['/tmp/g'])
  })
})
