import type { ClientModule } from 'claude-code'

import { TICK_MS, blockAhead, drawRows, heatAt, jump, messageFor, newGame, pad4, runs, start, step, widthFor, withWidth } from '../core/game'
import type { GameState } from '../core/game'

// The drawing and the keys of Temper Run. This module runs on the surface's own frame clock and
// has no engine calls at all: it draws with Box and Text, reads keys with onKey, and posts the
// score once when a game ends so the hooks module can keep the best score.

export type GameProps = {
  best: number
  // A short line from Temper for the top of the game area, or null.
  banner: string | null
  seed: number
  // How many times the pane's Jump and Start Buttons were pressed. The game compares them with
  // the values it saw last and applies each new press once.
  jumpCount: number
  startCount: number
}

type State = {
  // Ticks since the game opened, counted only until the first key or press. A game cannot know
  // whether the keys reach it, so after 3 seconds with none it says how to get them.
  age: number
  // Any key, click or Button press has arrived.
  touched: boolean
  // The counters this game has already applied.
  seenJump: number
  seenStart: number
  g: GameState
  // Ticks since the last key or click while the game runs. After 25 (2 seconds) with no block
  // close, the game pauses. This is how it stops when the game has no keys.
  idle: number
  paused: boolean
  // The score was posted for this game over.
  posted: boolean
}

// 3 seconds of 80 ms ticks, rounded up.
const NO_KEYS_TICKS = Math.ceil(3000 / TICK_MS)
const NO_KEYS_LINE = 'No keys yet? Press Ctrl+X, then Tab, to give the game the keys.'
const IDLE_TICKS = 25
// A block this close (in cells) keeps the game running, so an idle game never skips a block.
const NEAR = 14

// Keys that reach the game itself after a click. Space, Up, w jump; s starts.
const JUMP_KEYS = [' ', 'space', 'up', 'w', 'W']
const START_KEYS = ['s', 'S']

// One press of Start: start a game that is ready or over; wake a paused one. A running game ignores it.
function pressStart(cur: State): State {
  if (cur.g.status === 'running' && !cur.paused) return cur
  if (cur.g.status === 'running') return { ...cur, idle: 0, paused: false }
  return { ...cur, g: start(cur.g, nextSeed(cur.g)), idle: 0, paused: false, posted: false }
}

// One press of Jump: a paused game wakes up. A game that has not started does not move.
function pressJump(cur: State): State {
  if (cur.g.status !== 'running') return cur
  if (cur.paused) return { ...cur, idle: 0, paused: false }
  return { ...cur, g: jump(cur.g), idle: 0 }
}

const nextSeed = (g: GameState): number => (g.rng ^ Math.imul(g.tick + 1, 2654435761)) >>> 0

const GameClient: ClientModule<GameProps, State> = (props, surface) => {
  const { Box, Text } = surface.elements
  const first = surface.state === undefined
  // The counters start at what the pane shows now, so a press made before this game existed is not replayed.
  let current: State = surface.state ?? {
    g: newGame(props.seed, props.best, widthFor(surface.columns)),
    idle: 0,
    paused: false,
    posted: false,
    seenJump: props.jumpCount,
    seenStart: props.startCount,
    age: 0,
    touched: false,
  }

  // New presses of the pane's Buttons: Start first, then Jump, each applied once.
  if (!first && (props.startCount !== current.seenStart || props.jumpCount !== current.seenJump)) {
    let next = current
    if (props.startCount !== next.seenStart) next = pressStart(next)
    if (props.jumpCount !== next.seenJump) next = pressJump(next)
    current = { ...next, seenStart: props.startCount, seenJump: props.jumpCount, touched: true }
    surface.setState(current)
  }

  if (first) {
    // Set up once: the first call has no state yet.
    surface.setState(current)

    surface.every(TICK_MS, () => {
      const cur = surface.state
      // Waiting for the first key: count up to the limit, then stop writing.
      if (cur && !cur.touched && cur.g.status === 'ready') {
        if (cur.age <= NO_KEYS_TICKS) surface.setState({ ...cur, age: cur.age + 1 })
        return
      }
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
      surface.setState({ ...cur, g, idle, paused: false, posted })
    })

    // Keys that arrive after a click on the game. The pane's own Buttons (s, w, q) cover the
    // keyboard when the pane holds it; these keep a clicked game playable too.
    surface.onKey(event => {
      const seen = surface.state
      if (!seen) return
      // Any key proves the keys arrive, so the no keys line goes.
      const cur = seen.touched ? seen : { ...seen, touched: true }
      if (cur !== seen) surface.setState(cur)
      if (START_KEYS.includes(event.key)) {
        surface.setState(pressStart(cur))
        return
      }
      if (!JUMP_KEYS.includes(event.key)) return
      // Space also starts a game that is ready or over.
      if (cur.g.status !== 'running' && (event.key === ' ' || event.key === 'space')) surface.setState(pressStart(cur))
      else surface.setState(pressJump(cur))
    })

    // A click gives the game the keys, so a click also wakes a paused game.
    surface.onPointer(event => {
      const cur = surface.state
      if (!cur || event.type !== 'down') return
      if (!cur.paused && cur.touched) return
      surface.setState({ ...cur, touched: true, idle: 0, paused: false })
    })
  }

  // The field follows the region: when the width changes, the game takes the new width once.
  const width = widthFor(surface.columns)
  if (current.g.width !== width) {
    current = { ...current, g: withWidth(current.g, width) }
    surface.setState(current)
  }

  const g = current.g
  const best = Math.max(g.best, props.best)

  return (
    <Box flexDirection="column">
      {props.banner ? <Text color="yellow" wrap="truncate">{props.banner}</Text> : null}
      <Box flexDirection="row" columnGap={1} flexWrap="wrap">
        <Text color="yellow" bold>▲ TEMPER RUN</Text>
        <Text bold>{`score ${pad4(g.score)}`}</Text>
        <Text bold>{`best ${pad4(best)}`}</Text>
        <Text color="#ff8c1a" bold>{`heat ${heatAt(g.tick)}`}</Text>
      </Box>
      {drawRows(g).map((row, i) => (
        <Box key={`row-${i}`} flexDirection="row" width={g.width}>
          {runs(row).map((run, j) => (
            <Text key={`seg-${j}`} color={run.style.color} dimColor={run.style.dim} bold={run.style.bold}>
              {run.text}
            </Text>
          ))}
        </Box>
      ))}
      <Text dimColor>{messageFor(g, current.paused)}</Text>
      {!current.touched && g.status === 'ready' && current.age >= NO_KEYS_TICKS ? <Text dimColor>{NO_KEYS_LINE}</Text> : null}
    </Box>
  )
}

export default GameClient
