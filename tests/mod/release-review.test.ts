// Release review of 9.6.5: the prompts and deny texts name the CLI and the plugin's files by full path (finding 23),
// and the TRIVIAL exit of the orchestrator can clear a run that has nothing to lose (finding 24).
import { describe, expect, test } from 'claude-code/testing'

import { actionsFor, doneActions, findingActions, moreActions } from '../../hooks/temper-mod/core/actions'
import type { Action, ActionContext } from '../../hooks/temper-mod/core/actions'
import { CLI, IN_PLUGIN, pluginRootOf } from '../../hooks/temper-mod/core/cli'
import { followUp } from '../../hooks/temper-mod/core/commands'
import type { Draft } from '../../hooks/temper-mod/core/events'
import { PHASES } from '../../hooks/temper-mod/core/events'
import { evaluate } from '../../hooks/temper-mod/core/rules'
import type { RuleContext } from '../../hooks/temper-mod/core/rules'
import { MOD_CLI } from '../../hooks/temper-mod/register'
import { stateAt } from './helpers'
import { INTENT, LATER, PLAN, SPEC, TASKS, eventFile, runFiles, trusted } from './run-files'
import { world } from './world'

const ROOT = '/Users/a/plugin'
const ABS = `${ROOT}/scripts/temper`
// A plugin path that is written out in full: `scripts/temper` right after a slash of a longer path.
const BARE_CLI = /(?:^|[^/\w.-])scripts\/temper\b/
// The plugin files a prompt may name; each must come after the plugin folder.
const PLUGIN_FILES = ['reference/plan-review.md', 'scripts/plan_review.py']
const person = { origin: 'person', author: 'u' } as const

const STATES: ActionContext[] = [
  {},
  { ready: true, gate: 'fresh' },
  { gate: 'fail' },
  { hasFindings: true },
  { allChecksPass: true, ready: true, gate: 'fresh' },
  { loopLimitReached: true },
  { paused: true, configSuggestions: true, task: { n: 2, of: 5 } },
  { gate: 'fail', task: { n: 2, of: 3 }, tasksLeft: 2 },
  { pending: true, gate: 'fresh', ready: true },
]

const promptsOf = (cli: string): Array<{ where: string; text: string }> => {
  const out: Array<{ where: string; text: string }> = []
  const add = (where: string, a: Action) => {
    if (a.prompt) out.push({ where: `${where} ${a.id}`, text: a.prompt })
  }
  for (const p of PHASES) {
    for (const ctx of STATES) {
      const set = actionsFor(p, { ...ctx, cli })
      for (const a of [...set.primary, set.discuss, ...(set.override ? [set.override] : []), ...set.more, ...moreActions(p, { ...ctx, cli })]) add(p, a)
    }
  }
  for (const a of doneActions(cli).primary) add('done', a)
  for (const a of findingActions('1')) add('finding', a)
  return out
}

const DRAFTS: Draft[] = [
  { type: 'advance', from: 'intent', to: 'plan', ...person },
  { type: 'advance', from: 'check', to: 'done', ...person },
  { type: 'override', phase: 'build', reason: 'r', ...person },
  { type: 'accept', findingId: '1', reason: 'r', ...person },
  { type: 'back', to: 'plan', reason: 'r', ...person },
]

