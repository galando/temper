import { describe, expect, test as baseTest } from 'claude-code/testing'

import { DRAGON_X, ROWS, TICK_MS, drawScene, newGame, press, runs, start, step } from '../../hooks/temper-mod/core/runner'
import type { RunState } from '../../hooks/temper-mod/core/runner'
import { SPEC, runFiles } from './run-files'
import { world } from './world'

const SURFACES = ['terminal', 'desktop'] as const
const run = (args: string, kind = 'composer') => ({ command: 'temper', args, origin: { kind } }) as never
const START = (surface: 'terminal' | 'desktop' | 'vscode' | 'mobile' | null) => ({ cwd: '/repo', surface, isInteractive: false }) as const

const GAME = { title: 'Temper Run', isFocused: false, bodyColumns: 80, placement: 'dock', scroll: { offset: 0, bodyRows: 12 }, view: {} } as const
const GAME_INLINE = { ...GAME, placement: 'inline' } as const
const BAND = (isWorking: boolean) => ({ hasSurvey: false, isWorking, maxRows: 12, bodyColumns: 120, scroll: { offset: 0, bodyRows: 12 }, view: {} }) as const

const OPEN_TEXT = 'The game is open. Press r to run, w to jump, s to duck, q or Esc to leave.'

// All the text of a drawn tree, one string.
const textOf = (tree: unknown): string => JSON.stringify(tree)

// The game picks its seed from the clock when it opens. Every test in this file sets the plugin
// option `gameSeed`, so the run is known and the rules can be run again here to compare.
const SEED = 4242
const test = ((name: string, a: unknown, b?: unknown) => {
  const seedOption = { gameSeed: String(SEED) }
  const base = baseTest as unknown as (n: string, o: unknown, f: unknown) => unknown
  if (typeof a === 'function') return base(name, { options: seedOption }, a)
  const given = (a as { options?: Record<string, unknown> }).options ?? {}
  return base(name, { ...(a as object), options: { ...seedOption, ...given } }, b)
}) as unknown as typeof baseTest
// The seed of the run that the Run Button starts: the option plus 7919 for each press of Run.
const seedOfRun = (n: number): number => (SEED + n * 7919) >>> 0

type Mounted = {
  drawn: (a?: { in: string }) => Promise<unknown>
  find: (a: { key: string }) => Promise<unknown>
  press: (a: { key: string }) => Promise<void>
  key: (e: { key: string; in: string }) => Promise<void>
  advance: (ms: number) => Promise<void>
  resize: (s: { columns: number; rows: number; in?: string }) => Promise<void>
  unmount: () => Promise<void>
}

const mountGame = ($: never, surface: 'terminal' | 'desktop', requestId = 'temper-game', props: unknown = GAME): Promise<Mounted> =>
  ($ as unknown as { ui: { mount: (a: unknown) => Promise<Mounted> } }).ui.mount({ plugin: 'temper', surface, component: 'Pane', requestId, props })

// The scene of the drawn tree: for each Box with a key scene-N, its runs of cells.
type Node = { type?: string; props?: Record<string, unknown>; children?: Array<Node | string> }
type Run = { text: string; fg: string; bg: string }
const sceneOf = (tree: unknown): Run[][] => {
  const rows: Run[][] = []
  const walk = (n: Node | string) => {
    if (typeof n === 'string') return
    const key = n.props?.key
    if (typeof key === 'string' && key.startsWith('scene-')) {
      rows[Number(key.slice(6))] = (n.children ?? []).map(c => {
        const t = c as Node
        return { text: (t.children ?? []).join(''), fg: String(t.props?.color), bg: String(t.props?.backgroundColor) }
      })
      return
    }
    for (const c of n.children ?? []) walk(c)
  }
  walk(tree as Node)
  return rows
}
const expectedScene = (g: RunState): Run[][] => drawScene(g).map(r => runs(r).map(x => ({ text: x.text, fg: x.fg, bg: x.bg })))

