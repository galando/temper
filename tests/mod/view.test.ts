import { describe, expect, test } from 'claude-code/testing'

import { followUp } from '../../hooks/temper-mod/core/commands'
import { hintTail, questionHeader, spinnerWord, suggestion, turnLine } from '../../hooks/temper-mod/core/view'
import type { View } from '../../hooks/temper-mod/core/view'
import { buildView } from '../../hooks/temper-mod/core/view'
import { parseFindings } from '../../hooks/temper-mod/core/gates'
import { person, stateAt } from './helpers'

const input = (phase: Parameters<typeof stateAt>[0]) => ({
  state: stateAt(phase),
  title: 'Password reset',
  criteria: [
    { id: 'AC-01', text: 'a', priority: 'required' as const, deferred: false, status: 'passed' as const, evidence: [] },
    { id: 'AC-02', text: 'b', priority: 'required' as const, deferred: false, status: 'open' as const, evidence: [] },
  ],
  findings: [],
  task: { n: 2, of: 5 },
  enforcement: 'on' as const,
})

describe('buildView', () => {
  test('six steps with done, current and pending', () => {
    const v = buildView(input('build'))
    expect(v.steps.map(s => `${s.label}:${s.status}`)).toEqual([
      'Intent:done',
      'Plan:done',
      'Build:current',
      'Review:pending',
      'Check:pending',
      'Fix:pending',
    ])
    expect(v.passed).toBe(1)
    expect(v.total).toBe(2)
  })

  test('Fix is current in the fix loop; Done marks every phase done', () => {
    expect(buildView(input('fix')).steps.find(s => s.id === 'fix')?.status).toBe('current')
    const done = buildView({ ...input('check'), state: stateAt('check', [{ type: 'checkResult', result: 'pass', origin: 'system' }]) })
    expect(done.phase).toBe('done')
    expect(done.actions).toBe(null)
    expect(done.steps.filter(s => s.status === 'done')).toHaveLength(5)
  })

  test('going back marks later phases stale', () => {
    const v = buildView({ ...input('review'), state: stateAt('review', [{ type: 'back', to: 'plan', reason: 'x', ...person }]) })
    expect(v.steps.find(s => s.id === 'plan')?.status).toBe('current')
    expect(v.steps.find(s => s.id === 'build')?.status).toBe('stale')
  })

  test('no run means a bar of pending steps and no actions', () => {
    const v = buildView({ ...input('build'), state: { ...stateAt('build'), phase: null } })
    expect(v.actions).toBe(null)
    expect(v.now).toBe('')
  })

  test('the view is plain JSON, safe for $.state', () => {
    const v = buildView(input('plan'))
    expect(JSON.parse(JSON.stringify(v))).toEqual(v)
  })
})

describe('texts', () => {
  const v: View = buildView(input('build'))

  test('spinner word names the criterion being worked', () => {
    expect(spinnerWord(v)).toBe('Building · criterion 2 of 2')
    expect(spinnerWord({ ...v, passed: 0, total: 5 })).toBe('Building · criterion 1 of 5')
    expect(spinnerWord({ ...v, total: 0 })).toBe('Building')
    expect(spinnerWord({ ...v, phase: 'done' })).toBe(null)
    expect(spinnerWord({ ...v, phase: null })).toBe(null)
  })

  test('hint tail, turn line, question header and suggestion', () => {
    expect(hintTail(v)).toMatch(/^Temper, Build \(3 of 6\): /)
    expect(turnLine(v)).toBe('Build \u00b7 1 of 2 criteria met \u00b7 next: Review')
    expect(questionHeader(v)).toBe('Temper: Build (3 of 6), criterion 2 of 2')
    expect(suggestion(v)).toContain('Start the next task')
    expect(hintTail({ ...v, phase: null })).toBe(null)
    expect(turnLine({ ...v, phase: null })).toBe(null)
    expect(questionHeader({ ...v, phase: 'done' })).toBe(null)
    expect(suggestion({ ...v, actions: null })).toBe(null)
  })

  test('no em or en dashes in any text', () => {
    for (const t of [spinnerWord(v), hintTail(v), turnLine(v), questionHeader(v), suggestion(v)]) {
      expect(/[\u2013\u2014]/.test(t ?? '')).toBe(false)
    }
  })
})

