import { describe, expect, test } from 'claude-code/testing'

import { runFiles } from './run-files'
import { COMPOSE, cliTo, world } from './world'


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
    expect(text).toContain('Phase: Build · Intent: "Password reset by email"')
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
    expect(text).toBe('Temper enforcement: active\nPhase: none. No Temper run is active.')
  })

  test('a load failure leaves the engine sections untouched', async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }), { brokenList: true })
    const { sections } = await $.prompt.compose(COMPOSE)
    // Not inert (the version is fine) but no run could be read: the section says so.
    expect(sections.at(-1)?.text).toContain('Temper enforcement: active')
  })
})

describe('the run comes back after /clear from the CLI files and the kept decisions', () => {
  test('a reload on classic SessionStart reads the stage from the CLI and the answer from the store', async ($, on) => {
    // While the session was cleared the person answered Continue at the plan gate; the mod kept it for this run and step.
    const decision = { id: 'd1', run: 'run-pw', step: 3, stage: 'plan', ts: Date.now(), kind: 'gate', label: 'Continue to Build (Recommended)', move: 'approve', calls: [], steps: [], reason: '' }
    const w = world(on, runFiles({ nextStage: 'plan', gates: { plan: 'PASS' } }), { store: { 'dec:run-pw': [decision] } })
    await $.classic.SessionStart({ source: 'clear' })
    const text = (await $.prompt.compose(COMPOSE)).sections.at(-1)?.text ?? ''
    expect(text).toContain('Phase: Plan')
    expect(text).toContain('carry out the calls of that option')
    // Once the CLI moved on, the answer belongs to an earlier step: Build has its own.
    cliTo(w, 'build')
    const d = JSON.parse(w.files.get('.temper/build-state.json') ?? '{}') as Record<string, unknown>
    w.files.set('.temper/build-state.json', JSON.stringify({ ...d, step: 4 }))
    await $.classic.SessionStart({ source: 'clear' })
    const after = (await $.prompt.compose(COMPOSE)).sections.at(-1)?.text ?? ''
    expect(after).toContain('Phase: Build')
    expect(after).not.toContain('carry out the calls of that option')
  })
})
