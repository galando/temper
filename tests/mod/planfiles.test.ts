import { describe, expect, test } from 'claude-code/testing'

import { normalizePath } from '../../hooks/temper-mod/core/paths'
import { parsePlanFiles, parseTaskFiles, planFileList } from '../../hooks/temper-mod/core/planfiles'
import { spec_plan_files } from './fixtures/spec-plan-files'
import { spec_tasks } from './fixtures/spec-tasks'

describe('plan.md tables', () => {
  test('reads the first cell of every Files to Create and Files to Modify row', () => {
    const files = parsePlanFiles(spec_plan_files)
    expect(files).toContain('hooks/temper-mod/register.tsx')
    expect(files).toContain('hooks/temper-mod/core/machine.ts')
    expect(files).toContain('scripts/temper')
    expect(files).toContain('templates/temper.config.default')
    expect(files).not.toContain('Scenario')
    expect(files.every(f => !/\s/.test(f))).toBe(true)
  })

  test('ignores tables under other headings and the header and divider rows', () => {
    const text = [
      '### Files to Modify',
      '',
      '| File | Change |',
      '|---|---|',
      '| `a/b.ts` | edit |',
      '| `c.md` and `d.md` | docs |',
      '',
      '### Notes',
      '| `not/this.ts` | no |',
    ].join('\n')
    expect(parsePlanFiles(text)).toEqual(['a/b.ts', 'c.md', 'd.md'])
  })

  test('empty or table-less text gives nothing', () => {
    expect(parsePlanFiles('')).toEqual([])
    expect(parsePlanFiles('### Files to Create\n\nnone')).toEqual([])
  })
})

describe('tasks.md File lines', () => {
  test('reads every backticked path on each **File:** line, once', () => {
    const files = parseTaskFiles(spec_tasks)
    expect(files).toContain('scripts/temper')
    expect(files).toContain('.gitignore')
    expect(files).toContain('hooks/temper-mod/core/events.ts')
    expect(files).toContain('demo/password-reset/')
    expect(files).toContain('tests/mod/fixtures/')
    expect(new Set(files).size).toBe(files.length)
  })

  test('"none" and prose are not paths', () => {
    expect(parseTaskFiles('**File:** none\n**File:** `a.ts`, plus some words')).toEqual(['a.ts'])
  })
})

describe('planFileList', () => {
  test('unions plan and task files without duplicates', () => {
    const list = planFileList('### Files to Create\n| `a.ts` | x |\n', '**File:** `a.ts`, `b.ts`')
    expect(list).toEqual(['a.ts', 'b.ts'])
  })
})

// The engine reports the real folder (/private/tmp/x on macOS); a tool call may name the same folder
// through the link (/tmp/x). Both are inside the project.
describe('normalizePath with a symlinked project folder', () => {
  test('a path under /tmp is inside a root under /private/tmp', () => {
    expect(normalizePath('/tmp/pr-demo/src/users.js', '/private/tmp/pr-demo')).toBe('src/users.js')
    expect(normalizePath('/private/tmp/pr-demo/src/users.js', '/private/tmp/pr-demo')).toBe('src/users.js')
    expect(normalizePath('/private/var/x/a.ts', '/private/var/x')).toBe('a.ts')
    expect(normalizePath('/var/x/a.ts', '/private/var/x')).toBe('a.ts')
  })
  test('a path outside the project stays absolute', () => {
    expect(normalizePath('/tmp/other/src/users.js', '/private/tmp/pr-demo')).toBe('/tmp/other/src/users.js')
    expect(normalizePath('/tmp/pr-demo-2/a.js', '/private/tmp/pr-demo')).toBe('/tmp/pr-demo-2/a.js')
  })
})
