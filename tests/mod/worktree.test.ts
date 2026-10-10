// Grouped Build: the mod guards groups.json and usage.json, maps writes in a group worktree of THIS run through the
// same phase rule, and refuses agent writes to the run's tasks.md while a grouped Build run is active.
import { describe, expect, test } from 'claude-code/testing'

import { loadSnapshot } from '../../hooks/temper-mod/adapter'
import type { Io } from '../../hooks/temper-mod/adapter'
import { classifyBash, protectedKind } from '../../hooks/temper-mod/core/bash'
import { evaluate } from '../../hooks/temper-mod/core/rules'
import type { RuleContext, RuleResult } from '../../hooks/temper-mod/core/rules'
import { SPEC, runFiles } from './run-files'
import { stateAt } from './helpers'

const ctx: RuleContext = { specDir: SPEC, planFiles: ['src/app.ts', 'hooks/core/*.ts', 'docs/guide/'] }
const grouped: RuleContext = { ...ctx, groupedActive: true }
const WT = '.claude/worktrees/temper-pw-G1'
const isDeny = (r: RuleResult): r is Extract<RuleResult, { deny: string }> => 'deny' in r
const write = (c: RuleContext, path: string, phase: 'build' | 'fix' = 'build') =>
  evaluate(stateAt(phase), c, { tool: 'Write', input: { file_path: path } })

describe('groups.json and usage.json are CLI-only state', () => {
  test('protectedKind names both as state', () => {
    expect(protectedKind('.temper/groups.json')).toBe('state')
    expect(protectedKind('.temper/usage.json')).toBe('state')
    expect(protectedKind('/repo/.TEMPER/Groups.json')).toBe('state')
    expect(protectedKind(`${WT}/.temper/groups.json`)).toBe('state')
  })

  test('a Write or Edit to either is denied in every phase, with a CLI next step', () => {
    for (const phase of ['plan', 'build', 'review', 'check', 'fix'] as const) {
      for (const f of ['.temper/groups.json', '.temper/usage.json']) {
        const r = write(grouped, f, phase)
        expect(isDeny(r)).toBe(true)
        if (isDeny(r)) {
          expect(r.deny).toContain('Next: ')
          expect(r.deny).not.toContain('scope drift')
          expect(r.deny).toContain('temper CLI')
        }
      }
    }
  })

  test('a Bash redirect, copy or in-place edit of either is flagged; a read is not', () => {
    const flagged = (c: string) => classifyBash(c).protectedWrites.length > 0
    expect(flagged('echo {} > .temper/groups.json')).toBe(true)
    expect(flagged('cp x.json .temper/usage.json')).toBe(true)
    expect(flagged('sed -i s/a/b/ .temper/groups.json')).toBe(true)
    expect(flagged('cat .temper/groups.json')).toBe(false)
    expect(flagged('cat .temper/usage.json')).toBe(false)
  })
})

describe('writes in a group worktree of this run are judged by their worktree-relative path', () => {
  test('a planned source file is allowed', () => {
    expect('allow' in write(grouped, `${WT}/src/app.ts`)).toBe(true)
    expect('allow' in write(grouped, `${WT}/hooks/core/x.ts`, 'fix')).toBe(true)
  })

  test('a test file and the plan files are allowed, like outside the worktree', () => {
    expect('allow' in write(grouped, `${WT}/tests/unit/a.test.ts`)).toBe(true)
    expect('allow' in write(grouped, `${WT}/docs/guide/intro.md`)).toBe(true)
  })

  test('an unplanned file is denied as drift, naming the path', () => {
    const r = write(grouped, `${WT}/src/billing.ts`)
    expect(isDeny(r)).toBe(true)
    if (isDeny(r)) {
      expect(r.deny).toContain('scope drift')
      expect(r.deny).toContain('Next: ')
    }
  })

  test('a file added to the plan by a drift decision is allowed inside the worktree too', () => {
    const s = stateAt('build', [{ type: 'drift', path: 'src/extra.ts', choice: 'add', reason: 'needed', origin: 'person', author: 'galando' }])
    expect('allow' in evaluate(s, grouped, { tool: 'Write', input: { file_path: `${WT}/src/extra.ts` } })).toBe(true)
    expect(isDeny(write(grouped, `${WT}/src/extra.ts`))).toBe(true)
  })

  test('the mapping is the same with or without the grouped flag (it is a path rule)', () => {
    expect('allow' in write(ctx, `${WT}/src/app.ts`)).toBe(true)
    expect(isDeny(write(ctx, `${WT}/src/billing.ts`))).toBe(true)
  })

  test('a `..` after the prefix is normalized first: it cannot reach a path the plan does not name', () => {
    expect(isDeny(write(grouped, `${WT}/src/../../../../src/billing.ts`))).toBe(true)
    expect(isDeny(write(grouped, `${WT}/../temper-other-G1/src/app.ts`))).toBe(true)
  })

  test('a protected path inside the worktree is still protected', () => {
    expect(isDeny(write(grouped, `${WT}/.temper/gates.json`))).toBe(true)
    expect(isDeny(write(grouped, `${WT}/.temper/groups.json`))).toBe(true)
    expect(isDeny(write(grouped, `${WT}/.claude/temper.config`))).toBe(true)
  })

  test('an absolute path under the project root maps the same way', () => {
    const r = evaluate(stateAt('build'), { ...grouped, root: '/repo' }, { tool: 'Edit', input: { file_path: `/repo/${WT}/src/app.ts` } })
    expect('allow' in r).toBe(true)
    const d = evaluate(stateAt('build'), { ...grouped, root: '/repo' }, { tool: 'Edit', input: { file_path: `/repo/${WT}/src/billing.ts` } })
    expect(isDeny(d)).toBe(true)
  })
})

