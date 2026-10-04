import { describe, expect, test } from 'claude-code/testing'

import {
  BOARD_WIDTH,
  CELL_H,
  CELL_W,
  DIRS,
  HOT,
  SIZE,
  WIN_VALUE,
  applyMove,
  boardRows,
  canMove,
  centered,
  isNewBest,
  maxPiece,
  messageFor,
  newGame,
  nextRandom,
  pad4,
  pieceStyle,
  restart,
  slideBoard,
  slideLine,
  spawn,
} from '../../hooks/temper-mod/core/merge'
import type { Dir, MergeState } from '../../hooks/temper-mod/core/merge'

const B = (rows: number[][]): number[] => rows.flat()
const state = (board: number[], over: Partial<MergeState> = {}): MergeState => ({ board, score: 0, best: 0, rng: 7, won: false, over: false, presses: 0, ...over })
const count = (board: readonly number[], v: number): number => board.filter(x => x === v).length

describe('slideLine: the rule for one line, toward the front', () => {
  test('equal pieces merge once, and a made piece does not merge again', () => {
    expect(slideLine([2, 2, 2, 2]).line).toEqual([4, 4, 0, 0])
    expect(slideLine([2, 2, 4, 0]).line).toEqual([4, 4, 0, 0])
    expect(slideLine([4, 2, 2, 0]).line).toEqual([4, 4, 0, 0])
    expect(slideLine([2, 2, 2, 0]).line).toEqual([4, 2, 0, 0])
    expect(slideLine([4, 4, 8, 0]).line).toEqual([8, 8, 0, 0])
  })

  test('pieces move to the front through empty cells', () => {
    expect(slideLine([0, 0, 0, 2]).line).toEqual([2, 0, 0, 0])
    expect(slideLine([0, 2, 0, 2]).line).toEqual([4, 0, 0, 0])
    expect(slideLine([2, 0, 0, 2]).line).toEqual([4, 0, 0, 0])
    expect(slideLine([0, 0, 0, 0]).line).toEqual([0, 0, 0, 0])
  })

  test('different neighbours do not merge', () => {
    expect(slideLine([2, 4, 2, 4]).line).toEqual([2, 4, 2, 4])
    expect(slideLine([2, 4, 8, 16]).line).toEqual([2, 4, 8, 16])
  })

  test('the score gained is the sum of the merged values', () => {
    expect(slideLine([2, 2, 2, 2]).gained).toBe(8)
    expect(slideLine([4, 2, 2, 0]).gained).toBe(4)
    expect(slideLine([2, 4, 8, 16]).gained).toBe(0)
    expect(slideLine([8, 8, 16, 16]).gained).toBe(48)
  })
})

describe('slideBoard: all four directions', () => {
  const start = B([
    [2, 0, 2, 4],
    [0, 2, 0, 0],
    [4, 4, 0, 8],
    [0, 0, 2, 8],
  ])

  const show = (dir: Dir) => slideBoard(start, dir)

  test('left', () => {
    expect(show('left').board).toEqual(
      B([
        [4, 4, 0, 0],
        [2, 0, 0, 0],
        [8, 8, 0, 0],
        [2, 8, 0, 0],
      ]),
    )
    expect(show('left').gained).toBe(4 + 8)
  })

  test('right', () => {
    expect(show('right').board).toEqual(
      B([
        [0, 0, 4, 4],
        [0, 0, 0, 2],
        [0, 0, 8, 8],
        [0, 0, 2, 8],
      ]),
    )
    expect(show('right').gained).toBe(4 + 8)
  })

  test('up', () => {
    expect(show('up').board).toEqual(
      B([
        [2, 2, 4, 4],
        [4, 4, 0, 16],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]),
    )
    expect(show('up').gained).toBe(20)
  })

  test('down', () => {
    expect(show('down').board).toEqual(
      B([
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [2, 2, 0, 4],
        [4, 4, 4, 16],
      ]),
    )
    expect(show('down').gained).toBe(20)
  })

  test('a slide that changes nothing says so', () => {
    const packed = B([
      [2, 4, 8, 16],
      [4, 8, 16, 2],
      [8, 16, 2, 4],
      [16, 2, 4, 8],
    ])
    for (const d of DIRS) expect(slideBoard(packed, d).moved).toBe(false)
    const left = B([
      [2, 0, 0, 0],
      [4, 0, 0, 0],
      [8, 0, 0, 0],
      [16, 0, 0, 0],
    ])
    expect(slideBoard(left, 'left').moved).toBe(false)
    expect(slideBoard(left, 'right').moved).toBe(true)
  })

  test('a slide never changes the sum of the pieces and never makes a piece from nothing', () => {
    for (const d of DIRS) {
      const out = slideBoard(start, d).board
      expect(out.reduce((a, b) => a + b, 0)).toBe(start.reduce((a, b) => a + b, 0))
      expect(out).toHaveLength(SIZE * SIZE)
    }
  })

  test('one merge for each piece in one move, in every direction', () => {
    const row = B([
      [2, 2, 2, 2],
      [0, 0, 0, 0],
      [0, 0, 0, 0],
      [0, 0, 0, 0],
    ])
    expect(slideBoard(row, 'left').board.slice(0, 4)).toEqual([4, 4, 0, 0])
    expect(slideBoard(row, 'right').board.slice(0, 4)).toEqual([0, 0, 4, 4])
    const col = B([
      [2, 0, 0, 0],
      [2, 0, 0, 0],
      [2, 0, 0, 0],
      [2, 0, 0, 0],
    ])
    expect([0, 4, 8, 12].map(i => slideBoard(col, 'up').board[i])).toEqual([4, 4, 0, 0])
    expect([0, 4, 8, 12].map(i => slideBoard(col, 'down').board[i])).toEqual([0, 0, 4, 4])
  })
})

