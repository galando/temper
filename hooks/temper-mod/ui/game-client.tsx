import type { ClientModule } from 'claude-code'

import { TICK_MS, drawScene, heatAt, isNewRecord, lineFor, lineTwo, newGame, pad5, press, runs, start, step, widthFor, withWidth } from '../core/runner'
import type { RunState } from '../core/runner'
import { CARD_BG, FG, GREEN, MUTED, ORANGE, YELLOW } from './palette'

// The clock and the drawing of Temper Run. This module has no engine calls at all: it draws with
// Box and Text, runs the frame clock, applies the key presses it is given, and posts the score once
// when a run ends so the hooks module can keep the best score.
//
// A key reaches the game two ways. The pane Buttons (w, s, r) add one to a counter in the plugin
// state, and the hooks module hands the counters over as props. After one click on the game the keys
// also arrive here directly (Space and Up arrow jump, Down arrow ducks), with no wait.

export type GameProps = {
  // How many times each Button was pressed. A change is a new press.
  jumpCount: number
  duckCount: number
  startCount: number
  // The seed for the next run, and the best score from the store.
  seed: number
  best: number
  // A short line from Temper for the top of the game area, or null.
  banner: string | null
  // The pane sits inline above the prompt (a narrow terminal) and shows about 14 lines. Then the top
  // rows of sky are left out and the Temper line is not drawn, so the floor and the help line show.
  compact: boolean
}

type State = {
  g: RunState
  // The counters this drawing has already applied.
  seenJump: number
  seenDuck: number
  seenStart: number
  // The score was posted for this game over.
  posted: boolean
  // Ticks since the game opened, counted until the first key, click or press. A game cannot know
  // whether the keys reach it, so after 3 seconds with none it says how to get them.
  age: number
  touched: boolean
}

// Rows of sky left out when the pane is inline: the top of a jump is then a little cut off.
export const COMPACT_CUT = 3

// 3 seconds.
const NO_KEYS_TICKS = Math.ceil(3000 / TICK_MS)
const NO_KEYS_LINE = 'No keys yet? Press Ctrl+X, then Tab, to give the game the keys.'

const JUMP_KEYS = [' ', 'space', 'up', 'w', 'W']
const DUCK_KEYS = ['down', 's', 'S']
const RUN_KEYS = ['r', 'R']

const nextSeed = (g: RunState): number => (g.rng ^ Math.imul(g.tick + 7, 2654435761)) >>> 0

const GameClient: ClientModule<GameProps, State> = (props, surface) => {
  const { Box, Text } = surface.elements
  const first = surface.state === undefined
  let current: State = surface.state ?? {
    g: newGame(props.seed, props.best, widthFor(surface.columns)),
    seenJump: props.jumpCount,
    seenDuck: props.duckCount,
    seenStart: props.startCount,
    posted: false,
    age: 0,
    touched: false,
  }

  // New presses of the pane Buttons: Run first, then Jump and Duck, each applied once.
  if (!first && (props.startCount !== current.seenStart || props.jumpCount !== current.seenJump || props.duckCount !== current.seenDuck)) {
    let g = current.g
    let posted = current.posted
    if (props.startCount !== current.seenStart) {
      g = start(g, props.seed)
      posted = false
    }
    if (props.jumpCount !== current.seenJump) g = press(g, 'jump')
    if (props.duckCount !== current.seenDuck) g = press(g, 'duck')
    current = { ...current, g, posted, seenJump: props.jumpCount, seenDuck: props.duckCount, seenStart: props.startCount, touched: true }
    surface.setState(current)
  }

  if (first) {
    surface.setState(current)

    surface.every(TICK_MS, () => {
      const cur = surface.state
      if (!cur) return
      if (cur.g.status === 'running') {
        const g = step(cur.g)
        let posted = cur.posted
        if (g.status === 'over' && !posted) {
          // One post for each game over.
          surface.post({ kind: 'game-over', score: g.score })
          posted = true
        }
        surface.setState({ ...cur, g, posted })
        return
      }
      // Waiting for the first key: count up to the limit, then stop writing.
      if (!cur.touched && cur.age <= NO_KEYS_TICKS) surface.setState({ ...cur, age: cur.age + 1 })
    })

    // Keys that arrive after a click on the game.
    surface.onKey(event => {
      const seen = surface.state
      if (!seen) return
      let cur: State = seen.touched ? seen : { ...seen, touched: true }
      if (JUMP_KEYS.includes(event.key)) cur = { ...cur, g: press(cur.g, 'jump') }
      else if (DUCK_KEYS.includes(event.key)) cur = { ...cur, g: press(cur.g, 'duck') }
      else if (RUN_KEYS.includes(event.key) && cur.g.status !== 'running') cur = { ...cur, g: start(cur.g, nextSeed(cur.g)), posted: false }
      if (cur !== seen) surface.setState(cur)
    })

    surface.onPointer(event => {
      const cur = surface.state
      if (!cur || event.type !== 'down' || cur.touched) return
      surface.setState({ ...cur, touched: true })
    })
  }

  // The field follows the region: when the width changes, the game takes the new width once.
  const width = widthFor(surface.columns)
  if (current.g.width !== width) {
    current = { ...current, g: withWidth(current.g, width) }
    surface.setState(current)
  }

  const g = current.g
  const hi = Math.max(g.hi, props.best)
  const heat = heatAt(g.score)
  const second = lineTwo(g)

  // The same card as the pane (ui/palette.ts): an explicit background and explicit colours for every
  // line of text. The picture is made of coloured half blocks (Box key scene-...), drawn as pixels.
  return (
    <Box flexDirection="column" backgroundColor={CARD_BG}>
      {props.banner && !props.compact ? <Text color={YELLOW} wrap="truncate">{props.banner}</Text> : null}
      <Box flexDirection="row" columnGap={1} flexWrap="wrap" justifyContent="space-between" width={g.width}>
        <Box flexDirection="row" columnGap={1}>
          <Text color={ORANGE} bold>▲ TEMPER RUN</Text>
          <Box flexDirection="row">
            <Text color={ORANGE}>{'▮'.repeat(heat)}</Text>
            <Text color={MUTED}>{'▯'.repeat(5 - heat)}</Text>
          </Box>
        </Box>
        {g.banner ? <Text color={YELLOW} bold>{g.banner}</Text> : null}
        <Text color={FG} bold>{`HI ${pad5(hi)}  ${pad5(g.score)}`}</Text>
      </Box>
      {drawScene(g).slice(props.compact ? COMPACT_CUT : 0).map((row, i) => (
        <Box key={`scene-${i}`} flexDirection="row" width={g.width}>
          {runs(row).map((run, j) => (
            <Text key={`px-${j}`} color={run.fg} backgroundColor={run.bg}>
              {run.text}
            </Text>
          ))}
        </Box>
      ))}
      <Text color={isNewRecord(g) ? GREEN : FG}>{lineFor(g)}</Text>
      {second ? <Text color={FG}>{second}</Text> : null}
      {!current.touched && current.age >= NO_KEYS_TICKS ? <Text color={MUTED}>{NO_KEYS_LINE}</Text> : null}
    </Box>
  )
}

export default GameClient
