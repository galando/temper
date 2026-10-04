import { describe, expect, test as baseTest } from 'claude-code/testing'

import { DIRS, applyMove, newGame } from '../../hooks/temper-mod/core/merge'
import type { Dir, MergeState } from '../../hooks/temper-mod/core/merge'
import { SPEC, runFiles } from './run-files'
import { world } from './world'

const SURFACES = ['terminal', 'desktop'] as const
const run = (args: string, kind = 'composer') => ({ command: 'temper', args, origin: { kind } }) as never
const START = (surface: 'terminal' | 'desktop' | 'vscode' | 'mobile' | null) => ({ cwd: '/repo', surface, isInteractive: false }) as const

const GAME = { title: 'Temper Merge', isFocused: false, bodyColumns: 80, placement: 'inline', scroll: { offset: 0, bodyRows: 12 }, view: {} } as const
const BAND = (isWorking: boolean) => ({ hasSurvey: false, isWorking, maxRows: 12, bodyColumns: 120, scroll: { offset: 0, bodyRows: 12 }, view: {} }) as const

const OPEN_TEXT = 'The game is open. Press w a s d to slide the pieces, r for a new game, q or Esc to leave.'

// All the text of a drawn tree, one string.
const textOf = (tree: unknown): string => JSON.stringify(tree)

// The game picks its seed from the clock when it opens. Every test in this file sets the plugin
// option `gameSeed`, so the board is known and the rules can be run again here to compare.
const SEED_A = 4242
type TestFn = (...args: never[]) => unknown
const test = ((name: string, a: unknown, b?: unknown) => {
  const seedOption = { gameSeed: String(SEED_A) }
  const base = baseTest as unknown as (n: string, o: unknown, f: unknown) => unknown
  if (typeof a === 'function') return base(name, { options: seedOption }, a)
  const given = (a as { options?: Record<string, unknown> }).options ?? {}
  return base(name, { ...(a as object), options: { ...seedOption, ...given } }, b)
}) as unknown as typeof baseTest
void (null as unknown as TestFn)
// The clock no longer matters: the option fixes the seed. These stay so each test reads the same.
const withClock = async <T,>(_seed: number, fn: () => Promise<T>): Promise<T> => fn()
const SEED_B = 777

type Mounted = {
  drawn: (a?: { in: string }) => Promise<unknown>
  find: (a: { key: string }) => Promise<unknown>
  press: (a: { key: string }) => Promise<void>
  key: (e: { key: string; in: string }) => Promise<void>
  advance: (ms: number) => Promise<void>
  resize: (s: { columns: number; rows: number; in?: string }) => Promise<void>
  unmount: () => Promise<void>
}

const mountGame = ($: never, surface: 'terminal' | 'desktop', requestId = 'temper-game'): Promise<Mounted> =>
  ($ as unknown as { ui: { mount: (a: unknown) => Promise<Mounted> } }).ui.mount({ plugin: 'temper', surface, component: 'Pane', requestId, props: GAME })

// The drawn board as text rows, and as 16 numbers (0 for an empty cell).
type Node = { type?: string; props?: { key?: string }; children?: Array<Node | string> }
const joinText = (n: Node | string): string => (typeof n === 'string' ? n : (n.children ?? []).map(joinText).join(''))
const collectRows = (n: Node | string, out: string[]): string[] => {
  if (typeof n === 'string') return out
  if (n.props?.key?.startsWith('row-')) out.push(joinText(n))
  for (const c of n.children ?? []) collectRows(c, out)
  return out
}
const rowsOf = async (ui: Mounted): Promise<string[]> => collectRows((await ui.drawn({ in: 'game' })) as Node, [])
const boardOf = async (ui: Mounted): Promise<number[]> => {
  const rows = await rowsOf(ui)
  const out: number[] = []
  for (let r = 0; r < 4; r++) {
    const line = rows[r * 3 + 1] ?? ''
    for (let c = 0; c < 4; c++) out.push(Number(line.slice(1 + c * 7, 8 + c * 7).trim()) || 0)
  }
  return out
}
const scoreOf = async (ui: Mounted): Promise<number> => Number(/score (\d+)/.exec(textOf(await ui.drawn({ in: 'game' })))?.[1])

const BUTTON: Record<Dir, string> = { up: 'game-up', left: 'game-left', down: 'game-down', right: 'game-right' }

// What the pure rules say after the same moves from the same seed.
const expected = (seed: number, moves: Dir[], best = 0): MergeState => moves.reduce((g, d) => applyMove(g, d), newGame(seed, best))