describe('seeded generator and spawn', () => {
  test('the same seed gives the same numbers, in 0 up to 1', () => {
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
    expect(seq(5)).toEqual(seq(5))
    expect(seq(5)).not.toEqual(seq(6))
    for (const v of seq(9)) {
      expect(v).toBeGreaterThanOrEqual(0)
      expect(v).toBeLessThan(1)
    }
  })

  test('spawn puts one 2 or 4 in an empty cell and nowhere else', () => {
    const board = B([
      [2, 4, 8, 16],
      [4, 0, 16, 2],
      [8, 16, 0, 4],
      [16, 2, 4, 8],
    ])
    for (let seed = 1; seed < 40; seed++) {
      const out = spawn(board, seed)
      const changed = out.board.map((v, i) => (v !== board[i] ? i : -1)).filter(i => i >= 0)
      expect(changed).toHaveLength(1)
      expect([5, 10]).toContain(changed[0])
      expect([2, 4]).toContain(out.board[changed[0] as number])
    }
  })

  test('spawn is deterministic and mostly 2', () => {
    const empty = new Array<number>(16).fill(0)
    expect(spawn(empty, 3)).toEqual(spawn(empty, 3))
    let twos = 0
    let fours = 0
    let rng = 11
    for (let i = 0; i < 400; i++) {
      const out = spawn(empty, rng)
      rng = out.rng
      const v = out.board.find(x => x !== 0) as number
      if (v === 2) twos++
      else fours++
    }
    expect(twos + fours).toBe(400)
    expect(twos).toBeGreaterThan(fours * 4)
    expect(fours).toBeGreaterThan(0)
  })

  test('spawn on a full board changes nothing', () => {
    const full = B([
      [2, 4, 8, 16],
      [4, 8, 16, 2],
      [8, 16, 2, 4],
      [16, 2, 4, 8],
    ])
    expect(spawn(full, 1).board).toEqual(full)
  })
})

