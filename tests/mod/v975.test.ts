// 9.7.5 in the mod: the band while an answer is carried out, the stage refusals that name the run and point at a worktree, the
// small change window, the Pipeline stage, the person-only calls and the refusal to turn Temper off during a run. Pure rules.
import { describe, expect, test } from 'claude-code/testing'

import { buildView } from '../../hooks/temper-mod/core/view'
import { evaluate } from '../../hooks/temper-mod/core/rules'
import type { RuleContext, RunFacts } from '../../hooks/temper-mod/core/rules'
import { parseRunView } from '../../hooks/temper-mod/core/runview'
import { VIEWS } from '../../scripts/selftest/view-fixtures'

const run = (o: Partial<RunFacts> = {}): RunFacts => ({ stage: 'build', step: 3, specDir: '.temper/specs/pw', planFiles: ['src/app.ts'], groupedActive: false, trivialExit: false, ...o })
const ctx = (r: RunFacts | null, allowed: string[] = []): RuleContext => ({ run: r, allowed, root: '/repo', drift: { added: [], allowOnce: [] }, restart: false, cli: '/p/scripts/temper' }) as unknown as RuleContext
const write = (c: RuleContext, path: string) => evaluate(c, { tool: 'Write', input: { file_path: `/repo/${path}` } } as never)
const bash = (c: RuleContext, command: string) => evaluate(c, { tool: 'Bash', input: { command } } as never)
const text = (r: unknown): string => (r as { deny?: string }).deny ?? ''

describe('9.7.5: stage refusals name the run and point at a worktree', () => {
  test('Review: the refusal names the run and the stage, keeps its Next step, and points at the small change', () => {
    const t = text(write(ctx(run({ stage: 'review' })), 'src/other.ts'))
    expect(t).toContain('The run pw (Review stage) owns this folder.')
    expect(t).toContain('claude --worktree <name>')
    expect(t).toContain('choose Make a small change at the next Temper gate question')
    expect(t).toContain('Next: ')
  })
  test('Intent, Plan and Design: the small change is possible from Build on', () => {
    for (const stage of ['intent', 'plan', 'design'] as const) {
      const t = text(write(ctx(run({ stage })), 'src/other.ts'))
      expect(t).toContain('owns this folder.')
      expect(t).toContain('Make a small change is possible from Build on.')
    }
  })
})

describe('9.7.5: the small change window', () => {
  test('a code write passes inside an open window at its stage, and only there', () => {
    expect('deny' in write(ctx(run({ stage: 'check', adhocStage: 'check' })), 'src/other.ts')).toBe(false)
    expect('deny' in write(ctx(run({ stage: 'check', adhocStage: 'review' })), 'src/other.ts')).toBe(true)
    expect('deny' in write(ctx(run({ stage: 'commit', adhocStage: 'commit' })), 'src/other.ts')).toBe(false)
  })
  test('a window never opens Intent, Plan or Design to code', () => {
    expect('deny' in write(ctx(run({ stage: 'plan', adhocStage: 'plan' })), 'src/other.ts')).toBe(true)
  })
  test('Pipeline refuses a code write unless its window is open', () => {
    expect(text(write(ctx(run({ stage: 'pipeline' })), 'src/other.ts'))).toContain('Pipeline stage')
    expect('deny' in write(ctx(run({ stage: 'pipeline', adhocStage: 'pipeline' })), 'src/other.ts')).toBe(false)
    expect('deny' in write(ctx(run({ stage: 'pipeline' })), '.temper/specs/pw/pipeline-context.json')).toBe(false)
  })
})

