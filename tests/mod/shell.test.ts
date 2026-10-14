// The guard's reader of a Bash command (core/shell.ts, ADR 0013): it finds the temper calls written out, a commit that
// switches the native hook off, a change of core.hooksPath, and the paths a command writes, and it compares a call with
// one the CLI wrote. It is not a shell parser: what it does not see is listed in known-limits.test.ts.
import { describe, expect, test } from 'claude-code/testing'

import { callWords, readShell, sameCall, statements } from '../../hooks/temper-mod/core/shell'

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
  test('a substitution stays in its word, its commands are statements of their own; a subshell ends the statement', () => {
    expect(statements('echo $(scripts/temper gate plan) (ls)')).toEqual([['echo', '$(scripts/temper gate plan)'], ['ls'], ['scripts/temper', 'gate', 'plan']])
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
  test('each call written out, as its words after the script', () => {
    const r = readShell(['/p/scripts/temper override plan --reason "a b"', 'cd x && scripts/temper evidence accept --stage review --id 3', '"${ROOT}/scripts/temper" state advance plan_complete build'].join('\n'))
    expect(r.calls).toEqual([
      ['override', 'plan', '--reason', 'a b'],
      ['evidence', 'accept', '--stage', 'review', '--id', '3'],
      ['state', 'advance', 'plan_complete', 'build'],
    ])
  })
  test('a word that only ends in temper inside a longer word is no call', () => {
    expect(readShell('git commit -m "fix temper override"').calls).toEqual([])
    expect(readShell('ls .temper').calls).toEqual([])
  })
})

describe('sameCall: the call the CLI wrote, word for word', () => {
  const written = '/plugin/scripts/temper override build --reason "{reason}"'
  test('the same words, any path to the script, a reason in the placeholder', () => {
    expect(sameCall(written, ['override', 'build', '--reason', 'the flaky test'])).toBe(true)
    expect(sameCall(written, callWords(['--spec-path', '.temper/specs/pw', 'override', 'build', '--reason', 'x']))).toBe(true)
  })
  test('another stage, a word more, an empty reason or a repeated flag is another call', () => {
    expect(sameCall(written, ['override', 'review', '--reason', 'x'])).toBe(false)
    expect(sameCall(written, ['override', 'build', '--reason', 'x', '--reason', 'y'])).toBe(false)
    expect(sameCall(written, ['override', 'build', '--reason', ''])).toBe(false)
    expect(sameCall(written, ['override', 'build'])).toBe(false)
  })
  test('a step that is no temper call matches nothing', () => {
    expect(sameCall('git add -- .temper/specs/pw/', ['state', 'clear'])).toBe(false)
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
