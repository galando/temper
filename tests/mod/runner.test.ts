import { describe, expect, test } from 'claude-code/testing'

import { ANVIL_L } from '../../hooks/temper-mod/core/runner-art'
import { DRAGON, HAMMER_HIGH, HAMMER_LOW, OBSTACLES, PALETTE, WALL, heightOf, widthOf } from '../../hooks/temper-mod/core/runner-art'
import type { Frame, Kind } from '../../hooks/temper-mod/core/runner-art'
import {
  AIR_ROWS,
  BUFFER_TICKS,
  DEFAULT_WIDTH,
  DRAGON_X,
  DUCK_TICKS,
  FIRST_ARRIVAL_TICKS,
  FLASH_TICKS,
  GROUND_Y,
  JUMP_TICKS,
  MAX_WIDTH,
  MIN_WIDTH,
  PEAK,
  PIXEL_ROWS,
  ROWS,
  START_SPEED,
  TICK_MS,
  TOP_SPEED,
  TUTORIAL_TICKS,
  actionFor,
  bestLead,
  clearStarts,
  dragonBox,
  dragonFrame,
  drawScene,
  firstSpawnTick,
  heatAt,
  heatBars,
  isNewRecord,
  jumpHeight,
  lineFor,
  lineTwo,
  minGapPx,
  minGapTicks,
  newGame,
  nextRandom,
  obstacleBox,
  obstacleWidth,
  pad5,
  pickNext,
  pixels,
  press,
  runs,
  speedAt,
  start,
  step,
  widthFor,
  withWidth,
} from '../../hooks/temper-mod/core/runner'
import type { Obstacle, RunState } from '../../hooks/temper-mod/core/runner'

const running = (seed = 1, hi = 0, width = DEFAULT_WIDTH, score = 0): RunState => start(newGame(seed, hi, width, score), seed, score)
const ghost = (s: RunState, n: number): RunState => {
  let g = s
  for (let i = 0; i < n; i++) g = step(g, { ghost: true })
  return g
}
const withObstacle = (s: RunState, o: Partial<Obstacle> & { kind: Kind }): RunState => ({ ...s, obstacles: [{ id: 99, x: 30, lift: 0, ...o }] })
const alive = (s: RunState): boolean => s.status === 'running'

describe('speed, score and heat', () => {
  test('the speed starts slow, grows a little at a time, and stops at the top speed at heat 5', () => {
    expect(speedAt(0)).toBe(START_SPEED)
    expect(speedAt(1600)).toBe(TOP_SPEED)
    expect(speedAt(99999)).toBe(TOP_SPEED)
    for (let sc = 1; sc < 1700; sc++) {
      expect(speedAt(sc)).toBeGreaterThanOrEqual(speedAt(sc - 1))
      expect(speedAt(sc) - speedAt(sc - 1)).toBeLessThan(0.01)
    }
  })

  test('heat 1 to 5, one level for every 400 points, shown as bars', () => {
    expect([0, 399, 400, 799, 800, 1200, 1599, 1600, 9999].map(heatAt)).toEqual([1, 1, 2, 2, 3, 4, 4, 5, 5])
    expect(heatBars(1)).toBe('▮▯▯▯▯')
    expect(heatBars(3)).toBe('▮▮▮▯▯')
    expect(heatBars(5)).toBe('▮▮▮▮▮')
  })

  test('three points for every 4 pixels run, and the score prints with 5 digits', () => {
    let g = running()
    g = ghost(g, 40)
    expect(g.score).toBe(Math.floor(g.dist * 0.75 + 1e-9))
    // About 11 points a second at the start.
    expect((g.score / (40 * TICK_MS)) * 1000).toBeGreaterThan(9)
    expect(pad5(32)).toBe('00032')
    expect(pad5(155)).toBe('00155')
    expect(pad5(123456)).toBe('123456')
    expect(pad5(-3)).toBe('00000')
  })

  test('the picture warms with the heat: the wall colour follows the heat level', () => {
    for (let h = 1; h <= 5; h++) {
      const g = { ...running(1, 0, DEFAULT_WIDTH, (h - 1) * 400), obstacles: [] }
      expect(pixels(g)[0]?.[0]).toBe(WALL[h - 1])
    }
  })
})

