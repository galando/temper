// Acceptance criteria: parsed from intent.md with the same rules as scripts/acceptance.py
// (`^(AC-\d+)\s*\[(required|optional)\]:`), merged with the per-criterion status the CLI
// writes to .temper/status.json. Pure.

export type Priority = 'required' | 'optional'

export type Criterion = { id: string; priority: Priority; text: string; deferred: boolean }

export type CriterionStatus = { id: string; priority: string; status: 'passed' | 'open'; evidence: string[] }

export type StatusFile = { criteria: CriterionStatus[]; ts: string }

export type MergedCriterion = Criterion & { status: 'passed' | 'open'; evidence: string[] }

const BULLET = /^\s*-\s+/
const FENCE = /^\s*(`{3,}|~{3,})/
const AC_LINE = /^(AC-\d+)\s*\[(required|optional)\]:\s*(.*)$/
const SOURCE_TAIL = /\s*\((?:source|proposed)[^)]*\)\s*$/

function headingLevel(line: string): number {
  const m = /^(#{1,6})\s/.exec(line)
  return m?.[1]?.length ?? 0
}

// Lines under the first heading named `name`, up to the next heading of the same or
// a higher level. Fenced blocks are passed through, as acceptance.py does.
function sectionLines(lines: readonly string[], name: string): string[] {
  const out: string[] = []
  const target = new RegExp(`^#{1,6}\\s+${name}\\s*$`, 'i')
  let active = false
  let level = 0
  for (const line of lines) {
    const h = headingLevel(line)
    if (h > 0) {
      if (active && h <= level) break
      if (!active && target.test(line)) {
        active = true
        level = h
        continue
      }
    }
    if (active) out.push(line)
  }
  return out
}

export function parseTitle(intent: string): string | null {
  const m = /^#\s+Intent:\s*(.+?)\s*$/m.exec(intent)
  return m?.[1] ?? null
}

export function parseCriteria(intent: string): Criterion[] {
  const lines = sectionLines(intent.split('\n'), 'Success Criteria')
  const items: string[][] = []
  let cur: string[] | null = null
  let inFence = false
  for (const line of lines) {
    if (FENCE.test(line)) {
      inFence = !inFence
      continue
    }
    if (inFence) {
      cur?.push(line)
      continue
    }
    if (BULLET.test(line)) {
      cur = [line]
      items.push(cur)
    } else cur?.push(line)
  }

  const out: Criterion[] = []
  for (const block of items) {
    const first = (block[0] ?? '').replace(BULLET, '').replace(/^\[[ xX]\]\s*/, '').trim()
    if (first.startsWith('{')) continue
    const m = AC_LINE.exec(first)
    if (!m) continue
    out.push({
      id: m[1] ?? '',
      priority: m[2] as Priority,
      text: (m[3] ?? '').replace(SOURCE_TAIL, '').trim(),
      deferred: block.some(l => /^\s*Deferred:/.test(l)),
    })
  }
  return out
}

export function parseStatus(json: string): StatusFile | null {
  let raw: unknown
  try {
    raw = JSON.parse(json)
  } catch {
    return null
  }
  if (typeof raw !== 'object' || raw === null || !Array.isArray((raw as { criteria?: unknown }).criteria)) return null
  const rows: CriterionStatus[] = []
  for (const r of (raw as { criteria: unknown[] }).criteria) {
    if (typeof r !== 'object' || r === null) continue
    const o = r as Record<string, unknown>
    if (typeof o.id !== 'string') continue
    rows.push({
      id: o.id,
      priority: typeof o.priority === 'string' ? o.priority : 'required',
      status: o.status === 'passed' ? 'passed' : 'open',
      evidence: Array.isArray(o.evidence) ? o.evidence.filter((e): e is string => typeof e === 'string') : [],
    })
  }
  const ts = (raw as { ts?: unknown }).ts
  return { criteria: rows, ts: typeof ts === 'string' ? ts : '' }
}

export function mergeCriteria(criteria: readonly Criterion[], status: StatusFile | null): MergedCriterion[] {
  const byId = new Map<string, CriterionStatus>()
  for (const s of status?.criteria ?? []) byId.set(s.id, s)
  return criteria.map(c => {
    const s = byId.get(c.id)
    return { ...c, status: s?.status ?? 'open', evidence: s?.evidence ?? [] }
  })
}

export function progress(merged: readonly MergedCriterion[]): { passed: number; total: number; passedIds: string[] } {
  const passedIds = merged.filter(c => c.status === 'passed').map(c => c.id)
  return { passed: passedIds.length, total: merged.length, passedIds }
}
