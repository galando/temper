// The findings of the independent review of 9.7.0 (step 9), each reproduced here before it was fixed. Every case is
// a command the reviewer ran against the guard at the PR head and found let through; the guard now refuses it.
import { describe, expect, test } from 'claude-code/testing'

import { currentAnswer, parseBook, restartFor } from '../../hooks/temper-mod/core/decisions'
import { evaluate } from '../../hooks/temper-mod/core/rules'
import type { RuleContext, RuleResult } from '../../hooks/temper-mod/core/rules'
import { readShell, statements } from '../../hooks/temper-mod/core/shell'
import type { Stage } from '../../hooks/temper-mod/core/stages'
import { stateAt } from './helpers'

const CLI = 'scripts/temper'
const isDeny = (r: RuleResult): boolean => 'deny' in r
const ctx = (stage: Stage): RuleContext => ({
  run: stateAt(stage, { specDir: '.temper/specs/pw', planFiles: ['src/app.ts'] }),
  allowed: [],
  restart: false,
  drift: { added: [], allowOnce: [] },
})
const bash = (stage: Stage, command: string) => evaluate(ctx(stage), { tool: 'Bash', input: { command } })

describe('a backslash before a newline joins the lines, as bash does', () => {
  test('the words around it are one word, and the statement goes on', () => {
    expect(statements('scripts/temper \\\noverride review --reason x')).toEqual([['scripts/temper', 'override', 'review', '--reason', 'x']])
    expect(statements('echo "a\\\nb"')).toEqual([['echo', 'ab']])
  })
  test('a call, a commit past the hook and a write split over lines are each refused', () => {
    expect(isDeny(bash('review', `${CLI} \\\noverride review --reason x`))).toBe(true)
    expect(isDeny(bash('build', 'git commit \\\n--no-verify -m x'))).toBe(true)
    expect(isDeny(bash('build', 'rm \\\n.temper/gates.json'))).toBe(true)
  })
})

describe('the plain Bash writes onto a protected file the guard missed', () => {
  test('the >& and <> redirects name the file they write; a file descriptor is no file', () => {
    expect(readShell("echo '{}' >& .temper/gates.json").writes).toEqual(['.temper/gates.json'])
    expect(readShell("echo '{}' 1<> .temper/gates.json").writes).toEqual(['.temper/gates.json'])
    expect(readShell('npm test 2>&1; ls >&- ; ls >& 2').writes).toEqual([])
  })
  test('a target folder given with -t or --target-directory is written', () => {
    expect(readShell('cp -t .temper /tmp/gates.json').writes).toEqual(['.temper/gates.json'])
    expect(readShell('install --target-directory=.temper/evidence /tmp/review.json').writes).toEqual(['.temper/evidence/review.json'])
  })
  for (const command of [
    "echo '{}' >& .temper/gates.json",
    "echo '{}' 1<> .temper/gates.json",
    'rm .temper/*.json',
    'rm -f .temper/gate?.json',
    'rm -f .temper/[go]*.json',
    'cp -t .temper /tmp/gates.json',
    'rm -rf .temper/evidence',
    'rm -rf .temp*',
  ]) {
    test(`refused: ${command}`, () => expect(isDeny(bash('build', command))).toBe(true))
  }
  test('a glob that reaches no protected file is no refusal', () => {
    expect(isDeny(bash('build', 'rm -f src/*.tmp .temper/specs/pw/*.bak'))).toBe(false)
    // A segment that starts with a glob character does not match a dot name, as in bash: `*` leaves `.temper` alone.
    expect(isDeny(bash('build', 'rm -rf dist/* *'))).toBe(false)
  })
})

describe('the native hook switched off in a form the guard did not see', () => {
  test('git takes an unambiguous abbreviation of --no-verify', () => {
    for (const c of ['git commit --no-veri -m x', 'git commit --no-verif -m x']) expect(readShell(c).noVerify, c).toBe(true)
    // --no-ver is ambiguous for git (--no-verbose), so git refuses it: no hook is skipped.
    expect(readShell('git commit --no-ver -m x').noVerify).toBe(false)
  })
  test('removing or renaming the core section drops core.hooksPath', () => {
    for (const c of ['git config --remove-section core', 'git config --rename-section core old', 'git config --local --remove-section CORE']) {
      expect(readShell(c).hooksPath, c).toBe(true)
    }
    expect(readShell('git config --remove-section alias').hooksPath).toBe(false)
  })
})