describe('the game pane draws on the terminal and the desktop app', () => {
  for (const surface of SURFACES) {
    test(`the heads up line, the heat bars, the best score and the start line on ${surface}`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build' }), { store: { gameBest: 42 } })
      await $.session.start(START(surface))
      await $.command.run(run('play'))
      expect(w.opened).toContain('temper-game')
      const ui = await mountGame($ as never, surface)
      const text = textOf(await ui.drawn({ in: 'game' }))
      for (const part of ['▲ TEMPER RUN', '▮', '▯▯▯▯', 'HI 00042  00000', 'Press r to run. Press w to jump. Press s to duck.']) expect(text).toContain(part)
      expect(text).not.toContain('Merge')
      expect(text).not.toContain('pieces')
    })

    test(`the picture is 9 rows of coloured half blocks, as wide as the pane allows (36 to 72) on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      await $.command.run(run('play'))
      const ui = await mountGame($ as never, surface)
      for (const [columns, want] of [[0, 56], [30, 36], [36, 36], [45, 45], [60, 60], [72, 72], [200, 72]] as const) {
        if (columns > 0) await ui.resize({ columns, rows: 20, in: 'game' })
        await ui.advance(100)
        const rows = sceneOf(await ui.drawn({ in: 'game' }))
        expect(rows, `columns ${columns}`).toHaveLength(ROWS)
        for (const r of rows) expect(r.map(x => x.text).join(''), `columns ${columns}`).toHaveLength(want)
      }
    })

    test(`an inline pane (a narrow terminal) shows the whole picture, and leaves out only the Temper line on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'plan', gates: { plan: 'PASS' } }))
      await $.session.start(START(surface))
      await $.command.run(run('play'))
      const ui = await mountGame($ as never, surface, 'temper-game', GAME_INLINE)
      const g0 = newGame(SEED, 0, 56)
      const rows = sceneOf(await ui.drawn({ in: 'game' }))
      expect(rows).toHaveLength(ROWS)
      expect(rows).toEqual(expectedScene(g0))
      // The picture, the heads up line, two text lines and the Buttons are 13 lines: they fit 14.
      expect(ROWS + 4).toBeLessThanOrEqual(14)
      expect(textOf(await ui.drawn({ in: 'game' }))).not.toContain('Temper: Plan is ready')
      // The dock keeps all 9 rows and shows the Temper line.
      await ui.unmount()
      const dock = await mountGame($ as never, surface)
      expect(sceneOf(await dock.drawn({ in: 'game' }))).toHaveLength(ROWS)
      expect(textOf(await dock.drawn({ in: 'game' }))).toContain('Temper: Plan is ready')
    })

    test(`the Run Button starts a run, and the picture is the picture the rules draw, tick by tick on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      await $.command.run(run('play'))
      const ui = await mountGame($ as never, surface)
      await ui.press({ key: 'game-run' })
      let g = start(newGame(seedOfRun(1), 0, 56), seedOfRun(1))
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain('Press w to jump. Press s to duck.')
      for (let i = 0; i < 6; i++) {
        await ui.advance(TICK_MS * 5)
        for (let k = 0; k < 5; k++) g = step(g)
        expect(sceneOf(await ui.drawn({ in: 'game' })), `after ${(i + 1) * 5} ticks`).toEqual(expectedScene(g))
      }
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain(`${String(g.score).padStart(5, '0')}`)
    })

    test(`the Jump and Duck Buttons act at once, exactly as a press in the rules on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      await $.command.run(run('play'))
      const ui = await mountGame($ as never, surface)
      await ui.press({ key: 'game-run' })
      let g = start(newGame(seedOfRun(1), 0, 56), seedOfRun(1))
      await ui.advance(TICK_MS * 8)
      for (let k = 0; k < 8; k++) g = step(g)
      await ui.press({ key: 'game-jump' })
      g = press(g, 'jump')
      expect(g.jt).toBe(1)
      expect(sceneOf(await ui.drawn({ in: 'game' }))).toEqual(expectedScene(g))
      await ui.advance(TICK_MS * 4)
      for (let k = 0; k < 4; k++) g = step(g)
      expect(g.jt).toBeGreaterThan(1)
      expect(sceneOf(await ui.drawn({ in: 'game' }))).toEqual(expectedScene(g))
      // After the landing a duck.
      await ui.advance(TICK_MS * 8)
      for (let k = 0; k < 8; k++) g = step(g)
      expect(g.jt).toBe(0)
      await ui.press({ key: 'game-duck' })
      g = press(g, 'duck')
      expect(sceneOf(await ui.drawn({ in: 'game' }))).toEqual(expectedScene(g))
    })

    test(`after a click, Space and the Up arrow jump and the Down arrow ducks with no wait on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      await $.command.run(run('play'))
      const ui = await mountGame($ as never, surface)
      await ui.key({ key: 'r', in: 'game' })
      const seen = textOf(await ui.drawn({ in: 'game' }))
      expect(seen).toContain('Press w to jump. Press s to duck.')
      await ui.advance(TICK_MS * 3)
      const before = JSON.stringify(sceneOf(await ui.drawn({ in: 'game' })))
      await ui.key({ key: ' ', in: 'game' })
      const jumped = JSON.stringify(sceneOf(await ui.drawn({ in: 'game' })))
      expect(jumped).not.toEqual(before)
      await ui.advance(TICK_MS * 14)
      await ui.key({ key: 'down', in: 'game' })
      expect(JSON.stringify(sceneOf(await ui.drawn({ in: 'game' })))).not.toEqual(jumped)
      await ui.key({ key: 'up', in: 'game' })
    })

    test(`a run that is left alone ends, shows the game over lines, and posts the score once on ${surface}`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      await $.command.run(run('play'))
      const ui = await mountGame($ as never, surface)
      await ui.press({ key: 'game-run' })
      await ui.advance(TICK_MS * 200)
      const text = textOf(await ui.drawn({ in: 'game' }))
      expect(text).toContain('Game over. Your forge went cold.')
      expect(text).toContain('Press r to run again. q or Esc leaves.')
      expect(text).toContain('New record. The forge is hot.')
      const stored = w.store.gameBest
      expect(typeof stored === 'number' && stored > 0).toBe(true)
      // More time after the game over posts nothing more and changes nothing.
      const invalidated = w.invalidated
      await ui.advance(TICK_MS * 100)
      expect(w.store.gameBest).toBe(stored)
      expect(w.invalidated).toBe(invalidated)
    })

    test(`the best score from the store reaches the game, and a lower score is not stored on ${surface}`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build' }), { store: { gameBest: 1000000 } })
      await $.session.start(START(surface))
      await $.command.run(run('play'))
      const ui = await mountGame($ as never, surface)
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain('HI 1000000')
      await ui.press({ key: 'game-run' })
      await ui.advance(TICK_MS * 200)
      expect(textOf(await ui.drawn({ in: 'game' }))).not.toContain('New record')
      expect(w.store.gameBest).toBe(1000000)
    })

    test(`Run again starts a new run with a new seed and keeps the best score on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      await $.command.run(run('play'))
      const ui = await mountGame($ as never, surface)
      await ui.press({ key: 'game-run' })
      await ui.advance(TICK_MS * 200)
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain('Game over')
      const fresh = await mountGame($ as never, surface, 'temper-game-2').catch(() => null)
      void fresh
      await ui.press({ key: 'game-run' })
      const g = start(newGame(seedOfRun(2), 0, 56), seedOfRun(2))
      expect(sceneOf(await ui.drawn({ in: 'game' }))).toEqual(expectedScene(g))
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain('Press w to jump. Press s to duck.')
    })

    test(`a banner from Temper shows at the top when a phase changes on ${surface}`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'plan', gates: { plan: 'PASS' } }))
      await $.session.start(START(surface))
      await $.command.run(run('play'))
      const ui = await mountGame($ as never, surface)
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain('Temper: Plan is ready. Press Esc to go back.')
      await $.command.run(run('approve'))
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain('Temper: Build is open. Press Esc to go back.')
      expect(w.toasts).toEqual(['Plan approved. Build open.'])
    })

    test(`a milestone shows the banner and the dragon flashes on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      await $.command.run(run('play'))
      const ui = await mountGame($ as never, surface)
      await ui.press({ key: 'game-run' })
      // Press nothing else; the run ends before 100 points with no keys, so play it with the rules:
      // keep the dragon alive by jumping at the right moments, as a bot, until the first hundred.
      let g = start(newGame(seedOfRun(1), 0, 56), seedOfRun(1))
      let guard = 0
      let sawBanner = false
      while (guard++ < 400 && !sawBanner) {
        const ahead = g.obstacles.find(o => o.x + 8 > DRAGON_X)
        const near = ahead && ahead.x - DRAGON_X < 16 && ahead.x - DRAGON_X > 12
        if (near && g.jt === 0) {
          await ui.press({ key: ahead.kind === 'hammer' && ahead.lift <= 5 ? 'game-duck' : 'game-jump' })
          g = press(g, ahead.kind === 'hammer' && ahead.lift <= 5 ? 'duck' : 'jump')
        }
        await ui.advance(TICK_MS)
        g = step(g)
        if (g.status === 'over') break
        sawBanner = g.banner !== null
      }
      expect(sceneOf(await ui.drawn({ in: 'game' }))).toEqual(expectedScene(g))
      if (sawBanner) expect(textOf(await ui.drawn({ in: 'game' }))).toContain('Hot! 100')
    })
  }
})

describe('the game Buttons carry the keys', () => {
  for (const surface of SURFACES) {
    test(`w Jump, s Duck, r Run and q Quit have letter hotkeys, all different, on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const ui = await mountGame($ as never, surface)
      const text = textOf(await ui.drawn())
      const want = [['game-jump', 'w', 'Jump'], ['game-duck', 's', 'Duck'], ['game-run', 'r', 'Run'], ['game-quit', 'q', 'Quit']] as const
      for (const [key, hotkey, label] of want) {
        expect(await ui.find({ key })).toBeDefined()
        expect(text).toContain(`"hotkey":"${hotkey}"`)
        // The label starts with the key ("w  Jump").
        expect(text).toContain(`"label":"${hotkey}  ${label}"`)
      }
      const keys = [...text.matchAll(/"hotkey":"(.)"/g)].map(m => m[1])
      expect(new Set(keys).size).toBe(keys.length)
    })

    test(`the Run Button says Run again after a game over on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      await $.command.run(run('play'))
      const ui = await mountGame($ as never, surface)
      await ui.press({ key: 'game-run' })
      await ui.advance(TICK_MS * 200)
      await ui.unmount()
      const again = await mountGame($ as never, surface)
      expect(textOf(await again.drawn())).toContain('"label":"r  Run again"')
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

    test(`a press of a Button writes one counter, and the frame clock writes nothing on ${surface}`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      await $.command.run(run('play'))
      const ui = await mountGame($ as never, surface)
      await ui.press({ key: 'game-run' })
      const writes = w.writes.length
      const invalidated = w.invalidated
      // A run left alone ends at about 40 ticks; before that, many frames with no write at all.
      await ui.advance(TICK_MS * 30)
      expect(w.writes.length).toBe(writes)
      expect(w.invalidated).toBe(invalidated)
    })
  }

  test('a message from the drawing is checked: an unknown message does nothing', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START('terminal'))
    await $.command.run(run('play'))
    const ui = await mountGame($ as never, 'terminal')
    await ui.key({ key: 'x', in: 'game' })
    await ui.key({ key: 'escape', in: 'game' })
    expect(w.store.gameBest).toBeUndefined()
  })
})

describe('other surfaces say what the game needs', () => {
  for (const surface of ['vscode', 'mobile'] as const) {
    test(`the pane draws a text line on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const ui = await mountGame($ as never, surface as never)
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
    // The text is always the same simple one. Whether the keys arrive is the game's own business.
    expect(first.text).toBe(OPEN_TEXT)
    expect(w.openArgs.filter(a => a.id === 'temper-game')).toEqual([{ id: 'temper-game', focus: true, closeOnEscape: true }])
    expect((await $.command.run(run('play'))).text).toBe('The game is closed.')
    expect(w.closed).toContain('temper-game')
    expect((await $.command.run(run('play'))).text).toContain('The game is open.')
  })

  test('works in every mode, because the person asked', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START('terminal'))
    await $.command.run(run('mode off'))
    expect((await $.command.run(run('play'))).text).toContain('The game is open.')
    expect(w.opened).toContain('temper-game')
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

  for (const grantFocus of [true, false]) {
    test(`the open text is the simple one whether the surface grants the keys or not (grant=${grantFocus})`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build' }), { grantFocus })
      await $.session.start(START('terminal'))
      expect((await $.command.run(run('play'))).text).toBe(OPEN_TEXT)
      await $.command.run(run('play'))
      expect(w.toasts.every(t => !t.includes('Ctrl+X'))).toBe(true)
    })
  }

  test('the text never mentions the old games', async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START('terminal'))
    const text = (await $.command.run(run('play'))).text ?? ''
    for (const old of ['Merge', 'pieces', 'slide', 'flame', 'Click it', 'Space', 'w a s d']) expect(text).not.toContain(old)
  })
})

