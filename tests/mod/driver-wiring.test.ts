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
// `temper go`, and its first call of a drive with no request (WP11: --taken-up)
const isGo = (call: string) => /scripts\/temper go( --taken-up)?$/.test(call)

// The engine's side of the driver: `temper go` answers from a list; a state init writes the run state as the CLI does.
function engine(on: On, w: ReturnType<typeof world>, goes: unknown[], opts: { agentStatus?: string } = {}) {
  const ran: string[] = []
  const spawned: Array<{ subagent_type?: string; model?: string; prompt?: string }> = []
  on('process.spawn', async function* ($, e) {
    const argv = (e as { argv: string[] }).argv
    // The mod runs the CLI by its path with the call's words, no shell: the call as the CLI wrote it, quoted again.
    const call = argv.map(w => (/^[A-Za-z0-9_@%+=:,./-]+$/.test(w) ? w : `'${w.replace(/'/g, `'\\''`)}'`)).join(' ')
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
  on('agent.list', () => ({ value: spawned.map((s, i) => ({ id: `ag${i + 1}`, description: 'Temper', type: s.subagent_type ?? '', status: (opts.agentStatus ?? 'completed') as 'completed' })) as never }))
  on('clock.now', () => ({ value: Date.now() }))
  const logged: string[] = []
  on('ui.log', ($, e) => {
    logged.push((e as { text: string }).text)
    return { value: undefined }
  })
  return { ran, spawned, logged }
}

describe('the mod carries a /temper:temper run (the run driver)', () => {
  test('a request: state init with it whole, the agent asked for as the CLI names it; an agent that cannot start stops the run saved (WP16)', async ($, on) => {
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
    const r1 = (await api.command.run({ command: 'temper', args: 'Add refunds', origin: { kind: 'composer' } })) as { context?: string[] }
    expect(ran.some(c => /scripts\/temper state init refunds --feature 'Add refunds'$/.test(c))).toBe(true)
    expect(spawned.map(s => [s.subagent_type, s.model, s.prompt])).toEqual([['temper:temper-plan', 'opus', 'Follow plan.md exactly.']])
    // WP16: a saved stop, never a hand back: its text says what stopped and how the run is taken up
    void logged
    expect([String((r1 as { text?: string }).text ?? '').includes('temper:temper-plan'), String((r1 as { text?: string }).text ?? '').includes('/temper:temper')]).toEqual([true, true])
    expect((r1.context ?? []).some(n => n.startsWith('Temper hand back'))).toBe(false)
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
    // One answer, one decision: the dialog's own hook and the driver's record both see it (the pane listed it twice).
    const books = Object.entries(w.store).filter(([k]) => k.startsWith('dec:')).map(([, v]) => v as unknown[])
    expect(books.map(b => b.length)).toEqual([1])
  })

  test('Blocking questions come in one dialog through the mod, and each answer\'s call runs', async ($, on) => {
    const api = $ as unknown as Api
    const files = { ...runFiles({ gates: { plan: 'PASS' } }), '/repo/.git/HEAD': 'ref: refs/heads/feature/pw\n' }
    const w = world(on, files, { projectRoot: '/repo', answers: ['Admins only', 'Carry forward', '60 days'] })
    const q = questionOf(viewText(w) ?? '')
    const b = (n: number, text: string, labels: string[]) => ({ question: { header: `Question ${n}`, question: text, options: labels.map(l => ({ label: l, description: '' })) },
      question_ids: { id: 'intent.blocking', kind: 'blocking', options: labels.map((l, i) => (l === 'Carry forward' ? { id: 'carry', kind: 'carry' } : { id: `choice-${i + 1}` })) },
      answer: `X/scripts/temper intent answer '${text}' '{answer}'`, carry: `X/scripts/temper intent carry '${text}'` })
    const goes = [
      { action: 'ask', stage: 'plan', gate: 'X/scripts/temper gate plan', ask: { question: { ...q, multiSelect: false }, options: q.options.map(o => ({ label: o.label, calls: [] })) },
        blocking: [b(1, 'Who may refund?', ['Admins only', 'Everyone', 'Carry forward']), b(2, 'Partial refunds?', ['Yes', 'Carry forward']), b(3, 'A window?', ['60 days', 'Carry forward'])] },
      { action: 'none', say: 'The run is done.' },
    ]
    // The CLI lists the Blocking questions in the view (blocking_asks), the questions the guard lets a session ask.
    const v = JSON.parse(viewText(w) ?? '{}') as Record<string, unknown>
    w.files.set('.temper/view.json', JSON.stringify({ ...v, blocking_asks: goes[0]!.blocking!.map(x => ({ question: { ...x.question, multiSelect: false } })) }))
    const { ran } = engine(on, w, goes)
    await api.session.start(START)
    await api.command.run({ command: 'temper', args: '', origin: { kind: 'composer' } })
    expect(w.dialogs).toBe(1)
    expect(w.asked).toEqual(['Who may refund?', 'Partial refunds?', 'A window?'])
    expect(ran.filter(c => / intent (answer|carry) /.test(c))).toEqual([
      "X/scripts/temper intent answer 'Who may refund?' 'Admins only'", "X/scripts/temper intent carry 'Partial refunds?'", "X/scripts/temper intent answer 'A window?' '60 days'"])
  })

  test('a typed answer: the driver runs the question\'s typed calls with the person\'s words, and no option (WP16)', async ($, on) => {
    const api = $ as unknown as Api
    const files = { ...runFiles({ gates: { plan: 'PASS' } }), '/repo/.git/HEAD': 'ref: refs/heads/feature/pw\n' }
    const w = world(on, files, { projectRoot: '/repo', answers: ['make it admin only'] })
    const q = questionOf(viewText(w) ?? '')
    const typed = { calls: ["X/scripts/temper evidence add --stage plan --phase note --kind input --claim '{text}'", "X/scripts/temper state redo plan --reason '{text}'"], again: false }
    const goes = [{ action: 'ask', stage: 'plan', ask: { id: 'plan.approve', kind: 'gate', question: { ...q, multiSelect: false }, options: q.options.map(o => ({ label: o.label, calls: ['X/scripts/temper state advance plan_complete build'] })), typed } }]
    const { ran, logged } = engine(on, w, goes)
    await api.session.start(START)
    const r = (await api.command.run({ command: 'temper', args: '', origin: { kind: 'composer' } })) as { context?: string[] }
    void logged
    expect(ran).toContain("X/scripts/temper evidence add --stage plan --phase note --kind input --claim 'make it admin only'")
    expect(ran).toContain("X/scripts/temper state redo plan --reason 'make it admin only'")
    expect((r.context ?? []).some(n => n.startsWith('Temper hand back'))).toBe(false)
    // The dialog itself shows what each option does: the descriptions the CLI gave, which `$.ui.ask` cannot carry.
    expect(w.askedDescriptions[0]).toEqual(q.options.map(o => (o.description ?? '').trim()))
    expect(w.askedDescriptions[0]!.every(d => d !== '')).toBe(true)
    expect(logged.some(l => l.includes('the choices:'))).toBe(false)
    expect(ran.filter(c => c.includes('state advance'))).toEqual([])
  })

  // WP16: a hand back is one step the person asked for by an option: the note after the command's text ends with
  // `step <kind> <option id>`, and the conversation does that one step, then the person types /temper:temper.
  test('a hand back note carries step, the kind and the option id (WP16)', async ($, on) => {
    const api = $ as unknown as Api
    // The passed Review question and its Teach Me option: its kind (talk) and its id (teach-me) differ, so the note
    // shows their order
    const files = { ...runFiles({ nextStage: 'review', gates: { intent: 'PASS', plan: 'PASS', build: 'PASS', review: 'PASS' } }), '/repo/.git/HEAD': 'ref: refs/heads/feature/pw\n' }
    const w = world(on, files, { projectRoot: '/repo', answers: ['Teach Me'] })
    const mq = questionOf(viewText(w) ?? '')
    expect(mq.options.map(o => o.label)).toContain('Teach Me')
    const goes = [{ action: 'ask', stage: 'review', ask: { id: 'review.pass', kind: 'gate', question: { ...mq, multiSelect: false }, options: mq.options.map(o => (o.label === 'Teach Me'
      ? { label: o.label, id: 'teach-me', needs: 'talk', do: 'Use the teach-me skill on this stage\'s work, then ask this question again.' }
      : { label: o.label, calls: [] })) } }]
    engine(on, w, goes)
    await api.session.start(START)
    const r = (await api.command.run({ command: 'temper', args: '', origin: { kind: 'composer' } })) as { context?: string[] }
    expect(w.asked).toEqual([mq.question])
    expect(r.context?.at(-1)).toMatch(/: step talk teach-me$/)
  })

  // WP16: /temper:fix typed with no words while a fix run is active is taken up by the driver, as /temper:temper is.
  test('/temper:fix with no words and a fix run active is driven (WP16)', async ($, on) => {
    const api = $ as unknown as Api
    const files = runFiles({ nextStage: 'fix', gates: { rca: 'PASS' } })
    const state = JSON.parse(files['.temper/build-state.json']!) as Record<string, unknown>
    files['.temper/build-state.json'] = JSON.stringify({ ...state, command: 'fix', next_stage: 'fix' })
    const w = world(on, { ...files, '/repo/.git/HEAD': 'ref: refs/heads/fix/pw\n' }, { projectRoot: '/repo' })
    const { ran } = engine(on, w, [{ action: 'none', say: 'The fix is committed.' }])
    await api.session.start(START)
    const r = await api.command.run({ command: 'temper:fix', args: '', origin: { kind: 'composer' } })
    expect(ran.filter(isGo).length).toBe(1)
    expect(r.text).toBe('The fix is committed.')
  })

  // P8 (WP28-1): /temper:fix has no words of its own, so a bug that starts with a word of /temper:temper that takes text
  // (draft, discuss, chose) is still a bug, and the driver carries its fix: the CLI's go, then the root cause agent's model.
  for (const args of ['draft emails are sent twice', 'discuss button does nothing', 'chose the wrong plan on upgrade']) {
    test(`/temper:fix ${args}: the bug is driven (P8)`, async ($, on) => {
      const api = $ as unknown as Api
      const w = world(on, {}, { projectRoot: '/repo' })
      const { ran } = engine(on, w, [{ action: 'none', say: 'No run is active.' }])
      await api.session.start(START)
      await api.command.run({ command: 'temper:fix', args, origin: { kind: 'composer' } })
      expect(ran.filter(isGo).length).toBe(1)
      expect(ran.some(c => /scripts\/temper model rca$/.test(c))).toBe(true)
    })
  }

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

// WP28: a first word is a word only in its documented form. A request that only starts with a word reaches the driver as
// a request and starts a run; a word in its form (draft with an idea, init, pack, pack enable guardrails) starts none and
// goes on to the prompt based command, which reads its page.
describe('w28 the words of /temper:temper and the driver', () => {
  test('w28 /temper:temper status badge on the order page reaches the driver as a request: state init with it whole', async ($, on) => {
    const api = $ as unknown as Api
    const w = world(on, {}, { projectRoot: '/repo' })
    const { ran } = engine(on, w, [{ action: 'none', say: 'No run is active.' }])
    await api.session.start(START)
    await api.command.run({ command: 'temper:temper', args: 'status badge on the order page', origin: { kind: 'composer' } })
    expect(ran.some(c => / state init \S+ --feature 'status badge on the order page'$/.test(c))).toBe(true)
  })

  for (const args of ['draft an idea', 'init', 'pack', 'pack enable guardrails']) {
    test(`w28 ${args}: no run is started, and the words go on to the prompt based command`, async ($, on) => {
      const api = $ as unknown as Api
      const w = world(on, {}, { projectRoot: '/repo' })
      const { ran } = engine(on, w, [])
      await api.session.start(START)
      await api.command.run({ command: 'temper:temper', args, origin: { kind: 'composer' } })
      expect(ran.filter(c => / state init /.test(c))).toEqual([])
      expect(w.commandRuns.map(c => c.args)).toEqual([args])
    })
  }
})
