// The files a plan allows: `### Files to Create` and `### Files to Modify` tables in
// plan.md plus the `**File:**` lines of tasks.md. Pure.

const HEADING = /^(#{2,6})\s+(.*?)\s*$/
const FILE_SECTION = /^files to (?:create|modify)$/i

// A backticked token that names a path: no spaces, and a dot or a slash.
function pathTokens(text: string): string[] {
  const out: string[] = []
  for (const m of text.matchAll(/`([^`]+)`/g)) {
    const t = (m[1] ?? '').trim()
    if (/^[\w.@\-/*?]+$/.test(t) && (t.includes('/') || t.includes('.')) && t.toLowerCase() !== 'none') out.push(t)
  }
  return out
}

const unique = (xs: readonly string[]): string[] => [...new Set(xs)]

export function parsePlanFiles(plan: string): string[] {
  const out: string[] = []
  let active = false
  let level = 0
  for (const line of plan.split('\n')) {
    const h = HEADING.exec(line)
    if (h) {
      const hashes = (h[1] ?? '').length
      if (active && hashes <= level) active = false
      if (FILE_SECTION.test(h[2] ?? '')) {
        active = true
        level = hashes
      }
      continue
    }
    if (!active || !line.trimStart().startsWith('|')) continue
    const cells = line.split('|')
    out.push(...pathTokens(cells[1] ?? ''))
  }
  return unique(out)
}

export function parseTaskFiles(tasks: string): string[] {
  const out: string[] = []
  for (const line of tasks.split('\n')) {
    const m = /^\s*\*\*File:\*\*\s*(.*)$/.exec(line)
    if (m) out.push(...pathTokens(m[1] ?? ''))
  }
  return unique(out)
}

export function planFileList(plan: string, tasks: string): string[] {
  return unique([...parsePlanFiles(plan), ...parseTaskFiles(tasks)])
}