describe('the game pane draws on the terminal and the desktop app', () => {
  for (const surface of SURFACES) {
    test(`the header, the board and the start message on ${surface}`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build' }), { store: { gameBest: 42 } })
      await $.session.start(START(surface))
      await withClock(SEED_A, () => $.command.run(run('play')))
      expect(w.opened).toContain('temper-game')
      const ui = await mountGame($ as never, surface)
      const text = textOf(await ui.drawn({ in: 'game' }))
      for (const part of ['▲ TEMPER MERGE', 'score 0000', 'best 0042', 'Slide the pieces. Equal pieces merge and get hotter. Make a white hot 512.']) expect(text).toContain(part)
      expect(await boardOf(ui)).toEqual(newGame(SEED_A, 42).board)
      expect(text).not.toContain('Temper Run')
    })

    test(`pieces have heat colours and empty cells are dim dots on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      await withClock(SEED_A, () => $.command.run(run('play')))
      const ui = await mountGame($ as never, surface)
      const text = textOf(await ui.drawn({ in: 'game' }))
      expect(text).toContain('"backgroundColor":"#3a3a3a"')
      expect(text).toContain('·')
      expect(text).toContain('"color":"#a8a8a8"')
    })

    test(`every board row is 29 columns, and nothing is wider, at any pane width on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      await withClock(SEED_A, () => $.command.run(run('play')))
      const ui = await mountGame($ as never, surface)
      for (const columns of [30, 36, 60, 120]) {
        await ui.resize({ columns, rows: 20, in: 'game' })
        await ui.advance(250)
        const rows = await rowsOf(ui)
        expect(rows).toHaveLength(12)
        for (const r of rows) expect(r).toHaveLength(29)
      }
    })

    test(`each pane Button moves the pieces exactly as the rules say, one new piece for a move on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      await withClock(SEED_A, () => $.command.run(run('play')))
      const ui = await mountGame($ as never, surface)
      const moves: Dir[] = ['left', 'up', 'right', 'down', 'left', 'down', 'right', 'up']
      const done: Dir[] = []
      for (const d of moves) {
        await ui.press({ key: BUTTON[d] })
        done.push(d)
        const want = expected(SEED_A, done)
        expect(await boardOf(ui)).toEqual(want.board)
        expect(await scoreOf(ui)).toBe(want.score)
      }
    })

    test(`keys after a click move the pieces too: wasd and the arrow keys on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      await withClock(SEED_A, () => $.command.run(run('play')))
      const ui = await mountGame($ as never, surface)
      const keys: Array<[string, Dir]> = [['a', 'left'], ['w', 'up'], ['d', 'right'], ['s', 'down'], ['left', 'left'], ['up', 'up'], ['right', 'right'], ['down', 'down']]
      const done: Dir[] = []
      for (const [k, d] of keys) {
        await ui.key({ key: k, in: 'game' })
        done.push(d)
        expect(await boardOf(ui)).toEqual(expected(SEED_A, done).board)
      }
    })

    test(`a move that changes nothing adds no piece and no score on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      await withClock(SEED_A, () => $.command.run(run('play')))
      const ui = await mountGame($ as never, surface)
      // Find a direction that does nothing on the start board by asking the pure rules.
      let g = newGame(SEED_A)
      let dead: Dir | null = null
      for (let i = 0; i < 200 && dead === null; i++) {
        // After each move, ask the rules whether some direction would change nothing.
        dead = DIRS.find(d => applyMove(g, d).board.every((v, k) => v === g.board[k])) ?? null
        if (dead !== null) break
        const d = DIRS[i % 4] as Dir
        g = applyMove(g, d)
        await ui.press({ key: BUTTON[d] })
      }
      expect(dead).not.toBeNull()
      const before = await boardOf(ui)
      const score = await scoreOf(ui)
      await ui.press({ key: BUTTON[dead as Dir] })
      expect(await boardOf(ui)).toEqual(before)
      expect(await scoreOf(ui)).toBe(score)
    })

    test(`r starts a new game with a new board and keeps the best score on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }), { store: { gameBest: 300 } })
      await $.session.start(START(surface))
      await withClock(SEED_A, () => $.command.run(run('play')))
      const ui = await mountGame($ as never, surface)
      for (const d of ['left', 'up', 'right', 'down', 'left', 'up'] as Dir[]) await ui.press({ key: BUTTON[d] })
      expect(await scoreOf(ui)).toBeGreaterThanOrEqual(0)
      await withClock(SEED_B, () => ui.press({ key: 'game-new' }))
      const board = await boardOf(ui)
      expect(await scoreOf(ui)).toBe(0)
      expect(board.filter(v => v !== 0)).toHaveLength(2)
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain('best 0300')
      // The key r after a click does the same.
      await ui.press({ key: 'game-left' })
      await withClock(SEED_A, () => ui.key({ key: 'r', in: 'game' }))
      expect(await scoreOf(ui)).toBe(0)
      expect((await boardOf(ui)).filter(v => v !== 0)).toHaveLength(2)
    })

    test(`closing the pane keeps the board, and opening it again goes on with the same game on ${surface}`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      await withClock(SEED_A, () => $.command.run(run('play')))
      const ui = await mountGame($ as never, surface)
      const moves: Dir[] = ['left', 'up', 'right', 'down', 'left']
      for (const d of moves) await ui.press({ key: BUTTON[d] })
      const board = await boardOf(ui)
      const score = await scoreOf(ui)
      await ui.press({ key: 'game-quit' })
      expect(w.closed).toContain('temper-game')
      await ui.unmount()
      // Another seed in the clock must not matter: the game goes on.
      await withClock(SEED_B, () => $.command.run(run('play')))
      const again = await mountGame($ as never, surface)
      expect(await boardOf(again)).toEqual(board)
      expect(await scoreOf(again)).toBe(score)
      expect(board).toEqual(expected(SEED_A, moves).board)
    })

    test(`the game ends when no move changes the board, says the score, and keeps the best score once on ${surface}`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      await withClock(SEED_A, () => $.command.run(run('play')))
      const ui = await mountGame($ as never, surface)
      // Play the same moves the pure rules play, until the pure game is over.
      let g = newGame(SEED_A)
      let i = 0
      while (!g.over && i < 3000) {
        const d = DIRS[i % 4] as Dir
        g = applyMove(g, d)
        await ui.press({ key: BUTTON[d] })
        i++
      }
      expect(g.over).toBe(true)
      const text = textOf(await ui.drawn({ in: 'game' }))
      expect(text).toContain(`No more moves. Score ${g.score}. Press r for a new game. q or Esc leaves.`)
      expect(w.store.gameBest).toBe(g.score)
      // More presses after the end change nothing, and write nothing more to the store.
      const writes = w.store.gameBest
      await ui.press({ key: 'game-left' })
      expect(await boardOf(ui)).toEqual(g.board)
      expect(w.store.gameBest).toBe(writes)
    })

    test(`the best score from the store reaches the game, and a lower score is not stored on ${surface}`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build' }), { store: { gameBest: 1000000 } })
      await $.session.start(START(surface))
      await withClock(SEED_A, () => $.command.run(run('play')))
      const ui = await mountGame($ as never, surface)
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain('best 1000000')
      let g = newGame(SEED_A)
      for (let i = 0; i < 3000 && !g.over; i++) {
        g = applyMove(g, DIRS[i % 4] as Dir)
        await ui.press({ key: BUTTON[DIRS[i % 4] as Dir] })
      }
      expect(w.store.gameBest).toBe(1000000)
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
  }
})

