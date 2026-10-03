import { describe, expect, test } from 'claude-code/testing'

import { SPEC, runFiles } from './run-files'
import { world } from './world'

const SURFACES = ['terminal', 'desktop'] as const
const run = (args: string, kind = 'composer') => ({ command: 'temper', args, origin: { kind } }) as never
const START = (surface: 'terminal' | 'desktop' | 'vscode' | 'mobile' | null) => ({ cwd: '/repo', surface, isInteractive: false }) as const

// The Client's frame clock runs from the first key: space starts, and with no key for 2 seconds and
// no block close the game pauses. Space then goes on, and a game with no jumps ends at a block.
type Mounted = { key: (e: { key: string; in: string }) => Promise<void>; advance: (ms: number) => Promise<void> }
async function playToGameOver(ui: Mounted): Promise<void> {
  await ui.key({ key: ' ', in: 'game' })
  await ui.advance(80 * 30)
  await ui.key({ key: ' ', in: 'game' })
  await ui.advance(80 * 80)
}

const GAME = { title: 'Temper Run', isFocused: false, bodyColumns: 80, placement: 'inline', scroll: { offset: 0, bodyRows: 12 }, view: {} } as const
const BAND = (isWorking: boolean) => ({ hasSurvey: false, isWorking, maxRows: 12, bodyColumns: 120, scroll: { offset: 0, bodyRows: 12 }, view: {} }) as const

// All the text of a drawn tree, one string.
const textOf = (tree: unknown): string => JSON.stringify(tree)

describe('the game pane draws on the terminal and the desktop app', () => {
  for (const surface of SURFACES) {
    test(`starts on a key, the jump key moves the runner, a block ends the game on ${surface}`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      await $.command.run(run('play'))
      expect(w.opened).toContain('temper-game')
      const ui = await $.ui.mount({ plugin: 'temper', surface, component: 'Pane', requestId: 'temper-game', props: GAME })
      const inner = () => ui.drawn({ in: 'game' })
      expect(textOf(await inner())).toContain('TEMPER RUN')
      expect(textOf(await inner())).toContain('Press Space to start')

      // Space starts the game; the clock moves it.
      await ui.key({ key: ' ', in: 'game' })
      expect(textOf(await inner())).toContain('Space, Up or W jumps')
      const before = textOf(await inner())
      await ui.advance(80 * 3)
      expect(textOf(await inner())).not.toEqual(before)

      // Up jumps: the runner leaves the bottom row of the field.
      await ui.key({ key: 'up', in: 'game' })
      await ui.advance(80)
      const rows = JSON.stringify(await inner()).match(/[A^ #_]{56}/g) ?? []
      expect(rows.length).toBeGreaterThan(0)

      // With no key for 2 seconds and no block close, the game pauses by itself.
      await ui.advance(80 * 40)
      expect(textOf(await inner())).toContain('Paused. Press Space to go on.')
      const frozen = textOf(await inner())
      await ui.advance(80 * 40)
      expect(textOf(await inner())).toEqual(frozen)

      // Space goes on. Left alone, the runner then hits a block: game over, and the score is posted once.
      await ui.key({ key: ' ', in: 'game' })
      await ui.advance(80 * 80)
      expect(textOf(await inner())).toContain('Game over')
      expect(textOf(await inner())).toContain('Press Space to play again')
      expect(typeof w.store.gameBest === 'number' && w.store.gameBest > 0).toBe(true)
    })

    test(`Space after game over starts a new game, and Escape does nothing to the game on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const ui = await $.ui.mount({ plugin: 'temper', surface, component: 'Pane', requestId: 'temper-game', props: GAME })
      await playToGameOver(ui)
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain('Game over')
      // Escape is the engine's: the module ignores it and the game state is unchanged.
      await ui.key({ key: 'escape', in: 'game' })
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain('Game over')
      await ui.key({ key: ' ', in: 'game' })
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain('score 0000')
    })

    test(`the best score from the store reaches the game, and one game over posts one score on ${surface}`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build' }), { store: { gameBest: 777 } })
      await $.session.start(START(surface))
      await $.command.run(run('play'))
      const ui = await $.ui.mount({ plugin: 'temper', surface, component: 'Pane', requestId: 'temper-game', props: GAME })
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain('best 0777')
      await playToGameOver(ui)
      // A score below the best is not stored.
      expect(w.store.gameBest).toBe(777)
      // More time after game over posts nothing more.
      await ui.advance(80 * 40)
      expect(w.store.gameBest).toBe(777)
    })

    test(`a banner from Temper shows at the top when a phase changes on ${surface}`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'plan', gates: { plan: 'PASS' } }))
      await $.session.start(START(surface))
      await $.command.run(run('play'))
      const ui = await $.ui.mount({ plugin: 'temper', surface, component: 'Pane', requestId: 'temper-game', props: GAME })
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain('Temper: Plan is ready. Press Esc to go back.')
      await $.command.run(run('approve'))
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain('Temper: Build is open. Press Esc to go back.')
      expect(w.toasts).toEqual(['Plan approved · Build open'])
    })
  }
})

describe('other surfaces say what the game needs', () => {
  for (const surface of ['vscode', 'mobile'] as const) {
    test(`the pane draws a text line on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const ui = await $.ui.mount({ plugin: 'temper', surface, component: 'Pane', requestId: 'temper-game', props: GAME })
      expect(textOf(await ui.drawn())).toContain('The game needs the terminal or the desktop app.')
    })

    test(`/temper:temper play answers in text on ${surface}`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      expect((await $.command.run(run('play'))).text).toBe('The game needs the terminal or the desktop app.')
      expect(w.opened).not.toContain('temper-game')
    })
  }

  test('a headless run (no surface) answers the same', async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START(null))
    expect((await $.command.run(run('play'))).text).toBe('The game needs the terminal or the desktop app.')
  })
})

