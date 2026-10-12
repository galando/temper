// A new run on a spec folder that held an earlier one (found live): `state init` again on the same slug, with the
// earlier run's record still kept. The earlier run's choices must not count in the new one: no approval of its Plan
// (the Plan agent's `state set complexity` was refused), no move of it waiting to be recorded (the bar at the new Intent
// gate offered only "Record my choice", and that sent `continue plan`, which the guard refused every time).
import { describe, expect, test } from 'claude-code/testing'

import { evaluate } from '../../hooks/temper-mod/core/rules'
import { ONLY_USER } from '../../hooks/temper-mod/core/machine'
import type { Draft } from '../../hooks/temper-mod/core/events'
import { SPEC, eventFile, runFiles, trusted } from './run-files'
import { person, stateAt } from './helpers'
import { world } from './world'
import type { World } from './world'

const START = { cwd: '/repo', surface: null, isInteractive: false } as const
const BAND = { hasSurvey: false, isWorking: false, maxRows: 12, bodyColumns: 100, scroll: { offset: 0, bodyRows: 12 }, view: {} } as const
type Mounted = { press: (a: { key: string }) => Promise<void>; drawn: () => Promise<unknown> }
type Api = {
  ui: { mount: (a: unknown) => Promise<Mounted> }
  session: { start: (a: unknown) => Promise<unknown> }
  command: { run: (a: unknown) => Promise<{ text?: string }> }
  tool: { call: (a: unknown) => Promise<{ deny?: string }> }
}
const CLI = '/home/u/.claude/plugins/temper/scripts/temper'
const p = { origin: 'person', author: 'user' } as const

const band = (api: Api) => api.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', props: BAND })
const bar = async (api: Api) => JSON.stringify(await (await band(api)).drawn())
const sh = async (api: Api, command: string) => (await api.tool.call({ tool: 'Bash', command })).deny
const cliNext = (w: World) => (JSON.parse(w.files.get('.temper/build-state.json') ?? '{}') as { next_stage?: string }).next_stage

// The earlier run: the mod's bootstrap start, its Intent and Plan approvals mirrored (spent), and a Continue at Build
// whose mirror never ran (the run was ended before it). `unspent` adds a Continue at Plan that was never mirrored.
async function earlier(on: Parameters<typeof world>[0], unspent: Draft[] = []): Promise<World> {
  const spent: Draft[] = [
    { type: 'advance', from: 'intent', to: 'plan', ...p },
    { type: 'advance', from: 'plan', to: 'build', ...p },
  ]
  const head = eventFile({ type: 'start', slug: 'pw', title: 'Password reset', phase: 'intent', origin: 'system' }, 0, 'bootstrap', 1)
  const used = spent.map((d, i) => eventFile(d, 1000 + i, 'old', i + 1))
  const open = unspent.map((d, i) => eventFile(d, 2000 + i, 'old', 10 + i))
  const all = [head, ...used, ...open]
  const store = await trusted(all)
  for (const [path] of used) store[`used:${(path.split('/').pop() ?? '').replace(/\.json$/, '')}`] = 1
  // `state init` again: the CLI is at Intent with nothing completed, and its ledgers are new. The intent check passed.
  const files = { ...runFiles({ nextStage: 'intent', gates: { intent: 'PASS' } }), ...Object.fromEntries(all) }
  files['.temper/build-state.json'] = JSON.stringify({ stage: 'started', spec: 'pw', spec_path: SPEC, next_stage: 'intent', command: 'temper', branch: 'feature/pw' })
  files['/repo/.git/HEAD'] = 'ref: refs/heads/main\n'
  return world(on, files, { fakeCli: true, projectRoot: '/repo', store })
}

