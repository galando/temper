import { describe, expect, test } from 'claude-code/testing'

import { ACT, DISCUSS, SHOW, actionsFor, doneActions, findingActions, nextStep, nowText } from '../../hooks/temper-mod/core/actions'
import type { Action, ActionContext } from '../../hooks/temper-mod/core/actions'
import { PHASES } from '../../hooks/temper-mod/core/events'

type P = Parameters<typeof actionsFor>[0]
const labels = (phase: P, ctx: ActionContext = {}) => actionsFor(phase, ctx).primary.map(a => a.label)
const menu = (phase: P, ctx: ActionContext = {}) => actionsFor(phase, ctx).more.map(a => a.label)

// A checkpoint of Build (one task per launch) and the completion gate of Build.
const CHECKPOINT: ActionContext = { gate: 'fail', task: { n: 2, of: 3 }, tasksLeft: 2 }
const COMPLETION: ActionContext = { gate: 'fresh', ready: true, task: { n: 3, of: 3 }, tasksLeft: 0 }

// The options of the original orchestrator (commands/temper.md) that a button may carry. The script
// scripts/check-original-options.sh keeps this list in step with that file. "Continue to", "Loop back to"
// and "Continue with task" take a suffix. Besides them only the explicit extras below are allowed.
const ORIGINAL = [
  'Continue to',
  'Continue with task',
  'Loop back to',
  'Save for later',
  'Grill me',
  'Teach me',
  'Walk through step by step',
  'Open HTML review',
  'Share HTML review',
  'Architecture depth review',
  'Review config suggestions',
  'Change',
  'Stop',
  'Commit',
  'Start Intent',
  'Run Intent',
  'Run Plan',
  'Run Build',
  'Run Review',
  'Run Check',
]
const ALLOWED_EXTRA = [
  'Discuss',
  'Play while you wait',
  'Skip with a reason',
  'Resume',
  'Fix the failures',
  'Fix the findings',
  'Fix',
  'Accept',
  'Explain',
  'Loop back to Plan',
  // The person's last move is not recorded in the CLI yet: key 1 records it again (no new choice).
  'Record my choice',
]
const allowedLabel = (label: string): boolean => {
  const l = label.toLowerCase()
  return [...ORIGINAL, ...ALLOWED_EXTRA].some(o => l === o.toLowerCase() || l.startsWith(`${o.toLowerCase()} `))
}

const STATES: ActionContext[] = [
  {},
  { ready: true, gate: 'fresh' },
  { gate: 'fail' },
  { gate: 'stale' },
  { hasFindings: true },
  { allChecksPass: true, ready: true, gate: 'fresh' },
  { loopLimitReached: true },
  { paused: true, configSuggestions: true, task: { n: 2, of: 5 } },
  CHECKPOINT,
  COMPLETION,
  { configSuggestions: true },
  { pending: true, gate: 'fresh', ready: true },
]

const everyAction = (): Array<{ where: string; x: Action }> => {
  const out: Array<{ where: string; x: Action }> = []
  for (const p of PHASES) for (const ctx of STATES) {
    const a = actionsFor(p, ctx)
    for (const x of [...a.primary, a.discuss, ...(a.override ? [a.override] : []), ...a.more]) out.push({ where: `${p} ${JSON.stringify(ctx)}`, x })
  }
  for (const x of [...doneActions().primary, doneActions().discuss]) out.push({ where: 'done', x })
  for (const x of findingActions('1')) out.push({ where: 'finding', x })
  return out
}

describe('only the original options, plus Discuss, Play and Skip', () => {
  test('every label of every phase and state is an original option or an explicit extra', () => {
    for (const { where, x } of everyAction()) expect(allowedLabel(x.label), `${where}: "${x.label}" is not an original option`).toBe(true)
  })

  test('the removed buttons are gone everywhere', () => {
    const gone = [
      'Ask me questions', 'Edit the intent', 'Make the plan', 'Show the files', 'Try another plan', 'Split the tasks', 'Run the tests',
      'Show the changes', 'Review again', 'Run failed checks again', 'Show the failures', 'Write the PR text', 'Show the timeline',
      'Save my request', 'Fix the problems', 'Pause the run', 'Resume the run', 'Take over', 'Plan again',
    ]
    const all = everyAction().map(e => e.x.label)
    for (const g of gone) expect(all, g).not.toContain(g)
    for (const { where, x } of everyAction()) expect(/^Go back to/.test(x.label), `${where}: ${x.label}`).toBe(false)
  })
})

