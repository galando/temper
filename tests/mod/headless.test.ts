// Final review: a headless run (`claude -p`, the Agent SDK) and the decisions of the person. With enforcement on, a
// decision word from any origin but the person's prompt box is refused, and the refusal says that decisions need an
// interactive session instead of naming the command that was just typed. With enforcement off (the person switched the
// guard off), the decision is recorded with the origin it came from, and the prompt based command carries on.
import { describe, expect, test } from 'claude-code/testing'

import { SPEC, runFiles } from './run-files'
import { world } from './world'
import type { World } from './world'

type Api = {
  session: { start: (a: unknown) => Promise<unknown> }
  command: { run: (a: unknown) => Promise<{ text?: string }> }
  tool: { call: (a: unknown) => Promise<{ deny?: string }> }
}
const START = { cwd: '/repo', surface: null, isInteractive: false } as const
const PASSTHROUGH = 'prompt based /temper:temper ran'
const OFF = { options: { enforcement: 'off' } }
const INTERACTIVE = /decisions need an interactive session/
// The old refusal sent the person back to the command they had just typed.
const SAME_COMMAND = 'press 1 or run /temper:temper approve'

const decisions = (w: World): Array<Record<string, unknown>> =>
  [...w.files.entries()]
    .filter(([p]) => p.startsWith(`${SPEC}/events/`))
    .map(([, t]) => JSON.parse(t) as Record<string, unknown>)
    .filter(e => e.type !== 'start')
const say = (api: Api, args: string, origin: unknown) => api.command.run({ command: 'temper:temper', args, origin })

const REVIEW = { ...runFiles({ nextStage: 'review' }), '.temper/evidence/review.json': JSON.stringify([{ severity: 'major', claim: 'x' }]) }
// Each decision word, in a run where a person may make it.
const WORDS: Array<[string, Record<string, string>]> = [
  ['approve', runFiles({ nextStage: 'plan', gates: { plan: 'PASS' } })],
  ['next', runFiles({ nextStage: 'plan', gates: { plan: 'PASS' } })],
  ['back intent the problem changed', runFiles({ nextStage: 'plan' })],
  ['override the reviewer is away', runFiles({ nextStage: 'build' })],
  ['accept 1 it is not a real issue', REVIEW],
  ['drift add the helper file', runFiles({ nextStage: 'build' })],
]
const ORIGINS: unknown[] = [{ kind: 'sdk' }, { kind: 'model' }, { kind: 'plugin', name: 'other' }, { kind: 'hook' }, undefined]

describe('final review: with enforcement on, a decision needs the prompt box of an interactive session', () => {
  for (const [word, files] of WORDS) {
    test(`${word.split(' ')[0]} from another origin is refused, with where to decide`, async ($, on) => {
      const api = $ as unknown as Api
      const w = world(on, files)
      await api.session.start(START)
      for (const origin of ORIGINS) {
        const text = (await say(api, word, origin)).text ?? ''
        expect(text, JSON.stringify(origin)).toMatch(INTERACTIVE)
        expect(text).toContain('Only the user decides')
        expect(text).toMatch(/Next: /)
        expect(text).not.toContain(SAME_COMMAND)
      }
      expect(decisions(w)).toEqual([])
      expect(w.commandRuns).toEqual([])
    })
  }

  test('pause, resume and the settings words get the same answer', async ($, on) => {
    const api = $ as unknown as Api
    const w = world(on, runFiles({ nextStage: 'build' }))
    await api.session.start(START)
    for (const word of ['pause', 'resume', 'mode off', 'enforcement off']) expect((await say(api, word, { kind: 'sdk' })).text, word).toMatch(INTERACTIVE)
    expect(decisions(w)).toEqual([])
    expect(w.configSets).toEqual([])
  })
})

