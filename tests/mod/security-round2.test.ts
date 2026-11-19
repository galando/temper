// Tests that sit beside review-exploits-2.test.ts: the Temper CLI flows the guard keeps allowing, the stage an accept
// names, and the plugin folder path in a follow up prompt.
import { describe, expect, test } from 'claude-code/testing'

import { MOD_FILE, pluginCliFrom } from '../../hooks/temper-mod/core/cli'
import { check as evaluate } from './helpers'
import type { OldCtx as RuleContext } from './helpers'
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
    'scripts/temper evidence run --stage build --claim x --phase red -- bash scripts/selftest/test-temper.sh',
    'scripts/temper state get next_stage',
    // (complexity and base_sha are set in Plan and Build only, in the form the orchestrator uses: see hardening.test.ts)
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

describe('evidence accept needs the stage of the decision', () => {
  const accept = { id: 'e1', kind: 'accept' as const, phase: 'review', findingId: '1' }
  const call = (cmd: string) => evaluate(stateAt('review'), { ...ctx, humanDecisions: [accept] }, { tool: 'Bash', input: { command: cmd } })
  test('the same stage and id passes', () => expect('allow' in call('scripts/temper evidence accept --stage review --id 1 --reason x')).toBe(true))
  test('a call with no stage does not pass', () => expect('deny' in call('scripts/temper evidence accept --id 1 --reason x')).toBe(true))
  test('another stage does not pass', () => expect('deny' in call('scripts/temper evidence accept --stage check --id 1 --reason x')).toBe(true))
})

describe('the plugin folder path in a prompt', () => {
  const url = (p: string) => `file://${p}${MOD_FILE}`
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

describe('the setting words say where the person changes the setting', () => {
  // ADR 0012: the decision words go on to the orchestrator (it asks the Temper gate question). 9.7.3: the mode and
  // enforcement words change nothing from any origin; they name the /config option instead.
  for (const word of ['mode off', 'enforcement off']) {
    test(`${word} from a model origin`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'plan' }))
      await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: false })
      const r = await $.command.run({ command: 'temper', args: word, origin: { kind: 'sdk' } } as never)
      expect(r.text).toMatch(/Change it in \/config: Temper (UI mode|enforcement)/)
      expect(w.configSets).toEqual([])
    })
  }
  test('the spec folder name is used', () => expect(SPEC).toContain('.temper/specs/'))
})

// WP18: `evidence resolve` is never a tool call. The CLI resolves a finding itself, for its own repair commit (WP24),
// where no guard sees it; the rule refuses the call at every stage and in an armed run, even as a call written in the
// options of a question, so no answer of the person and no action of the CLI lets one through.
describe('evidence resolve is refused for the session and for every agent', () => {
  const calls = [
    'scripts/temper evidence resolve --stage review --id 3 --fixed-by 4f1c2ab',
    'scripts/temper evidence resolve --stage review --id 3 --fixed-by "the fix pass"',
    'cd demo && ../scripts/temper evidence resolve --stage check --id 1 --fixed-by HEAD',
    'S=/Users/x/plugin; "$S"/scripts/temper evidence resolve --stage review --id 1 --fixed-by HEAD',
    'bash scripts/temper evidence resolve --stage review --id 1 --fixed-by HEAD',
  ]
  for (const stage of ['build', 'review', 'check', 'commit'] as const) {
    for (const cmd of calls) test(`at ${stage}: ${cmd}`, () => expect('deny' in run(cmd, stage)).toBe(true))
  }
  const written = 'scripts/temper evidence resolve --stage review --id 1 --fixed-by 4f1c2ab'
  test('a call the options of a question name is refused all the same', () => {
    const r = evaluate(stateAt('review'), { ...ctx, allowed: [written] }, { tool: 'Bash', input: { command: written } })
    expect('deny' in r).toBe(true)
  })
  test('an armed run is refused all the same', () => {
    const r = evaluate(stateAt('review'), { ...ctx, autonomous: true }, { tool: 'Bash', input: { command: written } })
    expect('deny' in r).toBe(true)
  })
  // A /temper:fix run: the mod holds no run of its own there (run null), and the call is refused all the same.
  for (const cmd of calls) {
    test(`in a fix run: ${cmd}`, () => expect('deny' in evaluate(null, { ...ctx, fixRun: true }, { tool: 'Bash', input: { command: cmd } })).toBe(true))
  }
  // An unquoted glob that bash may expand to `resolve` (or `evidence`) once a file of that name exists is refused in a
  // fix run too, as it is in a /temper run.
  for (const cmd of [
    'scripts/temper evidence res?lve --stage review --id 1 --fixed-by HEAD',
    'scripts/temper evidence res[o]lve --stage review --id 1 --fixed-by HEAD',
    'scripts/temper evid?nce resolve --stage review --id 1 --fixed-by HEAD',
  ]) {
    test(`in a fix run, a glob: ${cmd}`, () => expect('deny' in evaluate(null, { ...ctx, fixRun: true }, { tool: 'Bash', input: { command: cmd } })).toBe(true))
  }
  test('the control: evidence list and evidence add at Review are allowed', () => {
    expect('deny' in run('scripts/temper evidence list --stage review', 'review')).toBe(false)
    const add = `scripts/temper evidence add --stage review --claim 'review completed' --exit 0`
    expect('deny' in run(add, 'review')).toBe(false)
  })
})
