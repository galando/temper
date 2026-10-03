// Interaction modes (mods-plan 3.8). The one table that says what each uiMode draws.
// Denials and /temper subcommands work in every mode; enforcement is a separate switch.

import type { UiMode } from './config'

export type Element =
  | 'denials'
  | 'phaseBar'
  | 'actionButtons'
  | 'pane'
  | 'toasts'
  | 'suggestions'
  | 'hint'
  | 'spinner'
  | 'turnLine'
  | 'questionHeader'
  | 'subcommands'

const ALWAYS: readonly Element[] = ['denials', 'subcommands']

const BY_MODE: Record<UiMode, readonly Element[]> = {
  full: ['phaseBar', 'actionButtons', 'pane', 'toasts', 'suggestions', 'hint', 'spinner', 'turnLine', 'questionHeader'],
  // Phases only: the bar without action buttons; nothing else is drawn.
  minimal: ['phaseBar'],
  off: [],
}

export function visible(mode: UiMode, element: Element): boolean {
  return ALWAYS.includes(element) || BY_MODE[mode].includes(element)
}

export type PhaseBarStyle = 'phases-and-actions' | 'phases-only' | 'none'

export function phaseBarStyle(mode: UiMode): PhaseBarStyle {
  if (!visible(mode, 'phaseBar')) return 'none'
  return visible(mode, 'actionButtons') ? 'phases-and-actions' : 'phases-only'
}
