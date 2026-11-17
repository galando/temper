// The mod answer audit (ADR 0016): every question of every fixture view is answered, option by option, through the mod's own answer
// code, and each call of the option is judged by the mod's rule. A call only the person may cause passes as the call an answer maps to
// and is refused with no answer; and each kind of person only call is reachable from at least one question the CLI writes.
import { describe, expect, test } from 'claude-code/testing'

import { answersIn } from '../../hooks/temper-mod/core/answers'
import { evaluate } from '../../hooks/temper-mod/core/rules'
import type { RuleContext, RunFacts } from '../../hooks/temper-mod/core/rules'
import { parseRunView } from '../../hooks/temper-mod/core/runview'
import type { Ask, Option, RunView } from '../../hooks/temper-mod/core/runview'
import { cliStage } from '../../hooks/temper-mod/core/stages'
import { VIEWS } from '../../scripts/selftest/view-fixtures'
import { EXTRA_VIEWS } from '../../scripts/selftest/view-fixtures-2'

const ALL: Record<string, unknown> = { ...VIEWS, ...EXTRA_VIEWS }

const factsOf = (rv: RunView): RunFacts | null => {
  const g = rv.guard
  const stage = cliStage(rv.run?.stage ?? null)
  return stage === null || g === null ? null : { stage, step: g.step, specDir: g.spec, planFiles: g.planFiles, groupedActive: g.grouped, trivialExit: g.trivialExit, prefix: g.prefix, adhocStage: g.adhocStage }
}
const ctx = (rv: RunView, allowed: string[]): RuleContext =>
  ({ run: factsOf(rv), allowed, root: '/project', drift: { added: [], allowOnce: [] }, restart: false, cli: '/plugin/scripts/temper', fixRun: false }) as unknown as RuleContext

const asks = (rv: RunView): Ask[] => {
  const out: Ask[] = []
  const walk = (a: Ask | null): void => {
    if (a === null) return
    out.push(a)
    walk(a.more)
    walk(a.accept)
  }
  walk(rv.ask)
  if (rv.contextCheck !== null) out.push(rv.contextCheck.ask)
  return out
}
const fill = (call: string): string => call.replace(/\{[A-Za-z]+\}/g, 'x')
const kindOf = (call: string): string | null => {
  const w = call.replace(/^\S*\/scripts\/temper\s+/, '').split(/\s+/)
  if (w[0] === 'override') return 'override'
  if (w[0] === 'plan' && w[1] === 'review') return 'plan review'
  if (w[0] === 'task' && (w[1] === 'confirm' || w[1] === 'accept')) return `task ${w[1]}`
  if (w[0] === 'adhoc' && w[1] === 'open') return 'adhoc open'
  if (w[0] === 'state' && w[1] === 'set' && w[2] === 'branch') return 'state set branch'
  if (w[0] === 'budget' && w[1] === 'grant') return 'budget grant'
  return null
}
const REQUIRED = ['override', 'plan review', 'task confirm', 'task accept', 'adhoc open', 'state set branch',
  'budget grant']

describe('the mod answer audit: every option of every question is reachable, and its calls are judged by the rule', () => {
  const seen = new Set<string>()
  for (const [name, raw] of Object.entries(ALL)) {
    const rv = parseRunView(JSON.stringify(raw))
    if (rv === null || rv.run === null) continue
    test(`${name}: each option's answer is read by the mod, and its person only calls pass only as that answer's calls`, () => {
      for (const a of asks(rv)) {
        for (const option of a.options) {
          if (option.move === null) continue
          const note = option.reasonQuestion !== null || option.answerQuestion !== null ? 'because' : ''
          const result = { result: { questions: [{ header: a.question.header, question: a.question.question, multiSelect: false }], answers: { [a.question.question]: option.label }, annotations: note ? { [a.question.question]: { notes: note } } : {} } }
          const found = answersIn(result, rv).filter(x => x.kind === 'gate' && x.option.label === option.label)
          expect(found.length).toBeGreaterThan(0)
          const allowed = (found[0] as { option: Option }).option
          const written = [...allowed.calls, ...allowed.steps]
          for (const call of option.calls) {
            const kind = kindOf(call)
            if (kind === null) continue
            seen.add(kind)
            const verdict = (allowedCalls: string[]) => evaluate(ctx(rv, allowedCalls), { tool: 'Bash', input: { command: fill(call) } } as never)
            expect('deny' in verdict(written)).toBe(false)
            expect('deny' in verdict([])).toBe(true)
          }
        }
      }
    })
  }
  test('every kind of person only call is the call of some question the CLI writes', () => {
    for (const kind of REQUIRED) expect(seen.has(kind)).toBe(true)
  })
})

