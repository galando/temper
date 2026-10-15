// Shared test builders. Not a test file: `claude plugin test` only runs *.test.ts(x).
import { evaluate } from '../../hooks/temper-mod/core/rules'
import type { RuleContext, RuleResult, RunFacts, ToolCall } from '../../hooks/temper-mod/core/rules'
import type { Stage } from '../../hooks/temper-mod/core/stages'

// The run as view.json gives it to the guard, at `stage`. The older tests name the stage after a failed check `fix` and
// the stage after the last gate `done`: those are Check and the commit stage of the CLI. `paused`: the person saved
// the run for later at this step (Save for later lifts no rule).
export type TestFacts = RunFacts & { paused?: boolean }

type OldDraft = { type: string; [other: string]: unknown }

export function stateAt(stage: Stage | 'fix' | 'done', over: Partial<TestFacts> | OldDraft[] = {}, _verdicts: Record<string, unknown> = {}): TestFacts {
  const s: Stage = stage === 'fix' ? 'check' : stage === 'done' ? 'commit' : stage
  const extra: Partial<TestFacts> = Array.isArray(over) ? (over.some(d => d.type === 'pause') ? { paused: true } : {}) : over
  return { stage: s, step: 3, specDir: '.temper/specs/pw', planFiles: [], groupedActive: false, trivialExit: false, ...extra }
}

// A decision of the person as the older tests wrote one: its kind and the stage (or finding) it was made for.
export type OldDecision = { id: string; kind: string; phase?: string; findingId?: string }

// The context the older tests pass to the guard. Their decisions become the calls the person's answer maps to, as the
// CLI writes them in the question's options (ADR 0013).
export type OldCtx = {
  specDir?: string
  planFiles?: readonly string[]
  humanDecisions?: readonly OldDecision[]
  // An armed run: its own loop back to Build after a failed Review or Check is the CLI's action.
  autonomous?: boolean
  groupedActive?: boolean
  cli?: string
  root?: string
  // A run that never left Intent (view.json's trivial_exit).
  nothingToLose?: boolean
  // The calls the person's answer (or the CLI's own action) maps to, as written.
  allowed?: readonly string[]
  fixRun?: boolean
  // The person's Scope drift answers in this run.
  drift?: { added: string[]; allowOnce: Array<{ id: string; path: string }> }
  [other: string]: unknown
}

const C = 'scripts/temper'
const NEXT: Record<string, string[]> = { intent: ['plan'], plan: ['build', 'design'], design: ['build'], build: ['review'], review: ['check'], check: ['commit'] }
const norm = (p: string | undefined): string | undefined => (p === 'fix' ? 'check' : p === 'done' ? 'commit' : p)

// The calls an older decision stands for, at the stage the run is at.
function callsOf(d: OldDecision, here: Stage): string[] {
  const phase = norm(d.phase)
  switch (d.kind) {
    case 'advance':
      if (phase !== undefined && phase !== here) return []
      return [`${C} intent accept`, ...(NEXT[here] ?? []).map(n => `${C} state advance ${here}_complete ${n}`)]
    case 'override':
      if (phase === 'commit') return ['intent', 'plan', 'design', 'build', 'review', 'check'].map(s => `${C} override ${s} --reason "{reason}"`).concat(`${C} gate commit`)
      if (phase === 'foreign-commit') return [`${C} group reopen {group} --accept-foreign {sha} --reason "{reason}"`]
      if (phase !== undefined && phase !== here) return []
      return [`${C} override ${here} --reason "{reason}"`, ...(NEXT[here] ?? []).map(n => `${C} state advance ${here}_complete ${n}`)]
    case 'back':
      return [`${C} state loop ${here} ${phase ?? 'build'} --reason "{reason}"`, `${C} state set next_stage ${phase ?? 'build'}`]
    case 'accept':
      return [`${C} evidence accept --stage review --id ${d.findingId ?? ''} --reason "{reason}"`, `${C} gate review`]
    case 'arm':
      return [`${C} state set run_mode autonomous`, `${C} state advance plan_complete build`]
    default:
      return []
  }
}

export function ctxOf(state: RunFacts | null, old: OldCtx = {}): RuleContext {
  const { paused: _paused, ...facts } = (state ?? { paused: false }) as TestFacts
  const run: RunFacts | null =
    state === null
      ? null
      : {
          ...(facts as RunFacts),
          specDir: old.specDir ?? state.specDir,
          planFiles: old.planFiles ?? state.planFiles,
          groupedActive: old.groupedActive ?? state.groupedActive,
          trivialExit: old.nothingToLose ?? state.trivialExit,
        }
  const here = run?.stage ?? 'intent'
  const allowed = [...(old.allowed ?? [])]
  let restart = false
  for (const d of old.humanDecisions ?? []) {
    if (d.kind === 'restart') restart = true
    else allowed.push(...callsOf(d, here))
  }
  if (old.autonomous) allowed.push(`${C} state loop review build --reason "{reason}"`, `${C} state loop check build --reason "{reason}"`)
  return {
    run,
    allowed,
    restart,
    drift: old.drift ?? { added: [], allowOnce: [] },
    ...(old.root !== undefined ? { root: old.root } : {}),
    ...(old.cli !== undefined ? { cli: old.cli } : {}),
    ...(old.fixRun !== undefined ? { fixRun: old.fixRun } : {}),
  }
}

// The guard, called the way the older tests call it: the run's facts, the old context, the call.
export function check(state: RunFacts | null, old: OldCtx, call: ToolCall): RuleResult {
  return evaluate(ctxOf(state, old), call)
}
