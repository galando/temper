// The drawings of ADR 0013, each a plain function of view.json: the band's time and loops on the timeline; the
// pane's plan files by group, Build grid (each task's state, model and retries), Review findings, Check markers with
// their failing lines and acceptance criteria with their evidence. No drawing decides, and neither the band nor the pane
// has a button. uiMode sets only how much is drawn. The views are the CLI's real output (scripts/selftest/view-fixtures.ts)
// with a run's own data put in.
import { describe, expect, test } from 'claude-code/testing'

import { CARD_BG, contrast } from '../../hooks/temper-mod/ui/palette'
import { view } from './run-files'
import { world } from './world'

const START = { cwd: '/repo', surface: 'terminal', isInteractive: true } as const
const BAND = (bodyColumns = 120) => ({ hasSurvey: false, isWorking: false, maxRows: 12, bodyColumns, scroll: { offset: 0, bodyRows: 12 }, view: {} }) as const
const PANE = (placement = 'dock') => ({ title: 'Temper', isFocused: false, bodyColumns: 100, placement, scroll: { offset: 0, bodyRows: 40 }, view: {} }) as const
type Mounted = { findAll: (q: { type: string }) => Promise<Array<{ props: { label?: string } }>>; drawn: () => Promise<unknown> }
type Ui = { ui: { mount: (a: unknown) => Promise<Mounted> } }
const mount = (api: unknown, component: 'AbovePrompt' | 'Pane', props: unknown, requestId?: string): Promise<Mounted> =>
  (api as Ui).ui.mount({ plugin: 'temper', surface: 'terminal', component, props, ...(requestId ? { requestId } : {}) })
const labels = async (m: Mounted): Promise<string[]> => (await m.findAll({ type: 'Button' })).map(b => String(b.props.label ?? ''))

type J = Record<string, unknown>

// A run at Check after a loop back from Review: every drawing has something to show.
function richView(): J {
  const v = view('check-fail')
  const tasks = (v.build as { groups: Array<{ tasks: J[] }> }).groups.flatMap(g => g.tasks)
  const states: Array<[string, string | null, number]> = [['pass', 'claude-haiku-4-5', 1], ['red', 'claude-haiku-4-5', 3], ['green', 'claude-sonnet-4-6', 2]]
  tasks.forEach((t, i) => Object.assign(t, { state: states[i]?.[0], model: states[i]?.[1], attempts: states[i]?.[2] }))
  v.loops = [{ from: 'review', to: 'build', reason: 'a real bug', iteration: 1, max: 2, at: 't' }]
  // A token count left by a 9.7.3 run is not drawn: since 9.7.4 Temper records the time only.
  v.usage = { tokens: 1234567, ms: 1, by_stage: {}, by_model: {} }
  v.time = { started: '2026-01-01T10:00:00Z', updated: '2026-01-01T10:42:00Z' }
  v.findings = [
    { id: 1, severity: 'critical', confidence: 0.9, claim: 'src/app.ts:12 the token never expires', file: 'src/app.ts', line: 12, state: 'resolved', label: 'PROVEN' },
    { id: 2, severity: 'low', confidence: null, claim: 'the subject is not localized', file: null, line: null, state: 'accepted', label: 'HEURISTIC' },
  ]
  v.check_markers = [
    { name: 'compile', state: 'pass', detail: 'tsc', value: null, lines: [] },
    { name: 'tests', state: 'fail', detail: 'npm test', value: null, lines: ['unit/app.test.ts: expected 410, got 200'] },
    { name: 'coverage', state: 'info', detail: 'coverage 81%', value: 81, lines: [] },
    { name: 'lint', state: 'pass', detail: 'eslint', value: null, lines: [] },
    { name: 'security', state: 'none', detail: '', value: null, lines: [] },
  ]
  const criteria = v.criteria as J[]
  Object.assign(criteria[0] as J, { status: 'passed', evidence: ['build#3 unit tests pass'] })
  return v
}

const runWith = (on: Parameters<typeof world>[0], v: J) => world(on, { '.temper/view.json': JSON.stringify(v) })

describe('the band: time and the loops on the timeline', () => {
  test('full mode draws the clock and each loop with its reason, and no button', async ($, on) => {
    runWith(on, richView())
    await $.session.start(START)
    const band = await mount($, 'AbovePrompt', BAND())
    const text = JSON.stringify(await band.drawn())
    expect(text).toContain('42 min')
    expect(text).not.toContain('1.2M')
    expect(text).toContain('↺ Review to Build (1 of 2): a real bug')
    expect(await labels(band)).toEqual([])
  })

  test('minimal mode draws the stages only; off draws nothing of Temper', { options: { uiMode: 'minimal' } }, async ($, on) => {
    runWith(on, richView())
    await $.session.start(START)
    const text = JSON.stringify(await (await mount($, 'AbovePrompt', BAND())).drawn())
    expect(text).toContain('TEMPER')
    expect(text).not.toContain('a real bug')
    expect(text).not.toContain('tokens')
  })

  test('off mode draws nothing of Temper', { options: { uiMode: 'off' } }, async ($, on) => {
    runWith(on, richView())
    await $.session.start(START)
    expect(JSON.stringify(await (await mount($, 'AbovePrompt', BAND())).drawn())).not.toContain('TEMPER')
  })
})

