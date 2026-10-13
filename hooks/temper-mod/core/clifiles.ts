// Readers for the CLI's own files. The mod only reads them: the CLI owns where the run is, every verdict, every skip
// and every loop (ADR 0012). Unreadable input reads as nothing, never as a guess. Pure.

import type { Stage } from './stages'
import { GATED, isStage } from './stages'

export type BuildState = {
  spec: string
  specPath: string
  nextStage: string | null
  // The stage the CLI completed last; `started` only right after `state init`.
  stage: string | null
  // The run and the step a decision of the person belongs to (ADR 0012). A run state written before it has neither
  // until its next CLI state call: the run is then `legacy:<spec>` and the step -1.
  runId: string
  step: number
  task: number | null
  complexity: string | null
  // The run's own branch and the command that started it (`temper` or `fix`).
  branch: string | null
  command: string | null
  // `autonomous` once the person armed autonomy at the plan gate, else `interactive` (or none).
  runMode: string | null
}

export function parseBuildState(text: string): BuildState | null {
  let raw: unknown
  try {
    raw = JSON.parse(text)
  } catch {
    return null
  }
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) return null
  const o = raw as Record<string, unknown>
  if (typeof o.spec !== 'string' || o.spec === '') return null
  const specPath = typeof o.spec_path === 'string' && o.spec_path !== '' ? o.spec_path : `.temper/specs/${o.spec}`
  return {
    spec: o.spec,
    specPath,
    nextStage: typeof o.next_stage === 'string' ? o.next_stage : null,
    stage: typeof o.stage === 'string' ? o.stage : null,
    runId: typeof o.run_id === 'string' && o.run_id !== '' ? o.run_id : `legacy:${o.spec}`,
    step: typeof o.step === 'number' && Number.isInteger(o.step) ? o.step : -1,
    complexity: typeof o.complexity === 'string' ? o.complexity : null,
    branch: typeof o.branch === 'string' && o.branch !== '' ? o.branch : null,
    command: typeof o.command === 'string' ? o.command : null,
    runMode: typeof o.run_mode === 'string' ? o.run_mode : null,
    task: typeof o.task === 'number' && Number.isInteger(o.task) && o.task >= 1 ? o.task : null,
  }
}

export type Requirement = { name: string; pass: boolean; detail: string }
export type GateRow = { verdict: 'PASS' | 'FAIL'; requirements: Requirement[] }
export type Gates = Partial<Record<Stage, GateRow>>

// gates.json: `{ stage: { verdict: 'PASS'|'FAIL', requirements: [{ name, pass, detail }], ... } }`. Since ADR 0012 the
// CLI removes the verdicts of the stages a step back redoes, so every row belongs to the current pass of its stage.
export function parseGates(text: string): Gates {
  let raw: unknown
  try {
    raw = JSON.parse(text)
  } catch {
    return {}
  }
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) return {}
  const out: Gates = {}
  for (const stage of [...GATED, 'commit' as const]) {
    const row = (raw as Record<string, unknown>)[stage]
    if (typeof row !== 'object' || row === null) continue
    const { verdict, requirements } = row as { verdict?: unknown; requirements?: unknown }
    if (verdict !== 'PASS' && verdict !== 'FAIL') continue
    const reqs = Array.isArray(requirements)
      ? requirements
          .filter((r): r is Record<string, unknown> => typeof r === 'object' && r !== null)
          .map(r => ({ name: typeof r.name === 'string' ? r.name : '', pass: r.pass === true || r.pass === 1, detail: typeof r.detail === 'string' ? r.detail : '' }))
          .filter(r => r.name !== '')
      : []
    out[stage] = { verdict, requirements: reqs }
  }
  return out
}

export type Skip = { reason: string; by: string }
export type Skips = Partial<Record<Stage, Skip>>

// overrides.json: the person's skips, one row a stage (`temper override <stage>`). A row for something that is no stage
// (`foreign-commit:G1:sha`, the kept commits of a task agent) skips nothing. The last row of a stage wins.
export function parseSkips(text: string): Skips {
  let raw: unknown
  try {
    raw = JSON.parse(text)
  } catch {
    return {}
  }
  if (!Array.isArray(raw)) return {}
  const out: Skips = {}
  for (const r of raw) {
    if (typeof r !== 'object' || r === null) continue
    const { stage, reason, by } = r as { stage?: unknown; reason?: unknown; by?: unknown }
    if (typeof stage !== 'string' || !isStage(stage)) continue
    out[stage] = { reason: typeof reason === 'string' ? reason : '', by: typeof by === 'string' ? by : '' }
  }
  return out
}