describe('any other worktree prefix gets no special treatment', () => {
  const others = [
    '.claude/worktrees/temper-other-G1',
    '.claude/worktrees/temper-pw-G',
    '.claude/worktrees/temper-pw-G1x',
    '.claude/worktrees/temper-pw-G1-extra',
    '.claude/worktrees/temper-pwx-G1',
    '.claude/worktrees/pw-G1',
    '.claude/worktrees/temper-pw-g1',
    'worktrees/temper-pw-G1',
    'other/.claude/worktrees/temper-pw-G1',
  ]
  for (const prefix of others) {
    test(`${prefix}/src/app.ts is judged as an ordinary path and denied as drift`, () => {
      const r = write(grouped, `${prefix}/src/app.ts`)
      expect(isDeny(r)).toBe(true)
      if (isDeny(r)) expect(r.deny).toContain('scope drift')
    })
  }

  test('a planned directory entry does not make a foreign worktree writable by the mapping', () => {
    expect(isDeny(write(grouped, '.claude/worktrees/temper-other-G2/docs/guide/intro.md'))).toBe(true)
  })

  test('a two-digit group number of this run maps', () => {
    expect('allow' in write(grouped, '.claude/worktrees/temper-pw-G12/src/app.ts')).toBe(true)
  })
})

describe('while a grouped Build run is active, the run tasks.md is the CLI\'s', () => {
  const tasks = `${SPEC}/tasks.md`

  test('Write, Edit and NotebookEdit to the run tasks.md are denied in Build and Fix', () => {
    for (const phase of ['build', 'fix'] as const) {
      for (const [tool, input] of [['Write', { file_path: tasks }], ['Edit', { file_path: tasks }], ['NotebookEdit', { notebook_path: tasks }]] as const) {
        const r = evaluate(stateAt(phase), grouped, { tool, input })
        expect(isDeny(r)).toBe(true)
        if (isDeny(r)) {
          expect(r.deny.startsWith('Temper: ')).toBe(true)
          expect(r.deny).toContain('Next: ')
          expect(r.deny).toContain('tasks.md')
        }
      }
    }
  })

  test('the run tasks.md written through the worktree copy path is denied as well', () => {
    expect(isDeny(write(grouped, `${WT}/${tasks}`))).toBe(true)
  })

  test('per-task mode (no groups.json) keeps today\'s allowance', () => {
    expect('allow' in write(ctx, tasks)).toBe(true)
    expect('allow' in write({ ...ctx, groupedActive: false }, tasks)).toBe(true)
  })

  test('Plan phase may still write tasks.md even when a stale groups.json is present', () => {
    expect('allow' in evaluate(stateAt('plan'), grouped, { tool: 'Write', input: { file_path: tasks } })).toBe(true)
  })

  test('other spec files stay writable during a grouped Build', () => {
    expect('allow' in write(grouped, `${SPEC}/build-context.json`)).toBe(true)
    expect('allow' in write(grouped, `${SPEC}/plan.md`)).toBe(true)
  })
})

describe('the adapter reads groups.json presence into the snapshot', () => {
  const ioWith = (files: Record<string, string>): Io => ({
    read: async path => files[path] ?? null,
    list: async () => [],
    write: async () => undefined,
    storeGet: async () => undefined,
    storeSet: async () => undefined,
    version: async () => '2.1.300',
    setRun: async () => undefined,
    setMode: async () => undefined,
    pause: async () => undefined,
  })

  test('groups.json present: groupedActive is true', async () => {
    const snap = await loadSnapshot(ioWith({ ...runFiles({ nextStage: 'build' }), '.temper/groups.json': '{}' }), {})
    expect(snap.groupedActive).toBe(true)
  })

  test('groups.json absent: groupedActive is false', async () => {
    const snap = await loadSnapshot(ioWith(runFiles({ nextStage: 'build' })), {})
    expect(snap.groupedActive).toBe(false)
  })
})