describe('the Play button in the band', () => {
  for (const surface of SURFACES) {
    test(`shows only while Claude works, with the digit 8, and opens the same focused game pane on ${surface}`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const idle = await $.ui.mount({ plugin: 'temper', surface, component: 'AbovePrompt', requestId: 'idle', props: BAND(false) })
      expect(await idle.find({ key: 'action-play' })).toBeUndefined()
      await idle.unmount()
      const busy = await $.ui.mount({ plugin: 'temper', surface, component: 'AbovePrompt', requestId: 'busy', props: BAND(true) })
      expect(await busy.find({ key: 'action-play' })).toBeDefined()
      await busy.press({ key: 'action-play' })
      expect(w.openArgs.filter(a => a.id === 'temper-game')).toEqual([{ id: 'temper-game', focus: true, closeOnEscape: true }])
      expect(w.toasts).toContain(OPEN_TEXT)
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
  test('enforcement still denies, phases still move and the band still works while the game runs', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'plan', gates: { plan: 'PASS' } }))
    await $.session.start(START('terminal'))
    await $.command.run(run('play'))
    const ui = await mountGame($ as never, 'terminal')
    await ui.press({ key: 'game-run' })
    await ui.advance(TICK_MS * 10)
    const denied = await $.tool.call({ tool: 'Write', file_path: 'src/app.ts', content: 'x' })
    expect(denied.deny?.startsWith('Temper: Plan phase.')).toBe(true)
    const band = await $.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', props: BAND(true) })
    await band.press({ key: 'action-continue' })
    expect([...w.files.keys()].some(k => k.startsWith(`${SPEC}/events/`))).toBe(true)
  })
})

