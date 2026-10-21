// The findings of the 9.7.0 release audit about the guard's reading of Bash (round 4), each reproduced against real bash
// before it was fixed: a call or a commit past the hook written out in a quote bash decodes, in a brace list, behind a
// variable word, by a glob, or handed to git as config, and a copy into the spec folder refused for nothing.
import { describe, expect, test } from 'claude-code/testing'

import { evaluate } from '../../hooks/temper-mod/core/rules'
import type { RuleContext, RuleResult } from '../../hooks/temper-mod/core/rules'
import { readShell, sameCall, statements } from '../../hooks/temper-mod/core/shell'
import type { Stage } from '../../hooks/temper-mod/core/stages'
import { stateAt } from './helpers'

const CLI = '/p/scripts/temper'
const isDeny = (r: RuleResult): boolean => 'deny' in r
const ctx = (stage: Stage, allowed: string[] = []): RuleContext => ({
  run: stateAt(stage, { specDir: '.temper/specs/pw', planFiles: ['src/app.ts'] }),
  allowed,
  restart: false,
  drift: { added: [], allowOnce: [] },
})
const bash = (stage: Stage, command: string, allowed: string[] = []) => evaluate(ctx(stage, allowed), { tool: 'Bash', input: { command } })

describe('round 4: the quotes bash decodes', () => {
  test("$'...' is read with its escapes, and $\"...\" as a double quote", () => {
    expect(statements(`echo $'a\\tb' $'\\x72m' $"c d"`)).toEqual([['echo', 'a\tb', 'rm', 'c d']])
    expect(statements(`printf $'it\\'s'`)).toEqual([['printf', "it's"]])
  })
  for (const command of [`${CLI} $'override' check --reason x`, `$'${CLI}' override check --reason x`, `${CLI} state $'loop' build plan --reason x`]) {
    test(`a person only call is refused: ${command}`, () => expect(isDeny(bash('build', command))).toBe(true))
  }
  for (const command of [`$'git' commit --no-verify -m x`, `$"git" commit -n -m x`, `g$'it' commit -n -m x`, `$'rm' .temper/gates.json`, `echo {} > $'.temper/gates.json'`]) {
    test(`refused: ${command}`, () => expect(isDeny(bash('build', command))).toBe(true))
  }
})

describe('round 4: every word is brace expanded, and a quoted brace is not', () => {
  for (const command of [`{${CLI},override} build --reason x`, `${CLI} {override,review} --reason x`, '{git,commit} --no-verify -m x', '{rm,.temper/gates.json}', '{cp,/tmp/g,.temper/gates.json}']) {
    test(`refused: ${command}`, () => expect(isDeny(bash('build', command))).toBe(true))
  }
  test('a quoted brace list stays one word, as in bash', () => {
    expect(readShell(`git commit -m 'a {x,y} b'`).noVerify).toBe(false)
    expect(isDeny(bash('build', `git commit -m "fix {a,b} and {1..2000}"`))).toBe(false)
    expect(isDeny(bash('build', `${CLI} override build --reason 'see {a,b}'`, [`${CLI} override build --reason '{reason}'`]))).toBe(false)
  })
  test('a long sequence names no program, so a loop over it is no refusal; a long list in a write still is', () => {
    expect(isDeny(bash('build', 'for i in {1..3000}; do echo $i; done'))).toBe(false)
    expect(isDeny(bash('build', 'touch x{1..5000}'))).toBe(true)
    expect(isDeny(bash('build', '{rm,a{1..2000}} .temper/gates.json'))).toBe(true)
  })
})

describe('round 4: a word that sets a variable does not hide the call after it', () => {
  for (const command of [`TEMPER_HOME=/opt/temper ${CLI} override build --reason x`, `PLUGIN=/home/u/temper ${CLI} state clear`]) {
    test(`refused: ${command}`, () => expect(isDeny(bash('build', command))).toBe(true))
  }
  test('each call of a statement is read', () => {
    expect(readShell(`T=/x/temper ${CLI} gate build`).calls).toEqual([['gate', 'build']])
  })
})

