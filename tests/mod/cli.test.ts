import { describe, expect, test } from 'claude-code/testing'

import { CLI, CLI_STAGES, advanceCommands } from '../../hooks/temper-mod/core/cli'
import { followUp } from '../../hooks/temper-mod/core/commands'
import type { Draft, Phase } from '../../hooks/temper-mod/core/events'
import { ONLY_USER } from '../../hooks/temper-mod/core/machine'
import { evaluate } from '../../hooks/temper-mod/core/rules'
import type { HumanDecision } from '../../hooks/temper-mod/core/rules'
import { person, stateAt } from './helpers'
import { SPEC, runFiles } from './run-files'
import { world } from './world'

const ctx = { specDir: SPEC, planFiles: [] as string[] }
const bash = (command: string) => ({ tool: 'Bash', input: { command } })

type Move = { name: string; draft: Draft; phaseAfter: Phase; decision: HumanDecision | null; guarded: boolean }

// One row per move the person can make with a button, with the human decision the mod records.
const MOVES: Move[] = [
  { name: 'approve intent', draft: { type: 'advance', from: 'intent', to: 'plan', ...person }, phaseAfter: 'plan', decision: { id: 'e1', kind: 'advance', phase: 'intent' }, guarded: true },
  { name: 'approve plan', draft: { type: 'advance', from: 'plan', to: 'build', ...person }, phaseAfter: 'build', decision: { id: 'e2', kind: 'advance', phase: 'plan' }, guarded: true },
  { name: 'build to review', draft: { type: 'advance', from: 'build', to: 'review', ...person }, phaseAfter: 'review', decision: { id: 'e7', kind: 'advance', phase: 'build' }, guarded: true },
  { name: 'review to check', draft: { type: 'advance', from: 'review', to: 'check', ...person }, phaseAfter: 'check', decision: { id: 'e8', kind: 'advance', phase: 'review' }, guarded: true },
  { name: 'check pass (done)', draft: { type: 'advance', from: 'check', to: 'done', ...person }, phaseAfter: 'check', decision: { id: 'e9', kind: 'advance', phase: 'check' }, guarded: true },
  { name: 'back to plan', draft: { type: 'back', to: 'plan', reason: 'need a cache layer', ...person }, phaseAfter: 'plan', decision: { id: 'e5', kind: 'back', phase: 'plan' }, guarded: true },
  { name: 'override in fix', draft: { type: 'override', phase: 'fix', reason: 'ship it', ...person }, phaseAfter: 'check', decision: { id: 'e6', kind: 'override', phase: 'check' }, guarded: true },
  { name: 'override review', draft: { type: 'override', phase: 'review', reason: 'reviewer is on leave', ...person }, phaseAfter: 'check', decision: { id: 'e3', kind: 'override', phase: 'review' }, guarded: true },
  { name: 'accept finding 2', draft: { type: 'accept', findingId: '2', reason: 'false positive', ...person }, phaseAfter: 'review', decision: { id: 'e4', kind: 'accept', phase: 'review', findingId: '2' }, guarded: true },
]

// The commands a prompt names: every backticked span.
// A reason can hold backticks, so the span ends at the backtick that is followed by a space, a full stop or the end.
// The path in front of scripts/temper may be the plugin folder (a full path); it is cut so the rest compares.
const commandsIn = (text: string): string[] =>
  [...text.matchAll(/`((?:\/\S*)?scripts\/temper(?:[^`]|`(?![ .]|$))+)`/g)].map(m => (m[1] ?? '').replace(/^\/\S*?scripts\/temper/, 'scripts/temper'))

describe('follow up prompts name the exact CLI command and say the decision is recorded', () => {
  for (const m of MOVES) {
    test(m.name, () => {
      const text = followUp(m.draft) ?? ''
      expect(text).toContain('already recorded')
      // Short, and it tells Claude to act and not to narrate.
      expect(text.endsWith('Do this now. Reply with one short line.')).toBe(true)
      expect(text.split('. ').length).toBeLessThanOrEqual(8)
      expect(commandsIn(text).length).toBeGreaterThan(0)
      expect(commandsIn(text).every(c => c.startsWith(`${CLI} `))).toBe(true)
    })
  }

  test('a prompt for a move with no CLI stage names no command', () => {
    expect(commandsIn(followUp({ type: 'advance', from: 'fix', to: 'check', ...person }) ?? '')).toEqual([])
  })
})