describe('a new run on a spec folder that held an earlier run', () => {
  test('the Intent gate offers Continue to Plan, not a choice of the earlier run to record', async ($, on) => {
    const api = $ as unknown as Api
    const w = await earlier(on, [{ type: 'advance', from: 'plan', to: 'build', ...p }])
    await api.session.start(START)
    const text = await bar(api)
    expect(text).toContain('Step 1 of 6: Intent')
    expect(text).toContain('1 Continue to Plan. The intent is checked.')
    expect(text).not.toContain('did not go through yet')
    // Continue hands over the Intent: never the earlier run's `continue plan`.
    await (await band(api)).press({ key: 'action-continue' })
    expect(w.commandRuns.map(r => r.args)).toEqual(['continue intent'])
    // The orchestrator's On Continue steps of Intent pass, and the CLI moves to Plan.
    expect(await sh(api, 'git add .temper/specs/pw/')).toBeUndefined()
    expect(await sh(api, 'git commit -m "docs(intent): accept pw"')).toBeUndefined()
    expect(await sh(api, `${CLI} state advance intent_complete plan`)).toBeUndefined()
    expect(cliNext(w)).toBe('plan')
    // The earlier run's unrecorded Continue at Plan does not approve the new plan.
    expect(await sh(api, `${CLI} state advance plan_complete build`)).toBe(ONLY_USER)
  })

  test('the Plan agent records the complexity of the new run', async ($, on) => {
    const api = $ as unknown as Api
    const w = await earlier(on)
    await api.session.start(START)
    await (await band(api)).press({ key: 'action-continue' })
    expect(await sh(api, `${CLI} state advance intent_complete plan`)).toBeUndefined()
    expect(cliNext(w)).toBe('plan')
    expect(await sh(api, `${CLI} state set complexity simple`)).toBeUndefined()
    expect(await sh(api, `"${CLI}" state set complexity "medium"`)).toBeUndefined()
  })

  test('the new run starts once: a second load writes no second start, and the new run keeps its own choices', { options: { moveCooldownMs: 0 } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = await earlier(on)
    await api.session.start(START)
    const starts = () => [...w.files.entries()].filter(([path, t]) => path.startsWith(`${SPEC}/events/`) && (JSON.parse(t) as { type?: string }).type === 'start').length
    expect(starts()).toBe(2)
    await api.command.run({ command: 'temper:temper', args: 'status', origin: { kind: 'composer' } })
    expect(starts()).toBe(2)
    // The person's Continue in the new run waits while the CLI is still at `started`: it is kept, and key 1 records it.
    await (await band(api)).press({ key: 'action-continue' })
    await api.command.run({ command: 'temper:temper', args: 'status', origin: { kind: 'composer' } })
    expect(starts()).toBe(2)
    const text = await bar(api)
    expect(text).toContain('Your move to Plan did not go through yet. Press 1 to finish it.')
    expect(text).toContain('1 Continue to Plan. Not recorded yet. Temper records it and goes on.')
  })
})

describe('a choice the CLI cannot record from where it is waits for nothing', () => {
  test('a Continue out of Plan while the CLI is back at Intent (moved from a shell) is not offered to record', async ($, on) => {
    const api = $ as unknown as Api
    const head = eventFile({ type: 'start', slug: 'pw', title: 'Password reset', phase: 'intent', origin: 'system' }, 0, 'bootstrap', 1)
    const spent = eventFile({ type: 'advance', from: 'intent', to: 'plan', ...p }, 1000, 's', 1)
    const open = eventFile({ type: 'advance', from: 'plan', to: 'build', ...p }, 2000, 's', 2)
    const store = await trusted([head, spent, open])
    store[`used:${(spent[0].split('/').pop() ?? '').replace(/\.json$/, '')}`] = 1
    const files = { ...runFiles({ nextStage: 'intent', gates: { intent: 'PASS' } }), ...Object.fromEntries([head, spent, open]) }
    files['.temper/build-state.json'] = JSON.stringify({ stage: 'plan_complete', spec: 'pw', spec_path: SPEC, next_stage: 'intent', command: 'temper' })
    world(on, files, { fakeCli: true, projectRoot: '/repo', store })
    await api.session.start(START)
    const text = await bar(api)
    expect(text).toContain('Step 1 of 6: Intent')
    expect(text).not.toContain('did not go through yet')
    expect(text).toContain('1 Continue to Plan. The intent is checked.')
  })
})

describe('a decision call chained with a commit spends its decision', () => {
  test('state advance and an artifact commit in one command: the decision is used once', () => {
    const s = stateAt('plan', [], { plan: { verdict: 'PASS', ts: Date.now() + 60_000 } })
    const decisions = [{ id: 'd1', kind: 'advance' as const, phase: 'plan' }]
    const command = `${CLI} state advance plan_complete build && git add .temper/specs/pw/ && git commit -m "docs(plan): approve plan"`
    const r = evaluate(s, { specDir: SPEC, planFiles: [], humanDecisions: decisions, commit: { stagedSpecsOnly: true, checkpoint: false } }, { tool: 'Bash', input: { command } })
    expect(r).toEqual({ allow: true, consume: 'advance', eventId: 'd1', eventIds: ['d1'] })
    // The commit rule still applies to such a command.
    const blocked = evaluate(s, { specDir: SPEC, planFiles: [], humanDecisions: decisions, commit: { stagedSpecsOnly: false, checkpoint: false } }, { tool: 'Bash', input: { command } })
    expect('deny' in blocked && blocked.deny.startsWith('Temper: commit blocked.')).toBe(true)
    void person
  })
})

