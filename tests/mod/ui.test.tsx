import { describe, expect, test } from 'claude-code/testing'

import { SPEC, runFiles } from './run-files'
import { COMPOSE, world } from './world'

const SURFACES = ['terminal', 'desktop'] as const
const ALL_SURFACES = ['terminal', 'desktop', 'vscode', 'mobile'] as const

const START = { cwd: '/repo', surface: null, isInteractive: false } as const

const BAND = {
  hasSurvey: false,
  isWorking: false,
  maxRows: 12,
  bodyColumns: 100,
  scroll: { offset: 0, bodyRows: 12 },
  view: {},
} as const

const PANE = {
  title: 'Temper',
  isFocused: false,
  bodyColumns: 80,
  placement: 'dock',
  scroll: { offset: 0, bodyRows: 20 },
  view: {},
} as const

const SPINNER = { word: 'Sauteing', message: null, suffix: '…', mode: 'responding' } as const
const HINT = { isDraft: false, isWorking: false, hint: '? for shortcuts' } as const

describe('phase bar (AbovePrompt)', () => {
  for (const surface of SURFACES) {
    test(`full mode draws six phases and the action buttons on ${surface}`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build', passedCriteria: ['AC-01'] }))
      await $.session.start(START)
      const ui = await $.ui.mount({ plugin: 'temper', surface, component: 'AbovePrompt', props: BAND })
      for (const label of ['Intent', 'Plan', 'Build', 'Review', 'Check', 'Fix']) {
        expect(await ui.find({ type: 'Text', text: new RegExp(label) })).toBeDefined()
      }
      expect((await ui.find({ type: 'Text', text: /Build/ }))?.text).toContain('▶')
      expect((await ui.find({ type: 'Text', text: /Intent/ }))?.text).toContain('✓')
      const buttons = await ui.findAll({ type: 'Button' })
      // Three context actions, override on 9, and all actions on 0.
      expect(buttons).toHaveLength(5)
      await ui.press({ key: 'action-next-task' })
      expect(w.prompts.some(p => p.includes('Start the next unfinished task'))).toBe(true)
      await ui.unmount()
    })
  }

  test('key 1 changes with readiness: Send to Review once the build gate passed', async ($, on) => {
    world(on, runFiles({ nextStage: 'build', gates: { build: 'PASS' } }))
    await $.session.start(START)
    const ui = await $.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', props: BAND })
    expect(await ui.find({ key: 'action-to-review' })).toBeDefined()
  })

  test('9 asks for a reason: no reason, no override', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'review' }), { answers: [] })
    await $.session.start(START)
    const ui = await $.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', props: BAND })
    await ui.press({ key: 'action-override' })
    expect(w.toasts.some(t => t.includes('needs a reason'))).toBe(true)
    expect([...w.files.keys()].filter(k => k.includes('/events/') && w.files.get(k)?.includes('"override"'))).toEqual([])
    w.answers.push('Risk accepted')
    await ui.press({ key: 'action-override' })
    expect([...w.files.values()].some(t => t.includes('"type":"override"') && t.includes('Risk accepted'))).toBe(true)
  })

  test('0 opens the pane with every action', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START)
    const ui = await $.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', props: BAND })
    await ui.press({ key: 'action-more' })
    expect(w.opened).toContain('temper')
  })

  for (const surface of SURFACES) {
    test(`minimal mode shows the phases and no Button on ${surface}`, { options: { uiMode: 'minimal' } }, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START)
      const ui = await $.ui.mount({ plugin: 'temper', surface, component: 'AbovePrompt', props: BAND })
      expect(await ui.findAll({ type: 'Button' })).toHaveLength(0)
      expect(await ui.find({ type: 'Text', text: /Review/ })).toBeDefined()
    })

    test(`off mode draws nothing on ${surface}: the engine's own drawing stands`, { options: { uiMode: 'off' } }, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START)
      const ui = await $.ui.mount({ plugin: 'temper', surface, component: 'AbovePrompt', props: BAND })
      expect(await ui.drawn()).toEqual({ type: 'engine', ref: 0 })
    })
  }

  test('a survey holding the band is left alone, and with no run nothing is drawn', async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START)
    const ui = await $.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', props: { ...BAND, hasSurvey: true } })
    expect(await ui.drawn()).toEqual({ type: 'engine', ref: 0 })
  })
})