describe('parseFindings', () => {
  test('open findings only, with 1-based ids', () => {
    const rows = [
      { claim: 'ran', exit_code: 0 },
      { claim: 'a', severity: 'critical' },
      { claim: 'b', severity: 'major', accepted: { reason: 'x' } },
      { claim: 'c', severity: 'minor', resolved: { fixed_by: 'y' } },
      { claim: 'd', severity: 'major' },
    ]
    expect(parseFindings(JSON.stringify(rows))).toEqual([
      { id: '2', severity: 'critical', claim: 'a' },
      { id: '5', severity: 'major', claim: 'd' },
    ])
    expect(parseFindings('nope')).toEqual([])
    expect(parseFindings('{}')).toEqual([])
  })
})

describe('followUp', () => {
  test('decisions ask Claude to mirror them in the CLI', () => {
    expect(followUp({ type: 'override', phase: 'review', reason: 'r', origin: 'person' })).toContain("scripts/temper override review --reason 'r'")
    expect(followUp({ type: 'accept', findingId: '2', reason: 'fp', origin: 'person' })).toContain('evidence accept --stage review --id 2')
    expect(followUp({ type: 'advance', from: 'plan', to: 'build', origin: 'person' })).toContain('state advance plan_complete build')
    expect(followUp({ type: 'back', to: 'plan', reason: 'x', origin: 'person' })).toContain('state set next_stage plan')
    expect(followUp({ type: 'drift', path: 'a.ts', choice: 'revert', reason: '', origin: 'person' })).toContain('a.ts')
    expect(followUp({ type: 'pause', origin: 'person' })).toBe(null)
    expect(/[\u2013\u2014]/.test(followUp({ type: 'override', phase: 'plan', reason: 'x', origin: 'person' }) ?? '')).toBe(false)
  })
})

describe('hotkeys are unique in every phase and state', () => {
  const PHASES = ['intent', 'plan', 'build', 'review', 'check', 'fix'] as const
  const unique = (keys: string[]) => new Set(keys).size === keys.length

  // Every combination of the flags that change which actions are offered.
  for (const phase of PHASES) {
    for (const hasFindings of [false, true]) {
      for (const paused of [false, true]) {
        for (const limit of [false, true]) {
          test(`${phase} findings=${hasFindings} paused=${paused} limit=${limit}`, () => {
            const state = stateAt(phase, paused ? [{ type: 'pause', ...person }] : [])
            const v = buildView({
              ...input(phase),
              state: limit && phase === 'fix' ? { ...state, loopLimitReached: true } : state,
              findings: hasFindings ? [{ id: '1', severity: 'major', claim: 'x' }, { id: '2', severity: 'minor', claim: 'y' }] : [],
            })
            const a = v.actions
            if (!a) throw new Error('no actions')
            const band = [...a.primary.map(x => x.key), a.override.key, '0']
            expect(unique(band)).toBe(true)
            expect(band).toEqual(['1', '2', '3', '9', '0'])
            // The band's Play button (only while Claude works) takes the digit 8: no phase uses it.
            expect(unique([...band, '8'])).toBe(true)
            // The pane adds the letters of the full list; 0 is only ever "More actions".
            const pane = [...a.primary.map(x => x.key), a.override.key, '0', ...a.more.map(x => x.key)]
            expect(unique(pane)).toBe(true)
            expect(a.more.every(x => /^[a-h]$/.test(x.key))).toBe(true)
            expect(a.more.length).toBeGreaterThan(0)
          })
        }
      }
    }
  }
})
