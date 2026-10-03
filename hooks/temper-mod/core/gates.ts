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

export type BuildState = { spec: string; specPath: string; nextStage: string | null; task: number | null }

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
    task: typeof o.task === 'number' && Number.isInteger(o.task) && o.task >= 1 ? o.task : null,
  }
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