describe('round 4: a program named by a glob or in another case', () => {
  for (const command of ['/usr/bin/gi[t] commit -n -m x', 'GIT commit --no-verify -m x', '/bin/r? .temper/gates.json', `/p/scripts/tempe[r] override build --reason x`]) {
    test(`refused: ${command}`, () => expect(isDeny(bash('build', command))).toBe(true))
  }
  test('a glob of no literal text names no program', () => {
    expect(isDeny(bash('build', 'ls src/* tests/*; wc -l *'))).toBe(false)
  })
})

describe('round 4: config handed to git that can switch the hook off', () => {
  for (const command of [
    'git -c include.path=/tmp/x.cfg commit -m x',
    'git -c includeIf.onbranch:main.path=/tmp/x.cfg commit -m x',
    'HP=/dev/null git --config-env core.hooksPath=HP commit -m x',
    'git --config-env=alias.ci=X ci -m x',
    "git -c alias.ci='commit --no-verify' ci -m x",
    "git -c alias.ci='!git commit -n' ci -m x",
    "git config alias.ci 'commit --no-verify'",
    'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=include.path GIT_CONFIG_VALUE_0=/tmp/x git commit -m x',
    'GIT_CONFIG_GLOBAL=/tmp/x.cfg git commit -m x',
  ]) {
    test(`refused: ${command}`, () => expect(isDeny(bash('build', command))).toBe(true))
  }
  test('an alias that commits through the hook, and reading an alias, are no refusal', () => {
    expect(isDeny(bash('build', "git -c alias.st='status -s' st"))).toBe(false)
    expect(isDeny(bash('build', 'git config --get-regexp alias'))).toBe(false)
  })
})

describe('round 4: a copy into the spec folder is a write into it, not a replacement of it', () => {
  for (const command of ['cp notes.md .temper/specs/pw/', 'mv draft.md .temper/specs/pw', 'cp -r assets .temper/specs/pw/']) {
    test(`allowed: ${command}`, () => expect(isDeny(bash('review', command))).toBe(false))
  }
  for (const command of ['cp /tmp/gates.json .temper/', 'mv /tmp/x/overrides.json .temper', 'cp -T /tmp/x .temper', 'rsync -a out/ .temper/specs/pw/', 'rm -rf .temper/specs/pw']) {
    test(`refused: ${command}`, () => expect(isDeny(bash('review', command))).toBe(true))
  }
})

describe('round 4: sameCall reads the call the CLI wrote the same way', () => {
  test('a quoted placeholder stays a placeholder', () => {
    expect(sameCall(`${CLI} state loop review build --reason '{reason}'`, ['state', 'loop', 'review', 'build', '--reason', 'a b'])).toBe(true)
  })
})

describe('round 4: a project below the top of its git repository', () => {
  // A group or task worktree is a checkout of the whole repository: the project's files are under its prefix there.
  const nested: RuleContext = {
    run: { ...stateAt('build', { specDir: '.temper/specs/pw', planFiles: ['src/app.ts'] }), prefix: 'packages/app/' },
    allowed: [],
    restart: false,
    drift: { added: [], allowOnce: [] },
  }
  const write = (path: string) => evaluate(nested, { tool: 'Write', input: { file_path: path } })
  test('a write in a task worktree is judged from the project folder in it', () => {
    expect(isDeny(write('.claude/worktrees/temper-pw-T1/packages/app/src/app.ts'))).toBe(false)
    expect(isDeny(write('.claude/worktrees/temper-pw-T1/packages/app/tests/app.test.ts'))).toBe(false)
  })
  test('a path of the worktree outside the project is no plan file', () => {
    expect(isDeny(write('.claude/worktrees/temper-pw-T1/src/app.ts'))).toBe(true)
    expect(isDeny(write('.claude/worktrees/temper-pw-G1/lib/shared.ts'))).toBe(true)
  })
})