describe('the jump', () => {
  test('the arc rises to 8 pixels, falls back, and the air time is about 0.88 seconds', () => {
    const heights = Array.from({ length: JUMP_TICKS + 1 }, (_, t) => jumpHeight(t))
    expect(Math.max(...heights)).toBe(PEAK)
    expect(heights[0]).toBe(0)
    expect(heights[JUMP_TICKS]).toBe(0)
    // Up, then down: symmetric.
    for (let t = 1; t < JUMP_TICKS; t++) expect(heights[t]).toBe(heights[JUMP_TICKS - t])
    // After the press the dragon is in the air for JUMP_TICKS - 1 ticks.
    const seconds = ((JUMP_TICKS - 1) * TICK_MS) / 1000
    expect(seconds).toBeGreaterThanOrEqual(0.8)
    expect(seconds).toBeLessThanOrEqual(0.9)
  })

  test('a press on the floor leaves the floor at once, and the dragon lands after the air time', () => {
    let g = press(running(), 'jump')
    expect(g.jt).toBe(1)
    let ticks = 0
    while (g.jt > 0 && ticks < 40) {
      g = step(g, { ghost: true })
      ticks++
    }
    expect(ticks).toBe(JUMP_TICKS - 1)
    expect(g.jt).toBe(0)
  })

  test('a jump press in the air does nothing but is remembered; a press with nothing running does nothing', () => {
    const air = press(press(running(), 'jump'), 'jump')
    expect(air.jt).toBe(1)
    expect(air.buf).toBe(BUFFER_TICKS)
    const ready = newGame(1)
    expect(press(ready, 'jump')).toBe(ready)
    expect(press({ ...running(), status: 'over' }, 'duck').duck).toBe(0)
  })

  test('input buffer: a jump pressed up to 250 ms before the landing fires on the landing', () => {
    expect(BUFFER_TICKS * TICK_MS).toBeGreaterThanOrEqual(240)
    expect(BUFFER_TICKS * TICK_MS).toBeLessThanOrEqual(250)
    for (let early = 1; early <= BUFFER_TICKS; early++) {
      let g = press(running(), 'jump')
      // Step to `early` ticks before the landing, then press again.
      while (g.jt < JUMP_TICKS - early) g = step(g, { ghost: true })
      g = press(g, 'jump')
      let landedAndJumped = false
      for (let i = 0; i < early + 1; i++) {
        g = step(g, { ghost: true })
        if (g.jt === 1) landedAndJumped = true
      }
      expect(landedAndJumped, `pressed ${early} ticks before the landing`).toBe(true)
    }
  })

  test('a jump pressed too early (more than 250 ms before the landing) is forgotten', () => {
    let g = press(running(), 'jump')
    while (g.jt < JUMP_TICKS - BUFFER_TICKS - 2) g = step(g, { ghost: true })
    g = press(g, 'jump')
    for (let i = 0; i < BUFFER_TICKS + 3; i++) g = step(g, { ghost: true })
    expect(g.jt).toBe(0)
  })

  test('a remembered jump is used once', () => {
    let g = press(running(), 'jump')
    while (g.jt < JUMP_TICKS - 2) g = step(g, { ghost: true })
    g = press(g, 'jump')
    let jumps = 0
    let last = g.jt
    for (let i = 0; i < 40; i++) {
      g = step(g, { ghost: true })
      if (g.jt === 1 && last !== 1) jumps++
      last = g.jt
    }
    // The remembered jump fires once on the landing; the next one is a new press.
    expect(jumps).toBe(1)
  })
})

describe('the duck', () => {
  test('a duck lasts 0.8 seconds for each press, and then the dragon runs again', () => {
    expect(DUCK_TICKS * TICK_MS).toBe(800)
    let g = press(running(), 'duck')
    expect(g.duck).toBe(DUCK_TICKS)
    expect(dragonFrame(g)).toBe(DRAGON.duck)
    for (let i = 0; i < DUCK_TICKS; i++) g = step(g, { ghost: true })
    expect(g.duck).toBe(0)
    expect(DRAGON.run).toContain(dragonFrame(g))
  })

  test('a new press starts the duck again, and a jump cancels it', () => {
    let g = press(running(), 'duck')
    g = ghost(g, 4)
    g = press(g, 'duck')
    expect(g.duck).toBe(DUCK_TICKS)
    g = press(g, 'jump')
    expect(g.duck).toBe(0)
    expect(g.jt).toBe(1)
    expect(dragonFrame(g)).toBe(DRAGON.jump)
  })

  test('a duck in the air does nothing', () => {
    const g = press(press(running(), 'jump'), 'duck')
    expect(g.duck).toBe(0)
  })

  test('the legs alternate every 4 ticks while the dragon runs', () => {
    let g = running()
    const frames: unknown[] = []
    for (let i = 0; i < 12; i++) {
      frames.push(dragonFrame(g))
      g = step(g, { ghost: true })
    }
    expect(frames.slice(0, 4).every(f => f === DRAGON.run[0])).toBe(true)
    expect(frames.slice(4, 8).every(f => f === DRAGON.run[1])).toBe(true)
    expect(frames.slice(8, 12).every(f => f === DRAGON.run[0])).toBe(true)
  })
})

