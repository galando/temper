// The view model: what the bar, the pane, the spinner, the hint, the question header and the system prompt show, made
// once from view.json (the CLI's) and the person's decisions (the mod's), so each drawing is a plain function of plain
// data (ADR 0013). It holds no button that decides: the person decides in the question dialog. Pure and JSON safe: it is
// mirrored into `$.state`, which survives reload and compaction.

import type { Decision } from './decisions'
import { describe } from './decisions'
import type { RunView } from './runview'
import type { Stage } from './stages'
import { cliStage, isStage, stageLabel } from './stages'

// How a stage stands on the timeline: its check passed, failed, or the person skipped it; the run is at it; or it is
// still to come.
export type Mark = 'passed' | 'failed' | 'skipped' | 'current' | 'pending'

export type StageView = { id: Stage; label: string; mark: Mark; failed: boolean; skip: string | null }

// What the run waits for at its current stage:
//  gate    the question is out: the person answers it
//  chosen  the person chose; Claude carries it out
//  saved   the person saved the run for later
//  work    the stage is being worked
//  armed   an armed autonomous run goes on by itself
//  done    every gate is behind the run: Commit is next
export type Wait = 'gate' | 'chosen' | 'saved' | 'work' | 'armed' | 'done'

export type TaskCell = { n: number; title: string; state: 'waiting' | 'running' | 'passed' | 'failed' | 'parked'; model: string | null; attempt: number | null }

export type GroupRow = { id: string; title: string; state: 'waiting' | 'running' | 'passed' | 'parked'; tasks: TaskCell[] }

// A task in the Build grid: its state as the CLI's ledger shows it (RED and GREEN from the task's own evidence), the
// model it ran on, and how many times it ran again.
export type GridTask = { n: number; title: string; state: 'waiting' | 'running' | 'red' | 'green' | 'pass' | 'fail' | 'parked'; model: string | null; retries: number }

export type GridGroup = { id: string; title: string; status: string; tasks: GridTask[] }

// A loop back on the timeline, with the reason the person (or the armed run) gave.
export type LoopMark = { from: string; to: string; iteration: number; max: number; reason: string }

export type FindingRow = { id: number; severity: string; confidence: number | null; where: string | null; claim: string; state: 'open' | 'resolved' | 'accepted' }

export type Marker = { name: string; state: 'pass' | 'fail' | 'info' | 'none'; detail: string; lines: string[] }

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
  // The failed checks of the current stage's gate, for the pane.
  failedChecks: Array<{ name: string; detail: string }>
  groups: GroupRow[] | null
  findings: Array<{ id: string; severity: string; claim: string }>
  criteria: Array<{ id: string; text: string; status: 'passed' | 'open'; priority: string; evidence: string[] }>
  passed: number
  total: number
  // Minutes from the run's start to its last change (null when not known).
  clock: { minutes: number | null }
  loopMarks: LoopMark[]
  // The plan's files by Build group (approved: as the person approved them at the plan gate); null with no plan.
  planTree: { approved: boolean; groups: Array<{ id: string; title: string; files: string[] }>; other: string[] } | null
  // Build, a cell per task; null with no grouped tasks.
  grid: GridGroup[] | null
  // Every Review finding, open, resolved or accepted.
  findingRows: FindingRow[]
  // The five Check markers: compile, tests, coverage, lint, security.
  markers: Marker[]
  // The person's decisions in this run, as sentences, oldest first.
  decisions: string[]
  // The loops of the run with their budget: "Review to Build: 1 of 2".
  loops: string[]
  // The one line that says the mod cannot read the run as it should; null when all is well.
  line: string | null
  // What `temper next` does now (the system prompt names it).
  next: { action: string; say: string; header: string | null }
  paneOpen: boolean
}

export type ViewInput = {
  view: RunView
  // The person's decisions in this run, and the latest gate answer at the CLI's step.
  decisions: readonly Decision[]
  answer: Extract<Decision, { kind: 'gate' }> | null
  enforcement: 'on' | 'off'
  line?: string | null
  paneOpen?: boolean
}

const MARKS: Record<string, Mark> = { passed: 'passed', failed: 'failed', skipped: 'skipped', here: 'current', todo: 'pending' }

const TASK_CELL: Record<string, TaskCell['state']> = { waiting: 'waiting', running: 'running', red: 'running', green: 'running', pass: 'passed', fail: 'failed', parked: 'parked' }

