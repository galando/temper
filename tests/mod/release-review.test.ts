// Release review of 9.6.5: the deny texts name the CLI by full path (finding 23), and the TRIVIAL exit of the
// orchestrator can clear a run that has nothing to lose (finding 24). Since ADR 0012 the mod sends no prompts of its
// own: the prompts of finding 23 are gone with the buttons.
import { describe, expect, test } from 'claude-code/testing'

import { CLI } from '../../hooks/temper-mod/core/cli'
import { STAGES } from '../../hooks/temper-mod/core/stages'
import { check as evaluate } from './helpers'
import type { OldCtx as RuleContext } from './helpers'
import { stateAt } from './helpers'
import { INTENT, LATER, PLAN, SPEC, TASKS, runFiles } from './run-files'
import { world } from './world'

const ROOT = '/Users/a/plugin'
const ABS = `${ROOT}/scripts/temper`
// A plugin path that is written out in full: `scripts/temper` right after a slash of a longer path.
const BARE_CLI = /(?:^|[^/\w.-])scripts\/temper\b/
const PHASES = STAGES.filter(s => s !== 'commit')

describe('release review 23: every deny text names the CLI by full path when it is known', () => {
  const base: RuleContext = { specDir: SPEC, planFiles: [] }
  const writes = ['.temper/gates.json', '.temper/build-state.json', '.temper/evidence/build.json', '.temper/specs/pw/events/1.json', '.claude/temper.config', 'src/x.ts']
  const commands = [
    'rm -rf .temper',
    'echo {} > .temper/gates.json',
    'echo {} > .temper/build-state.json',
    'echo [] > .temper/evidence/build.json',
    'echo x > $G',
    'cp a .temper/gate*',
    'sed -i s/a/b/ .temper/gates.json',
    'scripts/temper state clear',
    'scripts/temper state archive',
    'T=$(command -v temper); $T $c',
    'eval "$(echo scripts/temper override plan)"',
    'ln -s scripts/temper /tmp/t',
    'TEMPER_DIR=/tmp scripts/temper gate build',
    'python3 tool.py .temper/gates.json',
    'scripts/temper state advance intent_complete build',
    'git commit --no-verify -m x',
  ]
  const denies = (cli?: string): string[] => {
    const out: string[] = []
    const ctx = cli === undefined ? base : { ...base, cli }
    const humanDecisions = [{ id: 'e1', kind: 'advance' as const, phase: 'intent' }]
    for (const phase of PHASES) {
      for (const file_path of writes) {
        const r = evaluate(stateAt(phase), ctx, { tool: 'Write', input: { file_path } })
        if ('deny' in r) out.push(r.deny)
      }
      for (const command of commands) {
        const r = evaluate(stateAt(phase), { ...ctx, humanDecisions }, { tool: 'Bash', input: { command } })
        if ('deny' in r) out.push(r.deny)
      }
    }
    return out
  }

  test('no deny text holds a plain scripts/temper when the plugin path is known', () => {
    const all = denies(ABS)
    expect(all.length).toBeGreaterThan(20)
    expect(all.some(d => d.includes(ABS))).toBe(true)
    for (const d of all) expect(BARE_CLI.test(d), d).toBe(false)
  })

  test('the Next: line of each kind names the full path', () => {
    const at = (command: string, phase: (typeof PHASES)[number] = 'build') => {
      const r = evaluate(stateAt(phase), { ...base, cli: ABS }, { tool: 'Bash', input: { command } })
      return 'deny' in r ? r.deny : ''
    }
    expect(at('rm -rf .temper')).toContain(`Next: use ${ABS} state archive`)
    expect(at('scripts/temper state clear')).toContain(`then run ${ABS} state archive`)
    expect(at('echo [] > .temper/evidence/build.json')).toContain(`Next: use ${ABS} evidence add`)
    const w = evaluate(stateAt('build'), { ...base, cli: ABS }, { tool: 'Write', input: { file_path: '.temper/gates.json' } })
    expect('deny' in w ? w.deny : '').toContain(`Next: run ${ABS} gate <stage>`)
  })

  test('with the plugin folder not known, the deny texts keep the plain path', () => {
    const r = evaluate(stateAt('build'), base, { tool: 'Bash', input: { command: 'rm -rf .temper' } })
    expect('deny' in r ? r.deny : '').toContain(`Next: use ${CLI} state archive`)
  })
})