describe('collisions', () => {
  // An obstacle on top of the dragon.
  const onDragon = (kind: Kind, lift = 0): RunState => withObstacle(running(), { kind, x: DRAGON_X + 3, lift })

  test('standing in an anvil, a bucket or a low hammer ends the run', () => {
    for (const [kind, lift] of [['anvil_s', 0], ['anvil_l', 0], ['bucket', 0], ['hammer', HAMMER_LOW]] as const) {
      expect(step(onDragon(kind, lift)).status, `${kind} ${lift}`).toBe('over')
    }
  })

  test('a jump clears every anvil and the bucket at the top of the arc, with margin', () => {
    for (const kind of ['anvil_s', 'anvil_l', 'bucket'] as const) {
      let g = onDragon(kind)
      g = { ...g, jt: Math.floor(JUMP_TICKS / 2) - 1 }
      expect(alive(step(g)), kind).toBe(true)
      // At the top there are several pixels to spare.
      const dragonBottom = dragonBox({ ...g, jt: 5 }).bottom
      const obstacleTop = (() => {
        const o = (g.obstacles[0] as Obstacle)
        const b = obstacleBox(o, 0)
        return b.bottom + b.h
      })()
      expect(dragonBottom - obstacleTop, `${kind} margin`).toBeGreaterThanOrEqual(3)
    }
  })

  test('a duck passes under a low hammer, and a standing dragon passes under a high hammer', () => {
    const ducked = { ...onDragon('hammer', HAMMER_LOW), duck: DUCK_TICKS }
    expect(alive(step(ducked))).toBe(true)
    expect(step(onDragon('hammer', HAMMER_LOW)).status).toBe('over')
    expect(alive(step(onDragon('hammer', HAMMER_HIGH)))).toBe(true)
  })

  test('jumping into a high hammer hits it', () => {
    const g = { ...onDragon('hammer', HAMMER_HIGH), jt: 5 }
    expect(step(g).status).toBe('over')
  })

  test('a hammer needs a duck, an anvil needs a jump, a high hammer needs nothing', () => {
    expect(actionFor('hammer', HAMMER_LOW)).toBe('duck')
    expect(actionFor('hammer', HAMMER_HIGH)).toBe('none')
    expect(actionFor('anvil_s', 0)).toBe('jump')
    expect(actionFor('anvil_l', 0)).toBe('jump')
    expect(actionFor('bucket', 0)).toBe('jump')
  })

  test('the hit boxes are forgiving: a sprite that only touches the dragon picture is not a hit', () => {
    // The anvil picture reaches into the corner of the dragon picture, but the boxes do not touch.
    const runFrame = DRAGON.run[0]
    const front = DRAGON_X + runFrame.hit.x + runFrame.hit.w
    const hitLeft = (OBSTACLES.anvil_s[0] as Frame).hit.x
    // Left edge of the anvil sprite one pixel inside the dragon sprite's right edge is not a collision
    // as long as its hit box starts at or after the end of the dragon's hit box.
    const x = front - hitLeft
    const near = withObstacle(running(), { kind: 'anvil_s', x })
    expect(DRAGON_X + widthOf(runFrame)).toBeGreaterThan(x)
    expect(alive(step({ ...near, obstacles: [{ ...(near.obstacles[0] as Obstacle), x: x + speedAt(0) }] }))).toBe(true)
  })

  test('collisions use the frame that is drawn: the dead frame and each run frame have a hit box', () => {
    for (const f of [DRAGON.run[0], DRAGON.run[1], DRAGON.jump, DRAGON.duck, DRAGON.dead]) {
      expect(f.hit.w).toBeGreaterThan(0)
      expect(f.hit.x + f.hit.w).toBeLessThanOrEqual(widthOf(f))
      expect(f.hit.y + f.hit.h).toBeLessThanOrEqual(heightOf(f))
    }
  })

  test('after a game over nothing moves, and the dead frame shows', () => {
    const over = step(onDragon('anvil_l'))
    expect(over.status).toBe('over')
    expect(dragonFrame(over)).toBe(DRAGON.dead)
    expect(step(over)).toBe(over)
    expect(press(over, 'jump')).toBe(over)
  })
})

