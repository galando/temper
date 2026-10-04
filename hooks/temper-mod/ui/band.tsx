import type { RenderElement } from 'claude-code'

import type { UiMode } from '../core/config'
import { phaseBarStyle } from '../core/modes'
import { MARK, whereText } from '../core/view'
import type { Step, View } from '../core/view'
import { REASON_KEY } from './kit'
import type { Kit, OnAction, OnReason } from './kit'

// Below this width the band uses its compact form: no borders, the stepper as plain words,
// short button labels. Nothing wraps into a mess.
export const COMPACT_BELOW = 100

export const REASON_HINT = 'A skip needs a reason. Temper writes it in the report.'

const COLOR: Record<Step['status'], string | undefined> = { done: 'green', current: 'blue', pending: undefined, stale: 'yellow' }

// One chip of the phase bar: done is green with a check, the current phase is a filled blue
// chip, upcoming phases are dim and outlined, a phase to redo is yellow with a redo mark.
function chip(kit: Kit, step: Step, compact: boolean) {
  const { Box, Text } = kit
  const label = step.status === 'done' || step.status === 'stale' ? `${MARK[step.status]} ${step.label}` : step.label
  const isCurrent = step.status === 'current'
  const text = (
    <Text bold={isCurrent} color={isCurrent ? 'white' : COLOR[step.status]} dimColor={step.status === 'pending'}>
      {isCurrent ? `${MARK.current} ${label}` : label}
    </Text>
  )
  if (compact) {
    return (
      <Box key={`step-${step.id}`} paddingX={1} backgroundColor={isCurrent ? 'blue' : undefined}>
        {text}
      </Box>
    )
  }
  return (
    <Box
      key={`step-${step.id}`}
      borderStyle="round"
      borderColor={isCurrent ? 'blue' : COLOR[step.status] ?? 'gray'}
      borderDimColor={step.status === 'pending'}
      backgroundColor={isCurrent ? 'blue' : undefined}
      paddingX={1}
    >
      {text}
    </Box>
  )
}

// The band above the prompt. Full mode: the label, a plain sentence of what to do now, the six
// phases as chips, big action buttons on the right (1, 2, 3, override on 9, more on 0), and a
// field for the override reason. Minimal draws the chips only. Off draws nothing (the caller
// passes next(e)).
export type GameButton = { show: boolean; open: boolean }

export function renderBand(
  kit: Kit,
  view: View,
  mode: UiMode,
  onAction: OnAction,
  onReason: OnReason,
  columns = 120,
  game: GameButton = { show: false, open: false },
): RenderElement | null {
  const style = phaseBarStyle(mode)
  if (style === 'none' || view.phase === null) return null
  const { Box, Text, Button, Input } = kit
  const compact = columns < COMPACT_BELOW

  const chips = (
    <Box flexDirection="row" columnGap={compact ? 0 : 1} flexWrap="wrap">
      {view.steps.map(s => chip(kit, s, compact))}
    </Box>
  )

  if (style === 'phases-only' || view.actions === null) {
    return (
      <Box flexDirection="row" columnGap={1} alignItems="center" key="temper-band">
        <Text bold color="magenta">TEMPER</Text>
        {chips}
      </Box>
    )
  }

  const head = (
    <Box flexDirection="row" columnGap={1} key="row-head">
      <Text bold color="magenta">TEMPER</Text>
      <Text dimColor>{view.phase === 'done' ? 'Run done' : whereText(view)}</Text>
      {view.total > 0 ? <Text dimColor>{`· criteria ${view.passed} of ${view.total}`}</Text> : null}
      <Text dimColor={view.enforcement === 'on'} color={view.enforcement === 'on' ? undefined : 'yellow'}>{`· enforcement ${view.enforcement}`}</Text>
    </Box>
  )
  // The sentence is long enough to need two lines in a narrow band, so it wraps.
  const now = view.now ? <Text>{view.now}</Text> : null

  const { primary, override } = view.actions
  const size = compact ? 20 : 28
  const shown = (label: string) => (label.length > size ? `${label.slice(0, size - 1)}…` : label)
  const big = (id: string, key: string, label: string, onPress: () => void | Promise<void>, primaryLook: boolean) => (
    <Box key={`box-${id}`} borderStyle={compact ? undefined : 'round'} borderColor={primaryLook ? 'blue' : 'gray'} paddingX={compact ? 0 : 1} columnGap={1}>
      <Button key={`action-${id}`} label={shown(label)} hotkey={key} plain variant={primaryLook ? 'primary' : 'secondary'} onPress={onPress} />
    </Box>
  )
  const hasMore = view.actions.more.length > 0
  const buttons = [
    ...primary.map((a, i) => big(a.id, a.key, a.label, () => onAction(a), i === 0)),
    big(override.id, override.key, override.label, () => onAction(override), false),
    // 0 is drawn only when the phase has extra actions to show.
    ...(hasMore
      ? [big('more', '0', view.expanded ? 'Fewer' : 'More', () => onAction({ key: '0', id: compact ? 'more-narrow' : 'more', label: 'More', desc: 'Show the other actions.', command: 'pane' }), false)]
      : []),
  ]
  // The game offer: a normal secondary button like 2 and 3, drawn only while Claude works and only
  // when the game setting is on. Its key is the digit 8, because only a digit works from an empty
  // prompt (a letter would type into the composer).
  const play = game.show
    ? big('play', '8', game.open ? 'Close the game' : compact ? 'Play' : 'Play while you wait', () => onAction({ key: 'a', id: 'play', label: 'Play', desc: 'Play a small game.', command: 'play' }), false)
    : null

  // With the full list on and no docked pane to hold it (a narrow band, or no pane), the extra
  // actions show in a third row.
  const extras =
    view.expanded && (compact || !view.paneOpen)
      ? view.actions.more.map(a => (
          <Box key={`box-${a.id}`} paddingX={compact ? 0 : 1} columnGap={1}>
            <Button key={`action-${a.id}`} label={shown(a.label)} hotkey={a.key} plain dimColor onPress={() => onAction(a)} />
          </Box>
        ))
      : null

  return (
    <Box flexDirection="column" key="temper-band">
      {head}
      {now}
      <Box flexDirection="row" justifyContent="space-between" flexWrap="wrap">
        {chips}
        <Box flexDirection="row" columnGap={compact ? 1 : 0} flexWrap="wrap">{buttons}{play}</Box>
      </Box>
      {extras ? <Box flexDirection="row" flexWrap="wrap" columnGap={compact ? 1 : 0}>{extras}</Box> : null}
      {Input ? <Input key={REASON_KEY} placeholder="type a reason" submitLabel="skip" onSubmit={value => onReason(value)} /> : null}
      <Text dimColor>{REASON_HINT}</Text>
    </Box>
  )
}
