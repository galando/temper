// The view model: everything the band, pane, spinner, hint and question header draw,
// computed once from the folded run so each drawing is a plain function of plain data.
// Pure and JSON safe: it is mirrored into `$.state`, which survives reload and compaction.
//
// Vocabulary, used the same way everywhere: a run has six phases; the bar shows each as done
// (a check mark), current ("you are here", a filled circle), upcoming (an open circle) or
// redo (a counter clockwise arrow, after a back step).

import { actionsFor, globalActions, lettered, nowText } from './actions'
import type { Action, ActionContext, ActionSet } from './actions'
import type { MergedCriterion } from './criteria'
import type { Phase } from './events'
import type { Finding } from './gates'
import { phaseLabel } from './machine'
import type { HistoryRecord, RunState } from './machine'

export type StepStatus = 'done' | 'current' | 'pending' | 'stale'

export type Step = { id: Phase; label: string; status: StepStatus }

export type ViewCriterion = { id: string; text: string; status: 'passed' | 'open'; priority: string }

export type View = {
  title: string | null
  phase: Phase | 'done' | null
  // 1 to 6 while a phase is active, else null.
  stepNo: number | null
  paused: boolean
  enforcement: 'on' | 'off'
  steps: Step[]
  // Null when no phase is active (no run, or Done): nothing to act on. `more` is the full
  // list the pane shows when expanded, each with its own letter hotkey.
  actions: ActionSet | null
  // Whether the full action list is shown (in the pane, or under the band when no pane is open).
  expanded: boolean
  // Whether the pane is open, so the band knows where the full list shows.
  paneOpen: boolean
  criteria: ViewCriterion[]
  passed: number
  total: number
  findings: Finding[]
  timeline: string[]
  // One plain sentence: what to do now.
  now: string
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
  expanded?: boolean
  paneOpen?: boolean
}

export const BAR: readonly Phase[] = ['intent', 'plan', 'build', 'review', 'check', 'fix']
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

const KIND: Record<string, (from: string, to: string) => string> = {
  start: (_f, to) => `Run started at ${to}`,
  advance: (from, to) => `${from} done, now ${to}`,
  back: (from, to) => `Sent back from ${from} to ${to}`,
  override: (from, to) => `${from} skipped, now ${to}`,
  check: (_f, to) => (to === 'Done' ? 'Checks passed, run done' : `Checks failed, now ${to}`),
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
  let actions: ActionSet | null = null
  if (s.phase !== null && s.phase !== 'done') {
    const base = actionsFor(s.phase, ctx)
    // An action the phase already lists is not listed twice.
    const extra = globalActions(s.phase, s.paused).filter(g => !base.more.some(m => m.id === g.id))
    actions = { ...base, more: lettered([...base.more, ...extra]) }
  }
  const stepIdx = s.phase !== null && s.phase !== 'done' ? BAR.indexOf(s.phase) : -1
  return {
    title: input.title,
    phase: s.phase,
    stepNo: stepIdx >= 0 ? stepIdx + 1 : null,
    paused: s.paused,
    enforcement: input.enforcement,
    steps: stepsOf(s),
    actions,
    expanded: input.expanded ?? false,
    paneOpen: input.paneOpen ?? false,
    criteria: input.criteria.map(c => ({ id: c.id, text: c.text, status: c.status, priority: c.priority })),
    passed,
    total: input.criteria.length,
    findings: [...input.findings],
    timeline: s.history.slice(-6).map(h => (KIND[h.kind] ?? KIND.advance)?.(h.from ? phaseLabel(h.from) : 'Start', phaseLabel(h.to)) ?? ''),
    now: s.phase === null ? '' : nowText(s.phase, ctx),
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

// The step in plain words: "Step 3 of 6: Build".
export function whereText(v: View): string {
  if (v.phase === null) return ''
  if (v.phase === 'done') return 'Done'
  return `Step ${v.stepNo ?? 0} of 6: ${phaseLabel(v.phase)}`
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
  return v.phase === 'done' ? 'Temper: the run is done.' : `Temper. ${whereText(v)}. ${v.now}`
}

// The phase that follows, for "next: Review". Check is followed by Done, and Fix by Check.
export function nextPhaseLabel(v: View): string {
  if (v.phase === null) return ''
  if (v.phase === 'done') return 'commit'
  const flow = ['intent', 'plan', 'build', 'review', 'check']
  if (v.phase === 'fix') return 'Check'
  const next = flow[flow.indexOf(v.phase) + 1]
  return next ? phaseLabel(next as Phase) : 'Done'
}

// One dim line beneath an answer when a turn ends: "Build \u00b7 2 of 4 criteria met \u00b7 next: Review".
export function turnLine(v: View): string | null {
  if (v.phase === null) return null
  if (v.phase === 'done') return 'Done \u00b7 next: commit'
  const parts = [phaseLabel(v.phase)]
  if (v.total > 0) parts.push(`${v.passed} of ${v.total} criteria met`)
  parts.push(`next: ${nextPhaseLabel(v)}`)
  return parts.join(' \u00b7 ')
}

// One line above the engine's own question dialog.
export function questionHeader(v: View): string | null {
  if (v.phase === null || v.phase === 'done') return null
  return v.total > 0 ? `Temper: ${whereText(v)}, criterion ${Math.min(v.passed + 1, v.total)} of ${v.total}` : `Temper: ${whereText(v)}`
}

// The glyph for each state of a step. No bare arrow: the current step is a filled circle.
export const MARK: Record<StepStatus, string> = { done: '✓', current: '●', pending: '○', stale: '↺' }

export const LEGEND = '✓ done  ● you are here  ○ upcoming  ↺ redo'

// The prompt the suggestion box offers (Tab to take): the main action's prompt, never sent.
export function suggestion(v: View): string | null {
  const first: Action | undefined = v.actions?.primary[0]
  return first?.prompt ?? null
}

// The toast for a phase change: "Plan approved \u00b7 Build open". Null for a run start.
export function transitionToast(rec: HistoryRecord | undefined): string | null {
  if (!rec || rec.kind === 'start') return null
  const from = rec.from ? phaseLabel(rec.from) : ''
  const to = rec.to === 'done' ? 'Run done' : `${phaseLabel(rec.to)} open`
  switch (rec.kind) {
    case 'advance':
      return `${from} ${rec.from === 'fix' ? 'done' : 'approved'}. ${to}.`
    case 'override':
      return `${from} skipped. ${to}.`
    case 'back':
      return `Back to ${phaseLabel(rec.to as Phase)}. The later steps need a new check.`
    case 'check':
      return rec.to === 'done' ? 'Check passed. Run done.' : 'Check failed. Fix open.'
    default:
      return null
  }
}