describe('release review 23: every prompt names the CLI and the plugin files by full path when it is known', () => {
  test('the plugin folder comes from the full CLI path, and not from the plain one', () => {
    expect(pluginRootOf(ABS)).toBe(ROOT)
    expect(pluginRootOf(CLI)).toBeNull()
  })

  test('no button prompt holds a plain scripts/temper, and the plugin files follow the plugin folder', () => {
    const all = promptsOf(ABS)
    expect(all.length).toBeGreaterThan(10)
    for (const { where, text } of all) {
      expect(BARE_CLI.test(text), `${where}: ${text}`).toBe(false)
      expect(text, where).not.toContain('commands/temper.md')
      for (const f of PLUGIN_FILES) if (text.includes(f)) expect(text, where).toContain(`${ROOT}/${f}`)
      expect(text, where).not.toContain(IN_PLUGIN)
    }
  })

  test('the CLI prompts carry the full path: Stop, Commit, the HTML review and its sharing', () => {
    const stop = actionsFor('build', { gate: 'fail', task: { n: 2, of: 3 }, tasksLeft: 2, cli: ABS }).primary[2]
    expect(stop?.prompt).toContain(`${ABS} gate build`)
    const commit = doneActions(ABS).primary[0]?.prompt ?? ''
    for (const call of ['gate commit', 'state archive', 'state clear']) expect(commit).toContain(`${ABS} ${call}`)
    expect(commit).toContain('Commit steps of /temper:temper')
    const html = actionsFor('plan', { cli: ABS }).primary[2]?.prompt ?? ''
    expect(html).toContain(`${ROOT}/reference/plan-review.md`)
    expect(html).toContain(`${ROOT}/scripts/plan_review.py`)
    const share = moreActions('plan', { cli: ABS }).find(a => a.id === 'share-review')?.prompt ?? ''
    expect(share).toContain(`${ROOT}/reference/plan-review.md`)
  })

  test('the mirror prompts name the full path too', () => {
    for (const d of DRAFTS) {
      const text = followUp(d, null, ABS, d.type === 'back' ? 'build' : null) ?? ''
      expect(text, d.type).toContain(ABS)
      expect(BARE_CLI.test(text), `${d.type}: ${text}`).toBe(false)
    }
  })

  test('with the plugin folder not known, the plain path says where the files are', () => {
    const stop = actionsFor('build', { gate: 'fail', task: { n: 2, of: 3 }, tasksLeft: 2 }).primary[2]?.prompt ?? ''
    expect(stop).toContain(`${CLI} gate build`)
    expect(stop).toContain(IN_PLUGIN)
    const commit = doneActions().primary[0]?.prompt ?? ''
    expect(commit).toContain(`${CLI} gate commit`)
    expect(commit).toContain(IN_PLUGIN)
    expect(actionsFor('plan', {}).primary[2]?.prompt).toContain('in the Temper plugin folder')
    expect(moreActions('plan', {}).find(a => a.id === 'share-review')?.prompt).toContain('in the Temper plugin folder')
  })
})

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
    'git commit -m x',
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
    expect(at('ln -s scripts/temper /tmp/t')).toContain(`Next: run ${ABS} by its own path`)
    expect(at('TEMPER_DIR=/tmp scripts/temper gate build')).toContain(`Next: run ${ABS} with no TEMPER_DIR`)
    const w = evaluate(stateAt('build'), { ...base, cli: ABS }, { tool: 'Write', input: { file_path: '.temper/gates.json' } })
    expect('deny' in w ? w.deny : '').toContain(`Next: run ${ABS} gate <stage>`)
  })

  test('with the plugin folder not known, the deny texts keep the plain path', () => {
    const r = evaluate(stateAt('build'), base, { tool: 'Bash', input: { command: 'rm -rf .temper' } })
    expect('deny' in r ? r.deny : '').toContain(`Next: use ${CLI} state archive`)
  })
})

