import { describe, expect, test } from 'claude-code/testing'

import { runFiles } from './run-files'
import { COMPOSE, world } from './world'

const write = (path: string) => ({ tool: 'Write', file_path: path, content: 'x' }) as const

describe('version guard', () => {
  for (const version of ['2.1.286', '2.1.200', '2.0.9', 'not-a-version']) {
    test(`stays inert on ${version}: no deny, no section`, async ($, on) => {
      world(on, runFiles({ nextStage: 'plan' }), { version })
      await $.session.start({ cwd: '/repo', surface: null, isInteractive: false })
      expect((await $.tool.call(write('src/app.ts'))).text).toBe('stub ran')
      const { sections } = await $.prompt.compose(COMPOSE)
      expect(sections.some(s => s.id === 'temper:phase')).toBe(false)
    })
  }

  test('stays inert when the version call rejects', async ($, on) => {
    world(on, runFiles({ nextStage: 'plan' }), { version: null })
    await $.session.start({ cwd: '/repo', surface: null, isInteractive: false })
    expect((await $.tool.call(write('src/app.ts'))).text).toBe('stub ran')
    expect((await $.prompt.compose(COMPOSE)).sections.some(s => s.id === 'temper:phase')).toBe(false)
  })

  test('acts from 2.1.287', async ($, on) => {
    world(on, runFiles({ nextStage: 'plan' }), { version: '2.1.287' })
    await $.session.start({ cwd: '/repo', surface: null, isInteractive: false })
    expect('deny' in (await $.tool.call(write('src/app.ts')))).toBe(true)
    expect((await $.prompt.compose(COMPOSE)).sections.some(s => s.id === 'temper:phase')).toBe(true)
  })

  test('an inert mod touches no Temper file', async ($, on) => {
    const w = world(on, runFiles({ nextStage: 'plan' }), { version: '2.1.286' })
    await $.session.start({ cwd: '/repo', surface: null, isInteractive: false })
    expect(w.reads).toEqual([])
    expect(w.writes).toEqual([])
  })
})
