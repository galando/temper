// 9.7.6 in the mod: the fresh review of the plan in the run view and the pane, and reviewerModel for the fresh plan reviewer.
// The views are the CLI's real output (scripts/selftest/view-fixtures*.ts).
import { describe, expect, test } from 'claude-code/testing'

import { buildView } from '../../hooks/temper-mod/core/view'
import { parseRunView } from '../../hooks/temper-mod/core/runview'
import { VIEWS } from '../../scripts/selftest/view-fixtures'
import { EXTRA_VIEWS } from '../../scripts/selftest/view-fixtures-2'
import { world } from './world'

type J = Record<string, unknown>
const clone = (v: unknown): J => JSON.parse(JSON.stringify(v)) as J
const START = { cwd: '/repo', surface: 'terminal', isInteractive: true } as const
const PANE = { title: 'Temper', isFocused: false, bodyColumns: 120, placement: 'dock', scroll: { offset: 0, bodyRows: 60 }, view: {} } as const
type Mounted = { findAll: (q: { type: string }) => Promise<unknown[]>; drawn: () => Promise<unknown> }
const mountPane = (api: unknown): Promise<Mounted> =>
  (api as { ui: { mount: (a: unknown) => Promise<Mounted> } }).ui.mount({ plugin: 'temper', surface: 'terminal', component: 'Pane', props: PANE, requestId: 'temper' })
const viewOf = (v: J) => buildView({ view: parseRunView(JSON.stringify(v))!, enforcement: 'on', decisions: [], answer: null })

describe('9.7.6: the fresh review in the run view', () => {
  test('the CLI view of a medium plan with a blocker and a contest parses into findings with their state and citation', () => {
    const rv = parseRunView(JSON.stringify(EXTRA_VIEWS['plan-fresh-blocker']))!
    expect(rv.fresh).not.toBeNull()
    expect(rv.fresh!.paraphrase).toBe('a reset link by email, valid for one hour | the app has users and a mail helper')
    expect(rv.fresh!.missing).toEqual([])
    expect(rv.fresh!.findings.map(f => `${f.id}|${f.lens}|${f.state}|${f.cite}`)).toEqual(['5|readiness|open|null', '6|zoom-out|contested|src/mail.ts:sendMail'])
  })

  test('a simple plan has no fresh review: the field is null and the view has none', () => {
    const rv = parseRunView(JSON.stringify(VIEWS['plan-pass']))!
    expect(rv.fresh).toBeNull()
    expect(viewOf(VIEWS['plan-pass'] as J).fresh).toBeNull()
  })

  test('a malformed field reads as no fresh review, and an unknown state as open', () => {
    const v = clone(EXTRA_VIEWS['plan-fresh-blocker'])
    v.fresh = 'x'
    expect(parseRunView(JSON.stringify(v))!.fresh).toBeNull()
    const w = clone(EXTRA_VIEWS['plan-fresh-blocker'])
    ;((w.fresh as J).findings as J[])[0]!.state = 'gone'
    expect(parseRunView(JSON.stringify(w))!.fresh!.findings[0]!.state).toBe('open')
  })

  test('the view drops the lens tag from the claim and keeps the lens apart', () => {
    const fv = viewOf(EXTRA_VIEWS['plan-fresh-blocker'] as J).fresh!
    expect(fv.summary).toBe('a reset link by email, valid for one hour | the app has users and a mail helper')
    expect(fv.rows[0]).toEqual({ id: 5, severity: 'high', lens: 'readiness', claim: "Task 1: the Case 'expired link' names no status", state: 'open', cite: null })
  })
})

describe('9.7.6: the pane shows the fresh review at Plan, with no button', () => {
  test('the summary, the open blockers (a contest is still open for the person) and the citation', async ($, on) => {
    world(on, { '.temper/view.json': JSON.stringify(EXTRA_VIEWS['plan-fresh-blocker']) })
    await $.session.start(START)
    const pane = await mountPane($)
    const text = JSON.stringify(await pane.drawn())
    expect(text).toContain('Fresh review of the plan · 2 open blockers')
    expect(text).toContain('A reader with no context: a reset link by email, valid for one hour')
    expect(text).toContain("#5 high [readiness] Task 1: the Case 'expired link' names no status · open")
    expect(text).toContain('#6 high [zoom-out] Task 2: a new mail sender where one exists · contested (src/mail.ts:sendMail)')
    expect(await pane.findAll({ type: 'Button' })).toEqual([])
  })

  test('a lens that did not run is named', async ($, on) => {
    const v = clone(EXTRA_VIEWS['plan-fresh-blocker'])
    ;(v.fresh as J).missing = ['comprehension A']
    world(on, { '.temper/view.json': JSON.stringify(v) })
    await $.session.start(START)
    expect(JSON.stringify(await (await mountPane($)).drawn())).toContain('Not run: comprehension A')
  })

  test('a stale review says it runs again, and does not list the lenses as not run', async ($, on) => {
    const v = clone(EXTRA_VIEWS['plan-fresh-blocker'])
    Object.assign(v.fresh as J, { stale: true, missing: ['readiness A', 'zoom-out A', 'comprehension A'] })
    world(on, { '.temper/view.json': JSON.stringify(v) })
    await $.session.start(START)
    const text = JSON.stringify(await (await mountPane($)).drawn())
    expect(text).toContain('tasks.md changed after the review; it runs again')
    expect(text).not.toContain('Not run:')
  })

  test('an accepted finding is not counted as open', async ($, on) => {
    const v = clone(EXTRA_VIEWS['plan-fresh-blocker'])
    ;((v.fresh as J).findings as J[])[1]!.state = 'accepted'
    world(on, { '.temper/view.json': JSON.stringify(v) })
    await $.session.start(START)
    expect(JSON.stringify(await (await mountPane($)).drawn())).toContain('Fresh review of the plan · 1 open blocker"')
  })

  test('from Build on the section is gone', async ($, on) => {
    const v = clone(EXTRA_VIEWS['plan-fresh-blocker'])
    ;(v.run as J).stage = 'build'
    world(on, { '.temper/view.json': JSON.stringify(v) })
    await $.session.start(START)
    expect(JSON.stringify(await (await mountPane($)).drawn())).not.toContain('Fresh review of the plan')
  })
})
