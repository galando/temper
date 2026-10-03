import { describe, expect, test } from 'claude-code/testing'

import type { Phase } from '../../hooks/temper-mod/core/events'
import { evaluate } from '../../hooks/temper-mod/core/rules'
import type { RuleContext, RuleResult } from '../../hooks/temper-mod/core/rules'
import { ONLY_USER, initialState } from '../../hooks/temper-mod/core/machine'
import { person, stateAt } from './helpers'

const SPEC = '.temper/specs/pw'
const ctx: RuleContext = { specDir: SPEC, planFiles: ['src/app.ts', 'hooks/core/*.ts', 'docs/guide/'] }

const WRITE_TOOLS = ['Write', 'Edit', 'NotebookEdit'] as const
const inputFor = (tool: string, path: string) => (tool === 'NotebookEdit' ? { notebook_path: path } : { file_path: path })

const isDeny = (r: RuleResult): r is Extract<RuleResult, { deny: string }> => 'deny' in r

// One allowed and one disallowed path per phase (mods-plan 3.4 table).
const TABLE: Array<{ phase: Phase; allowed: string; disallowed: string }> = [
  { phase: 'intent', allowed: `${SPEC}/intent.md`, disallowed: 'src/app.ts' },
  { phase: 'plan', allowed: `${SPEC}/plan.md`, disallowed: 'src/app.ts' },
  { phase: 'build', allowed: 'src/app.ts', disallowed: 'src/billing.ts' },
  { phase: 'review', allowed: `${SPEC}/review-notes.md`, disallowed: 'src/app.ts' },
  { phase: 'check', allowed: `${SPEC}/check-notes.md`, disallowed: 'src/app.ts' },
  { phase: 'fix', allowed: 'src/app.ts', disallowed: 'src/billing.ts' },
]

describe('phase path table: 6 phases x 3 tools x allowed and disallowed', () => {
  for (const row of TABLE) {
    for (const tool of WRITE_TOOLS) {
      test(`${row.phase} ${tool} allows ${row.allowed}`, () => {
        const r = evaluate(stateAt(row.phase), ctx, { tool, input: inputFor(tool, row.allowed) })
        expect('allow' in r).toBe(true)
      })
      test(`${row.phase} ${tool} denies ${row.disallowed} with a Next clause`, () => {
        const r = evaluate(stateAt(row.phase), ctx, { tool, input: inputFor(tool, row.disallowed) })
        expect(isDeny(r)).toBe(true)
        if (isDeny(r)) {
          expect(r.deny.startsWith('Temper: ')).toBe(true)
          expect(r.deny).toContain('Next: ')
          expect(r.deny).toContain(row.disallowed)
        }
      })
    }
  }
})