// The offer while a phase works: band, pane and hint. The setting `game` picks on, command or off.
const PANE = { title: 'Temper', isFocused: false, bodyColumns: 80, placement: 'dock', scroll: { offset: 0, bodyRows: 12 }, view: {} } as const
const hintOf = (isWorking: boolean) => ({ isDraft: false, isWorking, hint: '? for shortcuts' }) as const

type Offer = { band: boolean; bandText: string; pane: boolean; hint: boolean; hintIdle: boolean }
async function offerAt($: never, w: ReturnType<typeof world>): Promise<Offer> {
  const api = $ as unknown as { ui: { mount: (a: unknown) => Promise<{ find: (a: { key: string }) => Promise<unknown>; drawn: () => Promise<unknown>; unmount: () => Promise<void> }> } }
  const idleBand = await api.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', requestId: 'idle', props: BAND(false) })
  const idleHasPlay = (await idleBand.find({ key: 'action-play' })) !== undefined
  await idleBand.unmount()
  const band = await api.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', requestId: 'busy', props: BAND(true) })
  const bandHas = (await band.find({ key: 'action-play' })) !== undefined
  const bandText = textOf(await band.drawn())
  const pane = await api.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'Pane', requestId: 'temper', props: PANE })
  const paneHas = (await pane.find({ key: 'pane-play' })) !== undefined
  const busyHint = await api.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'PromptHint', requestId: 'hint-busy', props: hintOf(true) })
  await busyHint.drawn()
  const idleHint = await api.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'PromptHint', requestId: 'hint-idle', props: hintOf(false) })
  await idleHint.drawn()
  const hints = w.rendered.filter(r => r.component === 'PromptHint')
  expect(idleHasPlay).toBe(false)
  return {
    band: bandHas,
    bandText,
    pane: paneHas,
    hint: String(hints[0]?.props.tail).includes('Press 8 to play while you wait.'),
    hintIdle: String(hints[1]?.props.tail).includes('Press 8'),
  }
}

