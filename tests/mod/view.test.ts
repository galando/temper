// What the mod shows (ADR 0012): the view is built from the CLI's files and the person's decisions, and the bar and the
// pane only show it. The bar has one button, Go on (it takes the run up again with /temper:temper); it decides
// nothing. The pane has no button.
import { describe, expect, test } from 'claude-code/testing'

import type { Decision, Move } from '../../hooks/temper-mod/core/decisions'
import { buildView, whereText } from '../../hooks/temper-mod/core/view'
import type { ViewInput } from '../../hooks/temper-mod/core/view'
import { stateAt } from './helpers'
import { runFiles } from './run-files'
import { world } from './world'

const input = (over: Partial<ViewInput> = {}): ViewInput => ({
  run: stateAt('build'),
  title: 'Export report',
  gates: {},
  skips: {},
  loops: [],
  groups: null,
  findings: [],
  criteria: [],
  task: null,
  move: null,
  decisions: [],
  enforcement: 'on',
  ...over,
})
const stamp = { id: 'm1', run: 'r', step: 3, ts: 1, reason: '' }
const marks = (over: Partial<ViewInput>) => Object.fromEntries(buildView(input(over)).stages.map(s => [s.id, s.mark]))

describe('the view of the run', () => {
  test('the timeline: the stages behind are passed, failed or skipped, the current one is here, the rest to come', () => {
    expect(
      marks({
        run: stateAt('review'),
        gates: { intent: { verdict: 'PASS', requirements: [] }, plan: { verdict: 'PASS', requirements: [] }, build: { verdict: 'FAIL', requirements: [] } },
        skips: { build: { reason: 'spike', by: 'u' } },
      }),
    ).toEqual({ intent: 'passed', plan: 'passed', build: 'skipped', review: 'current', check: 'pending', commit: 'pending' })
  })
  test('Design is on the timeline only for a run that has it', () => {
    expect(buildView(input()).stages.map(s => s.id)).not.toContain('design')
    expect(buildView(input({ run: stateAt('build', { complexity: 'complex', designRequired: true }) })).stages.map(s => s.id)).toContain('design')
    expect(buildView(input({ run: stateAt('build', { complexity: 'complex' }) })).stages.map(s => s.id)).not.toContain('design')
  })
  test('where the run is, counted on its own stages', () => {
    expect(whereText(buildView(input()))).toBe('Step 3 of 6: Build')
    expect(whereText(buildView(input({ run: stateAt('build', { complexity: 'complex', designRequired: true }) })))).toBe('Step 4 of 7: Build')
    expect(whereText(buildView(input({ run: stateAt('commit') })))).toBe('Done')
  })

  test('what the run waits for', () => {
    const passed = { build: { verdict: 'PASS' as const, requirements: [] } }
    expect(buildView(input()).wait).toBe('work')
    expect(buildView(input({ gates: passed })).wait).toBe('gate')
    expect(buildView(input({ gates: passed, move: { ...stamp, stage: 'build', kind: 'advance' } as Move })).wait).toBe('chosen')
    expect(buildView(input({ move: { ...stamp, stage: 'build', kind: 'pause' } as Move })).wait).toBe('saved')
    expect(buildView(input({ run: stateAt('build', { runMode: 'autonomous', autonomyEnabled: true }) })).wait).toBe('armed')
    expect(buildView(input({ run: stateAt('commit') })).wait).toBe('done')
  })

  test('the status says what to do, in one sentence', () => {
    expect(buildView(input({ gates: { build: { verdict: 'FAIL', requirements: [] } } })).status).toBe('Build: the check failed. Waiting for you: answer the Temper gate question.')
    expect(buildView(input()).status).toBe('Build: Claude is working on it.')
  })

  test('the details: the groups of Build, the open findings of Review, the failed checks', () => {
    const groups = [{ id: 'G1', title: 'Export', state: 'running' as const, tasks: [{ n: 1, title: 'a', state: 'passed' as const, model: null, attempt: null }, { n: 2, title: 'b', state: 'running' as const, model: null, attempt: 1 }] }]
    expect(buildView(input({ groups })).detail).toEqual(['Tasks: 1 of 2 done', 'G1 Export  ✓1 ◐2'])
    const findings = [{ id: '1', severity: 'high', claim: 'x' }, { id: '2', severity: 'high', claim: 'y' }]
    expect(buildView(input({ run: stateAt('review'), findings })).detail).toEqual(['Open findings: 2 high'])
    const gates = { check: { verdict: 'FAIL' as const, requirements: [{ name: 'lint', pass: false, detail: '3 errors' }, { name: 'tests', pass: true, detail: '' }] } }
    const v = buildView(input({ run: stateAt('check'), gates }))
    expect(v.detail).toEqual(['Failed: lint'])
    expect(v.failedChecks).toEqual([{ name: 'lint', pass: false, detail: '3 errors' }])
  })

  test('the loops with their budget and the person\'s decisions as sentences', () => {
    const decisions: Decision[] = [{ ...stamp, stage: 'review', kind: 'back', to: 'build', reason: 'a real bug' } as Decision]
    const v = buildView(input({ loops: [{ from: 'review', to: 'build', iteration: 1, max: 2 }], decisions }))
    expect(v.loops).toEqual(['Review to Build: 1 of 2'])
    expect(v.decisions).toEqual(['went back from review to build (a real bug)'])
  })
})

