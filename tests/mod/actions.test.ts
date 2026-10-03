import { describe, expect, test } from 'claude-code/testing'

import { actionsFor, findingActions, nextStep } from '../../hooks/temper-mod/core/actions'
import { PHASES } from '../../hooks/temper-mod/core/events'

const labels = (phase: Parameters<typeof actionsFor>[0], ctx = {}) => actionsFor(phase, ctx).primary.map(a => a.label)

describe('per-phase actions (mods-plan 3.7)', () => {
  test('every phase has keys 1, 2, 3 and an override on 9', () => {
    for (const p of PHASES) {
      const a = actionsFor(p, {})
      expect(a.primary.map(x => x.key)).toEqual(['1', '2', '3'])
      expect(a.override.key).toBe('9')
      expect(a.override.asksReason).toBe(true)
    }
  })

  test('key 1 follows readiness', () => {
    expect(labels('intent')[0]).toBe('Lint intent')
    expect(labels('intent', { ready: true })[0]).toBe('Approve intent')
    expect(labels('plan')[0]).toBe('Generate plan')
    expect(labels('plan', { ready: true })[0]).toBe('Approve plan')
    expect(labels('build')[0]).toBe('Start next task')
    expect(labels('build', { tasksDone: true })[0]).toBe('Send to Review')
    expect(labels('review')[0]).toBe('Start review')
    expect(labels('review', { hasFindings: true })[0]).toBe('Fix all')
    expect(labels('check')[0]).toBe('Run all checks')
    expect(labels('check', { allChecksPass: true })[0]).toBe('Mark done')
    expect(labels('fix')[0]).toBe('Fix failures')
  })

  test('keys 2 and 3 per phase', () => {
    expect(labels('intent').slice(1)).toEqual(['Ask clarifying questions', 'Edit intent'])
    expect(labels('plan').slice(1)).toEqual(['Show files the plan touches', 'Propose an alternative'])
    expect(labels('build').slice(1)).toEqual(['Run tests for current criterion', 'Show diff against plan'])
    expect(labels('review').slice(1)).toEqual(['Re-review', 'Show diff'])
    expect(labels('check').slice(1)).toEqual(['Rerun failed only', 'Failures by criterion'])
    expect(labels('fix').slice(1)).toEqual(['Fix open findings', 'Return to Check'])
  })

  test('key 0 lists the extra actions', () => {
    const more = (p: Parameters<typeof actionsFor>[0]) => actionsFor(p, {}).more.map(a => a.label)
    expect(more('intent')).toEqual(['Capture intent from my prompt'])
    expect(more('plan')).toEqual(['Split into tasks', 'Back to Intent'])
    expect(more('build')).toEqual(['Pause'])
    expect(more('review')).toEqual([])
    expect(more('check')).toEqual([])
  })

  test('at the fix loop limit the three choices replace the fix actions', () => {
    expect(labels('fix', { loopLimitReached: true })).toEqual(['Re-plan', 'Override', 'I take over'])
  })

  test('every action either sends a prompt or runs a subcommand, never both, never empty', () => {
    for (const p of PHASES) {
      const a = actionsFor(p, { ready: true, tasksDone: true })
      for (const x of [...a.primary, a.override, ...a.more]) {
        expect(Boolean(x.prompt) !== Boolean(x.command)).toBe(true)
      }
    }
  })

  test('per finding actions are Fix, Accept with reason and Explain', () => {
    expect(findingActions('3').map(a => a.label)).toEqual(['Fix', 'Accept with reason', 'Explain'])
    expect(findingActions('3')[1]?.asksReason).toBe(true)
  })

  test('nextStep names the key and the subcommand', () => {
    expect(nextStep('plan', { ready: true })).toContain('/temper:temper approve')
    expect(nextStep('check', {})).toContain('/temper:check')
    expect(nextStep('done', {})).toContain('commit')
    expect(nextStep('fix', { loopLimitReached: true })).toContain('loop limit')
  })

  test('no em or en dashes in any label or prompt', () => {
    for (const p of PHASES) {
      const a = actionsFor(p, { ready: true })
      for (const x of [...a.primary, a.override, ...a.more]) {
        expect(/[\u2013\u2014]/.test(`${x.label}${x.prompt ?? ''}${x.command ?? ''}`)).toBe(false)
      }
    }
  })
})
