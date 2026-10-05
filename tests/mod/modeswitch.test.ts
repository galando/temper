import { describe, expect, test } from 'claude-code/testing'

import { runFiles } from './run-files'
import { world } from './world'

const run = (args: string) => ({ command: 'temper', args, origin: { kind: 'composer' } }) as never
const START = { cwd: '/repo', surface: null, isInteractive: false } as const
const INTERACTIVE = { cwd: '/repo', surface: 'terminal', isInteractive: true } as const
const BAND = { hasSurvey: false, isWorking: false, maxRows: 12, bodyColumns: 100, scroll: { offset: 0, bodyRows: 12 }, view: {} } as const

const ROW = (key: string, value: string, isLocked = false) => ({ key, value, isLocked })

describe('/temper:temper mode', () => {
  test('switches without a restart: config.set, live redraw, reply', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }), { rows: [ROW('temper.uiMode', 'full')] })
    await $.session.start(START)
    const before = await $.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', props: BAND })
    expect(await before.findAll({ type: 'Button' })).not.toHaveLength(0)
    await before.unmount()
    const r = await $.command.run(run('mode minimal'))
    expect(r.text).toBe('Temper mode: minimal')
    expect(w.configSets).toEqual([{ key: 'temper.uiMode', value: 'minimal' }])
    expect(w.invalidated).toBeGreaterThan(0)
    const after = await $.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', props: BAND })
    expect(await after.findAll({ type: 'Button' })).toHaveLength(0)
    expect((await $.command.run(run('mode'))).text).toBe('Temper mode: minimal')
  })

  test('a locked row is reported, not changed', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }), { rows: [ROW('temper.uiMode', 'minimal', true)] })
    await $.session.start(START)
    const r = await $.command.run(run('mode full'))
    expect(r.text).toBe("Your organization set Temper's mode to minimal. Ask your admin to change it.")
    expect(w.configSets).toEqual([])
  })

  test('leaving full closes the pane', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START)
    expect(w.opened).toEqual(['temper'])
    await $.command.run(run('mode off'))
    expect(w.closed).toEqual(['temper'])
  })

  test('an unknown mode shows usage and changes nothing', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START)
    expect((await $.command.run(run('mode loud'))).text).toBe('Usage: /temper:temper mode <full|minimal|off>')
    expect(w.configSets).toEqual([])
  })

  test('the mode never changes what is enforced', async ($, on) => {
    world(on, runFiles({ nextStage: 'plan' }))
    await $.session.start(START)
    await $.command.run(run('mode off'))
    const r = await $.tool.call({ tool: 'Write', file_path: 'src/app.ts', content: 'x' })
    expect(r.deny?.startsWith('Temper: Plan phase.')).toBe(true)
  })
})

describe('/temper:temper enforcement', () => {
  test('off stops denials at once, toasts, and is persisted through the config row', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'plan' }), { rows: [ROW('temper.enforcement', 'on')] })
    await $.session.start(START)
    expect('deny' in (await $.tool.call({ tool: 'Write', file_path: 'src/app.ts', content: 'x' }))).toBe(true)
    expect((await $.command.run(run('enforcement off'))).text).toBe('Temper enforcement: off')
    expect(w.configSets).toEqual([{ key: 'temper.enforcement', value: 'off' }])
    expect(w.toasts).toContain('Temper enforcement: off')
    expect((await $.tool.call({ tool: 'Write', file_path: 'src/app.ts', content: 'x' })).text).toBe('stub ran')
    const text = (await $.prompt.compose({ model: 'm', promptModel: 'm', surfaces: [], tools: [], outputStyle: null, traits: [] })).sections.at(-1)?.text
    expect(text?.split('\n')[0]).toBe('Temper enforcement: off (UI only)')
    expect((await $.command.run(run('enforcement on'))).text).toBe('Temper enforcement: on')
    expect('deny' in (await $.tool.call({ tool: 'Write', file_path: 'src/app.ts', content: 'x' }))).toBe(true)
  })

  test('a locked row is reported', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'plan' }), { rows: [ROW('temper.enforcement', 'on', true)] })
    await $.session.start(START)
    expect((await $.command.run(run('enforcement off'))).text).toBe("Your organization set Temper's enforcement to on. Ask your admin to change it.")
    expect(w.configSets).toEqual([])
  })

  test('usage and the current value', async ($, on) => {
    world(on, runFiles({ nextStage: 'plan' }))
    await $.session.start(START)
    expect((await $.command.run(run('enforcement maybe'))).text).toBe('Usage: /temper:temper enforcement <on|off>')
    expect((await $.command.run(run('enforcement'))).text).toBe('Temper enforcement: on')
  })
})