describe('the command a prompt names goes through the real guard', () => {
  for (const m of MOVES) {
    test(`${m.name}: allowed${m.guarded ? ' once, a second time refused' : ''}`, () => {
      const cmds = commandsIn(followUp(m.draft) ?? '')
      const cmd = cmds[0] ?? ''
      const state = stateAt(m.phaseAfter)
      const pool = m.decision ? [m.decision] : []
      const first = evaluate(state, { ...ctx, humanDecisions: pool }, bash(cmd))
      expect('allow' in first).toBe(true)
      if (m.guarded) {
        expect('allow' in first && first.eventIds).toEqual([m.decision?.id])
        // The event is spent: the same call is refused.
        expect(evaluate(state, { ...ctx, humanDecisions: [] }, bash(cmd))).toEqual({ deny: ONLY_USER })
      } else {
        expect(evaluate(state, { ...ctx, humanDecisions: [] }, bash(cmd))).toHaveProperty('allow')
      }
    })
  }

  test('a model that invents the call without the person is refused', () => {
    for (const m of MOVES.filter(x => x.guarded)) {
      const cmd = commandsIn(followUp(m.draft) ?? '')[0] ?? ''
      expect(evaluate(stateAt(m.phaseAfter), { ...ctx, humanDecisions: [] }, bash(cmd))).toEqual({ deny: ONLY_USER })
    }
  })

  test('a decision for one phase does not authorize the call for another', () => {
    const planCall = commandsIn(followUp(MOVES[1]?.draft as Draft) ?? '')[0] ?? ''
    const intentOnly: HumanDecision[] = [{ id: 'e1', kind: 'advance', phase: 'intent' }]
    expect(evaluate(stateAt('build'), { ...ctx, humanDecisions: intentOnly }, bash(planCall))).toEqual({ deny: ONLY_USER })
  })
})

describe('plan with design', () => {
  test('medium and complex runs go through design, simple ones skip it', () => {
    expect(advanceCommands('plan', 'build', 'simple')).toEqual([`${CLI} state advance plan_complete build`])
    expect(advanceCommands('plan', 'build', null)).toEqual([`${CLI} state advance plan_complete build`])
    for (const c of ['medium', 'complex']) {
      expect(advanceCommands('plan', 'build', c)).toEqual([`${CLI} state advance plan_complete design`, `${CLI} state advance design_complete build`])
    }
  })

  test('both commands of a complex plan approval are allowed on one human event', () => {
    const cmds = commandsIn(followUp({ type: 'advance', from: 'plan', to: 'build', ...person }, 'complex') ?? '')
    expect(cmds).toHaveLength(2)
    const pool: HumanDecision[] = [{ id: 'e2', kind: 'advance', phase: 'plan' }]
    const c = { ...ctx, complexity: 'complex' }
    // The plan check passed and the plan was approved: design is the next stage and follows that verdict.
    const state = stateAt('build', [], { plan: { verdict: 'PASS', ts: 999_999_999 } })
    const first = evaluate(state, { ...c, humanDecisions: pool }, bash(cmds[0] ?? ''))
    expect('allow' in first && first.eventIds).toEqual(['e2'])
    expect('allow' in evaluate(state, { ...c, humanDecisions: [] }, bash(cmds[1] ?? ''))).toBe(true)
    // For a simple run design is not next: the same call is refused.
    expect('deny' in evaluate(state, { ...ctx, humanDecisions: [] }, bash(cmds[1] ?? ''))).toBe(true)
  })
})

describe('every command in a follow up prompt is a valid scripts/temper invocation', () => {
  const stages = CLI_STAGES.split(' ')
  const phases = ['intent', 'plan', 'build', 'review', 'check', 'fix'] as const

  // Every draft the mod can turn into a prompt, with every complexity.
  const drafts: Draft[] = [
    ...phases.flatMap(from => (['intent', 'plan', 'build', 'review', 'check', 'fix', 'done'] as const).map(to => ({ type: 'advance', from, to, ...person }) as Draft)),
    ...phases.map(phase => ({ type: 'override', phase, reason: 'why', ...person }) as Draft),
    ...phases.map(to => ({ type: 'back', to, reason: 'why', ...person }) as Draft),
    { type: 'accept', findingId: '3', reason: 'why', ...person },
  ]

  const valid = (cmd: string): boolean => {
    const t = cmd.split(/\s+/)
    if (t[0] !== CLI) return false
    if (t[1] === 'state' && t[2] === 'advance') {
      const stage = (t[3] ?? '').replace(/_complete$/, '')
      return t.length === 5 && (t[3] ?? '').endsWith('_complete') && stages.includes(stage) && (stages.includes(t[4] ?? '') || t[4] === 'commit')
    }
    if (t[1] === 'state' && t[2] === 'set') return t.length === 5 && t[3] === 'next_stage' && stages.includes(t[4] ?? '')
    if (t[1] === 'override') return stages.includes(t[2] ?? '') && t[3] === '--reason' && cmd.includes("--reason '")
    if (t[1] === 'evidence' && t[2] === 'accept') return t[3] === '--stage' && t[4] === 'review' && t[5] === '--id' && /^\d+$/.test(t[6] ?? '') && t[7] === '--reason'
    return false
  }

  test('the table covers every kind of prompt', () => {
    expect(drafts.length).toBeGreaterThan(40)
  })

  for (const complexity of [null, 'simple', 'medium', 'complex']) {
    test(`complexity ${complexity}`, () => {
      for (const d of drafts) {
        const text = followUp(d, complexity)
        if (!text) continue
        for (const cmd of commandsIn(text)) {
          if (!valid(cmd)) throw new Error(`not a valid scripts/temper invocation: ${cmd} (from ${JSON.stringify(d)})`)
        }
      }
    })
  }

  test('no prompt carries the old, invalid form', () => {
    for (const d of drafts) expect(followUp(d) ?? '').not.toMatch(/state advance (intent|plan|build|review|check) /)
  })
})

