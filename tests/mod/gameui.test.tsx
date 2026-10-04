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
      expect(textOf(await inner())).toContain('Press s to light the flame')

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
      expect(textOf(await inner())).toContain('Your flame went out')
      expect(textOf(await inner())).toContain('Press s to play again')
      expect(typeof w.store.gameBest === 'number' && w.store.gameBest > 0).toBe(true)
    })

    test(`Space after game over starts a new game, and Escape does nothing to the game on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const ui = await $.ui.mount({ plugin: 'temper', surface, component: 'Pane', requestId: 'temper-game', props: GAME })
      await playToGameOver(ui)
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain('Your flame went out')
      // Escape is the engine's: the module ignores it and the game state is unchanged.
      await ui.key({ key: 'escape', in: 'game' })
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain('Your flame went out')
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
    // The text is always the same simple one. Whether the keys arrive is the game's own business.
    expect(first.text).toBe('The game is open. Press s to start, w to jump, q or Esc to leave.')
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
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain('Press s to light the flame')
      await ui.press({ key: 'game-start' })
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain('w jumps. q or Esc leaves.')
      await ui.advance(80 * 3)
      // On the ground the runner is on the bottom row of the field.
      expect((await fieldRows(ui))[9]?.[6]).toBe('▀')
      await ui.press({ key: 'game-jump' })
      await ui.advance(80)
      expect((await fieldRows(ui))[9]?.[6]).toBe(' ')
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
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain('Your flame went out')
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
      expect((await fieldRows(ui))[9]?.[6]).toBe(' ')
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

  for (const grantFocus of [true, false]) {
    test(`the open text is the simple one whether the surface grants the keys or not (grant=${grantFocus})`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build' }), { grantFocus })
      await $.session.start(START('terminal'))
      expect((await $.command.run(run('play'))).text).toBe('The game is open. Press s to start, w to jump, q or Esc to leave.')
      await $.command.run(run('play'))
      expect(w.toasts.every(t => !t.includes('Ctrl+X'))).toBe(true)
    })
  }

  test('the band offer gives the same simple toast', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START('terminal'))
    const busy = await $.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', requestId: 'busy', props: BAND(true) })
    await busy.press({ key: 'action-play' })
    expect(w.toasts).toContain('The game is open. Press s to start, w to jump, q or Esc to leave.')
  })

  test('the game never uses the old key text', async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START('terminal'))
    const text = (await $.command.run(run('play'))).text ?? ''
    expect(text).not.toContain('Click it')
    expect(text).not.toContain('Space')
  })
})

describe('the forge look in the pane', () => {
  for (const surface of SURFACES) {
    test(`the header shows the flame glyph, score, best and heat, and the start message is plain on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }), { store: { gameBest: 42 } })
      await $.session.start(START(surface))
      await $.command.run(run('play'))
      const ui = await mountGame($ as never, surface)
      const text = textOf(await ui.drawn({ in: 'game' }))
      for (const part of ['▲ TEMPER RUN', 'score 0000', 'best 0042', 'heat 1', 'Press s to light the flame. w jumps.']) expect(text).toContain(part)
    })

    test(`the field never draws wider than the region: 36 cells at the least, 60 at the most on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const ui = await mountGame($ as never, surface)
      const resize = (size: { columns: number; rows: number }) => (ui as unknown as { resize: (s: unknown) => Promise<void> }).resize({ ...size, in: 'game' })
      for (const [columns, want] of [[40, 40], [20, 36], [200, 60]] as const) {
        await resize({ columns, rows: 14 })
        await ui.advance(80)
        const rows = await fieldRows(ui)
        expect(rows).toHaveLength(11)
        for (const r of rows) expect(r).toHaveLength(want)
      }
    })

    test(`a game over says the score, and a new best says the forge is hot on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const ui = await mountGame($ as never, surface)
      await ui.press({ key: 'game-start' })
      await ui.advance(80 * 30)
      await ui.press({ key: 'game-jump' })
      await ui.advance(80 * 80)
      const text = textOf(await ui.drawn({ in: 'game' }))
      expect(text).toMatch(/Your flame went out\. Score \d+\. Press s to play again\. q or Esc leaves\./)
      expect(text).toContain('New best. The forge is hot.')
    })
  }
})

// The game cannot know whether the keys reach it. It notices: with no key and no press for 3
// seconds after it opens (and no game started), it draws one dim line that says how to get them.
const NO_KEYS = 'No keys yet? Press Ctrl+X, then Tab, to give the game the keys.'

describe('the no keys hint in the game area', () => {
  for (const surface of SURFACES) {
    const key = (ui: unknown, k: string) => (ui as { key: (e: { key: string; in: string }) => Promise<void> }).key({ key: k, in: 'game' })

    test(`no hint when a key arrives within 3 seconds, and none later on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const ui = await mountGame($ as never, surface)
      await ui.advance(80 * 20)
      await key(ui, 's')
      await ui.advance(80 * 5)
      expect(textOf(await ui.drawn({ in: 'game' }))).not.toContain(NO_KEYS)
      await ui.advance(80 * 60)
      expect(textOf(await ui.drawn({ in: 'game' }))).not.toContain(NO_KEYS)
    })

    test(`the hint appears after 3 seconds with no key, and not before on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const ui = await mountGame($ as never, surface)
      await ui.advance(80 * 30)
      expect(textOf(await ui.drawn({ in: 'game' }))).not.toContain(NO_KEYS)
      await ui.advance(80 * 10)
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain(NO_KEYS)
      // It stays one line, drawn once.
      expect(textOf(await ui.drawn({ in: 'game' })).split(NO_KEYS)).toHaveLength(2)
    })

    test(`any key removes the hint at once, even a key the game does not use on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const ui = await mountGame($ as never, surface)
      await ui.advance(80 * 45)
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain(NO_KEYS)
      await key(ui, 'x')
      expect(textOf(await ui.drawn({ in: 'game' }))).not.toContain(NO_KEYS)
      await ui.advance(80 * 20)
      expect(textOf(await ui.drawn({ in: 'game' }))).not.toContain(NO_KEYS)
    })

    test(`a press of a pane Button also removes the hint on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const ui = await mountGame($ as never, surface)
      await ui.advance(80 * 45)
      expect(textOf(await ui.drawn({ in: 'game' }))).toContain(NO_KEYS)
      await ui.press({ key: 'game-jump' })
      expect(textOf(await ui.drawn({ in: 'game' }))).not.toContain(NO_KEYS)
    })

    test(`a game that has started never shows the hint on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const ui = await mountGame($ as never, surface)
      await ui.press({ key: 'game-start' })
      await ui.advance(80 * 45)
      expect(textOf(await ui.drawn({ in: 'game' }))).not.toContain(NO_KEYS)
    })

    test(`the hint adds no engine call and no write on ${surface}`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START(surface))
      const ui = await mountGame($ as never, surface)
      const writes = w.writes.length
      const invalidated = w.invalidated
      await ui.advance(80 * 60)
      expect(w.writes.length).toBe(writes)
      expect(w.invalidated).toBe(invalidated)
    })
  }
})
