// The run report: the audit text made on `/temper:temper report`, from the CLI's files and the person's decisions. Pure;
// the adapter keeps the returned text in the plugin store (the mod writes no file).

import type { Gates, Loop, Skips } from './clifiles'
import type { MergedCriterion } from './criteria'
import { progress } from './criteria'
import type { Decision } from './decisions'
import { describe } from './decisions'
import type { Stage } from './stages'
import { GATED, stageIndex, stageLabel } from './stages'

export type ReportInput = {
  slug: string | null
  title: string | null
  // The stage the CLI is at; null with no run.
  stage: Stage | null
  gates: Gates
  skips: Skips
  loops: readonly Loop[]
  decisions: readonly Decision[]
  criteria: readonly MergedCriterion[]
  generatedAt: number
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

const iso = (ts: number): string => new Date(ts).toISOString()

function section(title: string, rows: readonly string[]): string[] {
  return [`## ${title}`, '', ...(rows.length > 0 ? rows : ['None.']), '']
}

// How each stage stands: its verdict, the person's skip, or where the run is.
function stageResult(input: ReportInput, s: Stage): string {
  if (input.stage === s) return 'current'
  const skip = input.skips[s]
  if (skip) return `skipped${skip.reason ? ` (${skip.reason})` : ''}`
  const v = input.gates[s]?.verdict
  if (v === 'PASS') return 'passed'
  if (v === 'FAIL') return 'failed'
  return input.stage !== null && stageIndex(s) < stageIndex(input.stage) ? 'passed (no verdict kept)' : 'not started'
}

export function renderReport(input: ReportInput): string {
  const out: string[] = []
  out.push(`# Temper report: ${input.title ?? 'untitled run'}`, '')
  if (input.slug) out.push(`Spec: ${input.slug}`)
  out.push(`Generated: ${iso(input.generatedAt)}`)
  out.push(input.stage === 'commit' ? 'Result: Done' : `Result: In progress (${input.stage ? stageLabel(input.stage) : 'no run'})`, '')

  const shown = GATED.filter(s => s !== 'design' || input.gates.design !== undefined || input.skips.design !== undefined || input.stage === 'design')
  const stageRows = ['| Stage | Result |', '|---|---|', ...shown.map(s => `| ${stageLabel(s)} | ${stageResult(input, s)} |`)]
  for (const l of input.loops) stageRows.push('', `Loop ${l.from} to ${l.to}: ${l.iteration} of ${l.max}`)
  out.push(...section('Stages', stageRows))

  out.push(...section('Your decisions', input.decisions.map(d => `- ${iso(d.ts)}: ${describe(d)}`)))

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

  return out.join('\n').replace(/\n+$/, '\n')
}
