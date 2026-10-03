// Shared test builders. Not a test file: `claude plugin test` only runs *.test.ts(x).
import { stamp } from '../../hooks/temper-mod/core/events'
import type { Draft, Phase } from '../../hooks/temper-mod/core/events'
import { reduce } from '../../hooks/temper-mod/core/machine'
import type { RunState, Verdicts } from '../../hooks/temper-mod/core/machine'

export const person = { origin: 'person', author: 'galando' } as const

export const adv = (from: Phase, to: Phase | 'done'): Draft => ({ type: 'advance', from, to, ...person })

export function fold(drafts: Draft[], verdicts: Verdicts = {}, opts: { maxLoops?: number } = {}): RunState {
  return reduce(
    drafts.map((d, i) => stamp(d, { ts: (i + 1) * 10_000, session: 's', seq: i + 1 })),
    verdicts,
    opts,
  )
}

const CHAIN: Phase[] = ['intent', 'plan', 'build', 'review', 'check']

// The folded state of a run currently in `phase`, started on spec "pw".
export function stateAt(phase: Phase, extra: Draft[] = []): RunState {
  const drafts: Draft[] = [{ type: 'start', slug: 'pw', title: 'Password reset', ...person }]
  const target = phase === 'fix' ? 'check' : phase
  for (let i = 0; CHAIN[i] !== target; i++) {
    const from = CHAIN[i]
    const to = CHAIN[i + 1]
    if (from === undefined || to === undefined) break
    drafts.push(adv(from, to))
  }
  if (phase === 'fix') drafts.push({ type: 'checkResult', result: 'fail', origin: 'system' })
  return fold([...drafts, ...extra])
}