describe('the pane: the whole run, read only', () => {
  test('plan files by group, the Build grid, the findings, the Check markers and the criteria with evidence', async ($, on) => {
    runWith(on, richView())
    await $.session.start(START)
    const pane = await mount($, 'Pane', PANE(), 'temper')
    const text = JSON.stringify(await pane.drawn())
    // The plan's files, by group, as approved.
    expect(text).toContain('Plan files · as you approved them')
    expect(text).toContain('G1 Tokens')
    expect(text).toContain('├ src/app.ts')
    expect(text).toContain('└ unit/app.test.ts')
    // The Build grid: state, model, retries.
    expect(text).toContain('✓ PASS    Task 1: Issue a token · haiku-4-5')
    expect(text).toContain('● RED     Task 2: Expire a token · haiku-4-5 · 2 retries')
    expect(text).toContain('● GREEN   Task 3: Send the mail · sonnet-4-6 · 1 retry')
    // The findings: severity, confidence, file:line, state.
    expect(text).toContain('Review findings · 0 open')
    expect(text).toContain('#1 critical 0.90 src/app.ts:12 the token never expires · resolved')
    expect(text).toContain('#2 low the subject is not localized · accepted')
    // The Check markers with the failing lines.
    expect(text).toContain('✗ tests: npm test')
    expect(text).toContain('unit/app.test.ts: expected 410, got 200')
    expect(text).toContain('✓ compile: tsc')
    expect(text).toContain('○ security')
    // The criteria with their evidence, the loop and the clock.
    expect(text).toContain('Acceptance criteria · 1 of 5 met')
    expect(text).toContain('build#3 unit tests pass')
    expect(text).toContain('↺ Review to Build (1 of 2): a real bug')
    expect(text).toContain('42 min')
    expect(text).not.toContain('1.2M')
    expect(await labels(pane)).toEqual([])
  })

  test('each task state of the grid has its own mark', async ($, on) => {
    const v = richView()
    const tasks = (v.build as { groups: Array<{ tasks: J[] }> }).groups.flatMap(g => g.tasks)
    const all = ['waiting', 'running', 'red', 'green', 'pass', 'fail', 'parked']
    const g0 = (v.build as { groups: Array<{ tasks: J[] }> }).groups[0] as { tasks: J[] }
    g0.tasks = all.map((state, i) => ({ ...(tasks[0] as J), n: i + 1, title: state, state, attempts: 1 }))
    runWith(on, v)
    await $.session.start(START)
    const text = JSON.stringify(await (await mount($, 'Pane', PANE(), 'temper')).drawn())
    for (const word of ['○ waiting', '◐ running', '● RED', '● GREEN', '✓ PASS', '✗ FAIL', '⏸ parked']) expect(text, word).toContain(word)
  })

  test('an inline pane keeps each section short', async ($, on) => {
    const v = richView()
    v.findings = Array.from({ length: 8 }, (_, i) => ({ id: i + 1, severity: 'high', confidence: 0.8, claim: `finding ${i + 1}`, file: null, line: null, state: 'open', label: null }))
    runWith(on, v)
    await $.session.start(START)
    const text = JSON.stringify(await (await mount($, 'Pane', PANE('inline'), 'temper')).drawn())
    expect(text).toContain('#5 high 0.80 finding 5 · open')
    expect(text).not.toContain('finding 6 ')
    expect(text).toContain('and 3 more')
  })

  test('every text of the full pane sets a colour that reads on the card, on every theme', async ($, on) => {
    runWith(on, richView())
    await $.session.start(START)
    const tree = await (await mount($, 'Pane', PANE(), 'temper')).drawn()
    const texts: Array<{ color: unknown; dim: unknown }> = []
    const walk = (n: unknown): void => {
      if (Array.isArray(n)) return n.forEach(walk)
      if (typeof n !== 'object' || n === null) return
      const node = n as { type?: string; props?: Record<string, unknown>; children?: unknown }
      if (node.type === 'Text') texts.push({ color: node.props?.color, dim: node.props?.dimColor })
      walk(node.children)
    }
    walk(tree)
    expect(texts.length).toBeGreaterThan(30)
    for (const t of texts) {
      expect(typeof t.color).toBe('string')
      expect(contrast(t.color as string, CARD_BG)).toBeGreaterThanOrEqual(4.5)
      expect(t.dim).toBeFalsy()
    }
  })
})
