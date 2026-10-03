// The only elements the mod draws with: Box, Text, Button, Input and Markdown. The band and
// the pane need no other (mods-plan 2.8).
import type { Elements } from 'claude-code'

import type { Action } from '../core/actions'

// Input is drawn on the terminal, the desktop and vscode but not on mobile; the band, the only
// site that uses it, is raised on terminal and desktop only.
export type Kit = Pick<Elements['terminal'], 'Box' | 'Text' | 'Button' | 'Markdown'> & Partial<Pick<Elements['terminal'], 'Input'>>

// The handlers return their work so a press waits for it (a Button that sends a prompt or
// records a decision has finished only when that has).
export type OnAction = (action: Action) => void | Promise<void>

// A per finding button in the pane: Fix, Accept with reason, Explain.
export type OnFinding = (kind: 'fix' | 'accept' | 'explain', findingId: string) => void | Promise<void>

// The reason typed into the band's field and submitted with Enter.
export type OnReason = (reason: string) => void | Promise<void>

export const REASON_KEY = 'override-reason'