const BAND = (isWorking: boolean, bodyColumns = 120) => ({ hasSurvey: false, isWorking, maxRows: 12, bodyColumns, scroll: { offset: 0, bodyRows: 12 }, view: {} }) as const
const PANE = { title: 'Temper', isFocused: false, bodyColumns: 100, placement: 'dock', scroll: { offset: 0, bodyRows: 30 }, view: {} } as const
const START = { cwd: '/repo', surface: 'terminal', isInteractive: true } as const
type Mounted = { findAll: (q: { type: string }) => Promise<Array<{ props: { key?: string; label?: string } }>>; press: (q: { key: string }) => Promise<void>; drawn: () => Promise<unknown>; unmount: () => Promise<void> }
type Ui = { ui: { mount: (a: unknown) => Promise<Mounted> } }
const mount = (api: unknown, component: 'AbovePrompt' | 'Pane', props: unknown, requestId?: string): Promise<Mounted> =>
  (api as Ui).ui.mount({ plugin: 'temper', surface: 'terminal', component, props, ...(requestId ? { requestId } : {}) })
const labels = async (m: Mounted): Promise<string[]> => (await m.findAll({ type: 'Button' })).map(b => String(b.props.label ?? ''))
// Words a button that decides would carry: the person decides in the question dialog only.
const DECIDES = /continue|approve|override|accept|loop back|skip|commit|keep|restart|start over|fix/i

describe('the bar above the prompt shows; it does not decide', () => {
  test('at a gate the bar has Go on, and pressing it takes the run up again with /temper:temper', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'plan', gates: { plan: 'PASS' } }))
    await $.session.start(START)
    const band = await mount($, 'AbovePrompt', BAND(false))
    expect(await labels(band)).toEqual(['Go on'])
    const text = JSON.stringify(await band.drawn())
    expect(text).toContain('Plan: the check passed. Waiting for you: answer the Temper gate question.')
    await band.press({ key: 'action-go-on' })
    expect(w.commandRuns.filter(c => c.command === 'temper:temper').map(c => c.args)).toEqual([''])
    expect(Object.keys(w.store).some(k => k.startsWith('dec:'))).toBe(false)
  })

  test('no stage, and no state of a run, draws a button that decides', async ($, on) => {
    const cases: Array<[string, Record<string, 'PASS' | 'FAIL'>]> = [
      ['intent', {}],
      ['plan', { plan: 'PASS' }],
      ['build', { build: 'FAIL' }],
      ['review', { review: 'FAIL' }],
      ['check', { check: 'FAIL' }],
      ['check', { check: 'PASS' }],
      ['done', {}],
    ]
    const w = world(on, {})
    await $.session.start(START)
    let n = 0
    for (const [next, gates] of cases) {
      for (const [k, v] of Object.entries(runFiles({ nextStage: next, gates }))) w.files.set(k, v)
      await $.command.run({ command: 'temper:temper', args: 'status', origin: { kind: 'composer' } } as never)
      for (const working of [false, true]) {
        const band = await mount($, 'AbovePrompt', BAND(working), `band-${n++}`)
        for (const label of await labels(band)) expect(label, `${next} ${JSON.stringify(gates)}`).not.toMatch(DECIDES)
        await band.unmount()
      }
      const pane = await mount($, 'Pane', PANE, 'temper')
      for (const label of await labels(pane)) expect(label, `${next} pane`).not.toMatch(DECIDES)
      await pane.unmount()
    }
  })

  test('while Claude works the bar has no Go on', async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    await $.session.start(START)
    expect(await labels(await mount($, 'AbovePrompt', BAND(true)))).not.toContain('Go on')
  })

  test('a narrow terminal draws the compact bar with the same content', async ($, on) => {
    world(on, runFiles({ nextStage: 'plan', gates: { plan: 'PASS' } }))
    await $.session.start(START)
    const band = await mount($, 'AbovePrompt', BAND(false, 60))
    expect(await labels(band)).toEqual(['Go on'])
    expect(JSON.stringify(await band.drawn())).toContain('Plan: the check passed.')
  })
})

describe('the pane shows the whole run, read only', () => {
  test('the intent, the stages, the status, the criteria and the decisions; no button while Claude does not work', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'review', gates: { intent: 'PASS', plan: 'PASS', build: 'PASS', review: 'FAIL' } }), { answers: ['Loop back to Build: a real bug'] })
    await $.session.start(START)
    await (($ as unknown) as { tool: { call: (a: unknown) => Promise<unknown> } }).tool.call({ tool: 'AskUserQuestion', questions: [{ question: 'What next?', header: 'Temper gate', multiSelect: false, options: [{ label: 'Continue', description: 'x' }] }] })
    expect(Object.keys(w.store).some(k => k.startsWith('dec:'))).toBe(true)
    const pane = await mount($, 'Pane', PANE, 'temper')
    const text = JSON.stringify(await pane.drawn())
    expect(text).toContain('Stages · Step 4 of 6: Review')
    expect(text).toContain('Review: your choice (went back from review to build (a real bug)). Claude carries it out.')
    expect(text).toContain('Your decisions')
    expect(text).toContain('Acceptance criteria')
    expect(await labels(pane)).toEqual([])
  })

  test('with no run the pane says how to start one', async ($, on) => {
    world(on, {})
    await $.session.start(START)
    expect(JSON.stringify(await (await mount($, 'Pane', PANE, 'temper')).drawn())).toContain('No Temper run is active.')
  })
})