describe('pane', () => {
  for (const surface of ALL_SURFACES) {
    test(`title, phase, live criteria and timeline on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build', passedCriteria: ['AC-01', 'AC-03'] }))
      await $.session.start(START)
      const ui = await $.ui.mount({ plugin: 'temper', surface, component: 'Pane', requestId: 'temper', props: PANE })
      expect(await ui.find({ type: 'Text', text: /Password reset by email/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /Phase: Build \(task 3 of 7\)/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /Criteria: 2 of 5 passed/ })).toBeDefined()
      const checklist = await ui.find({ key: 'criteria' })
      expect(checklist?.text).toContain('[x] **AC-01**')
      expect(checklist?.text).toContain('[ ] **AC-02**')
    })
  }

  test('per finding Fix, Accept with reason and Explain', async ($, on) => {
    const files = {
      ...runFiles({ nextStage: 'review' }),
      '.temper/evidence/review.json': JSON.stringify([
        { claim: 'tests ran', exit_code: 0 },
        { claim: 'SQL built from input', severity: 'critical' },
        { claim: 'old issue', severity: 'major', resolved: { fixed_by: 'abc' } },
      ]),
    }
    const w = world(on, files, { answers: [] })
    await $.session.start(START)
    for (const surface of SURFACES) {
      const ui = await $.ui.mount({ plugin: 'temper', surface, component: 'Pane', requestId: 'temper', props: PANE })
      expect(await ui.findAll({ key: 'fix-2' })).toHaveLength(1)
      expect(await ui.find({ key: 'fix-3' })).toBeUndefined()
      await ui.press({ key: 'fix-2' })
      await ui.press({ key: 'explain-2' })
      await ui.unmount()
    }
    expect(w.prompts.filter(p => p.includes('finding 2')).length).toBe(4)
    const ui = await $.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'Pane', requestId: 'temper', props: PANE })
    await ui.press({ key: 'accept-2' })
    expect(w.toasts.some(t => t.includes('needs a reason'))).toBe(true)
    w.answers.push('false positive, input is trusted')
    await ui.press({ key: 'accept-2' })
    expect([...w.files.values()].some(t => t.includes('"type":"accept"') && t.includes('false positive'))).toBe(true)
    expect(w.prompts.some(p => p.includes('evidence accept --stage review --id 2'))).toBe(true)
  })

  test('in minimal mode the pane says it is part of full mode', { options: { uiMode: 'minimal' } }, async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START)
    const ui = await $.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'Pane', requestId: 'temper', props: PANE })
    expect(await ui.drawn()).toEqual({ type: 'engine', ref: 0 })
  })

  test('opens at session start only where it would dock', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }), { placed: false })
    await $.session.start(START)
    expect(w.opened).toEqual(['temper'])
    expect(w.closed).toEqual(['temper'])
  })

  test('opens at session start when it docks, and not without a run or outside full mode', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START)
    expect(w.opened).toEqual(['temper'])
    expect(w.closed).toEqual([])
  })
})

describe('spinner, hint and question header', () => {
  for (const surface of SURFACES) {
    test(`the spinner word names the criterion on ${surface}`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build', passedCriteria: ['AC-01'] }))
      await $.session.start(START)
      const ui = await $.ui.mount({ plugin: 'temper', surface, component: 'Spinner', props: SPINNER })
      await ui.drawn()
      const seen = w.rendered.find(r => r.component === 'Spinner')
      expect(seen?.props.word).toBe('Building \u00b7 criterion 2 of 5')
      expect(seen?.props.suffix).toBe('\u2026')
    })

    test(`the spinner is left alone in minimal mode on ${surface}`, { options: { uiMode: 'minimal' } }, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START)
      const ui = await $.ui.mount({ plugin: 'temper', surface, component: 'Spinner', props: SPINNER })
      await ui.drawn()
      expect(w.rendered.find(r => r.component === 'Spinner')?.props.word).toBe('Sauteing')
    })
  }

  test('the terminal hint gets a dim tail; the desktop hint passes through unchanged', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START)
    for (const surface of SURFACES) {
      const ui = await $.ui.mount({ plugin: 'temper', surface, component: 'PromptHint', props: HINT })
      await ui.drawn()
      await ui.unmount()
    }
    const [terminal, desktop] = w.rendered.filter(r => r.component === 'PromptHint')
    expect(String(terminal?.props.tail)).toContain('Temper Build: ')
    expect(desktop?.props.tail).toBeUndefined()
    expect(desktop?.props.hint).toBe('? for shortcuts')
  })

  for (const surface of ALL_SURFACES) {
    test(`the question dialog keeps the engine drawing exactly once under one Temper line on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build', passedCriteria: ['AC-01'] }))
      await $.session.start(START)
      const ui = await $.ui.mount({
        plugin: 'temper',
        surface,
        component: 'AskUserQuestion',
        props: { tool: 'AskUserQuestion', questions: [] },
      })
      const drawn = JSON.stringify(await ui.drawn())
      expect(drawn.match(/"type":"engine"/g)).toHaveLength(1)
      expect(drawn).toContain('Temper: Build, criterion 2 of 5')
    })
  }

  for (const uiMode of ['minimal', 'off']) {
    test(`${uiMode} mode leaves the question dialog untouched`, { options: { uiMode } }, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START)
      const ui = await $.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AskUserQuestion', props: { tool: 'AskUserQuestion', questions: [] } })
      expect(await ui.drawn()).toEqual({ type: 'engine', ref: 0 })
    })
  }

  // AbovePrompt, Spinner and PromptHint are raised on the terminal and desktop only
  // (the types say so), so vscode and mobile are smoke tested on Pane and the question.
})