describe('the game Buttons carry the keys', () => {
  for (const surface of SURFACES) {
    test(`w Up, a Left, s Down, d Right, r New game and q Quit have letter hotkeys, all different, on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const ui = await mountGame($ as never, surface)
      const text = textOf(await ui.drawn())
      const want = [['game-up', 'w', 'Up'], ['game-left', 'a', 'Left'], ['game-down', 's', 'Down'], ['game-right', 'd', 'Right'], ['game-new', 'r', 'New game'], ['game-quit', 'q', 'Quit']] as const
      for (const [key, hotkey, label] of want) {
        expect(await ui.find({ key })).toBeDefined()
        expect(text).toContain(`"hotkey":"${hotkey}"`)
        // The label starts with the key ("w  Up").
        expect(text).toContain(`"label":"${hotkey}  ${label}"`)
      }
      const keys = [...text.matchAll(/"hotkey":"(.)"/g)].map(m => m[1])
      expect(new Set(keys).size).toBe(keys.length)
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

    test(`the frame clock writes no file and invalidates nothing on ${surface}`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      await $.command.run(run('play'))
      const ui = await mountGame($ as never, surface)
      await ui.key({ key: 'a', in: 'game' })
      const writes = w.writes.length
      const invalidated = w.invalidated
      await ui.advance(60000)
      expect(w.writes.length).toBe(writes)
      expect(w.invalidated).toBe(invalidated)
    })
  }

  test('a message from the drawing is checked: an unknown direction does nothing', async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START('terminal'))
    await withClock(SEED_A, () => $.command.run(run('play')))
    const ui = await mountGame($ as never, 'terminal')
    const before = await boardOf(ui)
    await ui.key({ key: 'x', in: 'game' })
    await ui.key({ key: 'escape', in: 'game' })
    expect(await boardOf(ui)).toEqual(before)
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

  test('the text never mentions the old game', async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START('terminal'))
    const text = (await $.command.run(run('play'))).text ?? ''
    for (const old of ['flame', 'jump', 'Space', 'Click it', 'Temper Run']) expect(text).not.toContain(old)
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
  test('enforcement still denies, phases still move and the band still works while the game is open', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'plan', gates: { plan: 'PASS' } }))
    await $.session.start(START('terminal'))
    await $.command.run(run('play'))
    const ui = await mountGame($ as never, 'terminal')
    await ui.key({ key: 'a', in: 'game' })
    const denied = await $.tool.call({ tool: 'Write', file_path: 'src/app.ts', content: 'x' })
    expect(denied.deny?.startsWith('Temper: Plan phase.')).toBe(true)
    const band = await $.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', props: BAND(true) })
    await band.press({ key: 'action-approve' })
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
      await ui.key({ key: 'a', in: 'game' })
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
      await ui.press({ key: 'game-up' })
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