describe('specific denials', () => {
  test('Plan phase refuses a source write with the exact next action', () => {
    const r = evaluate(stateAt('plan'), ctx, { tool: 'Write', input: { file_path: 'src/app.ts' } })
    expect(r).toEqual({
      deny:
        'Temper: Plan phase. Writing src/app.ts is not allowed until the plan is approved. ' +
        'Next: finish plan.md and tasks.md, then ask the user to approve (key 1 or /temper approve).',
    })
  })

  test('Plan allows the spec files, ADRs and context files but not other spec files', () => {
    const s = stateAt('plan')
    for (const p of [`${SPEC}/intent.md`, `${SPEC}/tasks.md`, `${SPEC}/design.md`, `${SPEC}/plan-context.json`, 'docs/decisions/0009-mods.md']) {
      expect('allow' in evaluate(s, ctx, { tool: 'Write', input: { file_path: p } })).toBe(true)
    }
    expect(isDeny(evaluate(s, ctx, { tool: 'Write', input: { file_path: `${SPEC}/report.md` } }))).toBe(true)
  })

  test('Build allows test files and plan globs and directories', () => {
    const s = stateAt('build')
    for (const p of ['src/app.test.ts', 'tests/mod/x.test.ts', 'hooks/core/a.ts', 'docs/guide/page.md', 'pkg/test_thing.py', `${SPEC}/tasks.md`]) {
      expect('allow' in evaluate(s, ctx, { tool: 'Edit', input: { file_path: p } })).toBe(true)
    }
    expect(isDeny(evaluate(s, ctx, { tool: 'Edit', input: { file_path: 'hooks/core/sub/a.ts' } }))).toBe(true)
  })

  test('absolute paths inside the root and traversal are normalised', () => {
    const c = { ...ctx, root: '/repo' }
    const s = stateAt('plan')
    expect('allow' in evaluate(s, c, { tool: 'Write', input: { file_path: `/repo/${SPEC}/plan.md` } })).toBe(true)
    expect(isDeny(evaluate(s, c, { tool: 'Write', input: { file_path: `/repo/${SPEC}/../../../src/app.ts` } }))).toBe(true)
  })

  test('Review allows a file with an active Fix finding action', () => {
    const c = { ...ctx, fixFiles: ['src/app.ts'] }
    expect('allow' in evaluate(stateAt('review'), c, { tool: 'Edit', input: { file_path: 'src/app.ts' } })).toBe(true)
    expect(isDeny(evaluate(stateAt('review'), c, { tool: 'Edit', input: { file_path: 'src/other.ts' } }))).toBe(true)
  })

  test('other tools and no active run pass through', () => {
    expect('allow' in evaluate(stateAt('plan'), ctx, { tool: 'Read', input: { file_path: 'src/app.ts' } })).toBe(true)
    expect('allow' in evaluate(stateAt('plan'), ctx, { tool: 'Grep', input: {} })).toBe(true)
    expect('allow' in evaluate(initialState(), ctx, { tool: 'Write', input: { file_path: 'src/app.ts' } })).toBe(true)
    expect('allow' in evaluate(stateAt('plan', [{ type: 'pause', ...person }]), ctx, { tool: 'Write', input: { file_path: 'src/app.ts' } })).toBe(true)
  })
})

describe('scope drift in Build and Fix', () => {
  test('a path outside the plan is denied naming scope drift, the choices and the path', () => {
    const r = evaluate(stateAt('build'), ctx, { tool: 'Edit', input: { file_path: 'src/billing.ts' } })
    expect(isDeny(r)).toBe(true)
    if (isDeny(r)) {
      expect(r.deny).toContain('scope drift')
      expect(r.deny).toContain('src/billing.ts')
      expect(r.deny).toContain('add to plan')
      expect(r.deny).toContain('revert')
      expect(r.deny).toContain('allow once')
      expect(r.drift).toBe('src/billing.ts')
    }
  })

  test('Add to plan lets the path through for good; Allow once lets one call through', () => {
    const added = stateAt('build', [{ type: 'drift', path: 'src/billing.ts', choice: 'add', reason: '', ...person }])
    expect('allow' in evaluate(added, ctx, { tool: 'Edit', input: { file_path: 'src/billing.ts' } })).toBe(true)
    const once = stateAt('build', [{ type: 'drift', path: 'src/billing.ts', choice: 'allow-once', reason: 'hotfix', ...person }])
    const r = evaluate(once, ctx, { tool: 'Edit', input: { file_path: 'src/billing.ts' } })
    expect(r).toEqual({ allow: true, consume: 'drift', driftPath: 'src/billing.ts' })
  })

  test('Revert alone does not allow the path', () => {
    const reverted = stateAt('build', [{ type: 'drift', path: 'src/billing.ts', choice: 'revert', reason: '', ...person }])
    expect(isDeny(evaluate(reverted, ctx, { tool: 'Edit', input: { file_path: 'src/billing.ts' } }))).toBe(true)
  })
})

