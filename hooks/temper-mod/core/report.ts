// The run report: the audit text made on `/temper:temper report`, from view.json and the person's decisions. Pure; the
// adapter keeps the returned text in the plugin store (the mod writes no file).

import type { Decision } from './decisions'
import { describe } from './decisions'
import type { RunView } from './runview'

export type ReportInput = {
  view: RunView
  decisions: readonly Decision[]
  generatedAt: number
}

export const USAGE_NOTE = 'Usage (per-agent totals as Claude Code returns them; the orchestrator session is not counted)'

// Per stage and in total, as view.json gives them.
function usageRows(u: RunView['usage']): string[] {
  if (u.byStage.length === 0) return []
  const rows = [...u.byStage].sort((a, b) => (a.stage < b.stage ? -1 : a.stage > b.stage ? 1 : 0))
  const launches = rows.reduce((n, r) => n + r.runs, 0)
  return [
    USAGE_NOTE,
    '',
    '| Stage | Launches | ms |',
    '|---|---|---|',
    ...rows.map(r => `| ${r.stage} | ${r.runs} | ${r.ms} |`),
    '',
    '| Model | Launches | ms |',
    '|---|---|---|',
    ...[...u.byModel].sort((a, b) => (a.model < b.model ? -1 : a.model > b.model ? 1 : 0)).map(r => `| ${r.model} | ${r.runs} | ${r.ms} |`),
    '',
    `Total: ${launches} launches, ${u.ms} ms`,
  ]
}

const iso = (ts: number): string => new Date(ts).toISOString()

function section(title: string, rows: readonly string[]): string[] {
  return [`## ${title}`, '', ...(rows.length > 0 ? rows : ['None.']), '']
}

const RESULT: Record<string, string> = { passed: 'passed', failed: 'failed', skipped: 'skipped', here: 'current', todo: 'not started' }

export function renderReport(input: ReportInput): string {
  const v = input.view
  const out: string[] = []
  out.push(`# Temper report: ${v.run?.title ?? 'untitled run'}`, '')
  if (v.run) out.push(`Spec: ${v.run.slug}`)
  out.push(`Generated: ${iso(input.generatedAt)}`)
  const here = v.run?.stage ?? null
  out.push(here === 'commit' ? 'Result: Done' : `Result: In progress (${v.stages.find(s => s.id === here)?.label ?? 'no run'})`, '')

  const stageRows = [
    '| Stage | Result |',
    '|---|---|',
    ...v.stages.filter(s => s.id !== 'commit').map(s => `| ${s.label} | ${RESULT[s.mark] ?? s.mark}${s.skipped?.reason ? ` (${s.skipped.reason})` : ''} |`),
  ]
  for (const l of v.loops) stageRows.push('', `Loop ${l.from} to ${l.to}: ${l.iteration} of ${l.max}${l.reason ? ` (${l.reason})` : ''}`)
  out.push(...section('Stages', stageRows))

  out.push(...section('Your decisions', input.decisions.map(d => `- ${iso(d.ts)}: ${describe(d)}`)))

  const passed = v.criteria.filter(c => c.status === 'passed').length
  const critRows = [
    `${passed} of ${v.criteria.length} passed`,
    '',
    '| ID | Priority | Status | Evidence |',
    '|---|---|---|---|',
    ...v.criteria.map(c => `| ${c.id} | ${c.priority} | ${c.status} | ${c.evidence.join('; ')} |`),
  ]
  out.push(...section('Criteria', v.criteria.length > 0 ? critRows : []))

  out.push(...section('Usage', usageRows(v.usage)))

  return out.join('\n').replace(/\n+$/, '\n')
}
