// Temper Merge: a small optional puzzle for the wait while Claude works. A 4 by 4 board of metal
// pieces. Slide them with w a s d. Two equal pieces that touch merge into one piece of double
// value (it gets hotter), and the player scores that value. Make a white hot 512 piece.
// Turn based, so no timing and no clock. Pure and deterministic: the same seed and the same moves
// give the same game. No Claude imports; the drawing lives in ui/game-client.tsx.

export const SIZE = 4
export const WIN_VALUE = 512
// A cell is 7 columns by 3 rows. The board has a one column margin on the left: 29 columns in all.
export const CELL_W = 7
export const CELL_H = 3
export const BOARD_WIDTH = 1 + SIZE * CELL_W

export type Dir = 'up' | 'left' | 'down' | 'right'
export const DIRS: readonly Dir[] = ['up', 'left', 'down', 'right']

export type MergeState = {
  // 16 cells, row by row. 0 is empty.
  board: number[]
  score: number
  best: number
  // The random state: the next value of the seeded generator.
  rng: number
  // A 512 piece was made at least once. The player may keep playing.
  won: boolean
  // No move changes the board.
  over: boolean
  // How many times a move key was pressed (even one that changed nothing). A drawing uses it to
  // see that keys arrive.
  presses: number
}

// A small seeded generator (mulberry32): the next state and a number from 0 up to 1.
export function nextRandom(state: number): { state: number; value: number } {
  const s = (state + 0x6d2b79f5) >>> 0
  let t = s
  t = Math.imul(t ^ (t >>> 15), t | 1)
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
  return { state: s, value: ((t ^ (t >>> 14)) >>> 0) / 4294967296 }
}

// Puts a 2 (nine times in ten) or a 4 in a random empty cell. A full board is left as it is.
export function spawn(board: readonly number[], rng: number): { board: number[]; rng: number } {
  const empty: number[] = []
  board.forEach((v, i) => {
    if (v === 0) empty.push(i)
  })
  if (empty.length === 0) return { board: [...board], rng }
  const a = nextRandom(rng)
  const b = nextRandom(a.state)
  const cell = empty[Math.min(empty.length - 1, Math.floor(a.value * empty.length))] as number
  const next = [...board]
  next[cell] = b.value < 0.9 ? 2 : 4
  return { board: next, rng: b.state }
}

// A new game: an empty board with two pieces. The best score carries over.
export function newGame(seed: number, best = 0): MergeState {
  const first = spawn(new Array<number>(SIZE * SIZE).fill(0), seed >>> 0)
  const second = spawn(first.board, first.rng)
  return { board: second.board, score: 0, best, rng: second.rng, won: false, over: false, presses: 0 }
}

// One line slid to the left: the pieces move to the front, and each pair of equal neighbours merges
// once. A piece made by a merge does not merge again in the same move.
export function slideLine(line: readonly number[]): { line: number[]; gained: number } {
  const pieces = line.filter(v => v !== 0)
  const out: number[] = []
  let gained = 0
  for (let i = 0; i < pieces.length; i++) {
    const v = pieces[i] as number
    if (i + 1 < pieces.length && pieces[i + 1] === v) {
      out.push(v * 2)
      gained += v * 2
      i++
    } else out.push(v)
  }
  while (out.length < line.length) out.push(0)
  return { line: out, gained }
}

const rowOf = (board: readonly number[], r: number): number[] => board.slice(r * SIZE, r * SIZE + SIZE)
const colOf = (board: readonly number[], c: number): number[] => Array.from({ length: SIZE }, (_, r) => board[r * SIZE + c] as number)

// The whole board slid one way. `moved` says whether anything changed.
export function slideBoard(board: readonly number[], dir: Dir): { board: number[]; gained: number; moved: boolean } {
  const next = new Array<number>(SIZE * SIZE).fill(0)
  let gained = 0
  for (let i = 0; i < SIZE; i++) {
    // Read the line so that the slide is always "toward the front", then write it back.
    const line = dir === 'left' ? rowOf(board, i) : dir === 'right' ? rowOf(board, i).reverse() : dir === 'up' ? colOf(board, i) : colOf(board, i).reverse()
    const slid = slideLine(line)
    gained += slid.gained
    const out = dir === 'right' || dir === 'down' ? [...slid.line].reverse() : slid.line
    for (let k = 0; k < SIZE; k++) {
      if (dir === 'left' || dir === 'right') next[i * SIZE + k] = out[k] as number
      else next[k * SIZE + i] = out[k] as number
    }
  }
  return { board: next, gained, moved: next.some((v, i) => v !== board[i]) }
}

