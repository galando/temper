import { describe, expect, test } from 'claude-code/testing'

import { mergeCriteria, parseCriteria, parseStatus, parseTitle, progress } from '../../hooks/temper-mod/core/criteria'
import { intent_template } from './fixtures/intent-template'
import { spec_intent } from './fixtures/spec-intent'

describe('parseCriteria', () => {
  test('reads the template criteria with the acceptance.py pattern', () => {
    const c = parseCriteria(intent_template)
    expect(c.map(x => [x.id, x.priority])).toEqual([
      ['AC-01', 'required'],
      ['AC-02', 'optional'],
    ])
  })

  test('reads every criterion of the mods-support intent, in order, with priorities', () => {
    const c = parseCriteria(spec_intent)
    expect(c).toHaveLength(16)
    expect(c[0]).toMatchObject({ id: 'AC-01', priority: 'required', deferred: false })
    expect(c[15]).toMatchObject({ id: 'AC-15', priority: 'optional', deferred: true })
    expect(c.filter(x => x.priority === 'required')).toHaveLength(15)
    expect(c[0]?.text.startsWith('In every phase, a Write, Edit or NotebookEdit outside')).toBe(true)
    expect(c[0]?.text).not.toContain('(source:')
  })

  test('ignores bullets outside Success Criteria, placeholders and fenced blocks', () => {
    const text = [
      '# Intent: X',
      '- [ ] AC-09 [required]: not here, wrong section',
      '### Success Criteria',
      '- [ ] {placeholder criterion}',
      '- [x] AC-01 [required]: first',
      '  Validate: code - tests',
      '```',
      '- [ ] AC-02 [required]: inside a fence',
      '```',
      '- plain bullet without an id',
      '- AC-03 [optional]: no checkbox',
      '  Deferred: later',
      '### Constraints',
      '- AC-04 [required]: after the section',
    ].join('\n')
    expect(parseCriteria(text).map(c => c.id)).toEqual(['AC-01', 'AC-03'])
    expect(parseCriteria(text)[1]?.deferred).toBe(true)
  })

  test('no section or empty text gives no criteria', () => {
    expect(parseCriteria('')).toEqual([])
    expect(parseCriteria('# Intent: X\n\nnothing here')).toEqual([])
  })
})

describe('parseTitle', () => {
  test('takes the title after "# Intent:"', () => {
    expect(parseTitle(spec_intent)).toBe('Claude Code mods support for Temper')
    expect(parseTitle('# Something else')).toBe(null)
  })
})

describe('status merge and progress', () => {
  const status = JSON.stringify({
    ts: '2026-10-03T10:00:00Z',
    criteria: [
      { id: 'AC-01', priority: 'required', status: 'passed', evidence: ['build#2 unit tests'] },
      { id: 'AC-02', priority: 'required', status: 'open', evidence: [] },
      { id: 'AC-03', priority: 'required', status: 'passed', evidence: [] },
    ],
  })

  test('parseStatus is tolerant of bad JSON and wrong shapes', () => {
    expect(parseStatus('{not json')).toBe(null)
    expect(parseStatus('[]')).toBe(null)
    expect(parseStatus('{"criteria": 3}')).toBe(null)
    expect(parseStatus(status)?.criteria).toHaveLength(3)
  })

  test('merge marks unknown criteria open and counts passes', () => {
    const base = parseCriteria(spec_intent).slice(0, 5)
    const merged = mergeCriteria(base, parseStatus(status))
    expect(merged.map(m => m.status)).toEqual(['passed', 'open', 'passed', 'open', 'open'])
    expect(merged[0]?.evidence).toEqual(['build#2 unit tests'])
    expect(progress(merged)).toEqual({ passed: 2, total: 5, passedIds: ['AC-01', 'AC-03'] })
  })

  test('without a status file everything is open', () => {
    const merged = mergeCriteria(parseCriteria(spec_intent).slice(0, 2), null)
    expect(progress(merged)).toEqual({ passed: 0, total: 2, passedIds: [] })
  })
})
