// Shared test builders. Not a test file: `claude plugin test` only runs *.test.ts(x).
import type { Move } from '../../hooks/temper-mod/core/decisions'
import { evaluate } from '../../hooks/temper-mod/core/rules'
import type { RuleContext, RuleResult, RunFacts, ToolCall } from '../../hooks/temper-mod/core/rules'
import type { Stage } from '../../hooks/temper-mod/core/stages'

// The CLI's facts for a run at `stage` (ADR 0012). The older tests name the stage after a failed check `fix` and the
// stage after the last gate `done`: those are Check and the commit stage of the CLI.
// `paused`: the person saved the run for later at this step (Save for later): ctxOf turns it into that move.
export type TestFacts = RunFacts & { paused?: boolean }

type OldVerdicts = Record<string, { verdict: 'PASS' | 'FAIL'; ts?: number } | undefined>
type OldDraft = { type: string; [other: string]: unknown }

// Also takes the form the older tests use: a list of drafts (a `pause` draft means the run is saved for later) and the
// verdicts as the old fold read them ({ build: { verdict: 'PASS', ts } }).
export function stateAt(stage: Stage | 'fix' | 'done', over: Partial<TestFacts> | OldDraft[] = {}, verdicts: OldVerdicts = {}): TestFacts {
  const s: Stage = stage === 'fix' ? 'check' : stage === 'done' ? 'commit' : stage
  const extra: Partial<TestFacts> = Array.isArray(over) ? (over.some(d => d.type === 'pause') ? { paused: true } : {}) : over
  const v: RunFacts['verdicts'] = { ...(extra.verdicts ?? {}) }
  for (const [k, row] of Object.entries(verdicts)) if (row) v[(k === 'fix' ? 'check' : k) as Stage] = row.verdict
  return {
    stage: s,
    step: 3,
    runMode: 'interactive',
    complexity: null,
    designRequired: false,
    designSeen: false,
    autonomyEnabled: false,
    groupedActive: false,
    skipped: new Set(),
    specDir: '.temper/specs/pw',
    planFiles: [],
    ...extra,
    verdicts: v,
  }
}

// A decision of the person as the older tests wrote one: its kind and the stage (or finding) it was made for.
export type OldDecision = { id: string; kind: string; phase?: string; findingId?: string }

// The context the older tests pass to the guard. The pool of decisions maps onto the person's move at the step (the
// last one that is a move), the accepted findings and Start over. Fields of the old guard that are gone are ignored.
export type OldCtx = {
  specDir?: string
  planFiles?: readonly string[]
  humanDecisions?: readonly OldDecision[]
  autonomyEnabled?: boolean
  autonomous?: boolean
  groupedActive?: boolean
  complexity?: string | null
  designRequired?: boolean
  cwd?: string | null
  cli?: string
  root?: string
  nothingToLose?: boolean
  // The person's Scope drift answers in this run.
  drift?: { added: string[]; allowOnce: Array<{ id: string; path: string }> }
  [other: string]: unknown
}

const at = { run: 'r', step: 3 }
const stamp = (id: string, stage: Stage) => ({ id, ...at, stage, ts: 1 })

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
          complexity: old.complexity !== undefined ? old.complexity : state.complexity,
          designRequired: old.designRequired ?? state.designRequired,
          autonomyEnabled: old.autonomyEnabled ?? old.autonomous ?? state.autonomyEnabled,
          runMode: old.autonomous ? 'autonomous' : state.runMode,
        }
  const stage = run?.stage ?? 'intent'
  let move: Move | null = (state as TestFacts | null)?.paused ? { ...stamp('pause', stage), kind: 'pause', reason: '' } : null
  const accepts: string[] = []
  let restart = false
  // A decision the older tests made for another stage than the run is at belongs to another step (ADR 0012): it does not
  // count. A step back names its target, not its step.
  const here = (p: string | undefined): boolean => p === undefined || (p === 'fix' ? 'check' : p === 'done' ? 'commit' : p) === stage || p === 'commit' || p === 'foreign-commit'
  for (const d of old.humanDecisions ?? []) {
    if ((d.kind === 'advance' || d.kind === 'override') && !here(d.phase)) continue
    if (d.kind === 'accept') accepts.push(d.findingId ?? '')
    else if (d.kind === 'restart') restart = true
    else if (d.kind === 'advance') move = { ...stamp(d.id, stage), kind: d.phase === 'intent' || d.phase === 'plan' || d.phase === undefined ? 'approve' : 'advance', reason: '' }
    else if (d.kind === 'back') move = { ...stamp(d.id, stage), kind: 'back', reason: 'r', to: (d.phase === 'fix' ? 'check' : (d.phase ?? 'build')) as Stage }
    else if (d.kind === 'override') {
      const kind = d.phase === 'commit' ? 'commitOverride' : d.phase === 'foreign-commit' ? 'keep' : 'override'
      move = { ...stamp(d.id, stage), kind, reason: 'r' }
    }
  }
  return {
    run,
    move,
    accepts,
    restart,
    drift: old.drift ?? { added: [], allowOnce: [] },
    ...(old.root !== undefined ? { root: old.root } : {}),
    ...(old.cwd !== undefined ? { cwd: old.cwd } : {}),
    ...(old.cli !== undefined ? { cli: old.cli } : {}),
    ...(old.nothingToLose !== undefined ? { nothingToLose: old.nothingToLose } : {}),
  }
}

// The guard, called the way the older tests call it: the run's facts, the old context, the call.
export function check(state: RunFacts | null, old: OldCtx, call: ToolCall): RuleResult {
  return evaluate(ctxOf(state, old), call)
}