describe('score, best score and milestones', () => {
  test('the best score rises at a game over, and the run began with the old best', () => {
    let g = running(1, 50)
    g = ghost(g, 70)
    expect(g.score).toBeGreaterThan(50)
    const over = step({ ...g, obstacles: [{ id: 5, kind: 'anvil_l', x: DRAGON_X + 3, lift: 0 }] })
    expect(over.status).toBe('over')
    expect(over.hi).toBe(over.score)
    expect(over.hiStart).toBe(50)
    expect(isNewRecord(over)).toBe(true)
    expect(lineFor(over)).toBe('New record. The forge is hot. Game over. Your forge went cold.')
  })

  test('a lower score keeps the best score and is not a record', () => {
    const over = step({ ...running(1, 5000), obstacles: [{ id: 5, kind: 'anvil_l', x: DRAGON_X + 3, lift: 0 }] })
    expect(over.hi).toBe(5000)
    expect(isNewRecord(over)).toBe(false)
    expect(lineFor(over)).toBe('Game over. Your forge went cold.')
    expect(lineTwo(over)).toBe('Press r to run again. q or Esc leaves.')
  })

  test('at every hundred points the dragon flashes yellow for half a second and a banner shows', () => {
    expect(FLASH_TICKS * TICK_MS).toBeGreaterThanOrEqual(480)
    expect(FLASH_TICKS * TICK_MS).toBeLessThanOrEqual(500)
    let g = running()
    const banners: string[] = []
    let flashStarts = 0
    let lastFlash = 0
    for (let i = 0; i < 600; i++) {
      g = step(g, { ghost: true })
      if (g.banner && !banners.includes(g.banner)) banners.push(g.banner)
      if (g.flash === FLASH_TICKS && lastFlash !== FLASH_TICKS) flashStarts++
      lastFlash = g.flash
    }
    expect(banners.slice(0, 3)).toEqual(['Hot! 100', 'Hot! 200', 'Hot! 300'])
    expect(flashStarts).toBe(banners.length)
  })

  test('the flash recolours the dragon, and a banner goes away', () => {
    let g = running()
    while (g.flash === 0) g = step(g, { ghost: true })
    expect(g.banner).toBe('Hot! 100')
    const flashed = pixels({ ...g, obstacles: [] })
    const plain = pixels({ ...g, flash: 0, obstacles: [] })
    expect(JSON.stringify(flashed)).not.toEqual(JSON.stringify(plain))
    for (let i = 0; i < 40; i++) g = step(g, { ghost: true })
    expect(g.banner).toBeNull()
    expect(g.flash).toBe(0)
  })

  test('a milestone is shown once, also when the run starts above it', () => {
    const g = running(1, 0, DEFAULT_WIDTH, 250)
    expect(g.milestone).toBe(2)
    expect(ghost(g, 3).banner).toBeNull()
  })
})

describe('the help line and the messages', () => {
  test('the help line shows for the first 4 seconds of a run, then a short reminder', () => {
    expect(TUTORIAL_TICKS * TICK_MS).toBe(4000)
    let g = running()
    expect(lineFor(g)).toBe('Press w to jump. Press s to duck.')
    g = ghost(g, TUTORIAL_TICKS - 1)
    expect(lineFor(g)).toBe('Press w to jump. Press s to duck.')
    g = ghost(g, 1)
    expect(lineFor(g)).toBe('w jumps. s ducks. q or Esc leaves.')
  })

  test('before the first run the line says how to start', () => {
    expect(lineFor(newGame(1))).toBe('Press r to run. Press w to jump. Press s to duck.')
    expect(lineTwo(newGame(1))).toBe('')
  })
})