describe('Temper state paths and forged decisions', () => {
  const guarded = ['.temper/specs/pw/events/1-x-1.json', '.temper/gates.json', '.temper/status.json', '.temper/overrides.json']

  test('every phase and write tool refuses Temper state files', () => {
    for (const row of TABLE) {
      for (const tool of WRITE_TOOLS) {
        for (const p of guarded) {
          const r = evaluate(stateAt(row.phase), ctx, { tool, input: inputFor(tool, p) })
          expect(isDeny(r)).toBe(true)
        }
      }
    }
  })

  test('an events file write is a forged approval', () => {
    const r = evaluate(stateAt('plan'), ctx, { tool: 'Write', input: { file_path: '.temper/specs/pw/events/1-x-1.json' } })
    expect(r).toEqual({ deny: ONLY_USER })
  })

  test('hand-written verdict files are refused with the CLI as the next action', () => {
    const r = evaluate(stateAt('check'), ctx, { tool: 'Write', input: { file_path: '.temper/gates.json' } })
    expect(isDeny(r) && r.deny).toContain('Next: run scripts/temper gate')
  })

  test('decision CLI calls through Bash need an unconsumed human event', () => {
    const call = { tool: 'Bash', input: { command: 'temper override plan --reason ok' } }
    expect(evaluate(stateAt('plan'), ctx, call)).toEqual({ deny: ONLY_USER })
    expect(evaluate(stateAt('plan'), { ...ctx, humanDecisions: { override: 1 } }, call)).toEqual({ allow: true, consume: 'override' })
    const accept = { tool: 'Bash', input: { command: 'scripts/temper evidence accept --stage review --id 1 --reason x' } }
    expect(evaluate(stateAt('review'), ctx, accept)).toEqual({ deny: ONLY_USER })
    expect(evaluate(stateAt('review'), { ...ctx, humanDecisions: { accept: 1 } }, accept)).toEqual({ allow: true, consume: 'accept' })
  })

  test('state advance is guarded in Intent and Plan only', () => {
    const call = { tool: 'Bash', input: { command: 'temper state advance build' } }
    expect(evaluate(stateAt('plan'), ctx, call)).toEqual({ deny: ONLY_USER })
    expect('allow' in evaluate(stateAt('build'), ctx, call)).toBe(true)
  })

  test('Bash writes that name a Temper state path are denied', () => {
    const r = evaluate(stateAt('check'), ctx, { tool: 'Bash', input: { command: 'echo {} > .temper/gates.json' } })
    expect(isDeny(r)).toBe(true)
    const e = evaluate(stateAt('plan'), ctx, { tool: 'Bash', input: { command: 'cp x .temper/specs/pw/events/9-x-9.json' } })
    expect(e).toEqual({ deny: ONLY_USER })
  })
})

describe('git commit gate', () => {
  const commit = { tool: 'Bash', input: { command: 'git add -A && git commit -m wip' } }

  test('refused with the exact reason while Check has not passed', () => {
    expect(evaluate(stateAt('check'), ctx, commit)).toEqual({
      deny: 'Temper: commit blocked, Check has not passed. Next: run the checks (key 1 in Check or /temper check).',
    })
  })

  test('every unfinished phase refuses and names its next step', () => {
    for (const phase of ['intent', 'plan', 'build', 'review', 'fix'] as const) {
      const r = evaluate(stateAt(phase), ctx, commit)
      expect(isDeny(r) && r.deny.startsWith('Temper: commit blocked, Check has not passed. Next: ')).toBe(true)
    }
  })

  test('allowed once the run is Done (check passed or overridden)', () => {
    const done = stateAt('check', [{ type: 'checkResult', result: 'pass', origin: 'system' }])
    expect(done.phase).toBe('done')
    expect('allow' in evaluate(done, ctx, { tool: 'Bash', input: { command: 'git commit -m feat' } })).toBe(true)
    const overridden = stateAt('check', [{ type: 'override', phase: 'check', reason: 'ship it', ...person }])
    expect('allow' in evaluate(overridden, ctx, commit)).toBe(true)
  })

  test('no active run or a paused run does not block commits', () => {
    expect('allow' in evaluate(initialState(), ctx, commit)).toBe(true)
    expect('allow' in evaluate(stateAt('build', [{ type: 'pause', ...person }]), ctx, commit)).toBe(true)
  })

  test('ordinary Bash passes through', () => {
    expect('allow' in evaluate(stateAt('plan'), ctx, { tool: 'Bash', input: { command: 'npm test' } })).toBe(true)
  })
})
