// The run driver through the engine (9.8.0, round 5): the person's /temper:temper with a request, and the mod carries the
// run with `$.process.spawn`, `$.agent.spawn` and the question dialog; the person's answer is recorded as in the model loop.
import { describe, expect, test } from 'claude-code/testing'

import { optionCalls, questionOf, runFiles } from './run-files'
import { viewText, world } from './world'

const START = { cwd: '/repo', surface: 'terminal', isInteractive: true } as const
type Api = {
  session: { start: (a: unknown) => Promise<unknown> }
  command: { run: (a: unknown) => Promise<{ text?: string }> }
}
type On = Parameters<typeof world>[0]
const isGo = (call: string) => /scripts\/temper go$/.test(call)

// The engine's side of the driver: `temper go` answers from a list; a state init writes the run state as the CLI does.
function engine(on: On, w: ReturnType<typeof world>, goes: unknown[], opts: { agentStatus?: string } = {}) {
  const ran: string[] = []
  const spawned: Array<{ subagent_type?: string; model?: string; prompt?: string }> = []
  on('process.spawn', async function* ($, e) {
    const argv = (e as { argv: string[] }).argv
    const call = argv[0] === 'bash' && argv[1] === '-c' ? (argv[2] as string) : argv.join(' ')
    if (argv[0] === 'sleep') return { value: { code: 0, signal: null } }
    ran.push(call)
    if (isGo(call)) {
      yield { stream: 'stdout' as const, text: JSON.stringify(goes.shift() ?? { action: 'none', say: 'The run is done.' }) }
      return { value: { code: 0, signal: null } }
    }
    if (/ state init /.test(call)) {
      w.files.set('.temper/build-state.json', JSON.stringify({ spec: 'refunds', spec_path: '.temper/specs/refunds', command: 'temper', next_stage: 'intent', run_id: 'run-1', step: 0, run_mode: 'interactive' }))
    }
    return { value: { code: 0, signal: null } }
  })
  on('agent.spawn', ($, e) => {
    spawned.push(e as never)
    return { model: 'opus', agentId: `ag${spawned.length}` }
  })
  on('agent.list', () => ({ value: spawned.map((s, i) => ({ id: `ag${i + 1}`, description: 'Temper', type: s.subagent_type ?? '', status: opts.agentStatus ?? 'completed' })) }))
  on('clock.now', () => ({ value: Date.now() }))
  const logged: string[] = []
  on('ui.log', ($, e) => {
    logged.push((e as { text: string }).text)
    return { value: undefined }
  })
  return { ran, spawned, logged }
}

describe('the mod carries a /temper:temper run (the run driver)', () => {
  test('a request: state init with it whole, the agent asked for as the CLI names it; an agent that cannot start hands the run on', async ($, on) => {
    // The test kit pins a spawn's agent id to the engine, and nothing beneath it starts one: the spawn is asked for as
    // given, gets no id, and the run goes on in the conversation (a live run starts the agent and waits on it).
    const api = $ as unknown as Api
    const w = world(on, {}, { projectRoot: '/repo' })
    const goes = [
      { action: 'none', say: 'No run is active.' },
      { action: 'work', stage: 'plan', agents: [{ type: 'temper:temper-plan', model: 'opus', prompt: 'Follow plan.md exactly.', after: ['X/scripts/temper gate plan --brief'], gate: 'X/scripts/temper gate plan --brief' }] },
    ]
    const { ran, spawned, logged } = engine(on, w, goes)
    await api.session.start(START)
    await api.command.run({ command: 'temper', args: 'Add refunds', origin: { kind: 'composer' } })
    expect(ran.some(c => /scripts\/temper state init refunds --feature 'Add refunds'$/.test(c))).toBe(true)
    expect(spawned.map(s => [s.subagent_type, s.model, s.prompt])).toEqual([['temper:temper-plan', 'opus', 'Follow plan.md exactly.']])
    expect(logged).toEqual(['Temper: the run goes on in the conversation (the temper:temper-plan agent could not start).'])
    expect(w.commandRuns.map(c => c.args)).toEqual(['next'])
  })

  test('taken up again at the plan gate: the question of the view asked as given, the answer recorded, its calls run', async ($, on) => {
    const api = $ as unknown as Api
    const files = { ...runFiles({ gates: { plan: 'PASS' } }), '/repo/.git/HEAD': 'ref: refs/heads/feature/pw\n' }
    const w = world(on, files, { projectRoot: '/repo' })
    const q = questionOf(viewText(w) ?? '')
    const label = q.options[0]!.label
    w.answers.push(label)
    const calls = optionCalls('plan-pass', label)
    const goes = [
      { action: 'ask', stage: 'plan', ask: { question: { ...q, multiSelect: false }, options: q.options.map(o => ({ label: o.label, calls: o.label === label ? calls : [] })) } },
      { action: 'none', say: 'The run is done.' },
    ]
    const { ran } = engine(on, w, goes)
    await api.session.start(START)
    const r = await api.command.run({ command: 'temper', args: '', origin: { kind: 'composer' } })
    expect(r.text).toBe('The run is done.')
    expect(w.asked).toEqual([q.question])
    for (const c of calls) expect(ran).toContain(c)
    expect(Object.keys(w.store).some(k => k.startsWith('dec:'))).toBe(true)
  })

  test('a typed answer: the run goes on in the conversation with the person\'s words (discuss), nothing run', async ($, on) => {
    const api = $ as unknown as Api
    const files = { ...runFiles({ gates: { plan: 'PASS' } }), '/repo/.git/HEAD': 'ref: refs/heads/feature/pw\n' }
    const w = world(on, files, { projectRoot: '/repo', answers: ['make it admin only'] })
    const q = questionOf(viewText(w) ?? '')
    const goes = [{ action: 'ask', stage: 'plan', ask: { question: { ...q, multiSelect: false }, options: q.options.map(o => ({ label: o.label, calls: ['X/scripts/temper state advance plan_complete build'] })) } }]
    const { ran, logged } = engine(on, w, goes)
    await api.session.start(START)
    await api.command.run({ command: 'temper', args: '', origin: { kind: 'composer' } })
    expect([w.commandRuns.map(c => c.args), logged.at(-1)]).toEqual([['discuss make it admin only'], 'Temper: the run goes on in the conversation (the person typed an answer).'])
    // What the dialog cannot show, each option's description, was printed above the question.
    expect(logged[0]).toContain('Temper gate, the choices:\n  Stage by stage (Recommended): ')
    expect(ran.filter(c => c.includes('state advance'))).toEqual([])
  })

  test('a run word, and a request while another run is active, go to the model loop as before', async ($, on) => {
    const api = $ as unknown as Api
    const w = world(on, runFiles({ gates: { plan: 'PASS' } }), { projectRoot: '/repo' })
    const { ran } = engine(on, w, [])
    await api.session.start(START)
    await api.command.run({ command: 'temper', args: 'approve', origin: { kind: 'composer' } })
    await api.command.run({ command: 'temper', args: 'Add refunds', origin: { kind: 'composer' } })
    expect(w.commandRuns.map(c => c.args)).toEqual(['approve', 'Add refunds'])
    expect(ran).toEqual([])
  })
})
