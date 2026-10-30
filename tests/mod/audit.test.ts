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
  return null
}
const REQUIRED = ['override', 'plan review', 'task confirm', 'task accept', 'adhoc open', 'state set branch']

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
