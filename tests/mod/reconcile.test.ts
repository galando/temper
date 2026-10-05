// Where the CLI says the run is wins over the mod's own events (adapter.reconcile). Cases found in live runs.
import { describe, expect, test } from 'claude-code/testing'

import { loadSnapshot, reconcile } from '../../hooks/temper-mod/adapter'
import type { Io } from '../../hooks/temper-mod/adapter'
import { adv, stateAt } from './helpers'

describe('reconcile', () => {
  const approved = stateAt('build')
  test('the setup: the person approved the plan, so the mod is at Build', () => {
    expect(approved.phase).toBe('build')
  })

  test('the CLI is at its design stage after the plan approval: the run goes on, it is not a reset', () => {
    const r = reconcile(approved, 'design', null)
    expect(r.sync.looksReset).toBe(false)
    expect(r.sync.line).toBeNull()
    // Design is part of Plan: the phase drawn and enforced is Plan.
    expect(r.state.phase).toBe('plan')
  })

  test('the CLI at plan after the person went on to Build, with nothing pending, still looks reset', () => {
    const r = reconcile(approved, 'plan', null)
    expect(r.sync.looksReset).toBe(true)
    expect(r.sync.line).toContain('looks reset')
  })

  test('a person move that is not mirrored yet is pending, not a reset, also at design', () => {
    const pending = { id: 'x', draft: adv('plan', 'build') }
    const r = reconcile(approved, 'design', pending)
    expect(r.sync.looksReset).toBe(false)
    expect(r.sync.pending).toBe(pending)
  })
})

describe('build-state.json read while the CLI rewrites it (found live: the bar said "No Temper run is active" at Done)', () => {
  const STATE = JSON.stringify({ spec: 'pw', spec_path: '.temper/specs/pw', next_stage: 'commit' })
  // The first read of build-state.json sees what a read in the middle of a rewrite sees.
  const io = (first: string | null, reads: { n: number }): Io => ({
    read: async path => {
      if (!path.endsWith('build-state.json')) return null
      reads.n += 1
      return reads.n === 1 ? first : STATE
    },
    list: async () => [],
    write: async () => undefined,
    storeGet: async () => undefined,
    storeSet: async () => undefined,
    version: async () => '2.1.300',
    setRun: async () => undefined,
    setMode: async () => undefined,
  })

  test('an empty file is read again, and the run is found', async () => {
    const reads = { n: 0 }
    const snap = await loadSnapshot(io('', reads), {})
    expect(snap.slug).toBe('pw')
    expect(reads.n).toBe(2)
  })

  test('a cut file is read again too', async () => {
    const snap = await loadSnapshot(io('{"spec": "pw", "spec_pa', { n: 0 }), {})
    expect(snap.slug).toBe('pw')
  })

  test('a missing file is a run that ended: no second read, no run', async () => {
    const reads = { n: 0 }
    const snap = await loadSnapshot({ ...io(null, reads), read: async path => { if (path.endsWith('build-state.json')) reads.n += 1; return null } }, {})
    expect(snap.slug).toBeNull()
    expect(reads.n).toBe(1)
  })
})
