// Temper Run: a small optional runner game for the wait while Claude works. It is about the forge:
// a flame (the thing being tempered) runs along a bed of embers and hops over anvils and cold
// water. Pure and deterministic: the same seed and the same keys give the same game. No Claude
// imports; the drawing lives in ui/game-client.tsx.

// The playfield. The width follows the region the game is drawn in (36 to 60 cells). The height is
// fixed at 10 rows: a flame at the top of a jump (6 cells up, 4 rows tall) still fits.
export const MIN_WIDTH = 36
export const MAX_WIDTH = 60
export const DEFAULT_WIDTH = 56
export const FIELD = { width: DEFAULT_WIDTH, height: 10 }
// The flame stands at this column. Its sprite is 3 cells wide and 3 rows tall.
export const RUNNER = { x: 6, w: 3, h: 3 }
// The part of the flame that can hit a block: the two left columns of the lower two rows. The tip
// and the right edge are only drawn.
export const HITBOX = { dx: 0, w: 2, h: 2 }
export const JUMP_SPEED = 3
export const GRAVITY = 1
// A game step is one tick of 80 ms.
export const TICK_MS = 80

// ---- Sprites (data) --------------------------------------------------------------------
// Every row of one sprite has the same width, so nothing shifts when a frame changes.

export type Style = { color?: string; dim?: boolean; bold?: boolean }
export type Sprite = { rows: readonly string[]; styles: readonly Style[] }

const YELLOW: Style = { color: 'yellow', bold: true }
const ORANGE: Style = { color: '#ff8c1a', bold: true }
const RED: Style = { color: 'red', bold: true }
const IRON: Style = { color: '#7a7a7a', bold: true }
const ICE: Style = { color: 'cyan', bold: true }

// The flame runs: three frames, flipped every 3 ticks, so it flickers. Yellow top, orange middle,
// red base.
export const FLAME_RUN: readonly Sprite[] = [
  { rows: [' ▲ ', '▟█▙', '▀█▀'], styles: [YELLOW, ORANGE, RED] },
  { rows: ['▗▲ ', '▟█▙', '▀█▀'], styles: [YELLOW, ORANGE, RED] },
  { rows: [' ▲▖', '▜█▛', '▀█▀'], styles: [YELLOW, ORANGE, RED] },
]
// In the air the flame stretches taller: four rows.
export const FLAME_JUMP: Sprite = { rows: [' ▲ ', '▗█▖', '▟█▙', '▀█▀'], styles: [YELLOW, ORANGE, ORANGE, RED] }
// After a game over the flame is a spark.
export const FLAME_OUT: Sprite = { rows: [' * '], styles: [{ color: 'red', dim: true }] }
export const FLICKER_TICKS = 3

export type ObstacleKind = 'anvil_s' | 'anvil_l' | 'drop' | 'ice'
export type KindSpec = { w: number; h: number; sprite: Sprite }

// Two anvils (dark gray) and two cold things (cyan): a water drop and a block of ice.
export const KINDS: Record<ObstacleKind, KindSpec> = {
  anvil_s: { w: 3, h: 2, sprite: { rows: ['▟█▙', '▝█▘'], styles: [IRON, IRON] } },
  anvil_l: { w: 4, h: 3, sprite: { rows: ['▄██▄', '▟██▙', '▝██▘'], styles: [IRON, IRON, IRON] } },
  drop: { w: 1, h: 1, sprite: { rows: ['◆'], styles: [ICE] } },
  ice: { w: 3, h: 2, sprite: { rows: [' ▲ ', '▲▲▲'], styles: [ICE, ICE] } },
}
export const KIND_LIST: readonly ObstacleKind[] = ['anvil_s', 'anvil_l', 'drop', 'ice']

// ---- State -----------------------------------------------------------------------------

// `kind` is absent for a plain block (a test fixture); it is then drawn as an iron rectangle.
export type Obstacle = { x: number; w: number; h: number; kind?: ObstacleKind }

export type GameStatus = 'ready' | 'running' | 'over'