describe('keys 1 to 4 per phase', () => {
  test('every phase has keys 1, 2, 3, Discuss on 4 and a skip on 9', () => {
    for (const p of PHASES) {
      const a = actionsFor(p, {})
      expect(a.primary.map(x => x.key)).toEqual(['1', '2', '3'])
      expect(a.discuss.key).toBe('4')
      expect(a.override?.key).toBe('9')
      expect(a.override?.asksReason).toBe(true)
    }
  })

  test('Intent: Continue to Plan, Grill me, Teach me', () => {
    expect(labels('intent', { ready: true, gate: 'fresh' })).toEqual(['Continue to Plan', 'Grill me', 'Teach me'])
    expect(labels('intent', { gate: 'none' })).toEqual(['Start Intent', 'Grill me', 'Teach me'])
    expect(menu('intent')).toEqual(['Save for later'])
  })

  test('Plan: Continue to Build, Walk through step by step, Open HTML review', () => {
    expect(labels('plan', { ready: true, gate: 'fresh' })).toEqual(['Continue to Build', 'Walk through step by step', 'Open HTML review'])
    expect(menu('plan')).toEqual(['Grill me', 'Teach me', 'Share HTML review', 'Save for later'])
  })

  test('Build checkpoint: Continue with task N, Change, Stop', () => {
    expect(labels('build', CHECKPOINT)).toEqual(['Continue with task 2', 'Change', 'Stop'])
    expect(menu('build', CHECKPOINT)).toEqual(['Grill me', 'Teach me', 'Save for later'])
  })

  test('Build completion gate: Continue to Review, Teach me, Grill me; Loop back to Plan under More', () => {
    expect(labels('build', COMPLETION)).toEqual(['Continue to Review', 'Teach me', 'Grill me'])
    expect(menu('build', COMPLETION)).toEqual(['Loop back to Plan', 'Save for later'])
  })

  test('Review: Continue to Check, Architecture depth review, Grill me', () => {
    expect(labels('review', { ready: true, gate: 'fresh' })).toEqual(['Continue to Check', 'Architecture depth review', 'Grill me'])
    expect(menu('review', { ready: true, gate: 'fresh' })).toEqual(['Teach me', 'Loop back to Build', 'Save for later'])
  })

  test('Check: Continue to Commit, then config suggestions only when the file exists', () => {
    const ok = { ready: true, gate: 'fresh' as const }
    expect(labels('check', { ...ok, configSuggestions: true })).toEqual(['Continue to Commit', 'Review config suggestions', 'Teach me'])
    expect(labels('check', ok)).toEqual(['Continue to Commit', 'Grill me', 'Teach me'])
    expect(menu('check', ok)).toEqual(['Save for later'])
  })

  test('a failed check: Loop back is key 1, and it is not listed twice', () => {
    expect(labels('plan', { gate: 'fail' })[0]).toBe('Loop back to Intent')
    expect(labels('review', { gate: 'fail' })[0]).toBe('Loop back to Build')
    expect(labels('build', { gate: 'fail', task: { n: 3, of: 3 }, tasksLeft: 0 })[0]).toBe('Loop back to Plan')
    expect(menu('build', { gate: 'fail', task: { n: 3, of: 3 }, tasksLeft: 0 })).toEqual(['Save for later'])
    expect(menu('review', { gate: 'fail' })).not.toContain('Loop back to Build')
    const loop = actionsFor('build', { gate: 'fail', task: null, tasksLeft: null }).primary[0]
    expect(loop?.command).toBe('back plan')
    expect(loop?.asksReason).toBe(true)
    expect(loop?.resume).toBe(true)
  })

  test('a failed build check while tasks are open is a checkpoint, not a failure', () => {
    expect(labels('build', CHECKPOINT)[0]).toBe('Continue with task 2')
    expect(actionsFor('build', CHECKPOINT).primary[0]?.resume).toBe(true)
    expect(labels('build', { gate: 'fail', task: null, tasksLeft: null })[0]).toBe('Loop back to Plan')
  })

  test('key 1 starts or runs the stage when no check result is there yet', () => {
    expect(labels('plan', { gate: 'none' })[0]).toBe('Run Plan')
    expect(labels('plan', { gate: 'stale' })[0]).toBe('Run Plan')
    expect(labels('check', { gate: 'none' })[0]).toBe('Run Check')
    const run = actionsFor('plan', { gate: 'none' }).primary[0]
    expect(run?.resume).toBe(true)
    expect(run?.prompt).toBeUndefined()
    expect(run?.command).toBeUndefined()
  })

  test('a move that is not recorded in the CLI: key 1 records it again, in every phase', () => {
    for (const p of PHASES) {
      const first = actionsFor(p, { pending: true, ready: true, gate: 'fresh' }).primary[0]
      expect(first?.label).toBe('Record my choice')
      expect(first?.record).toBe(true)
      expect(first?.command).toBeUndefined()
      expect(first?.prompt).toBeUndefined()
    }
  })

  test('Continue records the move and then runs the orchestrator', () => {
    const plan = actionsFor('plan', { ready: true, gate: 'fresh' }).primary[0]
    expect(plan?.command).toBe('approve')
    expect(plan?.resume).toBe(true)
    expect(actionsFor('build', COMPLETION).primary[0]?.command).toBe('next')
  })

  test('Fix: the limit has Loop back to Plan, Skip with a reason, Save for later; else the fix keys', () => {
    expect(labels('fix', { loopLimitReached: true })).toEqual(['Loop back to Plan', 'Skip with a reason', 'Save for later'])
    expect(labels('fix')).toEqual(['Fix the failures', 'Fix the findings', 'Continue to Check'])
  })

  test('Fix with the check already passing again: key 1 is Continue to Check', () => {
    const a = actionsFor('fix', { allChecksPass: true, gate: 'fresh' })
    expect(a.primary.map(x => x.label)).toEqual(['Continue to Check', 'Fix the failures', 'Fix the findings'])
    expect(a.primary[0]?.command).toBe('next')
    expect(a.primary[0]?.resume).toBe(true)
    expect(a.primary.map(x => x.key)).toEqual(['1', '2', '3'])
  })

  test('the Done phase: Commit, Save for later, Discuss', () => {
    const d = doneActions()
    expect(d.primary.map(a => a.label)).toEqual(['Commit', 'Save for later'])
    expect(d.primary.map(a => a.key)).toEqual(['1', '2'])
    expect(d.discuss.key).toBe('4')
    expect(d.override).toBeNull()
    expect(d.primary[0]?.prompt).toContain('Do not push')
    expect(d.more).toEqual([])
  })

  test('Change and Discuss put a draft in the prompt box and change nothing', () => {
    const change = actionsFor('build', CHECKPOINT).primary[1]
    expect(change?.fill).toBe('Change this task: ')
    expect(change?.prompt).toBeUndefined()
    expect(change?.command).toBeUndefined()
    expect(DISCUSS.fill).toBe('Discuss this step: ')
    expect(DISCUSS.desc).toBe('Type your own message about this step.')
  })

  test('Stop pauses the run and asks for the build check', () => {
    const stop = actionsFor('build', CHECKPOINT).primary[2]
    expect(stop?.command).toBe('pause')
    expect(stop?.prompt).toContain('gate build')
  })

  test('key 9 says what it does: skip with a reason', () => {
    for (const p of PHASES) expect(actionsFor(p, {}).override?.label).toBe('Skip with a reason')
  })
})

