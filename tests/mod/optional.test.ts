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

describe('reviewer model (turn.step in the review agent)', () => {
  const seen: Array<{ model: string; agentId?: string }> = []
  const AGENTS = [
    { id: 'rev', type: 'temper:temper-review', description: 'review', status: 'running' },
    { id: 'rev2', type: 'temper-review', description: 'review', status: 'running' },
    { id: 'exp', type: 'Explore', description: 'look', status: 'running' },
    { id: 'bld', type: 'temper:temper-build', description: 'build', status: 'running' },
  ]
  const listen = (on: Parameters<typeof world>[0]) => {
    seen.length = 0
    on('agent.list', () => ({ value: AGENTS as never }))
    on('turn.step', async function* ($2, e) {
      seen.push({ model: e.model, agentId: e.agentId })
      return { turnId: e.turnId, index: e.index, answer: '', toolUses: [], stopReason: 'end_turn' } as never
    })
  }

  test('empty reviewerModel leaves every step alone', async ($, on) => {
    world(on, {})
    listen(on)
    for await (const _chunk of $.turn.step({ ...STEP, agentId: 'rev' } as never)) void _chunk
    expect(seen).toEqual([{ model: 'opus', agentId: 'rev' }])
  })

  test('the Temper review agent runs on reviewerModel; other agents and the main loop do not', { options: { reviewerModel: 'haiku' } }, async ($, on) => {
    world(on, {})
    listen(on)
    for (const agentId of ['rev', 'rev2', 'exp', 'bld', 'gone', undefined]) {
      for await (const _chunk of $.turn.step({ ...STEP, ...(agentId ? { agentId } : {}) } as never)) void _chunk
    }
    expect(seen.map(s => s.model)).toEqual(['haiku', 'haiku', 'opus', 'opus', 'opus', 'opus'])
  })

  test('a spawn passes through unchanged', { options: { reviewerModel: 'haiku' } }, async ($, on) => {
    world(on, {})
    const spawned: unknown[] = []
    on('agent.spawn', ($2, e) => {
      spawned.push(e)
      return { model: e.model ?? 'inherit', agentId: 'rev' }
    })
    expect((await $.agent.spawn(SPAWN as never)).model).toBe('inherit')
    expect(spawned).toEqual([expect.objectContaining({ subagentType: 'temper:temper-review' })])
    expect((spawned[0] as { model?: string }).model).toBeUndefined()
  })
})
