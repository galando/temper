// Temper Run: a small optional runner for the wait while Claude works. Ember, a small dragon, runs on
// the spot in a forge hall. Jump over anvils and water buckets, duck under flying hammers. Pure and
// deterministic: the same seed and the same key presses give the same run. No Claude imports; the
// drawing lives in ui/game-client.tsx.
//
// The world is a grid of pixels. One terminal cell holds two pixels (a half block), so a pixel is
// square. All sizes below are in pixels, and all times are in ticks of 80 ms.

import { DRAGON, FLASH, FLOOR, GLOW, HAMMER_HIGH, HAMMER_LOW, OBSTACLES, PALETTE, SPARK, WALL, heightOf, widthOf } from './runner-art'
import type { Frame, Kind } from './runner-art'

export const TICK_MS = 80
// Jump: the arc has 12 steps, and the dragon is in the air for 11 ticks (0.88 s) after the press. It
// rises 8 pixels at the top of the arc (the big anvil is 6 tall).
export const JUMP_TICKS = 12
export const PEAK = 8
// A jump pressed up to 3 ticks (240 ms) before the landing is kept and fires on the landing.
export const BUFFER_TICKS = 3
// Duck: 10 ticks (0.8 s) for each press. A jump cancels it.
export const DUCK_TICKS = 10
// The first obstacle reaches Ember after 2.5 seconds (31.25 ticks).
export const FIRST_ARRIVAL_TICKS = 32
// The help line shows for the first 4 seconds of a run.
export const TUTORIAL_TICKS = 50
// Ember flashes yellow for half a second at every hundred points. The banner stays a little longer.
export const FLASH_TICKS = 6
export const BANNER_TICKS = 16

// The picture: 8 rows of air and 1 row of floor, 9 rows, 18 pixels tall.
export const AIR_ROWS = 8
export const FLOOR_ROWS = 1
export const ROWS = AIR_ROWS + FLOOR_ROWS
export const GROUND_Y = AIR_ROWS * 2
export const PIXEL_ROWS = ROWS * 2
export const DRAGON_X = 3
export const MIN_WIDTH = 36
export const MAX_WIDTH = 72
export const DEFAULT_WIDTH = 56

export const widthFor = (columns: number): number => (columns > 0 ? Math.min(MAX_WIDTH, Math.max(MIN_WIDTH, Math.floor(columns))) : DEFAULT_WIDTH)

// ---- Speed, score and heat ---------------------------------------------------------------

// Three points for every 4 pixels run (so a run of 1.2 pixels a tick scores about 11 points a second).
// The speed starts slow and grows gently up to heat 5 (1600 points).
export const POINTS_PER_PIXEL = 0.75
export const START_SPEED = 1.2
export const TOP_SPEED = 1.9
export const HEAT_POINTS = 400
export const speedAt = (score: number): number => START_SPEED + ((TOP_SPEED - START_SPEED) * Math.min(Math.max(score, 0), 4 * HEAT_POINTS)) / (4 * HEAT_POINTS)
export const heatAt = (score: number): number => Math.min(5, 1 + Math.floor(Math.max(score, 0) / HEAT_POINTS))
export const heatBars = (heat: number): string => `${'▮'.repeat(heat)}${'▯'.repeat(5 - heat)}`

// ---- Obstacles ---------------------------------------------------------------------------

export type Action = 'jump' | 'duck' | 'none'
export type Obstacle = { id: number; kind: Kind; x: number; lift: number }

export const frameOf = (o: Obstacle, tick: number): Frame => {
  const frames = OBSTACLES[o.kind]
  return frames[o.kind === 'hammer' ? Math.floor((tick + o.id) / 3) % frames.length : 0] as Frame
}
export const obstacleWidth = (kind: Kind): number => widthOf(OBSTACLES[kind][0] as Frame)

// What the player must do. A low hammer needs a duck. A high hammer flies over Ember and needs
// nothing. Anvils and buckets need a jump.
export const actionFor = (kind: Kind, lift: number): Action => (kind === 'hammer' ? (lift <= HAMMER_LOW ? 'duck' : 'none') : 'jump')

// Ticks of travel that must lie between two obstacles, by what each one needs. A jump takes 11 ticks,
// a duck 10, and a person needs a few more to react.
const GAP_TICKS: Record<Action, Record<Action, number>> = {
  jump: { jump: 16, duck: 18, none: 10 },
  duck: { jump: 18, duck: 14, none: 10 },
  none: { jump: 10, duck: 10, none: 8 },
}
export const minGapTicks = (a: Action, b: Action): number => GAP_TICKS[a][b]
export const minGapPx = (a: Action, b: Action, speed: number): number => minGapTicks(a, b) * speed

