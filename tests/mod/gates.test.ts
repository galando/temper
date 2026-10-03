import { describe, expect, test } from 'claude-code/testing'

import { MIN_VERSION, versionAtLeast } from '../../hooks/temper-mod/core/config'
import { parseBuildState, parseGates, phaseFromStage } from '../../hooks/temper-mod/core/gates'
import { taskProgress } from '../../hooks/temper-mod/core/planfiles'
import { spec_tasks } from './fixtures/spec-tasks'

describe('parseGates', () => {
  test('reads verdict and ISO timestamp per stage, ignores other keys and bad rows', () => {
    const v = parseGates(
      JSON.stringify({
        intent: { verdict: 'PASS', ts: '2026-10-03T09:04:58Z', requirements: [] },
        commit: { verdict: 'PASS', ts: '2026-10-03T09:19:59Z' },
        plan: { verdict: 'MAYBE', ts: '2026-10-03T08:19:51Z' },
        build: { verdict: 'FAIL', ts: 'not a date' },
        check: { verdict: 'FAIL', ts: '2026-10-03T10:00:00Z' },
      }),
    )
    expect(Object.keys(v).sort()).toEqual(['check', 'intent'])
    expect(v.intent).toEqual({ verdict: 'PASS', ts: Date.parse('2026-10-03T09:04:58Z') })
    expect(v.check?.verdict).toBe('FAIL')
  })

  test('garbage gives no verdicts', () => {
    expect(parseGates('{oops')).toEqual({})
    expect(parseGates('[]')).toEqual({})
    expect(parseGates('null')).toEqual({})
  })
})

describe('parseBuildState and phaseFromStage', () => {
  test('reads spec, path and next stage', () => {
    const s = parseBuildState('{"spec":"pw","spec_path":".temper/specs/pw","next_stage":"build"}')
    expect(s).toEqual({ spec: 'pw', specPath: '.temper/specs/pw', nextStage: 'build', task: null, complexity: null })
    expect(parseBuildState('{"spec":"pw","task":3}')?.task).toBe(3)
    expect(parseBuildState('{"spec":"pw"}')?.specPath).toBe('.temper/specs/pw')
  })

  test('no spec or bad JSON is null', () => {
    expect(parseBuildState('{"stage":"x"}')).toBe(null)
    expect(parseBuildState('nope')).toBe(null)
  })

  test('next stage maps to a phase', () => {
    expect(phaseFromStage('design')).toBe('plan')
    expect(phaseFromStage('build')).toBe('build')
    expect(phaseFromStage('rca')).toBe('fix')
    expect(phaseFromStage('commit')).toBe('done')
    expect(phaseFromStage(null)).toBe('intent')
  })
})

describe('versionAtLeast', () => {
  test('the minimum is 2.1.287', () => {
    expect(MIN_VERSION).toBe('2.1.287')
    expect(versionAtLeast('2.1.287')).toBe(true)
    expect(versionAtLeast('2.1.288')).toBe(true)
    expect(versionAtLeast('2.2.0')).toBe(true)
    expect(versionAtLeast('3.0.0')).toBe(true)
    expect(versionAtLeast('2.1.286')).toBe(false)
    expect(versionAtLeast('2.0.999')).toBe(false)
  })

  test('dev builds compare by their base; junk is unsupported', () => {
    expect(versionAtLeast('2.1.290-dev.20260920.t1.sha1')).toBe(true)
    expect(versionAtLeast('2.1.280-dev.1')).toBe(false)
    expect(versionAtLeast('banana')).toBe(false)
    expect(versionAtLeast(undefined)).toBe(false)
  })
})

describe('taskProgress', () => {
  test('counts Task headings; none done means task 1', () => {
    const p = taskProgress(spec_tasks)
    expect(p?.of).toBe(23)
    expect(p?.n).toBe(1)
  })

  test('the first task without a ticked row is current; build-state task overrides', () => {
    const md = [
      '## Tasks',
      '### Task 1: a',
      '- [x] done',
      '### Task 2: b',
      '- [x] done',
      '- [ ] open',
      '### Task 3: c',
      '- [x] done',
      '## Other',
      '- [ ] not a task row',
    ].join('\n')
    expect(taskProgress(md)).toEqual({ n: 2, of: 3 })
    expect(taskProgress(md, 3)).toEqual({ n: 3, of: 3 })
    expect(taskProgress(md, 9)).toEqual({ n: 3, of: 3 })
    expect(taskProgress('### Task 1: a\n- [x] y')).toEqual({ n: 1, of: 1 })
  })

  test('no tasks is null', () => {
    expect(taskProgress('# nothing')).toBe(null)
  })
})