describe('at Review: the move to Check while Claude carries it out, and when it did not go through', () => {
  const atReview = (on: Parameters<typeof world>[0], store: Record<string, unknown> = {}, extra: Record<string, string> = {}) => {
    const files = { ...runFiles({ nextStage: 'review', gates: { review: 'PASS' } }), ...extra }
    files['.temper/build-state.json'] = JSON.stringify({ stage: 'build_complete', spec: 'pw', spec_path: SPEC, next_stage: 'review', command: 'temper' })
    return world(on, files, { fakeCli: true, projectRoot: '/repo', store })
  }
  const working = async (api: Api) => JSON.stringify(await (await api.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', props: { ...BAND, isWorking: true } })).drawn())

  test('while Claude works the line says Claude is finishing it, and pressing 1 hands nothing over twice', { options: { moveCooldownMs: 0 } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = atReview(on)
    await api.session.start(START)
    await (await band(api)).press({ key: 'action-continue' })
    expect(w.commandRuns.map(r => r.args)).toEqual(['continue review'])
    const text = await working(api)
    expect(text).toContain('Claude is finishing your move to Check.')
    expect(text).not.toContain('Temper state')
    // Key 1 now says the move, and while Claude works it waits.
    expect(text).toContain('1 Continue to Check. Not recorded yet. Temper records it and goes on.')
    await (await api.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', props: { ...BAND, isWorking: true } })).press({ key: 'action-record' })
    expect(w.commandRuns.map(r => r.args)).toEqual(['continue review'])
    // The orchestrator's On Continue step passes the guard and the line goes.
    expect(await sh(api, `${CLI} state advance review_complete check`)).toBeUndefined()
    expect(cliNext(w)).toBe('check')
    expect(await bar(api)).not.toContain('did not go through')
  })

  test('a move that did not go through says so in plain words, and one press of 1 finishes it', { options: { moveCooldownMs: 0 } }, async ($, on) => {
    const api = $ as unknown as Api
    const w = atReview(on)
    await api.session.start(START)
    await (await band(api)).press({ key: 'action-continue' })
    // The orchestrator stopped before its `state advance` (nothing ran).
    const text = await bar(api)
    expect(text).toContain('Your move to Check did not go through yet. Press 1 to finish it.')
    await (await band(api)).press({ key: 'action-record' })
    expect(w.commandRuns.map(r => r.args)).toEqual(['continue review', 'continue review'])
    expect(await sh(api, `${CLI} state advance review_complete check`)).toBeUndefined()
    expect(cliNext(w)).toBe('check')
    expect(await bar(api)).not.toContain('did not go through')
  })

  test('a Continue at Review of an earlier run on the same spec folder does not wait in this run', async ($, on) => {
    const api = $ as unknown as Api
    const head = eventFile({ type: 'start', slug: 'pw', title: 'Password reset', phase: 'intent', origin: 'system' }, 0, 'bootstrap', 1)
    const old = [
      eventFile({ type: 'advance', from: 'intent', to: 'plan', ...p }, 1000, 'old', 1),
      eventFile({ type: 'advance', from: 'plan', to: 'build', ...p }, 1001, 'old', 2),
      eventFile({ type: 'advance', from: 'build', to: 'review', ...p }, 1002, 'old', 3),
    ]
    // Never mirrored: the earlier run was ended after this press.
    const unsent = eventFile({ type: 'advance', from: 'review', to: 'check', ...p }, 1003, 'old', 4)
    // The new run: its own start (written when it began) and its own moves, mirrored, up to Review.
    const fresh = eventFile({ type: 'start', slug: 'pw', title: 'Password reset', phase: 'intent', origin: 'system' }, 5000, 'newrun', 1)
    const mine = [
      eventFile({ type: 'advance', from: 'intent', to: 'plan', ...p }, 6000, 'new', 1),
      eventFile({ type: 'advance', from: 'plan', to: 'build', ...p }, 6001, 'new', 2),
      eventFile({ type: 'advance', from: 'build', to: 'review', ...p }, 6002, 'new', 3),
    ]
    const all = [head, ...old, unsent, fresh, ...mine]
    const store = await trusted(all)
    for (const [path] of [...old, ...mine]) store[`used:${(path.split('/').pop() ?? '').replace(/\.json$/, '')}`] = 1
    atReview(on, store, Object.fromEntries(all))
    await api.session.start(START)
    const text = await bar(api)
    expect(text).not.toContain('did not go through')
    expect(text).toContain('1 Continue to Check. The review has no open problems.')
    // Nor does it approve this run's move to Check.
    expect(await sh(api, `${CLI} state advance review_complete check`)).toBeUndefined()
  })
})
