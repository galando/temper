import { describe, expect, test } from 'claude-code/testing'

import { SPEC, questionOf, runFiles } from './run-files'
import { viewText, world } from './world'

const START = { cwd: '/repo', surface: null, isInteractive: false } as const

// 9.6.2: the plugin directory holds a mod that writes files at a path it cannot read. The mod writes
// no file: its records are kept in the plugin store (the report under `vf:<path>`).
describe('the mod writes no file', () => {
  test('a decision and the report are kept in the store; no fs.write is made', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'review', gates: { review: 'FAIL' } }), { answers: [{ label: 'Override and continue', note: 'reviewer is on leave' }] })
    await $.session.start(START)
    await $.tool.call({ tool: 'AskUserQuestion', questions: [{ ...questionOf(viewText(w) ?? ''), multiSelect: false }] } as never)
    const report = await $.command.run({ command: 'temper', args: 'report', origin: { kind: 'composer' } } as never)
    expect(report.text).toContain('# Temper report')
    expect(w.fsWrites).toEqual([])
    // ADR 0012: the decisions are kept per run (the CLI's run id), the report as a kept text.
    expect(Array.isArray(w.store['dec:run-pw'])).toBe(true)
    expect(Object.keys(w.store)).toContain('vf:/repo/.temper/report.md')
    const timeline = await $.command.run({ command: 'temper', args: 'timeline', origin: { kind: 'composer' } } as never)
    expect(timeline.text ?? '').toContain('review: Override and continue (reviewer is on leave)')
  })

  test('the store keeps the decisions of the last 40 runs: the oldest run is dropped', async ($, on) => {
    const store: Record<string, unknown> = {}
    const old = Array.from({ length: 40 }, (_, i) => `old-${i}`)
    for (const run of old) store[`dec:${run}`] = []
    store.decruns = old
    const w = world(on, runFiles({ nextStage: 'review', gates: { review: 'FAIL' } }), { store, answers: [{ label: 'Override and continue', note: 'reviewer is on leave' }] })
    await $.session.start(START)
    await $.tool.call({ tool: 'AskUserQuestion', questions: [{ ...questionOf(viewText(w) ?? ''), multiSelect: false }] } as never)
    const runs = w.store.decruns as string[]
    expect(runs.length).toBe(40)
    expect(runs.at(-1)).toBe('run-pw')
    expect(w.store['dec:old-0']).toBeUndefined()
    expect(w.store['dec:old-1']).toEqual([])
  })
})
