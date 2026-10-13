// The findings of the independent review of 9.7.0 (step 9), each reproduced here before it was fixed. Every case is
// a command the reviewer ran against the guard at the PR head and found let through; the guard now refuses it.
import { describe, expect, test } from 'claude-code/testing'

import { currentAnswer, parseBook } from '../../hooks/temper-mod/core/decisions'
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
