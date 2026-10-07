// The run report: the audit text made when a run completes or on `/temper:temper report`. Pure;
// the adapter keeps the returned text in the plugin store (the mod writes no file).

import type { MergedCriterion } from './criteria'
import { progress } from './criteria'
import type { Phase } from './events'
import { phaseLabel } from './machine'
import type { RunState } from './machine'

export type ReportInput = {
  state: RunState
  criteria: readonly MergedCriterion[]
  generatedAt: number
  unreadable?: readonly string[]
  unverified?: readonly string[]
}

const ROWS: readonly Phase[] = ['intent', 'plan', 'build', 'review', 'check']

const iso = (ts: number): string => new Date(ts).toISOString()
const by = (author: string | undefined, ts: number): string => `(by ${author ?? 'unknown'}, ${iso(ts)})`
const reasonOf = (reason: string): string => (reason ? `, reason: ${reason}` : '')

const CHOICE: Record<string, string> = { add: 'add to plan', revert: 'revert', 'allow-once': 'allow once' }

function phaseResult(s: RunState, p: Phase): string {
  if (s.phase === p) return 'current'
  if (s.stale.includes(p)) return 'stale'
  if (s.overrides.some(o => o.phase === p)) return 'overridden'
  const left = s.history.some(h => h.from === p && (h.kind === 'advance' || (h.kind === 'check' && h.to === 'done')))
  return left ? 'passed' : 'not started'
}

function section(title: string, rows: readonly string[]): string[] {
  return [`## ${title}`, '', ...(rows.length > 0 ? rows : ['None.']), '']
}

export function renderReport(input: ReportInput): string {
  const s = input.state
  const out: string[] = []
  out.push(`# Temper report: ${s.title ?? 'untitled run'}`, '')
  if (s.slug) out.push(`Spec: ${s.slug}`)
  out.push(`Generated: ${iso(input.generatedAt)}`)
  out.push(s.phase === 'done' ? 'Result: Done' : `Result: In progress (${s.phase ? phaseLabel(s.phase) : 'no run'})`, '')

  const phaseRows = ['| Phase | Result |', '|---|---|', ...ROWS.map(p => `| ${phaseLabel(p)} | ${phaseResult(s, p)} |`)]
  if (s.loops > 0) phaseRows.push('', `Check to Fix loops: ${s.loops} (limit ${s.maxLoops})`)
  out.push(...section('Phases', phaseRows))

  out.push(...section('Overrides', s.overrides.map(o => `- ${phaseLabel(o.phase)}: overridden${reasonOf(o.reason)} ${by(o.author, o.ts)}`)))
  out.push(...section('Accepted findings', s.accepted.map(a => `- Finding ${a.findingId}: accepted${reasonOf(a.reason)} ${by(a.author, a.ts)}`)))
  out.push(...section('Scope drift', s.drift.map(d => `- ${d.path}: ${CHOICE[d.choice] ?? d.choice}${reasonOf(d.reason)} ${by(d.author, d.ts)}`)))

  const p = progress(input.criteria)
  const critRows = [
    `${p.passed} of ${p.total} passed`,
    '',
    '| ID | Priority | Status | Evidence |',
    '|---|---|---|---|',
    ...input.criteria.map(c => `| ${c.id} | ${c.priority} | ${c.status} | ${c.evidence.join('; ')} |`),
  ]
  out.push(...section('Criteria', input.criteria.length > 0 ? critRows : []))

  const notes = [
    ...(input.unreadable ?? []).map(n => `- Unreadable event file: ${n}`),
    ...(input.unverified ?? []).map(n => `- Event that Temper does not trust: ${n}`),
  ]
  if (notes.length > 0) out.push(...section('Notes', notes))

  return out.join('\n').replace(/\n+$/, '\n')
}
