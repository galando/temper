// Deny rules: `evaluate(state, ctx, toolCall)` answers allow or deny for one tool call.
// Pure. Every deny reason ends with what to do next (mods-plan 3.4).

import { classifyBash, protectedKind } from './bash'
import type { DecisionKind, ProtectedKind } from './bash'
import type { Phase } from './events'
import { ONLY_USER, phaseLabel } from './machine'
import type { RunState } from './machine'
import { guardedPhase } from './cli'
import { matchesPlan, normalizePath } from './paths'

// A decision the person made that no CLI call has matched yet: the event id, its kind, and
// the phase (or finding id) it was made for.
export type HumanDecision = { id: string; kind: DecisionKind; phase?: string; findingId?: string }

export type RuleContext = {
  // Absolute project root; absolute tool paths inside it are made relative.
  root?: string
  // The spec directory, relative to the root: `.temper/specs/{slug}`.
  specDir: string
  // File entries from plan.md and tasks.md (exact paths, `dir/` prefixes or globs).
  planFiles: readonly string[]
  // Human decision events not yet matched by a CLI call.
  humanDecisions?: readonly HumanDecision[]
  // `autonomy.enabled: true` in .claude/temper.config: the person has opted in to autonomous runs.
  autonomyEnabled?: boolean
  // Files a Fix finding action is currently active for (Review phase writes).
  fixFiles?: readonly string[]
}

export type ToolCall = { tool: string; input: Record<string, unknown> }

export type RuleResult =
  | { allow: true; consume?: DecisionKind | 'drift'; driftPath?: string; eventId?: string; eventIds?: string[] }
  | { deny: string; drift?: string }

const ALLOW: RuleResult = { allow: true }
const WRITE_TOOLS = new Set(['Write', 'Edit', 'MultiEdit', 'NotebookEdit'])

