// Interaction modes. The one table that says what each uiMode draws (ADR 0012): the mode sets only how much is drawn,
// never how a decision is made. Refusals and the /temper:temper words work in every mode; enforcement is a separate
// switch.

import type { UiMode } from './config'

export type Element = 'denials' | 'stages' | 'details' | 'pane' | 'toasts' | 'hint' | 'spinner' | 'turnLine' | 'questionHeader' | 'subcommands'

const ALWAYS: readonly Element[] = ['denials', 'subcommands']

const BY_MODE: Record<UiMode, readonly Element[]> = {
  // The bar with the stage timeline and the details of the stage, the pane, and the lines around the prompt.
  full: ['stages', 'details', 'pane', 'toasts', 'hint', 'spinner', 'turnLine', 'questionHeader'],
  // The stage timeline only.
  minimal: ['stages'],
  off: [],
}

export function visible(mode: UiMode, element: Element): boolean {
  return ALWAYS.includes(element) || BY_MODE[mode].includes(element)
}

export type BarStyle = 'full' | 'stages' | 'none'

export function barStyle(mode: UiMode): BarStyle {
  if (!visible(mode, 'stages')) return 'none'
  return visible(mode, 'details') ? 'full' : 'stages'
}