describe('evidence clear erases what Review found', () => {
  test('clearing a stage ledger during a run is the person\'s, like accepting a finding', () => {
    expect(isDeny(bash('review', `${CLI} evidence clear --stage review`))).toBe(true)
    expect(isDeny(bash('check', `${CLI} evidence clear --stage check`))).toBe(true)
  })
})

describe('an answer counts for the question it answered, not for the next one at the same step', () => {
  // Build's group questions and an accepted finding keep the CLI's step: the next question comes at the same step.
  const g1 = {
    id: 'a', run: 'r', step: 1, stage: 'build', ts: 1, kind: 'gate' as const, label: 'Continue (Recommended)', move: 'advance',
    calls: ['/p/scripts/temper group continue G1'], steps: [], reason: '', ask: 'Group G1 (One) passed its check. Continue?',
  }
  test('the question of the next group is not answered by the answer to the first', () => {
    expect(currentAnswer([g1], { run: 'r', step: 1 }, 'Group G2 (Two) passed its check. Continue?')).toBeNull()
  })
  test('the question it answered, or no question while Claude carries it out, keeps it', () => {
    expect(currentAnswer([g1], { run: 'r', step: 1 }, 'Group G1 (One) passed its check. Continue?')?.label).toBe('Continue (Recommended)')
    expect(currentAnswer([g1], { run: 'r', step: 1 }, null)?.label).toBe('Continue (Recommended)')
  })
  test('a kept decision keeps the question it answered', () => {
    expect(parseBook([g1])[0]).toMatchObject({ ask: 'Group G1 (One) passed its check. Continue?' })
  })
})

// Round 2 of the independent review.
describe('round 2: a shell keyword or a wrapper does not hide the program', () => {
  for (const command of [
    'if true; then git commit --no-verify -m x; fi',
    '{ git commit -n -m x; }',
    'timeout 60 git commit --no-verify -m x',
    'timeout -s KILL 60 git commit --no-verify -m x',
    'env -i git commit --no-verify -m x',
    'for f in a; do rm -f .temper/gates.json; done',
    'while true; do rm .temper/gates.json; done',
    '! rm .temper/overrides.json',
    'nice rm .temper/gates.json',
    'nice -n 5 rm .temper/gates.json',
    'stdbuf -o0 rm .temper/gates.json',
  ]) {
    test(`refused: ${command}`, () => expect(isDeny(bash('build', command))).toBe(true))
  }
  test('an ordinary loop over source files is no refusal', () => {
    expect(isDeny(bash('build', 'for f in src/*.ts; do echo $f; done'))).toBe(false)
  })
})

describe('round 2: more spellings of a target folder, of sed in place, and a brace list', () => {
  for (const command of [
    'cp -at .temper /tmp/gates.json',
    'cp -t.temper /tmp/gates.json',
    'cp --target=.temper /tmp/gates.json',
    "sed --in-place=.bak 's/FAIL/PASS/' .temper/gates.json",
    "sed -i --expression='s/FAIL/PASS/' .temper/gates.json",
    'sed -i -es/FAIL/PASS/ .temper/gates.json',
    'rm .temper/{gates,overrides}.json',
  ]) {
    test(`refused: ${command}`, () => expect(isDeny(bash('build', command))).toBe(true))
  }
})

describe('round 2: a hooks path set through another config file', () => {
  for (const command of [
    "printf '[core]\\n\\thooksPath = /dev/null\\n' > .git/config.worktree",
    'git config include.path /tmp/x.cfg',
    'git config --local includeIf.gitdir:/x/.path /tmp/x.cfg',
    'git config unset core.hooksPath',
    'git config remove-section core',
  ]) {
    test(`refused: ${command}`, () => expect(isDeny(bash('build', command))).toBe(true))
  }
  test('reading the config is no refusal', () => {
    expect(isDeny(bash('build', 'git config --get include.path'))).toBe(false)
  })
})

describe('round 2: a Start over answer counts at the step it was given', () => {
  const restart = { id: 'r1', run: 'r', step: 0, stage: 'intent', ts: 1, kind: 'restart' as const, calls: [], reason: '' }
  test('at the same step it counts; at a later step it is spent', () => {
    expect(restartFor([restart], { run: 'r', step: 0 })).not.toBeNull()
    expect(restartFor([restart], { run: 'r', step: 1 })).toBeNull()
  })
})

