// Tests that sit beside review-exploits-2.test.ts: the flows the fail closed Temper CLI rule must
// keep allowing, the deny texts of that rule, and the plugin folder path in a follow up prompt.
import { describe, expect, test } from 'claude-code/testing'

import { classifyBash } from '../../hooks/temper-mod/core/bash'
import { pluginCliFrom } from '../../hooks/temper-mod/core/cli'
import { evaluate } from '../../hooks/temper-mod/core/rules'
import type { RuleContext } from '../../hooks/temper-mod/core/rules'
import { stateAt } from './helpers'
import { SPEC, runFiles } from './run-files'
import { world } from './world'

const ctx: RuleContext = { specDir: '.temper/specs/pw', planFiles: [] }
const run = (command: string, phase: Parameters<typeof stateAt>[0] = 'build') =>
  evaluate(stateAt(phase), ctx, { tool: 'Bash', input: { command } })

describe('legitimate Temper CLI flows stay allowed', () => {
  const allowed = [
    'scripts/temper gate build',
    './scripts/temper gate check',
    '/Users/x/plugin/scripts/temper gate review',
    'cd /tmp/proj && /Users/x/plugin/scripts/temper gate plan',
    'cd demo && ../scripts/temper evidence list --stage review',
    'S=/Users/x/plugin; $S/scripts/temper gate check',
    'S=/Users/x/plugin; "$S"/scripts/temper evidence add --stage build --claim x',
    'scripts/temper evidence run --stage build --claim x --phase red -- bash scripts/tests/test-temper.sh',
    'scripts/temper evidence resolve --stage review --id 3 --reason fixed',
    'scripts/temper state get next_stage',
    // (complexity and base_sha are set in Plan and Build only, in the form the orchestrator uses: tests/mod/hardening.test.ts)
    'scripts/temper state set task 2',
    'scripts/temper state set regression_test tests/a.test.ts',
    'scripts/temper report',
    'scripts/temper status',
    'scripts/temper config get autonomy.enabled',
    'scripts/temper model plan',
    'bash scripts/temper gate check',
    'bash -o pipefail scripts/temper gate check',
    'timeout 60 scripts/temper gate build',
    'grep -n override scripts/temper',
    'cat scripts/temper | head -20',
    'git commit -m "document override and accept"',
    'cd /Users/x/dev/temper && git status && echo accept',
    'ls scripts/ && echo advance',
    'python3 -c "print(1)"',
  ]
  for (const cmd of allowed) {
    test(cmd, () => {
      expect('deny' in run(cmd, 'check') && !/commit blocked/.test((run(cmd, 'check') as { deny: string }).deny)).toBe(false)
    })
  }
})

describe('the fail closed rule: more spellings are denied and say what to do', () => {
  const attempts = [
    'tempe[r] override plan --reason x',
    'scripts/temp* override plan --reason x',
    'scripts/* state advance plan_complete build',
    'T=scripts/temper; $T override plan --reason x',
    'U=$(echo scripts/temper); $U override plan --reason x',
    'echo "scripts/temper override plan --reason x" | bash',
    'echo override | xargs scripts/temper',
    'nohup scripts/temper evidence accept --stage review --id 1 --reason x',
    'nice -n 5 scripts/temper state advance plan_complete build',
    'find . -maxdepth 0 -exec scripts/temper override plan --reason x \\;',
    'ln -s scripts/temper /tmp/t',
    'cp scripts/temper /tmp/t',
    'mv scripts/temper /tmp/t',
    'ln -s /Users/x/plugin/scripts/temper tp',
    'source scripts/temper',
    '. scripts/temper',
    'perl -e \'system("scripts/temper","override","plan")\'',
    'ruby -e \'system("scripts/temper override plan --reason x")\'',
    'node -e "require(\'child_process\').execSync(\'scripts/temper override plan --reason x\')"',
  ]
  for (const cmd of attempts) {
    test(cmd, () => {
      const r = run(cmd, 'plan')
      expect('deny' in r).toBe(true)
      if ('deny' in r) expect(r.deny).toMatch(/Next: /)
    })
  }

  test('a link of the script is denied with no decision word at all', () => {
    expect('deny' in run('ln -s scripts/temper /tmp/t', 'check')).toBe(true)
    expect(classifyBash('cp -r scripts/temper /tmp/t').alias).toBe(true)
  })

  test('the deny names the buttons and the subcommands', () => {
    const r = run('tempe[r] override plan --reason x', 'plan')
    expect('deny' in r && r.deny).toContain('/temper:temper')
    expect('deny' in r && r.deny).toContain('buttons')
  })
})

describe('evidence accept needs the stage of the decision', () => {
  const accept = { id: 'e1', kind: 'accept' as const, phase: 'review', findingId: '1' }
  const call = (cmd: string) => evaluate(stateAt('review'), { ...ctx, humanDecisions: [accept] }, { tool: 'Bash', input: { command: cmd } })
  test('the same stage and id passes', () => expect('allow' in call('scripts/temper evidence accept --stage review --id 1 --reason x')).toBe(true))
  test('a call with no stage does not pass', () => expect('deny' in call('scripts/temper evidence accept --id 1 --reason x')).toBe(true))
  test('another stage does not pass', () => expect('deny' in call('scripts/temper evidence accept --stage check --id 1 --reason x')).toBe(true))
})

describe('the plugin folder path in a prompt', () => {
  const url = (p: string) => `file://${p}/hooks/temper-mod/register.tsx`
  test('a plain folder gives the full path', () => expect(pluginCliFrom(url('/Users/a/plugin'))).toBe('/Users/a/plugin/scripts/temper'))
  test('an encoded space is not put into a command', () => expect(pluginCliFrom(url('/Users/a%20b/plugin'))).toBe('scripts/temper'))
  test('an encoded quote is not put into a command', () => expect(pluginCliFrom(url('/Users/a%27b/plugin'))).toBe('scripts/temper'))
  for (const ch of ['%24', '%3B', '%60', '%26', '%7C', '%3C', '%3E', '%28', '%29', '%5C', '%22', '%0A']) {
    test(`an encoded ${ch} is refused`, () => expect(pluginCliFrom(url(`/Users/a${ch}b/plugin`))).toBe('scripts/temper'))
  }
  test('another file location gives the plain path', () => expect(pluginCliFrom('file:///Users/a/other.tsx')).toBe('scripts/temper'))
  test('no URL gives the plain path', () => expect(pluginCliFrom(undefined)).toBe('scripts/temper'))
  test('a broken encoding gives the plain path', () => expect(pluginCliFrom(url('/Users/a%ZZb/plugin'))).toBe('scripts/temper'))
})

describe('refusals of the commands end with Next:', () => {
  for (const word of ['approve', 'override because', 'accept 1 because', 'pause', 'mode off']) {
    test(`${word} from a model origin`, async ($, on) => {
      world(on, runFiles({ nextStage: 'plan' }))
      await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: false })
      const r = await $.command.run({ command: 'temper', args: word, origin: { kind: 'sdk' } } as never)
      expect(r.text).toMatch(/Next: /)
    })
  }
  test('the spec folder name is used', () => expect(SPEC).toContain('.temper/specs/'))
})
