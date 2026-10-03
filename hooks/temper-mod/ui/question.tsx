import type { RenderElement } from 'claude-code'

import { questionHeader } from '../core/view'
import type { View } from '../core/view'
import type { Kit } from './kit'

// One dim line above the engine's own dialog, which is held exactly once: its drawing
// is `engine`, the element `next(e)` answered.
export function renderQuestion(kit: Kit, view: View, engine: RenderElement): RenderElement | null {
  const header = questionHeader(view)
  if (header === null) return null
  const { Box, Text } = kit
  return (
    <Box flexDirection="column">
      <Text dimColor>{header}</Text>
      {engine}
    </Box>
  )
}
