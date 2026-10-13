// The view model (ADR 0012): what the bar, the pane, the spinner, the hint, the question header and the system prompt
// show, computed once from the CLI's files and the person's decisions, so each drawing is a plain function of plain
// data. It holds no button that decides: the person decides in the `Temper gate` question. Pure and JSON safe: it is
// mirrored into `$.state`, which survives reload and compaction.

import type { Finding, Gates, GroupRow, Loop, Requirement, Skips } from './clifiles'
import type { MergedCriterion } from './criteria'
import type { Decision, Move } from './decisions'
import { describe } from './decisions'
import type { RunFacts } from './rules'
import type { Stage } from './stages'
import { STAGES, hasDesign, nextStage, stageIndex, stageLabel } from './stages'

// How a stage stands on the timeline: its check passed, failed, or the person skipped it; the run is at it; or it is
// still to come.
export type Mark = 'passed' | 'failed' | 'skipped' | 'current' | 'pending'

export type StageView = { id: Stage; label: string; mark: Mark; failed: boolean; skip: string | null }

// What the run waits for at its current stage:
//  gate    the stage's check ran and no choice is made yet: the person answers the `Temper gate` question
//  chosen  the person chose; Claude carries it out
//  saved   the person saved the run for later
//  work    the stage is being worked (no verdict yet)
//  armed   an armed autonomous run goes on by itself
//  done    every gate is behind the run: Commit is next
export type Wait = 'gate' | 'chosen' | 'saved' | 'work' | 'armed' | 'done'

export type View = {
  title: string | null
  stage: Stage | null
  enforcement: 'on' | 'off'
  stages: StageView[]
  wait: Wait | null
  // One plain sentence: where the run is and what it waits for.
  status: string
  // The lines under it, for the current stage: the groups in Build, the findings in Review, the failed checks.
  detail: string[]
  // The failed requirements of the current stage's gate, for the pane.
  failedChecks: Requirement[]
  groups: GroupRow[] | null
  findings: Finding[]
  criteria: Array<{ id: string; text: string; status: 'passed' | 'open'; priority: string }>
  passed: number
  total: number
  task: { n: number; of: number } | null
  // The person's decisions in this run, as sentences, oldest first.
  decisions: string[]
  // The loops of the run with their budget: "Review to Build: 1 of 2".
  loops: string[]
  // The one line that says the mod cannot read the run as it should; null when all is well.
  line: string | null
  // Check wrote config-suggestions.json (the Commit question offers "Review config suggestions").
  configSuggestions: boolean
  paneOpen: boolean
}

export type ViewInput = {
  run: RunFacts | null
  title: string | null
  gates: Gates
  skips: Skips
  loops: readonly Loop[]
  groups: GroupRow[] | null
  findings: readonly Finding[]
  criteria: readonly MergedCriterion[]
  task: { n: number; of: number } | null
  move: Move | null
  decisions: readonly Decision[]
  enforcement: 'on' | 'off'
  configSuggestions?: boolean
  line?: string | null
  paneOpen?: boolean
}

function stagesOf(input: ViewInput): StageView[] {
  const r = input.run
  const design = r !== null && hasDesign(r.complexity, r.designRequired, r.designSeen)
  return STAGES.filter(s => s !== 'design' || design).map(id => {
    const skip = input.skips[id]?.reason ?? null
    const failed = input.gates[id]?.verdict === 'FAIL'
    const base = { id, label: stageLabel(id), failed, skip: skip ?? null }
    if (r === null) return { ...base, mark: 'pending' as const }
    if (id === r.stage) return { ...base, mark: 'current' as const }
    if (stageIndex(id) > stageIndex(r.stage)) return { ...base, mark: 'pending' as const }
    if (skip !== null) return { ...base, mark: 'skipped' as const }
    return { ...base, mark: failed ? ('failed' as const) : ('passed' as const) }
  })
}

const TASK_GLYPH: Record<string, string> = { waiting: '○', running: '◐', passed: '✓', failed: '✗', parked: '⏸' }

