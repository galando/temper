// $.state contract for the Temper mod. Each value the module keeps in $.state is
// declared here under the plugin name; `claude plugin validate` holds the module to it.
// The view types repeat the shapes of hooks/temper-mod/core/view.ts and actions.ts on
// purpose: the validator reads this file alone, so it cannot import them. TypeScript
// checks the two agree wherever the module writes the value.

export type PhaseName = 'intent' | 'plan' | 'build' | 'review' | 'check' | 'fix'

export type UiMode = 'full' | 'minimal' | 'off'

export type TemperAction = {
  key: '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9' | '0'
  id: string
  label: string
  short?: string
  desc: string
  prompt?: string
  command?: string
  asksReason?: boolean
  resume?: boolean
  fill?: string
}

export type TemperView = {
  title: string | null
  phase: PhaseName | 'done' | null
  stepNo: number | null
  paused: boolean
  enforcement: 'on' | 'off'
  steps: Array<{ id: PhaseName; label: string; status: 'done' | 'current' | 'pending' | 'stale' }>
  actions: { primary: TemperAction[]; discuss: TemperAction; override: TemperAction | null; more: TemperAction[] } | null
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

// The game, Temper Run: how many times each Button of the game pane was pressed. The drawing reads
// the counters as props, compares them with the values it saw last, and applies each new press once.
// Written on a key press only, never on a frame.
export type TemperGame = {
  jumpCount: number
  duckCount: number
  startCount: number
}

declare module 'claude-code' {
  interface PluginState {
    temper: { run: TemperRun | null; mode: UiMode | null; game: TemperGame | null }
  }
}
