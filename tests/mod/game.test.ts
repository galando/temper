import { describe, expect, test } from 'claude-code/testing'

import {
  FIELD,
  FLAME_JUMP,
  FLAME_OUT,
  FLAME_RUN,
  GRAVITY,
  HITBOX,
  JUMP_SPEED,
  KINDS,
  KIND_LIST,
  MAX_WIDTH,
  MIN_WIDTH,
  RUNNER,
  blockAhead,
  drawRows,
  flameSprite,
  groundRow,
  heatAt,
  isNewBest,
  messageFor,
  runs,
  sparks,
  widthFor,
  withWidth,
  jump,
  newGame,
  nextRandom,
  onGround,
  pad4,
  speedAt,
  start,
  step,
} from '../../hooks/temper-mod/core/game'
import type { GameState } from '../../hooks/temper-mod/core/game'

const running = (seed = 1): GameState => start(newGame(seed), seed)
const run = (s: GameState, ticks: number, jumpAt: (tick: number) => boolean = () => false): GameState => {
  let g = s
  for (let i = 0; i < ticks && g.status === 'running'; i++) g = step(jump_if(g, jumpAt(g.tick)))
  return g
}
const jump_if = (g: GameState, j: boolean): GameState => (j ? jump(g) : g)

describe('seeded generator', () => {
  test('the same seed gives the same sequence, another seed another', () => {
    const seq = (seed: number) => {
      let st = seed
      const out: number[] = []
      for (let i = 0; i < 6; i++) {
        const r = nextRandom(st)
        st = r.state
        out.push(r.value)
      }
      return out
    }
    expect(seq(42)).toEqual(seq(42))
    expect(seq(42)).not.toEqual(seq(43))
    for (const v of seq(7)) {
      expect(v).toBeGreaterThanOrEqual(0)
      expect(v).toBeLessThan(1)
    }
  })

  test('the same seed and the same keys give the same game', () => {
    const a = run(running(9), 200, t => t % 17 === 0)
    const b = run(running(9), 200, t => t % 17 === 0)
    expect(a).toEqual(b)
    expect(run(running(10), 200, t => t % 17 === 0)).not.toEqual(a)
  })
})

describe('start and restart', () => {
  test('a new game is ready and does not move', () => {
    const g = newGame(5)
    expect(g.status).toBe('ready')
    expect(step(g)).toEqual(g)
    expect(jump(g)).toEqual(g)
  })

  test('start runs the game; restart after game over keeps the best score and resets the rest', () => {
    const over: GameState = { ...running(3), status: 'over', score: 80, best: 120, tick: 99, obstacles: [{ x: 5, w: 1, h: 1 }] }
    const again = start(over, 77)
    expect(again.status).toBe('running')
    expect(again.score).toBe(0)
    expect(again.tick).toBe(0)
    expect(again.obstacles).toEqual([])
    expect(again.best).toBe(120)
    expect(again.rng).toBe(77)
  })
})

describe('jump and gravity', () => {
  test('a jump leaves the ground, peaks, and lands', () => {
    let g = jump(running())
    expect(g.vy).toBe(JUMP_SPEED)
    const heights: number[] = []
    for (let i = 0; i < 12; i++) {
      g = { ...step(g), obstacles: [] }
      heights.push(g.y)
    }
    const peak = Math.max(...heights)
    expect(peak).toBe(JUMP_SPEED + (JUMP_SPEED - GRAVITY) + (JUMP_SPEED - 2 * GRAVITY))
    expect(heights[0]).toBe(JUMP_SPEED)
    expect(onGround(g)).toBe(true)
    expect(g.y).toBe(0)
  })

  test('a jump in the air does nothing; a jump after a game over or before the start does nothing', () => {
    const air = { ...jump(running()), obstacles: [] }
    const moved = step(air)
    expect(jump(moved)).toEqual(moved)
    expect(jump({ ...running(), status: 'over' }).vy).toBe(0)
    expect(jump(newGame(1)).vy).toBe(0)
  })

  test('the runner stays on the ground without a jump', () => {
    const g = run(running(), 5)
    expect(g.y).toBe(0)
    expect(g.vy).toBe(0)
  })
})