// ---- Boxes -------------------------------------------------------------------------------

// A box in the world: x from the left edge, bottom in pixels above the floor.
export type Box = { x: number; bottom: number; w: number; h: number }

export const jumpHeight = (jt: number): number => (jt <= 0 || jt >= JUMP_TICKS ? 0 : Math.round(PEAK * (1 - ((jt - JUMP_TICKS / 2) / (JUMP_TICKS / 2)) ** 2)))

const boxOf = (f: Frame, x: number, lift: number): Box => ({ x: x + f.hit.x, bottom: lift + heightOf(f) - f.hit.y - f.hit.h, w: f.hit.w, h: f.hit.h })
const overlap = (a: Box, b: Box): boolean => a.x < b.x + b.w && b.x < a.x + a.w && a.bottom < b.bottom + b.h && b.bottom < a.bottom + a.h

// ---- State -------------------------------------------------------------------------------

export type Status = 'ready' | 'running' | 'over'

export type RunState = {
  status: Status
  tick: number
  // Distance run, in pixels.
  dist: number
  score: number
  // The best score and the best score when this run began.
  hi: number
  hiStart: number
  width: number
  // How many ticks the jump has been in the air (0 on the floor), the ticks of duck that are left,
  // and the ticks that a remembered jump press is still good for.
  jt: number
  duck: number
  buf: number
  obstacles: Obstacle[]
  nextId: number
  rng: number
  // Pixels run since the last obstacle appeared, and the pixels the next one waits for.
  since: number
  need: number
  nextKind: Kind
  nextLift: number
  // Ticks of the yellow flash and of the banner that are left, and the last hundred that was reached.
  flash: number
  banner: string | null
  bannerT: number
  milestone: number
}

// A small seeded generator (mulberry32): the next state and a number from 0 up to 1.
export function nextRandom(state: number): { state: number; value: number } {
  const s = (state + 0x6d2b79f5) >>> 0
  let t = s
  t = Math.imul(t ^ (t >>> 15), t | 1)
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
  return { state: s, value: ((t ^ (t >>> 14)) >>> 0) / 4294967296 }
}

const hitDragon = (s: RunState): Box => {
  const f = dragonFrame(s)
  return boxOf(f, DRAGON_X, jumpHeight(s.jt))
}

export function dragonFrame(s: RunState): Frame {
  if (s.status === 'over') return DRAGON.dead
  if (s.jt > 0) return DRAGON.jump
  if (s.duck > 0) return DRAGON.duck
  return DRAGON.run[Math.floor(s.tick / 4) % 2] as Frame
}

export const dragonBox = hitDragon
export const obstacleBox = (o: Obstacle, tick: number): Box => boxOf(frameOf(o, tick), o.x, o.lift)

// ---- The pick of the next obstacle ---------------------------------------------------------

// How many different moments to start a jump (or a duck) clear this obstacle, at this speed. A fair
// obstacle leaves at least 3 of them (240 ms).
const startsCache = new Map<string, number[]>()

export function clearStarts(kind: Kind, lift: number, speed: number): number[] {
  // The answer changes only a little with the speed, so it is kept for each hundredth of a pixel.
  const key = `${kind}:${lift}:${speed.toFixed(2)}`
  const kept = startsCache.get(key)
  if (kept) return kept
  const found = computeStarts(kind, lift, Number(speed.toFixed(2)))
  startsCache.set(key, found)
  return found
}

function computeStarts(kind: Kind, lift: number, speed: number): number[] {
  const action = actionFor(kind, lift)
  if (action === 'none') return Array.from({ length: 12 }, (_, i) => i)
  const out: number[] = []
  const w = obstacleWidth(kind)
  // The obstacle starts far away and arrives at about tick 40.
  const front = DRAGON_X + (DRAGON.run[0].hit.x + DRAGON.run[0].hit.w)
  const x0 = front + 40 * speed
  for (let start = 0; start <= 60; start++) {
    let hit = false
    let jt = 0
    let duck = 0
    for (let t = 0; t <= 90 && !hit; t++) {
      // The same order as `press` and then `step`: the press sets the state, and the tick moves it on.
      if (t === start) {
        if (action === 'jump') jt = 1
        else duck = DUCK_TICKS
      }
      if (jt > 0) jt = jt + 1 >= JUMP_TICKS ? 0 : jt + 1
      if (duck > 0) duck--
      const o: Obstacle = { id: 0, kind, x: x0 - t * speed, lift }
      if (o.x + w < 0) break
      const f: Frame = jt > 0 ? DRAGON.jump : duck > 0 ? DRAGON.duck : (DRAGON.run[0] as Frame)
      if (overlap(boxOf(f, DRAGON_X, jumpHeight(jt)), obstacleBox(o, 0))) hit = true
    }
    // A start that is far too early or too late clears by luck of timing nothing: keep only starts
    // near the arrival (a jump started after the obstacle passed is not a clear).
    if (!hit && start >= 10 && start <= 50) out.push(start)
  }
  return out
}

