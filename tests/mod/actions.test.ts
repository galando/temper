import { describe, expect, test } from 'claude-code/testing'

import { ACT, DISCUSS, SHOW, actionsFor, doneActions, findingActions, nextStep, nowText } from '../../hooks/temper-mod/core/actions'
import type { Action, ActionContext } from '../../hooks/temper-mod/core/actions'
import { PHASES } from '../../hooks/temper-mod/core/events'

type P = Parameters<typeof actionsFor>[0]
const labels = (phase: P, ctx: ActionContext = {}) => actionsFor(phase, ctx).primary.map(a => a.label)
const menu = (phase: P, ctx: ActionContext = {}) => actionsFor(phase, ctx).more.map(a => a.label)

describe('per-phase actions (one flow, two views)', () => {
  test('every phase has keys 1, 2, 3, Discuss on 4 and an override on 9', () => {
    for (const p of PHASES) {
      const a = actionsFor(p, p === 'review' ? { hasFindings: true } : {})
      expect(a.primary.map(x => x.key)).toEqual(['1', '2', '3'])
      expect(a.discuss.key).toBe('4')
      expect(a.override?.key).toBe('9')
      expect(a.override?.asksReason).toBe(true)
    }
  })

  test('key 1 is the original Continue once the check passed', () => {
    expect(labels('intent', { ready: true, gate: 'fresh' })[0]).toBe('Continue to Plan')
    expect(labels('plan', { ready: true, gate: 'fresh' })[0]).toBe('Continue to Build')
    expect(labels('build', { ready: true, gate: 'fresh' })[0]).toBe('Continue to Review')
    expect(labels('review', { ready: true, gate: 'fresh' })[0]).toBe('Continue to Check')
    expect(labels('check', { ready: true, gate: 'fresh' })[0]).toBe('Continue to Commit')
    const plan = actionsFor('plan', { ready: true, gate: 'fresh' }).primary[0]
    expect(plan?.command).toBe('approve')
    expect(plan?.resume).toBe(true)
    expect(actionsFor('build', { ready: true, gate: 'fresh' }).primary[0]?.command).toBe('next')
  })

  test('key 1 is the original Loop back when the check failed', () => {
    expect(labels('plan', { gate: 'fail' })[0]).toBe('Loop back to Intent')
    expect(labels('build', { gate: 'fail' })[0]).toBe('Loop back to Plan')
    expect(labels('review', { gate: 'fail' })[0]).toBe('Loop back to Build')
    const loop = actionsFor('build', { gate: 'fail' }).primary[0]
    expect(loop?.command).toBe('back plan')
    expect(loop?.asksReason).toBe(true)
    expect(loop?.resume).toBe(true)
  })

  test('a failed build check while tasks are open is a checkpoint, not a failure', () => {
    const open = { gate: 'fail' as const, task: { n: 2, of: 3 }, tasksLeft: 2 }
    expect(labels('build', open)[0]).toBe('Continue with task 2')
    expect(actionsFor('build', open).primary[0]?.resume).toBe(true)
    // Every task is done and the check still fails: that is the original Loop back.
    expect(labels('build', { gate: 'fail', task: { n: 3, of: 3 }, tasksLeft: 0 })[0]).toBe('Loop back to Plan')
    // Nothing is known about the tasks: a failed check is a failure.
    expect(labels('build', { gate: 'fail', task: null, tasksLeft: null })[0]).toBe('Loop back to Plan')
  })

  test('key 1 starts or runs the stage when no check result is there yet', () => {
    expect(labels('intent', { gate: 'none' })[0]).toBe('Start Intent')
    expect(labels('plan', { gate: 'none' })[0]).toBe('Run Plan')
    expect(labels('plan', { gate: 'stale' })[0]).toBe('Run Plan')
    expect(labels('check', { gate: 'none' })[0]).toBe('Run Check')
    expect(labels('build', { gate: 'none', task: { n: 3, of: 7 } })[0]).toBe('Continue with task 3')
    // A stage launcher has no prompt of its own: the orchestrator runs the stage with its brief.
    const run = actionsFor('plan', { gate: 'none' }).primary[0]
    expect(run?.resume).toBe(true)
    expect(run?.prompt).toBeUndefined()
    expect(run?.command).toBeUndefined()
  })

  test('there is no separate Check the intent or Make the plan step any more', () => {
    for (const p of PHASES) for (const g of ['none', 'fail', 'fresh', 'stale'] as const) {
      const all = [...actionsFor(p, { gate: g, ready: g === 'fresh' }).primary, ...actionsFor(p, { gate: g }).more].map(x => x.label)
      expect(all).not.toContain('Check the intent')
      expect(all).not.toContain('Make the plan')
      expect(all).not.toContain('Approve the plan')
    }
  })

  test('keys 2 and 3 per phase use the words of the original options', () => {
    expect(labels('intent').slice(1)).toEqual(['Ask me questions', 'Edit the intent'])
    expect(labels('plan').slice(1)).toEqual(['Walk through step by step', 'Show the files'])
    expect(labels('build').slice(1)).toEqual(['Change', 'Run the tests'])
    expect(labels('review', { hasFindings: true }).slice(1)).toEqual(['Fix the problems', 'Show the changes'])
    expect(labels('review').slice(1)).toEqual(['Show the changes'])
    expect(labels('check').slice(1)).toEqual(['Run failed checks again', 'Show the failures'])
    expect(labels('fix').slice(1)).toEqual(['Fix the findings', 'Go back to checks'])
  })

  test('Change and Discuss put a draft in the prompt box and change nothing', () => {
    const change = actionsFor('build', {}).primary[1]
    expect(change?.fill).toBe('Change this task: ')
    expect(change?.prompt).toBeUndefined()
    expect(change?.command).toBeUndefined()
    expect(DISCUSS.fill).toBe('Discuss this step: ')
    expect(DISCUSS.label).toBe('Discuss')
    expect(DISCUSS.desc).toBe('Type your own message about this step.')
  })

  test('the menu on key 0 holds the rest of the original options', () => {
    expect(menu('intent')).toEqual(['Grill me', 'Teach me', 'Save my request', 'Save for later', 'Show the timeline'])
    expect(menu('plan')).toEqual([
      'Open HTML review',
      'Try another plan',
      'Split the tasks',
      'Grill me',
      'Teach me',
      'Go back to Intent',
      'Save for later',
      'Show the timeline',
    ])
    expect(menu('build')).toEqual(['Stop', 'Grill me', 'Teach me', 'Go back to Plan', 'Save for later', 'Show the timeline'])
    expect(menu('review')).toEqual(['Architecture depth review', 'Grill me', 'Teach me', 'Go back to Build', 'Save for later', 'Show the timeline', 'Write the PR text'])
    expect(menu('check')).toEqual(['Grill me', 'Teach me', 'Go back to Review', 'Save for later', 'Show the timeline', 'Write the PR text'])
  })

  test('Review config suggestions is offered only when the file exists', () => {
    expect(menu('check', { configSuggestions: true })[0]).toBe('Review config suggestions')
    expect(menu('check', { configSuggestions: false })).not.toContain('Review config suggestions')
  })

  test('a paused run offers Resume the run where it offers Save for later', () => {
    expect(menu('build', { paused: true })).toContain('Resume the run')
    expect(menu('build', { paused: true })).not.toContain('Save for later')
  })

  test('the menu has digits 1 to 9 in order, never more than nine entries, and no label twice', () => {
    for (const p of PHASES) for (const ctx of [{}, { configSuggestions: true }, { paused: true }, { loopLimitReached: true }]) {
      const m = actionsFor(p, ctx).more
      expect(m.length).toBeGreaterThan(0)
      expect(m.length).toBeLessThanOrEqual(9)
      expect(m.map(a => a.key)).toEqual(['1', '2', '3', '4', '5', '6', '7', '8', '9'].slice(0, m.length))
      expect(new Set(m.map(a => a.label)).size).toBe(m.length)
    }
  })

  test('at the fix loop limit the three choices replace the fix actions', () => {
    expect(labels('fix', { loopLimitReached: true })).toEqual(['Plan again', 'Skip with a reason', 'Take over'])
  })

  test('key 9 says what it does: skip with a reason', () => {
    for (const p of PHASES) expect(actionsFor(p, {}).override?.label).toBe('Skip with a reason')
  })

  test('a finished run offers Commit, the PR text and the timeline, and no skip', () => {
    const d = doneActions()
    expect(d.primary.map(a => a.label)).toEqual(['Commit', 'Write the PR text', 'Show the timeline'])
    expect(d.primary.map(a => a.key)).toEqual(['1', '2', '3'])
    expect(d.discuss.key).toBe('4')
    expect(d.override).toBeNull()
    expect(d.primary[0]?.prompt).toContain('Do not push')
  })

  test('every action does exactly one kind of thing: prompt, command, launch or draft', () => {
    const all = (a: ReturnType<typeof actionsFor>): Action[] => [...a.primary, a.discuss, ...(a.override ? [a.override] : []), ...a.more]
    for (const p of PHASES) for (const ctx of [{}, { ready: true, gate: 'fresh' as const }, { gate: 'fail' as const }, { hasFindings: true }]) {
      for (const x of all(actionsFor(p, ctx))) {
        const kinds = [Boolean(x.prompt), Boolean(x.command), Boolean(x.fill), Boolean(x.resume && !x.command && !x.prompt)].filter(Boolean).length
        // Stop is the one action that records (pause) and asks (the build check) together.
        expect(kinds >= 1 && (kinds === 1 || x.id === 'stop' || Boolean(x.command && x.resume)), `${p} ${x.id}`).toBe(true)
      }
    }
    for (const x of all(doneActions())) expect(Boolean(x.prompt || x.command || x.fill)).toBe(true)
  })

  test('per finding actions are Fix, Accept with reason and Explain', () => {
    expect(findingActions('3').map(a => a.label)).toEqual(['Fix', 'Accept', 'Explain'])
    expect(findingActions('3')[1]?.asksReason).toBe(true)
  })

  test('nextStep names the key and the subcommand', () => {
    expect(nextStep('plan', { ready: true })).toContain('/temper:temper approve')
    expect(nextStep('plan', { ready: true })).toContain('continue to Build')
    expect(nextStep('check', {})).toContain('/temper:check')
    expect(nextStep('done', {})).toContain('Commit')
    expect(nextStep('fix', { loopLimitReached: true })).toContain('loop limit')
  })

  test('no em or en dashes in any label or prompt', () => {
    for (const p of PHASES) {
      const a = actionsFor(p, { ready: true })
      for (const x of [...a.primary, a.discuss, ...(a.override ? [a.override] : []), ...a.more]) {
        expect(/[–—]/.test(`${x.label}${x.prompt ?? ''}${x.command ?? ''}${x.fill ?? ''}`)).toBe(false)
      }
    }
  })
})