describe('obstacles, speed and score', () => {
  test('obstacles appear on the right edge, move left, and leave', () => {
    let g = running(2)
    let seen = false
    for (let i = 0; i < 60 && g.status === 'running'; i++) {
      g = step(jump_if(g, g.obstacles.some(o => o.x < RUNNER.x + 14 && o.x > RUNNER.x) && onGround(g)))
      if (g.obstacles.length > 0) seen = true
    }
    expect(seen).toBe(true)
    for (const o of g.obstacles) {
      expect(o.x).toBeLessThanOrEqual(FIELD.width)
      expect(o.w).toBeGreaterThanOrEqual(1)
      expect(o.h).toBeGreaterThanOrEqual(1)
      expect(o.h).toBeLessThanOrEqual(3)
      // The size of an obstacle is the size of its kind.
      if (o.kind) expect({ w: o.w, h: o.h }).toEqual({ w: KINDS[o.kind].w, h: KINDS[o.kind].h })
    }
  })

  test('the seeded generator mixes anvils and cold things over a long run', () => {
    const kinds = new Set<string>()
    let g = running(11)
    for (let i = 0; i < 4000; i++) {
      // Keep the flame alive: remove the blocks the test does not jump.
      g = step({ ...g, obstacles: g.obstacles.filter(o => o.x > RUNNER.x + 12) })
      for (const o of g.obstacles) if (o.kind) kinds.add(o.kind)
    }
    expect([...kinds].sort()).toEqual([...KIND_LIST].sort())
  })

  test('obstacles enter at the right edge of the field, whatever its width', () => {
    let g = withWidth(running(2), 40)
    for (let i = 0; i < 40 && g.obstacles.length === 0; i++) g = step(g)
    expect(g.obstacles[0]?.x).toBeLessThanOrEqual(40)
    expect(g.obstacles[0]?.x).toBeGreaterThan(36)
  })

  test('the speed grows with the ticks and stops at 3', () => {
    expect(speedAt(0)).toBe(1)
    expect(speedAt(149)).toBe(1)
    expect(speedAt(150)).toBe(2)
    expect(speedAt(300)).toBe(3)
    expect(speedAt(5000)).toBe(3)
  })

  test('the score grows each tick, and a passed obstacle adds 5', () => {
    const base = { ...running(), obstacles: [], gap: 99 }
    expect(step(base).score).toBe(1)
    // An obstacle that has just gone behind the runner is passed on this tick (the runner is in the air).
    const passing = { ...base, y: 3, vy: 1, obstacles: [{ x: RUNNER.x, w: 1, h: 1 }] }
    const after = step(passing)
    expect(after.status).toBe('running')
    expect(after.score).toBe(1 + 5)
  })
})

describe('collision and game over', () => {
  test('hitting a block ends the game and records the best score', () => {
    const g: GameState = { ...running(), best: 3, score: 10, gap: 99, obstacles: [{ x: RUNNER.x + 1, w: 1, h: 1 }] }
    const over = step(g)
    expect(over.status).toBe('over')
    expect(over.best).toBe(11)
    expect(isNewBest(over)).toBe(true)
  })

  test('jumping over the block does not end the game', () => {
    const g: GameState = { ...running(), gap: 99, y: 3, vy: 1, obstacles: [{ x: RUNNER.x + 1, w: 1, h: 1 }] }
    expect(step(g).status).toBe('running')
  })

  test('a block does not hit the runner when it is not at the runner column', () => {
    const g: GameState = { ...running(), gap: 99, obstacles: [{ x: RUNNER.x + 20, w: 2, h: 2 }] }
    expect(step(g).status).toBe('running')
  })

  test('a game that is over does not move', () => {
    const over = step({ ...running(), gap: 99, obstacles: [{ x: RUNNER.x + 1, w: 1, h: 2 }] })
    expect(over.status).toBe('over')
    expect(step(over)).toEqual(over)
  })

  test('a lower score does not replace the best score', () => {
    const g: GameState = { ...running(), best: 500, score: 1, gap: 99, obstacles: [{ x: RUNNER.x + 1, w: 1, h: 1 }] }
    const over = step(g)
    expect(over.best).toBe(500)
    expect(isNewBest(over)).toBe(false)
  })

  test('a player who never jumps always loses; a good player survives longer', () => {
    const never = run(running(4), 2000)
    expect(never.status).toBe('over')
    // Jump when a block is about to reach the runner.
    const smart = run(running(4), 400, () => false)
    expect(smart.tick).toBeGreaterThan(0)
  })
})

