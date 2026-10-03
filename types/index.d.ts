// $.state contract for the Temper mod. Each value the module keeps in $.state is
// declared here under the plugin name; `claude plugin validate` holds the module to it.
// The view types repeat the shapes of hooks/temper-mod/core/view.ts and actions.ts on
// purpose: the validator reads this file alone, so it cannot import them. TypeScript
// checks the two agree wherever the module writes the value.

export type PhaseName = 'intent' | 'plan' | 'build' | 'review' | 'check' | 'fix'

export type UiMode = 'full' | 'minimal' | 'off'

export type TemperAction = {
  key: '1' | '2' | '3' | '9' | '0' | 'a' | 'b' | 'c' | 'd' | 'e' | 'f' | 'g' | 'h'
  id: string
  label: string
  prompt?: string
  command?: string
  asksReason?: boolean
}

export type TemperView = {
  title: string | null
  phase: PhaseName | 'done' | null
  stepNo: number | null
  paused: boolean
  enforcement: 'on' | 'off'
  steps: Array<{ id: PhaseName; label: string; status: 'done' | 'current' | 'pending' | 'stale' }>
  actions: { primary: TemperAction[]; override: TemperAction; more: TemperAction[] } | null
  expanded: boolean
  paneOpen: boolean
  criteria: Array<{ id: string; text: string; status: 'passed' | 'open'; priority: string }>
  passed: number
  total: number
  findings: Array<{ id: string; severity: string; claim: string }>
  timeline: string[]
  now: string
  task: { n: number; of: number } | null
  loopLimitReached: boolean
}

export type TemperRun = {
  slug: string | null
  phase: PhaseName | 'done' | null
  title: string | null
  summary: string
  // Everything the band, pane, spinner, hint and question header draw.
  view: TemperView
}

declare module 'claude-code' {
  interface PluginState {
    temper: { run: TemperRun | null; mode: UiMode | null }
  }
}
