import { describe, expect, test } from 'claude-code/testing'

import { ACT, SHOW, actionsFor, findingActions, globalActions, nextStep, nowText } from '../../hooks/temper-mod/core/actions'
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
    expect(labels('intent')[0]).toBe('Check the intent')
    expect(labels('intent', { ready: true })[0]).toBe('Approve the intent')
    expect(labels('plan')[0]).toBe('Make the plan')
    expect(labels('plan', { ready: true })[0]).toBe('Approve the plan')
    expect(labels('build')[0]).toBe('Start the next task')
    expect(labels('build', { tasksDone: true })[0]).toBe('Send to review')
    expect(labels('review')[0]).toBe('Start the review')
    expect(labels('review', { hasFindings: true })[0]).toBe('Fix the problems')
    expect(labels('check')[0]).toBe('Run the checks')
    expect(labels('check', { allChecksPass: true })[0]).toBe('Finish the run')
    expect(labels('fix')[0]).toBe('Fix the failures')
  })

  test('keys 2 and 3 per phase', () => {
    expect(labels('intent').slice(1)).toEqual(['Ask me questions', 'Edit the intent'])
    expect(labels('plan').slice(1)).toEqual(['Show the files', 'Try another plan'])
    expect(labels('build').slice(1)).toEqual(['Run the tests', 'Show the changes'])
    expect(labels('review').slice(1)).toEqual(['Review again', 'Show the changes'])
    expect(labels('check').slice(1)).toEqual(['Run failed checks again', 'Show the failures'])
    expect(labels('fix').slice(1)).toEqual(['Fix the findings', 'Go back to checks'])
  })

  test('key 0 lists the extra actions', () => {
    const more = (p: Parameters<typeof actionsFor>[0]) => actionsFor(p, {}).more.map(a => a.label)
    expect(more('intent')).toEqual(['Save my request'])
    expect(more('plan')).toEqual(['Split the tasks', 'Go back to Intent'])
    expect(more('build')).toEqual([])
    expect(more('review')).toEqual([])
    expect(more('check')).toEqual([])
  })

  test('at the fix loop limit the three choices replace the fix actions', () => {
    expect(labels('fix', { loopLimitReached: true })).toEqual(['Make a new plan', 'Skip with a reason', 'Take over'])
  })

  test('key 9 says what it does: skip with a reason', () => {
    for (const p of PHASES) expect(actionsFor(p, {}).override.label).toBe('Skip with a reason')
  })

  test('every action either sends a prompt or runs a subcommand, never both, never empty', () => {
    for (const p of PHASES) {
      const a = actionsFor(p, { ready: true, tasksDone: true })
      for (const x of [...a.primary, a.override, ...a.more]) {
        expect(Boolean(x.prompt) !== Boolean(x.command)).toBe(true)
      }
    }
  })

  test('the intent key 1 is Approve the intent as soon as a PASS verdict exists, with no extra check', () => {
    const a = actionsFor('intent', { ready: true }).primary[0]
    expect(a?.label).toBe('Approve the intent')
    expect(a?.command).toBe('approve')
    expect(a?.prompt).toBeUndefined()
  })

  test('per finding actions are Fix, Accept with reason and Explain', () => {
    expect(findingActions('3').map(a => a.label)).toEqual(['Fix', 'Accept', 'Explain'])
    expect(findingActions('3')[1]?.asksReason).toBe(true)
  })

  test('nextStep names the key and the subcommand', () => {
    expect(nextStep('plan', { ready: true })).toContain('/temper:temper approve')
    expect(nextStep('check', {})).toContain('/temper:check')
    expect(nextStep('done', {})).toContain('Commit')
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

// Every label, in every phase and state, is easy to read: 1 to 4 words, a verb first, no internal
// word. Every action has one short line of its own, and every prompt tells Claude to act now.
describe('easy words (labels, lines and prompts)', () => {
  const VERBS = new Set(['Check', 'Approve', 'Ask', 'Edit', 'Save', 'Make', 'Show', 'Try', 'Split', 'Go', 'Start', 'Run', 'Send', 'Review', 'Fix', 'Finish', 'Take', 'Skip', 'Pause', 'Resume', 'Write', 'Accept', 'Explain'])
  const STATES = [
    {},
    { ready: true },
    { tasksDone: true, ready: true },
    { hasFindings: true },
    { allChecksPass: true, ready: true },
    { loopLimitReached: true },
  ]
  const words = (s: string): string[] => s.trim().split(/\s+/)
  const all = () => {
    const out: Array<{ phase: string; x: ReturnType<typeof actionsFor>['primary'][number] }> = []
    for (const p of PHASES) for (const ctx of STATES) {
      const a = actionsFor(p, ctx)
      for (const x of [...a.primary, a.override, ...a.more, ...globalActions(p, false), ...globalActions(p, true)]) out.push({ phase: `${p} ${JSON.stringify(ctx)}`, x })
      if (p === 'review') for (const f of findingActions('1')) out.push({ phase: 'finding', x: f })
    }
    return out
  }

  test('every label is 1 to 4 words and starts with a verb', () => {
    for (const { phase, x } of all()) {
      const w = words(x.label)
      expect(w.length >= 1 && w.length <= 4, `${phase}: "${x.label}" has ${w.length} words`).toBe(true)
      expect(VERBS.has(w[0] ?? ''), `${phase}: "${x.label}" does not start with a verb`).toBe(true)
    }
  })

  test('every action has one line of 10 words at most, and no label or line holds an internal word', () => {
    for (const { phase, x } of all()) {
      expect(x.desc.length > 0, `${phase}: "${x.label}" has no line`).toBe(true)
      expect(words(x.desc).length <= 10, `${phase}: "${x.label}" line is too long: ${x.desc}`).toBe(true)
      expect(/\b(gate|override|verdict|criterion|criteria|goals?)\b/i.test(`${x.label} ${x.desc}`), `${phase}: "${x.label}"`).toBe(false)
    }
  })

  test('every prompt tells Claude to act now and keep it short', () => {
    for (const { phase, x } of all()) {
      if (!x.prompt) continue
      expect(x.prompt.endsWith(ACT) || x.prompt.endsWith(SHOW), `${phase}: ${x.label}`).toBe(true)
    }
  })

  test('the sentence under the bar starts with the key and the label of the main action', () => {
    for (const p of PHASES) for (const ctx of STATES) {
      const a = actionsFor(p, ctx)
      const now = nowText(p, ctx)
      if (p === 'fix' && ctx.loopLimitReached) continue
      expect(now.startsWith(`1 ${a.primary[0]?.label}. `), `${p} ${JSON.stringify(ctx)}: ${now}`).toBe(true)
      expect(now.endsWith('.')).toBe(true)
    }
  })

  test('the plan and intent sentences say what happens next', () => {
    expect(nowText('plan', {})).toBe('1 Make the plan. Claude writes the plan: which files change and the steps. Then you approve it.')
    expect(nowText('plan', { ready: true })).toBe('1 Approve the plan. Claude can then change the files in the plan. Build opens.')
    expect(nowText('intent', {})).toContain('Then press 1 again to approve.')
  })
})
