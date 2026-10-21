// The only elements the mod draws with: Box, Text and Markdown. The band and the pane need no other, and no button.
import type { Elements } from 'claude-code'

export type Kit = Pick<Elements['terminal'], 'Box' | 'Text' | 'Markdown'>