// The ticks between the moment a person presses and the moment the obstacle touches Ember, for a
// press in the middle of the clear starts. A bot uses this.
export function bestLead(kind: Kind, lift: number, speed: number): number {
  const front = DRAGON_X + (DRAGON.run[0].hit.x + DRAGON.run[0].hit.w)
  const starts = clearStarts(kind, lift, speed)
  if (starts.length === 0) return 0
  const mid = starts[Math.floor(starts.length / 2)] as number
  const x0 = front + 40 * speed
  const obstacleLeft = x0 + (boxOf(frameOf({ id: 0, kind, x: 0, lift }, 0), 0, lift).x)
  const contact = (obstacleLeft - front) / speed
  // A press made when the state is at tick T acts in the step to tick T + 1, so the lead is one more.
  return contact - mid + 1
}

type Pick = { kind: Kind; lift: number; rng: number }

// Picks the next obstacle: only a fair one for this speed. Hammers wait for 100 points.
export function pickNext(score: number, speed: number, rngState: number): Pick {
  const a = nextRandom(rngState)
  const b = nextRandom(a.state)
  const options: Array<{ kind: Kind; lift: number; weight: number }> = [
    { kind: 'anvil_s', lift: 0, weight: 30 },
    { kind: 'bucket', lift: 0, weight: 26 },
  ]
  options.push({ kind: 'anvil_l', lift: 0, weight: 16 })
  if (score >= 100) {
    options.push({ kind: 'hammer', lift: HAMMER_LOW, weight: 18 })
    options.push({ kind: 'hammer', lift: HAMMER_HIGH, weight: 10 })
  }
  // Only an obstacle with a window of 3 ticks or more at this speed. The big anvil needs the speed
  // of a later heat level, so it waits for it.
  const fair = options.filter(o => clearStarts(o.kind, o.lift, speed).length >= 3)
  const pool = fair.length > 0 ? fair : options.slice(0, 1)
  const total = pool.reduce((n, o) => n + o.weight, 0)
  let roll = a.value * total
  let chosen = pool[0] as (typeof pool)[number]
  for (const o of pool) {
    if (roll < o.weight) {
      chosen = o
      break
    }
    roll -= o.weight
  }
  return { kind: chosen.kind, lift: chosen.lift, rng: b.state }
}

// ---- A run ------------------------------------------------------------------------------

export function newGame(seed: number, hi = 0, width = DEFAULT_WIDTH, startScore = 0): RunState {
  const first = pickNext(startScore, speedAt(startScore), seed >>> 0)
  return {
    status: 'ready',
    tick: 0,
    dist: startScore / POINTS_PER_PIXEL,
    score: startScore,
    hi,
    hiStart: hi,
    width,
    jt: 0,
    duck: 0,
    buf: 0,
    obstacles: [],
    nextId: 1,
    rng: first.rng,
    since: 0,
    need: 0,
    nextKind: 'anvil_s',
    nextLift: 0,
    flash: 0,
    banner: null,
    bannerT: 0,
    milestone: Math.floor(startScore / 100),
  }
}

export const withWidth = (s: RunState, width: number): RunState => (s.width === width ? s : { ...s, width })

// Starts a run, or runs again after game over, with a new seed. The best score stays.
export function start(state: RunState, seed: number, startScore = 0): RunState {
  return { ...newGame(seed, state.hi, state.width, startScore), status: 'running' }
}

// The first obstacle appears at this tick: it reaches Ember 2.5 seconds after the run began.
export function firstSpawnTick(width: number, speed: number): number {
  const front = DRAGON_X + (DRAGON.run[0].hit.x + DRAGON.run[0].hit.w)
  const hitLeft = (OBSTACLES.anvil_s[0] as Frame).hit.x
  const travel = (width + hitLeft - front) / speed
  // The speed grows a little while it travels, so leave one tick of margin.
  return Math.max(1, Math.ceil(FIRST_ARRIVAL_TICKS - travel) + 1)
}

