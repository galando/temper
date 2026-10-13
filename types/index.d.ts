// $.state contract for the Temper mod. Each value the module keeps in $.state is
// declared here under the plugin name; `claude plugin validate` holds the module to it.
// The view types repeat the shapes the module defines for its run view, on purpose: the
// validator reads this file alone, so it cannot import them. TypeScript checks the two
// agree wherever the module writes the value. The view only shows the run: no decision
// is made from it (ADR 0012).

export type StageName = 'intent' | 'plan' | 'design' | 'build' | 'review' | 'check' | 'commit'

export type UiMode = 'full' | 'minimal' | 'off'

export type TemperTask = { n: number; title: string; state: 'waiting' | 'running' | 'passed' | 'failed' | 'parked'; model: string | null; attempt: number | null }

export type TemperView = {
  title: string | null
  stage: StageName | null
  enforcement: 'on' | 'off'
  stages: Array<{ id: StageName; label: string; mark: 'passed' | 'failed' | 'skipped' | 'current' | 'pending'; failed: boolean; skip: string | null }>
  wait: 'gate' | 'chosen' | 'saved' | 'work' | 'armed' | 'done' | null
  status: string
  detail: string[]
  failedChecks: Array<{ name: string; pass: boolean; detail: string }>
  groups: Array<{ id: string; title: string; state: 'waiting' | 'running' | 'passed' | 'parked'; tasks: TemperTask[] }> | null
  findings: Array<{ id: string; severity: string; claim: string }>
  criteria: Array<{ id: string; text: string; status: 'passed' | 'open'; priority: string }>
  passed: number
  total: number
  task: { n: number; of: number } | null
  decisions: string[]
  loops: string[]
  line: string | null
  configSuggestions: boolean
  paneOpen: boolean
}

export type TemperRun = {
  slug: string | null
  stage: StageName | null
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
    temper: { run: TemperRun | null; mode: UiMode | null; game: TemperGame | null; root: string | null }
  }
}