describe('release review 24: the TRIVIAL exit clears a run that has nothing to lose', () => {
  const START = { cwd: '/repo', surface: null, isInteractive: false } as const
  type Api = { session: { start: (a: unknown) => Promise<unknown> }; tool: { call: (a: unknown) => Promise<{ deny?: string }> } }
  const CLEAR = '/home/u/.claude/plugins/temper/scripts/temper state clear'
  const FRESH = { stage: 'started', spec: 'pw', spec_path: SPEC, next_stage: 'intent', command: 'temper', branch: 'feature/pw', run_id: 'run-pw', step: 0 }
  // A run the orchestrator just started: the CLI is at Intent with the empty ledgers `state init` writes, and the spec
  // folder holds nothing yet. `extra` adds or replaces files (null removes one), `store` trusts event files.
  type Begin = { next?: string; intent?: string | null; extra?: Record<string, string | null> }
  const begin = async ($: unknown, on: Parameters<typeof world>[0], o: Begin = {}) => {
    const api = $ as Api
    const files = runFiles({ nextStage: o.next ?? 'intent' })
    files['.temper/build-state.json'] = JSON.stringify({ ...FRESH, next_stage: o.next ?? 'intent' })
    files['.temper/gates.json'] = '{}'
    files['.temper/overrides.json'] = '[]'
    files['/repo/.git/HEAD'] = 'ref: refs/heads/feature/pw\n'
    for (const name of ['intent.md', 'plan.md', 'tasks.md']) delete files[`${SPEC}/${name}`]
    if (o.intent !== undefined && o.intent !== null) files[`${SPEC}/intent.md`] = o.intent
    for (const [path, text] of Object.entries(o.extra ?? {})) {
      if (text === null) delete files[path]
      else files[path] = text
    }
    const w = world(on, files, { fakeCli: true, projectRoot: '/repo' })
    await api.session.start(START)
    return { w, api }
  }
  const sh = async (api: Api, command: string) => (await api.tool.call({ tool: 'Bash', command })).deny

  test('at Intent with no intent.md, state clear passes (by full path and by the plain path)', async ($, on) => {
    const { api } = await begin($, on)
    expect(await sh(api, CLEAR)).toBeUndefined()
    expect(await sh(api, 'scripts/temper state clear')).toBeUndefined()
  })

  test('after the TRIVIAL exit the cleared run is not held: the work that follows is not judged against it', async ($, on) => {
    const { w, api } = await begin($, on)
    const write = async () => (await api.tool.call({ tool: 'Write', file_path: 'app.py', content: 'x' })).deny
    // With the run at Intent, a write outside the spec folder waits for the intent (control).
    expect(await write()).toMatch(/Intent stage/)
    expect(await sh(api, CLEAR)).toBeUndefined()
    expect(w.files.has('.temper/build-state.json')).toBe(false)
    expect(await write()).toBeUndefined()
  })

  test('a clear the CLI did not carry out leaves the run as it was', async ($, on) => {
    const { w, api } = await begin($, on)
    // The command is let through, but the CLI refuses it: the state file stays.
    w.cliFailures = 1
    expect(await sh(api, CLEAR)).toBeUndefined()
    expect(w.files.has('.temper/build-state.json')).toBe(true)
    expect((await api.tool.call({ tool: 'Write', file_path: 'app.py', content: 'x' })).deny).toMatch(/Intent stage/)
  })

  test('at Intent with an intent.md, state clear is refused', async ($, on) => {
    const { api } = await begin($, on, { intent: '# Intent: x\n' })
    expect(await sh(api, CLEAR)).toMatch(/do not clear or archive/)
  })

  test('an intent.md written after the mod last read the run counts (read fresh)', async ($, on) => {
    const { w, api } = await begin($, on)
    expect(await sh(api, 'ls src')).toBeUndefined()
    w.files.set(`${SPEC}/intent.md`, '# Intent: x\n')
    expect(await sh(api, CLEAR)).toMatch(/do not clear or archive/)
  })

  test('an empty intent.md still counts as an intent', async ($, on) => {
    const { api } = await begin($, on, { intent: '' })
    expect(await sh(api, CLEAR)).toMatch(/do not clear or archive/)
  })

  test('an unreadable intent.md still counts as an intent', async ($, on) => {
    const { w, api } = await begin($, on, { intent: '# Intent: x\n' })
    w.unreadable = new Set([`${SPEC}/intent.md`])
    expect(await sh(api, CLEAR)).toMatch(/do not clear or archive/)
  })

  test('state archive and state init stay refused at Intent', async ($, on) => {
    const { api } = await begin($, on)
    expect(await sh(api, 'scripts/temper state archive')).toMatch(/do not clear or archive/)
    expect(await sh(api, 'scripts/temper state clear; scripts/temper state init other')).toMatch(/restart or move the run/)
  })

  test('a clear past Intent stays refused, also with no intent.md', async ($, on) => {
    const { api } = await begin($, on, { next: 'plan' })
    expect(await sh(api, CLEAR)).toMatch(/do not clear or archive/)
  })

  test('the rule: only at Intent, only when the run is known to have nothing to lose', () => {
    const ctx: RuleContext = { specDir: SPEC, planFiles: [] }
    // A run the orchestrator just started is at step 0.
    const run = (phase: (typeof PHASES)[number], extra: Partial<RuleContext>, command = 'scripts/temper state clear') =>
      evaluate(stateAt(phase, { step: 0 }), { ...ctx, ...extra }, { tool: 'Bash', input: { command } })
    expect('allow' in run('intent', { nothingToLose: true })).toBe(true)
    expect('deny' in run('intent', {})).toBe(true)
    expect('deny' in run('intent', { nothingToLose: false })).toBe(true)
    expect('deny' in run('intent', { nothingToLose: true }, 'scripts/temper state archive')).toBe(true)
    for (const phase of ['plan', 'design', 'build', 'review', 'check'] as const) expect('deny' in run(phase, { nothingToLose: true }), phase).toBe(true)
  })

  test('the rule: a run that took a step is not cleared, even back at Intent', () => {
    const ctx: RuleContext = { specDir: SPEC, planFiles: [], nothingToLose: true }
    const clear = { tool: 'Bash', input: { command: 'scripts/temper state clear' } }
    // The CLI counts every move of the run (ADR 0012): back at Intent after a loop, the step is past 0.
    expect('deny' in evaluate(stateAt('intent', { step: 2 }), ctx, clear)).toBe(true)
    expect('allow' in evaluate(stateAt('intent', { step: 0 }), ctx, clear)).toBe(true)
  })

  // Final review: deleting intent.md no longer opens the clear. A run that left Intent and came back to it (a loop back)
  // keeps its plan, its verdicts and its record: the agent may delete intent.md at Intent, and the clear stays refused.
  test('a loop back to Intent, then intent.md deleted, then state clear: refused', async ($, on) => {
    const gates = { intent: { verdict: 'PASS', ts: LATER }, plan: { verdict: 'PASS', ts: LATER } }
    const { w, api } = await begin($, on, {
      intent: INTENT,
      extra: {
        '.temper/build-state.json': JSON.stringify({ ...FRESH, stage: 'plan_complete', step: 3 }),
        '.temper/gates.json': JSON.stringify(gates),
        [`${SPEC}/plan.md`]: PLAN,
        [`${SPEC}/tasks.md`]: TASKS,
      },
    })
    // At Intent the intent may be rewritten, and removed: the world's rm is a stub, so the test removes the file.
    expect(await sh(api, `rm ${SPEC}/intent.md`)).toBeUndefined()
    w.files.delete(`${SPEC}/intent.md`)
    expect(await sh(api, CLEAR)).toMatch(/do not clear or archive/)
    expect(await sh(api, 'scripts/temper state clear')).toMatch(/do not clear or archive/)
    expect(w.files.has('.temper/build-state.json')).toBe(true)
  })

  // Each fact on its own keeps the run: the CLI files and the spec folder of an otherwise fresh run.
  const keeps: Record<string, Record<string, string>> = {
    'a completed stage in build-state.json': { '.temper/build-state.json': JSON.stringify({ ...FRESH, stage: 'intent_complete' }) },
    'a FAIL verdict in gates.json': { '.temper/gates.json': JSON.stringify({ intent: { verdict: 'FAIL', ts: LATER } }) },
    'a gates.json that is not JSON': { '.temper/gates.json': '{"intent":' },
    'a gates.json that is a list': { '.temper/gates.json': '[]' },
    'a skip in overrides.json': { '.temper/overrides.json': JSON.stringify([{ stage: 'intent', reason: 'later' }]) },
    'an overrides.json that is not a list': { '.temper/overrides.json': '{}' },
    'a plan.md': { [`${SPEC}/plan.md`]: PLAN },
    'an empty plan.md': { [`${SPEC}/plan.md`]: '' },
    'a tasks.md': { [`${SPEC}/tasks.md`]: TASKS },
    'a design.md': { [`${SPEC}/design.md`]: '# Design\n' },
  }
  for (const [name, extra] of Object.entries(keeps)) {
    test(`with ${name} and no intent.md, state clear is refused`, async ($, on) => {
      const { w, api } = await begin($, on, { extra })
      expect(await sh(api, CLEAR)).toMatch(/do not clear or archive/)
      expect(w.files.has('.temper/build-state.json')).toBe(true)
    })
  }

  test('a gates.json and overrides.json that are missing count as empty', async ($, on) => {
    const { w, api } = await begin($, on, { extra: { '.temper/gates.json': null, '.temper/overrides.json': null } })
    expect(await sh(api, CLEAR)).toBeUndefined()
    expect(w.files.has('.temper/build-state.json')).toBe(false)
  })

  test('a run whose CLI counted a step is kept, also when its files look fresh', async ($, on) => {
    const { api } = await begin($, on, { extra: { '.temper/build-state.json': JSON.stringify({ ...FRESH, step: 2 }) } })
    expect(await sh(api, CLEAR)).toMatch(/do not clear or archive/)
  })
})
