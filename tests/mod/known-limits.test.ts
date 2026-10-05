// What the Bash reader cannot do, on purpose. It reads command text only. Each row is an attempt that
// stays possible by nature: nothing in the command text names the Temper script, or the guarded file,
// or a decision word. The table is the honest record. The README says the same in its limits
// paragraph ("shell tricks" and the native pre-commit hook); scripts/check-known-limits.sh checks that
// text, because a plugin test cannot read the README.
//
// If a row here starts to be refused, the limit is smaller than the docs say: move the row to
// review-exploits-3.test.ts and update the paragraph.
import { describe, expect, test } from 'claude-code/testing'

import { evaluate } from '../../hooks/temper-mod/core/rules'
import type { RuleContext } from '../../hooks/temper-mod/core/rules'
import { stateAt } from './helpers'

const ctx: RuleContext = { specDir: '.temper/specs/pw', planFiles: [] }
const verdict = (command: string) => evaluate(stateAt('plan'), ctx, { tool: 'Bash', input: { command } })

export const KNOWN_LIMITS: Array<{ name: string; command: string; why: string }> = [
  {
    name: 'a link made in an earlier call',
    command: `echo '{}' > t/gates.json`,
    why: 'ln -s .temper t ran in an earlier call. The text names t, not .temper. The classifier has no realpath.',
  },
  {
    name: 'a link to the script made in an earlier call',
    command: '/tmp/tp state advance plan_complete build',
    why: 'ln -s scripts/temper /tmp/tp ran earlier. The command word is /tmp/tp, which names nothing.',
  },
  {
    name: 'a copy of the script made in an earlier call',
    command: '/tmp/t override plan --reason x',
    why: 'The copy was written earlier. Only a command that copies the script can be seen.',
  },
  {
    name: 'a script file already on disk, run later',
    command: 'bash /tmp/x.sh',
    why: 'The file was written in an earlier call. The command text holds no name and no decision word.',
  },
  {
    name: 'an interpreter file already on disk, run later',
    command: 'python3 /tmp/p.py',
    why: 'The program text is in a file the classifier never reads.',
  },
  {
    name: 'a variable set in an earlier call',
    command: '$T override plan --reason x',
    why: 'T was set in an earlier call or a profile. This one is still refused when the verb is literal, so it is checked below.',
  },
]

describe('KNOWN_LIMITS: attempts a text reader cannot see', () => {
  for (const row of KNOWN_LIMITS.filter(r => r.name !== 'a variable set in an earlier call')) {
    test(`${row.name} is not refused by the command text (${row.why})`, () => {
      expect('deny' in verdict(row.command)).toBe(false)
    })
  }

  test('an unresolved command word with a literal decision verb is refused (the limit is smaller than it looks)', () => {
    expect('deny' in verdict('$T override plan --reason x')).toBe(true)
  })

  test('every row says why', () => {
    for (const row of KNOWN_LIMITS) expect(row.why.length).toBeGreaterThan(20)
  })

  test('the rows are all different', () => {
    expect(new Set(KNOWN_LIMITS.map(r => r.command)).size).toBe(KNOWN_LIMITS.length)
  })
})

describe('what still holds when the reader is passed', () => {
  test('a Write to a guarded path is refused whatever Bash did', () => {
    const r = evaluate(stateAt('build'), { ...ctx, planFiles: ['**'] }, { tool: 'Write', input: { file_path: '.temper/gates.json' } })
    expect(r).toHaveProperty('deny')
  })
  test('a Write outside the phase is refused', () => {
    expect(evaluate(stateAt('plan'), ctx, { tool: 'Write', input: { file_path: 'src/app.ts' } })).toHaveProperty('deny')
  })
})
