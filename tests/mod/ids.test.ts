// Ids in the protocol (WP04): every question and option of the view has a stable id, a question and some options a kind,
// and an option says when it is recommended. A question that goes to the dialog as given (a reason, name or Blocking
// question) holds no id: its ids sit beside it. The mod reads them, still takes a view of the base (10e965a) that has none,
// and selects More options, Accept, Cancel and Carry forward by kind. An id is a lookup: an answer still counts only on
// the exact header, question and label for the run and step (core/answers.ts; ADR 0016 decision 1).
import { describe, expect, test } from 'claude-code/testing'

import { answersIn } from '../../hooks/temper-mod/core/answers'
import { drive } from '../../hooks/temper-mod/core/driver'
import type { AgentEnd, GoAsk, GoOut, GoQuestion, Port } from '../../hooks/temper-mod/core/driver'
import { parseRunView } from '../../hooks/temper-mod/core/runview'
import { view } from './run-files'

const CLI = '/p/scripts/temper'
type J = Record<string, unknown>

// A view of the base: the same view with no id, kind or recommended on a question or an option (the head has `id` on
// groups, tasks and findings already, so only the questions and their options lose them).
function base(v: J): J {
  const strip = (o: unknown): void => {
    if (typeof o !== 'object' || o === null) return
    const x = o as J
    delete x.id
    delete x.kind
    delete x.recommended
    delete x.reason_ids
    delete x.answer_ids
    for (const k of ['more', 'accept', 'reason_question', 'answer_question', 'question']) strip(x[k])
    for (const opt of Array.isArray(x.options) ? x.options : []) strip(opt)
  }
  strip(v.ask)
  strip(v.restart)
  strip(v.context_check)
  return v
}

function port(goes: GoOut[], answers: Array<string | null>) {
  const log = { ran: [] as string[], asked: [] as GoQuestion[] }
  const left = [...answers]
  const p: Port = {
    run: async call => {
      log.ran.push(call)
      if (call === `${CLI} go`) return { code: 0, out: JSON.stringify(goes.shift() ?? { action: 'none', say: 'end' }) }
      return { code: 0, out: '' }
    },
    spawn: async () => 'ag1',
    wait: async ids => Object.fromEntries(ids.map(id => [id, { text: '', ms: 1 } as AgentEnd])),
    ask: async q => {
      log.asked.push(q)
      return left.length > 0 ? (left.shift() as string | null) : null
    },
    record: async () => {},
    show: async () => {},
    stopped: () => false,
  }
  return { p, log }
}

// The view's ask, with one option's label changed in the question and in its options alike.
function relabel(a: J, from: string, to: string): GoAsk {
  const q = a.question as { options: Array<{ label: string }> }
  for (const o of [...q.options, ...(a.options as Array<{ label: string }>)]) if (o.label === from) o.label = to
  return a as unknown as GoAsk
}

describe('the view carries ids, and the mod reads them', () => {
  test('parseRunView gives each option of plan-pass its id, kind and recommended', () => {
    const rv = parseRunView(JSON.stringify(view('plan-pass')))
    expect(rv?.ask?.id).toBe('plan.approve')
    expect(rv?.ask?.kind).toBe('gate')
    expect(rv?.ask?.options.map(o => o.id)).toEqual(['ask-every-stage', 'approve-run', 'fresh-review', 'more'])
    expect(rv?.ask?.options.map(o => o.recommended)).toEqual([true, false, false, false])
    expect(rv?.ask?.options.map(o => o.kind)).toEqual([null, null, null, 'more'])
    expect(rv?.ask?.more?.id).toBe('plan.approve.more')
    expect(rv?.restart?.options.map(o => [o.id, o.kind])).toEqual([['start-over', null], ['cancel', 'cancel']])
  })

  test('a view of the base, with none of the keys, still parses: id null, kind null, recommended false', () => {
    const rv = parseRunView(JSON.stringify(base(view('plan-pass'))))
    expect(rv).not.toBeNull()
    expect(rv?.ask?.id).toBeNull()
    expect(rv?.ask?.kind).toBeNull()
    expect(rv?.ask?.options.map(o => o.label)).toEqual(['Stage by stage (Recommended)', 'Autonomous Build: run Build unattended', 'Fresh review first', 'More options'])
    expect(rv?.ask?.options.every(o => o.id === null && o.kind === null && o.recommended === false)).toBe(true)
    expect(rv?.restart?.options.every(o => o.id === null)).toBe(true)
  })
})

describe('the driver selects by kind, never by label', () => {
  test('it opens the More question by kind more, when the option says something else', async () => {
    const v = view('plan-pass')
    const ask = relabel(v.ask as J, 'More options', 'Show the rest')
    const { p, log } = port([{ action: 'ask', stage: 'plan', ask }], ['Show the rest', 'Save for later'])
    const end = await drive(p, CLI, null)
    expect(log.asked.map(q => q.question)).toEqual([ask.question.question, ask.more!.question.question])
    expect(end.kind).toBe('done')
  })

  test('it goes back on kind cancel at a reason question, whatever the label of that option', async () => {
    const v = view('intent-fail')
    const ask = v.ask as J
    const over = (ask.options as J[]).find(o => o.id === 'override') as J
    const rq = over.reason_question as { question: string; options: Array<{ label: string }> }
    // the ids sit beside the dialog question, in the order of its options
    const at = (over.reason_ids as { options: Array<{ kind?: string }> }).options.findIndex(o => o.kind === 'cancel')
    rq.options[at]!.label = 'Not now'
    const { p, log } = port([{ action: 'ask', stage: 'intent', ask: ask as unknown as GoAsk }], ['Override and continue', 'Not now', 'Save for later'])
    await drive(p, CLI, null)
    expect(log.asked.map(q => q.question)).toEqual([(ask.question as J).question, rq.question, (ask.question as J).question])
    expect(log.ran.some(c => c.includes(' override '))).toBe(false)
  })

  test('it runs the carry call on kind carry', async () => {
    const question: GoQuestion = { header: 'Question 1', question: 'Who may refund?', options: [
      { label: 'Admins only', description: 'Recommended' }, { label: 'Keep it for later', description: '' }] }
    const question_ids = { id: 'intent.blocking', kind: 'blocking', options: [{ id: 'choice-1' }, { id: 'carry', kind: 'carry' }] }
    const blocking = [{ question, question_ids, answer: `${CLI} intent answer 'Who may refund?' '{answer}'`, carry: `${CLI} intent carry 'Who may refund?'` }]
    const { p, log } = port([{ action: 'ask', stage: 'intent', gate: `${CLI} gate intent`, blocking }], ['Keep it for later'])
    await drive(p, CLI, null)
    expect(log.ran).toContain(`${CLI} intent carry 'Who may refund?'`)
    expect(log.ran.some(c => c.includes('intent answer'))).toBe(false)
  })
})

describe('an id is a lookup, never what makes an answer count', () => {
  const result = (q: { header: string; question: string }, answer: string) => ({ result: { questions: [{ ...q, multiSelect: false }], answers: { [q.question]: answer } } })

  test('a reworded question whose ids are right counts nothing', () => {
    const v = view('plan-pass')
    const rv = parseRunView(JSON.stringify(v))!
    const q = rv.ask!.question
    expect(answersIn(result({ header: q.header, question: `${q.question} Really?` }, 'Stage by stage (Recommended)'), rv)).toEqual([])
    const exact = answersIn(result(q, 'Stage by stage (Recommended)'), rv)
    expect(exact.map(a => (a.kind === 'gate' ? [a.questionId, a.option.id] : []))).toEqual([['plan.approve', 'ask-every-stage']])
  })
})