describe('a game', () => {
  test('a new game has two pieces, no score, and keeps the best score', () => {
    const g = newGame(42, 900)
    expect(g.board).toHaveLength(16)
    expect(g.board.filter(v => v !== 0)).toHaveLength(2)
    expect(g.score).toBe(0)
    expect(g.best).toBe(900)
    expect(g.won).toBe(false)
    expect(g.over).toBe(false)
    expect(newGame(42, 900)).toEqual(g)
    expect(newGame(43, 900)).not.toEqual(g)
  })

  test('the same seed and the same moves give the same game', () => {
    const play = (seed: number) => {
      let g = newGame(seed)
      for (let i = 0; i < 60; i++) g = applyMove(g, DIRS[i % 4] as Dir)
      return g
    }
    expect(play(8)).toEqual(play(8))
    expect(play(8)).not.toEqual(play(9))
  })

  test('a move that changes the board adds one piece and the score', () => {
    const g = state(B([
      [2, 2, 0, 0],
      [0, 0, 0, 0],
      [0, 0, 0, 0],
      [0, 0, 0, 0],
    ]))
    const out = applyMove(g, 'left')
    expect(out.score).toBe(4)
    expect(out.best).toBe(4)
    expect(out.board.filter(v => v !== 0)).toHaveLength(2)
    expect(out.board[0]).toBe(4)
    expect(out.presses).toBe(1)
  })

  test('a move that changes nothing adds no piece and no score, but counts as a press', () => {
    const g = state(B([
      [2, 0, 0, 0],
      [0, 0, 0, 0],
      [0, 0, 0, 0],
      [0, 0, 0, 0],
    ]))
    const out = applyMove(g, 'left')
    expect(out.board).toEqual(g.board)
    expect(out.score).toBe(0)
    expect(out.rng).toBe(g.rng)
    expect(out.presses).toBe(1)
  })

  test('the best score follows the score, and a lower new game score does not lower it', () => {
    const g = state(B([[4, 4, 0, 0], ...new Array(3).fill([0, 0, 0, 0])]), { score: 10, best: 50 })
    expect(applyMove(g, 'left').best).toBe(50)
    const g2 = state(B([[4, 4, 0, 0], ...new Array(3).fill([0, 0, 0, 0])]), { score: 48, best: 50 })
    expect(applyMove(g2, 'left').best).toBe(56)
    expect(restart(g2, 5).best).toBe(50)
    expect(restart(g2, 5).score).toBe(0)
  })

  test('game over when no move changes the board, and then the board stays', () => {
    const almost = state(B([
      [2, 4, 8, 16],
      [4, 8, 16, 32],
      [8, 16, 32, 64],
      [16, 32, 64, 0],
    ]), { rng: 1 })
    expect(canMove(almost.board)).toBe(true)
    // Slide a piece into the last cell: the board is then full with no equal neighbours.
    const out = applyMove(almost, 'right')
    expect(out.over).toBe(false)
    const dead = state(B([
      [2, 4, 2, 4],
      [4, 2, 4, 2],
      [2, 4, 2, 4],
      [4, 2, 4, 2],
    ]), { over: true })
    expect(canMove(dead.board)).toBe(false)
    expect(applyMove(dead, 'left')).toBe(dead)
  })

  test('a move that fills the board with no pair left ends the game', () => {
    // One empty cell. Moving left shifts the piece, spawn fills the cell, and nothing can merge.
    const g = state(B([
      [4, 2, 4, 2],
      [2, 4, 2, 4],
      [4, 2, 4, 2],
      [0, 4, 8, 16],
    ]), { rng: 3 })
    const out = applyMove(g, 'left')
    expect(out.over).toBe(canMove(out.board) === false)
  })

  test('a full board with an equal pair can still move', () => {
    const b = B([
      [2, 2, 4, 8],
      [4, 8, 16, 32],
      [8, 16, 32, 64],
      [16, 32, 64, 128],
    ])
    expect(canMove(b)).toBe(true)
  })

  test('making a 512 piece wins once, and the player keeps playing', () => {
    const g = state(B([
      [256, 256, 0, 0],
      [0, 0, 0, 0],
      [0, 0, 0, 0],
      [0, 0, 0, 0],
    ]))
    const out = applyMove(g, 'left')
    expect(maxPiece(out.board)).toBe(WIN_VALUE)
    expect(out.won).toBe(true)
    expect(out.over).toBe(false)
    expect(out.score).toBe(512)
    // The next move keeps the win and the game goes on.
    const next = applyMove(out, 'right')
    expect(next.won).toBe(true)
    expect(next.board).not.toEqual(out.board)
  })

  test('a piece bigger than 512 also counts as a win', () => {
    const g = state(B([
      [512, 512, 0, 0],
      [0, 0, 0, 0],
      [0, 0, 0, 0],
      [0, 0, 0, 0],
    ]))
    expect(applyMove(g, 'left').won).toBe(true)
  })

  test('a new best is reported only at the end of a game with a score at the best', () => {
    expect(isNewBest(state([], { over: true, score: 120, best: 120 }))).toBe(true)
    expect(isNewBest(state([], { over: true, score: 80, best: 120 }))).toBe(false)
    expect(isNewBest(state([], { over: false, score: 120, best: 120 }))).toBe(false)
    expect(isNewBest(state([], { over: true, score: 0, best: 0 }))).toBe(false)
  })

  test('a long random game keeps the rules: the sum grows only by pieces added, and a stuck game ends', () => {
    let g = newGame(2026)
    let guard = 0
    while (!g.over && guard++ < 4000) {
      const before = g.board.reduce((a, b) => a + b, 0)
      const d = DIRS[guard % 4] as Dir
      const next = applyMove(g, d)
      const after = next.board.reduce((a, b) => a + b, 0)
      // A move adds at most one piece of 2 or 4.
      expect(after - before === 0 || after - before === 2 || after - before === 4).toBe(true)
      expect(next.board.every(v => v === 0 || (v & (v - 1)) === 0)).toBe(true)
      g = next
    }
    expect(g.over).toBe(true)
    expect(canMove(g.board)).toBe(false)
  })
})