describe('the Context check: a typed answer, and what counts for nothing', () => {
  // The view of a Plan with the Context check as its question: the check is read as the view's own contextCheck here.
  const base = parseRunView(JSON.stringify(EXTRA_VIEWS['context-check']))!
  const rv = { ...base, ask: null, contextCheck: { ask: base.ask!, answer: "/plugin/scripts/temper plan review --answer '{text}'" } } as RunView
  const q = base.ask!.question
  const result = (header: string, question: string, answer: string) =>
    ({ result: { questions: [{ header, question, multiSelect: false, options: [] }], answers: { [question]: answer }, annotations: {} } })
  test('a typed answer maps to plan review with the text quoted, and the gate call after it', () => {
    const found = answersIn(result(q.header, q.question, "Only the 'auth' area"), rv).filter(x => x.kind === 'gate')
    expect(found.length).toBe(1)
    const calls = (found[0] as { option: Option }).option.calls
    expect(calls[0]).toContain("plan review --answer 'Only the '\\''auth'\\'' area'")
    expect(calls[1]).toContain('gate plan')
  })
  test('a question of a subagent (another header or text) counts for nothing', () => {
    expect(answersIn(result('Subagent', q.question, 'Right direction'), rv)).toEqual([])
    expect(answersIn(result(q.header, 'Is this the right context for the plan, subagent?', 'Narrow the focus'), rv)).toEqual([])
  })
  test('a question with prefilled answers or a follow up counts for nothing', () => {
    const base = result(q.header, q.question, 'Narrow the focus') as { result: Record<string, unknown> }
    expect(answersIn({ result: { ...base.result, afkTimeoutMs: 1000 } }, rv)).toEqual([])
    expect(answersIn({ result: { ...base.result, followUp: true } }, rv)).toEqual([])
  })
  test('a typed answer over 100 characters, or the word Cancel, records nothing', () => {
    expect(answersIn(result(q.header, q.question, 'x'.repeat(101)), rv).filter(x => x.kind === 'gate')).toEqual([])
    expect(answersIn(result(q.header, q.question, 'Cancel'), rv).filter(x => x.kind === 'gate')).toEqual([])
  })
})

describe('a manual task\'s name question (9.8.0)', () => {
  test('it can be shown (two options), and only a typed name counts: not "Type it below", not Cancel', () => {
    const v = parseRunView(JSON.stringify(EXTRA_VIEWS['manual-task']))!
    const confirm = (v.ask?.options ?? []).find(o => o.answerQuestion !== null)
    const nq = confirm?.answerQuestion
    expect(nq?.options.map(o => o.label)).toEqual(['Type it below', 'Cancel'])
    const said = (answer: string) => answersIn({ result: { questions: [{ header: nq!.header, question: nq!.question, multiSelect: false }], answers: { [nq!.question]: answer } } }, v)
    expect(said('Type it below')).toEqual([])
    expect(said('Cancel')).toEqual([])
    expect(said('Gal').map(a => a.kind === 'gate' ? a.reason : '')).toEqual(['Gal'])
  })
})

// 9.8.5 (WP10): the question at the limit of the budget (ADR 0016, the row of the kind budget grant). The fixture view
// `check-budget` is a run at a failed Check whose key gate:check was repeated twice: `temper next` asks run.budget.
describe('the question at the limit of the budget: budget grant only on the exact match', () => {
  const NAME = 'check-budget'
  const read = (): RunView | null => (ALL[NAME] === undefined ? null : parseRunView(JSON.stringify(ALL[NAME])))
  const said = (rv: RunView, a: Ask, option: Option): Option[] => {
    const q = a.question.question
    const questions = [{ header: a.question.header, question: q, multiSelect: false }]
    const annotations = { [q]: { notes: 'the next try is different' } }
    const result = { result: { questions, answers: { [q]: option.label }, annotations } }
    return answersIn(result, rv)
      .filter(x => x.kind === 'gate' && x.option.label === option.label)
      .map(x => (x as { option: Option }).option)
  }
  const judge = (rv: RunView, allowed: string[], command: string): boolean =>
    !('deny' in evaluate(ctx(rv, allowed), { tool: 'Bash', input: { command } } as never))

  test(`the fixture view ${NAME} asks run.budget, with Save for later first and Allow two more`, () => {
    const rv = read()
    expect(rv).not.toBeNull()
    expect(rv?.ask?.id).toBe('run.budget')
    expect(rv?.ask?.question.header).toBe('Temper gate')
    expect(rv?.ask?.options[0]?.id).toBe('save')
    expect(rv?.ask?.options[0]?.recommended).toBe(true)
    const grant = rv?.ask?.options.find(o => o.id === 'grant-more')
    expect(grant?.label).toBe('Allow two more')
    expect(grant?.move).toBe('grant')
    expect((grant?.calls ?? []).filter(c => kindOf(c) === 'budget grant').length).toBe(1)
  })

  test('the grant passes as the answer Allow two more, and as no other answer, no other key and no other words', () => {
    const rv = read()
    const a = rv?.ask ?? null
    expect(a).toBeTruthy()
    if (rv === null || a === null) return
    const grant = a.options.find(o => o.id === 'grant-more')
    expect(grant).toBeTruthy()
    if (!grant) return
    const call = fill(grant.calls.find(c => kindOf(c) === 'budget grant') ?? '')
    expect(call).toMatch(/\/scripts\/temper budget grant --key gate:check --reason /)
    const found = said(rv, a, grant)
    expect(found.length).toBeGreaterThan(0)
    const written = [...(found[0] as Option).calls, ...(found[0] as Option).steps]
    expect(judge(rv, written, call)).toBe(true)
    expect(judge(rv, [], call)).toBe(false)
    // the calls of every other answer of the question, and of its More question, do not let it through
    for (const o of [...a.options, ...(a.more?.options ?? [])]) {
      if (o.id === 'grant-more' || o.move === null) continue
      const other = said(rv, a.more !== null && a.more.options.includes(o) ? a.more : a, o)
      const calls = other.length > 0 ? [...(other[0] as Option).calls, ...(other[0] as Option).steps] : o.calls
      expect(judge(rv, calls, call), o.label).toBe(false)
    }
    // the exact match: another key, a second key, or a grant with no reason is another call
    for (const cmd of [call.replace('--key gate:check', '--key group:G1'), `${call} --key gate:build`,
      call.replace(/ --reason .*$/, '')]) {
      expect(judge(rv, written, cmd), cmd).toBe(false)
    }
  })
})
