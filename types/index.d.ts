// $.state contract for the Temper mod. Each value the module keeps in $.state is
// declared here under the plugin name; `claude plugin validate` holds the module to it.

export type PhaseName = 'intent' | 'plan' | 'build' | 'review' | 'check' | 'fix'

export type UiMode = 'full' | 'minimal' | 'off'

export type TemperRun = {
  slug: string | null
  phase: PhaseName | 'done' | null
  title: string | null
  summary: string
}

declare module 'claude-code' {
  interface PluginState {
    temper: { run: TemperRun | null; mode: UiMode | null }
  }
}
