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

// "Task N of M" for the system prompt. M counts the `### Task N:` headings of tasks.md.
// A task is done when its block carries ticked `- [x]` rows and no open `- [ ]` row
// (the Build stage ticks a task's box when its Validate passes). N is the first task
// not done, or M once all are. `override` (build-state's numeric `task`) wins when set.
function taskBlocks(tasksMd: string): string[][] {
  const tasks: string[][] = []
  let isTask = false
  for (const line of tasksMd.split('\n')) {
    // `## Task 1:` and `### Task 1:` both start a task.
    if (/^#{2,3}\s+Task\s+\d+/.test(line)) {
      tasks.push([])
      isTask = true
    } else if (/^#{1,3}\s/.test(line)) isTask = false
    else if (isTask) tasks[tasks.length - 1]?.push(line)
  }
  return tasks
}

const taskDone = (b: string[]): boolean => b.some(l => /^\s*-\s+\[[xX]\]/.test(l)) && !b.some(l => /^\s*-\s+\[ \]/.test(l))

// How many tasks are not done yet; null when tasks.md has no task headings (nothing is known).
export function tasksLeft(tasksMd: string): number | null {
  const tasks = taskBlocks(tasksMd)
  return tasks.length === 0 ? null : tasks.filter(b => !taskDone(b)).length
}

export function taskProgress(tasksMd: string, override: number | null = null): { n: number; of: number } | null {
  const tasks = taskBlocks(tasksMd)
  if (tasks.length === 0) return null
  const done = taskDone
  let first = tasks.findIndex(b => !done(b))
  if (first < 0) first = tasks.length - 1
  const n = override !== null ? Math.min(Math.max(override, 1), tasks.length) : first + 1
  return { n, of: tasks.length }
}