export function press(state: RunState, what: 'jump' | 'duck'): RunState {
  if (state.status !== 'running') return state
  if (what === 'jump') {
    if (state.jt === 0) return { ...state, jt: 1, duck: 0 }
    return { ...state, buf: BUFFER_TICKS }
  }
  if (state.jt > 0) return state
  return { ...state, duck: DUCK_TICKS }
}

// One tick. With `ghost` the dragon cannot be hit (a test uses it to look at the obstacles).
export function step(state: RunState, opts: { ghost?: boolean } = {}): RunState {
  if (state.status !== 'running') return state
  const tick = state.tick + 1
  const speed = speedAt(state.score)
  const dist = state.dist + speed
  const score = Math.floor(dist * POINTS_PER_PIXEL + 1e-9)

  let jt = state.jt
  let buf = state.buf
  if (jt > 0) {
    jt += 1
    if (jt >= JUMP_TICKS) {
      // Landed. A remembered press fires now.
      jt = buf > 0 ? 1 : 0
      buf = 0
    }
  }
  if (buf > 0) buf -= 1
  const duck = state.duck > 0 ? state.duck - 1 : 0

  let obstacles = state.obstacles.map(o => ({ ...o, x: o.x - speed })).filter(o => o.x + obstacleWidth(o.kind) > 0)
  let { rng, since, need, nextKind, nextLift, nextId } = state
  since += speed
  const first = state.obstacles.length === 0 && nextId === 1
  const due = first ? tick >= firstSpawnTick(state.width, START_SPEED) : since >= need
  if (due) {
    if (first) {
      const p = pickNext(0, speed, rng)
      // The first obstacle is always a plain jump.
      nextKind = 'anvil_s'
      nextLift = 0
      rng = p.rng
    }
    obstacles = [...obstacles, { id: nextId, kind: nextKind, x: state.width, lift: nextLift }]
    nextId += 1
    const prevAction = actionFor(nextKind, nextLift)
    const prevWidth = obstacleWidth(nextKind)
    const p = pickNext(score, speed, rng)
    rng = p.rng
    const extra = nextRandom(rng)
    rng = extra.state
    nextKind = p.kind
    nextLift = p.lift
    // The speed may grow a little before the next one appears: ask for the gap at a slightly higher speed.
    const gap = minGapPx(prevAction, actionFor(nextKind, nextLift), speed + 0.05) + extra.value * 10 * speed
    need = prevWidth + gap
    since = 0
  }

  let { flash, banner, bannerT, milestone } = state
  if (flash > 0) flash -= 1
  if (bannerT > 0) bannerT -= 1
  if (bannerT === 0) banner = null
  const hundred = Math.floor(score / 100)
  if (hundred > milestone) {
    milestone = hundred
    flash = FLASH_TICKS
    banner = `Hot! ${hundred * 100}`
    bannerT = BANNER_TICKS
  }

  const next: RunState = { ...state, tick, dist, score, jt, buf, duck, obstacles, rng, since, need, nextKind, nextLift, nextId, flash, banner, bannerT, milestone }
  if (!opts.ghost) {
    const box = hitDragon(next)
    if (obstacles.some(o => overlap(box, obstacleBox(o, tick)))) return { ...next, status: 'over', hi: Math.max(state.hi, score) }
  }
  return next
}

export const isNewRecord = (s: RunState): boolean => s.status === 'over' && s.score > 0 && s.score > s.hiStart

export const pad5 = (n: number): string => String(Math.max(0, Math.floor(n))).padStart(5, '0')

// The line under the picture, in plain short sentences.
export function lineFor(s: RunState): string {
  if (s.status === 'ready') return 'Press r to run. Press w to jump. Press s to duck.'
  if (s.status === 'over') return `${isNewRecord(s) ? 'New record. The forge is hot. ' : ''}Game over. Your forge went cold.`
  if (s.tick < TUTORIAL_TICKS) return 'Press w to jump. Press s to duck.'
  return 'w jumps. s ducks. q or Esc leaves.'
}

export const lineTwo = (s: RunState): string => (s.status === 'over' ? 'Press r to run again. q or Esc leaves.' : '')

// ---- The picture ---------------------------------------------------------------------------

export type Cell = { ch: string; fg: string; bg: string }

