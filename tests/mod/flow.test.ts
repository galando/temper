// One flow, two views: the buttons run the same choices as the orchestrator's questions, and the
// orchestrator (commands/temper.md) stays the driver of the stages.
import { describe, expect, test } from 'claude-code/testing'

import { GATE_MESSAGE } from '../../hooks/temper-mod/core/section'
import { SPEC, runFiles } from './run-files'
import { COMPOSE, world } from './world'

const START = { cwd: '/repo', surface: null, isInteractive: false } as const
const BAND = { hasSurvey: false, isWorking: false, maxRows: 12, bodyColumns: 100, scroll: { offset: 0, bodyRows: 12 }, view: {} } as const
type Mounted = { press: (a: { key: string }) => Promise<void>; find: (a: { key: string }) => Promise<unknown>; drawn: () => Promise<unknown> }
type Mounter = { ui: { mount: (a: unknown) => Promise<Mounted> } }
const band = ($: unknown, props: Record<string, unknown> = {}): Promise<Mounted> =>
  ($ as Mounter).ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', props: { ...BAND, ...props } })

const events = (w: ReturnType<typeof world>) => [...w.files.entries()].filter(([p]) => p.startsWith(`${SPEC}/events/`)).map(([, t]) => JSON.parse(t) as Record<string, unknown>)

describe('the orchestrator starts every stage', () => {
  test('Continue records the move, then runs /temper:temper continue <stage>: the orchestrator does the On Continue steps', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'plan', gates: { plan: 'PASS' } }))
    await $.session.start(START)
    const ui = await band($)
    await ui.press({ key: 'action-continue' })
    expect(events(w).some(e => e.type === 'advance' && e.from === 'plan' && e.to === 'build')).toBe(true)
    // No prompt of the mod: the orchestrator's own `state advance` is the mirror, and it writes the
    // branch, the commits and the next stage itself, with its own briefs.
    expect(w.prompts).toEqual([])
    expect(w.commandRuns).toEqual([{ command: 'temper:temper', args: 'continue plan', origin: 'plugin' }])
  })

  test('Continue at the design check (the CLI is at design, the mod at Plan) runs continue design (found live)', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'design', complexity: 'medium', gates: { plan: 'PASS' } }))
    await $.session.start(START)
    const ui = await band($)
    await ui.press({ key: 'action-continue' })
    expect(w.commandRuns).toEqual([{ command: 'temper:temper', args: 'continue design', origin: 'plugin' }])
  })

  test('/temper:temper continue <stage> records nothing in the mod, from any origin', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'plan', gates: { plan: 'PASS' } }))
    await $.session.start(START)
    const before = events(w).length
    for (const origin of ['composer', 'plugin', 'model', 'sdk']) {
      const r = await $.command.run({ command: 'temper:temper', args: 'continue plan', origin: { kind: origin, name: 'x' } } as never)
      expect(r.text).toBe('prompt based /temper:temper ran')
    }
    expect(events(w).length).toBe(before)
  })

  test('a refused decision starts nothing', async ($, on) => {
    // Plan check not passed: the machine refuses to advance, so there is no Continue; key 1 only runs the stage.
    const w = world(on, runFiles({ nextStage: 'plan' }))
    await $.session.start(START)
    const ui = await band($)
    expect(await ui.find({ key: 'action-continue' })).toBeUndefined()
    await ui.press({ key: 'action-run-stage' })
    expect(events(w).some(e => e.type === 'advance')).toBe(false)
    expect(w.prompts).toEqual([])
    expect(w.commandRuns).toEqual([{ command: 'temper:temper', args: '', origin: 'plugin' }])
  })

  test('while Claude works a stage launcher says wait and starts nothing', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'plan' }))
    await $.session.start(START)
    const ui = await band($, { isWorking: true })
    await ui.press({ key: 'action-run-stage' })
    expect(w.commandRuns).toEqual([])
    expect(w.toasts).toContain('Claude is working. Wait for the answer, then press 1.')
  })

  test('skipping with a reason records the override, mirrors it, then runs the orchestrator', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'review' }), { answers: ['reviewer is on leave'] })
    await $.session.start(START)
    const ui = await band($)
    await ui.press({ key: 'action-override' })
    expect(events(w).some(e => e.type === 'override')).toBe(true)
    expect(w.prompts.some(p => p.includes('override'))).toBe(true)
    // A skip is a move on: the orchestrator does the On Continue steps of the skipped stage, then runs the next one.
    expect(w.commandRuns).toEqual([{ command: 'temper:temper', args: 'continue review', origin: 'plugin' }])
  })

  test('only the person bare /temper:temper toggles the pane; the same command from a plugin reaches the orchestrator', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'plan' }), { placed: true })
    await $.session.start(START)
    const fromPlugin = await $.command.run({ command: 'temper:temper', args: '', origin: { kind: 'plugin', name: 'temper' } } as never)
    expect(fromPlugin.text).toBe('prompt based /temper:temper ran')
    expect(w.closed).toEqual([])
    const fromPerson = await $.command.run({ command: 'temper:temper', args: '', origin: { kind: 'composer' } } as never)
    expect(fromPerson.text).toContain('Temper pane')
  })
})

