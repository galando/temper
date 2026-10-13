// The run report the mod keeps and shows (`/temper:temper report`) carries the usage of view.json (the CLI sums
// .temper/usage.json), per stage, per model and in total, as `temper report` prints them. No usage gives "None.".
import { describe, expect, test } from 'claude-code/testing'

import { USAGE_NOTE, renderReport } from '../../hooks/temper-mod/core/report'
import { parseRunView } from '../../hooks/temper-mod/core/runview'
import { runFiles, view } from './run-files'
import { world } from './world'

const ROWS = JSON.stringify([
  { stage: 'intent', model: 'opus', tokens: 1000, ms: 2000, task: null, group: null, ts: 't' },
  { stage: 'task', model: 'haiku', tokens: 300, ms: 400, task: 1, group: 'G1', ts: 't' },
  { stage: 'task', model: 'haiku', tokens: null, ms: 600, task: 2, group: 'G1', ts: 't' },
])

const USAGE = {
  tokens: 1300,
  ms: 3000,
  by_stage: { intent: { tokens: 1000, ms: 2000, runs: 1 }, task: { tokens: 300, ms: 1000, runs: 2 } },
  by_model: { opus: { tokens: 1000, ms: 2000, runs: 1 }, haiku: { tokens: 300, ms: 1000, runs: 2 } },
}

const report = (usage: unknown) => {
  const v = parseRunView(JSON.stringify({ ...view('build-work'), usage }))
  if (v === null) throw new Error('no view')
  return renderReport({ view: v, decisions: [], generatedAt: 1700000000000 })
}

describe('the usage section of the report', () => {
  test('rows per stage, per model and in total, with the same caveat as temper report', () => {
    const md = report(USAGE)
    expect(md).toContain('## Usage')
    expect(md).toContain(USAGE_NOTE)
    expect(md).toContain('| intent | 1 | 1000 | 2000 |')
    expect(md).toContain('| task | 2 | 300 | 1000 |')
    expect(md).toContain('| opus | 1 | 1000 | 2000 |')
    expect(md).toContain('| haiku | 2 | 300 | 1000 |')
    expect(md).toContain('Total: 3 launches, 1300 tokens, 3000 ms')
  })

  test('no usage, or usage that is not the shape view.json gives, gives None.', () => {
    for (const usage of [undefined, 'not usage', { tokens: 0, ms: 0, by_stage: {} }]) {
      const md = report(usage)
      expect(md).toMatch(/## Usage\n\nNone\.\n/)
      expect(md).not.toContain(USAGE_NOTE)
    }
  })

  test('/temper:temper report shows it, read through the mod', async ($, on) => {
    world(on, { ...runFiles({ nextStage: 'build' }), '.temper/usage.json': ROWS })
    const r = await $.command.run({ command: 'temper', args: 'report', origin: { kind: 'composer' } } as never)
    expect(r.text).toContain('Total: 3 launches, 1300 tokens, 3000 ms')
  })

  test('the report kept when the run completes includes it', async ($, on) => {
    const w = world(on, { ...runFiles({ nextStage: 'check', gates: { check: 'PASS' } }), '.temper/usage.json': ROWS }, { fakeCli: true })
    await $.session.start({ cwd: '/repo', surface: null, isInteractive: false })
    // The CLI moves the run to Done; the mod keeps the report when it sees that.
    await $.tool.call({ tool: 'Bash', command: 'scripts/temper state advance check_complete commit' } as never)
    const kept = w.files.get('.temper/report.md') ?? ''
    expect(kept).toContain('Result: Done')
    expect(kept).toContain('Total: 3 launches, 1300 tokens, 3000 ms')
  })
})