describe('the menu on key 0', () => {
  test('a paused run offers Resume where it offers Save for later', () => {
    expect(menu('intent', { paused: true })).toEqual(['Resume'])
    expect(menu('build', { ...CHECKPOINT, paused: true })).toContain('Resume')
    expect(menu('build', { ...CHECKPOINT, paused: true })).not.toContain('Save for later')
  })

  test('digits 1 to 9 in order, at least one entry, at most nine, no label twice', () => {
    for (const p of PHASES) for (const ctx of STATES) {
      const m = actionsFor(p, ctx).more
      expect(m.length).toBeGreaterThan(0)
      expect(m.length).toBeLessThanOrEqual(9)
      expect(m.map(a => a.key)).toEqual(['1', '2', '3', '4', '5', '6', '7', '8', '9'].slice(0, m.length))
      expect(new Set(m.map(a => a.label)).size).toBe(m.length)
    }
  })

  test('no label repeats between the main buttons and the menu of one phase', () => {
    for (const p of PHASES) for (const ctx of STATES) {
      const a = actionsFor(p, ctx)
      const main = [...a.primary, a.discuss, ...(a.override ? [a.override] : [])].map(x => x.label)
      for (const m of a.more) expect(main, `${p} ${JSON.stringify(ctx)}`).not.toContain(m.label)
    }
  })
})

