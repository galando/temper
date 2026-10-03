// The view model: everything the band, pane, spinner, hint and question header draw,
// computed once from the folded run so each drawing is a plain function of plain data.
// Pure and JSON safe: it is mirrored into `$.state`, which survives reload and compaction.

import { actionsFor, nextStep } from './actions'
import type { Action, ActionContext, ActionSet } from './actions'
import type { MergedCriterion } from './criteria'
import type { Phase } from './events'
import type { Finding } from './gates'
import { phaseLabel } from './machine'
import type { RunState } from './machine'

export type StepStatus = 'done' | 'current' | 'pending' | 'stale'

export type Step = { id: Phase; label: string; status: StepStatus }

export type ViewCriterion = { id: string; text: string; status: 'passed' | 'open'; priority: string }

export type View = {
  title: string | null
  phase: Phase | 'done' | null
  paused: boolean
  enforcement: 'on' | 'off'
  steps: Step[]
  // Null when no phase is active (no run, or Done): nothing to act on.
  actions: ActionSet | null
  criteria: ViewCriterion[]
  passed: number
  total: number
  findings: Finding[]
  timeline: string[]
  next: string
  task: { n: number; of: number } | null
  loopLimitReached: boolean
}

export type ViewInput = {
  state: RunState
  title: string | null
  criteria: readonly MergedCriterion[]
  findings: readonly Finding[]
  task: { n: number; of: number } | null
  enforcement: 'on' | 'off'
}

const BAR: readonly Phase[] = ['intent', 'plan', 'build', 'review', 'check', 'fix']
const FLOW: readonly Phase[] = ['intent', 'plan', 'build', 'review', 'check']

const order = (p: Phase): number => (p === 'fix' ? FLOW.indexOf('check') + 0.5 : FLOW.indexOf(p))

function stepsOf(s: RunState): Step[] {
  return BAR.map(id => {
    const label = phaseLabel(id)
    if (s.phase === null) return { id, label, status: 'pending' as const }
    if (s.phase === 'done') return { id, label, status: id !== 'fix' || s.loops > 0 ? ('done' as const) : ('pending' as const) }
    if (id === s.phase) return { id, label, status: 'current' as const }
    if (s.stale.includes(id)) return { id, label, status: 'stale' as const }
    return { id, label, status: order(id) < order(s.phase) ? ('done' as const) : ('pending' as const) }
  })
}

export function buildView(input: ViewInput): View {
  const s = input.state
  const active = s.phase !== null && s.phase !== 'done'
  const gateFresh = active && s.phase !== null && s.phase !== 'done' ? s.gate[s.phase] === 'fresh' : false
  const ctx: ActionContext = {
    ready: gateFresh,
    tasksDone: s.phase === 'build' && gateFresh,
    hasFindings: input.findings.length > 0,
    allChecksPass: s.gate.check === 'fresh',
    loopLimitReached: s.loopLimitReached,
  }
  const passed = input.criteria.filter(c => c.status === 'passed').length
  return {
    title: input.title,
    phase: s.phase,
    paused: s.paused,
    enforcement: input.enforcement,
    steps: stepsOf(s),
    actions: s.phase !== null && s.phase !== 'done' ? actionsFor(s.phase, ctx) : null,
    criteria: input.criteria.map(c => ({ id: c.id, text: c.text, status: c.status, priority: c.priority })),
    passed,
    total: input.criteria.length,
    findings: [...input.findings],
    timeline: s.history.slice(-5).map(h => `${h.from ? phaseLabel(h.from) : 'Start'} to ${phaseLabel(h.to)} (${h.kind})`),
    next: s.phase === null ? '' : nextStep(s.phase, ctx),
    task: input.task,
    loopLimitReached: s.loopLimitReached,
  }
}

const VERB: Record<Phase, string> = {
  intent: 'Capturing intent',
  plan: 'Planning',
  build: 'Building',
  review: 'Reviewing',
  check: 'Checking',
  fix: 'Fixing',
}

// "Building · criterion 2 of 5": the criterion being worked is the first not yet passed.
export function spinnerWord(v: View): string | null {
  if (v.phase === null || v.phase === 'done') return null
  const verb = VERB[v.phase]
  if (v.total === 0) return verb
  return `${verb} · criterion ${Math.min(v.passed + 1, v.total)} of ${v.total}`
}

// The dim line after the engine's prompt hint on the terminal.
export function hintTail(v: View): string | null {
  if (v.phase === null) return null
  const phase = phaseLabel(v.phase)
  return v.phase === 'done' ? `Temper: ${phase}` : `Temper ${phase}: ${v.next}`
}

// One line beneath an answer when a turn ends.
export function turnLine(v: View): string | null {
  if (v.phase === null) return null
  const parts = [`Temper: ${phaseLabel(v.phase)}`]
  if (v.task) parts.push(`task ${v.task.n} of ${v.task.of}`)
  if (v.total > 0) parts.push(`${v.passed} of ${v.total} criteria passed`)
  const line = parts.join(', ')
  return v.next ? `${line}. Next: ${v.next}` : line
}

// One line above the engine's own question dialog.
export function questionHeader(v: View): string | null {
  if (v.phase === null || v.phase === 'done') return null
  const where = v.total > 0 ? `${phaseLabel(v.phase)}, criterion ${Math.min(v.passed + 1, v.total)} of ${v.total}` : phaseLabel(v.phase)
  return `Temper: ${where}`
}

// A short label per phase for the phase bar marker.
export const MARK: Record<StepStatus, string> = { done: '✓', current: '▶', pending: '·', stale: '!' }

// The prompt the suggestion box offers (Tab to take): the main action's prompt, never sent.
export function suggestion(v: View): string | null {
  const first: Action | undefined = v.actions?.primary[0]
  return first?.prompt ?? null
}