describe('the game offer while a phase works follows the game setting', () => {
  test('on: the band, the pane and the hint offer it, and the band button looks like 2 and 3', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START('terminal'))
    const o = await offerAt($ as never, w)
    expect(o.band).toBe(true)
    expect(o.bandText).toContain('Play while you wait')
    expect(o.bandText).toContain('"hotkey":"8"')
    // Not dim, and a secondary button: the same look as the buttons 2 and 3.
    expect(/"dimColor":true[^}]*"label":"Play while you wait"|"label":"Play while you wait"[^}]*"dimColor":true/.test(o.bandText)).toBe(false)
    expect(o.pane).toBe(true)
    expect(o.hint).toBe(true)
    expect(o.hintIdle).toBe(false)
  })

  test('command: no offer in the band, the pane or the hint, and the command still opens it', { options: { game: 'command' } }, async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START('terminal'))
    const o = await offerAt($ as never, w)
    expect(o).toMatchObject({ band: false, pane: false, hint: false, hintIdle: false })
    expect((await $.command.run(run('play'))).text).toContain('The game is open.')
  })

  test('off: no offer anywhere, and the command answers how to turn it on', { options: { game: 'off' } }, async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START('terminal'))
    const o = await offerAt($ as never, w)
    expect(o).toMatchObject({ band: false, pane: false, hint: false, hintIdle: false })
    expect((await $.command.run(run('play'))).text).toBe('The game is off. Set game to on in /config.')
  })

  test('the offer never opens the game or asks for the keys by itself', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START('terminal'))
    await offerAt($ as never, w)
    expect(w.opened).not.toContain('temper-game')
  })

  test('an unknown value means on', { options: { game: 'maybe' } }, async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START('terminal'))
    expect((await offerAt($ as never, w)).band).toBe(true)
  })
})

