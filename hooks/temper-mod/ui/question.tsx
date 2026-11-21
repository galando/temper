import type { RenderElement } from 'claude-code'

import type { Card } from '../core/runview'
import { questionHeader } from '../core/view'
import type { View } from '../core/view'
import type { Kit } from './kit'

// Above the engine's own dialog, which is held exactly once (its drawing is `engine`, the element `next(e)`
// answered): the one dim line, then (WP15) the card of a question that decides, as the CLI made it: its title and
// tag, each section's title and note, its rows with their marks, what a cut section leaves out, and the foot. The card
// only shows: the person decides in the dialog. `card` is the view's own unless the caller gives one (null: none).
export function renderQuestion(kit: Kit, view: View, engine: RenderElement, card: Card | null = view.card ?? null): RenderElement | null {
  const header = questionHeader(view)
  if (header === null && card === null) return null
  const { Box, Text } = kit
  const rowText = (text: string, mark: string | null) => (mark ? `${text}  [${mark}]` : text)
  return (
    <Box flexDirection="column">
      {header !== null ? <Text dimColor>{header}</Text> : null}
      {card !== null ? (
        <Box flexDirection="column" marginBottom={1}>
          <Text bold>{card.tag ? `${card.title}  ${card.tag}` : card.title}</Text>
          {card.sections.map(s => (
            <Box key={s.id} flexDirection="column">
              <Text bold>{s.note ? `${s.title} (${s.note})` : s.title}</Text>
              {s.rows.map((r, i) => (
                <Text key={`${s.id}-${i}`}>{` ${rowText(r.text, r.mark)}`}</Text>
              ))}
              {s.total > s.rows.length ? <Text dimColor>{` and ${s.total - s.rows.length} more: ${s.file ?? "the run's files"}`}</Text> : null}
            </Box>
          ))}
          {card.foot.length > 0 ? <Text dimColor>{card.foot.join(' ')}</Text> : null}
        </Box>
      ) : null}
      {engine}
    </Box>
  )
}
