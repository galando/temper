import type { ClientModule } from 'claude-code'

import { FIELD, TICK_MS, blockAhead, frameRows, isNewBest, jump, newGame, pad4, start, step } from '../core/game'
import type { GameState } from '../core/game'

// The drawing and the keys of Temper Run. This module runs on the surface's own frame clock and
// has no engine calls at all: it draws with Box and Text, reads keys with onKey, and posts the
// score once when a game ends so the hooks module can keep the best score.

export type GameProps = {
  best: number
  // A short line from Temper for the top of the game area, or null.
  banner: string | null
  seed: number
}

type State = {
  g: GameState
  // Ticks since the last key or click while the game runs. After 25 (2 seconds) with no block
  // close, the game pauses. This is how it stops when the game has no keys.
  idle: number
  paused: boolean
  // The score was posted for this game over.
  posted: boolean
}

const IDLE_TICKS = 25
// A block this close (in cells) keeps the game running, so an idle game never skips a block.
const NEAR = 14

const JUMP_KEYS = [' ', 'space', 'up', 'w', 'W']

const COLOR: Record<string, { color?: string; dim?: boolean; bold?: boolean }> = {
  '#': { color: 'blue', bold: true },
  '^': { color: 'yellow', bold: true },
  A: { color: 'red', bold: true },
  _: { dim: true },
  ' ': {},
}

// Runs of one character, so one Text carries one colour.
function segments(row: string): Array<{ text: string; ch: string }> {
  const out: Array<{ text: string; ch: string }> = []
  for (const ch of row) {
    const last = out[out.length - 1]
    if (last && last.ch === ch) last.text += ch
    else out.push({ text: ch, ch })
  }
  return out
}

const nextSeed = (g: GameState): number => (g.rng ^ Math.imul(g.tick + 1, 2654435761)) >>> 0

const GameClient: ClientModule<GameProps, State> = (props, surface) => {
  const { Box, Text } = surface.elements
  const current: State = surface.state ?? { g: newGame(props.seed, props.best), idle: 0, paused: false, posted: false }

  if (surface.state === undefined) {
    // Set up once: the first call has no state yet.
    surface.setState(current)

    surface.every(TICK_MS, () => {
      const cur = surface.state
      if (!cur || cur.g.status !== 'running' || cur.paused) return
      const idle = cur.idle + 1
      if (idle > IDLE_TICKS && !blockAhead(cur.g, NEAR)) {
        surface.setState({ ...cur, idle, paused: true })
        return
      }
      const g = step(cur.g)
      let posted = cur.posted
      if (g.status === 'over' && !posted) {
        // One post for each game over.
        surface.post({ kind: 'game-over', score: g.score, best: g.best })
        posted = true
      }
      surface.setState({ g, idle, paused: false, posted })
    })

    surface.onKey(event => {
      const cur = surface.state
      if (!cur || !JUMP_KEYS.includes(event.key)) return
      let g = cur.g
      let posted = cur.posted
      if (g.status === 'ready') g = start(g, nextSeed(g))
      else if (g.status === 'over') {
        g = start(g, nextSeed(g))
        posted = false
      } else if (!cur.paused) g = jump(g)
      surface.setState({ g, idle: 0, paused: false, posted })
    })

    // A click gives the game the keys, so a click also wakes a paused game.
    surface.onPointer(event => {
      const cur = surface.state
      if (!cur || event.type !== 'down' || !cur.paused) return
      surface.setState({ ...cur, idle: 0, paused: false })
    })
  }

  const g = current.g
  const best = Math.max(g.best, props.best)
  const hint =
    g.status === 'ready'
      ? 'Press Space to start. Space, Up or W jumps. Esc leaves.'
      : current.paused
        ? 'Paused. Press Space to go on. Esc leaves.'
        : g.status === 'over'
          ? `${isNewBest(g) ? 'New best score. ' : ''}Game over. Press Space to play again. Esc leaves.`
          : 'Space, Up or W jumps. Esc leaves.'

  return (
    <Box flexDirection="column">
      {props.banner ? <Text color="yellow" wrap="truncate">{props.banner}</Text> : null}
      <Text bold>{`TEMPER RUN   score ${pad4(g.score)}   best ${pad4(best)}`}</Text>
      {frameRows(g).map((row, i) => (
        <Box key={`row-${i}`} flexDirection="row" width={FIELD.width}>
          {segments(row).map((seg, j) => (
            <Text key={`seg-${j}`} color={COLOR[seg.ch]?.color} dimColor={COLOR[seg.ch]?.dim} bold={COLOR[seg.ch]?.bold}>
              {seg.text}
            </Text>
          ))}
        </Box>
      ))}
      <Text dimColor wrap="truncate">{hint}</Text>
    </Box>
  )
}

export default GameClient