// Every label, in every phase and state, is easy to read: 1 to 4 words, no internal word. Every action has
// one short line of its own, and every prompt tells Claude to act now. The labels that are the original
// options of commands/temper.md keep their words, so they are listed here.
describe('easy words (labels, lines and prompts)', () => {
  const VERBS = new Set([
    'Ask', 'Edit', 'Save', 'Show', 'Try', 'Split', 'Go', 'Start', 'Run', 'Review', 'Fix', 'Take', 'Skip', 'Resume', 'Write', 'Accept', 'Explain',
    'Continue', 'Loop', 'Walk', 'Open', 'Grill', 'Teach', 'Stop', 'Commit', 'Discuss', 'Change', 'Plan',
  ])
  const ORIGINAL = ['Architecture depth review']
  const STATES: ActionContext[] = [
    {},
    { ready: true, gate: 'fresh' },
    { gate: 'fail' },
    { gate: 'stale' },
    { hasFindings: true },
    { allChecksPass: true, ready: true, gate: 'fresh' },
    { loopLimitReached: true },
    { paused: true, configSuggestions: true, task: { n: 2, of: 5 } },
  ]
  const words = (s: string): string[] => s.trim().split(/\s+/)
  const all = () => {
    const out: Array<{ phase: string; x: Action }> = []
    for (const p of PHASES) for (const ctx of STATES) {
      const a = actionsFor(p, ctx)
      for (const x of [...a.primary, a.discuss, ...(a.override ? [a.override] : []), ...a.more]) out.push({ phase: `${p} ${JSON.stringify(ctx)}`, x })
      if (p === 'review') for (const f of findingActions('1')) out.push({ phase: 'finding', x: f })
    }
    for (const x of [...doneActions().primary]) out.push({ phase: 'done', x })
    return out
  }

  test('every label is 1 to 5 words and starts with a verb or is an original option', () => {
    for (const { phase, x } of all()) {
      const w = words(x.label)
      expect(w.length >= 1 && w.length <= 5, `${phase}: "${x.label}" has ${w.length} words`).toBe(true)
      expect(VERBS.has(w[0] ?? '') || ORIGINAL.includes(x.label), `${phase}: "${x.label}" does not start with a verb`).toBe(true)
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

  test('the narrow label of every action is short enough for 80 columns', () => {
    for (const { phase, x } of all()) {
      const narrow = x.short ?? x.label
      expect(narrow.length <= 20 || x.key === '4', `${phase}: "${narrow}"`).toBe(true)
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

  test('the sentences say what happens next', () => {
    expect(nowText('plan', { ready: true, gate: 'fresh' })).toBe('1 Continue to Build. The plan is checked. Build opens and Claude starts building.')
    expect(nowText('intent', { gate: 'none' })).toBe('1 Start Intent. Claude writes the intent and checks it. Then you decide.')
    expect(nowText('done', {})).toBe('The run is done. 1 Commit when you are ready.')
  })
})

// Every question of the original orchestrator (commands/temper.md) is reachable with the same words.
// scripts/check-original-options.sh keeps this list in step with that file.
describe('every original option maps to an action', () => {
  const ORIGINAL: Array<[string, P | 'done', ActionContext]> = [
    ['Continue to', 'plan', { ready: true, gate: 'fresh' }],
    ['Save for later', 'plan', {}],
    ['Grill Me', 'plan', {}],
    ['Teach Me', 'plan', {}],
    ['Walk through step by step', 'plan', {}],
    ['Open HTML review', 'plan', {}],
    ['Loop back', 'build', { gate: 'fail' }],
    ['Override and continue', 'plan', {}],
    ['Architecture Depth Review', 'review', {}],
    ['Review config suggestions', 'check', { configSuggestions: true }],
    ['Change', 'build', {}],
    ['Stop', 'build', {}],
    ['Commit', 'done', {}],
    ['Other', 'plan', {}],
  ]
  // The original wording and the button label that carries it.
  const SAME: Record<string, string> = { 'Override and continue': 'Skip with a reason', Other: 'Discuss' }
  for (const [option, phase, ctx] of ORIGINAL) {
    test(option, () => {
      const set = phase === 'done' ? doneActions() : actionsFor(phase, ctx)
      const all = [...set.primary, set.discuss, ...(set.override ? [set.override] : []), ...set.more].map(a => a.label.toLowerCase())
      const wanted = (SAME[option] ?? option).toLowerCase()
      expect(all.some(l => l === wanted || l.startsWith(wanted)), `${option} -> ${wanted} in ${all.join(', ')}`).toBe(true)
    })
  }

  test('each is reachable in at most two presses: a digit, or 0 then a digit', () => {
    for (const p of PHASES) {
      const a = actionsFor(p, { configSuggestions: true, hasFindings: true })
      for (const x of [...a.primary, a.discuss, ...(a.override ? [a.override] : [])]) expect(/^[1-9]$/.test(x.key)).toBe(true)
      for (const x of a.more) expect(/^[1-9]$/.test(x.key)).toBe(true)
    }
  })
})
