import { describe, expect, test } from 'claude-code/testing'

import { answersIn } from '../../hooks/temper-mod/core/answers'
import { parseRunView } from '../../hooks/temper-mod/core/runview'
import { SPEC, runFiles, view } from './run-files'
import { denyText, world } from './world'

const edit = (path: string) => ({ tool: 'Edit', file_path: path, old_string: 'a', new_string: 'b' }) as const

// The Scope drift question as Claude asks it: the file, Claude's why, the change, and the three choices.
const question = (path: string) =>
  `Outside the plan: ${path}\nWhy: a used reset token still lets billing charge the old account.\nChange: read the user through the token lookup.`
const ask = (path: string, header = 'Scope drift', extra: Record<string, unknown> = {}) =>
  ({
    tool: 'AskUserQuestion',
    questions: [
      {
        question: question(path),
        header,
        multiSelect: false,
        options: [
          { label: 'Add to plan', description: 'The file becomes part of the plan.' },
          { label: 'Revert', description: 'Skip it and stay inside the plan.' },
          { label: 'Allow once', description: 'Only this change; the reason goes in the report.' },
        ],
      },
    ],
    ...extra,
  }) as never

// The person's Scope drift answers the mod keeps (ADR 0012: in its store, one list per run), and whether each Allow once
// was used: `drift:<choice>:<reason>:<path>`, then `used` when a write spent it.
type W = ReturnType<typeof world>
const eventTypes = (w: W): string[] =>
  Object.entries(w.store)
    .filter(([k]) => k.startsWith('dec:'))
    .flatMap(([, v]) => v as Array<{ id: string; kind: string; choice?: string; reason?: string; path?: string }>)
    .filter(d => d.kind === 'drift')
    .flatMap(d => [`drift:${d.choice ?? ''}:${d.reason ?? ''}:${d.path ?? ''}`, ...(w.store[`used:${d.id}`] ? [`used:${d.path ?? ''}`] : [])])

describe('scope drift in Build', () => {
  test('a write outside the plan is refused with the Scope drift question to ask, and the mod asks nothing itself', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    const r = await $.tool.call(edit('src/billing.ts'))
    expect(denyText(r)).toContain('scope drift')
    expect(denyText(r)).toContain('DRIFT section')
    expect(denyText(r)).toContain('Outside the plan: src/billing.ts')
    expect(denyText(r)).toContain('"Why:" line')
    expect(w.asked).toEqual([])
    expect(eventTypes(w)).toEqual([])
  })

  test('the person answers "Add to plan": recorded as theirs, and the file is in the plan from then on', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }), { answers: ['Add to plan'] })
    expect('deny' in (await $.tool.call(edit('src/billing.ts')))).toBe(true)
    await $.tool.call(ask('src/billing.ts'))
    expect(w.asked[0]).toContain('Why: a used reset token')
    expect(eventTypes(w)).toEqual(['drift:add::src/billing.ts'])
    expect((await $.tool.call(edit('src/billing.ts'))).text).toBe('stub ran')
    expect((await $.tool.call(edit('src/billing.ts'))).text).toBe('stub ran')
  })

  test('"Revert" is recorded and the file stays out of the plan', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }), { answers: ['Revert'] })
    await $.tool.call(ask('src/billing.ts'))
    expect(eventTypes(w)).toEqual(['drift:revert::src/billing.ts'])
    expect(denyText(await $.tool.call(edit('src/billing.ts')))).toContain('scope drift')
  })

  test('"Allow once" lets exactly one edit through, with Claude\'s why as the reason', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }), { answers: ['Allow once'] })
    await $.tool.call(ask('src/hotfix.ts'))
    expect((await $.tool.call(edit('src/hotfix.ts'))).text).toBe('stub ran')
    expect(eventTypes(w)).toEqual([
      'drift:allow-once:why (Claude): a used reset token still lets billing charge the old account.:src/hotfix.ts',
      'used:src/hotfix.ts',
    ])
    expect('deny' in (await $.tool.call(edit('src/hotfix.ts')))).toBe(true)
  })

  test('a question nobody answered decides nothing', async ($, on) => {
    const none = world(on, runFiles({ nextStage: 'build' }))
    await $.tool.call(ask('src/billing.ts'))
    expect(eventTypes(none)).toEqual([])
  })

  test('an answer the caller wrote into the question is not the person\'s answer', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    await $.tool.call(ask('src/billing.ts', 'Scope drift', { answers: { [question('src/billing.ts')]: 'Add to plan' } }))
    expect(eventTypes(w)).toEqual([])
    expect(denyText(await $.tool.call(edit('src/billing.ts')))).toContain('scope drift')
  })

  test('the deny asks the Scope drift question and invites no typing', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    const r = await $.tool.call(edit('src/billing.ts'))
    expect(denyText(r)).toContain('the options Add to plan, Revert, Allow once.')
    expect(denyText(r)).not.toContain('/temper:temper')
    expect(eventTypes(w)).toEqual([])
  })
})

describe('reading the Scope drift answer', () => {
  const rv = parseRunView(JSON.stringify(view('build-work')))
  if (rv === null) throw new Error('no view')
  const result = (header: string, answer: string, q = question('src/a.ts')) => ({ result: { questions: [{ question: q, header }], answers: { [q]: answer } } })
  const drift = (r: unknown) => answersIn(r, rv).filter(a => a.kind === 'drift')

  test('the three choices map to the three decisions', () => {
    expect(drift(result('Scope drift', 'Add to plan'))).toEqual([{ kind: 'drift', path: 'src/a.ts', choice: 'add', reason: '' }])
    expect(drift(result('Scope drift', 'Revert'))).toEqual([{ kind: 'drift', path: 'src/a.ts', choice: 'revert', reason: '' }])
    expect(drift(result('Scope drift', 'Allow once'))[0]).toMatchObject({ choice: 'allow-once' })
  })

  test('the header and the choice must be the ones the CLI wrote, exactly', () => {
    expect(drift(result('scope drift', 'Add to plan'))).toEqual([])
    expect(drift(result('Scope drift', 'allow once'))).toEqual([])
    expect(drift(result('Scope drift', 'Add to plan (Recommended)'))).toEqual([])
  })

  test('another header, a typed answer, a missing path or no result is no decision', () => {
    expect(drift(result('Library', 'Add to plan'))).toEqual([])
    expect(drift(result('Scope drift', 'yes please'))).toEqual([])
    expect(drift(result('Scope drift', 'Add to plan', 'Why: no path line'))).toEqual([])
    expect(drift(undefined)).toEqual([])
    expect(drift({ result: 'stub ran' })).toEqual([])
  })

  test('a trailing period after the path is not part of the path; an empty why still gives Allow once a reason', () => {
    expect(drift(result('Scope drift', 'Add to plan', 'Outside the plan: src/a.ts.'))[0]).toMatchObject({ path: 'src/a.ts' })
    expect(drift(result('Scope drift', 'Allow once', 'Outside the plan: src/a.ts'))[0]).toMatchObject({ reason: 'why (Claude): not given' })
  })
})
