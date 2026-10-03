import { describe, expect, test } from 'claude-code/testing'

import { SPEC, runFiles } from './run-files'
import { denyText, world } from './world'

const edit = (path: string) => ({ tool: 'Edit', file_path: path, old_string: 'a', new_string: 'b' }) as const

const eventTypes = (files: Map<string, string>): string[] =>
  [...files.entries()]
    .filter(([p]) => p.startsWith(`${SPEC}/events/`))
    .map(([, t]) => JSON.parse(t) as { type: string; choice?: string; reason?: string; path?: string; origin?: string })
    .filter(e => e.type === 'drift' || e.type === 'driftUsed')
    .map(e => `${e.type}:${e.choice ?? ''}:${e.reason ?? ''}:${e.path ?? ''}:${e.origin}`)

describe('scope drift in Build', () => {
  test('asks the three choices and "Add to plan" lets the edit through and is logged', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }), { answers: ['Add to plan'] })
    const r = await $.tool.call(edit('src/billing.ts'))
    expect(denyText(r)).toBe('')
    expect(r.text).toBe('stub ran')
    expect(w.asked[0]).toContain('src/billing.ts')
    expect(eventTypes(w.files)).toEqual(['drift:add::src/billing.ts:person'])
    // The path is in the plan now: the next edit is not asked about again.
    expect((await $.tool.call(edit('src/billing.ts'))).text).toBe('stub ran')
    expect(w.asked).toHaveLength(1)
  })

  test('"Revert" refuses the edit, logs it and tells Claude to restore the file', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }), { answers: ['Revert'] })
    const r = await $.tool.call(edit('src/billing.ts'))
    expect(denyText(r)).toContain('scope drift')
    expect(denyText(r)).toContain('chose to revert')
    expect(eventTypes(w.files)).toEqual(['drift:revert::src/billing.ts:person'])
    expect(denyText(r)).toContain('restore src/billing.ts to its committed state')
    // Revert alone does not allow the path: the next edit asks again.
    w.answers.push('Revert')
    expect('deny' in (await $.tool.call(edit('src/billing.ts')))).toBe(true)
    expect(w.asked).toHaveLength(2)
  })

  test('"Allow once" with a reason lets exactly one edit through', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }), { answers: ['Allow once', 'prod incident'] })
    expect((await $.tool.call(edit('src/hotfix.ts'))).text).toBe('stub ran')
    expect(eventTypes(w.files)).toEqual(['drift:allow-once:prod incident:src/hotfix.ts:person', 'driftUsed:::src/hotfix.ts:system'])
    // The allowance is spent: the next edit on that path asks again.
    expect(w.asked).toHaveLength(2)
    expect('deny' in (await $.tool.call(edit('src/hotfix.ts')))).toBe(true)
    expect(w.asked).toHaveLength(3)
  })

  test('"Allow once" with an empty reason writes nothing and asks again', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }), { answers: ['Allow once', '   ', '', ''] })
    const r = await $.tool.call(edit('src/hotfix.ts'))
    expect(denyText(r)).toContain('scope drift')
    expect(eventTypes(w.files)).toEqual([])
    expect(w.asked.length).toBe(4)
  })

  test('with nobody to ask, the edit is denied with the instructions and /temper drift decides', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    const r = await $.tool.call(edit('src/billing.ts'))
    expect(denyText(r)).toContain('add to plan, revert, or allow once with a reason')
    expect(denyText(r)).toContain('/temper drift add|revert|allow <reason>')
    expect(eventTypes(w.files)).toEqual([])
  })
})