function groupsOf(rv: RunView): GroupRow[] | null {
  if (rv.build.groups.length === 0) return null
  return rv.build.groups.map(g => {
    const tasks = g.tasks.map(t => ({ n: t.n, title: t.title, state: TASK_CELL[t.state] ?? 'waiting', model: t.model, attempt: t.attempts > 0 ? t.attempts : null }))
    const state: GroupRow['state'] = g.status === 'parked' ? 'parked' : g.status === 'passed' || g.status === 'merged' ? 'passed' : tasks.some(t => t.state !== 'waiting') ? 'running' : 'waiting'
    return { id: g.id, title: g.title, state, tasks }
  })
}

const TASK_GLYPH: Record<string, string> = { waiting: '○', running: '◐', passed: '✓', failed: '✗', parked: '⏸' }

// One line a group in Build: "G2 Payments  ✓1 ✓2 ◐3 ○4".
export function groupLine(g: GroupRow): string {
  const tasks = g.tasks.map(t => `${TASK_GLYPH[t.state] ?? '○'}${t.n}`).join(' ')
  const state = g.state === 'parked' ? ' (parked)' : g.state === 'passed' ? ' (passed)' : ''
  return `${g.id}${g.title ? ` ${g.title}` : ''}${state}  ${tasks}`
}

function waitOf(input: ViewInput, stage: Stage | null): Wait | null {
  const rv = input.view
  if (stage === null) return null
  if (stage === 'commit' && rv.next.action !== 'ask') return 'done'
  if (input.answer?.move === 'pause') return 'saved'
  if (input.answer !== null) return 'chosen'
  if (rv.next.action === 'auto' || rv.guard?.armed === true) return 'armed'
  return rv.next.action === 'ask' ? 'gate' : 'work'
}

function statusOf(input: ViewInput, stage: Stage | null, wait: Wait | null): string {
  if (stage === null) return ''
  const label = stageLabel(stage)
  if (wait === 'saved') return `${label} is saved for later. Type /temper:temper when you are ready.`
  if (wait === 'chosen' && input.answer !== null) return `${label}: your choice (${input.answer.label}). Claude carries it out.`
  return input.view.status
}

function detailOf(rv: RunView, stage: Stage | null, groups: GroupRow[] | null, failed: ReadonlyArray<{ name: string }>): string[] {
  if (stage === null) return []
  const out: string[] = []
  if (stage === 'build' && groups !== null) {
    const done = groups.reduce((n, g) => n + g.tasks.filter(t => t.state === 'passed').length, 0)
    const all = groups.reduce((n, g) => n + g.tasks.length, 0)
    out.push(`Tasks: ${done} of ${all} done`)
    for (const g of groups) out.push(groupLine(g))
  }
  if (stage === 'review') {
    const open = rv.findings.filter(f => f.state === 'open')
    const by = new Map<string, number>()
    for (const f of open) by.set(f.severity, (by.get(f.severity) ?? 0) + 1)
    out.push(open.length === 0 ? 'No open findings.' : `Open findings: ${[...by.entries()].map(([s, n]) => `${n} ${s}`).join(', ')}`)
  }
  if (failed.length > 0) out.push(`Failed: ${failed.map(q => q.name).join(', ')}`)
  return out
}