// The re-audit of the round 4 fixes: each case below was reproduced against the guard and, for a commit past the hook,
// against real bash, before it was fixed.
describe('re-audit: a copy into a folder does not let another write of that folder through', () => {
  for (const command of ['cp /dev/null .temper/ ; rm -rf .temper/', 'mv notes.md .temper/specs/pw/ && rm -rf .temper/specs/pw', 'cp a .temper/specs/pw/; rm -r .temper/specs/pw/']) {
    test(`refused: ${command}`, () => expect(isDeny(bash('review', command))).toBe(true))
  }
  test('a copy target that is a protected file is still refused, and mv still writes its sources', () => {
    expect(isDeny(bash('review', 'cp /tmp/x .temper/gates.json'))).toBe(true)
    expect(isDeny(bash('review', 'ln -s /tmp/x .temper/gates.json'))).toBe(true)
    expect(isDeny(bash('review', 'mv .temper/gates.json /tmp/x'))).toBe(true)
  })
})

describe('re-audit: a brace list gives each word as many times as bash does', () => {
  test('the words it repeats are kept', () => {
    expect(readShell('rm a{,}b').writes).toEqual(['ab', 'ab'])
  })
  for (const command of ['git commit -m {-n,-n}', 'git commit -m {--no-verify,--no-verify}', 'git commit -F {x,x} -n']) {
    test(`refused: ${command}`, () => expect(isDeny(bash('build', command))).toBe(true))
  }
})

describe('re-audit: a glob with a class names a program', () => {
  for (const command of ['/usr/bin/[[:alpha:]]it commit -n -m x', '/usr/bin/g[[:lower:]]t commit --no-verify -m x', '/bin/[[:alpha:]]m .temper/gates.json']) {
    test(`refused: ${command}`, () => expect(isDeny(bash('build', command))).toBe(true))
  }
  test('a glob of classes only has no literal text and names no program', () => {
    expect(isDeny(bash('build', 'ls [[:alpha:]]* src/[[:digit:]]?'))).toBe(false)
  })
})

describe('re-audit: a home folder handed to git', () => {
  for (const command of ['HOME=/tmp/h git ci -m x', 'export XDG_CONFIG_HOME=/tmp/x; git ci -m x', 'env HOME=/tmp/h git commit -m x']) {
    test(`refused: ${command}`, () => expect(isDeny(bash('build', command))).toBe(true))
  }
  test('a home folder for another program is no refusal', () => {
    expect(isDeny(bash('build', 'HOME=/tmp/h npm test'))).toBe(false)
  })
})

describe('re-audit: a temper call with a glob in its words', () => {
  for (const command of [`${CLI} o?erride intent --reason x`, `${CLI} state lo[o]p review build --reason x`, `${CLI} * --reason x`]) {
    test(`refused: ${command}`, () => expect(isDeny(bash('build', command))).toBe(true))
  }
  test('a glob in the reason, or a quoted one, is no refusal', () => {
    expect(isDeny(bash('build', `${CLI} gate build`))).toBe(false)
    expect(isDeny(bash('build', `${CLI} evidence add --stage build --claim 'a*b' --cmd 'npm test' --exit 0 --phase green`))).toBe(false)
    expect(isDeny(bash('build', `${CLI} usage add --stage build --reason why?`))).toBe(false)
  })
})

describe('re-audit: the project notes a config suggestion may go into', () => {
  test('.claude/AGENTS.md at Check, as reference/config-suggestions.md names it', () => {
    expect(isDeny(evaluate(ctx('check'), { tool: 'Write', input: { file_path: '.claude/AGENTS.md' } }))).toBe(false)
  })
})