describe('first interactive run asks once', () => {
  const OPTIONS = ['Full: phase bar, actions, pane', 'Minimal: phase bar only', 'Off: draw nothing']

  test('asks one line per mode, applies the answer, and never asks again', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }), { answers: ['Minimal: phase bar only'] })
    await $.session.start(INTERACTIVE)
    const first = await $.command.run(run('add password reset'))
    expect(first.text).toBe('prompt based /temper:temper ran')
    expect(w.asked).toEqual(['How much do you want Temper to show?'])
    expect(w.configSets).toEqual([{ key: 'temper.uiMode', value: 'minimal' }])
    await $.command.run(run('status'))
    await $.command.run(run('add something else'))
    expect(w.asked).toHaveLength(1)
    expect(OPTIONS).toHaveLength(3)
  })

  test('a dismissed question means full plus a toast on how to change it', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(INTERACTIVE)
    await $.command.run(run('add password reset'))
    expect(w.asked).toHaveLength(1)
    expect(w.configSets).toEqual([])
    expect(w.toasts).toContain('Temper mode is full. To change it, use /temper:temper mode <full|minimal|off>.')
    await $.command.run(run('add more'))
    expect(w.asked).toHaveLength(1)
  })

  test('never asks in a non interactive run', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }), { answers: ['Off: draw nothing'] })
    await $.session.start(START)
    await $.command.run(run('add password reset'))
    expect(w.asked).toEqual([])
    expect(w.configSets).toEqual([])
  })

  test('/temper:temper mode with no argument offers the choice again, even after the first ask', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }), { answers: ['Full: phase bar, actions, pane', 'Off: draw nothing'] })
    await $.session.start(INTERACTIVE)
    await $.command.run(run('add password reset'))
    expect(w.asked).toHaveLength(1)
    const r = await $.command.run(run('mode'))
    expect(w.asked).toHaveLength(2)
    expect(r.text).toBe('Temper mode: off')
    expect(w.configSets.at(-1)).toEqual({ key: 'temper.uiMode', value: 'off' })
  })

  test('an explicit mode argument applies at once and never asks, first run or not', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }), { answers: ['Off: draw nothing'], rows: [ROW('temper.uiMode', 'full')] })
    await $.session.start(INTERACTIVE)
    const r = await $.command.run(run('mode minimal'))
    expect(r.text).toBe('Temper mode: minimal')
    expect(w.asked).toEqual([])
    expect(w.configSets).toEqual([{ key: 'temper.uiMode', value: 'minimal' }])
    // The explicit choice counts as the first run answer: a later /temper:temper does not ask either.
    await $.command.run(run('add password reset'))
    expect(w.asked).toEqual([])
  })

  test('a bare first /temper:temper still asks once, and /temper:temper mode with no argument asks again', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }), { answers: ['Full: phase bar, actions, pane', 'Minimal: phase bar only'] })
    await $.session.start(INTERACTIVE)
    await $.command.run(run('add password reset'))
    expect(w.asked).toHaveLength(1)
    await $.command.run(run('mode'))
    expect(w.asked).toHaveLength(2)
  })

  test('/temper:temper mode with no argument on a fresh store asks exactly once, not twice', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }), { answers: ['Minimal: phase bar only', 'Off: draw nothing'] })
    await $.session.start(INTERACTIVE)
    const r = await $.command.run(run('mode'))
    expect(w.asked).toHaveLength(1)
    expect(r.text).toBe('Temper mode: minimal')
  })

  test('an invalid mode argument asks nothing and changes nothing', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }), { answers: ['Off: draw nothing'] })
    await $.session.start(INTERACTIVE)
    expect((await $.command.run(run('mode loud'))).text).toBe('Usage: /temper:temper mode <full|minimal|off>')
    expect(w.asked).toEqual([])
    expect(w.configSets).toEqual([])
  })

  test('a command that is not the person never marks the question answered or opens it', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }), { answers: ['Minimal: phase bar only'] })
    await $.session.start(INTERACTIVE)
    for (const kind of ['sdk', 'plugin', 'bridge'] as const) {
      await $.command.run({ command: 'temper', args: 'mode full', origin: { kind, name: 'x' } } as never)
      await $.command.run({ command: 'temper', args: 'add password reset', origin: { kind, name: 'x' } } as never)
    }
    expect(w.asked).toEqual([])
    // The person's first /temper still gets the question.
    await $.command.run(run('add password reset'))
    expect(w.asked).toHaveLength(1)
  })
})
