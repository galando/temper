// The stages of a run, as the CLI names them (STAGE_SEQ_TEMPER in scripts/temper, then commit). The mod has no
// stages of its own: where a run is comes from view.json alone (ADR 0013). Pure.

export const STAGES = ['intent', 'plan', 'design', 'build', 'review', 'check', 'commit'] as const
export type Stage = (typeof STAGES)[number]

export const isStage = (s: string): s is Stage => (STAGES as readonly string[]).includes(s)

export const stageIndex = (s: Stage): number => STAGES.indexOf(s)

const LABEL: Record<Stage, string> = {
  intent: 'Intent',
  plan: 'Plan',
  design: 'Design',
  build: 'Build',
  review: 'Review',
  check: 'Check',
  commit: 'Commit',
}

export const stageLabel = (s: Stage): string => LABEL[s]

// Where the CLI says a /temper run is. `done` is the commit stage. Null for a name that is no stage
// of a /temper run (a /temper:fix run has rca and fix; the mod stands aside for it), or none: the mod cannot tell then.
export function cliStage(next: string | null): Stage | null {
  if (next === 'done') return 'commit'
  return next !== null && isStage(next) ? next : null
}
