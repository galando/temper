import { describe, expect, test } from 'claude-code/testing'

import { driftAnswers } from '../../hooks/temper-mod/core/drift'
import { SPEC, runFiles } from './run-files'
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

const eventTypes = (files: Map<string, string>): string[] =>
  [...files.entries()]
    .filter(([p]) => p.startsWith(`${SPEC}/events/`))
    .map(([, t]) => JSON.parse(t) as { type: string; choice?: string; reason?: string; path?: string; origin?: string })
    .filter(e => e.type === 'drift' || e.type === 'driftUsed')
    .map(e => `${e.type}:${e.choice ?? ''}:${e.reason ?? ''}:${e.path ?? ''}:${e.origin}`)

describe('scope drift in Build', () => {
  test('a write outside the plan is refused with the Scope drift question to ask, and the mod asks nothing itself', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    const r = await $.tool.call(edit('src/billing.ts'))
    expect(denyText(r)).toContain('scope drift')
    expect(denyText(r)).toContain('DRIFT section')
    expect(denyText(r)).toContain('Outside the plan: src/billing.ts')
    expect(denyText(r)).toContain('"Why:" line')
    expect(w.asked).toEqual([])
    expect(eventTypes(w.files)).toEqual([])
  })

  test('the person answers "Add to plan": recorded as theirs, and the file is in the plan from then on', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }), { answers: ['Add to plan'] })
    expect('deny' in (await $.tool.call(edit('src/billing.ts')))).toBe(true)
    await $.tool.call(ask('src/billing.ts'))
    expect(w.asked[0]).toContain('Why: a used reset token')
    expect(eventTypes(w.files)).toEqual(['drift:add::src/billing.ts:person'])
    expect((await $.tool.call(edit('src/billing.ts'))).text).toBe('stub ran')
    expect((await $.tool.call(edit('src/billing.ts'))).text).toBe('stub ran')
  })

  test('"Revert" is recorded and the file stays out of the plan', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }), { answers: ['Revert'] })
    await $.tool.call(ask('src/billing.ts'))
    expect(eventTypes(w.files)).toEqual(['drift:revert::src/billing.ts:person'])
    expect(denyText(await $.tool.call(edit('src/billing.ts')))).toContain('scope drift')
  })

  test('"Allow once" lets exactly one edit through, with Claude\'s why as the reason', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }), { answers: ['Allow once'] })
    await $.tool.call(ask('src/hotfix.ts'))
    expect((await $.tool.call(edit('src/hotfix.ts'))).text).toBe('stub ran')
    expect(eventTypes(w.files)).toEqual([
      'drift:allow-once:why (Claude): a used reset token still lets billing charge the old account.:src/hotfix.ts:person',
      'driftUsed:::src/hotfix.ts:system',
    ])
    expect('deny' in (await $.tool.call(edit('src/hotfix.ts')))).toBe(true)
  })

  test('a question nobody answered decides nothing', async ($, on) => {
    const none = world(on, runFiles({ nextStage: 'build' }))
    await $.tool.call(ask('src/billing.ts'))
    expect(eventTypes(none.files)).toEqual([])
  })

  test('an answer the caller wrote into the question is not the person\'s answer', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    await $.tool.call(ask('src/billing.ts', 'Scope drift', { answers: { [question('src/billing.ts')]: 'Add to plan' } }))
    expect(eventTypes(w.files)).toEqual([])
    expect(denyText(await $.tool.call(edit('src/billing.ts')))).toContain('scope drift')
  })

  test('with nobody to ask, the person can still decide by typing /temper:temper drift', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'build' }))
    const r = await $.tool.call(edit('src/billing.ts'))
    expect(denyText(r)).toContain('/temper:temper drift add|revert|allow <reason>')
    expect(eventTypes(w.files)).toEqual([])
  })
})

describe('reading the Scope drift answer', () => {
  const result = (header: string, answer: string, q = question('src/a.ts')) => ({ result: { questions: [{ question: q, header }], answers: { [q]: answer } } })

  test('the three choices map to the three decisions', () => {
    expect(driftAnswers(result('Scope drift', 'Add to plan'))).toEqual([{ path: 'src/a.ts', choice: 'add', reason: '' }])
    expect(driftAnswers(result('Scope drift', 'Revert'))).toEqual([{ path: 'src/a.ts', choice: 'revert', reason: '' }])
    expect(driftAnswers(result('scope drift', 'allow once'))[0]?.choice).toBe('allow-once')
  })

  test('another header, a typed answer, a missing path or no result is no decision', () => {
    expect(driftAnswers(result('Library', 'Add to plan'))).toEqual([])
    expect(driftAnswers(result('Scope drift', 'yes please'))).toEqual([])
    expect(driftAnswers(result('Scope drift', 'Add to plan', 'Why: no path line'))).toEqual([])
    expect(driftAnswers(undefined)).toEqual([])
    expect(driftAnswers({ result: 'stub ran' })).toEqual([])
  })

  test('a trailing period after the path is not part of the path; an empty why still gives Allow once a reason', () => {
    expect(driftAnswers(result('Scope drift', 'Add to plan', 'Outside the plan: src/a.ts.'))[0]?.path).toBe('src/a.ts')
    expect(driftAnswers(result('Scope drift', 'Allow once', 'Outside the plan: src/a.ts'))[0]?.reason).toBe('why (Claude): not given')
  })
})
