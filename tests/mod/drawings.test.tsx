// The drawings of ADR 0013, each a plain function of view.json: the band's time and loops on the timeline; the
// pane's plan files by group, Build grid (each task's state, model and retries), Review findings, Check markers with
// their failing lines and acceptance criteria with their evidence. No drawing decides, and neither the band nor the pane
// has a button. uiMode sets only how much is drawn. The views are the CLI's real output (scripts/selftest/view-fixtures.ts)
// with a run's own data put in.
import { describe, expect, test } from 'claude-code/testing'

import type { RenderElement } from 'claude-code'

import { parseRunView } from '../../hooks/temper-mod/core/runview'
import { buildView, questionHeader } from '../../hooks/temper-mod/core/view'
import type { View } from '../../hooks/temper-mod/core/view'
import type { Kit } from '../../hooks/temper-mod/ui/kit'
import { CARD_BG, contrast } from '../../hooks/temper-mod/ui/palette'
import { renderQuestion } from '../../hooks/temper-mod/ui/question'
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
    const all = ['waiting', 'running', 'red', 'green', 'covered', 'pass', 'fail', 'parked']
    const g0 = (v.build as { groups: Array<{ tasks: J[] }> }).groups[0] as { tasks: J[] }
    g0.tasks = all.map((state, i) => ({ ...(tasks[0] as J), n: i + 1, title: state, state, attempts: 1 }))
    runWith(on, v)
    await $.session.start(START)
    const text = JSON.stringify(await (await mount($, 'Pane', PANE(), 'temper')).drawn())
    for (const word of ['○ waiting', '◐ running', '● RED', '● GREEN', '◇ COVERED', '✓ PASS', '✗ FAIL', '⏸ parked']) expect(text, word).toContain(word)
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

// WP15: the card above the question dialog. renderQuestion draws the dim line it draws today, then the card's title,
// its sections' titles and their rows, then the engine's dialog, held once. The kit here makes plain data elements
// from string tags; the card goes in as the call's fourth argument and as the view's own field, so the test holds
// whichever of the two the drawing reads.
const KIT = { Box: 'Box', Text: 'Text', Markdown: 'Markdown' } as unknown as Kit
const ENGINE = { type: 'engine', ref: 0 } as unknown as RenderElement
const CARD = {
  kind: 'approval', run_id: 'run-pw', step: 3, title: 'APPROVE BEFORE ANY CODE IS WRITTEN', tag: 'pw · risk M',
  sections: [
    { id: 'criteria', title: 'WHAT WILL BE TRUE', note: '5 criteria; each gets a test written and locked first',
      rows: [{ text: 'AC-01 criterion 1', mark: null }, { text: 'AC-05 criterion 5', mark: 'proposed' }], total: 2,
      file: '.temper/specs/pw/intent.md' },
    { id: 'commands', title: 'THE CHECKS RUN', note: null, rows: [{ text: 'G1: npm test', mark: null }], total: 1,
      file: null },
  ],
  foot: ['You are asked again only if a check still fails after one repair, and at the commit.', 'Nothing is pushed.'],
}
type Drawn = { type?: string; props?: Record<string, unknown>; children?: unknown }
// The tree in drawing order: each Text as its text (with `dim:` before a dimmed one), the engine's dialog as ENGINE.
function drawnOrder(tree: unknown, out: string[] = []): string[] {
  if (Array.isArray(tree)) {
    for (const k of tree) drawnOrder(k, out)
    return out
  }
  if (typeof tree !== 'object' || tree === null) return out
  const n = tree as Drawn
  if (n.type === 'engine') out.push('ENGINE')
  else if (n.type === 'Text') {
    const kids = Array.isArray(n.children) ? n.children : [n.children]
    const text = kids.map(x => (typeof x === 'string' ? x : '')).join('')
    out.push(`${n.props?.dimColor === true ? 'dim:' : ''}${text}`)
  } else drawnOrder(n.children, out)
  return out
}
const planView = (card: unknown): View => {
  const rv = parseRunView(JSON.stringify(view('plan-pass')))
  if (rv === null) throw new Error('no view')
  return { ...buildView({ view: rv, decisions: [], answer: null, enforcement: 'on' }), card } as unknown as View
}
type Draw = (kit: Kit, v: View, engine: RenderElement, card?: unknown) => RenderElement | null
const draw = renderQuestion as unknown as Draw

describe('the question line: the card above the dialog', () => {
  test('with a card it draws the dim line, the title, each section title and each row above the engine\'s dialog',
    () => {
    const v = planView(CARD)
    const header = questionHeader(v)
    const order = drawnOrder(draw(KIT, v, ENGINE, CARD))
    expect(order[0]).toBe(`dim:${header}`)
    expect(order.filter(x => x === 'ENGINE')).toEqual(['ENGINE'])
    expect(order[order.length - 1]).toBe('ENGINE')
    const want = [CARD.title, ...CARD.sections.flatMap(s => [s.title, ...s.rows.map(r => r.text)])]
    let last = 0
    for (const w of want) {
      const at = order.findIndex((x, i) => i > last && x.includes(w))
      expect(at, `${w} is drawn after what comes before it, above the dialog (${order.join(' | ')})`)
        .toBeGreaterThan(last)
      last = at
    }
  })

  test('with no card it draws the one dim line it draws today, above the engine\'s dialog', () => {
    const v = planView(null)
    expect(drawnOrder(draw(KIT, v, ENGINE))).toEqual([`dim:${questionHeader(v)}`, 'ENGINE'])
    expect(drawnOrder(draw(KIT, v, ENGINE, null))).toEqual([`dim:${questionHeader(v)}`, 'ENGINE'])
  })
})

// WP19: a measurement that was not taken is a third state, drawn with a mark of its own (the CLI prints `[?]`); never
// as a pass and never as a failure. The planted bug score is a Check marker of its own, information only.
describe('the pane: a check that was not measured, and the planted bugs as information', () => {
  test('a checks entry with state not measured is carried by the view and drawn with its own mark', async ($, on) => {
    const v = richView()
    v.check_markers = (v.check_markers as J[]).map(m => ({ ...m, state: 'none', detail: '', lines: [] }))
    v.checks = [
      { name: 'tests pass', pass: true, detail: '1 green test run(s) recorded' },
      { name: 'coverage', pass: null, state: 'not measured', detail: 'not measured: no coverage tool for this stack' },
    ]
    const parsed = parseRunView(JSON.stringify(v))
    const row = (parsed?.checks ?? []).find(c => c.name === 'coverage') as Record<string, unknown> | undefined
    expect(row?.state, 'the view carries the state beside pass').toBe('not measured')
    expect(row?.pass, 'a row not measured is never read as passed').not.toBe(true)
    runWith(on, v)
    await $.session.start(START)
    const text = JSON.stringify(await (await mount($, 'Pane', PANE(), 'temper')).drawn())
    expect(text).toContain('? coverage')
    expect(text).not.toContain('✓ coverage')
    expect(text).not.toContain('✗ coverage')
  })

  test('a check_markers entry mutation with state info is drawn as information, never as a failure', async ($, on) => {
    const v = richView()
    v.check_markers = [...(v.check_markers as J[]),
      { name: 'mutation', state: 'info', detail: '7 of 9 planted bugs caught', value: null, lines: [] }]
    runWith(on, v)
    await $.session.start(START)
    const text = JSON.stringify(await (await mount($, 'Pane', PANE(), 'temper')).drawn())
    expect(text).toContain('• mutation: 7 of 9 planted bugs caught')
    expect(text).not.toContain('✗ mutation')
    expect(text).not.toContain('✓ mutation')
  })
})