describe('Stop, timeline and the finished run', () => {
  test('Stop at Build pauses the run and asks Claude to run the build check', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }), { placed: false })
    await $.session.start(START)
    const ui = await band($)
    // At a Build checkpoint Stop is key 3.
    await ui.press({ key: 'action-stop' })
    expect(events(w).some(e => e.type === 'pause')).toBe(true)
    expect(w.prompts.some(p => p.includes('scripts/temper gate build'))).toBe(true)
    expect(w.commandRuns).toEqual([])
  })

  test('the removed buttons are not drawn', async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }), { placed: false })
    await $.session.start(START)
    const ui = await band($)
    for (const k of ['action-run-tests', 'action-diff-plan', 'action-timeline', 'action-pr-desc', 'action-back-one']) expect(await ui.find({ key: k }), k).toBeUndefined()
    await ui.press({ key: 'action-more' })
    for (const k of ['action-timeline', 'action-pr-desc', 'action-back-one']) expect(await ui.find({ key: k }), k).toBeUndefined()
  })

  test('a finished run draws Commit and Save for later; Commit asks Claude to commit without pushing', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'check', gates: { check: 'PASS' } }))
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'scripts/temper gate check' })
    const ui = await band($)
    expect(await ui.find({ key: 'action-commit' })).toBeDefined()
    expect(await ui.find({ key: 'action-save-done' })).toBeDefined()
    expect(await ui.find({ key: 'action-pr-desc' })).toBeUndefined()
    await ui.press({ key: 'action-save-done' })
    expect(w.toasts).toContain('Saved. Commit when you are ready.')
    expect(w.prompts).toEqual([])
    await ui.press({ key: 'action-commit' })
    expect(w.prompts.at(-1)).toContain('Do not push')
  })
})

describe('the files of the run are found after Claude runs cd', () => {
  test('every read, list and write names the session folder, so a changed Bash folder loses nothing', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'plan', gates: { plan: 'PASS' } }))
    await $.session.start(START)
    const ui = await band($)
    await ui.press({ key: 'action-continue' })
    // The session folder of this test is /repo. Every fs call names it, except the one that finds it.
    expect(w.rawPaths.length).toBeGreaterThan(0)
    expect(w.rawPaths.every(p => p.startsWith('/repo/'))).toBe(true)
    expect(w.rawPaths.some(p => p.includes('/events/'))).toBe(true)
  })
})

describe('Discuss, the original Other', () => {
  test('/temper:temper discuss <text> passes to the orchestrator from any origin and records nothing', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'plan' }))
    await $.session.start(START)
    const before = events(w).length
    for (const origin of ['composer', 'sdk', 'model']) {
      const r = await $.command.run({ command: 'temper', args: 'discuss why is this file in the plan?', origin: { kind: origin } } as never)
      expect(r.text).toBe('prompt based /temper:temper ran')
    }
    expect(events(w).length).toBe(before)
  })

  test('the system prompt carries the gate message line while a run is on', async ($, on) => {
    world(on, runFiles({ nextStage: 'plan' }))
    await $.session.start(START)
    const r = await $.prompt.compose(COMPOSE as never)
    const text = r.sections.find(s => s.id === 'temper:phase')?.text ?? ''
    expect(text).toContain(GATE_MESSAGE)
    expect(text).toContain('If the user writes a message at a gate, answer it.')
  })
})

describe('a stale press (#45)', () => {
  test('a button drawn for a phase that has moved is ignored with a short toast and records nothing', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'plan', gates: { plan: 'PASS', build: 'PASS' } }))
    await $.session.start(START)
    const ui = await band($)
    // The person approves with the typed command; the button on screen is now for a step that is done.
    await $.command.run({ command: 'temper:temper', args: 'approve', origin: { kind: 'composer' } } as never)
    const before = events(w).filter(e => e.type === 'advance').length
    // The CLI has not moved yet, so the bar shows "Record my choice" in place of Continue: the old
    // button is gone, and pressing the new one writes no event.
    expect(await ui.find({ key: 'action-continue' })).toBeUndefined()
    await ui.press({ key: 'action-record' })
    const after = events(w).filter(e => e.type === 'advance').length
    expect(after - before).toBe(0)
  })
})