// One line a group in Build: "G2 Payments  ✓1 ✓2 ◐3 ○4".
export function groupLine(g: GroupRow): string {
  const tasks = g.tasks.map(t => `${TASK_GLYPH[t.state] ?? '○'}${t.n}`).join(' ')
  const state = g.state === 'parked' ? ' (parked)' : g.state === 'passed' ? ' (passed)' : ''
  return `${g.id}${g.title ? ` ${g.title}` : ''}${state}  ${tasks}`
}

function waitOf(input: ViewInput): Wait | null {
  const r = input.run
  if (r === null) return null
  if (r.stage === 'commit') return 'done'
  if (input.move?.kind === 'pause') return 'saved'
  if (input.move !== null) return 'chosen'
  if (r.runMode === 'autonomous' && r.autonomyEnabled) return 'armed'
  return input.gates[r.stage] !== undefined || r.skipped.has(r.stage) ? 'gate' : 'work'
}

function statusOf(input: ViewInput, wait: Wait | null): string {
  const r = input.run
  if (r === null) return ''
  const label = stageLabel(r.stage)
  const verdict = input.gates[r.stage]?.verdict
  switch (wait) {
    case 'done':
      return 'Every gate is behind the run. Commit is next.'
    case 'saved':
      return `${label} is saved for later. Go on when you are ready.`
    case 'chosen':
      return `${label}: your choice (${describe(input.move as Move)}). Claude carries it out.`
    case 'armed':
      return `${label}: the run goes on by itself (armed at the plan gate).`
    case 'gate':
      return `${label}: the check ${verdict === 'FAIL' ? 'failed' : 'passed'}. Waiting for you: answer the Temper gate question.`
    default:
      return `${label}: Claude is working on it.`
  }
}

function detailOf(input: ViewInput): string[] {
  const r = input.run
  if (r === null) return []
  const out: string[] = []
  if (r.stage === 'build' && input.groups !== null) {
    const done = input.groups.reduce((n, g) => n + g.tasks.filter(t => t.state === 'passed').length, 0)
    const all = input.groups.reduce((n, g) => n + g.tasks.length, 0)
    out.push(`Tasks: ${done} of ${all} done`)
    for (const g of input.groups) out.push(groupLine(g))
  } else if (r.stage === 'build' && input.task !== null) {
    out.push(`Task ${input.task.n} of ${input.task.of}`)
  }
  if (r.stage === 'review') {
    const by = new Map<string, number>()
    for (const f of input.findings) by.set(f.severity, (by.get(f.severity) ?? 0) + 1)
    out.push(input.findings.length === 0 ? 'No open findings.' : `Open findings: ${[...by.entries()].map(([s, n]) => `${n} ${s}`).join(', ')}`)
  }
  const failed = (input.gates[r.stage]?.requirements ?? []).filter(q => !q.pass)
  if (failed.length > 0) out.push(`Failed: ${failed.map(q => q.name).join(', ')}`)
  return out
}

export function buildView(input: ViewInput): View {
  const wait = waitOf(input)
  const r = input.run
  return {
    title: input.title,
    stage: r?.stage ?? null,
    enforcement: input.enforcement,
    stages: stagesOf(input),
    wait,
    status: statusOf(input, wait),
    detail: detailOf(input),
    failedChecks: r === null ? [] : (input.gates[r.stage]?.requirements ?? []).filter(q => !q.pass),
    groups: input.groups,
    findings: [...input.findings],
    criteria: input.criteria.map(c => ({ id: c.id, text: c.text, status: c.status, priority: c.priority })),
    passed: input.criteria.filter(c => c.status === 'passed').length,
    total: input.criteria.length,
    task: input.task,
    decisions: input.decisions.map(describe),
    loops: input.loops.map(l => `${cap(l.from)} to ${cap(l.to)}: ${l.iteration} of ${l.max}`),
    line: input.line ?? null,
    configSuggestions: input.configSuggestions ?? false,
    paneOpen: input.paneOpen ?? false,
  }
}

const cap = (s: string): string => `${s.charAt(0).toUpperCase()}${s.slice(1)}`

