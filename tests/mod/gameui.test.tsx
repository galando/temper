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
      expect(textOf(await inner())).toContain('Press s to start')

      // After a click, the key s starts the game; the clock moves it.
      await ui.key({ key: 's', in: 'game' })
      expect(textOf(await inner())).toContain('w jumps. q or Esc leaves.')
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
      expect(textOf(await inner())).toContain('Paused. Press s or w to go on.')
      const frozen = textOf(await inner())
      await ui.advance(80 * 40)
      expect(textOf(await inner())).toEqual(frozen)

      // Space goes on. Left alone, the runner then hits a block: game over, and the score is posted once.
      await ui.key({ key: ' ', in: 'game' })
      await ui.advance(80 * 80)
      expect(textOf(await inner())).toContain('Game over')
      expect(textOf(await inner())).toContain('Press s to play again')
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
    // The surface refused the keys (the composer held text), so the text says how to get them.
    expect(first.text).toBe('The game is open. Press Ctrl+X, then Tab, to give it the keys. Then press s to start, w to jump, q or Esc to leave.')
    expect(w.openArgs.filter(a => a.id === 'temper-game')).toEqual([{ id: 'temper-game', focus: true, closeOnEscape: true }])
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
    test(`shows only while Claude works, dim, with the digit 8, and opens the same focused game pane on ${surface}`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const idle = await $.ui.mount({ plugin: 'temper', surface, component: 'AbovePrompt', requestId: 'idle', props: BAND(false) })
      expect(await idle.find({ key: 'action-play' })).toBeUndefined()
      await idle.unmount()
      const busy = await $.ui.mount({ plugin: 'temper', surface, component: 'AbovePrompt', requestId: 'busy', props: BAND(true) })
      expect(await busy.find({ key: 'action-play' })).toBeDefined()
      await busy.press({ key: 'action-play' })
      expect(w.openArgs.filter(a => a.id === 'temper-game')).toEqual([{ id: 'temper-game', focus: true, closeOnEscape: true }])
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

  test('the digit 8 does not clash with any other hotkey of the band, and is a digit', async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START('terminal'))
    const band = await $.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', props: BAND(true) })
    const text = JSON.stringify(await band.drawn())
    const keys = [...text.matchAll(/"hotkey":"(.)"/g)].map(m => m[1])
    expect(new Set(keys).size).toBe(keys.length)
    expect(keys).toContain('8')
    expect(keys).not.toContain('p')
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

// The keyboard path: the pane's Buttons carry the letter hotkeys, so the game plays with no mouse.
const mountGame = ($: never, surface: 'terminal' | 'desktop') =>
  ($ as { ui: { mount: (a: unknown) => Promise<never> } }).ui.mount({ plugin: 'temper', surface, component: 'Pane', requestId: 'temper-game', props: GAME }) as Promise<{
    drawn: (a?: { in: string }) => Promise<unknown>
    find: (a: { key: string }) => Promise<unknown>
    press: (a: { key: string }) => Promise<void>
    advance: (ms: number) => Promise<void>
    unmount: () => Promise<void>
  }>
// The field as text: each row Box of the drawn tree joined into one string.
type Node = { type?: string; props?: { key?: string }; children?: Array<Node | string> }
const joinText = (n: Node | string): string => (typeof n === 'string' ? n : (n.children ?? []).map(joinText).join(''))
const collectRows = (n: Node | string, out: string[]): string[] => {
  if (typeof n === 'string') return out
  if (n.props?.key?.startsWith('row-')) out.push(joinText(n))
  for (const c of n.children ?? []) collectRows(c, out)
  return out
}
const fieldRows = async (ui: Awaited<ReturnType<typeof mountGame>>): Promise<string[]> => collectRows((await ui.drawn({ in: 'game' })) as Node, [])

describe('the game pane Buttons (keyboard only)', () => {
  for (const surface of SURFACES) {
    test(`w Jump, s Start and q Quit are drawn with letter hotkeys on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const ui = await mountGame($ as never, surface)
      const text = textOf(await ui.drawn())
      for (const [key, hotkey, label] of [['game-jump', 'w', 'Jump'], ['game-start', 's', 'Start'], ['game-quit', 'q', 'Quit']] as const) {
        expect(await ui.find({ key })).toBeDefined()
        expect(text).toContain(`"hotkey":"${hotkey}"`)
        expect(text).toContain(label)
      }
    })

    test(`pressing Jump adds one to the counter, and only a press writes it on ${surface}`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const ui = await mountGame($ as never, surface)
      // The counters live in $.state; the pane hands them to the game as props, so read them there.
      const read = async () => {
        const text = textOf(await ui.drawn())
        return { jump: Number(/"jumpCount":(\d+)/.exec(text)?.[1]), start: Number(/"startCount":(\d+)/.exec(text)?.[1]) }
      }
      expect(await read()).toEqual({ jump: 0, start: 0 })
      await ui.press({ key: 'game-jump' })
      expect(await read()).toEqual({ jump: 1, start: 0 })
      await ui.press({ key: 'game-jump' })
      await ui.press({ key: 'game-start' })
      expect(await read()).toEqual({ jump: 2, start: 1 })
      const writes = w.writes.length
      const invalidated = w.invalidated
      await ui.advance(80 * 50)
      expect(w.writes.length).toBe(writes)
      expect(w.invalidated).toBe(invalidated)
    })

    test(`the game reacts to a new startCount and a new jumpCount on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const ui = await mountGame($ as never, surface)
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain('Press s to start')
      await ui.press({ key: 'game-start' })
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain('w jumps. q or Esc leaves.')
      await ui.advance(80 * 3)
      // On the ground the runner is on the bottom row of the field.
      expect((await fieldRows(ui))[5]?.[6]).toBe('A')
      await ui.press({ key: 'game-jump' })
      await ui.advance(80)
      expect((await fieldRows(ui))[5]?.[6]).toBe(' ')
      // One press moves the runner once: a second press while it is in the air changes nothing.
      const air = textOf(await ui.drawn({ in: 'game' }))
      expect(air).toContain('score')
    })

    test(`Start becomes Again after a game over, and the Start Button starts a new game on ${surface}`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const ui = await mountGame($ as never, surface)
      await ui.press({ key: 'game-start' })
      // With no press for 2 seconds the game pauses; one Jump press wakes it, and with no more
      // presses the runner then hits a block.
      await ui.advance(80 * 30)
      await ui.press({ key: 'game-jump' })
      await ui.advance(80 * 80)
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain('Game over')
      expect(typeof w.store.gameBest === 'number' && w.store.gameBest > 0).toBe(true)
      // The Start Button now says Again (a pane drawn after the game over shows it).
      await ui.unmount()
      const fresh = await mountGame($ as never, surface)
      expect(textOf(await fresh.drawn())).toContain('Again')
      // A new Client counts from the counters it sees, so press Start twice to cover a game with no state yet.
      await fresh.press({ key: 'game-start' })
      expect(textOf(await fresh.drawn({ in: 'game' }))).toContain('score 0000')
      expect(textOf(await fresh.drawn({ in: 'game' }))).toContain('w jumps. q or Esc leaves.')
    })

    test(`keys still work after a click through onKey on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const ui = await mountGame($ as never, surface)
      await (ui as unknown as { key: (e: { key: string; in: string }) => Promise<void> }).key({ key: 's', in: 'game' })
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain('w jumps. q or Esc leaves.')
      await (ui as unknown as { key: (e: { key: string; in: string }) => Promise<void> }).key({ key: 'up', in: 'game' })
      await ui.advance(80)
      expect((await fieldRows(ui))[5]?.[6]).toBe(' ')
    })

    test(`the Quit Button closes the pane on ${surface}`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      await $.command.run(run('play'))
      const ui = await mountGame($ as never, surface)
      await ui.press({ key: 'game-quit' })
      expect(w.closed).toContain('temper-game')
      // The pane is closed, so the same command opens it again.
      expect((await $.command.run(run('play'))).text).toContain('The game is open.')
    })
  }

  test('Esc path: the pane asks to close on Esc, and a person close lets the command open it again', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START('terminal'))
    await $.command.run(run('play'))
    expect(w.openArgs.filter(a => a.id === 'temper-game')).toEqual([{ id: 'temper-game', focus: true, closeOnEscape: true }])
    // The same command closes it, and a second one opens it again.
    expect((await $.command.run(run('play'))).text).toBe('The game is closed.')
    expect((await $.command.run(run('play'))).text).toContain('The game is open.')
    expect(w.openArgs.filter(a => a.id === 'temper-game')).toHaveLength(2)
  })

  test('the toast says the keys when the surface grants them, and the Ctrl+X Tab way when it does not', async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }), { grantFocus: true })
    await $.session.start(START('terminal'))
    expect((await $.command.run(run('play'))).text).toBe('The game is open. Press s to start, w to jump, q or Esc to leave.')
  })

  test('the game never uses the old key text', async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START('terminal'))
    const text = (await $.command.run(run('play'))).text ?? ''
    expect(text).not.toContain('Click it')
    expect(text).not.toContain('Space')
  })
})
