import type { ClientModule } from 'claude-code'

import { BOARD_WIDTH, boardRows, messageFor, pad4 } from '../core/merge'
import type { Dir } from '../core/merge'
import { CARD_BG, FG, GREEN, MUTED, ORANGE, YELLOW } from './palette'

// The drawing of Temper Merge, and the keys that reach it after a click. This module has no engine
// calls at all: it draws with Box and Text, and it posts a key to the hooks module, which holds
// the game (so a closed pane keeps its board). The hooks module draws again with the new props.

export type GameProps = {
  board: number[]
  score: number
  best: number
  won: boolean
  over: boolean
  // How many times a move key was pressed anywhere. A change means keys arrive.
  presses: number
  // A short line from Temper for the top of the game area, or null.
  banner: string | null
}

type State = {
  // Quarter seconds since the game opened, counted only until the first key, click or press. A game
  // cannot know whether the keys reach it, so after 3 seconds with none it says how to get them.
  age: number
  // Any key, click or press has arrived.
  touched: boolean
  // The press count this drawing has seen.
  seenPresses: number
}

const TICK_MS = 250
// 3 seconds.
const NO_KEYS_TICKS = 12
const NO_KEYS_LINE = 'No keys yet? Press Ctrl+X, then Tab, to give the game the keys.'

const KEYS: Record<string, Dir> = {
  w: 'up',
  W: 'up',
  up: 'up',
  a: 'left',
  A: 'left',
  left: 'left',
  s: 'down',
  S: 'down',
  down: 'down',
  d: 'right',
  D: 'right',
  right: 'right',
}

const GameClient: ClientModule<GameProps, State> = (props, surface) => {
  const { Box, Text } = surface.elements
  const first = surface.state === undefined
  let current: State = surface.state ?? { age: 0, touched: false, seenPresses: props.presses }

  // A press anywhere (a pane Button, or a key after a click) proves that keys arrive.
  if (!first && props.presses !== current.seenPresses) {
    current = { ...current, touched: true, seenPresses: props.presses }
    surface.setState(current)
  }

  if (first) {
    surface.setState(current)

    // Count up to the limit, then stop writing.
    surface.every(TICK_MS, () => {
      const cur = surface.state
      if (!cur || cur.touched || cur.age > NO_KEYS_TICKS) return
      surface.setState({ ...cur, age: cur.age + 1 })
    })

    surface.onKey(event => {
      const cur = surface.state
      if (!cur) return
      if (!cur.touched) surface.setState({ ...cur, touched: true })
      const dir = KEYS[event.key]
      if (dir) surface.post({ kind: 'move', dir })
      else if (event.key === 'r' || event.key === 'R') surface.post({ kind: 'new' })
    })

    surface.onPointer(event => {
      const cur = surface.state
      if (!cur || event.type !== 'down' || cur.touched) return
      surface.setState({ ...cur, touched: true })
    })
  }

  const message = messageFor({ board: props.board, score: props.score, best: props.best, rng: 0, won: props.won, over: props.over, presses: props.presses })

  // The same card as the pane (ui/palette.ts): an explicit background, explicit colours, no dim.
  return (
    <Box flexDirection="column" backgroundColor={CARD_BG}>
      {props.banner ? <Text color={YELLOW} wrap="truncate">{props.banner}</Text> : null}
      <Box flexDirection="row" columnGap={1} flexWrap="wrap">
        <Text color={ORANGE} bold>▲ TEMPER MERGE</Text>
        <Text color={FG} bold>{`score ${pad4(props.score)}`}</Text>
        <Text color={FG} bold>{`best ${pad4(Math.max(props.best, props.score))}`}</Text>
      </Box>
      {boardRows(props.board).map((row, i) => (
        <Box key={`row-${i}`} flexDirection="row" width={BOARD_WIDTH}>
          <Text color={FG}>{' '}</Text>
          {row.map((piece, j) => (
            <Text key={`cell-${j}`} color={piece.style.color} backgroundColor={piece.style.bg} bold={piece.style.bold}>
              {piece.text}
            </Text>
          ))}
        </Box>
      ))}
      <Text color={props.won ? GREEN : FG}>{message}</Text>
      {!current.touched && current.age >= NO_KEYS_TICKS ? <Text color={MUTED}>{NO_KEYS_LINE}</Text> : null}
    </Box>
  )
}

export default GameClient