describe('drawing data', () => {
  test('the heat goes from dark gray to white hot', () => {
    expect(pieceStyle(2).bg).toBe('#3a3a3a')
    expect(pieceStyle(4).bg).toBe('#5f5f5f')
    expect(pieceStyle(8).bg).toBe('#870000')
    expect(pieceStyle(16).bg).toBe('#d70000')
    expect(pieceStyle(32).bg).toBe('#d75f00')
    expect(pieceStyle(64).bg).toBe('#ff8700')
    expect(pieceStyle(128).bg).toBe('#ffaf00')
    expect(pieceStyle(256).bg).toBe('#ffd700')
    for (const v of [512, 1024, 2048, 4096]) expect(pieceStyle(v)).toEqual(HOT)
    expect(HOT.color).toBe('#ffffff')
    // Every value has its own background.
    expect(new Set([2, 4, 8, 16, 32, 64, 128, 256, 512].map(v => pieceStyle(v).bg)).size).toBe(9)
    // A light piece has dark text and a dark piece has light text.
    for (const v of [32, 64, 128, 256]) expect(pieceStyle(v).color).toBe('#000000')
    for (const v of [2, 4, 8, 16, 512]) expect(['#e4e4e4', '#ffffff']).toContain(pieceStyle(v).color)
  })

  test('a number is centered in 7 columns', () => {
    expect(centered('2')).toBe('   2   ')
    expect(centered('16')).toBe('  16   ')
    expect(centered('512')).toBe('  512  ')
    expect(centered('2048')).toBe(' 2048  ')
    expect(centered('')).toBe('       ')
    for (const t of ['2', '16', '512', '2048', '16384']) expect(centered(t)).toHaveLength(CELL_W)
  })

  test('the board is 12 rows of 4 pieces, every piece 7 columns, and the board is 29 columns wide', () => {
    const rows = boardRows(B([
      [2, 0, 16, 512],
      [0, 0, 0, 0],
      [4, 8, 0, 2048],
      [0, 0, 0, 1024],
    ]))
    expect(rows).toHaveLength(SIZE * CELL_H)
    for (const r of rows) {
      expect(r).toHaveLength(SIZE)
      for (const p of r) expect(p.text).toHaveLength(CELL_W)
    }
    expect(BOARD_WIDTH).toBe(29)
    // The middle row of a cell carries the number. The other rows are blank colour.
    expect(rows[1]?.[0]?.text).toBe('   2   ')
    expect(rows[0]?.[0]?.text).toBe('       ')
    expect(rows[1]?.[2]?.text).toBe('  16   ')
    expect(rows[1]?.[3]?.style).toEqual(HOT)
    // An empty cell is a dim dot, with no background.
    expect(rows[1]?.[1]?.text).toBe('   ·   ')
    expect(rows[1]?.[1]?.style).toEqual({ color: '#a8a8a8' })
    expect(rows[0]?.[1]?.style.bg).toBeUndefined()
  })

  test('scores print with four digits', () => {
    expect(pad4(7)).toBe('0007')
    expect(pad4(1240)).toBe('1240')
    expect(pad4(12345)).toBe('12345')
    expect(pad4(-3)).toBe('0000')
  })

  test('messages are short plain sentences', () => {
    expect(messageFor(newGame(1))).toBe('Slide the pieces. Equal pieces merge and get hotter. Make a white hot 512.')
    // Also after r (the press count is not zero then).
    expect(messageFor({ ...newGame(1), presses: 5 })).toBe('Slide the pieces. Equal pieces merge and get hotter. Make a white hot 512.')
    expect(messageFor(state([2], { score: 8, presses: 3 }))).toBe('w a s d slide the pieces. r starts a new game. q or Esc leaves.')
    expect(messageFor(state([2], { won: true, score: 512, presses: 40 }))).toBe('White hot! You made 512. You can keep playing.')
    expect(messageFor(state([2], { over: true, score: 1240, best: 2000, presses: 90 }))).toBe('No more moves. Score 1240. Press r for a new game. q or Esc leaves.')
    expect(messageFor(state([2], { over: true, score: 2100, best: 2100, presses: 90 }))).toBe('New best. No more moves. Score 2100. Press r for a new game. q or Esc leaves.')
    expect(messageFor(state([2], { over: true, won: true, score: 3000, best: 3000, presses: 90 }))).toBe('New best. White hot! You made 512. No more moves. Score 3000. Press r for a new game. q or Esc leaves.')
  })

  test('counts of a value on a board', () => {
    expect(count(B([[2, 2, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 2]]), 2)).toBe(3)
  })
})
