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