describe('/temper:temper play', () => {
  test('opens the pane and asks for the keys; the same command closes it', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START('terminal'))
    const first = await $.command.run(run('play'))
    expect(first.text).toBe('The game is open. Click it or press a key to play. Esc leaves.')
    expect(w.openArgs.filter(a => a.id === 'temper-game')).toEqual([{ id: 'temper-game', focus: true }])
    expect((await $.command.run(run('play'))).text).toBe('The game is closed.')
    expect(w.closed).toContain('temper-game')
    expect((await $.command.run(run('play'))).text).toContain('The game is open.')
  })

  test('works in every mode, because the person asked', async ($, on) => {
    for (const mode of ['full', 'minimal', 'off'] as const) {
      const w = world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START('terminal'))
      await $.command.run(run(`mode ${mode}`))
      expect((await $.command.run(run('play'))).text).toContain('The game is open.')
      expect(w.opened).toContain('temper-game')
      break
    }
  })

  test('works without a run', async ($, on) => {
    world(on, {})
    await $.session.start(START('terminal'))
    expect((await $.command.run(run('play'))).text).toContain('The game is open.')
  })

  test('only the person opens it', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START('terminal'))
    for (const kind of ['sdk', 'plugin', 'bridge']) {
      expect((await $.command.run(run('play', kind))).text).toContain('Only the user can open the game')
    }
    expect(w.opened).not.toContain('temper-game')
  })

  test('the game option off answers with how to turn it on', { options: { game: 'off' } }, async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START('terminal'))
    expect((await $.command.run(run('play'))).text).toBe('The game is off. Set game to on in /config.')
    expect(w.opened).not.toContain('temper-game')
  })

  test('an unknown game value means on', { options: { game: 'maybe' } }, async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START('terminal'))
    expect((await $.command.run(run('play'))).text).toContain('The game is open.')
  })

  test('never opens by itself', async ($, on) => {
    on('turn.complete', ($2, e) => ({ text: e.answer }))
    const w = world(on, runFiles({ nextStage: 'plan', gates: { plan: 'PASS' } }))
    await $.session.start(START('terminal'))
    await $.command.run(run('approve'))
    await $.turn.complete({ answer: 'x', durationMs: 1, isAborted: false, turnId: 't', reason: 'answer' } as never)
    expect(w.opened).not.toContain('temper-game')
  })
})

describe('the Play button in the band', () => {
  for (const surface of SURFACES) {
    test(`shows only while Claude works, dim, with key p, and opens the game without the keys on ${surface}`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const idle = await $.ui.mount({ plugin: 'temper', surface, component: 'AbovePrompt', requestId: 'idle', props: BAND(false) })
      expect(await idle.find({ key: 'action-play' })).toBeUndefined()
      await idle.unmount()
      const busy = await $.ui.mount({ plugin: 'temper', surface, component: 'AbovePrompt', requestId: 'busy', props: BAND(true) })
      expect(await busy.find({ key: 'action-play' })).toBeDefined()
      await busy.press({ key: 'action-play' })
      expect(w.openArgs.filter(a => a.id === 'temper-game')).toEqual([{ id: 'temper-game', focus: false }])
      expect(w.toasts.some(t => t.includes('The game is open'))).toBe(true)
    })
  }

  test('is not drawn when the game is off, in minimal mode, or on other surfaces', async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }), {})
    await $.session.start(START('terminal'))
    await $.command.run(run('mode minimal'))
    const band = await $.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', props: BAND(true) })
    expect(await band.find({ key: 'action-play' })).toBeUndefined()
  })

  test('is not drawn when the game option is off', { options: { game: 'off' } }, async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START('terminal'))
    const band = await $.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', props: BAND(true) })
    expect(await band.find({ key: 'action-play' })).toBeUndefined()
  })

  test('the p key does not clash with any other hotkey of the band', async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START('terminal'))
    const band = await $.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', props: BAND(true) })
    const text = JSON.stringify(await band.drawn())
    const keys = [...text.matchAll(/"hotkey":"(.)"/g)].map(m => m[1])
    expect(new Set(keys).size).toBe(keys.length)
    expect(keys).toContain('p')
  })
})

describe('the game never disturbs Temper work', () => {
  test('enforcement still denies, phases still move and the band still works while the game is open', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'plan', gates: { plan: 'PASS' } }))
    await $.session.start(START('terminal'))
    await $.command.run(run('play'))
    const ui = await $.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'Pane', requestId: 'temper-game', props: GAME })
    await ui.key({ key: ' ', in: 'game' })
    const denied = await $.tool.call({ tool: 'Write', file_path: 'src/app.ts', content: 'x' })
    expect(denied.deny?.startsWith('Temper: Plan phase.')).toBe(true)
    const band = await $.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', props: BAND(true) })
    await band.press({ key: 'action-approve' })
    expect([...w.files.keys()].some(k => k.startsWith(`${SPEC}/events/`))).toBe(true)
    expect(w.invalidated).toBeLessThan(5)
  })

  test('the frame clock writes no state and invalidates nothing', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START('terminal'))
    await $.command.run(run('play'))
    const ui = await $.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'Pane', requestId: 'temper-game', props: GAME })
    await ui.key({ key: ' ', in: 'game' })
    const invalidated = w.invalidated
    const writes = w.writes.length
    await ui.advance(80 * 100)
    expect(w.invalidated).toBe(invalidated)
    expect(w.writes.length).toBe(writes)
  })
})
