// The stages of a run, as the CLI names them (STAGE_SEQ_TEMPER in scripts/temper, then commit). The mod has no
// stages of its own: where a run is comes from build-state.json's `next_stage` alone (ADR 0012). Pure.

export const STAGES = ['intent', 'plan', 'design', 'build', 'review', 'check', 'commit'] as const
export type Stage = (typeof STAGES)[number]

// The stages that have a gate verdict.
export const GATED: readonly Stage[] = ['intent', 'plan', 'design', 'build', 'review', 'check']

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

// Where the CLI says a /temper run is: its `next_stage`. `done` is the commit stage. Null for a name that is no stage
// of a /temper run (a /temper:fix run has rca and fix; the mod stands aside for it), or none: the mod cannot tell then.
export function cliStage(next: string | null): Stage | null {
  if (next === 'done') return 'commit'
  return next !== null && isStage(next) ? next : null
}

// Whether the run has a Design stage: a medium or complex run, with design switched on (or already designed).
export function hasDesign(complexity: string | null, designRequired: boolean, designSeen = false): boolean {
  return designSeen || ((complexity === 'medium' || complexity === 'complex') && designRequired)
}

// The stage after `s` in this run. Plan is followed by Design only when the run has one.
export function nextStage(s: Stage, design: boolean): Stage | null {
  switch (s) {
    case 'intent':
      return 'plan'
    case 'plan':
      return design ? 'design' : 'build'
    case 'design':
      return 'build'
    case 'build':
      return 'review'
    case 'review':
      return 'check'
    case 'check':
      return 'commit'
    case 'commit':
      return null
  }
}

// The stages a step back from `s` may go to: every earlier stage of the run, never the commit stage.
export function earlierStages(s: Stage, design: boolean): Stage[] {
  return STAGES.filter(x => x !== 'commit' && stageIndex(x) < stageIndex(s) && (x !== 'design' || design))
}