// The second narrow review of the final tree: each case reproduced against the guard, and the commits past the hook and
// the forged ledgers against real bash, before it was fixed.
describe('second review: a glob as a copy target is judged as a write', () => {
  for (const command of ['cp /tmp/f.json .temper/[Eg][Va]*', 'mv /tmp/f.json .temper/[Eo][Vv]*', 'ln -sf /tmp/f.json .temper/g*', 'install /tmp/f.json .temper/[g]*']) {
    test(`refused: ${command}`, () => expect(isDeny(bash('review', command))).toBe(true))
  }
  test('a copy into a folder named plainly is still a write into it', () => {
    expect(isDeny(bash('review', 'cp a b .temper/specs/pw/'))).toBe(false)
  })
})

describe('second review: NAME+=value sets a variable', () => {
  for (const command of [
    'GIT_CONFIG_COUNT+=1 GIT_CONFIG_KEY_0+=core.hooksPath GIT_CONFIG_VALUE_0+=/dev/null git commit -m x',
    'HOME+=/hh git ci -m x',
    'GIT_CONFIG_GLOBAL+=/tmp/x git commit -m x',
    `TEMPER_HOME+=/x ${CLI} override build --reason x`,
  ]) {
    test(`refused: ${command}`, () => expect(isDeny(bash('build', command))).toBe(true))
  }
})

describe('second review: a program named by bracket sets alone', () => {
  for (const command of ['/usr/bin/[g][i][t] commit -n -m x', '/p/scripts/[t][e][m][p][e][r] override build --reason x', '/usr/bin/[r][m] -rf .temper', '/usr/bin/[g][i][]t] commit -n -m x']) {
    test(`refused: ${command}`, () => expect(isDeny(bash('build', command))).toBe(true))
  }
  test('a negated set or a class is no literal text, but a letter beside it is', () => {
    expect(isDeny(bash('build', 'ls [[:alpha:]]* [!a]*'))).toBe(false)
    expect(isDeny(bash('build', '/bin/[!x]m .temper/gates.json'))).toBe(true)
  })
})

describe('second review: a copy that keeps the source path, and rsync that removes its sources', () => {
  for (const command of ['cp --parents evidence/review.json .temper/', 'rsync -aR evidence/review.json .temper/', 'rsync --relative evidence/gates.json .temper/', 'rsync --remove-source-files .temper/gates.json /tmp/']) {
    test(`refused: ${command}`, () => expect(isDeny(bash('build', command))).toBe(true))
  }
  test('cp --parents into a folder of the project is no refusal', () => {
    expect(isDeny(bash('build', 'cp --parents src/a.ts out/'))).toBe(false)
  })
})

describe('second review: a glob in a temper call is refused only when it could spell a word the person decides', () => {
  for (const command of [`${CLI} group reopen G1 --reason x --accept-for?ign abc1234`, `${CLI} group reopen G1 --accept-for?ign=abc1234 --reason x`, `${CLI} state lo?p review build --reason x`]) {
    test(`refused: ${command}`, () => expect(isDeny(bash('build', command))).toBe(true))
  }
  for (const command of [`${CLI} task gate 1 --model sonnet[1m] --ms 3400`, 'grep -rn TODO /home/user/temper --include=*.ts', 'find ~/.claude/plugins/cache/temper -name *.md']) {
    test(`allowed: ${command}`, () => expect(isDeny(bash('build', command))).toBe(false))
  }
})

describe('second review: a copy of a folder\'s contents (rsync, and cp on macOS) lands where the guard cannot tell', () => {
  for (const command of ['cp -R dir/ .temper/', 'cp -r out/ .temper/evidence']) {
    test(`refused: ${command}`, () => expect(isDeny(bash('build', command))).toBe(true))
  }
  test('a copy of a folder by its name is a write into the folder', () => {
    expect(isDeny(bash('review', 'cp -r assets .temper/specs/pw/'))).toBe(false)
  })
})

describe('live run 6: a door\'s stage and what an earlier run built are the CLI\'s', () => {
  for (const command of [`${CLI} state set enter build`, `${CLI} state set built_before abc1234`, `${CLI} state set review_snapshot x`]) {
    test(`refused: ${command}`, () => expect(isDeny(bash('review', command))).toBe(true))
  }
})
