// A small spec directory as the files Temper reads. Not a test file.
import { encodeEvent, eventFileName, stamp } from '../../hooks/temper-mod/core/events'
import type { Draft } from '../../hooks/temper-mod/core/events'

export const SPEC = '.temper/specs/pw'

// Far in the future so a verdict is always newer than the run's start event.
export const LATER = '2999-01-01T00:00:00Z'

export const INTENT = [
  '# Intent: Password reset by email',
  '',
  '### Success Criteria',
  '',
  ...[1, 2, 3, 4, 5].map(n => `- [ ] AC-0${n} [required]: criterion ${n} (source: test)`),
  '',
].join('\n')

export const PLAN = ['### Files to Modify', '', '| File | Change |', '|---|---|', '| `src/app.ts` | edit |', ''].join('\n')

// Seven tasks; the first two have a ticked row, so the third is current.
export const TASKS = [
  '## Tasks',
  ...[1, 2, 3, 4, 5, 6, 7].flatMap(n => [`### Task ${n}: t${n}`, n <= 2 ? '- [x] done' : '- [ ] open']),
  '',
].join('\n')

export type RunOptions = {
  nextStage?: string
  gates?: Record<string, 'PASS' | 'FAIL'>
  passedCriteria?: string[]
}

export function runFiles(o: RunOptions = {}): Record<string, string> {
  const gates: Record<string, unknown> = {}
  for (const [stage, verdict] of Object.entries(o.gates ?? {})) gates[stage] = { verdict, ts: LATER }
  const files: Record<string, string> = {
    '.temper/build-state.json': JSON.stringify({ spec: 'pw', spec_path: SPEC, next_stage: o.nextStage ?? 'plan' }),
    '.temper/gates.json': JSON.stringify(gates),
    [`${SPEC}/intent.md`]: INTENT,
    [`${SPEC}/plan.md`]: PLAN,
    [`${SPEC}/tasks.md`]: TASKS,
  }
  if (o.passedCriteria) {
    files['.temper/status.json'] = JSON.stringify({
      ts: 't',
      criteria: [1, 2, 3, 4, 5].map(n => ({
        id: `AC-0${n}`,
        priority: 'required',
        status: o.passedCriteria?.includes(`AC-0${n}`) ? 'passed' : 'open',
        evidence: [],
      })),
    })
  }
  return files
}

// An event file as the mod writes it: [path, text].
export function eventFile(draft: Draft, ts: number, session = 's', seq = 1): [string, string] {
  const ev = stamp(draft, { ts, session, seq })
  return [`${SPEC}/events/${eventFileName(ev)}`, encodeEvent(ev)]
}
