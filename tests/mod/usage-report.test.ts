// The run report the mod keeps and shows (`/temper:temper report`) carries the CLI's usage rows (.temper/usage.json),
// per stage, per model and in total, as `temper report` prints them. A missing or unreadable file gives "None.".
import { describe, expect, test } from 'claude-code/testing'

import { USAGE_NOTE, parseUsage, renderReport } from '../../hooks/temper-mod/core/report'
import { runFiles } from './run-files'
import { world } from './world'

const ROWS = JSON.stringify([
  { stage: 'intent', model: 'opus', tokens: 1000, ms: 2000, task: null, group: null, ts: 't' },
  { stage: 'task', model: 'haiku', tokens: 300, ms: 400, task: 1, group: 'G1', ts: 't' },
  { stage: 'task', model: 'haiku', tokens: null, ms: 600, task: 2, group: 'G1', ts: 't' },
])

const report = (usage = parseUsage(ROWS)) =>
  renderReport({ slug: 'pw', title: 'Password reset', stage: 'intent', gates: {}, skips: {}, loops: [], decisions: [], criteria: [], generatedAt: 1700000000000, usage })

describe('the usage section of the report', () => {
  test('rows per stage, per model and in total, with the same caveat as temper report', () => {
    const md = report()
    expect(md).toContain('## Usage')
    expect(md).toContain(USAGE_NOTE)
    expect(md).toContain('| intent | 1 | 1000 | 2000 |')
    expect(md).toContain('| task | 2 | 300 | 1000 |')
    expect(md).toContain('| opus | 1 | 1000 | 2000 |')
    expect(md).toContain('| haiku | 2 | 300 | 1000 |')
    expect(md).toContain('Total: 3 launches, 1300 tokens, 3000 ms')
  })

  test('no usage file, or one that does not read, gives None.', () => {
    for (const text of ['', 'not json', '{"a":1}']) {
      const md = report(parseUsage(text))
      expect(md).toMatch(/## Usage\n\nNone\.\n/)
      expect(md).not.toContain(USAGE_NOTE)
    }
  })

  test('malformed rows are left out, and a missing number shows as a dash', () => {
    const rows = parseUsage(JSON.stringify([5, 'x', null, [1], { stage: 'plan', tokens: 'many', ms: 1.5 }]))
    expect(rows).toEqual([{ stage: 'plan', model: 'unknown', tokens: null, ms: null }])
    const md = report(rows)
    expect(md).toContain('| plan | 1 | - | - |')
    expect(md).toContain('Total: 1 launches, - tokens, - ms')
  })

  test('/temper:temper report shows it, read through the mod', async ($, on) => {
    world(on, { ...runFiles({ nextStage: 'build' }), '.temper/usage.json': ROWS })
    const r = await $.command.run({ command: 'temper', args: 'report', origin: { kind: 'composer' } } as never)
    expect(r.text).toContain('Total: 3 launches, 1300 tokens, 3000 ms')
  })

  test('the report kept when the run completes includes it', async ($, on) => {
    const w = world(on, { ...runFiles({ nextStage: 'check', gates: { check: 'PASS' } }), '.temper/usage.json': ROWS }, { fakeCli: true })
    await $.session.start({ cwd: '/repo', surface: null, isInteractive: false })
    // The CLI moves the run to Done (ADR 0012); the mod keeps the report when it sees that.
    await $.tool.call({ tool: 'Bash', command: 'scripts/temper state advance check_complete commit' } as never)
    const kept = w.files.get('.temper/report.md') ?? ''
    expect(kept).toContain('Result: Done')
    expect(kept).toContain('Total: 3 launches, 1300 tokens, 3000 ms')
  })
})