const mix = (a: string, b: string, t: number): string => {
  const n = (h: string, i: number) => parseInt(h.slice(1 + i * 2, 3 + i * 2), 16)
  const c = (i: number) => Math.round(n(a, i) + (n(b, i) - n(a, i)) * t).toString(16).padStart(2, '0')
  return `#${c(0)}${c(1)}${c(2)}`
}

// The dragon in the colours of a flash: body yellow, shade amber, belly white.
const FLASHED: Readonly<Record<string, string>> = { o: FLASH, O: '#ffaf00', F: '#ffd700', y: '#ffffff', v: '#ffe97f' }

// All the pixels of the scene, row by row, top to bottom. A pixel is a colour.
export function pixels(s: RunState): string[][] {
  const W = s.width
  const heat = heatAt(s.score)
  const wall = WALL[heat - 1] as string
  const glow = GLOW[heat - 1] as string
  const buf: string[][] = Array.from({ length: PIXEL_ROWS }, () => Array.from({ length: W }, () => wall))
  const set = (x: number, y: number, color: string) => {
    if (x >= 0 && x < W && y >= 0 && y < PIXEL_ROWS) (buf[y] as string[])[x] = color
  }
  // The far wall: furnace windows that glow, moving slowly (a fifth of the speed).
  const slow = Math.floor(s.dist * 0.2)
  for (let i = -1; i <= Math.ceil(W / 18) + 1; i++) {
    const x0 = i * 18 - (slow % 18) + 2
    for (let dx = 0; dx < 6; dx++) for (let dy = 0; dy < 6; dy++) {
      // An arched window: the top corners are cut.
      if (dy === 0 && (dx < 1 || dx > 4)) continue
      set(x0 + dx, 3 + dy, dy < 2 ? mix(glow, wall, 0.35) : glow)
    }
    // The glow shows in the bar of the window.
    for (let dy = 1; dy < 6; dy++) set(x0 + 2, 3 + dy, wall)
  }
  // Sparks drift up and to the left, a little faster than the far wall.
  for (let i = 0; i < 5; i++) {
    const x = (((i * 17 + 9) - Math.floor(s.tick * 0.7 + i * 4)) % (W + 6) + (W + 6)) % (W + 6) - 3
    const y = GROUND_Y - 3 - ((i * 5 + Math.floor(s.tick * 0.25)) % 10)
    set(x, y, SPARK)
  }
  // The floor, 2 pixels thick (one row of cells): glowing embers on top, and a row of bricks below.
  // It moves at the speed of the run.
  const off = Math.floor(s.dist)
  for (let x = 0; x < W; x++) {
    const e = (x + off) % 7
    set(x, GROUND_Y, e < 2 ? FLOOR.emberHot : e < 4 ? FLOOR.ember : FLOOR.edge)
    set(x, GROUND_Y + 1, (x + off) % 8 === 0 ? FLOOR.mortar : FLOOR.brick)
  }
  const blit = (f: Frame, x: number, lift: number, recolor?: Readonly<Record<string, string>>) => {
    const top = GROUND_Y - lift - heightOf(f)
    f.rows.forEach((row, ry) => {
      for (let cx = 0; cx < row.length; cx++) {
        const ch = row[cx] as string
        if (ch === '.') continue
        set(Math.round(x) + cx, top + ry, recolor?.[ch] ?? (PALETTE[ch] as string))
      }
    })
  }
  for (const o of s.obstacles) blit(frameOf(o, s.tick), o.x, o.lift)
  blit(dragonFrame(s), DRAGON_X, jumpHeight(s.jt), s.flash > 0 ? FLASHED : undefined)
  return buf
}

// The scene as terminal cells: two pixels in one cell. The top pixel is the foreground of an upper
// half block, the bottom pixel is the background.
export function drawScene(s: RunState): Cell[][] {
  const px = pixels(s)
  const rows: Cell[][] = []
  for (let r = 0; r < ROWS; r++) {
    const top = px[r * 2] as string[]
    const bottom = px[r * 2 + 1] as string[]
    rows.push(top.map((t, c) => ({ ch: '▀', fg: t, bg: bottom[c] as string })))
  }
  return rows
}

// Cells that share the same look, as runs: one Text for each run.
export function runs(row: readonly Cell[]): Array<{ text: string; fg: string; bg: string }> {
  const out: Array<{ text: string; fg: string; bg: string }> = []
  for (const cell of row) {
    const last = out[out.length - 1]
    if (last && last.fg === cell.fg && last.bg === cell.bg) last.text += cell.ch
    else out.push({ text: cell.ch, fg: cell.fg, bg: cell.bg })
  }
  return out
}
