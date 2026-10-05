// Readers for the CLI's own files: `.temper/gates.json` (verdicts) and
// `.temper/build-state.json` (which spec and stage the CLI is on). The mod only reads
// them; the CLI owns every verdict. Pure.

import type { Phase } from './events'
import type { Verdicts } from './machine'

const GATED: readonly Phase[] = ['intent', 'plan', 'build', 'review', 'check']

// gates.json is `{ stage: { verdict: 'PASS'|'FAIL', ts: ISO string, ... } }`. Unreadable
// input or a malformed row yields no verdict for that stage.
export function parseGates(text: string): Verdicts {
  let raw: unknown
  try {
    raw = JSON.parse(text)
  } catch {
    return {}
  }
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) return {}
  const out: Verdicts = {}
  for (const stage of GATED) {
    const row = (raw as Record<string, unknown>)[stage]
    if (typeof row !== 'object' || row === null) continue
    const { verdict, ts } = row as { verdict?: unknown; ts?: unknown }
    const ms = typeof ts === 'string' ? Date.parse(ts) : typeof ts === 'number' ? ts : Number.NaN
    if ((verdict === 'PASS' || verdict === 'FAIL') && !Number.isNaN(ms)) out[stage] = { verdict, ts: ms }
  }
  return out
}

export type BuildState = {
  spec: string
  specPath: string
  nextStage: string | null
  task: number | null
  complexity: string | null
  // The run's own branch and the command that started it (the CLI commit gate reads both).
  branch: string | null
  command: string | null
}

export function parseBuildState(text: string): BuildState | null {
  let raw: unknown
  try {
    raw = JSON.parse(text)
  } catch {
    return null
  }
  if (typeof raw !== 'object' || raw === null) return null
  const o = raw as Record<string, unknown>
  if (typeof o.spec !== 'string' || o.spec === '') return null
  const specPath = typeof o.spec_path === 'string' && o.spec_path !== '' ? o.spec_path : `.temper/specs/${o.spec}`
  return {
    spec: o.spec,
    specPath,
    nextStage: typeof o.next_stage === 'string' ? o.next_stage : null,
    complexity: typeof o.complexity === 'string' ? o.complexity : null,
    branch: typeof o.branch === 'string' && o.branch !== '' ? o.branch : null,
    command: typeof o.command === 'string' ? o.command : null,
    task: typeof o.task === 'number' && Number.isInteger(o.task) && o.task >= 1 ? o.task : null,
  }
}

// Where the CLI says the run is, from build-state's `next_stage`: the stage that runs next is the phase
// the person is at. Null when the name is not one the CLI uses, or there is none: then the mod cannot
// tell, and it must not guess (see Snapshot.sync). This is the one source of truth for the phase.
export function cliPhase(next: string | null): Phase | 'done' | null {
  switch (next) {
    case 'intent':
    case 'plan':
    case 'design':
    case 'build':
    case 'review':
    case 'check':
    case 'fix':
    case 'rca':
    case 'commit':
    case 'done':
    case 'eval':
      return phaseFromStage(next)
    default:
      return null
  }
}

// The mod's phase and the CLI's phase say the same thing. Fix is a phase of the mod after a failed check
// (the CLI is still at check); Done after a passed check (the CLI is at check until commit); Design is
// part of Plan.
export function samePhase(mod: Phase | 'done' | null, cli: Phase | 'done'): boolean {
  if (mod === cli) return true
  if (mod === 'fix') return cli === 'check'
  if (mod === 'done') return cli === 'check'
  return false
}

// Where a run the CLI already started stands, from build-state's `next_stage`.
export function phaseFromStage(next: string | null): Phase | 'done' {
  switch (next) {
    case 'plan':
    case 'design':
      return 'plan'
    case 'build':
      return 'build'
    case 'review':
      return 'review'
    case 'check':
      return 'check'
    case 'fix':
    case 'rca':
      return 'fix'
    case 'commit':
    case 'done':
    case 'eval':
      return 'done'
    default:
      return 'intent'
  }
}

export type Finding = { id: string; severity: string; claim: string }

// Open review findings from `.temper/evidence/review.json`: rows with a severity that are
// neither resolved nor accepted. The id is the row's 1-based position, which is what
// `temper evidence accept --id` takes.
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