export type GameState = {
  status: GameStatus
  tick: number
  // The height of the flame's feet above the ground, in cells, and its speed upward.
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
  // The playfield, in cells.
  width: number
  height: number
}

// A small seeded generator (mulberry32): the next state and a number from 0 up to 1.
export function nextRandom(state: number): { state: number; value: number } {
  const s = (state + 0x6d2b79f5) >>> 0
  let t = s
  t = Math.imul(t ^ (t >>> 15), t | 1)
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
  return { state: s, value: ((t ^ (t >>> 14)) >>> 0) / 4294967296 }
}

// The width the game uses in a region of `columns` cells: never under 36, never over 60. A region
// that is not laid out yet (0 columns) gets the default.
export const widthFor = (columns: number): number => (columns > 0 ? Math.min(MAX_WIDTH, Math.max(MIN_WIDTH, Math.floor(columns))) : DEFAULT_WIDTH)

export function newGame(seed: number, best = 0, width = DEFAULT_WIDTH): GameState {
  return { status: 'ready', tick: 0, y: 0, vy: 0, obstacles: [], speed: 1, score: 0, best, rng: seed >>> 0, gap: 12, width, height: FIELD.height }
}

// A game in a new width (the region changed). Nothing else moves.
export const withWidth = (s: GameState, width: number): GameState => (s.width === width ? s : { ...s, width })

// Starts a ready game, or starts again after game over, with a new seed and the best score kept.
export function start(state: GameState, seed: number): GameState {
  return { ...newGame(seed, state.best, state.width), status: 'running' }
}

// The speed grows by one cell per tick every 150 ticks (about 12 seconds), up to 3.
export const speedAt = (tick: number): number => Math.min(3, 1 + Math.floor(tick / 150))

// Heat is the speed ramp in five steps, one every 75 ticks (6 seconds): heat 1 to heat 5.
export const heatAt = (tick: number): number => Math.min(5, 1 + Math.floor(tick / 75))

export const onGround = (s: GameState): boolean => s.y === 0 && s.vy === 0

// Whether a block is within `cells` cells in front of the flame. The drawing pauses an idle game
// only while no block is close, so a wait never costs a game that is about to be lost.
export const blockAhead = (s: GameState, cells: number): boolean =>
  s.obstacles.some(o => o.x + o.w > RUNNER.x && o.x - (RUNNER.x + RUNNER.w) < cells)

// Jump when on the ground. In the air a jump does nothing.
export function jump(state: GameState): GameState {
  if (state.status !== 'running' || !onGround(state)) return state
  return { ...state, vy: JUMP_SPEED }
}

const overlaps = (s: GameState): boolean =>
  s.obstacles.some(o => o.x < RUNNER.x + HITBOX.dx + HITBOX.w && o.x + o.w > RUNNER.x + HITBOX.dx && s.y < o.h)

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
    rng = b.state
    // The seeded generator mixes anvils and cold things.
    const kind = KIND_LIST[Math.min(KIND_LIST.length - 1, Math.floor(a.value * KIND_LIST.length))] as ObstacleKind
    const spec = KINDS[kind]
    obstacles = [...obstacles, { x: state.width, w: spec.w, h: spec.h, kind }]
    // Room to land and jump again grows with the speed.
    gap = 10 + speed * 4 + Math.floor(b.value * 8)
  }

  // A passed obstacle is worth 5 points; every tick alive is worth 1.
  const passed = state.obstacles.filter(o => o.x + o.w > RUNNER.x && o.x + o.w - speed <= RUNNER.x).length
  const score = state.score + 1 + passed * 5

  const next: GameState = { ...state, tick, y, vy, obstacles, speed, score, rng, gap }
  if (overlaps(next)) return { ...next, status: 'over', best: Math.max(state.best, score) }
  return next
}

export const isNewBest = (s: GameState): boolean => s.status === 'over' && s.score >= s.best && s.score > 0

// ---- Drawing rows ----------------------------------------------------------------------

export type Cell = { ch: string; style: Style }
const BLANK: Cell = { ch: ' ', style: {} }