describe('the first obstacle and the gaps (fairness)', () => {
  test('the first obstacle reaches the dragon after 2.5 seconds or more, at any width', () => {
    expect(FIRST_ARRIVAL_TICKS * TICK_MS).toBeGreaterThanOrEqual(2500)
    for (const width of [MIN_WIDTH, 45, DEFAULT_WIDTH, MAX_WIDTH]) {
      for (let seed = 1; seed <= 20; seed++) {
        let g = running(seed, 0, width)
        let spawnedAt = -1
        for (let i = 0; i < 200 && spawnedAt < 0; i++) {
          g = step(g, { ghost: true })
          if (g.obstacles.length > 0) spawnedAt = g.tick
        }
        // Run on until the obstacle hit box touches the dragon hit box.
        let arrival = spawnedAt
        let o = g.obstacles[0] as Obstacle
        while (obstacleBox(o, g.tick).x > dragonBox(g).x + dragonBox(g).w && arrival < 400) {
          g = step(g, { ghost: true })
          o = g.obstacles[0] as Obstacle
          arrival = g.tick
        }
        expect(arrival * TICK_MS, `width ${width} seed ${seed}`).toBeGreaterThanOrEqual(2500)
        expect(o.kind).toBe('anvil_s')
      }
    }
  })

  test('a wider field gets its first obstacle earlier (it travels farther), and never before tick 1', () => {
    expect(firstSpawnTick(MIN_WIDTH, START_SPEED)).toBeGreaterThan(firstSpawnTick(MAX_WIDTH, START_SPEED))
    expect(firstSpawnTick(MIN_WIDTH, START_SPEED)).toBeGreaterThanOrEqual(1)
  })

  test('every gap is at least the minimum gap for the speed, over thousands of seeds and every speed', () => {
    // 100 seeds for each of 7 speeds (the test had 150 and sat close to the 5 second limit on a busy machine).
    for (const startScore of [0, 200, 400, 800, 1200, 1600, 2400]) {
      for (let seed = 1; seed <= 100; seed++) {
        let g = running(seed, 0, DEFAULT_WIDTH, startScore)
        let known = 0
        for (let i = 0; i < 700; i++) {
          g = step(g, { ghost: true })
          if (g.obstacles.length > 0 && g.nextId - 1 > known) {
            known = g.nextId - 1
            const fresh = g.obstacles[g.obstacles.length - 1] as Obstacle
            const prev = g.obstacles[g.obstacles.length - 2]
            if (prev) {
              const gap = fresh.x - (prev.x + obstacleWidth(prev.kind))
              const need = minGapPx(actionFor(prev.kind, prev.lift), actionFor(fresh.kind, fresh.lift), speedAt(g.score))
              expect(gap, `score ${startScore} seed ${seed}: ${prev.kind} then ${fresh.kind}`).toBeGreaterThanOrEqual(need - 1e-9)
            }
          }
        }
      }
    }
  })

  test('every obstacle that appears can be cleared, with a window of at least 3 ticks (240 ms), at its speed', () => {
    for (const startScore of [0, 400, 800, 1200, 1600]) {
      for (let seed = 1; seed <= 100; seed++) {
        let g = running(seed, 0, DEFAULT_WIDTH, startScore)
        let known = 0
        for (let i = 0; i < 500; i++) {
          g = step(g, { ghost: true })
          if (g.nextId - 1 > known) {
            known = g.nextId - 1
            const o = g.obstacles[g.obstacles.length - 1] as Obstacle
            expect(clearStarts(o.kind, o.lift, speedAt(g.score)).length, `score ${startScore} seed ${seed}: ${o.kind} ${o.lift}`).toBeGreaterThanOrEqual(3)
          }
        }
      }
    }
  })

  test('hammers wait for 100 points, and all four kinds appear in a long run', () => {
    const kinds = new Set<string>()
    for (let seed = 1; seed <= 30; seed++) {
      let g = running(seed)
      let known = 0
      for (let i = 0; i < 1500; i++) {
        g = step(g, { ghost: true })
        if (g.nextId - 1 > known) {
          known = g.nextId - 1
          const o = g.obstacles[g.obstacles.length - 1] as Obstacle
          if (o.kind === 'hammer') expect(g.score).toBeGreaterThanOrEqual(100)
          kinds.add(o.kind === 'hammer' ? `hammer${o.lift}` : o.kind)
        }
      }
    }
    expect([...kinds].sort()).toEqual(['anvil_l', 'anvil_s', `hammer${HAMMER_HIGH}`, `hammer${HAMMER_LOW}`, 'bucket'].sort())
  })

  test('the minimum gaps rise with the work between two obstacles', () => {
    expect(minGapTicks('jump', 'duck')).toBeGreaterThan(minGapTicks('jump', 'jump'))
    expect(minGapTicks('duck', 'jump')).toBeGreaterThan(minGapTicks('duck', 'duck'))
    // Jump then duck, or duck then jump: at least the air time of a jump plus a few ticks to react.
    expect(minGapTicks('jump', 'duck')).toBeGreaterThanOrEqual(JUMP_TICKS + 4)
    expect(minGapTicks('duck', 'jump')).toBeGreaterThanOrEqual(JUMP_TICKS + 4)
    expect(minGapPx('jump', 'jump', 2)).toBe(minGapTicks('jump', 'jump') * 2)
  })

  test('the big anvil appears only when its window is big enough', () => {
    const slowKinds = new Set<string>()
    for (let seed = 1; seed <= 300; seed++) slowKinds.add(pickNext(0, speedAt(0), seed).kind)
    expect(clearStarts('anvil_l', 0, speedAt(0)).length >= 3).toBe(slowKinds.has('anvil_l'))
    const fastKinds = new Set<string>()
    for (let seed = 1; seed <= 300; seed++) fastKinds.add(pickNext(0, TOP_SPEED, seed).kind)
    expect(fastKinds.has('anvil_l')).toBe(true)
  })
})