// The engine side: the prompts the mod submits and suggests, and its deny texts, through the test world. The plugin
// folder is where this checkout is (the mod's own module URL); a folder with a space gives the plain path.
describe('release review 23: what the mod sends through the engine', () => {
  const START = { cwd: '/repo', surface: null, isInteractive: false } as const
  const BAND = { hasSurvey: false, isWorking: false, maxRows: 12, bodyColumns: 100, scroll: { offset: 0, bodyRows: 12 }, view: {} } as const
  type Mounted = { press: (a: { key: string }) => Promise<void> }
  type Api = {
    ui: { mount: (a: unknown) => Promise<Mounted> }
    session: { start: (a: unknown) => Promise<unknown> }
    tool: { call: (a: unknown) => Promise<{ deny?: string }> }
    turn: { complete: (a: unknown) => Promise<unknown> }
  }
  const band = (api: Api) => api.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', props: BAND })
  // The CLI path as the mod computes it from its own module URL (the value the mod exports).
  const here = MOD_CLI
  // Every text that names the CLI names it as the mod computes it: by full path, or plainly with where it is.
  const checkText = (text: string) => {
    if (pluginRootOf(here) !== null) {
      expect(BARE_CLI.test(text), text).toBe(false)
      for (const f of PLUGIN_FILES) if (text.includes(f)) expect(text).toContain(`${pluginRootOf(here)}/${f}`)
    } else if (BARE_CLI.test(text)) expect(/plugin folder/.test(text), text).toBe(true)
  }

  test('the button prompts at Plan and the mirror prompt of a skip', async ($, on) => {
    const api = $ as unknown as Api
    const w = world(on, runFiles({ nextStage: 'plan' }), { placed: false, answers: ['the reviewer is away'] })
    await api.session.start(START)
    const ui = await band(api)
    await ui.press({ key: 'action-html-review' })
    await ui.press({ key: 'action-more' })
    await ui.press({ key: 'action-share-review' })
    // A skip with a reason: the mirror prompt names the CLI.
    await ui.press({ key: 'action-override' })
    expect(w.prompts.length).toBeGreaterThanOrEqual(3)
    for (const p of w.prompts) checkText(p)
    expect(w.prompts.some(p => p.includes(here))).toBe(true)
  })

  test('the Stop prompt at a Build checkpoint', async ($, on) => {
    const api = $ as unknown as Api
    const w = world(on, runFiles({ nextStage: 'build' }), { placed: false })
    await api.session.start(START)
    const ui = await band(api)
    await ui.press({ key: 'action-stop' })
    expect(w.prompts.some(p => p.includes(`${here} gate build`))).toBe(true)
    for (const p of w.prompts) checkText(p)
  })

  test('the Commit prompt at Done, pressed and suggested', async ($, on) => {
    const api = $ as unknown as Api
    const w = world(on, runFiles({ nextStage: 'check', gates: { check: 'PASS' } }))
    on('turn.complete', ($2, e) => ({ text: e.answer }))
    await api.session.start(START)
    await api.tool.call({ tool: 'Bash', command: 'scripts/temper gate check' })
    await api.turn.complete({ answer: 'done', durationMs: 10, isAborted: false, turnId: 't1', reason: 'answer' })
    expect(w.suggestions.some(p => p.includes('Commit steps of /temper:temper'))).toBe(true)
    const ui = await band(api)
    await ui.press({ key: 'action-commit' })
    const commit = w.prompts.find(p => p.includes('Commit steps of /temper:temper')) ?? ''
    expect(commit).toContain(`${here} gate commit`)
    for (const p of [...w.prompts, ...w.suggestions]) checkText(p)
  })

  test('a deny text from the guard', async ($, on) => {
    const api = $ as unknown as Api
    world(on, runFiles({ nextStage: 'build' }))
    await api.session.start(START)
    const r = await api.tool.call({ tool: 'Bash', command: 'rm -rf .temper' })
    expect(r.deny ?? '').toContain(`${here} state archive`)
    checkText(r.deny ?? '')
  })
})