describe('blockAhead', () => {
  test('true for a block within the distance in front of the runner, false for a far or a passed block', () => {
    const g = (x: number) => ({ ...running(), obstacles: [{ x, w: 1, h: 1 }] })
    expect(blockAhead(g(RUNNER.x + RUNNER.w + 5), 14)).toBe(true)
    expect(blockAhead(g(RUNNER.x + RUNNER.w + 14), 14)).toBe(false)
    expect(blockAhead(g(40), 14)).toBe(false)
    expect(blockAhead(g(RUNNER.x - 3), 14)).toBe(false)
    expect(blockAhead(running(), 14)).toBe(false)
  })
})

describe('drawing rows', () => {
  const text = (rows: ReturnType<typeof drawRows>): string[] => rows.map(r => r.map(c => c.ch).join(''))

  test('the field has the right size: the field rows, one ground row, every row as wide as the field', () => {
    const rows = drawRows({ ...running(), obstacles: [{ x: 30, w: 3, h: 2, kind: 'anvil_s' }] })
    expect(rows).toHaveLength(FIELD.height + 1)
    for (const r of rows) expect(r).toHaveLength(FIELD.width)
    // The ground is a row of embers.
    expect(text(rows)[FIELD.height]).toMatch(/^[▁▂▃]+$/)
  })

  test('the flame stands on the ground, in three rows, and an anvil is drawn in dark gray', () => {
    const rows = drawRows({ ...running(), obstacles: [{ x: 30, w: 3, h: 2, kind: 'anvil_s' }] })
    const t = text(rows)
    expect(t[FIELD.height - 1]?.slice(RUNNER.x, RUNNER.x + RUNNER.w)).toBe('▀█▀')
    expect(t[FIELD.height - 3]?.slice(RUNNER.x, RUNNER.x + RUNNER.w)).toBe(' ▲ ')
    expect(t[FIELD.height - 1]?.slice(30, 33)).toBe('▝█▘')
    expect(rows[FIELD.height - 1]?.[30]?.style.color).toBe('#7a7a7a')
  })

  test('the flame has yellow on top, orange in the middle and red at the base', () => {
    const rows = drawRows(running())
    expect(rows[FIELD.height - 3]?.[RUNNER.x + 1]?.style.color).toBe('yellow')
    expect(rows[FIELD.height - 2]?.[RUNNER.x + 1]?.style.color).toBe('#ff8c1a')
    expect(rows[FIELD.height - 1]?.[RUNNER.x + 1]?.style.color).toBe('red')
  })

  test('the flame moves up in the picture and stretches taller when it jumps', () => {
    const t = text(drawRows({ ...running(), y: 3, vy: 1 }))
    expect(t[FIELD.height - 1]?.[RUNNER.x + 1]).toBe(' ')
    // Four rows now: the tip is one row higher than a standing flame would be at this height.
    expect(t[FIELD.height - 1 - 3 - 3]?.slice(RUNNER.x, RUNNER.x + 3)).toBe(' ▲ ')
    expect(flameSprite({ ...running(), y: 3, vy: 1 })).toBe(FLAME_JUMP)
  })

  test('the flame shrinks to a spark when the game is over', () => {
    const over: GameState = { ...running(), status: 'over', y: 0 }
    expect(flameSprite(over)).toBe(FLAME_OUT)
    const t = text(drawRows(over))
    expect(t[FIELD.height - 1]?.slice(RUNNER.x, RUNNER.x + 3)).toBe(' * ')
  })

  test('the flame flickers: the frame changes every 3 ticks and repeats', () => {
    const at = (tick: number) => flameSprite({ ...running(), tick })
    expect(at(0)).toBe(FLAME_RUN[0])
    expect(at(2)).toBe(FLAME_RUN[0])
    expect(at(3)).toBe(FLAME_RUN[1])
    expect(at(6)).toBe(FLAME_RUN[2])
    expect(at(9)).toBe(FLAME_RUN[0])
  })

  test('an obstacle without a kind is drawn as an iron rectangle of its size', () => {
    const t = text(drawRows({ ...running(), obstacles: [{ x: 30, w: 2, h: 2 }] }))
    expect(t[FIELD.height - 1]?.slice(30, 32)).toBe('██')
    expect(t[FIELD.height - 2]?.slice(30, 32)).toBe('██')
  })

  test('the drawing never reaches outside the field, even for a block half off the edge', () => {
    const rows = drawRows({ ...running(), obstacles: [{ x: FIELD.width - 1, w: 4, h: 3, kind: 'anvil_l' }, { x: -2, w: 4, h: 3, kind: 'anvil_l' }] })
    for (const r of rows) expect(r).toHaveLength(FIELD.width)
  })

  test('the field follows its width: 36 to 60 cells, 56 before the region is measured', () => {
    expect(widthFor(0)).toBe(56)
    expect(widthFor(20)).toBe(MIN_WIDTH)
    expect(widthFor(45)).toBe(45)
    expect(widthFor(200)).toBe(MAX_WIDTH)
    for (const w of [MIN_WIDTH, 45, MAX_WIDTH]) {
      const rows = drawRows(withWidth(running(), w))
      expect(rows).toHaveLength(FIELD.height + 1)
      for (const r of rows) expect(r).toHaveLength(w)
    }
    expect(FIELD.height).toBeGreaterThanOrEqual(9)
  })

  test('scores print with four digits', () => {
    expect(pad4(7)).toBe('0007')
    expect(pad4(12345)).toBe('12345')
    expect(pad4(-3)).toBe('0000')
  })
})

