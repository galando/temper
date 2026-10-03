import { describe, expect, test } from 'claude-code/testing'

import { eventFile, runFiles, trusted } from './run-files'
import { COMPOSE, world } from './world'


describe('prompt.compose', () => {
  test('appends one session section "temper:phase" last, with the exact lines', async ($, on) => {
    world(on, runFiles({ nextStage: 'build', passedCriteria: ['AC-01', 'AC-03'] }))
    const { sections } = await $.prompt.compose(COMPOSE)
    const last = sections[sections.length - 1]
    expect(sections.filter(s => s.id === 'temper:phase')).toHaveLength(1)
    expect(last?.id).toBe('temper:phase')
    expect(last?.scope).toBe('session')
    const text = last?.text ?? ''
    expect(text).toContain('Temper enforcement: active')
    expect(text).toContain('Phase: Build (task 3 of 7) · Intent: "Password reset by email"')
    expect(text).toContain('Criteria: 2 of 5 passed (AC-01, AC-03)')
    expect(text).toContain('Next: ')
    // The engine's own sections are kept, ahead of ours.
    expect(sections[0]?.id).toBe('intro')
  })

  test('the same section is still last after compaction', async ($, on) => {
    world(on, runFiles({ nextStage: 'build', passedCriteria: ['AC-01', 'AC-03'] }))
    on('session.compact', () => ({ messages: [{ role: 'user', text: 'summary', toolUses: [] }] }) as never)
    const before = await $.prompt.compose(COMPOSE)
    await $.session.compact({ trigger: 'manual', messages: [] })
    const after = await $.prompt.compose(COMPOSE)
    expect(after.sections[after.sections.length - 1]).toEqual(before.sections[before.sections.length - 1])
  })

  test('enforcement off says UI only', { options: { enforcement: 'off' } }, async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    const text = (await $.prompt.compose(COMPOSE)).sections.at(-1)?.text ?? ''
    expect(text.split('\n')[0]).toBe('Temper enforcement: off (UI only)')
  })

  test('with no run the marker is still there, saying no run is active', async ($, on) => {
    world(on, {})
    const text = (await $.prompt.compose(COMPOSE)).sections.at(-1)?.text ?? ''
    expect(text).toBe('Temper enforcement: active\nPhase: none (no active Temper run)')
  })

  test('a load failure leaves the engine sections untouched', async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }), { brokenList: true })
    const { sections } = await $.prompt.compose(COMPOSE)
    // Not inert (the version is fine) but no run could be read: the section says so.
    expect(sections.at(-1)?.text).toContain('Temper enforcement: active')
  })
})

describe('state comes back after /clear from the event files', () => {
  test('a reload on classic SessionStart folds the events the mod wrote', async ($, on) => {
    // While the session was cleared another load wrote an approval; its id is in the store.
    const [path, text] = eventFile({ type: 'advance', from: 'intent', to: 'plan', origin: 'person', author: 'galando' }, Date.now() + 5000, 'own', 2)
    const id = path.split('/').pop()?.replace('.json', '') ?? ''
    const w = world(on, runFiles({ nextStage: 'intent' }), { store: await trusted([[path, text]]) })
    const first = (await $.prompt.compose(COMPOSE)).sections.at(-1)?.text ?? ''
    expect(first).toContain('Phase: Intent')
    w.files.set(path, text)
    await $.classic.SessionStart({ source: 'clear' })
    const second = (await $.prompt.compose(COMPOSE)).sections.at(-1)?.text ?? ''
    expect(second).toContain('Phase: Plan')
  })
})