describe('9.7.5: the calls only the person may cause', () => {
  const CLI = '/p/scripts/temper'
  const calls: Array<[string, string]> = [
    ['plan review', `${CLI} plan review --answer 'Narrow the focus'`],
    ['task confirm', `${CLI} task confirm 2 --by 'Dana'`],
    ['task accept', `${CLI} task accept 2 --reason 'built before'`],
    ['adhoc open', `${CLI} adhoc open --stage check --reason 'a fix'`],
    ['state set branch', `${CLI} state set branch feature/pw-2`],
  ]
  for (const [name, call] of calls) {
    test(`${name} is refused with no answer, and passes as the call an answer maps to`, () => {
      expect('deny' in bash(ctx(run()), call)).toBe(true)
      const written = call.replace(/'[^']*'/g, m => (name === 'plan review' ? m : '{x}'))
      expect('deny' in bash(ctx(run(), [written]), call)).toBe(false)
    })
  }
  test('adhoc close needs no answer', () => {
    expect('deny' in bash(ctx(run()), `${CLI} adhoc close`)).toBe(false)
  })
})

describe('9.7.5: turning Temper off is not done during a run', () => {
  test('temper guards uninstall and install.sh --uninstall are refused while a run is active, and pass with none', () => {
    for (const cmd of ['/p/scripts/temper guards uninstall', 'bash /p/scripts/guards/install.sh --uninstall']) {
      expect(text(bash(ctx(run()), cmd))).toContain('turning the commit gate off')
      expect('deny' in bash(ctx(null), cmd)).toBe(false)
    }
  })
})

describe('9.7.5: the band while the answer is carried out', () => {
  const view = parseRunView(JSON.stringify((VIEWS as Record<string, unknown>)['build-fail']))
  test('a failed check shows its rows and a red chip; once the answer is chosen they are gone', () => {
    expect(view).not.toBeNull()
    const shown = buildView({ view: view!, enforcement: 'on', answer: null, decisions: [] } as never)
    expect(shown.failedChecks.length).toBeGreaterThan(0)
    expect(shown.stages.find(s => s.id === 'build')?.failed).toBe(true)
    const chosen = buildView({ view: view!, enforcement: 'on', answer: { label: 'Run Build again', move: 'redo', calls: [], steps: [] }, decisions: [] } as never)
    expect(chosen.wait).toBe('chosen')
    expect(chosen.failedChecks).toEqual([])
    expect(chosen.detail.join('\n')).not.toContain('Failed:')
    expect(chosen.stages.find(s => s.id === 'build')?.failed).toBe(false)
  })
})

describe('9.7.5: every pull request is a draft', () => {
  const CLI = '/p/scripts/temper'
  test('gh pr create without --draft and any gh pr ready are refused while a run is active; a draft passes', () => {
    expect(text(bash(ctx(run()), "gh pr create --head f --base main --title 't' --body-file b"))).toContain('every pull request is a draft')
    expect(text(bash(ctx(run()), 'gh pr ready 12'))).toContain('never runs gh pr ready')
    expect('deny' in bash(ctx(run()), "gh pr create --head f --base main --title 't' --body-file b --draft")).toBe(false)
    expect(CLI).toContain('temper')
  })
})

describe('9.7.5: the command the CLI wrote whole for a branch switch', () => {
  const carry = 't="$(mktemp -d)" && cp -R .temper/specs/pw/. "$t"/ && { git restore --source=HEAD --worktree -- .temper/specs/pw 2>/dev/null; git clean -fdq -- .temper/specs/pw ; } ; if git checkout feature/pw; then mkdir -p .temper/specs/pw && cp -R "$t"/. .temper/specs/pw/ && rm -rf "$t"; else exit 1; fi'
  test('passes character for character when the person chose it, and not otherwise or when changed', () => {
    expect('deny' in bash(ctx(run()), carry)).toBe(true)
    expect('deny' in bash(ctx(run(), [carry]), carry)).toBe(false)
    expect('deny' in bash(ctx(run(), [carry]), carry.replace('feature/pw', 'main'))).toBe(true)
  })
  test('does not pass when it writes another Temper path than the spec folder', () => {
    const other = carry.replace('cp -R "$t"/. .temper/specs/pw/', 'cp -R "$t"/. .temper/gates.json')
    expect('deny' in bash(ctx(run(), [other]), other)).toBe(true)
  })
})
