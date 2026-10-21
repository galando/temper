import { describe, expect, test } from 'claude-code/testing'

import { runFiles } from './run-files'
import { world } from './world'

// 9.7.3: the mod changes no setting and runs no command. The person sets Temper UI mode and Temper enforcement in
// /config (the plugin's own options); `/temper:temper mode` and `/temper:temper enforcement` only say what is set and
// where to change it. There is no first run question, and the bar has no button.
const run = (args: string) => ({ command: 'temper', args, origin: { kind: 'composer' } }) as never
const START = { cwd: '/repo', surface: null, isInteractive: false } as const
const INTERACTIVE = { cwd: '/repo', surface: 'terminal', isInteractive: true } as const
const BAND = { hasSurvey: false, isWorking: false, maxRows: 12, bodyColumns: 100, scroll: { offset: 0, bodyRows: 12 }, view: {} } as const
const MODE_WHERE = 'Change it in /config: Temper UI mode (full, minimal or off).'
const ENFORCEMENT_WHERE = 'Change it in /config: Temper enforcement (on or off).'
const COMPOSE = { model: 'm', promptModel: 'm', surfaces: [], tools: [], outputStyle: null, traits: [] }

describe('/temper:temper mode', () => {
  test('says the mode and where to change it, with or without a word after it, and changes nothing', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START)
    for (const args of ['mode', 'mode minimal', 'mode off', 'mode loud']) {
      expect((await $.command.run(run(args))).text).toBe(`Temper mode: full. ${MODE_WHERE}`)
    }
    expect(w.configSets).toEqual([])
    expect(w.asked).toEqual([])
    expect(w.closed).toEqual([])
  })

  test('the mode is the uiMode option', { options: { uiMode: 'minimal' } }, async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START)
    expect((await $.command.run(run('mode'))).text).toBe(`Temper mode: minimal. ${MODE_WHERE}`)
    expect((await $.command.run(run('pane'))).text).toBe(`The pane shows in full mode only. ${MODE_WHERE}`)
  })

  test('the mode never changes what is enforced', { options: { uiMode: 'off' } }, async ($, on) => {
    world(on, runFiles({ nextStage: 'plan' }))
    await $.session.start(START)
    const r = await $.tool.call({ tool: 'Write', file_path: 'src/app.ts', content: 'x' })
    expect(r.deny?.startsWith('Temper: Plan stage.')).toBe(true)
  })
})

describe('/temper:temper enforcement', () => {
  test('says the value and where to change it, and the guard stays as it is', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'plan' }))
    await $.session.start(START)
    expect('deny' in (await $.tool.call({ tool: 'Write', file_path: 'src/app.ts', content: 'x' }))).toBe(true)
    for (const args of ['enforcement', 'enforcement off', 'enforcement maybe']) {
      expect((await $.command.run(run(args))).text).toBe(`Temper enforcement: on. ${ENFORCEMENT_WHERE}`)
    }
    expect('deny' in (await $.tool.call({ tool: 'Write', file_path: 'src/app.ts', content: 'x' }))).toBe(true)
    expect(w.configSets).toEqual([])
    expect(w.toasts).toEqual([])
  })

  test('the enforcement option off stops denials, and the section says UI only', { options: { enforcement: 'off' } }, async ($, on) => {
    world(on, runFiles({ nextStage: 'plan' }))
    await $.session.start(START)
    expect((await $.tool.call({ tool: 'Write', file_path: 'src/app.ts', content: 'x' })).text).toBe('stub ran')
    expect((await $.prompt.compose(COMPOSE)).sections.at(-1)?.text?.split('\n')[0]).toBe('Temper enforcement: off (UI only)')
    expect((await $.command.run(run('enforcement'))).text).toBe(`Temper enforcement: off. ${ENFORCEMENT_WHERE}`)
  })

  test('a word from any origin gets the same answer and changes nothing', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'plan' }))
    await $.session.start(START)
    for (const kind of ['sdk', 'plugin', 'bridge'] as const) {
      const r = await $.command.run({ command: 'temper', args: 'enforcement off', origin: { kind, name: 'x' } } as never)
      expect(r.text).toBe(`Temper enforcement: on. ${ENFORCEMENT_WHERE}`)
    }
    expect(w.configSets).toEqual([])
    expect('deny' in (await $.tool.call({ tool: 'Write', file_path: 'src/app.ts', content: 'x' }))).toBe(true)
  })
})

describe('no question and no button', () => {
  test('a first interactive /temper:temper asks nothing and sets nothing', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(INTERACTIVE)
    expect((await $.command.run(run('add password reset'))).text).toBe('prompt based /temper:temper ran')
    await $.command.run(run('status'))
    expect(w.asked).toEqual([])
    expect(w.configSets).toEqual([])
    // The feature text goes on to the prompt based command; a word the mod answers (status) does not.
    expect(w.commandRuns.map(c => c.args)).toEqual(['add password reset'])
  })

  test('the bar has no button in any mode, and the mod runs no command of its own', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START)
    const band = await $.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', props: BAND })
    expect(await band.findAll({ type: 'Button' })).toHaveLength(0)
    await band.unmount()
    expect(w.commandRuns).toEqual([])
  })
})
