// The mod's implicit state machines, made explicit (fix plan, section C): what outlives a reload of the module, the run
// held through a lost view.json, the one rule each guard state, small change window and TRIVIAL exit is read by, the
// run driver at an interrupt and while it waits, the person's answer recorded once, a decision spent once its call
// ran, the store entries that end with their run, loads taken in order, and the fix run's regression test shield.
import { describe, expect, test } from 'claude-code/testing'

import { enforces, guardsRun, idleSnapshot } from '../../hooks/temper-mod/adapter'
import type { Snapshot } from '../../hooks/temper-mod/adapter'
import { ANSWER_LOOKS, STOPPED, drive, lookAtAgents } from '../../hooks/temper-mod/core/driver'
import type { AgentEnd, GoOut, GoQuestion, Port } from '../../hooks/temper-mod/core/driver'
import { adhocOpen, evaluate, trivialExit } from '../../hooks/temper-mod/core/rules'
import type { RuleContext, RunFacts } from '../../hooks/temper-mod/core/rules'
import { SESSION_WRITE_DENY, evaluateSession, factsOf } from '../../hooks/temper-mod/core/session'
import { ADHOC_STAGES } from '../../hooks/temper-mod/core/stages'
import { stageToast } from '../../hooks/temper-mod/core/view'
import { FEATURE_DENY } from '../../hooks/temper-mod/core/session'
import { register } from '../../hooks/temper-mod/register'
import { SPEC, deriveView, questionOf, runFiles } from './run-files'
import { cliTo, world } from './world'

const CLI = '/home/u/.claude/plugins/temper/scripts/temper'
// The test runs where timers are (the lib of the type check has none).
declare const setTimeout: (f: () => void, ms: number) => unknown
const START = { cwd: '/repo', surface: 'terminal', isInteractive: true } as const
type Api = {
  session: { start: (a: unknown) => Promise<unknown> }
  command: { run: (a: unknown) => Promise<{ text?: string }> }
  tool: { call: (a: unknown) => Promise<{ deny?: string; text?: string; isError?: boolean }> }
}
const sh = async (api: Api, command: string) => (await api.tool.call({ tool: 'Bash', command })).deny
const agentWrite = async (api: Api, path: string) => (await api.tool.call({ tool: 'Write', file_path: `/repo/${path}`, content: 'x', agentId: 'agent' } as never)).deny