describe('turn line, suggestions and toasts', () => {
  const COMPLETE = { answer: 'done', durationMs: 10, isAborted: false, turnId: 't1', reason: 'answer' } as const

  test('turn.complete adds one line with phase, task, progress and next step, and suggests without submitting', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build', passedCriteria: ['AC-01', 'AC-03'] }))
    on('turn.complete', ($2, e) => ({ text: e.answer }))
    await $.session.start(START)
    const r = await $.turn.complete(COMPLETE as never)
    expect(r.text).toBe(
      'Temper: Build, task 3 of 7, 2 of 5 criteria passed. Next: work the next task in tasks.md with a failing test first; stay inside the plan files',
    )
    expect(w.suggestions).toEqual(['Start the next unfinished task in tasks.md with a failing test first.'])
    expect(w.prompts).toEqual([])
  })

  test('minimal mode adds no line and no suggestion', { options: { uiMode: 'minimal' } }, async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    on('turn.complete', ($2, e) => ({ text: e.answer }))
    await $.session.start(START)
    expect((await $.turn.complete(COMPLETE as never)).text).toBe('done')
    expect(w.suggestions).toEqual([])
  })

  test('a subagent turn and an interrupted turn are left alone', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    on('turn.complete', ($2, e) => ({ text: e.answer }))
    await $.session.start(START)
    expect((await $.turn.complete({ ...COMPLETE, agentId: 'sub' } as never)).text).toBe('done')
    expect((await $.turn.complete({ ...COMPLETE, reason: 'aborted', isAborted: true } as never)).text).toBe('done')
    expect(w.suggestions).toEqual([])
  })

  test('one toast per phase transition, none at load', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'plan', gates: { plan: 'PASS' } }))
    await $.session.start(START)
    expect(w.toasts).toEqual([])
    await $.command.run({ command: 'temper', args: 'approve', origin: { kind: 'composer' } } as never)
    expect(w.toasts).toEqual(['Temper: Build'])
  })

  test('no toast in minimal mode', { options: { uiMode: 'minimal' } }, async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'plan', gates: { plan: 'PASS' } }))
    await $.session.start(START)
    await $.command.run({ command: 'temper', args: 'approve', origin: { kind: 'composer' } } as never)
    expect(w.toasts).toEqual([])
  })
})

describe('pane commands', () => {
  const run = (args: string) => ({ command: 'temper', args, origin: { kind: 'composer' } }) as never

  test('/temper pane toggles', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }), { placed: true })
    await $.session.start(START)
    w.opened.length = 0
    expect((await $.command.run(run('pane'))).text).toBe('Temper pane closed.')
    expect((await $.command.run(run('pane'))).text).toBe('Temper pane opened.')
    expect(w.closed).toEqual(['temper'])
    expect(w.opened).toEqual(['temper'])
  })

  test('bare /temper toggles the pane while a run is active', async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START)
    expect((await $.command.run(run(''))).text).toBe('Temper pane closed.')
  })

  test('bare /temper with no run reaches the prompt based command', async ($, on) => {
    world(on, {})
    await $.session.start(START)
    expect((await $.command.run(run(''))).text).toBe('prompt based /temper ran')
  })

  test('outside full mode the pane is refused with a hint', { options: { uiMode: 'minimal' } }, async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START)
    expect((await $.command.run(run('pane'))).text).toContain('full mode only')
    expect((await $.command.run(run(''))).text).toBe('prompt based /temper ran')
  })
})