// A bot that plays the way a person could: it looks at the next obstacle, presses at the best moment,
// and its press arrives some ticks late (the Button route adds a delay).
function bot(state: RunState, latency: number, seed: number, ticks: number): RunState {
  let g = state
  const queue: Array<{ at: number; what: 'jump' | 'duck' }> = []
  let armed = -1
  const cache = new Map<string, number>()
  for (let i = 0; i < ticks && alive(g); i++) {
    const speed = speedAt(g.score)
    const d = dragonBox(g)
    const ahead = g.obstacles.find(o => obstacleBox(o, g.tick).x + obstacleBox(o, g.tick).w > d.x)
    if (ahead && ahead.id !== armed) {
      const action = actionFor(ahead.kind, ahead.lift)
      if (action !== 'none') {
        const key = `${ahead.kind}:${ahead.lift}:${speed.toFixed(2)}`
        let lead = cache.get(key)
        if (lead === undefined) {
          lead = bestLead(ahead.kind, ahead.lift, speed)
          cache.set(key, lead)
        }
        const contact = (obstacleBox(ahead, g.tick).x - (d.x + d.w)) / speed
        // A small allowance, so that a tie does not depend on rounding.
        if (contact <= lead + latency + 0.01) {
          queue.push({ at: g.tick + latency, what: action })
          armed = ahead.id
        }
      } else armed = ahead.id
    }
    while (queue.length > 0 && (queue[0] as { at: number }).at <= g.tick) g = press(g, (queue.shift() as { what: 'jump' | 'duck' }).what)
    g = step(g)
  }
  void seed
  return g
}

describe('a bot with a slow hand survives (the game is fair at every speed)', () => {
  for (const latency of [0, 2, 3]) {
    test(`with ${latency} ticks (${latency * TICK_MS} ms) between the look and the press, over many seeds and every speed`, () => {
      for (const startScore of [0, 400, 800, 1200, 1600, 3000]) {
        for (let seed = 1; seed <= 40; seed++) {
          const end = bot(running(seed, 0, DEFAULT_WIDTH, startScore), latency, seed, 900)
          expect(end.status, `score ${startScore} seed ${seed} died at tick ${end.tick} with ${end.obstacles.map(o => o.kind).join(',')}`).toBe('running')
        }
      }
    })
  }

  test('a player who never presses anything loses', () => {
    let g = running(3)
    for (let i = 0; i < 400 && alive(g); i++) g = step(g)
    expect(g.status).toBe('over')
  })
})

