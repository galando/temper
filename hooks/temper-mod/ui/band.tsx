import type { RenderElement } from 'claude-code'

import type { UiMode } from '../core/config'
import { phaseBarStyle } from '../core/modes'
import { MARK } from '../core/view'
import type { View } from '../core/view'
import type { Kit, OnAction } from './kit'

// The band above the prompt: the six phases, and in full mode up to three context
// actions (hotkeys 1, 2, 3), override (9) and all actions (0). Minimal draws the phases
// only; off draws nothing (the caller passes next(e)).
export function renderBand(kit: Kit, view: View, mode: UiMode, onAction: OnAction): RenderElement | null {
  const style = phaseBarStyle(mode)
  if (style === 'none' || view.phase === null) return null
  const { Box, Text, Button } = kit

  const bar = view.steps.map(step => (
    <Text key={`step-${step.id}`} bold={step.status === 'current'} dimColor={step.status === 'pending'}>
      {`${MARK[step.status]} ${step.label}  `}
    </Text>
  ))

  if (style === 'phases-only' || view.actions === null) {
    return (
      <Box flexDirection="row" key="temper-band">
        {bar}
      </Box>
    )
  }

  const { primary, override } = view.actions
  const buttons = [...primary, override].map(action => (
    <Button
      key={`action-${action.id}`}
      label={action.label}
      hotkey={action.key}
      plain
      onPress={() => onAction(action)}
    />
  ))
  return (
    <Box flexDirection="column" key="temper-band">
      <Box flexDirection="row">{bar}</Box>
      <Box flexDirection="row" columnGap={2}>
        {buttons}
        <Button
          key="action-more"
          label="All actions"
          hotkey="0"
          plain
          onPress={() => onAction({ key: '0', id: 'more', label: 'All actions', command: 'pane' })}
        />
      </Box>
    </Box>
  )
}
