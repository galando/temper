// What the mod shows (ADR 0013): the view is built from view.json (the CLI's real output, scripts/selftest/view-fixtures.ts)
// and the person's decisions, and the bar and the pane only show it. The bar has one button, Go on (it takes the run up
// again with /temper:temper); it decides nothing. The pane has no button.
import { describe, expect, test } from 'claude-code/testing'

import type { Decision } from '../../hooks/temper-mod/core/decisions'
import { parseRunView } from '../../hooks/temper-mod/core/runview'
import { buildView, whereText } from '../../hooks/temper-mod/core/view'
import type { ViewInput } from '../../hooks/temper-mod/core/view'
import { deriveView, questionOf, runFiles, view } from './run-files'
import { viewText, world } from './world'

const rv = (doc: unknown) => {
  const v = parseRunView(typeof doc === 'string' ? doc : JSON.stringify(doc))
  if (v === null) throw new Error('no view')
  return v
}
const input = (name: string, over: Partial<ViewInput> = {}, patch: Record<string, unknown> = {}): ViewInput => ({
  view: rv({ ...view(name), ...patch }),
  decisions: [],
  answer: null,
  enforcement: 'on',
  ...over,
})
const answer = (label: string, move: string, reason = ''): Extract<Decision, { kind: 'gate' }> => ({ kind: 'gate', id: 'm1', run: 'run-pw', step: 3, stage: 'build', ts: 1, label, move, calls: [], steps: [], reason })

describe('the view of the run', () => {
  test('the timeline: the stages behind are passed, failed or skipped, the current one is here, the rest to come', () => {
    const files: Record<string, string> = {
      ...runFiles({ nextStage: 'review', gates: { intent: 'PASS', plan: 'PASS', build: 'FAIL' } }),
      '.temper/overrides.json': JSON.stringify([{ stage: 'build', reason: 'spike', by: 'u' }]),
    }
    const v = buildView({ view: rv(deriveView(p => files[p]) ?? ''), decisions: [], answer: null, enforcement: 'on' })
    expect(Object.fromEntries(v.stages.map(st => [st.id, st.mark]))).toEqual({ intent: 'passed', plan: 'passed', build: 'skipped', review: 'current', check: 'pending', commit: 'pending' })
    expect(v.stages.find(st => st.id === 'build')?.skip).toBe('spike')
  })
  test('Design is on the timeline only for a run that has it', () => {
    expect(buildView(input('build-work')).stages.map(st => st.id)).not.toContain('design')
    expect(buildView(input('design-work')).stages.map(st => st.id)).toContain('design')
  })
  test('where the run is, counted on its own stages', () => {
    expect(whereText(buildView(input('build-work')))).toBe('Step 3 of 6: Build')
    expect(whereText(buildView(input('design-work')))).toBe('Step 3 of 7: Design')
    expect(whereText(buildView(input('commit-pass')))).toBe('Done')
  })

  test('what the run waits for', () => {
    expect(buildView(input('build-work')).wait).toBe('work')
    expect(buildView(input('build-pass')).wait).toBe('gate')
    expect(buildView(input('build-pass', { answer: answer('Continue to Review (Recommended)', 'advance') })).wait).toBe('chosen')
    expect(buildView(input('build-pass', { answer: answer('Save for later', 'pause') })).wait).toBe('saved')
    expect(buildView(input('armed-build-pass')).wait).toBe('armed')
    expect(buildView(input('commit-pass')).wait).toBe('done')
  })

  test('the status is the CLI\'s sentence, or the person\'s choice', () => {
    expect(buildView(input('build-fail')).status).toBe('Build: waiting for your answer to the Temper gate question.')
    expect(buildView(input('build-pass', { answer: answer('Continue to Review (Recommended)', 'advance') })).status).toBe('Build: your choice (Continue to Review (Recommended)). Claude carries it out.')
    expect(buildView(input('build-pass', { answer: answer('Save for later', 'pause') })).status).toBe('Build is saved for later. Go on when you are ready.')
  })

  test('the details: the groups of Build, the open findings of Review, the failed checks', () => {
    const groups = view('build-work').build as { groups: Array<{ tasks: Array<{ state: string }> }> }
    const g0 = groups.groups[0]
    if (g0 === undefined || g0.tasks[0] === undefined || g0.tasks[1] === undefined) throw new Error('no group')
    g0.tasks[0].state = 'pass'
    g0.tasks[1].state = 'red'
    const b = buildView(input('build-work', {}, { build: groups }))
    expect(b.detail).toEqual(['Tasks: 1 of 3 done', 'G1 Tokens  ✓1 ◐2', 'G2 Mail  ○3'])
    expect(buildView(input('review-fail')).detail).toEqual(['Open findings: 1 critical, 1 low', 'Failed: critical findings'])
    const v = buildView(input('check-fail'))
    expect(v.detail).toEqual(['Failed: tests pass'])
    expect(v.failedChecks).toEqual([{ name: 'tests pass', detail: 'exit 1: 2 failed' }])
  })

  test('the loops with their budget and reason, and the person\'s decisions as sentences', () => {
    const decisions: Decision[] = [{ ...answer('Loop back to Build (Recommended)', 'back', 'a real bug'), stage: 'review' }]
    const v = buildView(input('build-work', { decisions }, { loops: [{ from: 'review', to: 'build', reason: 'a real bug', iteration: 1, max: 2, at: 't' }] }))
    expect(v.loops).toEqual(['Review to Build: 1 of 2 (a real bug)'])
    expect(v.decisions).toEqual(['review: Loop back to Build (Recommended) (a real bug)'])
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
    expect(text).toContain('Plan: waiting for your answer to the Temper gate question.')
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
    expect(JSON.stringify(await band.drawn())).toContain('Plan: waiting for your answer')
  })
})

describe('the pane shows the whole run, read only', () => {
  test('the intent, the stages, the status, the criteria and the decisions; no button while Claude does not work', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'review', gates: { intent: 'PASS', plan: 'PASS', build: 'PASS', review: 'FAIL' } }), { answers: [{ label: 'Loop back to Build (Recommended)', note: 'a real bug' }] })
    await $.session.start(START)
    await (($ as unknown) as { tool: { call: (a: unknown) => Promise<unknown> } }).tool.call({ tool: 'AskUserQuestion', questions: [{ ...questionOf(viewText(w) ?? ''), multiSelect: false }] })
    expect(Object.keys(w.store).some(k => k.startsWith('dec:'))).toBe(true)
    const pane = await mount($, 'Pane', PANE, 'temper')
    const text = JSON.stringify(await pane.drawn())
    expect(text).toContain('Stages · Step 4 of 6: Review')
    expect(text).toContain('Review: your choice (Loop back to Build (Recommended)). Claude carries it out.')
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