// Round 3: a narrow check of the round 2 fixes. A wrapper no list names, a full path to a wrapper, a brace list past
// the cap or with a sequence or a substitution in it, and a substitution inside double quotes each still hid the
// program, the write or the call.
describe('round 3: no wrapper hides the program, whether a list names it or not', () => {
  for (const command of [
    '/usr/bin/env git commit --no-verify -m x',
    '/usr/bin/timeout 5 git commit --no-verify -m x',
    'exec -a foo git commit --no-verify -m x',
    'coproc git commit --no-verify -m x',
    'function f { git commit --no-verify -m x; }; f',
    'flock /tmp/l git commit --no-verify -m x',
    'eatmydata git commit --no-verify -m x',
    'sudo -D /tmp git commit --no-verify -m x',
    'exec -a foo rm .temper/gates.json',
    '/usr/bin/env rm .temper/gates.json',
    'coproc git config core.hooksPath /dev/null',
    'env GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null GIT_CONFIG_COUNT=1 git commit -m x',
  ]) {
    test(`refused: ${command}`, () => expect(isDeny(bash('build', command))).toBe(true))
  }
  test('ordinary commands that name git or a writing program are no refusal', () => {
    for (const command of [
      'git log --oneline -3',
      'npm install',
      'pip install -r requirements.txt',
      'git rm --cached src/old.ts',
      'timeout 60 npm test',
      'git commit -m "drop rm from the docs"',
      'ls git',
    ]) expect(isDeny(bash('build', command))).toBe(false)
  })
})

describe('round 3: brace lists as bash expands them', () => {
  for (const command of [
    'rm .temper/{x,gates.json}{,}{,}{,}{,}{,}{,}',
    'rm .temper/{f..g}ates.json',
    'rm .temper/gates.{json,`true`}',
    'rm .temper/{gates.json,$(true)}',
  ]) {
    test(`refused: ${command}`, () => expect(isDeny(bash('build', command))).toBe(true))
  }
  test('sequences, padding, steps, a nested list, and what bash leaves as it is', () => {
    expect(readShell('rm .temper/{a..c}.json').writes).toEqual(['.temper/a.json', '.temper/b.json', '.temper/c.json'])
    expect(readShell('rm f{08..10}').writes).toEqual(['f08', 'f09', 'f10'])
    expect(readShell('rm f{1..5..2}').writes).toEqual(['f1', 'f3', 'f5'])
    expect(readShell('rm f{a,{b,c}}').writes).toEqual(['fa', 'fb', 'fc'])
    expect(readShell('rm {a{b,c}').writes).toEqual(['{ab', '{ac'])
    expect(readShell('rm a{b}c ${x,y} f{1..a}').writes).toEqual(['a{b}c', '${x,y}', 'f{1..a}'])
  })
  test('a word that expands to more words than the guard reads is refused, not cut short', () => {
    expect(readShell('touch x{1..5000}').tooMany).toBe(true)
    expect(isDeny(bash('build', 'touch x{1..5000}'))).toBe(true)
    expect(readShell('touch x{1..50}').tooMany).toBe(false)
  })
})

describe('round 3: a command substitution is read, inside double quotes too', () => {
  for (const command of [
    'echo "$(scripts/temper override build --reason x)"',
    'echo "`scripts/temper override build --reason x`"',
    'echo "$(rm .temper/gates.json)"',
    'x="$(git commit --no-verify -m x)"',
  ]) {
    test(`refused: ${command}`, () => expect(isDeny(bash('build', command))).toBe(true))
  }
  test('its text stays in the word around it, and its commands are statements of their own', () => {
    expect(statements('x="$(git rev-parse HEAD)"; echo $x')).toEqual([['x=$(git rev-parse HEAD)'], ['echo', '$x'], ['git', 'rev-parse', 'HEAD']])
    expect(statements('echo "a `date` b"')).toEqual([['echo', 'a `date` b'], ['date']])
    expect(statements("echo \"$(printf ')')\"")).toEqual([["echo", "$(printf ')')"], ['printf', ')']])
  })
})

describe('round 3: the hooks path handed to git through a variable set earlier in the command', () => {
  for (const command of [
    'export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null; git commit -m x',
    'GIT_CONFIG_KEY_0=core.hooksPath; export GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0=/dev/null GIT_CONFIG_COUNT=1; git commit -m x',
    "declare -x GIT_CONFIG_PARAMETERS=\"'core.hooksPath=/dev/null'\"; git commit -m x",
  ]) {
    test(`refused: ${command}`, () => expect(isDeny(bash('build', command))).toBe(true))
  }
  test('reading the hooks path is no refusal', () => {
    expect(isDeny(bash('build', 'git config --get core.hooksPath'))).toBe(false)
  })
})