export type Loop = { from: string; to: string; iteration: number; max: number }

// feedback-loops.json: the loops the CLI keeps (`state loop`), each with its count and its budget.
export function parseLoops(text: string): Loop[] {
  try {
    const d = JSON.parse(text) as { active_loops?: unknown }
    if (!Array.isArray(d.active_loops)) return []
    return d.active_loops
      .filter((l): l is Record<string, unknown> => typeof l === 'object' && l !== null)
      .filter(l => typeof l.from_stage === 'string' && typeof l.to_stage === 'string' && typeof l.iteration === 'number' && typeof l.max_iterations === 'number')
      .map(l => ({ from: l.from_stage as string, to: l.to_stage as string, iteration: l.iteration as number, max: l.max_iterations as number }))
  } catch {
    return []
  }
}

export type Finding = { id: string; severity: string; claim: string }

// Open review findings from `.temper/evidence/review.json`: rows with a severity that are neither resolved nor
// accepted. The id is the row's 1-based position, which is what `temper evidence accept --id` takes.
export function parseFindings(text: string): Finding[] {
  let raw: unknown
  try {
    raw = JSON.parse(text)
  } catch {
    return []
  }
  if (!Array.isArray(raw)) return []
  const out: Finding[] = []
  raw.forEach((row, i) => {
    if (typeof row !== 'object' || row === null) return
    const r = row as Record<string, unknown>
    if (typeof r.severity !== 'string' || r.severity === '' || r.resolved || r.accepted) return
    out.push({ id: String(i + 1), severity: r.severity, claim: typeof r.claim === 'string' ? r.claim : '' })
  })
  return out
}

export type TaskState = 'waiting' | 'running' | 'passed' | 'failed' | 'parked'
export type TaskCell = { n: number; title: string; state: TaskState; model: string | null; attempt: number | null }
export type GroupRow = { id: string; title: string; state: 'waiting' | 'running' | 'passed' | 'parked'; tasks: TaskCell[] }

// The groups of a grouped Build, from tasks.md (`## Group G1: title`, `### Task N: title`, a ticked box when done) and
// groups.json (each started group and task: its state and its attempts with their model). Null when tasks.md has no
// groups.
export function parseGroups(tasksMd: string, groupsJson: string): GroupRow[] | null {
  const groups: GroupRow[] = []
  let cur: GroupRow | null = null
  let task: TaskCell | null = null
  for (const line of tasksMd.split('\n')) {
    const g = /^##\s+Group\s+(G\d+)\s*:?\s*(.*)$/.exec(line)
    if (g) {
      cur = { id: g[1] as string, title: (g[2] ?? '').trim(), state: 'waiting', tasks: [] }
      groups.push(cur)
      task = null
      continue
    }
    const t = /^###\s+Task\s+(\d+)\s*:?\s*(.*)$/.exec(line)
    if (t && cur) {
      task = { n: Number(t[1]), title: (t[2] ?? '').trim(), state: 'waiting', model: null, attempt: null }
      cur.tasks.push(task)
      continue
    }
    if (/^#{1,3}\s/.test(line)) task = null
    else if (task && /^\s*-\s+\[[xX]\]/.test(line)) task.state = 'passed'
  }
  if (groups.length === 0) return null
  let run: { groups?: Record<string, { status?: unknown }>; tasks?: Record<string, { status?: unknown; attempts?: unknown; attempt?: unknown }> } = {}
  try {
    const d = JSON.parse(groupsJson) as unknown
    if (typeof d === 'object' && d !== null && !Array.isArray(d)) run = d as typeof run
  } catch {
    run = {}
  }
  for (const grp of groups) {
    const gs = run.groups?.[grp.id]?.status
    if (gs === 'running' || gs === 'passed' || gs === 'parked') grp.state = gs
    for (const cell of grp.tasks) {
      const rt = run.tasks?.[String(cell.n)]
      if (!rt) continue
      const st = rt.status
      if (st === 'running' || st === 'passed' || st === 'failed') cell.state = st
      if (grp.state === 'parked' && st === 'failed') cell.state = 'parked'
      const attempts = Array.isArray(rt.attempts) ? rt.attempts : []
      const last = attempts[attempts.length - 1] as { model?: unknown } | undefined
      // A running attempt is recorded only when its gate runs: the model shown is that of the last finished attempt.
      cell.model = st !== 'running' && typeof last?.model === 'string' ? last.model : null
      cell.attempt = typeof rt.attempt === 'number' ? rt.attempt : attempts.length > 0 ? attempts.length : null
    }
  }
  return groups
}