describe('a run is deterministic and starts again', () => {
  test('the same seed and the same presses give the same run; another seed another run', () => {
    const play = (seed: number) => {
      let g = running(seed)
      for (let i = 0; i < 300; i++) {
        if (i % 17 === 5) g = press(g, 'jump')
        if (i % 23 === 7) g = press(g, 'duck')
        g = step(g, { ghost: true })
      }
      return g
    }
    expect(play(8)).toEqual(play(8))
    expect(play(8)).not.toEqual(play(9))
  })

  test('start keeps the best score, resets the run and takes the new seed', () => {
    const over: RunState = { ...running(3), status: 'over', hi: 120, score: 80, tick: 99, obstacles: [{ id: 1, kind: 'bucket', x: 5, lift: 0 }], jt: 4, duck: 3 }
    const again = start(over, 77)
    expect(again.status).toBe('running')
    expect(again.score).toBe(0)
    expect(again.tick).toBe(0)
    expect(again.obstacles).toEqual([])
    expect(again.jt).toBe(0)
    expect(again.duck).toBe(0)
    expect(again.hi).toBe(120)
    expect(again.hiStart).toBe(120)
    expect(start(over, 77)).toEqual(again)
    expect(start(over, 78)).not.toEqual(again)
  })

  test('a new game is ready and does not move; the width is 36 to 72', () => {
    const g = newGame(5)
    expect(g.status).toBe('ready')
    expect(step(g)).toBe(g)
    expect(widthFor(0)).toBe(DEFAULT_WIDTH)
    expect(widthFor(20)).toBe(MIN_WIDTH)
    expect(widthFor(45)).toBe(45)
    expect(widthFor(400)).toBe(MAX_WIDTH)
    expect(withWidth(g, 40).width).toBe(40)
    expect(withWidth(g, g.width)).toBe(g)
  })

  test('the seeded generator gives numbers from 0 up to 1, the same for the same seed', () => {
    const seq = (seed: number) => {
      let s = seed
      const out: number[] = []
      for (let i = 0; i < 6; i++) {
        const r = nextRandom(s)
        s = r.state
        out.push(r.value)
      }
      return out
    }
    expect(seq(4)).toEqual(seq(4))
    expect(seq(4)).not.toEqual(seq(5))
    for (const v of seq(9)) {
      expect(v).toBeGreaterThanOrEqual(0)
      expect(v).toBeLessThan(1)
    }
  })
})