describe('shape of every action', () => {
  test('every action does exactly one kind of thing: prompt, command, launch or draft', () => {
    for (const { where, x } of everyAction()) {
      const kinds = [Boolean(x.prompt), Boolean(x.command), Boolean(x.fill), Boolean(x.record), Boolean(x.resume && !x.command && !x.prompt)].filter(Boolean).length
      // Stop records (pause) and asks (the build check). A command can also resume the orchestrator.
      const ok = kinds >= 1 && (kinds === 1 || x.id === 'stop' || Boolean(x.command && x.resume)) || x.id === 'save-done'
      expect(ok, `${where} ${x.id}`).toBe(true)
    }
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

  test('no em or en dashes in any label, line or prompt', () => {
    for (const { x } of everyAction()) expect(/[–—]/.test(`${x.label}${x.desc}${x.prompt ?? ''}${x.command ?? ''}${x.fill ?? ''}`)).toBe(false)
  })
})

// Every label is easy to read: 1 to 5 words, no internal word. Every action has one short line of its own, and
// every prompt tells Claude to act now.
describe('easy words (labels, lines and prompts)', () => {
  const words = (s: string): string[] => s.trim().split(/\s+/)

  test('every label is 1 to 5 words', () => {
    for (const { where, x } of everyAction()) {
      const n = words(x.label).length
      expect(n >= 1 && n <= 5, `${where}: "${x.label}" has ${n} words`).toBe(true)
    }
  })

  test('every action has one line of 10 words at most, and no label or line holds an internal word', () => {
    for (const { where, x } of everyAction()) {
      expect(x.desc.length > 0, `${where}: "${x.label}" has no line`).toBe(true)
      expect(words(x.desc).length <= 10, `${where}: "${x.label}" line is too long: ${x.desc}`).toBe(true)
      expect(/\b(gate|override|verdict|criterion|criteria|goals?)\b/i.test(`${x.label} ${x.desc}`), `${where}: "${x.label}"`).toBe(false)
    }
  })

  test('every prompt tells Claude to act now and keep it short', () => {
    for (const { where, x } of everyAction()) {
      if (!x.prompt) continue
      expect(x.prompt.endsWith(ACT) || x.prompt.endsWith(SHOW), `${where}: ${x.label}`).toBe(true)
    }
  })

  test('the narrow label of every action is short enough for 80 columns', () => {
    for (const { where, x } of everyAction()) {
      const narrow = x.short ?? x.label
      expect(narrow.length <= 20 || x.key === '4', `${where}: "${narrow}"`).toBe(true)
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

// Every question of the original orchestrator (commands/temper.md) is reachable with the same words, in
// one digit or 0 and one digit. scripts/check-original-options.sh keeps the list in step with that file.
describe('every original option maps to a button', () => {
  const find = (phase: P | 'done', ctx: ActionContext, wanted: string): boolean => {
    const set = phase === 'done' ? doneActions() : actionsFor(phase, ctx)
    const all = [...set.primary, set.discuss, ...(set.override ? [set.override] : []), ...set.more].map(a => a.label.toLowerCase())
    return all.some(l => l === wanted.toLowerCase() || l.startsWith(`${wanted.toLowerCase()} `))
  }
  const TABLE: Array<[string, P | 'done', ActionContext, string]> = [
    ['Continue to', 'plan', { ready: true, gate: 'fresh' }, 'Continue to'],
    ['Save for later', 'plan', {}, 'Save for later'],
    ['Grill Me', 'plan', {}, 'Grill me'],
    ['Teach Me', 'plan', {}, 'Teach me'],
    ['Walk through step by step', 'plan', {}, 'Walk through step by step'],
    ['Open HTML review', 'plan', {}, 'Open HTML review'],
    ['Share HTML review', 'plan', {}, 'Share HTML review'],
    ['Loop back', 'review', { gate: 'fail' }, 'Loop back to'],
    ['Override and continue', 'plan', {}, 'Skip with a reason'],
    ['Architecture Depth Review', 'review', {}, 'Architecture depth review'],
    ['Review config suggestions', 'check', { configSuggestions: true }, 'Review config suggestions'],
    ['Change', 'build', CHECKPOINT, 'Change'],
    ['Stop', 'build', CHECKPOINT, 'Stop'],
    ['Commit', 'done', {}, 'Commit'],
    ['Other', 'plan', {}, 'Discuss'],
  ]
  for (const [option, phase, ctx, label] of TABLE) test(option, () => expect(find(phase, ctx, label), `${option} -> ${label}`).toBe(true))

  test('each is reachable in at most two presses: a digit, or 0 then a digit', () => {
    for (const p of PHASES) {
      const a = actionsFor(p, { configSuggestions: true, hasFindings: true })
      for (const x of [...a.primary, a.discuss, ...(a.override ? [a.override] : [])]) expect(/^[1-9]$/.test(x.key)).toBe(true)
      for (const x of a.more) expect(/^[1-9]$/.test(x.key)).toBe(true)
    }
  })
})
