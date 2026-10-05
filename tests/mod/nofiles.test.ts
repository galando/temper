import { describe, expect, test } from 'claude-code/testing'

import { SPEC, runFiles } from './run-files'
import { world } from './world'

const START = { cwd: '/repo', surface: null, isInteractive: false } as const

// 9.6.2: the plugin directory holds a mod that writes files at a path it cannot read. The mod writes
// no file: its records are kept in the plugin store (`vf:<path>`), and reads see them as files.
describe('the mod writes no file', () => {
  test('a decision and the report are kept in the store; no fs.write is made', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'review', gates: { review: 'FAIL' } }))
    await $.session.start(START)
    await $.command.run({ command: 'temper', args: 'override reviewer is on leave', origin: { kind: 'composer' } } as never)
    const report = await $.command.run({ command: 'temper', args: 'report', origin: { kind: 'composer' } } as never)
    expect(report.text).toContain('# Temper report')
    expect(w.fsWrites).toEqual([])
    const kept = Object.keys(w.store).filter(k => k.startsWith('vf:'))
    expect(kept.some(k => k.startsWith(`vf:/repo/${SPEC}/events/`))).toBe(true)
    expect(kept).toContain('vf:/repo/.temper/report.md')
    // The kept event is read back as part of the run: the timeline names the skip.
    const timeline = await $.command.run({ command: 'temper', args: 'timeline', origin: { kind: 'composer' } } as never)
    expect((timeline.text ?? '').toLowerCase()).toContain('review')
  })

  test('the store keeps at most 40 folders: the oldest folder is dropped', async ($, on) => {
    const store: Record<string, unknown> = {}
    const old = Array.from({ length: 40 }, (_, i) => `/other/p${i}/.temper/specs/x/events`)
    for (const dir of old) {
      store[`vfdir:${dir}`] = ['a.json']
      store[`vf:${dir}/a.json`] = '{}'
    }
    store.vfdirs = old
    const w = world(on, runFiles({ nextStage: 'review', gates: { review: 'FAIL' } }), { store })
    await $.session.start(START)
    await $.command.run({ command: 'temper', args: 'override reviewer is on leave', origin: { kind: 'composer' } } as never)
    const dirs = w.store.vfdirs as string[]
    expect(dirs.length).toBe(40)
    expect(dirs.at(-1)).toBe(`/repo/${SPEC}/events`)
    expect(w.store[`vfdir:${old[0]}`]).toBeUndefined()
    expect(w.store[`vf:${old[0]}/a.json`]).toBeUndefined()
    expect(w.store[`vf:${old[1]}/a.json`]).toBe('{}')
  })
})
