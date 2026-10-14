// What the guard does not see in a Bash command, on purpose (ADR 0013). The guard reads a command for three things only:
// a temper call written out, a commit that switches the native hook off (--no-verify, a changed core.hooksPath, a plain
// write onto the git hooks), and a plain write into the .temper folder. Temper is not a sandbox: each row is an attempt
// that stays possible, and docs/trust.md and docs/mod.md say so. scripts/check-known-limits.sh checks that text, because
// a plugin test cannot read the docs.
//
// If a row here starts to be refused, the limit is smaller than the docs say: move the row to a test that expects the
// refusal, and update the docs.
import { describe, expect, test } from 'claude-code/testing'

import { check as evaluate } from './helpers'
import type { OldCtx as RuleContext } from './helpers'
import { stateAt } from './helpers'

const ctx: RuleContext = { specDir: '.temper/specs/pw', planFiles: [] }
const verdict = (command: string) => evaluate(stateAt('plan'), ctx, { tool: 'Bash', input: { command } })

export const KNOWN_LIMITS: Array<{ name: string; command: string; why: string }> = [
  {
    name: 'a call in a variable',
    command: 'T=scripts/temper; $T override plan --reason x',
    why: 'The command word is $T. The guard does not follow variables, so no temper call is written out.',
  },
  {
    name: 'a call in a string another program runs',
    command: `sh -c 'scripts/temper override plan --reason x'`,
    why: 'The call is one quoted word that sh runs. eval, perl -e, node -e and xargs hide a call the same way.',
  },
  {
    name: 'a call in a here document a shell reads',
    command: `bash <<'EOF'\nscripts/temper override plan --reason x\nEOF`,
    why: 'A here document is text to the guard, so a call quoted in a note is not refused; bash runs this one.',
  },
  {
    name: 'a link or a copy of the script made in an earlier call',
    command: '/tmp/tp state advance plan_complete build',
    why: 'ln -s scripts/temper /tmp/tp ran earlier. The command word is /tmp/tp, which does not name the script.',
  },
  {
    name: 'a script file already on disk, run later',
    command: 'bash /tmp/x.sh',
    why: 'The file was written in an earlier call. The command text holds no call and no path of the run.',
  },
  {
    name: 'a program that builds the script name at run time',
    command: `python3 -c "import os; os.system('scripts/te' + 'mper override plan --reason x')"`,
    why: 'The name is never in the text whole. The native hook and the editing tool rules still hold.',
  },
  {
    name: 'a write into the run folder through a variable',
    command: 'A=.temper; echo {} > $A/gates.json',
    why: 'The target is $A/gates.json. The guard does not follow variables; a plain path is refused.',
  },
  {
    name: 'a link to the run folder made in an earlier call',
    command: `echo '{}' > t/gates.json`,
    why: 'ln -s .temper t ran in an earlier call. The text names t, not .temper.',
  },
  {
    name: 'a write after a cd',
    command: 'cd .git && rm temper-pre-commit',
    why: 'The guard reads each path as written; it does not follow cd. The editing tools are judged on the real path.',
  },
  {
    name: 'a program that writes a file it names inside its own text',
    command: `python3 -c "open('.git/temper-gate/pre-commit', 'w').write('exit 0')"`,
    why: 'python3 is not a program the guard knows to write; the path is inside its program text.',
  },
  {
    name: 'an archive or a patch that holds a guarded file',
    command: 'tar xf /tmp/a.tar',
    why: 'The names are inside the archive, a file the guard never reads.',
  },
  {
    name: 'a commit the native hook does not check',
    command: 'git merge --no-ff other',
    why: 'git runs pre-commit for git commit only. A merge, cherry-pick, revert, am, pull or git plumbing makes a commit it does not see.',
  },
  {
    name: 'a git command that runs a command of its own',
    command: `git rebase --exec 'scripts/temper override plan --reason x' HEAD~1`,
    why: 'The call is one quoted word that git runs. bisect run, submodule foreach and an editor or pager set for the call do the same.',
  },
  {
    name: 'a git alias of the person for commit',
    command: 'git ci -m x',
    why: 'The alias lives in the git config the mod cannot read. The native pre-commit hook still checks the commit.',
  },
  {
    name: 'a change of the plugin data folder',
    command: 'rm -rf ~/.claude/plugins/data/temper',
    why: 'The editing tools may not write there during a run; the shell is not checked for it.',
  },
]

describe('KNOWN_LIMITS: attempts the guard does not see', () => {
  for (const row of KNOWN_LIMITS) {
    test(`${row.name} is not refused by the command text (${row.why})`, () => {
      expect('deny' in verdict(row.command)).toBe(false)
    })
  }

  test('every row says why', () => {
    for (const row of KNOWN_LIMITS) expect(row.why.length).toBeGreaterThan(20)
  })

  test('the rows are all different', () => {
    expect(new Set(KNOWN_LIMITS.map(r => r.command)).size).toBe(KNOWN_LIMITS.length)
  })
})

describe('what still holds when the guard does not see a command', () => {
  test('a Write to a guarded path is refused whatever Bash did', () => {
    const r = evaluate(stateAt('build'), { ...ctx, planFiles: ['**'] }, { tool: 'Write', input: { file_path: '.temper/gates.json' } })
    expect(r).toHaveProperty('deny')
  })
  test('a Write outside the phase is refused', () => {
    expect(evaluate(stateAt('plan'), ctx, { tool: 'Write', input: { file_path: 'src/app.ts' } })).toHaveProperty('deny')
  })
})