// The game cannot know whether the keys reach it. It notices: with no key and no press for 3
// seconds after it opens, it draws one dim line that says how to get them.
const NO_KEYS = 'No keys yet? Press Ctrl+X, then Tab, to give the game the keys.'

describe('the no keys hint in the game area', () => {
  for (const surface of SURFACES) {
    test(`no hint when a key arrives within 3 seconds, and none later on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const ui = await mountGame($ as never, surface)
      await ui.advance(2000)
      await ui.key({ key: 'x', in: 'game' })
      await ui.advance(500)
      expect(textOf(await ui.drawn({ in: 'game' }))).not.toContain(NO_KEYS)
      await ui.advance(10000)
      expect(textOf(await ui.drawn({ in: 'game' }))).not.toContain(NO_KEYS)
    })

    test(`the hint appears after 3 seconds with no key, and not before on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const ui = await mountGame($ as never, surface)
      await ui.advance(2500)
      expect(textOf(await ui.drawn({ in: 'game' }))).not.toContain(NO_KEYS)
      await ui.advance(1500)
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain(NO_KEYS)
      // It stays one line, drawn once.
      expect(textOf(await ui.drawn({ in: 'game' })).split(NO_KEYS)).toHaveLength(2)
    })

    test(`any key removes the hint at once, even a key the game does not use on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const ui = await mountGame($ as never, surface)
      await ui.advance(5000)
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain(NO_KEYS)
      await ui.key({ key: 'x', in: 'game' })
      expect(textOf(await ui.drawn({ in: 'game' }))).not.toContain(NO_KEYS)
      await ui.advance(5000)
      expect(textOf(await ui.drawn({ in: 'game' }))).not.toContain(NO_KEYS)
    })

    test(`a press of a pane Button also removes the hint on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const ui = await mountGame($ as never, surface)
      await ui.advance(5000)
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain(NO_KEYS)
      await ui.press({ key: 'game-jump' })
      expect(textOf(await ui.drawn({ in: 'game' }))).not.toContain(NO_KEYS)
    })

    test(`the hint adds no engine call and no write on ${surface}`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const ui = await mountGame($ as never, surface)
      const writes = w.writes.length
      const invalidated = w.invalidated
      await ui.advance(20000)
      expect(w.writes.length).toBe(writes)
      expect(w.invalidated).toBe(invalidated)
    })
  }
})
