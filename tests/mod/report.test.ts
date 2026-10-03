import { describe, expect, test } from 'claude-code/testing'

import { mergeCriteria, parseCriteria, parseStatus } from '../../hooks/temper-mod/core/criteria'
import type { Draft } from '../../hooks/temper-mod/core/events'
import { renderReport } from '../../hooks/temper-mod/core/report'
import { spec_intent } from './fixtures/spec-intent'
import { adv, fold, person } from './helpers'

const status = JSON.stringify({
  ts: 't',
  criteria: [
    { id: 'AC-01', priority: 'required', status: 'passed', evidence: ['build#1 unit tests'] },
    { id: 'AC-02', priority: 'required', status: 'passed', evidence: [] },
    { id: 'AC-03', priority: 'required', status: 'passed', evidence: [] },
    { id: 'AC-04', priority: 'required', status: 'passed', evidence: [] },
    { id: 'AC-05', priority: 'required', status: 'open', evidence: [] },
  ],
})

const drafts: Draft[] = [
  { type: 'start', slug: 'pw', title: 'Password reset', ...person },
  adv('intent', 'plan'),
  adv('plan', 'build'),
  { type: 'drift', path: 'src/billing.ts', choice: 'add', reason: 'shared helper', ...person },
  { type: 'drift', path: 'src/hotfix.ts', choice: 'allow-once', reason: 'prod incident', ...person },
  adv('build', 'review'),
  { type: 'accept', findingId: '2', reason: 'false positive, input is trusted', ...person },
  { type: 'override', phase: 'review', reason: 'reviewer is on leave, risk accepted', ...person },
  { type: 'checkResult', result: 'pass', origin: 'system' },
]

const input = () => ({
  state: fold(drafts),
  criteria: mergeCriteria(parseCriteria(spec_intent).slice(0, 5), parseStatus(status)),
  generatedAt: 1700000000000,
})

describe('renderReport', () => {
  const md = renderReport(input())

  test('has the five sections in order', () => {
    const heads = md.split('\n').filter(l => l.startsWith('## '))
    expect(heads).toEqual(['## Phases', '## Overrides', '## Accepted findings', '## Scope drift', '## Criteria'])
  })

  test('title, spec and result lead the file', () => {
    expect(md.startsWith('# Temper report: Password reset')).toBe(true)
    expect(md).toContain('Result: Done')
  })

  test('the override lists phase, reason and author', () => {
    expect(md).toContain('Review: overridden, reason: reviewer is on leave, risk accepted')
    expect(md).toContain('by galando')
  })

  test('accepted findings and both drift decisions carry reason and author', () => {
    expect(md).toContain('Finding 2: accepted, reason: false positive, input is trusted')
    expect(md).toContain('src/billing.ts: add to plan, reason: shared helper')
    expect(md).toContain('src/hotfix.ts: allow once, reason: prod incident')
    expect((md.match(/by galando/g) ?? []).length).toBeGreaterThanOrEqual(4)
  })

  test('criteria show the count and one row per criterion', () => {
    expect(md).toContain('4 of 5 passed')
    expect(md).toContain('| AC-01 | required | passed | build#1 unit tests |')
    expect(md).toContain('| AC-05 | required | open |')
  })

  test('phases show passed, overridden and the Check result', () => {
    expect(md).toContain('| Intent | passed |')
    expect(md).toContain('| Review | overridden |')
    expect(md).toContain('| Check | passed |')
  })

  test('empty sections say so, and an in-progress run says so', () => {
    const quiet = renderReport({ state: fold(drafts.slice(0, 3)), criteria: [], generatedAt: 1 })
    expect(quiet).toContain('Result: In progress (Build)')
    expect(quiet).toContain('## Overrides\n\nNone.')
    expect(quiet).toContain('## Scope drift\n\nNone.')
  })

  test('unverified and unreadable events are listed under Notes', () => {
    const noted = renderReport({ ...input(), unreadable: ['4-s-4.json'], unverified: ['2-x-1'] })
    expect(noted).toContain('## Notes')
    expect(noted).toContain('Unreadable event file: 4-s-4.json')
    expect(noted).toContain('Event that Temper does not trust: 2-x-1')
  })

  test('no em or en dashes anywhere in the output', () => {
    expect(/[\u2013\u2014]/.test(md)).toBe(false)
  })
})
