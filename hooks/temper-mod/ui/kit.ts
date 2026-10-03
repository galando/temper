// The only elements the mod draws with. Every drawing surface has all four, so no
// fallback is needed (mods-plan 2.8).
import type { Elements } from 'claude-code'

import type { Action } from '../core/actions'

export type Kit = Pick<Elements['terminal'], 'Box' | 'Text' | 'Button' | 'Markdown'>

// The handlers return their work so the press waits for it (a Button press that sends a prompt
// or records a decision has finished only when that has).
export type OnAction = (action: Action) => void | Promise<void>

// A per finding button in the pane: Fix, Accept with reason, Explain.
export type OnFinding = (kind: 'fix' | 'accept' | 'explain', findingId: string) => void | Promise<void>
