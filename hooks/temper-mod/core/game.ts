// Temper Run: a small optional runner game for the wait while Claude works. A flame runs along
// the ground and jumps over blocks. Pure and deterministic: the same seed and the same keys give
// the same game. No Claude imports; the drawing lives in ui/game-client.tsx.

export const FIELD = { width: 56, height: 6 }
// The runner stands at this column and is two cells wide and two tall.
export const RUNNER = { x: 6, w: 2, h: 2 }
export const JUMP_SPEED = 3
export const GRAVITY = 1
// A game step is one tick of 80 ms.
export const TICK_MS = 80

export type Obstacle = { x: number; w: number; h: number }

export type GameStatus = 'ready' | 'running' | 'over'

export type GameState = {
  status: GameStatus
  tick: number
  // The height of the runner's feet above the ground, in cells, and its speed upward.
  y: number
  vy: number
  obstacles: Obstacle[]
  // Cells the world moves left each tick.
  speed: number
  score: number
  best: number
  // The random state: the next value of the seeded generator.
  rng: number
  // Ticks until the next obstacle may appear.
  gap: number
}

// A small seeded generator (mulberry32): the next state and a number from 0 up to 1.
export function nextRandom(state: number): { state: number; value: number } {
  const s = (state + 0x6d2b79f5) >>> 0
  let t = s
  t = Math.imul(t ^ (t >>> 15), t | 1)
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
  return { state: s, value: ((t ^ (t >>> 14)) >>> 0) / 4294967296 }
}

export function newGame(seed: number, best = 0): GameState {
  return { status: 'ready', tick: 0, y: 0, vy: 0, obstacles: [], speed: 1, score: 0, best, rng: seed >>> 0, gap: 12 }
}

// Starts a ready game, or starts again after game over, with a new seed and the best score kept.
export function start(state: GameState, seed: number): GameState {
  return { ...newGame(seed, state.best), status: 'running' }
}

// The speed grows by one cell per tick every 150 ticks (about 12 seconds), up to 3.
export const speedAt = (tick: number): number => Math.min(3, 1 + Math.floor(tick / 150))

export const onGround = (s: GameState): boolean => s.y === 0 && s.vy === 0

// Whether a block is within `cells` cells in front of the runner. The drawing pauses an idle game
// only while no block is close, so a wait never costs a game that is about to be lost.
export const blockAhead = (s: GameState, cells: number): boolean =>
  s.obstacles.some(o => o.x + o.w > RUNNER.x && o.x - (RUNNER.x + RUNNER.w) < cells)

// Jump when on the ground. In the air a jump does nothing.
export function jump(state: GameState): GameState {
  if (state.status !== 'running' || !onGround(state)) return state
  return { ...state, vy: JUMP_SPEED }
}

const overlaps = (s: GameState): boolean =>
  s.obstacles.some(o => o.x < RUNNER.x + RUNNER.w && o.x + o.w > RUNNER.x && s.y < o.h)

// One tick: physics, obstacles, speed, score, collision. A game that is not running does not move.
export function step(state: GameState): GameState {
  if (state.status !== 'running') return state
  const tick = state.tick + 1
  const speed = speedAt(tick)

  let y = state.y
  let vy = state.vy
  if (y > 0 || vy > 0) {
    y += vy
    vy -= GRAVITY
    if (y <= 0) {
      y = 0
      vy = 0
    }
  }

  let rng = state.rng
  let gap = state.gap - 1
  let obstacles = state.obstacles.map(o => ({ ...o, x: o.x - speed })).filter(o => o.x + o.w > 0)
  if (gap <= 0) {
    const a = nextRandom(rng)
    const b = nextRandom(a.state)
    const c = nextRandom(b.state)
    rng = c.state
    obstacles = [...obstacles, { x: FIELD.width, w: 1 + Math.floor(a.value * 2), h: 1 + Math.floor(b.value * 2) }]
    // Room to land and jump again grows with the speed.
    gap = 10 + speed * 4 + Math.floor(c.value * 8)
  }

  // A passed obstacle is worth 5 points; every tick alive is worth 1.
  const passed = state.obstacles.filter(o => o.x + o.w > RUNNER.x && o.x + o.w - speed <= RUNNER.x).length
  const score = state.score + 1 + passed * 5

  const next: GameState = { ...state, tick, y, vy, obstacles, speed, score, rng, gap }
  if (overlaps(next)) return { ...next, status: 'over', best: Math.max(state.best, score) }
  return next
}

export const isNewBest = (s: GameState): boolean => s.status === 'over' && s.score >= s.best && s.score > 0

// The field as text rows, top row first. `#` is a block, `^` the runner (a flame), `_` the ground.
export function frameRows(s: GameState): string[] {
  const rows: string[][] = []
  for (let r = 0; r < FIELD.height; r++) rows.push(Array.from({ length: FIELD.width }, () => ' '))
  const put = (x: number, y: number, ch: string) => {
    const row = FIELD.height - 1 - y
    if (x >= 0 && x < FIELD.width && row >= 0 && row < FIELD.height) (rows[row] as string[])[x] = ch
  }
  for (const o of s.obstacles) for (let dx = 0; dx < o.w; dx++) for (let h = 0; h < o.h; h++) put(Math.round(o.x) + dx, h, '#')
  for (let dx = 0; dx < RUNNER.w; dx++) for (let h = 0; h < RUNNER.h; h++) put(RUNNER.x + dx, Math.round(s.y) + h, h === RUNNER.h - 1 ? '^' : 'A')
  return [...rows.map(r => r.join('')), '_'.repeat(FIELD.width)]
}

export const pad4 = (n: number): string => String(Math.max(0, Math.floor(n))).padStart(4, '0')