// ---- 24. The TRIVIAL exit ---------------------------------------------------------------------------------------
// The orchestrator runs `state init`, the intent stage answers TRIVIAL and writes nothing, and the orchestrator
// clears the run (commands/temper.md). With the mod on, that clear passes only for a run that never left Intent: the CLI
// shows no completed stage, no verdict and no skip, the spec folder holds no intent.md, plan.md, tasks.md or design.md,
// and the mod's own record holds only the start. Then nothing is lost. Everything else about clearing and archiving
// stays refused.
describe('release review 24: the TRIVIAL exit clears a run that has nothing to lose', () => {
  const START = { cwd: '/repo', surface: null, isInteractive: false } as const
  type Api = { session: { start: (a: unknown) => Promise<unknown> }; tool: { call: (a: unknown) => Promise<{ deny?: string }> } }
  const CLEAR = '/home/u/.claude/plugins/temper/scripts/temper state clear'
  const FRESH = { stage: 'started', spec: 'pw', spec_path: SPEC, next_stage: 'intent', command: 'temper', branch: 'feature/pw' }
  // A run the orchestrator just started: the CLI is at Intent with the empty ledgers `state init` writes, and the spec
  // folder holds nothing yet. `extra` adds or replaces files (null removes one), `store` trusts event files.
  type Begin = { next?: string; intent?: string | null; extra?: Record<string, string | null>; store?: Record<string, unknown> }
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
    const w = world(on, files, { fakeCli: true, projectRoot: '/repo', ...(o.store ? { store: o.store } : {}) })
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
    expect(await write()).toMatch(/Intent phase/)
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
    expect((await api.tool.call({ tool: 'Write', file_path: 'app.py', content: 'x' })).deny).toMatch(/Intent phase/)
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
    const run = (phase: (typeof PHASES)[number], extra: Partial<RuleContext>, command = 'scripts/temper state clear') =>
      evaluate(stateAt(phase), { ...ctx, ...extra }, { tool: 'Bash', input: { command } })
    expect('allow' in run('intent', { nothingToLose: true })).toBe(true)
    expect('deny' in run('intent', {})).toBe(true)
    expect('deny' in run('intent', { nothingToLose: false })).toBe(true)
    expect('deny' in run('intent', { nothingToLose: true }, 'scripts/temper state archive')).toBe(true)
    for (const phase of ['plan', 'build', 'review', 'check', 'fix'] as const) expect('deny' in run(phase, { nothingToLose: true }), phase).toBe(true)
  })

  test('the rule: a run whose own record went past its start is not cleared, even back at Intent', () => {
    const ctx: RuleContext = { specDir: SPEC, planFiles: [], nothingToLose: true }
    const clear = { tool: 'Bash', input: { command: 'scripts/temper state clear' } }
    const back: Draft = { type: 'back', to: 'intent', reason: 'wrong problem', ...person }
    const skip: Draft = { type: 'override', phase: 'intent', reason: 'later', ...person }
    expect('deny' in evaluate(stateAt('intent', [{ type: 'advance', from: 'intent', to: 'plan', ...person }, back]), ctx, clear)).toBe(true)
    expect('deny' in evaluate(stateAt('plan', [back]), ctx, clear)).toBe(true)
    // A skip of Intent that the CLI has not followed yet: the mod's phase is the CLI's (Intent), its record holds the skip.
    const skipped = { ...stateAt('intent', [skip]), phase: 'intent' as const }
    expect('deny' in evaluate(skipped, ctx, clear)).toBe(true)
  })

  // Final review: deleting intent.md no longer opens the clear. A run that left Intent and came back to it (a loop back)
  // keeps its plan, its verdicts and its record: the agent may delete intent.md at Intent, and the clear stays refused.
  test('a loop back to Intent, then intent.md deleted, then state clear: refused, and the commit stays blocked', async ($, on) => {
    const items: Array<[string, string]> = [
      eventFile({ type: 'start', slug: 'pw', title: 'Password reset', phase: 'intent', origin: 'system' }, 1_000, 's', 1),
      eventFile({ type: 'advance', from: 'intent', to: 'plan', ...person }, 2_000, 's', 2),
      eventFile({ type: 'advance', from: 'plan', to: 'build', ...person }, 3_000, 's', 3),
      eventFile({ type: 'back', to: 'intent', reason: 'wrong problem', ...person }, 4_000, 's', 4),
    ]
    const gates = { intent: { verdict: 'PASS', ts: LATER }, plan: { verdict: 'PASS', ts: LATER }, build: { verdict: 'FAIL', ts: LATER } }
    const { w, api } = await begin($, on, {
      intent: INTENT,
      store: await trusted(items),
      extra: {
        ...Object.fromEntries(items),
        '.temper/build-state.json': JSON.stringify({ ...FRESH, stage: 'plan_complete' }),
        '.temper/gates.json': JSON.stringify(gates),
        [`${SPEC}/plan.md`]: PLAN,
        [`${SPEC}/tasks.md`]: TASKS,
      },
    })
    expect(await sh(api, 'git add -A && git commit -m unreviewed')).toMatch(/commit blocked/)
    // At Intent the intent may be rewritten, and removed: the world's rm is a stub, so the test removes the file.
    expect(await sh(api, `rm ${SPEC}/intent.md`)).toBeUndefined()
    w.files.delete(`${SPEC}/intent.md`)
    expect(await sh(api, CLEAR)).toMatch(/do not clear or archive/)
    expect(await sh(api, 'scripts/temper state clear')).toMatch(/do not clear or archive/)
    expect(w.files.has('.temper/build-state.json')).toBe(true)
    expect(await sh(api, 'git add -A && git commit -m unreviewed')).toMatch(/commit blocked/)
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

  test('a run whose record holds a step back is kept, also when the CLI files look fresh', async ($, on) => {
    const items: Array<[string, string]> = [
      eventFile({ type: 'start', slug: 'pw', title: 'Password reset', phase: 'intent', origin: 'system' }, 1_000, 's', 1),
      eventFile({ type: 'advance', from: 'intent', to: 'plan', ...person }, 2_000, 's', 2),
      eventFile({ type: 'back', to: 'intent', reason: 'wrong problem', ...person }, 3_000, 's', 3),
    ]
    const { api } = await begin($, on, { store: await trusted(items), extra: Object.fromEntries(items) })
    expect(await sh(api, CLEAR)).toMatch(/do not clear or archive/)
  })
})
