// $.state contract for the Temper mod. Each value the module keeps in $.state is
// declared here under the plugin name; `claude plugin validate` holds the module to it.
// The view types repeat the shapes the module defines for its run view, on purpose: the
// validator reads this file alone, so it cannot import them. TypeScript checks the two
// agree wherever the module writes the value. The view only shows the run: no decision
// is made from it (ADR 0013).

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
  failedChecks: Array<{ name: string; detail: string }>
  groups: Array<{ id: string; title: string; state: 'waiting' | 'running' | 'passed' | 'parked'; tasks: TemperTask[] }> | null
  findings: Array<{ id: string; severity: string; claim: string }>
  criteria: Array<{ id: string; text: string; status: 'passed' | 'open'; priority: string; evidence: string[] }>
  passed: number
  total: number
  clock: { minutes: number | null; tokens: number }
  loopMarks: Array<{ from: string; to: string; iteration: number; max: number; reason: string }>
  planTree: { approved: boolean; groups: Array<{ id: string; title: string; files: string[] }>; other: string[] } | null
  grid: Array<{ id: string; title: string; status: string; tasks: Array<{ n: number; title: string; state: 'waiting' | 'running' | 'red' | 'green' | 'pass' | 'fail' | 'parked'; model: string | null; retries: number }> }> | null
  findingRows: Array<{ id: number; severity: string; confidence: number | null; where: string | null; claim: string; state: 'open' | 'resolved' | 'accepted' }>
  markers: Array<{ name: string; state: 'pass' | 'fail' | 'info' | 'none'; detail: string; lines: string[] }>
  decisions: string[]
  loops: string[]
  line: string | null
  next: { action: string; say: string; header: string | null }
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

declare module 'claude-code' {
  interface PluginState {
    temper: { run: TemperRun | null; mode: UiMode | null; root: string | null }
  }
}
