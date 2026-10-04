import { describe, expect, test } from 'claude-code/testing'

import { EMPTY, pieceStyle } from '../../hooks/temper-mod/core/merge'
import { BLUE, CARD_BG, FG, GREEN, MUTED, ORANGE, PINK, YELLOW, contrast, luminance } from '../../hooks/temper-mod/ui/palette'
import { runFiles } from './run-files'
import { world } from './world'

const SURFACES = ['terminal', 'desktop', 'vscode', 'mobile'] as const
const START = (surface: string | null) => ({ cwd: '/repo', surface, isInteractive: false }) as never

const PANE = { title: 'Temper', isFocused: false, bodyColumns: 80, placement: 'dock', scroll: { offset: 0, bodyRows: 20 }, view: {} } as const
const GAME = { title: 'Temper Merge', isFocused: false, bodyColumns: 80, placement: 'inline', scroll: { offset: 0, bodyRows: 12 }, view: {} } as const

type Node = { type?: string; props?: Record<string, unknown>; children?: unknown }

// Every Text node under `tree`, with the background it sits on: its own, or the nearest ancestor's.
type Seen = { text: string; props: Record<string, unknown>; bg: string | null }
function texts(tree: unknown, bg: string | null = null, out: Seen[] = []): Seen[] {
  if (typeof tree === 'string') return out
  if (Array.isArray(tree)) {
    for (const k of tree) texts(k, bg, out)
    return out
  }
  if (typeof tree !== 'object' || tree === null) return out
  const n = tree as Node
  const own = typeof n.props?.backgroundColor === 'string' ? (n.props.backgroundColor as string) : bg
  if (n.type === 'Text') out.push({ text: JSON.stringify(n.children ?? ''), props: n.props ?? {}, bg: own })
  texts(n.children, own, out)
  return out
}

const kinds = (tree: unknown, type: string, out: Node[] = []): Node[] => {
  if (Array.isArray(tree)) for (const k of tree) kinds(k, type, out)
  else if (typeof tree === 'object' && tree !== null) {
    const n = tree as Node
    if (n.type === type) out.push(n)
    kinds(n.children, type, out)
  }
  return out
}

// The rule for a card with its own background: it sets the background, and every text node inside
// sets an explicit colour with a contrast of 4.5 to 1 or more, never dims it, and never uses its own
// background as its colour.
function expectLegible(tree: unknown, label: string): void {
  const root = tree as Node
  expect(root.props?.backgroundColor, `${label}: the card sets a background`).toBe(CARD_BG)
  const all = texts(tree)
  expect(all.length, `${label}: has text`).toBeGreaterThan(0)
  for (const t of all) {
    const color = t.props.color
    expect(typeof color, `${label}: ${t.text} has an explicit colour`).toBe('string')
    expect(t.bg, `${label}: ${t.text} sits on a background`).not.toBeNull()
    expect(color, `${label}: ${t.text} is not its own background`).not.toBe(t.bg)
    expect(Number.isNaN(luminance(color as string)), `${label}: ${t.text} colour ${String(color)} is #rrggbb`).toBe(false)
    expect(contrast(color as string, t.bg as string), `${label}: ${t.text} contrast ${String(color)} on ${String(t.bg)}`).toBeGreaterThanOrEqual(4.5)
    expect(t.props.dimColor, `${label}: ${t.text} is not dimmed`).toBeFalsy()
  }
  expect(kinds(tree, 'Markdown'), `${label}: no Markdown (it takes the theme colour)`).toHaveLength(0)
}

describe('contrast helper', () => {
  test('black on white is 21 and a colour on itself is 1', () => {
    expect(Math.round(contrast('#000000', '#ffffff'))).toBe(21)
    expect(contrast('#336699', '#336699')).toBe(1)
  })
})

describe('the pane is legible on every theme', () => {
  for (const surface of SURFACES) {
    for (const stage of ['intent', 'plan', 'build', 'review', 'check'] as const) {
      test(`${stage}: explicit background and explicit colours on ${surface}`, async ($, on) => {
        world(on, { ...runFiles({ nextStage: stage, passedCriteria: ['AC-01'] }), '.temper/evidence/review.json': JSON.stringify([{ claim: 'x', severity: 'major' }]) })
        await $.session.start(START(surface))
        const ui = await $.ui.mount({ plugin: 'temper', surface, component: 'Pane', requestId: 'temper', props: PANE })
        await ui.press({ key: 'pane-more-actions' }).catch(() => undefined)
        expectLegible(await ui.drawn(), `${stage}/${surface}`)
      })
    }
  }

  test('the empty pane (no run) is legible too', async ($, on) => {
    world(on, {})
    await $.session.start(START('terminal'))
    const ui = await $.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'Pane', requestId: 'temper', props: PANE })
    expectLegible(await ui.drawn(), 'no run')
  })
})

describe('the game is legible on every theme', () => {
  for (const surface of ['terminal', 'desktop'] as const) {
    test(`the game area sets a background and explicit colours on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }), { options: undefined } as never)
      await $.session.start(START(surface))
      await $.command.run({ command: 'temper', args: 'play', origin: { kind: 'composer' } } as never)
      const ui = await $.ui.mount({ plugin: 'temper', surface, component: 'Pane', requestId: 'temper-game', props: GAME })
      expectLegible(await ui.drawn({ in: 'game' }), `game/${surface}`)
    })
  }
})

describe('every heat colour of a piece is legible on its own background', () => {
  test('text on a piece has a contrast of 4.5 or more, and the empty dot is legible on the card', () => {
    for (const v of [2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096]) {
      const s = pieceStyle(v)
      expect(contrast(s.color as string, s.bg as string), `piece ${v}: ${String(s.color)} on ${String(s.bg)}`).toBeGreaterThanOrEqual(4.5)
    }
    expect(contrast(EMPTY.color as string, CARD_BG)).toBeGreaterThanOrEqual(4.5)
  })

  test('every palette colour is legible on the card', () => {
    for (const c of [FG, MUTED, GREEN, BLUE, YELLOW, ORANGE, PINK]) expect(contrast(c, CARD_BG), c).toBeGreaterThanOrEqual(4.5)
  })
})

describe('what has no background keeps the theme colours', () => {
  test('the band, the hint tail and the question header set no background of their own', async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START('terminal'))
    const band = await $.ui.mount({
      plugin: 'temper',
      surface: 'terminal',
      component: 'AbovePrompt',
      props: { hasSurvey: false, isWorking: true, maxRows: 12, bodyColumns: 120, scroll: { offset: 0, bodyRows: 12 }, view: {} },
    })
    // The only background in the band is the chip of the phase you are in. Its text sets its own colour.
    const withBg = texts(await band.drawn()).filter(t => t.props.backgroundColor !== undefined)
    expect(withBg.length).toBeLessThanOrEqual(1)
    for (const t of withBg) {
      expect(typeof t.props.color, `${t.text} sets a colour`).toBe('string')
      expect(t.props.color).not.toBe(t.props.backgroundColor)
    }
  })
})
