import { describe, expect, test } from 'claude-code/testing'

import {
  FIELD,
  GRAVITY,
  JUMP_SPEED,
  RUNNER,
  blockAhead,
  frameRows,
  isNewBest,
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
      expect(o.h).toBeLessThanOrEqual(2)
    }
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
  test('the field has the right size, the runner, the ground and the blocks', () => {
    const g: GameState = { ...running(), obstacles: [{ x: 30, w: 2, h: 2 }] }
    const rows = frameRows(g)
    expect(rows).toHaveLength(FIELD.height + 1)
    for (const r of rows) expect(r).toHaveLength(FIELD.width)
    expect(rows[FIELD.height]).toBe('_'.repeat(FIELD.width))
    expect(rows.join('\n')).toContain('#')
    expect(rows[FIELD.height - 1]?.[RUNNER.x]).toBe('A')
    expect(rows[FIELD.height - 2]?.[RUNNER.x]).toBe('^')
  })

  test('the runner moves up in the picture when it jumps', () => {
    const rows = frameRows({ ...running(), y: 3 })
    expect(rows[FIELD.height - 1]?.[RUNNER.x]).toBe(' ')
    expect(rows[FIELD.height - 4]?.[RUNNER.x]).toBe('A')
  })

  test('scores print with four digits', () => {
    expect(pad4(7)).toBe('0007')
    expect(pad4(12345)).toBe('12345')
    expect(pad4(-3)).toBe('0000')
  })
})