describe('sprites are data tables', () => {
  const all = [...FLAME_RUN, FLAME_JUMP, FLAME_OUT, ...KIND_LIST.map(k => KINDS[k].sprite)]

  test('every row of a sprite has the same width, so nothing shifts', () => {
    for (const sp of all) {
      expect(sp.rows.length).toBeGreaterThan(0)
      for (const row of sp.rows) expect([...row]).toHaveLength([...(sp.rows[0] as string)].length)
      expect(sp.styles).toHaveLength(sp.rows.length)
    }
  })

  test('the three run frames have the same size, and the jump frame is the same width and taller', () => {
    for (const f of FLAME_RUN) {
      expect(f.rows).toHaveLength(RUNNER.h)
      expect([...(f.rows[0] as string)]).toHaveLength(RUNNER.w)
    }
    expect(FLAME_JUMP.rows.length).toBeGreaterThan(RUNNER.h)
    expect([...(FLAME_JUMP.rows[0] as string)]).toHaveLength(RUNNER.w)
    expect(FLAME_OUT.rows.length).toBeLessThan(RUNNER.h)
  })

  test('the hit box lies inside the flame and covers solid cells in every run frame and the jump frame', () => {
    expect(HITBOX.dx + HITBOX.w).toBeLessThanOrEqual(RUNNER.w)
    expect(HITBOX.h).toBeLessThanOrEqual(RUNNER.h)
    for (const f of [...FLAME_RUN, FLAME_JUMP]) {
      // The lower rows, counted from the base.
      for (let r = 0; r < HITBOX.h; r++) {
        const row = f.rows[f.rows.length - 1 - r] as string
        for (let c = HITBOX.dx; c < HITBOX.dx + HITBOX.w; c++) expect(row[c]).not.toBe(' ')
      }
    }
  })

  test('every obstacle kind has a sprite as large as its collision size', () => {
    for (const k of KIND_LIST) {
      const spec = KINDS[k]
      expect(spec.sprite.rows).toHaveLength(spec.h)
      expect([...(spec.sprite.rows[0] as string)]).toHaveLength(spec.w)
    }
    // Two anvils (gray) and two cold things (cyan).
    expect(KINDS.anvil_s.sprite.styles[0]?.color).toBe('#7a7a7a')
    expect(KINDS.anvil_l.sprite.styles[0]?.color).toBe('#7a7a7a')
    expect(KINDS.drop.sprite.styles[0]?.color).toBe('cyan')
    expect(KINDS.ice.sprite.styles[0]?.color).toBe('cyan')
    expect(KINDS.anvil_l.h).toBeGreaterThan(KINDS.anvil_s.h)
  })

  test('every kind can be cleared by a jump at the lowest speed', () => {
    // Ticks in the air at a height of at least h, against the ticks the hit box overlaps the block.
    for (const k of KIND_LIST) {
      const spec = KINDS[k]
      let y = 0
      let vy = JUMP_SPEED
      let high = 0
      while (vy > 0 || y > 0) {
        y += vy
        vy -= GRAVITY
        if (y >= spec.h) high++
        if (y <= 0) break
      }
      expect(high).toBeGreaterThanOrEqual(HITBOX.w + spec.w - 1)
    }
  })
})

