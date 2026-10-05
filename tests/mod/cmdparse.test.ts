import { describe, expect, test } from 'claude-code/testing'

import { HELP, RESERVED, isReserved, parseArgs, planCommand } from '../../hooks/temper-mod/core/commands'

describe('parseArgs', () => {
  test('only the 18 reserved first words are claimed', () => {
    expect(RESERVED).toHaveLength(18)
    for (const w of RESERVED) expect(parseArgs(`${w} rest of it`)).toEqual({ word: w, rest: 'rest of it' })
  })

  test('a feature description, an empty line or a near miss is not claimed', () => {
    expect(parseArgs('add password reset by email')).toBe(null)
    expect(parseArgs('')).toBe(null)
    expect(parseArgs('   ')).toBe(null)
    expect(parseArgs('statuses')).toBe(null)
    expect(parseArgs('nextgen thing')).toBe(null)
    expect(isReserved('status')).toBe(true)
    expect(isReserved('build')).toBe(false)
  })

  test('the word is case insensitive and extra spaces are trimmed', () => {
    expect(parseArgs('  Override   too risky  ')).toEqual({ word: 'override', rest: 'too risky' })
  })
})

describe('planCommand', () => {
  const plan = (args: string, pending: string | null = null) => planCommand(parseArgs(args)!, pending)

  test('decisions map to machine commands', () => {
    expect(plan('approve')).toEqual({ kind: 'command', command: { type: 'approve' } })
    expect(plan('next')).toEqual({ kind: 'command', command: { type: 'advance' } })
    expect(plan('override reviewer is on leave')).toEqual({ kind: 'command', command: { type: 'override', reason: 'reviewer is on leave' } })
    expect(plan('override')).toEqual({ kind: 'command', command: { type: 'override', reason: '' } })
    expect(plan('back plan need a cache layer')).toEqual({ kind: 'command', command: { type: 'back', to: 'plan', reason: 'need a cache layer' } })
    expect(plan('accept 2 false positive')).toEqual({ kind: 'command', command: { type: 'acceptFinding', id: '2', reason: 'false positive' } })
  })

  test('usage errors', () => {
    expect(plan('back sideways x')).toMatchObject({ kind: 'error' })
    expect(plan('back fix x')).toMatchObject({ kind: 'error' })
    expect(plan('accept')).toMatchObject({ kind: 'error' })
    expect(plan('drift maybe')).toMatchObject({ kind: 'error' })
  })

  test('drift needs a pending path and maps allow to allow-once', () => {
    expect(plan('drift allow hotfix')).toMatchObject({ kind: 'error', text: expect.stringContaining('No scope drift waits for a decision') })
    expect(plan('drift allow hotfix', 'src/a.ts')).toEqual({
      kind: 'command',
      command: { type: 'drift', path: 'src/a.ts', choice: 'allow-once', reason: 'hotfix' },
    })
    expect(plan('drift add', 'src/a.ts')).toMatchObject({ command: { choice: 'add', reason: '' } })
  })

  test('read-only words are local', () => {
    for (const w of ['status', 'timeline', 'help', 'report', 'pr', 'mode', 'enforcement', 'pane']) {
      expect(plan(w)).toEqual({ kind: 'local', word: w, rest: '' })
    }
  })
})

describe('help', () => {
  test('lists every reserved word and has no em or en dash', () => {
    for (const w of ['status', 'timeline', 'approve', 'next', 'back', 'override', 'accept', 'drift', 'pause', 'resume', 'report', 'pr', 'mode', 'enforcement', 'pane']) {
      expect(HELP).toContain(w)
    }
    expect(/[\u2013\u2014]/.test(HELP)).toBe(false)
  })
})
