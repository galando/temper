// Deny rules: `evaluate(state, ctx, toolCall)` answers allow or deny for one tool call.
// Pure. Every deny reason ends with what to do next (mods-plan 3.4).

import { classifyBash, protectedKind } from './bash'
import type { DecisionKind } from './bash'
import type { Phase } from './events'
import { ONLY_USER, phaseLabel } from './machine'
import type { RunState } from './machine'
import { matchesPlan, normalizePath } from './paths'

export type RuleContext = {
  // Absolute project root; absolute tool paths inside it are made relative.
  root?: string
  // The spec directory, relative to the root: `.temper/specs/{slug}`.
  specDir: string
  // File entries from plan.md and tasks.md (exact paths, `dir/` prefixes or globs).
  planFiles: readonly string[]
  // Human decision events not yet matched by a CLI call, per kind.
  humanDecisions?: Partial<Record<DecisionKind, number>>
  // Files a Fix finding action is currently active for (Review phase writes).
  fixFiles?: readonly string[]
}

export type ToolCall = { tool: string; input: Record<string, unknown> }

export type RuleResult =
  | { allow: true; consume?: DecisionKind | 'drift'; driftPath?: string }
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

function protectedDeny(kind: 'events' | 'gates' | 'status' | 'overrides'): RuleResult {
  if (kind === 'events' || kind === 'overrides') return { deny: ONLY_USER }
  return {
    deny:
      'Temper: gate verdicts are computed by the temper CLI and never written by hand. ' +
      'Next: run scripts/temper gate <stage> and read the verdict it records.',
  }
}

const COMMIT_NEXT: Record<Phase, string> = {
  intent: 'finish the intent and move through the phases to Check (key 1 or /temper next)',
  plan: 'finish the plan and move through the phases to Check (key 1 or /temper next)',
  build: 'finish the build and move on to Review and Check (key 1 or /temper next)',
  review: 'finish the review and move on to Check (key 1 or /temper next)',
  check: 'run the checks (key 1 in Check or /temper check)',
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
          'Next: finish intent.md, then ask the user to approve (key 1 or /temper approve).',
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
          'Next: finish plan.md and tasks.md, then ask the user to approve (key 1 or /temper approve).',
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
          'Next: run the checks (key 1 in Check or /temper check).',
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
          '(/temper drift add|revert|allow <reason>).',
        drift: path,
      }
    }
  }
}

function evaluateBash(s: RunState, ctx: RuleContext, command: string): RuleResult {
  const c = classifyBash(command)

  if (c.protectedWrites.length > 0) {
    const kinds = c.protectedWrites.map(p => protectedKind(p) ?? 'events')
    const forged = kinds.find(k => k === 'events' || k === 'overrides')
    return protectedDeny(forged ?? kinds[0] ?? 'events')
  }

  if (isActive(s)) {
    const guarded = c.decisions.filter(k => k !== 'advance' || s.phase === 'intent' || s.phase === 'plan')
    for (const kind of guarded) {
      if ((ctx.humanDecisions?.[kind] ?? 0) < 1) return { deny: ONLY_USER }
    }
    if (guarded.length > 0 && !(c.commits && !s.paused)) return { allow: true, consume: guarded[0] }
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