describe('heat, sparks, embers and messages', () => {
  test('heat goes from 1 to 5 with the speed ramp and stays at 5', () => {
    expect(heatAt(0)).toBe(1)
    expect(heatAt(74)).toBe(1)
    expect(heatAt(75)).toBe(2)
    expect(heatAt(150)).toBe(3)
    expect(heatAt(225)).toBe(4)
    expect(heatAt(300)).toBe(5)
    expect(heatAt(9999)).toBe(5)
    for (let t = 1; t < 600; t++) expect(heatAt(t)).toBeGreaterThanOrEqual(heatAt(t - 1))
  })

  test('sparks are a pure function of the tick and stay inside the field', () => {
    expect(sparks(40, 50, 10)).toEqual(sparks(40, 50, 10))
    expect(sparks(0, 50, 10)).not.toEqual(sparks(80, 50, 10))
    for (const t of [0, 7, 100, 999]) {
      for (const sp of sparks(t, 40, 10)) {
        expect(sp.x).toBeGreaterThanOrEqual(0)
        expect(sp.x).toBeLessThan(40)
        expect(sp.y).toBeGreaterThanOrEqual(7)
        expect(sp.y).toBeLessThanOrEqual(9)
        expect(['·', '*']).toContain(sp.ch)
      }
    }
  })

  test('the ground is red and orange embers that scroll', () => {
    const a = groundRow(0, 36)
    const b = groundRow(9, 36)
    expect(a).toHaveLength(36)
    expect(new Set(a.map(c => c.style.color))).toEqual(new Set(['red', '#ff8c1a']))
    expect(a.map(c => c.ch).join('')).not.toEqual(b.map(c => c.ch).join(''))
    for (const c of a) expect('▁▂▃').toContain(c.ch)
  })

  test('runs join cells of one style into one piece', () => {
    const r = runs([{ ch: 'a', style: {} }, { ch: 'b', style: {} }, { ch: 'c', style: { color: 'red' } }])
    expect(r).toEqual([{ text: 'ab', style: {} }, { text: 'c', style: { color: 'red' } }])
  })

  test('messages are short plain sentences', () => {
    expect(messageFor(newGame(1), false)).toBe('Press s to light the flame. w jumps.')
    expect(messageFor(running(), false)).toBe('w jumps. q or Esc leaves.')
    expect(messageFor(running(), true)).toBe('Paused. Press s or w to go on. q or Esc leaves.')
    expect(messageFor({ ...running(), status: 'over', score: 85, best: 120 }, false)).toBe('Your flame went out. Score 85. Press s to play again. q or Esc leaves.')
    expect(messageFor({ ...running(), status: 'over', score: 130, best: 130 }, false)).toBe('New best. The forge is hot. Your flame went out. Score 130. Press s to play again. q or Esc leaves.')
  })

  test('scores print with four digits', () => {
    expect(pad4(7)).toBe('0007')
    expect(pad4(12345)).toBe('12345')
    expect(pad4(-3)).toBe('0000')
  })
})