// Whether any move changes the board.
export const canMove = (board: readonly number[]): boolean => DIRS.some(d => slideBoard(board, d).moved)

export const maxPiece = (board: readonly number[]): number => Math.max(0, ...board)

// One key press. A move that changes nothing adds no piece and no score. A move that changes the
// board adds the merge values to the score, adds one new piece, and checks for a win and for the
// end. After the end the board does not change.
export function applyMove(state: MergeState, dir: Dir): MergeState {
  if (state.over) return state
  const slid = slideBoard(state.board, dir)
  if (!slid.moved) return { ...state, presses: state.presses + 1 }
  const placed = spawn(slid.board, state.rng)
  const score = state.score + slid.gained
  return {
    board: placed.board,
    score,
    best: Math.max(state.best, score),
    rng: placed.rng,
    won: state.won || maxPiece(placed.board) >= WIN_VALUE,
    over: !canMove(placed.board),
    presses: state.presses + 1,
  }
}

// A new game with a new seed: the best score is kept, the board and the score are not.
export const restart = (state: MergeState, seed: number): MergeState => ({ ...newGame(seed, state.best), presses: state.presses + 1 })

export const isNewBest = (s: MergeState): boolean => s.over && s.score > 0 && s.score >= s.best

// ---- Drawing data -------------------------------------------------------------------------

export type Style = { color?: string; bg?: string; dim?: boolean; bold?: boolean }

// The heat of a piece: 2 is dark gray, then gray, dull red, red, orange red, orange, amber and
// yellow, and 512 and more is white on a hot background. Every pair is readable on its own colour.
const HEAT: ReadonlyArray<readonly [number, Style]> = [
  [2, { color: '#e4e4e4', bg: '#3a3a3a' }],
  [4, { color: '#ffffff', bg: '#5f5f5f' }],
  [8, { color: '#ffffff', bg: '#870000' }],
  [16, { color: '#ffffff', bg: '#d70000' }],
  [32, { color: '#000000', bg: '#d75f00' }],
  [64, { color: '#000000', bg: '#ff8700' }],
  [128, { color: '#000000', bg: '#ffaf00' }],
  [256, { color: '#000000', bg: '#ffd700' }],
]
// The same palette colour as MUTED in ui/palette.ts (core has no ui import).
export const EMPTY: Style = { color: '#a8a8a8' }
export const HOT: Style = { color: '#ffffff', bg: '#d7005f', bold: true }

export function pieceStyle(value: number): Style {
  if (value >= WIN_VALUE) return HOT
  const hit = HEAT.find(([v]) => v === value)
  return hit ? { ...hit[1], bold: true } : { color: '#ffffff', bg: '#6b2d2d', bold: true }
}

// A value centered in the cell width.
export function centered(text: string, width = CELL_W): string {
  const left = Math.max(0, Math.floor((width - text.length) / 2))
  return `${' '.repeat(left)}${text}`.padEnd(width).slice(0, width)
}

export type Piece = { text: string; style: Style }

// The board as 12 text rows (4 board rows of 3 rows each). Each row has 4 pieces of 7 columns.
// An empty cell is a dim dot. Every piece has the same width, so nothing shifts.
export function boardRows(board: readonly number[]): Piece[][] {
  const rows: Piece[][] = []
  for (let r = 0; r < SIZE; r++) {
    for (let line = 0; line < CELL_H; line++) {
      const cells: Piece[] = []
      for (let c = 0; c < SIZE; c++) {
        const v = board[r * SIZE + c] as number
        // An empty cell is a muted dot with an explicit colour (never a dim, never a theme colour).
        if (v === 0) cells.push({ text: centered(line === 1 ? '·' : ''), style: EMPTY })
        else cells.push({ text: line === 1 ? centered(String(v)) : ' '.repeat(CELL_W), style: pieceStyle(v) })
      }
      rows.push(cells)
    }
  }
  return rows
}

export const pad4 = (n: number): string => String(Math.max(0, Math.floor(n))).padStart(4, '0')

// The lines under the board, in plain short sentences.
export function messageFor(s: MergeState): string {
  if (s.over) return `${isNewBest(s) ? 'New best. ' : ''}${s.won ? 'White hot! You made 512. ' : ''}No more moves. Score ${s.score}. Press r for a new game. q or Esc leaves.`
  if (s.won) return 'White hot! You made 512. You can keep playing.'
  // A fresh board (no score, two pieces or fewer) gets the start text, also after r.
  if (s.score === 0 && s.board.filter(v => v !== 0).length <= 2) return 'Slide the pieces. Equal pieces merge and get hotter. Make a white hot 512.'
  return 'w a s d slide the pieces. r starts a new game. q or Esc leaves.'
}
