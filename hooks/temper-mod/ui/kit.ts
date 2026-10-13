// The only elements the mod draws with: Box, Text, Button and Markdown. The band and the pane need no other.
import type { Elements } from 'claude-code'

export type Kit = Pick<Elements['terminal'], 'Box' | 'Text' | 'Button' | 'Markdown'>