describe('final review: with enforcement off, a decision from a headless run is recorded with its origin', () => {
  test('approve from the SDK at the plan gate: recorded, and the prompt based command carries on', OFF, async ($, on) => {
    const api = $ as unknown as Api
    const w = world(on, runFiles({ nextStage: 'plan', gates: { plan: 'PASS' } }))
    await api.session.start(START)
    expect((await say(api, 'approve', { kind: 'sdk' })).text).toBe(PASSTHROUGH)
    expect(decisions(w)).toEqual([expect.objectContaining({ type: 'advance', from: 'plan', to: 'build', origin: 'model', author: 'sdk origin' })])
    expect(w.commandRuns.map(r => r.origin)).toEqual(['sdk'])
    // The orchestrator's mirror call passes (enforcement is off).
    expect((await api.tool.call({ tool: 'Bash', command: 'scripts/temper state advance plan_complete build' })).deny).toBeUndefined()
  })

  test('a step back from the SDK is recorded with its origin', OFF, async ($, on) => {
    const api = $ as unknown as Api
    const w = world(on, runFiles({ nextStage: 'plan' }))
    await api.session.start(START)
    expect((await say(api, 'back intent the problem changed', { kind: 'sdk' })).text).toBe(PASSTHROUGH)
    expect(decisions(w).map(e => [e.type, e.to, e.origin, e.author])).toEqual([['back', 'intent', 'model', 'sdk origin']])
  })

  test('a skip from the SDK is recorded with its origin, and the report shows it', OFF, async ($, on) => {
    const api = $ as unknown as Api
    const w = world(on, runFiles({ nextStage: 'build' }))
    await api.session.start(START)
    expect((await say(api, 'override the reviewer is away', { kind: 'sdk' })).text).toBe(PASSTHROUGH)
    expect(decisions(w).map(e => [e.type, e.origin, e.author])).toEqual([['override', 'model', 'sdk origin']])
    expect((await say(api, 'report', { kind: 'composer' })).text).toContain('Build: overridden, reason: the reviewer is away (by sdk origin,')
  })

  test('an accepted finding from the SDK is recorded with its origin, and the report shows it', OFF, async ($, on) => {
    const api = $ as unknown as Api
    const w = world(on, REVIEW)
    await api.session.start(START)
    expect((await say(api, 'accept 1 it is not a real issue', { kind: 'sdk' })).text).toBe(PASSTHROUGH)
    expect(decisions(w).map(e => [e.type, e.origin, e.author])).toEqual([['accept', 'model', 'sdk origin']])
    expect((await say(api, 'report', { kind: 'composer' })).text).toContain('Finding 1: accepted, reason: it is not a real issue (by sdk origin,')
  })

  test('a command with no origin is recorded as from an unknown origin', OFF, async ($, on) => {
    const api = $ as unknown as Api
    const w = world(on, runFiles({ nextStage: 'plan', gates: { plan: 'PASS' } }))
    await api.session.start(START)
    expect((await say(api, 'approve', undefined)).text).toBe(PASSTHROUGH)
    expect(decisions(w).map(e => [e.origin, e.author])).toEqual([['model', 'unknown origin']])
  })

  test('the person at the prompt box is still recorded as the person', OFF, async ($, on) => {
    const api = $ as unknown as Api
    const w = world(on, runFiles({ nextStage: 'plan', gates: { plan: 'PASS' } }))
    await api.session.start(START)
    expect((await say(api, 'approve', { kind: 'composer' })).text).toBe(PASSTHROUGH)
    expect(decisions(w).map(e => [e.origin, e.author])).toEqual([['person', 'user']])
  })

  test('pause, resume and the settings words stay the person\'s own', OFF, async ($, on) => {
    const api = $ as unknown as Api
    const w = world(on, runFiles({ nextStage: 'build' }))
    await api.session.start(START)
    for (const word of ['pause', 'resume', 'mode off', 'enforcement on']) expect((await say(api, word, { kind: 'sdk' })).text, word).toMatch(INTERACTIVE)
    expect(decisions(w)).toEqual([])
    expect(w.configSets).toEqual([])
  })

  test('the rules of a decision still apply: an approval before the check passed is refused', OFF, async ($, on) => {
    const api = $ as unknown as Api
    const w = world(on, runFiles({ nextStage: 'plan' }))
    await api.session.start(START)
    expect((await say(api, 'approve', { kind: 'sdk' })).text).toMatch(/has not passed its check/)
    expect(decisions(w)).toEqual([])
  })
})