// ---- An engine of the test's own, to load the module twice in one session -----------------------------------------
// The kit loads the plugin once per test. A reload (a save of the mod's files, a change of its options, a hooks worker
// the engine started again) runs register() again with every module variable new, while `$.state` and `$.store` stay:
// this engine keeps those two across a load, and calls register() for each load, as the engine does.
type Hook = (...a: unknown[]) => unknown
function engine(files: Record<string, string>) {
  const hooks = new Map<string, Hook>()
  const on = ((event: string, a: unknown, b?: unknown) => {
    const h = (typeof a === 'function' ? a : b) as Hook
    if (!hooks.has(event)) hooks.set(event, h)
    return { catch: () => undefined }
  }) as unknown as Parameters<typeof register>[0]
  const state = new Map<string, unknown>()
  const store = new Map<string, unknown>()
  const panes = new Set<string>()
  const log: string[] = []
  const toasts: string[] = []
  const opened: string[] = []
  const goes: GoOut[] = []
  const answers: string[] = []
  const rel = (p: string) => p.replace(/^\/repo\//, '')
  const fire = async (event: string, e: Record<string, unknown>, base: (x: Record<string, unknown>) => unknown = x => x): Promise<unknown> => {
    const h = hooks.get(event)
    if (h === undefined) throw new Error(`no hook for ${event}`)
    const next = Object.assign(async (x: Record<string, unknown>) => base(x), { called: false })
    return h($, e, next)
  }
  const $ = {
    state: {
      get: async (r: { key: string }) => ({ value: state.get(r.key) }),
      set: async (r: { key: string }, v: unknown) => void state.set(r.key, v),
    },
    store: {
      get: async (k: string) => store.get(k),
      set: async (k: string, v: unknown) => {
        log.push(`store ${k}`)
        store.set(k, v)
      },
      delete: async (k: string) => void store.delete(k),
    },
    fs: {
      read: async (p: string) => {
        const text = rel(p) === '.temper/view.json' ? deriveView(x => files[x]) : files[rel(p)]
        if (text === null || text === undefined) throw new Error(`ENOENT: ${p}`)
        return text
      },
      stat: async () => ({ realPath: '/repo' }),
    },
    session: { version: async () => ({ version: '2.1.300', base: '2.1.300' }), id: async () => 'conv-1' },
    ui: {
      open: async ({ id }: { id: string }) => {
        panes.add(id)
        opened.push(id)
        return { isPlaced: true }
      },
      close: async ({ id }: { id: string }) => void panes.delete(id),
      panes: async () => [...panes].map(id => ({ id, title: id, isShown: true, isFocused: false, isPlaced: true })),
      toast: (t: string) => void toasts.push(t),
      log: () => undefined,
      // The engine's question dialog: an AskUserQuestion through the plugin's tool.call hook, answered by the person.
      ask: async (question: string, o: { options: string[]; header: string }) => {
        const questions = [{ question, header: o.header, multiSelect: false, options: o.options.map(label => ({ label, description: '' })) }]
        const answer = answers.shift() ?? ''
        await fire('tool.call', { tool: 'AskUserQuestion', questions }, x => {
          const qs = (x.questions as Array<{ question: string }>) ?? questions
          return { result: { questions: qs, answers: { [qs[0]!.question]: answer } }, text: answer }
        })
        log.push(`dialog closed: ${answer}`)
        return answer
      },
    },
    // The plugin's CLI: `temper go` answers from the list, every other call passes.
    process: {
      spawn: ({ argv }: { argv: string[] }) => {
        const out = argv.at(-1) === 'go' ? JSON.stringify(goes.shift() ?? { action: 'none', say: 'The run is done.' }) : ''
        if (argv.at(-1) !== 'go') log.push(`ran ${argv.slice(1).join(' ')}`)
        return { async *[Symbol.asyncIterator]() { yield { text: out } }, result: Promise.resolve({ code: 0 }) }
      },
    },
  }
  const load = () => {
    hooks.clear()
    register(on, {})
  }
  return { load, fire, state, store, panes, toasts, opened, log, goes, answers, files }
}

const at = (files: Record<string, string>, next: string) => {
  const d = JSON.parse(files['.temper/build-state.json'] ?? '{}') as Record<string, unknown>
  files['.temper/build-state.json'] = JSON.stringify({ ...d, next_stage: next })
}

describe('C1: what the mod knows outlives a reload of the module', () => {
  test('a pane the person closed is not opened again by the session start that follows a reload', async () => {
    const x = engine(runFiles({ nextStage: 'build' }))
    x.load()
    await x.fire('session.start', START)
    expect(x.opened).toEqual(['temper'])
    await x.fire('ui.close', { id: 'temper', origin: { kind: 'person' } }, e => void x.panes.delete(String(e.id)))
    x.load()
    await x.fire('session.start', START)
    expect(x.opened).toEqual(['temper'])
  })

  test('the pane open before a reload is open after it: /temper:temper pane closes it (the engine keeps the record)', async () => {
    const x = engine(runFiles({ nextStage: 'build' }))
    x.load()
    await x.fire('session.start', START)
    x.load()
    const r = (await x.fire('command.run', { command: 'temper', args: 'pane' })) as { text?: string }
    expect(r.text).toBe('The Temper pane is closed.')
    expect(x.panes.size).toBe(0)
  })

  test('a run that reaches Done across a reload still keeps its report, and the stage change still toasts', async () => {
    const x = engine(runFiles({ nextStage: 'check', gates: { intent: 'PASS', plan: 'PASS', build: 'PASS', review: 'PASS', check: 'PASS' } }))
    x.load()
    await x.fire('session.start', START)
    expect(x.toasts).toEqual([])
    x.load()
    at(x.files, 'commit')
    await x.fire('session.start', START)
    expect(x.toasts).toEqual([stageToast('commit')])
    expect(x.store.has('vf:/repo/.temper/report.md')).toBe(true)
  })

  test('a new session (no state yet) still toasts nothing at its first load', async () => {
    const x = engine(runFiles({ nextStage: 'build' }))
    x.load()
    await x.fire('session.start', START)
    expect(x.toasts).toEqual([])
  })
})

describe('C3, C4: a run is held through a lost view.json at every stage, the CLI saying there is none ends it', () => {
  test('at Commit, a view.json that turns missing keeps the run guarded: no commit around the native hook', async ($, on) => {
    const api = $ as unknown as Api
    const w = world(on, { ...runFiles({ nextStage: 'commit', gates: { intent: 'PASS', plan: 'PASS', build: 'PASS', review: 'PASS', check: 'PASS' } }), '/repo/.git/HEAD': 'ref: refs/heads/main\n' }, { fakeCli: true, projectRoot: '/repo' })
    await api.session.start(START)
    w.files.delete('.temper/build-state.json')
    expect(await sh(api, 'git commit --no-verify -m x')).toMatch(/--no-verify/)
  })

  test('a held run is shown with the line that says so, and its report is not kept', async ($, on) => {
    const api = $ as unknown as Api
    const w = world(on, runFiles({ nextStage: 'build' }), { fakeCli: true, projectRoot: '/repo' })
    await api.session.start(START)
    w.files.delete('.temper/build-state.json')
    const r = await api.command.run({ command: 'temper', args: 'report', origin: { kind: 'composer' } })
    expect(r.text).toMatch(/^Temper state: \.temper\/view\.json is missing or unreadable/)
    expect(Object.keys(w.store).filter(k => k.startsWith('vf:'))).toEqual([])
  })

  test('a view of another version is no run to hold: it fails open, as its line says', async ($, on) => {
    const api = $ as unknown as Api
    const w = world(on, runFiles({ nextStage: 'build' }), { fakeCli: true, projectRoot: '/repo' })
    await api.session.start(START)
    w.files.set('.temper/view.json', JSON.stringify({ version: 999, run: null }))
    expect(await sh(api, 'git commit --no-verify -m x')).toBeUndefined()
  })
})

const snap = (o: Partial<Snapshot>): Snapshot => ({ ...idleSnapshot({}, false), ...o })
const facts = (stage: RunFacts['stage'], o: Partial<RunFacts> = {}): RunFacts => ({ stage, step: 3, specDir: SPEC, planFiles: ['src/app.ts'], groupedActive: false, trivialExit: false, ...o })

describe('C5: one question decides whether the guard acts', () => {
  const run = facts('build')
  test('enforces: not inert, enforcement on, a view it reads', () => {
    expect(enforces(snap({}))).toBe(true)
    expect(enforces(snap({ inert: true }))).toBe(false)
    expect(enforces(snap({ enforcement: 'off' }))).toBe(false)
    expect(enforces(snap({ failOpen: true }))).toBe(false)
  })
  test('guardsRun: enforced, with a /temper run in progress (a fix run has none)', () => {
    expect(guardsRun(snap({ run }))).toBe(true)
    expect(guardsRun(snap({ run: null, slug: 'pw', runCommand: 'fix' }))).toBe(false)
    expect(guardsRun(snap({ run, enforcement: 'off' }))).toBe(false)
  })
})

// A port that plays the engine for the driver core.
function port(goes: GoOut[], o: { ran?: (call: string) => { code: number; out?: string }; answer?: (q: GoQuestion) => string | null; stopAfter?: (log: string[]) => boolean } = {}) {
  const log: string[] = []
  const p: Port = {
    run: async call => {
      log.push(call)
      if (call.endsWith(' go')) return { code: 0, out: JSON.stringify(goes.shift() ?? { action: 'none', say: 'done' }) }
      const r = o.ran?.(call) ?? { code: 0 }
      return { code: r.code, out: r.out ?? '' }
    },
    spawn: async () => 'ag1',
    wait: async ids => Object.fromEntries(ids.map(id => [id, { text: 'done', ms: 1 }])),
    ask: async q => {
      log.push(`ask ${q.question}`)
      return o.answer ? o.answer(q) : (q.options[0]?.label ?? null)
    },
    record: async () => undefined,
    show: async () => undefined,
    stopped: () => o.stopAfter?.(log) ?? false,
  }
  return { p, log }
}
const ask = (calls: string[]): GoOut => ({ action: 'ask', stage: 'plan', ask: { question: { header: 'Temper gate', question: 'Approve?', options: [{ label: 'Approve' }] }, options: [{ label: 'Approve', calls }] } })

describe('C6: the person\'s interrupt ends the drive STOPPED, whichever step saw it', () => {
  test('an answer\'s call the interrupt aborted (exit 130) is no failed call to hand on', async () => {
    let stopped = false
    const { p } = port([ask([`${CLI} state advance plan_complete build`])], {
      ran: () => {
        stopped = true
        return { code: 130 }
      },
      stopAfter: () => stopped,
    })
    expect(await drive(p, CLI, null)).toEqual({ kind: 'done', text: STOPPED })
  })

  test('a dialog the interrupt closed is not "nobody answered"', async () => {
    let stopped = false
    const { p, log } = port([ask([`${CLI} state advance plan_complete build`])], {
      answer: () => {
        stopped = true
        return null
      },
      stopAfter: () => stopped,
    })
    expect(await drive(p, CLI, null)).toEqual({ kind: 'done', text: STOPPED })
    expect(log.filter(l => l.includes('state advance'))).toEqual([])
  })

  test('temper go read at the interrupt (no action) is not "temper go gave no action"', async () => {
    let stopped = false
    const { p } = port([], { stopAfter: () => stopped })
    p.run = async () => {
      stopped = true
      return { code: 130, out: '' }
    }
    expect(await drive(p, CLI, null)).toEqual({ kind: 'done', text: STOPPED })
  })
})

describe('C7: every look of a wait counts toward its bound', () => {
  test('the same after calls asked for again changed nothing: they run once, and the run is handed on', async () => {
    const after = [`${CLI} task gate 3 --model opus --ms {ms}`]
    const wait: GoOut = { action: 'wait', stage: 'build', tasks: [{ after }] }
    const { p, log } = port([wait, wait, wait, wait])
    const end = await drive(p, CLI, null)
    expect(end).toEqual({ kind: 'handback', args: 'next', why: 'the after calls of the waiting tasks changed nothing' })
    expect(log.filter(l => l.includes('task gate 3'))).toEqual([`${CLI} task gate 3 --model opus --ms none`])
  })

  test('a wait whose after calls change every time is still bounded by the waits', async () => {
    const waits: GoOut[] = Array.from({ length: 200 }, (_, i) => ({ action: 'wait', stage: 'build', tasks: [{ after: [`${CLI} task gate ${i} --ms {ms}`] }] }))
    const { p, log } = port(waits)
    expect(await drive(p, CLI, null)).toEqual({ kind: 'handback', args: 'next', why: 'the run waited too long' })
    expect(log.filter(l => l.includes('task gate')).length).toBe(120)
  })
})

describe('C8: the driver\'s own dialog is recorded once, by the driver', () => {
  test('the dialog\'s hook keeps nothing of it; the driver records the answer after the dialog closed, before its calls run', async () => {
    const files = runFiles({ gates: { plan: 'PASS' } })
    const x = engine(files)
    const q = questionOf(deriveView(p => files[p]) ?? '')
    const label = q.options[0]!.label
    x.goes.push({ action: 'ask', stage: 'plan', ask: { question: { ...q, multiSelect: false }, options: q.options.map(o => ({ label: o.label, calls: o.label === label ? [`${CLI} state advance plan_complete build`] : [] })) } })
    x.answers.push(label)
    x.load()
    await x.fire('session.start', START)
    const r = (await x.fire('command.run', { command: 'temper', args: '', origin: { kind: 'composer' } })) as { text?: string }
    expect(r.text).toBe('The run is done.')
    const kept = x.log.filter(l => l === 'store dec:run-pw' || l.startsWith('dialog closed') || l.includes('state advance'))
    expect(kept).toEqual([`dialog closed: ${label}`, 'store dec:run-pw', expect.stringContaining('state advance plan_complete build')])
  })
})

describe('C9: an Allow once answer is spent once the write ran', () => {
  test('a write the tool failed leaves the answer for the next write', async ($, on) => {
    const api = $ as unknown as Api
    const w = world(on, runFiles({ nextStage: 'build' }), { fakeCli: true, projectRoot: '/repo', answers: ['Allow once'] })
    await api.session.start(START)
    await api.tool.call({ tool: 'AskUserQuestion', questions: [{ question: 'Outside the plan: src/once.ts\nWhy: a fix\nChange: one line', header: 'Scope drift', multiSelect: false, options: [{ label: 'Allow once', description: 'x' }] }] })
    w.toolErrors = 1
    expect(await agentWrite(api, 'src/once.ts')).toBeUndefined()
    expect(await agentWrite(api, 'src/once.ts')).toBeUndefined()
    expect(await agentWrite(api, 'src/once.ts')).toContain('scope drift')
  })
})

describe('C10: the window of a chosen skill ends when the run moves on, and leaves no entry behind', () => {
  const own = { tool: 'AskUserQuestion', questions: [{ question: 'Grill: what breaks first?', header: 'Grill Me', multiSelect: false, options: [{ label: 'The token', description: 'x' }, { label: 'The mail', description: 'y' }] }] }
  test('at the step it was chosen its questions pass; a step later they do not, and the entry is gone', async ($, on) => {
    const api = $ as unknown as Api
    const w = world(on, runFiles({ nextStage: 'plan' }), { fakeCli: true, projectRoot: '/repo', answers: ['The token'], store: { 'skill:/repo': { run: 'run-pw', step: 3 } } })
    await api.session.start(START)
    expect((await api.tool.call(own)).deny).toBeUndefined()
    const d = JSON.parse(w.files.get('.temper/build-state.json') ?? '{}') as Record<string, unknown>
    w.files.set('.temper/build-state.json', JSON.stringify({ ...d, step: 4 }))
    expect((await api.tool.call(own)).deny).toMatch(/ask only a question the CLI gives/)
    expect(Object.keys(w.store).filter(k => k.startsWith('skill:'))).toEqual([])
  })
})

describe('C11: the request kept at /temper:temper is used up by the state init that starts its run', () => {
  const REQ = 'Add partial refunds; more than the balance is a 409.'
  const init = (slug: string, feature: string) => `${CLI} state init ${slug} --feature '${feature}'`
  test('after that run, another state init is not held to the old request', async ($, on) => {
    const api = $ as unknown as Api
    world(on, {}, { fakeCli: true, projectRoot: '/repo' })
    await api.session.start(START)
    await api.command.run({ command: 'temper:temper', args: REQ, origin: { kind: 'composer' } })
    expect(await sh(api, init('pp', 'Partial refunds'))).toBe(FEATURE_DENY)
    expect(await sh(api, init('pp', REQ))).toBeUndefined()
    // The run never left Intent: the TRIVIAL exit clears it, and the next run starts from other words.
    expect(await sh(api, `${CLI} state clear`)).toBeUndefined()
    expect(await sh(api, init('other', 'Export invoices as CSV'))).toBeUndefined()
  })
})

describe('C12: the small change window is one rule, adhoc_ops.py\'s stages', () => {
  test('the stages are adhoc_ops.py STAGES', () => expect([...ADHOC_STAGES]).toEqual(['build', 'review', 'check', 'commit', 'pipeline']))
  const ctx = (r: RunFacts): RuleContext => ({ run: r, allowed: [], restart: false, drift: { added: [], allowOnce: [] }, root: '/repo' })
  test('a window recorded at Plan opens nothing: the session still writes no file and runs no other program', () => {
    const r = facts('plan', { adhocStage: 'plan' })
    expect(adhocOpen(r)).toBe(false)
    expect(evaluateSession(ctx(r), factsOf(null, false), { tool: 'Write', input: { file_path: 'src/app.ts', content: 'x' } })).toEqual({ deny: SESSION_WRITE_DENY })
    expect('deny' in evaluateSession(ctx(r), factsOf(null, false), { tool: 'Bash', input: { command: 'npm install left-pad' } })).toBe(true)
  })
  test('a window at Build lets the session and the stage rule through, at Build only', () => {
    const r = facts('build', { adhocStage: 'build' })
    expect(adhocOpen(r)).toBe(true)
    expect(evaluateSession(ctx(r), factsOf(null, false), { tool: 'Write', input: { file_path: 'src/other.ts', content: 'x' } })).toEqual({ allow: true })
    expect(evaluate(ctx(r), { tool: 'Write', input: { file_path: 'lib/other.ts', content: 'x' } })).toEqual({ allow: true })
    expect(adhocOpen(facts('review', { adhocStage: 'build' }))).toBe(false)
  })
})

describe('C13: the TRIVIAL exit is one rule', () => {
  test('the flag counts at Intent before any step only', () => {
    expect(trivialExit(facts('intent', { trivialExit: true, step: 0 }))).toBe(true)
    expect(trivialExit(facts('intent', { trivialExit: true, step: 2 }))).toBe(false)
    expect(trivialExit(facts('plan', { trivialExit: true, step: 0 }))).toBe(false)
    expect(trivialExit(facts('intent', { trivialExit: false, step: 0 }))).toBe(false)
    expect(trivialExit(null)).toBe(false)
  })
})

describe('C14: in a /temper:fix run only the person lifts the regression test shield', () => {
  const fix: RuleContext = { run: null, allowed: [], restart: false, drift: { added: [], allowOnce: [] }, fixRun: true, root: '/repo', cli: CLI }
  const bash = (c: RuleContext, command: string) => evaluate(c, { tool: 'Bash', input: { command } })
  test('the lift is refused, for an agent and the session alike', () => {
    for (const v of ['""', "''", '" "']) expect('deny' in bash(fix, `${CLI} state set regression_test ${v}`)).toBe(true)
    expect('deny' in bash(fix, `${CLI} state set regression_test`)).toBe(true)
  })
  test('recording the test\'s path passes; outside a fix run nothing changes', () => {
    expect(bash(fix, `${CLI} state set regression_test tests/test_reset.py`)).toEqual({ allow: true })
    expect(bash({ ...fix, fixRun: false }, `${CLI} state set regression_test ""`)).toEqual({ allow: true })
  })
})

describe('C15: two reads of the run at once: the later one stands', () => {
  test('a slow read that began before the CLI moved does not take the run back to the stage it read', async ($, on) => {
    const api = $ as unknown as Api
    const w = world(on, runFiles({ nextStage: 'build' }), { fakeCli: true, projectRoot: '/repo' })
    await api.session.start(START)
    let release = () => undefined as void
    const gate = new Promise<void>(r => (release = r))
    let held = false
    w.viewRead = async text => {
      if (!held) {
        held = true
        await gate
      }
      return text
    }
    const tick = () => new Promise<void>(r => setTimeout(() => r(), 20))
    const a = api.tool.call({ tool: 'Bash', command: 'ls' })
    await tick()
    cliTo(w, 'review')
    const b = api.tool.call({ tool: 'Bash', command: 'ls' })
    await tick()
    release()
    await Promise.all([a, b])
    expect(w.toasts).toEqual([stageToast('review')])
  })
})

describe('C16: an agent whose status ended before its answer arrived is waited for', () => {
  const list = [{ id: 'ag1', status: 'completed' }]
  test('its answer recorded on a later look is the one the driver reads', () => {
    const ends = new Map<string, AgentEnd>()
    const unanswered: Record<string, number> = {}
    const out: Record<string, AgentEnd> = {}
    expect(lookAtAgents(['ag1'], ends, list, unanswered, out)).toBe(1)
    ends.set('ag1', { text: 'DRIFT src/extra.ts', ms: 5 })
    expect(lookAtAgents(['ag1'], ends, list, unanswered, out)).toBe(0)
    expect(out.ag1).toEqual({ text: 'DRIFT src/extra.ts', ms: 5 })
  })
  test('with no answer after the looks it is waited for, it is done with none', () => {
    const unanswered: Record<string, number> = {}
    const out: Record<string, AgentEnd> = {}
    for (let i = 0; i < ANSWER_LOOKS; i++) expect(lookAtAgents(['ag1'], new Map(), list, unanswered, out)).toBe(1)
    expect(lookAtAgents(['ag1'], new Map(), list, unanswered, out)).toBe(0)
    expect(out.ag1).toEqual({ text: '', ms: null })
  })
})
