import type { Register } from 'claude-code'
import { describe, expect, test } from 'claude-code/testing'

import { runFiles } from './run-files'
import { world } from './world'

const write = (path: string) => ({ tool: 'Write', file_path: path, content: 'x' }) as const
const bash = (command: string) => ({ tool: 'Bash', command }) as const

describe('composition with a prepended managed guard', () => {
  const denyBash = {
    name: 'managed-guard',
    tier: 'prepend' as const,
    register: ((on) => {
      on('tool.call', { tool: 'Bash' }, () => ({ deny: 'managed guard: no shell' }))
    }) satisfies Register,
  }
  const allowAll = {
    name: 'managed-allow',
    tier: 'prepend' as const,
    register: ((on) => {
      on('tool.call', ($, e, next) => next(e))
    }) satisfies Register,
  }

  test('a prepended deny wins before Temper sees the call; Temper still denies the rest', { plugins: [denyBash] }, async ($, on) => {
    world(on, runFiles({ nextStage: 'plan' }))
    expect(await $.tool.call(bash('git commit -m x'))).toEqual({ deny: 'managed guard: no shell' })
    const r = await $.tool.call(write('src/app.ts'))
    expect(r.deny?.startsWith('Temper: Plan phase.')).toBe(true)
  })

  test('a prepended allow does not override Temper', { plugins: [allowAll] }, async ($, on) => {
    world(on, runFiles({ nextStage: 'plan' }))
    const r = await $.tool.call(write('src/app.ts'))
    expect(r.deny?.startsWith('Temper: Plan phase.')).toBe(true)
    expect((await $.tool.call(write('.temper/specs/pw/plan.md'))).text).toBe('stub ran')
  })
})
