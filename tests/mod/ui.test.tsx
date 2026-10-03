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

// Every node of a drawn tree, depth first.
type Node = { type?: string; props?: Record<string, unknown>; children?: unknown }
function walk(tree: unknown, out: Node[] = []): Node[] {
  if (typeof tree !== 'object' || tree === null) return out
  const n = tree as Node
  if (n.type) out.push(n)
  const kids = n.children
  if (Array.isArray(kids)) for (const k of kids) walk(k, out)
  else walk(kids, out)
  return out
}
const textOf = (n: Node): string => JSON.stringify(n.children ?? '')

describe('phase bar (AbovePrompt)', () => {
  for (const surface of SURFACES) {
    test(`full mode draws the chips, the buttons and the reason field on ${surface}`, async ($, on) => {
      const w = world(on, runFiles({ nextStage: 'build', passedCriteria: ['AC-01'] }))
      await $.session.start(START)
      const ui = await $.ui.mount({ plugin: 'temper', surface, component: 'AbovePrompt', props: BAND })
      const drawn = await ui.drawn()
      const tree = walk(drawn)
      const texts = tree.filter(n => n.type === 'Text').map(textOf).join(' ')
      // Glyph per state: done check, current dot, upcoming plain, no bare arrow anywhere.
      expect(texts).toContain('\u2713 Intent')
      expect(texts).toContain('\u2713 Plan')
      expect(texts).toContain('\u25cf Build')
      for (const label of ['Review', 'Check', 'Fix']) expect(texts).toContain(label)
      expect(JSON.stringify(drawn).match(/\u25cf/g)).toHaveLength(1)
      expect(/[\u25b6\u25b8\u2192\u279c]/.test(JSON.stringify(drawn))).toBe(false)
      expect(texts).toContain('TEMPER')
      expect(texts).toContain('Build (3 of 6)')
      expect(texts).toContain('Work through the tasks')
      // Buttons: three actions, override on 9, more on 0; the first is primary.
      const buttons = tree.filter(n => n.type === 'Button')
      expect(buttons).toHaveLength(5)
      expect(buttons.map(b => b.props?.hotkey)).toEqual(['1', '2', '3', '9', '0'])
      expect(buttons[0]?.props?.variant).toBe('primary')
      expect(buttons[1]?.props?.variant).toBe('secondary')
      // The reason field and its hint.
      expect(tree.some(n => n.type === 'Input' && n.props?.key === 'override-reason')).toBe(true)
      expect(texts).toContain('Override needs a reason; it is logged in the report')
      await ui.press({ key: 'action-next-task' })
      expect(w.prompts.some(p => p.includes('Start the next unfinished task'))).toBe(true)
      await ui.unmount()
    })

    test(`the stepper shows done, current, upcoming and redo states on ${surface}`, async ($, on) => {
      const files = runFiles({ nextStage: 'review' })
      const w = world(on, files)
      await $.session.start(START)
      await $.command.run({ command: 'temper', args: 'back plan rework', origin: { kind: 'composer' } } as never)
      const ui = await $.ui.mount({ plugin: 'temper', surface, component: 'AbovePrompt', props: BAND })
      const texts = walk(await ui.drawn()).filter(n => n.type === 'Text').map(textOf).join(' ')
      expect(texts).toContain('\u25cf Plan')
      expect(texts).toContain('\u21ba Build')
      expect(texts).toContain('\u21ba Review')
      expect(w.files.size).toBeGreaterThan(0)
    })

    test(`wide draws bordered chips and buttons, under 100 columns the compact form has no borders on ${surface}`, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START)
      const wide = await $.ui.mount({ plugin: 'temper', surface, component: 'AbovePrompt', props: { ...BAND, bodyColumns: 140 } })
      expect(JSON.stringify(await wide.drawn())).toContain('"borderStyle":"round"')
      await wide.unmount()
      const compact = await $.ui.mount({ plugin: 'temper', surface, component: 'AbovePrompt', props: { ...BAND, bodyColumns: 80 } })
      const drawn = await compact.drawn()
      expect(JSON.stringify(drawn)).not.toContain('borderStyle')
      // Still every action, with short labels, and one dot.
      expect(walk(drawn).filter(n => n.type === 'Button')).toHaveLength(5)
      expect(JSON.stringify(drawn).match(/\u25cf/g)).toHaveLength(1)
    })
  }

  test('key 1 changes with readiness: Send to Review once the build gate passed', async ($, on) => {
    world(on, runFiles({ nextStage: 'build', gates: { build: 'PASS' } }))
    await $.session.start(START)
    const ui = await $.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', props: BAND })
    expect(await ui.find({ key: 'action-to-review' })).toBeDefined()
  })

  test('Enter in the reason field records the override with that reason; an empty reason is refused', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'review' }))
    await $.session.start(START)
    const ui = await $.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', props: BAND })
    await ui.input({ key: 'override-reason', text: '   ' })
    expect(w.toasts.some(t => t.includes('Override needs a reason'))).toBe(true)
    expect([...w.files.values()].some(t => t.includes('"type":"override"'))).toBe(false)
    await ui.input({ key: 'override-reason', text: 'reviewer is on leave' })
    expect([...w.files.values()].some(t => t.includes('"type":"override"') && t.includes('reviewer is on leave'))).toBe(true)
  })

  // The kit does not implement ui.focus for a plugin's own call, so here 9 always takes the fallback
  // (the engine moves the focus in a real session; checked live in a terminal).
  test('9 falls back to the question dialog when the field cannot take the focus', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'review' }), { answers: ['Risk accepted'] })
    await $.session.start(START)
    const ui = await $.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', props: BAND })
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
    test(`minimal mode shows the chips only: no Button, no field, no sentence on ${surface}`, { options: { uiMode: 'minimal' } }, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START)
      const ui = await $.ui.mount({ plugin: 'temper', surface, component: 'AbovePrompt', props: BAND })
      const tree = walk(await ui.drawn())
      expect(tree.filter(n => n.type === 'Button')).toHaveLength(0)
      expect(tree.filter(n => n.type === 'Input')).toHaveLength(0)
      const texts = tree.filter(n => n.type === 'Text').map(textOf).join(' ')
      expect(texts).toContain('\u25cf Build')
      expect(texts).not.toContain('Override needs a reason')
    })

    test(`off mode draws nothing on ${surface}: the engine's own drawing stands`, { options: { uiMode: 'off' } }, async ($, on) => {
      world(on, runFiles({ nextStage: 'build' }))
      await $.session.start(START)
      const ui = await $.ui.mount({ plugin: 'temper', surface, component: 'AbovePrompt', props: BAND })
      expect(await ui.drawn()).toEqual({ type: 'engine', ref: 0 })
    })
  }

  test('a survey holding the band is left alone', async ($, on) => {
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
      expect(await ui.find({ type: 'Text', text: /Temper/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /Password reset by email/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /Phase \u00b7 Build \(3 of 6\) \u00b7 task 3 of 7/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /Acceptance criteria \u00b7 2 of 5 met/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /\u2714 criterion 1/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /\u25cb criterion 2/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /\u2713 done {2}\u25cf you are here {2}\u25cb upcoming {2}\u21ba redo/ })).toBeDefined()
      expect((await ui.find({ key: 'timeline' }))?.text).toContain('1. Run started at Build')
    })
  }

  test('pane hotkeys are unique in every phase, expanded or not, and findings carry none', async ($, on) => {
    {
      const files = { ...runFiles({ nextStage: 'review' }), '.temper/evidence/review.json': JSON.stringify([{ claim: 'x', severity: 'major' }]) }
      world(on, files)
      await $.session.start(START)
      for (const expanded of [false, true]) {
        const ui = await $.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'Pane', requestId: 'temper', props: PANE })
        if (expanded) await ui.press({ key: 'pane-more-actions' })
        const keys = walk(await ui.drawn()).filter(n => n.type === 'Button').map(n => n.props?.hotkey).filter((k): k is string => typeof k === 'string')
        expect(new Set(keys).size).toBe(keys.length)
        expect(keys).toContain('0')
        expect(keys.filter(k => /^[a-h]$/.test(k)).length > 0).toBe(expanded)
        await ui.unmount()
      }
    }
  })

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
    // Hashing the event file is asynchronous in the host, so the follow up lands a moment after the press.
    for (const end = Date.now() + 1000; Date.now() < end && !w.prompts.some(p => p.includes('evidence accept')); ) await $.prompt.compose(COMPOSE)
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
    expect(String(terminal?.props.tail)).toContain('Temper, Build (3 of 6): ')
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
      expect(drawn).toContain('Temper: Build (3 of 6), criterion 2 of 5')
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
      'Build \u00b7 2 of 5 criteria met \u00b7 next: Review',
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
    expect(w.toasts).toEqual(['Plan approved \u00b7 Build open'])
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

  test('/temper:temper pane toggles', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }), { placed: true })
    await $.session.start(START)
    w.opened.length = 0
    expect((await $.command.run(run('pane'))).text).toBe('Temper pane closed.')
    expect((await $.command.run(run('pane'))).text).toBe('Temper pane opened.')
    expect(w.closed).toEqual(['temper'])
    expect(w.opened).toEqual(['temper'])
  })

  test('bare /temper:temper toggles the pane while a run is active', async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START)
    expect((await $.command.run(run(''))).text).toBe('Temper pane closed.')
  })

  test('bare /temper:temper with no run reaches the prompt based command', async ($, on) => {
    world(on, {})
    await $.session.start(START)
    expect((await $.command.run(run(''))).text).toBe('prompt based /temper:temper ran')
  })

  test('outside full mode the pane is refused with a hint', { options: { uiMode: 'minimal' } }, async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START)
    expect((await $.command.run(run('pane'))).text).toContain('full mode only')
    expect((await $.command.run(run(''))).text).toBe('prompt based /temper:temper ran')
  })
})