describe('end to end through the band: the prompt the mod sends is runnable once', () => {
  test('approving the intent with key 1 sends a command the guard then allows exactly once', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'intent', gates: { intent: 'PASS' } }))
    await $.session.start({ cwd: '/repo', surface: null, isInteractive: false })
    const band = await $.ui.mount({
      plugin: 'temper',
      surface: 'terminal',
      component: 'AbovePrompt',
      props: { hasSurvey: false, isWorking: false, maxRows: 12, bodyColumns: 120, scroll: { offset: 0, bodyRows: 12 }, view: {} },
    })
    await band.press({ key: 'action-continue' })
    // The mod writes no mirror prompt for a move forward: the orchestrator does the On Continue steps of
    // the stage (its `state advance` is the mirror) and launches the next stage with its own brief.
    expect(w.prompts).toEqual([])
    expect(w.commandRuns).toEqual([{ command: 'temper:temper', args: 'continue intent', origin: 'plugin' }])
    // The orchestrator's call, with the full path of the plugin folder, is let through once.
    const cmd = `${CLI} state advance intent_complete plan`
    const first = await $.tool.call({ tool: 'Bash', command: cmd })
    expect(first.deny).toBeUndefined()
    expect(first.text).toBe('stub ran')
    const second = await $.tool.call({ tool: 'Bash', command: cmd })
    expect(second.deny).toContain('Only the user can approve this')
  })

  test('approving a complex plan: both design commands run, the first once', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'plan', complexity: 'complex', gates: { plan: 'PASS' } }))
    await $.session.start({ cwd: '/repo', surface: null, isInteractive: false })
    const band = await $.ui.mount({
      plugin: 'temper',
      surface: 'terminal',
      component: 'AbovePrompt',
      props: { hasSurvey: false, isWorking: false, maxRows: 12, bodyColumns: 120, scroll: { offset: 0, bodyRows: 12 }, view: {} },
    })
    await band.press({ key: 'action-continue' })
    expect(w.commandRuns).toEqual([{ command: 'temper:temper', args: 'continue plan', origin: 'plugin' }])
    const cmds = [`${CLI} state advance plan_complete design`, `${CLI} state advance design_complete build`]
    expect((await $.tool.call({ tool: 'Bash', command: cmds[0] ?? '' })).text).toBe('stub ran')
    expect((await $.tool.call({ tool: 'Bash', command: cmds[0] ?? '' })).deny).toContain('Only the user')
    expect((await $.tool.call({ tool: 'Bash', command: cmds[1] ?? '' })).text).toBe('stub ran')
  })
})

describe('where the script is', () => {
  const move = { type: 'advance', from: 'plan', to: 'build', ...person } as const

  test('with the plugin folder known, the prompt names the full path and nothing else changes', () => {
    const text = followUp(move, null, '/plugins/temper/scripts/temper') ?? ''
    expect(text).toContain('`/plugins/temper/scripts/temper state advance plan_complete build`')
    expect(text).not.toContain('`scripts/temper ')
    expect(text).not.toContain('plugin folder, not in the project')
  })

  test('with no path known, the prompt says the script is in the plugin folder, not in the project', () => {
    const text = followUp(move) ?? ''
    expect(text).toContain('`scripts/temper state advance plan_complete build`')
    expect(text).toContain('The script is in the Temper plugin folder, not in the project.')
    expect(text.endsWith('Do this now. Reply with one short line.')).toBe(true)
  })

  test('the real mod hands Claude a full path that ends in scripts/temper', async ($, on) => {
    // A move forward goes to the orchestrator; a step back (Loop back) still names the CLI command.
    const w = world(on, runFiles({ nextStage: 'review', gates: { review: 'FAIL' } }), { answers: ['the fix is not enough'] })
    await $.session.start({ cwd: '/repo', surface: null, isInteractive: false })
    const band = await $.ui.mount({
      plugin: 'temper',
      surface: 'terminal',
      component: 'AbovePrompt',
      props: { hasSurvey: false, isWorking: false, maxRows: 12, bodyColumns: 120, scroll: { offset: 0, bodyRows: 12 }, view: {} },
    })
    await band.press({ key: 'action-loop-back' })
    const prompt = w.prompts.find(p => p.includes('state set next_stage')) ?? ''
    expect(prompt).toMatch(/`\/\S+\/scripts\/temper state set next_stage build`/)
  })
})
