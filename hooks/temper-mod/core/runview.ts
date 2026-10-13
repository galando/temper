// `.temper/view.json`, the one thing the mod reads of the CLI (ADR 0013, docs/flow.md). The CLI writes it after every
// command that may change the run; this file reads it into plain typed data, with every field checked. A view of a
// version this file does not know is no view: the mod draws nothing and refuses nothing it cannot read. Pure.

export const VIEW_VERSION = 1

// A question as it goes to the AskUserQuestion tool.
export type Question = { header: string; question: string; options: Array<{ label: string; description: string }> }

// An option with what it means: the move, and the exact CLI calls and steps the answer maps to.
export type Option = {
  label: string
  description: string
  move: string | null
  calls: string[]
  steps: string[]
  // The move needs the person's reason: their note on the option, or their answer to this question.
  reasonQuestion: Question | null
}

export type Ask = { stage: string; step: number; runId: string; question: Question; options: Option[]; more: Ask | null; accept: Ask | null }

export type StageMark = 'passed' | 'failed' | 'skipped' | 'here' | 'todo'

export type TaskState = 'waiting' | 'running' | 'red' | 'green' | 'pass' | 'fail' | 'parked'

export type RunView = {
  run: {
    id: string
    step: number
    slug: string
    title: string
    command: string
    stage: string
    mode: string
    complexity: string | null
    branch: string | null
    spec: string
    parked: string | null
  } | null
  stages: Array<{ id: string; label: string; mark: StageMark; verdict: 'PASS' | 'FAIL' | null; failed: Array<{ name: string; detail: string }>; skipped: { reason: string; by: string } | null }>
  status: string
  next: { action: string; stage: string; say: string; calls: string[]; steps: string[] }
  ask: Ask | null
  restart: { header: string; question: string; options: Option[] } | null
  drift: { header: string; prefix: string; options: string[] }
  guard: {
    stage: string
    spec: string
    slug: string
    fixRun: boolean
    grouped: boolean
    armed: boolean
    autonomyEnabled: boolean
    planFiles: string[]
    step: number
    runId: string
    trivialExit: boolean
  } | null
  plan: { approved: boolean; files: string[]; groups: Array<{ id: string; title: string; files: string[] }> }
  build: {
    groups: Array<{ id: string; title: string; status: string; verdict: string | null; tasks: Array<{ n: number; title: string; files: string[]; state: TaskState; model: string | null; attempts: number }> }>
    integration: string | null
  }
  findings: Array<{ id: number; severity: string; claim: string; file: string | null; line: number | null; state: 'open' | 'resolved' | 'accepted'; label: string | null }>
  checks: Array<{ name: string; pass: boolean; detail: string }>
  markers: Array<{ name: string; state: 'pass' | 'fail' | 'info' | 'none'; detail: string; value: number | null; lines: string[] }>
  criteria: Array<{ id: string; priority: string; status: string; text: string; evidence: string[] }>
  loops: Array<{ from: string; to: string; reason: string; iteration: number; max: number; at: string }>
  skips: Array<{ stage: string; reason: string; by: string }>
  usage: { tokens: number; ms: number; byStage: Array<{ stage: string; tokens: number; ms: number; runs: number }>; byModel: Array<{ model: string; tokens: number; ms: number; runs: number }> }
  time: { started: string | null; updated: string | null }
}

type J = Record<string, unknown>

const obj = (v: unknown): J => (typeof v === 'object' && v !== null && !Array.isArray(v) ? (v as J) : {})
const arr = (v: unknown): unknown[] => (Array.isArray(v) ? v : [])
const str = (v: unknown, fallback = ''): string => (typeof v === 'string' ? v : fallback)
const strOrNull = (v: unknown): string | null => (typeof v === 'string' && v !== '' ? v : null)
const num = (v: unknown, fallback = 0): number => (typeof v === 'number' && Number.isFinite(v) ? v : fallback)
const numOrNull = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null)
const strs = (v: unknown): string[] => arr(v).filter((x): x is string => typeof x === 'string')
const oneOf = <T extends string>(v: unknown, values: readonly T[], fallback: T): T => (values.includes(v as T) ? (v as T) : fallback)

function question(v: unknown): Question | null {
  const q = obj(v)
  if (typeof q.header !== 'string' || typeof q.question !== 'string') return null
  return { header: q.header, question: q.question, options: arr(q.options).map(o => ({ label: str(obj(o).label), description: str(obj(o).description) })) }
}

function option(v: unknown): Option {
  const o = obj(v)
  return {
    label: str(o.label),
    description: str(o.description),
    move: strOrNull(o.move),
    calls: strs(o.calls),
    steps: strs(o.steps),
    reasonQuestion: o.reason === true ? question(o.reason_question) : null,
  }
}

function ask(v: unknown): Ask | null {
  const a = obj(v)
  const q = question(a.question)
  if (q === null) return null
  return { stage: str(a.stage), step: num(a.step, -1), runId: str(a.run_id), question: q, options: arr(a.options).map(option), more: ask(a.more), accept: ask(a.accept) }
}

const TASK_STATES: readonly TaskState[] = ['waiting', 'running', 'red', 'green', 'pass', 'fail', 'parked']