// The glyph for each mark on the timeline. The current stage is a filled circle; a failed check is a cross.
export const MARK: Record<Mark, string> = { passed: '✓', failed: '✗', skipped: '↷', current: '●', pending: '○' }

export const LEGEND = '✓ passed  ✗ failed  ↷ skipped  ● here  ○ to come'

// "Step 4 of 7: Build" (the run's own stages, Design only when it has one).
export function whereText(v: View): string {
  if (v.stage === null) return ''
  if (v.stage === 'commit') return 'Done'
  const at = v.stages.findIndex(s => s.id === v.stage)
  return `Step ${at + 1} of ${v.stages.length}: ${stageLabel(v.stage)}`
}

const VERB: Record<Stage, string> = {
  intent: 'Capturing intent',
  plan: 'Planning',
  design: 'Designing',
  build: 'Building',
  review: 'Reviewing',
  check: 'Checking',
  commit: 'Committing',
}

// "Building · criterion 2 of 5": the criterion being worked is the first not yet passed.
export function spinnerWord(v: View): string | null {
  if (v.stage === null) return null
  const verb = VERB[v.stage]
  if (v.total === 0) return verb
  return `${verb} · criterion ${Math.min(v.passed + 1, v.total)} of ${v.total}`
}

// The dim line after the engine's prompt hint on the terminal.
export function hintTail(v: View): string | null {
  if (v.stage === null) return null
  return v.stage === 'commit' ? 'Temper: the run is done.' : `Temper. ${whereText(v)}. ${v.status}`
}

// One dim line beneath an answer when a turn ends: "Build · 2 of 4 criteria met · next: Review".
export function turnLine(v: View): string | null {
  if (v.stage === null) return null
  if (v.stage === 'commit') return 'Done · next: commit'
  const parts = [stageLabel(v.stage)]
  if (v.total > 0) parts.push(`${v.passed} of ${v.total} criteria met`)
  const at = v.stages.findIndex(s => s.id === v.stage)
  const next = v.stages[at + 1]
  parts.push(`next: ${next ? next.label : 'Commit'}`)
  return parts.join(' · ')
}

// One line above the engine's own question dialog.
export function questionHeader(v: View): string | null {
  if (v.stage === null || v.stage === 'commit') return null
  return v.total > 0 ? `Temper: ${whereText(v)}, criterion ${Math.min(v.passed + 1, v.total)} of ${v.total}` : `Temper: ${whereText(v)}`
}

// The toast when the run reaches another stage: "Build is open." Null for no run.
export function stageToast(stage: Stage | null): string | null {
  if (stage === null) return null
  return stage === 'commit' ? 'The run is done. Commit is next.' : `${stageLabel(stage)} is open.`
}

// What Claude does next, for the system prompt: the gate to ask, the choice to carry out, or the stage to run.
export function nextStep(v: View, run: RunFacts | null): string {
  if (v.stage === null || run === null) return ''
  const label = stageLabel(v.stage)
  const after = nextStage(v.stage, hasDesign(run.complexity, run.designRequired, run.designSeen))
  const failed = v.stages.find(s => s.id === v.stage)?.failed ?? false
  switch (v.wait) {
    case 'done':
      return 'every gate is behind the run: commit as the Commit section of commands/temper.md says'
    case 'saved':
      return 'the user saved the run for later: do nothing for the run until the user takes it up again'
    case 'chosen':
      return 'the user chose in the `Temper gate` question: carry out that answer now, as commands/temper.md says for it'
    case 'armed':
      return 'the run is armed: go on by the verdicts, and park as reference/autonomy.md says'
    case 'gate':
      return failed
        ? `the ${label} check failed: ask the user with AskUserQuestion, header \`Temper gate\`, with the FAIL options of the ${label} gate`
        : `ask the user with AskUserQuestion, header \`Temper gate\`: continue to ${after ? stageLabel(after) : 'Commit'}, or the other options of the ${label} gate`
    default:
      return `run the ${label} stage and its check, then ask the user with AskUserQuestion, header \`Temper gate\``
  }
}
