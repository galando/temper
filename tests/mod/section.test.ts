import { describe, expect, test } from 'claude-code/testing'

import { SECTION_ID, sectionText } from '../../hooks/temper-mod/core/section'

const base = {
  enforcement: 'on',
  phase: 'build',
  title: 'Password reset by email',
  task: { n: 3, of: 7 },
  progress: { passed: 2, total: 5, passedIds: ['AC-01', 'AC-03'] },
} as const

describe('system prompt section', () => {
  test('has a stable id', () => {
    expect(SECTION_ID).toBe('temper:phase')
  })

  test('Build on task 3 of 7 reads exactly as the plan says', () => {
    const lines = sectionText(base).split('\n')
    expect(lines[0]).toBe('Temper enforcement: active')
    expect(lines[1]).toBe('Phase: Build (task 3 of 7) · Intent: "Password reset by email"')
    expect(lines[2]).toBe('Criteria: 2 of 5 passed (AC-01, AC-03)')
    expect(lines[3]?.startsWith('Next: ')).toBe(true)
  })

  test('enforcement off says UI only', () => {
    expect(sectionText({ ...base, enforcement: 'off' }).split('\n')[0]).toBe('Temper enforcement: off (UI only)')
  })

  test('no passes drops the id list; no task drops the task part', () => {
    const t = sectionText({ ...base, task: null, progress: { passed: 0, total: 5, passedIds: [] } })
    expect(t).toContain('Phase: Build · Intent')
    expect(t).toContain('Criteria: 0 of 5 passed\n')
  })

  test('done, paused, loop limit and stale phases are stated', () => {
    expect(sectionText({ ...base, phase: 'done' })).toContain('Phase: Done')
    expect(sectionText({ ...base, paused: true })).toContain('(paused)')
    expect(sectionText({ ...base, phase: 'fix', loopLimitReached: true })).toContain('loop limit')
    expect(sectionText({ ...base, phase: 'plan', stale: ['build', 'review'] })).toContain('Stale: Build, Review')
  })

  test('no run gives a short section', () => {
    const t = sectionText({ enforcement: 'on', phase: null, title: null, progress: null })
    expect(t).toBe('Temper enforcement: active\nPhase: none. No Temper run is active.')
  })

  test('no em or en dashes', () => {
    expect(/[\u2013\u2014]/.test(sectionText({ ...base, stale: ['build'] }))).toBe(false)
  })
})