// The view in `text`, or null when it is not a view.json of a version this file knows.
export function parseRunView(text: string): RunView | null {
  let raw: unknown
  try {
    raw = JSON.parse(text)
  } catch {
    return null
  }
  const v = obj(raw)
  if (v.version !== VIEW_VERSION) return null
  const r = obj(v.run)
  const g = obj(v.guard)
  const n = obj(v.next)
  const restart = question(v.restart)
  const drift = obj(v.drift)
  const plan = obj(v.plan)
  const build = obj(v.build)
  const usage = obj(v.usage)
  const time = obj(v.time)
  return {
    run:
      v.run === null || typeof r.stage !== 'string'
        ? null
        : {
            id: str(r.id),
            step: num(r.step, -1),
            slug: str(r.slug),
            title: str(r.title, str(r.slug)),
            command: str(r.command, 'temper'),
            stage: r.stage,
            mode: str(r.mode, 'interactive'),
            complexity: strOrNull(r.complexity),
            branch: strOrNull(r.branch),
            spec: str(r.spec),
            parked: strOrNull(r.parked),
          },
    stages: arr(v.stages).map(x => {
      const s = obj(x)
      const sk = obj(s.skipped)
      return {
        id: str(s.id),
        label: str(s.label, str(s.id)),
        mark: oneOf(s.mark, ['passed', 'failed', 'skipped', 'here', 'todo'] as const, 'todo'),
        verdict: s.verdict === 'PASS' || s.verdict === 'FAIL' ? s.verdict : null,
        failed: arr(s.failed).map(f => ({ name: str(obj(f).name), detail: str(obj(f).detail) })),
        skipped: s.skipped === undefined || s.skipped === null ? null : { reason: str(sk.reason), by: str(sk.by) },
      }
    }),
    status: str(v.status),
    next: { action: str(n.action, 'none'), stage: str(n.stage), say: str(n.say), calls: strs(n.calls), steps: strs(n.steps) },
    ask: ask(v.ask),
    restart: restart === null ? null : { header: restart.header, question: restart.question, options: arr(obj(v.restart).options).map(option) },
    drift: { header: str(drift.header, 'Scope drift'), prefix: str(drift.prefix, 'Outside the plan:'), options: strs(drift.options) },
    guard:
      typeof g.stage !== 'string'
        ? null
        : {
            stage: g.stage,
            spec: str(g.spec),
            slug: str(g.slug),
            fixRun: g.fix_run === true,
            grouped: g.grouped === true,
            armed: g.armed === true,
            autonomyEnabled: g.autonomy_enabled === true,
            planFiles: strs(g.plan_files),
            step: num(g.step, -1),
            runId: str(g.run_id),
            trivialExit: g.trivial_exit === true,
          },
    plan: {
      approved: plan.approved === true,
      files: strs(plan.files),
      groups: arr(plan.groups).map(x => ({ id: str(obj(x).id), title: str(obj(x).title), files: strs(obj(x).files) })),
    },
    build: {
      groups: arr(build.groups).map(x => {
        const gr = obj(x)
        return {
          id: str(gr.id),
          title: str(gr.title),
          status: str(gr.status, 'pending'),
          verdict: strOrNull(gr.verdict),
          tasks: arr(gr.tasks).map(t => {
            const k = obj(t)
            return { n: num(k.n), title: str(k.title), files: strs(k.files), state: oneOf(k.state, TASK_STATES, 'waiting'), model: strOrNull(k.model), attempts: num(k.attempts) }
          }),
        }
      }),
      integration: strOrNull(build.integration),
    },
    findings: arr(v.findings).map(x => {
      const f = obj(x)
      return {
        id: num(f.id),
        severity: str(f.severity, 'unknown'),
        claim: str(f.claim),
        file: strOrNull(f.file),
        line: numOrNull(f.line),
        state: oneOf(f.state, ['open', 'resolved', 'accepted'] as const, 'open'),
        label: strOrNull(f.label),
      }
    }),
    checks: arr(v.checks).map(x => ({ name: str(obj(x).name), pass: obj(x).pass === true, detail: str(obj(x).detail) })),
    markers: arr(v.check_markers).map(x => {
      const m = obj(x)
      return { name: str(m.name), state: oneOf(m.state, ['pass', 'fail', 'info', 'none'] as const, 'none'), detail: str(m.detail), value: numOrNull(m.value), lines: strs(m.lines) }
    }),
    criteria: arr(v.criteria).map(x => ({ id: str(obj(x).id), priority: str(obj(x).priority), status: str(obj(x).status, 'open'), text: str(obj(x).text), evidence: strs(obj(x).evidence) })),
    loops: arr(v.loops).map(x => {
      const l = obj(x)
      return { from: str(l.from), to: str(l.to), reason: str(l.reason), iteration: num(l.iteration), max: num(l.max), at: str(l.at) }
    }),
    skips: arr(v.skips).map(x => ({ stage: str(obj(x).stage), reason: str(obj(x).reason), by: str(obj(x).by) })),
    usage: {
      tokens: num(usage.tokens),
      ms: num(usage.ms),
      byStage: Object.entries(obj(usage.by_stage)).map(([stage, x]) => ({ stage, tokens: num(obj(x).tokens), ms: num(obj(x).ms), runs: num(obj(x).runs) })),
      byModel: Object.entries(obj(usage.by_model)).map(([model, x]) => ({ model, tokens: num(obj(x).tokens), ms: num(obj(x).ms), runs: num(obj(x).runs) })),
    },
    time: { started: strOrNull(time.started), updated: strOrNull(time.updated) },
  }
}