const TEST_FILE = [/(^|\/)(?:tests?|__tests__|specs?)\//, /\.(?:test|spec)\.[^/]+$/, /(^|\/)test_[^/]*$/, /_test\.[^/]+$/]

export const isTestFile = (path: string): boolean => TEST_FILE.some(re => re.test(path))

function targetPath(call: ToolCall): string | null {
  const raw = call.tool === 'NotebookEdit' ? call.input.notebook_path : call.input.file_path
  return typeof raw === 'string' && raw.length > 0 ? raw : null
}

const inDir = (path: string, dir: string): boolean => path === dir || path.startsWith(dir + '/')

function protectedDeny(kind: ProtectedKind): RuleResult {
  if (kind === 'events' || kind === 'overrides') return { deny: ONLY_USER }
  if (kind === 'folder') {
    return {
      deny:
        'Temper: the .temper folders hold the run, its verdicts and its decisions, and are not removed or replaced by hand. ' +
        'Next: use scripts/temper state archive after the run, or name the single file you mean.',
    }
  }
  if (kind === 'state') {
    return {
      deny:
        'Temper: run state is changed with the temper CLI and never written by hand. ' +
        'Next: use scripts/temper state set or scripts/temper state advance.',
    }
  }
  return {
    deny:
      'Temper: gate verdicts are computed by the temper CLI and never written by hand. ' +
      'Next: run scripts/temper gate <stage> and read the verdict it records.',
  }
}

const COMMIT_NEXT: Record<Phase, string> = {
  intent: 'finish the intent and move through the phases to Check (key 1 or /temper:temper next)',
  plan: 'finish the plan and move through the phases to Check (key 1 or /temper:temper next)',
  build: 'finish the build and move on to Review and Check (key 1 or /temper:temper next)',
  review: 'finish the review and move on to Check (key 1 or /temper:temper next)',
  check: 'run the checks (key 1 in Check or /temper:check)',
  fix: 'fix the failures, then rerun the checks (key 1 in Fix)',
}

const isActive = (s: RunState): s is RunState & { phase: Phase } => s.phase !== null && s.phase !== 'done'

function phaseWriteRule(s: RunState & { phase: Phase }, ctx: RuleContext, path: string): RuleResult {
  const spec = normalizePath(ctx.specDir)
  const inSpec = inDir(path, spec)
  const specFile = (name: string) => path === `${spec}/${name}`
  const label = phaseLabel(s.phase)

  switch (s.phase) {
    case 'intent':
      if (specFile('intent.md') || specFile('intent-context.json')) return ALLOW
      return {
        deny:
          `Temper: ${label} phase. Writing ${path} is not allowed until the intent is approved. ` +
          'Next: finish intent.md, then ask the user to approve (key 1 or /temper:temper approve).',
      }
    case 'plan': {
      const ok =
        ['intent.md', 'plan.md', 'tasks.md', 'design.md', 'config-suggestions.json'].some(specFile) ||
        (inSpec && /-context\.json$/.test(path)) ||
        (path.startsWith('docs/decisions/') && path.endsWith('.md'))
      if (ok) return ALLOW
      return {
        deny:
          `Temper: ${label} phase. Writing ${path} is not allowed until the plan is approved. ` +
          'Next: finish plan.md and tasks.md, then ask the user to approve (key 1 or /temper:temper approve).',
      }
    }
    case 'review':
      if (inSpec || (ctx.fixFiles ?? []).some(f => normalizePath(f, ctx.root) === path)) return ALLOW
      return {
        deny:
          `Temper: ${label} phase. Writing ${path} is not allowed; Review only changes the spec directory. ` +
          'Next: record the finding, then fix it once the user starts Fix (key 1 in Review, Fix all).',
      }
    case 'check':
      if (inSpec) return ALLOW
      return {
        deny:
          `Temper: ${label} phase. Writing ${path} is not allowed; Check only runs validation. ` +
          'Next: run the checks (key 1 in Check or /temper:check).',
      }
    case 'build':
    case 'fix': {
      if (inSpec || isTestFile(path) || matchesPlan(path, ctx.planFiles) || s.addedPaths.some(p => normalizePath(p) === path)) {
        return ALLOW
      }
      if (s.allowOnce.some(p => normalizePath(p) === path)) return { allow: true, consume: 'drift', driftPath: path }
      return {
        deny:
          `Temper: scope drift. ${path} is not in the plan. ` +
          'Next: ask the user to choose: add to plan, revert, or allow once with a reason ' +
          '(/temper:temper drift add|revert|allow <reason>).',
        drift: path,
      }
    }
  }
}

// The CLI has no Fix stage: a decision made in Fix is a decision about the Check stage.
const stageName = (p: string): string => (p === 'fix' ? 'check' : p)

// The Plan was approved by the person in this run: a trusted advance out of Plan, not undone by a
// later back step to Intent or Plan. Untrusted event files never reach the state, so they never count.
const planApproved = (s: RunState): boolean => {
  let approved = false
  for (const h of s.history) {
    if (h.kind === 'advance' && h.from === 'plan') approved = true
    if (h.kind === 'back' && (h.to === 'intent' || h.to === 'plan')) approved = false
  }
  return approved
}

const AUTONOMY_DENY =
  'Temper: autonomous mode is armed by the user at the plan gate. ' +
  'Next: ask the user to approve the plan (key 1 or /temper:temper approve) and to set autonomy.enabled: true in .claude/temper.config, then try again.'

const GUARD_KEYS = new Set(['stage', 'next_stage', 'branch', 'spec_path', 'run_mode'])

const UNCHECKABLE =
  'Temper: this command writes through a path that cannot be checked, and it names Temper state. ' +
  'Next: spell the exact file path with no variables, globs, braces or substitutions, or use ' +
  'scripts/temper gate <stage>, scripts/temper evidence or scripts/temper state.'

const REPEATED_FLAG =
  'Temper: this decision call repeats a flag (--id, --stage or --reason), so it cannot be matched to ' +
  'what the person decided. Next: run it once with each flag given a single time.'

const STATE_END =
  'Temper: clearing or archiving the run state is for after the run. Next: finish the run (Check passes), ' +
  'commit, then run scripts/temper state archive.'

const stateSetDeny = (key: string): string =>
  `Temper: state set ${key} moves the run, and only the user can do that. ` +
  'Next: ask the user to run /temper:temper back <phase> <reason>.'

function evaluateBash(s: RunState, ctx: RuleContext, command: string): RuleResult {
  const c = classifyBash(command)

  if (c.protectedWrites.length > 0) {
    const known = c.protectedWrites.filter(p => !c.uncheckable.includes(p))
    if (known.length === 0) return { deny: UNCHECKABLE }
    const kinds = known.map(p => protectedKind(p) ?? 'events')
    const forged = kinds.find(k => k === 'events' || k === 'overrides')
    return protectedDeny(forged ?? kinds[0] ?? 'events')
  }

  // Removing or archiving the run's state is for after the run: while a run is active it would
  // take the gate ledger and the overrides with it.
  if (isActive(s) && c.stateOps.some(o => o.op === 'clear' || o.op === 'archive')) return { deny: STATE_END }

  if (isActive(s)) {
    if (c.calls.some(call => call.invalid)) return { deny: REPEATED_FLAG }
    for (const op of c.stateOps) {
      // Keys that move the run. next_stage is matched to the person's back decision below.
      if (op.op === 'set' && op.key === 'run_mode' && op.value === 'autonomous') {
        // Armed only after the person approved the Plan, and only where autonomy is switched on.
        if (!(planApproved(s) && ctx.autonomyEnabled === true)) return { deny: AUTONOMY_DENY }
        continue
      }
      if (op.op === 'set' && GUARD_KEYS.has(op.key) && op.key !== 'next_stage' && !(op.key === 'run_mode' && op.value === 'interactive')) {
        return { deny: stateSetDeny(op.key) }
      }
    }
    // Each guarded CLI call needs its own unconsumed human decision made for that phase (and
    // that finding, when the call names one).
    const pool = [...(ctx.humanDecisions ?? [])]
    let first: { kind: DecisionKind; eventId: string } | null = null
    const matched: string[] = []
    for (const call of c.calls) {
      // An advance needs a person only when it leaves Intent or Plan (`intent_complete`,
      // `plan_complete`); the phase it names is the phase the person approved, whatever phase the
      // run is in by now. Later advances follow a verdict and are not guarded.
      const approved = call.kind === 'advance' ? (call.stage === undefined ? (s.phase === 'intent' || s.phase === 'plan' ? s.phase : null) : guardedPhase(call.stage)) : null
      if (call.kind === 'advance' && approved === null) continue
      const i = pool.findIndex(
        h =>
          h.kind === call.kind &&
          (call.kind === 'accept' || (call.kind === 'advance' ? h.phase === undefined || h.phase === approved : call.stage === undefined || h.phase === undefined || stageName(h.phase) === stageName(call.stage))) &&
          (call.id === undefined || h.findingId === undefined || h.findingId === call.id),
      )
      const hit = i >= 0 ? pool[i] : undefined
      if (!hit) return { deny: ONLY_USER }
      pool.splice(i, 1)
      matched.push(hit.id)
      first ??= { kind: call.kind, eventId: hit.id }
    }
    if (first && !(c.commits && !s.paused)) return { allow: true, consume: first.kind, eventId: first.eventId, eventIds: matched }
  }

  if (c.commits && isActive(s) && !s.paused) {
    return {
      deny: `Temper: commit blocked, Check has not passed. Next: ${COMMIT_NEXT[s.phase]}.`,
    }
  }
  return ALLOW
}

export function evaluate(state: RunState, ctx: RuleContext, call: ToolCall): RuleResult {
  if (call.tool === 'Bash') {
    const command = typeof call.input.command === 'string' ? call.input.command : ''
    return evaluateBash(state, ctx, command)
  }
  if (!WRITE_TOOLS.has(call.tool)) return ALLOW

  const raw = targetPath(call)
  if (raw === null) return ALLOW
  const path = normalizePath(raw, ctx.root)

  const kind = protectedKind(path)
  if (kind !== null) return protectedDeny(kind)

  if (!isActive(state) || state.paused) return ALLOW
  return phaseWriteRule(state, ctx, path)
}