// The sprite the flame shows now: a spark after game over, stretched in the air, else a flicker.
export function flameSprite(s: GameState): Sprite {
  if (s.status === 'over') return FLAME_OUT
  if (s.y > 0) return FLAME_JUMP
  return FLAME_RUN[Math.floor(s.tick / FLICKER_TICKS) % FLAME_RUN.length] as Sprite
}

// A few sparks drift up and to the left behind everything else. Each spark is a pure function of
// the tick, so the drawing keeps no state.
export function sparks(tick: number, width: number, height: number): Array<{ x: number; y: number; ch: string }> {
  const out: Array<{ x: number; y: number; ch: string }> = []
  const sky = 3
  const count = Math.max(3, Math.floor(width / 9))
  for (let i = 0; i < count; i++) {
    const x = (((i * 9 + ((i * 5) % 7) - Math.floor(tick / 8)) % width) + width) % width
    const lift = (((i * 2 - Math.floor(tick / 10)) % sky) + sky) % sky
    out.push({ x, y: height - 1 - lift, ch: i % 3 === 0 ? '*' : '·' })
  }
  return out
}

const EMBER = '▁▂▃▂'

// The ground: embers that glow red and orange in turn and scroll slowly left.
export function groundRow(tick: number, width: number): Cell[] {
  const shift = Math.floor(tick / 3)
  const row: Cell[] = []
  for (let x = 0; x < width; x++) {
    const i = x + shift
    row.push({ ch: EMBER[i % EMBER.length] as string, style: Math.floor(i / 2) % 2 === 0 ? { color: 'red' } : { color: '#ff8c1a' } })
  }
  return row
}

// The whole picture, top row first, as rows of styled cells. The last row is the ground.
export function drawRows(s: GameState): Cell[][] {
  const { width, height } = s
  const grid: Cell[][] = Array.from({ length: height }, () => Array.from({ length: width }, () => BLANK))
  const put = (x: number, y: number, cell: Cell) => {
    const row = height - 1 - y
    if (x >= 0 && x < width && row >= 0 && row < height) (grid[row] as Cell[])[x] = cell
  }
  for (const sp of sparks(s.tick, width, height)) put(sp.x, sp.y, { ch: sp.ch, style: { dim: true } })
  const blit = (sprite: Sprite, x: number, y: number) => {
    sprite.rows.forEach((text, r) => {
      const style = sprite.styles[r] as Style
      for (let c = 0; c < text.length; c++) if (text[c] !== ' ') put(x + c, y + sprite.rows.length - 1 - r, { ch: text[c] as string, style })
    })
  }
  for (const o of s.obstacles) {
    const x = Math.round(o.x)
    if (o.kind) blit(KINDS[o.kind].sprite, x, 0)
    else for (let dx = 0; dx < o.w; dx++) for (let h = 0; h < o.h; h++) put(x + dx, h, { ch: '█', style: IRON })
  }
  const flame = flameSprite(s)
  blit(flame, RUNNER.x, s.status === 'over' ? 0 : Math.round(s.y))
  return [...grid, groundRow(s.tick, width)]
}

// Cells in a row that share one style, as runs: one Text for each run.
export function runs(row: readonly Cell[]): Array<{ text: string; style: Style }> {
  const out: Array<{ text: string; style: Style }> = []
  for (const cell of row) {
    const last = out[out.length - 1]
    if (last && last.style.color === cell.style.color && last.style.dim === cell.style.dim && last.style.bold === cell.style.bold) last.text += cell.ch
    else out.push({ text: cell.ch, style: cell.style })
  }
  return out
}

export const pad4 = (n: number): string => String(Math.max(0, Math.floor(n))).padStart(4, '0')

// The line under the field, in plain short sentences.
export function messageFor(s: GameState, paused: boolean): string {
  if (s.status === 'ready') return 'Press s to light the flame. w jumps.'
  if (paused) return 'Paused. Press s or w to go on. q or Esc leaves.'
  if (s.status === 'over') return `${isNewBest(s) ? 'New best. The forge is hot. ' : ''}Your flame went out. Score ${s.score}. Press s to play again. q or Esc leaves.`
  return 'w jumps. q or Esc leaves.'
}
