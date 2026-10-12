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
  // The CLI's usage rows (.temper/usage.json, see parseUsage). Left out: none recorded.
  usage?: readonly UsageRow[]
}

// One agent launch's usage as the CLI records it (`temper usage add`): tokens and ms are null when not given.
export type UsageRow = { stage: string; model: string; tokens: number | null; ms: number | null }

// The rows of .temper/usage.json. Text that is not a list gives none; a row that is not an object is left out.
export function parseUsage(text: string): UsageRow[] {
  let raw: unknown
  try {
    raw = JSON.parse(text)
  } catch {
    return []
  }
  if (!Array.isArray(raw)) return []
  const num = (v: unknown): number | null => (typeof v === 'number' && Number.isInteger(v) ? v : null)
  const name = (v: unknown): string => (typeof v === 'string' && v !== '' ? v : 'unknown')
  return raw
    .filter((r): r is Record<string, unknown> => typeof r === 'object' && r !== null && !Array.isArray(r))
    .map(r => ({ stage: name(r.stage), model: name(r.model), tokens: num(r.tokens), ms: num(r.ms) }))
}

export const USAGE_NOTE = 'Usage (per-agent totals as Claude Code returns them; the orchestrator session is not counted)'

type Sum = { rows: number; tokens: number | null; ms: number | null }

const add = (acc: Sum, r: UsageRow): Sum => ({
  rows: acc.rows + 1,
  tokens: r.tokens === null ? acc.tokens : (acc.tokens ?? 0) + r.tokens,
  ms: r.ms === null ? acc.ms : (acc.ms ?? 0) + r.ms,
})

// Per stage, per model and in total, as `temper report` prints them. A sum with no number given is '-'.
function usageRows(rows: readonly UsageRow[]): string[] {
  if (rows.length === 0) return []
  const empty: Sum = { rows: 0, tokens: null, ms: null }
  const group = (key: (r: UsageRow) => string): Array<[string, Sum]> => {
    const m = new Map<string, Sum>()
    for (const r of rows) m.set(key(r), add(m.get(key(r)) ?? empty, r))
    return [...m.entries()].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
  }
  const n = (v: number | null): string => (v === null ? '-' : String(v))
  const line = (name: string, x: Sum): string => `| ${name} | ${x.rows} | ${n(x.tokens)} | ${n(x.ms)} |`
  const total = rows.reduce(add, empty)
  return [
    USAGE_NOTE,
    '',
    '| Stage | Launches | Tokens | ms |',
    '|---|---|---|---|',
    ...group(r => r.stage).map(([k, v]) => line(k, v)),
    '',
    '| Model | Launches | Tokens | ms |',
    '|---|---|---|---|',
    ...group(r => r.model).map(([k, v]) => line(k, v)),
    '',
    `Total: ${total.rows} launches, ${n(total.tokens)} tokens, ${n(total.ms)} ms`,
  ]
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

  out.push(...section('Usage', usageRows(input.usage ?? [])))

  const notes = [
    ...(input.unreadable ?? []).map(n => `- Unreadable event file: ${n}`),
    ...(input.unverified ?? []).map(n => `- Event that Temper does not trust: ${n}`),
  ]
  if (notes.length > 0) out.push(...section('Notes', notes))

  return out.join('\n').replace(/\n+$/, '\n')
}