export function buildView(input: ViewInput): View {
  const rv = input.view
  const stage = cliStage(rv.run?.stage ?? null)
  const wait = waitOf(input, stage)
  const here = rv.stages.find(s => s.mark === 'here')
  const failed = here?.failed ?? []
  const groups = groupsOf(rv)
  const criteria = rv.criteria.map(c => ({ id: c.id, text: c.text || c.id, status: c.status === 'passed' ? ('passed' as const) : ('open' as const), priority: c.priority, evidence: c.evidence }))
  return {
    title: rv.run?.title ?? null,
    stage,
    enforcement: input.enforcement,
    stages: rv.stages
      .filter((s): s is typeof s & { id: Stage } => isStage(s.id))
      .map(s => ({ id: s.id, label: s.label || stageLabel(s.id), mark: MARKS[s.mark] ?? 'pending', failed: s.verdict === 'FAIL', skip: s.skipped?.reason ?? null })),
    wait,
    status: statusOf(input, stage, wait),
    detail: detailOf(rv, stage, groups, failed),
    failedChecks: failed.map(q => ({ name: q.name, detail: q.detail })),
    groups,
    findings: rv.findings.filter(f => f.state === 'open').map(f => ({ id: String(f.id), severity: f.severity, claim: f.claim })),
    criteria,
    passed: criteria.filter(c => c.status === 'passed').length,
    total: criteria.length,
    decisions: input.decisions.map(describe),
    loops: rv.loops.map(l => `${cap(l.from)} to ${cap(l.to)}: ${l.iteration} of ${l.max}${l.reason ? ` (${l.reason})` : ''}`),
    line: input.line ?? null,
    next: { action: rv.next.action, say: rv.next.say, header: rv.ask?.question.header ?? null },
    clock: { minutes: minutesOf(rv.time.started, rv.time.updated) },
    loopMarks: rv.loops.map(l => ({ from: l.from, to: l.to, iteration: l.iteration, max: l.max, reason: l.reason })),
    planTree: planTreeOf(rv),
    grid: rv.build.groups.length === 0 ? null : rv.build.groups.map(g => ({ id: g.id, title: g.title, status: g.status, tasks: g.tasks.map(t => ({ n: t.n, title: t.title, state: t.state, model: t.model, retries: Math.max(t.attempts - 1, 0) })) })),
    findingRows: rv.findings.map(f => ({ id: f.id, severity: f.severity, confidence: f.confidence, where: f.file ? `${f.file}:${f.line ?? ''}` : null, claim: f.file ? f.claim.replace(/^\s*\S+:\d+\s*/, '') : f.claim, state: f.state })),
    markers: rv.markers.map(m => ({ name: m.name, state: m.state, detail: m.detail, lines: m.lines })),
    paneOpen: input.paneOpen ?? false,
  }
}

// Whole minutes between two ISO times; null when either does not read.
function minutesOf(start: string | null, end: string | null): number | null {
  const a = start ? Date.parse(start) : NaN
  const b = end ? Date.parse(end) : NaN
  return Number.isFinite(a) && Number.isFinite(b) && b >= a ? Math.floor((b - a) / 60000) : null
}

function planTreeOf(rv: RunView): View['planTree'] {
  if (rv.plan.groups.length === 0 && rv.plan.files.length === 0) return null
  const grouped = new Set(rv.plan.groups.flatMap(g => g.files))
  return { approved: rv.plan.approved, groups: rv.plan.groups, other: rv.plan.files.filter(f => !grouped.has(f)) }
}

// "42 min": the band's measure of the run; null when it is not known.
export function clockText(v: View): string | null {
  if (v.clock.minutes === null) return null
  return v.clock.minutes >= 60 ? `${Math.floor(v.clock.minutes / 60)} h ${v.clock.minutes % 60} min` : `${v.clock.minutes} min`
}

// "↺ Review to Build (1 of 2): a real bug": a loop on the timeline.
export const loopText = (l: LoopMark): string => `↺ ${cap(l.from)} to ${cap(l.to)} (${l.iteration} of ${l.max})${l.reason ? `: ${l.reason}` : ''}`

// The cell of a task in the Build grid: its glyph and its word.
export const TASK_STATE: Record<GridTask['state'], [string, string]> = {
  waiting: ['○', 'waiting'],
  running: ['◐', 'running'],
  red: ['●', 'RED'],
  green: ['●', 'GREEN'],
  pass: ['✓', 'PASS'],
  fail: ['✗', 'FAIL'],
  parked: ['⏸', 'parked'],
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

// What Claude does next, for the system prompt: what `temper next --json` says, in one line.
export function nextStep(v: View): string {
  if (v.stage === null) return ''
  switch (v.wait) {
    case 'saved':
      return 'the user saved the run for later: do nothing for the run until the user takes it up again'
    case 'chosen':
      return 'the user answered the question: carry out the calls of that option, as `temper next --json` gave them'
    case 'gate':
      return `ask the \`${v.next.header ?? 'Temper gate'}\` question exactly as \`temper next --json\` gives it, then wait`
    case 'armed':
      return 'the run is armed: run the calls `temper next --json` gives, and never ask "Shall I...?"'
    default:
      return v.next.say ? `${v.next.say} Do what \`temper next --json\` says.` : 'do what `temper next --json` says'
  }
}
