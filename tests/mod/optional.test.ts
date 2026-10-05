import { describe, expect, test } from 'claude-code/testing'

import { runFiles } from './run-files'
import { world } from './world'

const START = { cwd: '/repo', surface: null, isInteractive: false } as const

const STEP = { turnId: 't1', index: 0, model: 'opus', messageCount: 3 } as const

const SPAWN = {
  tool_use_id: 'u1',
  prompt: 'review it',
  description: 'review',
  subagentType: 'temper:temper-review',
  provider: { plugin: 'temper', tier: 'user' },
  parentModel: 'opus',
} as const

describe('per phase model and effort (turn.step)', () => {
  const seen: Array<{ model: string; effort?: unknown }> = []

  test('empty phaseModels passes the step through untouched', async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    seen.length = 0
    on('turn.step', async function* ($2, e) {
      seen.push({ model: e.model, effort: e.effort })
      return { turnId: e.turnId, index: e.index, answer: '', toolUses: [], stopReason: 'end_turn' } as never
    })
    await $.session.start(START)
    const stream = $.turn.step(STEP as never)
    for await (const _chunk of stream) void _chunk
    expect(seen).toEqual([{ model: 'opus', effort: undefined }])
  })

  test('build=sonnet:high picks the model and effort in Build only', { options: { phaseModels: 'build=sonnet:high, plan=haiku' } }, async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    seen.length = 0
    on('turn.step', async function* ($2, e) {
      seen.push({ model: e.model, effort: e.effort })
      return { turnId: e.turnId, index: e.index, answer: '', toolUses: [], stopReason: 'end_turn' } as never
    })
    await $.session.start(START)
    for await (const _chunk of $.turn.step(STEP as never)) void _chunk
    for await (const _chunk of $.turn.step({ ...STEP, agentId: 'sub' } as never)) void _chunk
    expect(seen).toEqual([
      { model: 'sonnet', effort: 'high' },
      { model: 'opus', effort: undefined },
    ])
  })

  test('a phase with no entry, or no active run, is left alone', { options: { phaseModels: 'review=sonnet' } }, async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    seen.length = 0
    on('turn.step', async function* ($2, e) {
      seen.push({ model: e.model })
      return { turnId: e.turnId, index: e.index, answer: '', toolUses: [], stopReason: 'end_turn' } as never
    })
    await $.session.start(START)
    for await (const _chunk of $.turn.step(STEP as never)) void _chunk
    expect(seen).toEqual([{ model: 'opus' }])
  })

  test('with the mod inert the step is untouched', { options: { phaseModels: 'build=sonnet' } }, async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }), { version: '2.1.286' })
    seen.length = 0
    on('turn.step', async function* ($2, e) {
      seen.push({ model: e.model })
      return { turnId: e.turnId, index: e.index, answer: '', toolUses: [], stopReason: 'end_turn' } as never
    })
    await $.session.start(START)
    for await (const _chunk of $.turn.step(STEP as never)) void _chunk
    expect(seen).toEqual([{ model: 'opus' }])
  })
})

describe('reviewer model (agent.spawn)', () => {
  test('empty reviewerModel passes every spawn through', async ($, on) => {
    world(on, {})
    on('agent.spawn', ($2, e) => ({ model: e.model ?? 'inherit' }))
    expect((await $.agent.spawn(SPAWN as never)).model).toBe('inherit')
  })

  test('the Temper review agent runs on reviewerModel; other agents do not', { options: { reviewerModel: 'opus' } }, async ($, on) => {
    world(on, {})
    on('agent.spawn', ($2, e) => ({ model: e.model ?? 'inherit' }))
    expect((await $.agent.spawn(SPAWN as never)).model).toBe('opus')
    expect((await $.agent.spawn({ ...SPAWN, subagentType: 'temper-review' } as never)).model).toBe('opus')
    expect((await $.agent.spawn({ ...SPAWN, subagentType: 'Explore' } as never)).model).toBe('inherit')
    expect((await $.agent.spawn({ ...SPAWN, subagentType: 'temper:temper-build' } as never)).model).toBe('inherit')
  })
})