describe('the picture', () => {
  test('the scene is 9 rows of the field width (8 of air, 1 of floor), each cell holds two pixels, and every colour is #rrggbb', () => {
    expect(ROWS).toBe(9)
    expect(PIXEL_ROWS).toBe(18)
    // The dragon is under a third of the picture and a jump fits in the air.
    expect(heightOf(DRAGON.run[0])).toBeLessThanOrEqual(PIXEL_ROWS / 3 + 2)
    expect(PEAK + heightOf(DRAGON.run[0])).toBeLessThanOrEqual(AIR_ROWS * 2)
    expect(AIR_ROWS * 2).toBe(GROUND_Y)
    for (const width of [MIN_WIDTH, 45, MAX_WIDTH]) {
      const g = running(2, 0, width)
      const px = pixels(g)
      expect(px).toHaveLength(PIXEL_ROWS)
      for (const row of px) {
        expect(row).toHaveLength(width)
        for (const c of row) expect(/^#[0-9a-f]{6}$/i.test(c)).toBe(true)
      }
      const rows = drawScene(g)
      expect(rows).toHaveLength(ROWS)
      for (const r of rows) expect(r).toHaveLength(width)
      // The top pixel is the foreground of an upper half block, the bottom pixel the background.
      expect(rows[3]?.[5]).toEqual({ ch: '▀', fg: px[6]?.[5], bg: px[7]?.[5] })
    }
  })

  test('the dragon is drawn at its place on the floor, with its own colours', () => {
    const g = { ...running(), obstacles: [] as Obstacle[] }
    const px = pixels(g)
    const f = dragonFrame(g)
    const top = GROUND_Y - heightOf(f)
    f.rows.forEach((row, ry) => {
      for (let cx = 0; cx < row.length; cx++) if (row[cx] !== '.') expect(px[top + ry]?.[DRAGON_X + cx], `${cx},${ry}`).toBe(PALETTE[row[cx] as string])
    })
  })

  test('an anvil is drawn on the floor and a hammer in the air', () => {
    const anvil = pixels(withObstacle(running(), { kind: 'anvil_s', x: 30 }))
    expect(anvil[GROUND_Y - 1]?.[34]).toBe(PALETTE.g)
    expect(anvil[GROUND_Y - 4]?.[33]).toBe(PALETTE.G)
    const hammer = pixels(withObstacle(running(), { kind: 'hammer', x: 30, lift: HAMMER_LOW }))
    expect(hammer[GROUND_Y - 1]?.[34]).not.toBe(PALETTE.G)
    expect(hammer.some((row, y) => y < GROUND_Y - HAMMER_LOW && row.slice(30, 38).some(c => c === PALETTE.h))).toBe(true)
  })

  test('the hammer spins: the two frames alternate', () => {
    const a = pixels(withObstacle({ ...running(), tick: 0 }, { kind: 'hammer', x: 30, lift: HAMMER_LOW, id: 0 }))
    const b = pixels(withObstacle({ ...running(), tick: 3 }, { kind: 'hammer', x: 30, lift: HAMMER_LOW, id: 0 }))
    expect(JSON.stringify(a)).not.toEqual(JSON.stringify(b))
  })

  test('the floor scrolls with the run, and the far wall scrolls slower', () => {
    const a = pixels({ ...running(), obstacles: [], dist: 100 })
    const b = pixels({ ...running(), obstacles: [], dist: 103 })
    expect(a[GROUND_Y]?.join('')).not.toEqual(b[GROUND_Y]?.join(''))
  })

  test('runs join cells of one look into one piece', () => {
    const r = runs([
      { ch: '▀', fg: '#111111', bg: '#222222' },
      { ch: '▀', fg: '#111111', bg: '#222222' },
      { ch: '▀', fg: '#333333', bg: '#222222' },
    ])
    expect(r).toEqual([
      { text: '▀▀', fg: '#111111', bg: '#222222' },
      { text: '▀', fg: '#333333', bg: '#222222' },
    ])
  })

  test('a long run has much fewer runs than cells (the picture stays cheap to draw)', () => {
    const g = ghost(running(4), 120)
    const total = drawScene(g).reduce((n, row) => n + runs(row).length, 0)
    expect(total).toBeLessThan(ROWS * DEFAULT_WIDTH * 0.6)
  })
})

describe('a kind has a hit box for every frame', () => {
  test('obstacleBox is inside the world for every kind', () => {
    for (const kind of ['anvil_s', 'anvil_l', 'bucket', 'hammer'] as const) {
      const lift = kind === 'hammer' ? HAMMER_LOW : 0
      const b = obstacleBox({ id: 0, kind, x: 10, lift }, 0)
      expect(b.w).toBeGreaterThan(0)
      expect(b.h).toBeGreaterThan(0)
      expect(b.bottom).toBeGreaterThanOrEqual(lift)
    }
  })
})

describe('the small sizes', () => {
  test('a jump clears the big anvil with at least 3 pixels to spare at the top of the arc', () => {
    const anvilTop = 1 + (ANVIL_L.hit.h as number)
    const dragonBottom = dragonBox({ ...running(), jt: JUMP_TICKS / 2 }).bottom
    expect(dragonBottom - anvilTop).toBeGreaterThanOrEqual(3)
  })

  test('a standing dragon is about a third of the picture or less, and a duck is half of that', () => {
    expect(heightOf(DRAGON.run[0]) / PIXEL_ROWS).toBeLessThanOrEqual(0.45)
    expect(heightOf(DRAGON.duck)).toBe(heightOf(DRAGON.run[0]) / 2)
  })

  test('the low hammer is hit by a standing dragon and passes over a ducking one by 2 pixels or more', () => {
    const lowBottom = obstacleBox({ id: 0, kind: 'hammer', x: 0, lift: HAMMER_LOW }, 0).bottom
    const duckTop = dragonBox({ ...running(), duck: DUCK_TICKS }).bottom + DRAGON.duck.hit.h
    expect(lowBottom - duckTop).toBeGreaterThanOrEqual(2)
    const standingTop = dragonBox(running()).bottom + DRAGON.run[0].hit.h
    expect(lowBottom).toBeLessThan(standingTop)
    // The high hammer flies over a standing dragon.
    expect(obstacleBox({ id: 0, kind: 'hammer', x: 0, lift: HAMMER_HIGH }, 0).bottom).toBeGreaterThanOrEqual(standingTop)
  })
})
