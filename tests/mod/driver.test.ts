// The run driver (9.8.0, round 5): the mod carries a /temper:temper run with no model in the main session. Its core is
// pure; here a scripted port stands for the engine and a list of `temper go` answers for the CLI.
import { describe, expect, test } from 'claude-code/testing'
import { STOPPED, compactPanel, dialogQuestions, dialogQuestionsAll, drive, driverThrew, logRows, recordedVerdict, driveFix, fill, fixSlug, parseGo, rcaPrompt, shq, slugOf, stepPlan } from '../../hooks/temper-mod/core/driver'
import type { AgentEnd, DriveEnd, GoAgent, GoAsk, GoIds, GoOut, GoQuestion, Port } from '../../hooks/temper-mod/core/driver'
import { deriveView, runFiles } from './run-files'
import { world } from './world'

// WP09: recordedVerdict(call, out) is the rule of `recorded` in scripts/go.py: the verdict when the call is one of
// `gate <stage>`, `task gate <N>`, `group gate <G>` or `integrate` and the last line of its output that is a marker
// (`VERDICT: <scope> <PASS or FAIL or PARKED>`) names the call's scope; else none.

const CLI = '/p/scripts/temper'

type Script = {
  goes: GoOut[]
  answers?: Array<string | null>
  ends?: Record<string, AgentEnd>
  fail?: (call: string) => boolean
  out?: (call: string) => string
}

function port(s: Script & { stop?: number }) {
  const log = { ran: [] as string[], spawned: [] as GoAgent[], asked: [] as GoQuestion[], recorded: [] as string[], shown: [] as string[] }
  const answers = [...(s.answers ?? [])]
  let n = 0
  const p: Port = {
    run: async call => {
      log.ran.push(call)
      // `temper go` with its flags too (WP11: --taken-up on the first go of a drive with no request)
      if (call === `${CLI} go` || call.startsWith(`${CLI} go `)) {
        const g = s.goes.shift() ?? { action: 'none', say: 'No run is active.' }
        return { code: 0, out: JSON.stringify(g) }
      }
      return { code: s.fail?.(call) ? 1 : 0, out: s.out?.(call) ?? '' }
    },
    spawn: async a => {
      log.spawned.push(a)
      return `ag${++n}`
    },
    wait: async ids => Object.fromEntries(ids.map(id => [id, s.ends?.[id] ?? { text: 'done', ms: 1234 }])),
    ask: async q => {
      log.asked.push(q)
      return answers.length > 0 ? (answers.shift() as string | null) : null
    },
    record: async (q, label) => {
      log.recorded.push(`${q.question} -> ${label}`)
    },
    show: async text => {
      log.shown.push(text)
    },
    stopped: () => s.stop !== undefined && log.ran.length >= s.stop,
  }
  return { p, log }
}

const q = (question: string, labels: string[], header = 'Temper gate'): GoQuestion => ({ header, question, options: labels.map(label => ({ label, description: '' })) })
// The ids the CLI writes beside a reason, name or Blocking question (9.8.5): the driver selects by their kind, never by label.
const KINDS: Record<string, string> = { 'Carry forward': 'carry', Cancel: 'cancel', 'Type it below': 'type' }
const ids = (x: GoQuestion): GoIds => ({ options: x.options.map((o, i) => ({ id: KINDS[o.label] ?? `choice-${i + 1}`, ...(KINDS[o.label] ? { kind: KINDS[o.label] } : {}) })) })
const agent = (type: string, after: string[] = []): GoAgent => ({ type, model: 'opus', prompt: `Follow ${type}.`, after, gate: after.find(c => / gate /.test(c)) })

// WP16: the driver has two ends. A hand back carries the kind of the one step the conversation does (`needs`, one of
// the seven hand back kinds) and the id of the option the person picked (`option`); every other end is a saved stop
// (`done`) whose text says what stopped and that /temper:temper takes the run up. The CLI's new fields (`typed` on a
// question, `needs` on an option, `restart` beside `broken`) are given through `loose`, as the CLI writes them.
type End = { kind: string; needs?: unknown; option?: unknown; text?: unknown }
const endOf = (e: DriveEnd): End => e as unknown as End
const handedBack = (e: DriveEnd): string => {
  const x = endOf(e)
  return x.kind === 'handback' ? `${String(x.needs)} ${String(x.option)}` : `no hand back (${x.kind}: ${String(x.text ?? '')})`
}
// A saved stop: done, its text names /temper:temper, and it is not the interrupt's own text.
const savedStop = (e: DriveEnd): [string, boolean, boolean] => {
  const x = endOf(e)
  const text = typeof x.text === 'string' ? x.text : ''
  return [x.kind, text.includes('/temper:temper'), text !== STOPPED]
}
const SAVED: [string, boolean, boolean] = ['done', true, true]
const textOf = (e: DriveEnd): string => String(endOf(e).text ?? '')
const loose = <T>(x: unknown): T => x as T
// The seven hand back kinds, each with the id of an option of the head that carries it.
const SEVEN: Array<[string, string]> = [['talk', 'grill-me'], ['html-review', 'html-review'], ['depth-review', 'depth-review'],
  ['config-suggestions', 'config-suggestions'], ['small-change', 'small-change'], ['pull-request', 'commit-pr'], ['pipeline-fix', 'apply-fix']]

describe('the driver carries a run from the request to the end', () => {
  test('a new run: state init with the request whole, the agent launched as given, its after calls with its time, the gate answered', async () => {
    const plan = agent('temper:temper-plan', [`${CLI} usage add --stage plan --model opus --ms {ms}`, `${CLI} panel plan`, `${CLI} gate plan --brief`])
    const { p, log } = port({
      goes: [
        { action: 'none' },
        { action: 'work', stage: 'plan', say: 'Plan: the Plan agent is working.', agents: [plan] },
        { action: 'ask', stage: 'plan', ask: { question: q('Plan: the check passed. Approve the plan?', ['Approve (Recommended)', 'Save for later']), options: [{ label: 'Approve (Recommended)', calls: [`${CLI} state advance plan_complete build`] }, { label: 'Save for later', stop: true }] } },
        { action: 'none', say: 'The run is done.' },
      ],
      answers: ['Approve (Recommended)'],
      out: call => (call.endsWith('panel plan') ? '+----+\n| PLAN |\n+----+' : ''),
    })
    const end = await drive(p, CLI, "Refund an invoice's payment", 'refunds')
    expect(end).toEqual({ kind: 'done', text: 'The run is done.' })
    expect(log.ran).toContain(`${CLI} state init refunds --feature 'Refund an invoice'\\''s payment'`)
    expect(log.spawned.map(a => [a.type, a.model, a.prompt])).toEqual([['temper:temper-plan', 'opus', 'Follow temper:temper-plan.']])
    expect(log.ran).toContain(`${CLI} usage add --stage plan --model opus --ms 1234`)
    expect(log.shown).toContain('PLAN')   // the panel, as the compact rows the terminal draws
    expect(log.recorded).toEqual(['Plan: the check passed. Approve the plan? -> Approve (Recommended)'])
    expect(log.ran).toContain(`${CLI} state advance plan_complete build`)
  })

  test('Blocking questions: each answer is written by its call, Carry forward by its own', async () => {
    const { p, log } = port({
      goes: [{ action: 'ask', stage: 'intent', gate: `${CLI} gate intent`, ask: { question: q('Intent: answer the questions?', ['Continue']), options: [] }, blocking: [
        { question: q('Who may refund?', ['Admins only (Recommended)', 'Everyone', 'Carry forward'], 'Question 1'), question_ids: ids(q('Who may refund?', ['Admins only (Recommended)', 'Everyone', 'Carry forward'], 'Question 1')), answer: `${CLI} intent answer 'Who may refund?' '{answer}'`, carry: `${CLI} intent carry 'Who may refund?'` },
        { question: q('A window?', ['60 days', 'Carry forward'], 'Question 2'), question_ids: ids(q('A window?', ['60 days', 'Carry forward'], 'Question 2')), answer: `${CLI} intent answer 'A window?' '{answer}'`, carry: `${CLI} intent carry 'A window?'` },
      ] }],
      answers: ['Admins only (Recommended)', 'Carry forward'],
    })
    await drive(p, CLI, null)
    expect(log.ran).toContain(`${CLI} intent answer 'Who may refund?' 'Admins only (Recommended)'`)
    expect(log.ran).toContain(`${CLI} intent carry 'A window?'`)
    // Then the action's gate call reads the answers, before `temper go` asks again.
    expect(log.ran.slice(-2)).toEqual([`${CLI} gate intent`, `${CLI} go`])
  })

  test('Blocking questions come four to a dialog, as the loop without the mod asks them; each answer\'s call runs in order', async () => {
    const qs = [1, 2, 3, 4, 5].map(n => ({ question: q(`Rule ${n}?`, [`Yes ${n}`, 'Carry forward'], `Question ${n}`), question_ids: ids(q(`Rule ${n}?`, [`Yes ${n}`, 'Carry forward'])),
      answer: `${CLI} intent answer 'Rule ${n}?' '{answer}'`, carry: `${CLI} intent carry 'Rule ${n}?'` }))
    const dialogs: string[][] = []
    const { p, log } = port({ goes: [{ action: 'ask', stage: 'intent', gate: `${CLI} gate intent`, ask: { question: q('Intent?', ['Continue']), options: [] }, blocking: qs }] })
    p.askAll = async list => {
      dialogs.push(list.map(x => x.question))
      return list.map(x => (x.question === 'Rule 3?' ? 'Carry forward' : `Yes ${x.question.slice(5, 6)}`))
    }
    await drive(p, CLI, null)
    expect(dialogs).toEqual([['Rule 1?', 'Rule 2?', 'Rule 3?', 'Rule 4?'], ['Rule 5?']])
    expect(log.ran.filter(c => / intent (answer|carry) /.test(c))).toEqual([
      `${CLI} intent answer 'Rule 1?' 'Yes 1'`, `${CLI} intent answer 'Rule 2?' 'Yes 2'`, `${CLI} intent carry 'Rule 3?'`,
      `${CLI} intent answer 'Rule 4?' 'Yes 4'`, `${CLI} intent answer 'Rule 5?' 'Yes 5'`])
    expect(log.asked).toEqual([])
  })

  test('a dialog of several questions that nobody answers ends as a saved stop, with no answer call run (WP16)', async () => {
    const { p, log } = port({ goes: [{ action: 'ask', stage: 'intent', ask: { question: q('Intent?', ['Continue']), options: [] }, blocking: [
      { question: q('A?', ['x'], 'Question 1'), answer: `${CLI} intent answer 'A?' '{answer}'`, carry: `${CLI} intent carry 'A?'` },
      { question: q('B?', ['y'], 'Question 2'), answer: `${CLI} intent answer 'B?' '{answer}'`, carry: `${CLI} intent carry 'B?'` }] }] })
    p.askAll = async list => list.map(() => null)
    expect(savedStop(await drive(p, CLI, null))).toEqual(SAVED)
    expect(log.ran.filter(c => c.includes('intent answer'))).toEqual([])
  })

  test('a manual task\'s name question is asked by the driver: "Type it below" asks again, the typed name fills the call', async () => {
    const nameQ = { header: 'Manual task', question: 'Task 2: what name should the confirmation carry?', options: [{ label: 'Type it below', description: '' }, { label: 'Cancel', description: '' }] }
    const confirm = { label: 'Confirm', calls: [`${CLI} task confirm 2 --by '{answer}'`, `${CLI} task gate 2 --model person`], answer_question: nameQ, answer_ids: ids(nameQ) }
    const { p, log } = port({
      goes: [{ action: 'ask', stage: 'build', ask: { question: q('Task 2 is a manual task. Confirm?', ['Confirm', 'Stop']), options: [confirm, { label: 'Stop' }] } }, { action: 'none', say: 'end' }],
      answers: ['Confirm', 'Type it below', "Gal O'Neil"],
    })
    expect(await drive(p, CLI, null)).toEqual({ kind: 'done', text: 'end' })
    expect(log.asked.map(x => x.question)).toEqual(['Task 2 is a manual task. Confirm?', nameQ.question, nameQ.question])
    expect(log.ran).toContain(`${CLI} task confirm 2 --by 'Gal O'\\''Neil'`)
    expect(log.ran).toContain(`${CLI} task gate 2 --model person`)
  })

  test('Cancel at the name question asks the manual task question again, and nothing runs', async () => {
    const nameQ = { header: 'Manual task', question: 'Task 2: name?', options: [{ label: 'Type it below', description: '' }, { label: 'Cancel', description: '' }] }
    const confirm = { label: 'Confirm', calls: [`${CLI} task confirm 2 --by '{answer}'`], answer_question: nameQ, answer_ids: ids(nameQ) }
    const { p, log } = port({
      goes: [{ action: 'ask', stage: 'build', ask: { question: q('Confirm?', ['Confirm', 'Stop']), options: [confirm, { label: 'Stop', stop: true }] } }],
      answers: ['Confirm', 'Cancel', 'Stop'],
    })
    await drive(p, CLI, null)
    expect(log.asked.map(x => x.question)).toEqual(['Confirm?', 'Task 2: name?', 'Confirm?'])
    expect(log.ran.filter(c => c.includes('task confirm'))).toEqual([])
  })

  test('a typed answer at a question with no typed calls runs no option and hands nothing back (WP16)', async () => {
    const { p, log } = port({
      goes: [{ action: 'ask', ask: { question: q('Approve?', ['Approve', 'Loop back']), options: [{ label: 'Approve', calls: [`${CLI} state advance plan_complete build`] }, { label: 'Loop back' }] } }],
      answers: ['make the route admin only'],
    })
    expect(endOf(await drive(p, CLI, null)).kind).toBe('done')
    expect(log.ran.filter(c => c.includes('state advance'))).toEqual([])
    expect(log.recorded).toEqual([])
  })

  test('an option that needs a reason asks the reason question as given; Cancel asks the first question again', async () => {
    const rq = q('Loop back to Plan. What is the reason?', ['The plan cannot be built', 'Cancel'])
    const opts = { question: q('Group G1 is parked. Run the task again?', ['Loop back to Plan', 'Run the task again']), options: [
      { label: 'Loop back to Plan', calls: [`${CLI} state loop build plan --reason '{reason}'`], reason: true, reason_question: rq, reason_ids: ids(rq) },
      { label: 'Run the task again', calls: [`${CLI} group reopen G1 --task 2`] },
    ] }
    const { p, log } = port({ goes: [{ action: 'ask', ask: opts }, { action: 'none', say: 'end' }], answers: ['Loop back to Plan', 'Cancel', 'Loop back to Plan', 'The plan cannot be built'] })
    await drive(p, CLI, null)
    expect(log.asked.map(x => x.question)).toEqual([opts.question.question, rq.question, opts.question.question, rq.question])
    expect(log.ran).toContain(`${CLI} state loop build plan --reason 'The plan cannot be built'`)
    expect(log.recorded).toContain(`${rq.question} -> The plan cannot be built`)
  })

  test('More options asks the rest of the question; an option whose needs is talk (a skill) hands back its kind and id (WP16)', async () => {
    const more = loose<GoAsk>({ question: q('More choices?', ['Grill Me', 'Cancel']), options: [{ label: 'Grill Me', id: 'grill-me', needs: 'talk', do: 'Use the grill-me skill on this stage\'s work, then ask this question again.' }, { label: 'Cancel' }] })
    const { p, log } = port({ goes: [{ action: 'ask', ask: { question: q('Approve?', ['Approve', 'More options']), options: [{ label: 'Approve' }, loose({ label: 'More options', id: 'more', needs: 'more', do: 'Ask the more question.', kind: 'more' })], more } }], answers: ['More options', 'Grill Me'] })
    const end = await drive(p, CLI, null)
    expect(handedBack(end)).toBe('talk grill-me')
    expect(log.asked.map(x => x.question)).toEqual(['Approve?', 'More choices?'])
  })

  test('Save for later ends the drive and says the run is saved', async () => {
    const { p } = port({ goes: [{ action: 'ask', ask: { question: q('Approve?', ['Approve', 'Save for later']), options: [{ label: 'Approve' }, { label: 'Save for later', stop: true }] } }], answers: ['Save for later'] })
    const end = await drive(p, CLI, null)
    expect(end.kind).toBe('done')
    expect(end.kind === 'done' && end.text).toContain('saved')
  })

  test('an agent that lists DRIFT rows: its after calls run, and the run goes on to what the CLI gives next (WP16)', async () => {
    const b = agent('temper:temper-build-task', [`${CLI} task gate 1 --model haiku`])
    const { p, log } = port({ goes: [{ action: 'work', agents: [b] }, { action: 'none', say: 'end' }], ends: { ag1: { text: '+--- DRIFT (1) ---+\n| src/x.py: needed |', ms: 5 } } })
    const end = await drive(p, CLI, null)
    expect(end).toEqual({ kind: 'done', text: 'end' })
    expect(log.ran).toContain(`${CLI} task gate 1 --model haiku`)
  })

  test('a Build task agent: the CLI draws its panel after the gates, and only a stopped line of the agent is shown', async () => {
    const b = agent('temper:temper-build-task', [`${CLI} task gate 1 --model haiku --if-running`, `${CLI} task gate 2 --model haiku --if-running`, `${CLI} panel task 1 2`])
    const { p, log } = port({
      goes: [{ action: 'work', agents: [b] }, { action: 'none', say: 'end' }],
      ends: { ag1: { text: 'TASK 1: done\n  TASK 2: stopped: the RED run passed first; Task 1 built it', ms: 5 } },
      out: call => (call.endsWith('panel task 1 2') ? 'PANEL 1 2' : ''),
    })
    const end = await drive(p, CLI, null)
    expect(end).toEqual({ kind: 'done', text: 'end' })
    expect(log.ran.filter(c => / task gate | panel task /.test(c))).toEqual([`${CLI} task gate 1 --model haiku --if-running`, `${CLI} task gate 2 --model haiku --if-running`, `${CLI} panel task 1 2`])
    expect(log.shown).toEqual(['TASK 2: stopped: the RED run passed first; Task 1 built it', 'PANEL 1 2'])
  })

  test('a Build task agent that stopped before its gate: the failed verdict of the after gate is the CLI\'s, and the run goes on', async () => {
    const b = agent('temper:temper-build-task', [`${CLI} task gate 1 --model haiku --if-running`, `${CLI} task gate 2 --model haiku --if-running`, `${CLI} panel task 1 2`])
    const { p, log } = port({
      goes: [{ action: 'work', agents: [b] }, { action: 'none', say: 'end' }],
      ends: { ag1: { text: 'TASK 1: stopped: the Cases contradict each other', ms: 5 } },
      fail: call => / task gate 1 /.test(call),
      out: call => (/ task gate 1 /.test(call) ? 'FAIL: no green run for this task and attempt\nNEXT: park group G1\nVERDICT: task:1 FAIL' : ''),
    })
    const end = await drive(p, CLI, null)
    expect(end).toEqual({ kind: 'done', text: 'end' })
    expect(log.ran).toContain(`${CLI} panel task 1 2`)
  })

  test('every agent\'s before calls run before any agent starts; when one fails, the started agents are followed to their gates, then the run stops saved with the CLI\'s FAIL line (WP16)', async () => {
    const t = (n: number): GoAgent => ({ ...agent('temper:temper-build-task', [`${CLI} task gate ${n} --model haiku --if-running`]), before: [`${CLI} task start ${n}`] })
    const refused = 'FAIL: branch temper/x/T2 is left by an earlier attempt; delete it (git branch -D temper/x/T2), then run this again'
    const { p, log } = port({
      goes: [{ action: 'work', agents: [t(1), t(2), t(3)] }],
      fail: c => c.endsWith('task start 2'),
      out: c => (c.endsWith('task start 2') ? `Task 2\n${refused}\n` : ''),
    })
    const order: string[] = []
    const run0 = p.run
    const spawn0 = p.spawn
    p.run = async c => {
      order.push(c)
      return run0(c)
    }
    p.spawn = async a => {
      order.push(`spawn ${a.type}`)
      return spawn0(a)
    }
    const end = await drive(p, CLI, null)
    expect(savedStop(end)).toEqual(SAVED)
    expect(textOf(end)).toContain(refused)
    expect(order.filter(c => / task (start|gate) \d|^spawn /.test(c))).toEqual([
      `${CLI} task start 1`, `${CLI} task start 2`, 'spawn temper:temper-build-task', `${CLI} task gate 1 --model haiku --if-running`])
    expect(log.spawned.length).toBe(1)
  })

  test('when the first agent\'s before call fails, no agent starts and the run stops saved at once (WP16)', async () => {
    const t1: GoAgent = { ...agent('temper:temper-build-task', [`${CLI} task gate 1 --model haiku --if-running`]), before: [`${CLI} task start 1`] }
    const { p, log } = port({ goes: [{ action: 'work', agents: [t1] }], fail: c => c.endsWith('task start 1') })
    expect(savedStop(await drive(p, CLI, null))).toEqual(SAVED)
    expect(log.spawned).toEqual([])
    expect(log.ran.some(c => / task gate /.test(c))).toBe(false)
  })

  test('the report steps: CLI calls run and the report is shown as printed', async () => {
    const { p, log } = port({
      goes: [{ action: 'work', steps: [`${CLI} report --end`, 'Copy what temper report printed into your reply, as it printed it.'] }, { action: 'none', say: 'end' }],
      out: call => (call.endsWith('report --end') ? 'REPORT TEXT' : ''),
    })
    expect((await drive(p, CLI, null)).kind).toBe('done')
    expect(log.shown).toContain('REPORT TEXT')
  })

  test('steps where one needs the conversation (a pull request): none runs here, so none is left half done', async () => {
    const { p, log } = port({ goes: [{ action: 'work', steps: [`${CLI} state archive`, 'Follow /p/reference/pr.md, section One PR.', `${CLI} state clear`] }] })
    await drive(p, CLI, null)
    expect(log.ran).toEqual([`${CLI} go --taken-up`])
  })

  test('an option the conversation carries out (a skill): recorded, nothing of it run, handed on as its kind and id (WP16)', async () => {
    const { p, log } = port({ goes: [{ action: 'ask', ask: { question: q('Approve?', ['Approve', 'Grill Me']), options: [
      { label: 'Approve', calls: [`${CLI} state advance plan_complete build`] },
      loose({ label: 'Grill Me', id: 'grill-me', needs: 'talk', calls: [`${CLI} usage note grill`], do: 'Use the grill-me skill on this stage\'s work, then ask this question again.' })] } }], answers: ['Grill Me'] })
    expect(handedBack(await drive(p, CLI, null))).toBe('talk grill-me')
    expect(log.recorded).toEqual(['Approve? -> Grill Me'])
    expect(log.ran).toEqual([`${CLI} go --taken-up`])
  })

  test('a failed call, an error action and a gate that records FAIL: the two first are saved stops (WP16)', async () => {
    const g = agent('temper:temper-plan', [`${CLI} gate plan --brief`])
    const { p: p1 } = port({ goes: [{ action: 'work', agents: [g] }, { action: 'none', say: 'end' }], fail: c => c.includes('gate plan'), out: c => (c.includes('gate plan') ? 'temper gate plan -> FAIL\nVERDICT: gate:plan FAIL' : '') })
    expect((await drive(p1, CLI, null)).kind).toBe('done')
    const { p: p2 } = port({ goes: [{ action: 'error', say: 'temper next failed' }] })
    const e2 = await drive(p2, CLI, null)
    expect(savedStop(e2)).toEqual(SAVED)
    expect(textOf(e2)).toContain('temper next failed')
    const { p: p3 } = port({ goes: [{ action: 'ask', ask: { question: q('Approve?', ['Approve', 'No']), options: [{ label: 'Approve', calls: [`${CLI} state advance plan_complete build`] }, { label: 'No' }] } }], answers: ['Approve'], fail: c => c.includes('state advance'), out: c => (c.includes('state advance') ? 'FAIL: the plan changed since the question showed it' : '') })
    const e3 = await drive(p3, CLI, null)
    expect(savedStop(e3)).toEqual(SAVED)
    expect(textOf(e3)).toContain('FAIL: the plan changed since the question showed it')
  })

  test('a wait for tasks started in an earlier conversation runs their after calls now', async () => {
    const { p, log } = port({ goes: [{ action: 'wait', tasks: [{ after: [`${CLI} usage add --stage build --ms {ms} --task 2`, `${CLI} task gate 2`] }] }, { action: 'none', say: 'end' }] })
    expect((await drive(p, CLI, null)).kind).toBe('done')
    expect(log.ran).toContain(`${CLI} usage add --stage build --ms none --task 2`)
    expect(log.ran).toContain(`${CLI} task gate 2`)
  })

  test('nobody answers (a session with no one to ask): the run stops saved, and no conversation takes it on (WP16)', async () => {
    const { p } = port({ goes: [{ action: 'ask', ask: { question: q('Approve?', ['Approve', 'No']), options: [{ label: 'Approve' }, { label: 'No' }] } }], answers: [] })
    expect(savedStop(await drive(p, CLI, null))).toEqual(SAVED)
  })
})

describe('a call that printed its own marker recorded a verdict, whatever its exit code (WP09)', () => {
  const again = `${CLI} group gate G1 --timeout-s 1200`
  const twice = 'Run the check again with twice the time (Recommended)'
  const groupFailed = (): GoOut => ({ action: 'ask', stage: 'build', ask: {
    question: q('Group G1: the check failed. What now?', [twice, 'Save for later']),
    options: [{ label: twice, calls: [again] }, { label: 'Save for later', stop: true }] } })
  const integ = `${CLI} integrate`
  const gate = `${CLI} gate build --brief`
  const usage = `${CLI} usage add --stage build --model opus --ms {ms}`
  const fixPass = (): GoOut => ({ action: 'work', stage: 'build',
    agents: [agent('temper:temper-build', [usage, integ, gate])] })
  const gateOut = 'temper gate build -> FAIL\n  [x] integration\nVERDICT: gate:build FAIL'
  // WP16: an after call that failed with no marker of its own is a saved stop that shows the CLI's FAIL line
  const afterFailed = (e: DriveEnd, line: string): [string, boolean, boolean, boolean] => [...savedStop(e), textOf(e).includes(line)]
  const SAVED_WITH: [string, boolean, boolean, boolean] = ['done', true, true, true]

  test('a group gate of the person\'s answer that exits 1 with its marker does not hand back', async () => {
    const out = 'VERDICT: group:G1 FAIL\nFAIL: group G1 Validate failed (exit 1): make test'
    const { p, log } = port({ goes: [groupFailed(), { action: 'none', say: 'end' }], answers: [twice],
      fail: c => c === again, out: c => (c === again ? out : '') })
    expect(await drive(p, CLI, null)).toEqual({ kind: 'done', text: 'end' })
    expect(log.ran).toEqual([`${CLI} go --taken-up`, again, `${CLI} go`])
    expect(recordedVerdict(again, out) == null).toBe(false)
  })

  test('an after call integrate that exits 1 with its marker does not hand back; the gate after it runs', async () => {
    const out = 'VERDICT: integrate FAIL\nFAIL: integration suite failed (exit 1): make test'
    const { p, log } = port({ goes: [fixPass(), { action: 'none', say: 'end' }],
      fail: c => c === integ || c === gate, out: c => (c === integ ? out : c === gate ? gateOut : '') })
    expect(await drive(p, CLI, null)).toEqual({ kind: 'done', text: 'end' })
    expect(log.ran.slice(-3)).toEqual([integ, gate, `${CLI} go`])
    expect(recordedVerdict(integ, out) == null).toBe(false)
  })

  test('an after call that exits 1 with no marker stops the run saved, with its FAIL line (WP16)', async () => {
    const out = "FAIL: integrate runs on the run's feature branch 'feature/x' (current branch: 'main')"
    const { p, log } = port({ goes: [fixPass(), { action: 'none', say: 'end' }],
      fail: c => c === integ, out: c => (c === integ ? out : '') })
    expect(afterFailed(await drive(p, CLI, null), out)).toEqual(SAVED_WITH)
    expect(log.ran).not.toContain(gate)
    expect(recordedVerdict(integ, out) == null).toBe(true)
  })

  test('a marker of another scope is no verdict of the call: the run stops saved (WP16)', async () => {
    const other = 'VERDICT: group:G2 FAIL\nFAIL: group G1 Validate failed (exit 1): make test'
    const { p: p1 } = port({ goes: [groupFailed(), { action: 'none', say: 'end' }], answers: [twice],
      fail: c => c === again, out: c => (c === again ? other : '') })
    expect(afterFailed(await drive(p1, CLI, null), 'FAIL: group G1 Validate failed (exit 1): make test')).toEqual(SAVED_WITH)
    const { p: p2, log } = port({ goes: [fixPass(), { action: 'none', say: 'end' }],
      fail: c => c === integ, out: c => (c === integ ? 'VERDICT: gate:build FAIL' : '') })
    expect(savedStop(await drive(p2, CLI, null))).toEqual(SAVED)
    expect(log.ran).not.toContain(gate)
    expect(recordedVerdict(again, other) == null).toBe(true)
    expect(recordedVerdict(integ, 'VERDICT: gate:build FAIL') == null).toBe(true)
  })
})

// WP16: a run leaves the driver only for a step on the closed list of seven kinds, each one step the person asked for
// by an option. A typed answer, Cancel, a dialog nobody answered, a failed call, a bound, a scope drift and a broken run
// stay with the driver: each becomes the CLI's next question or a saved stop. One case per former cause.
describe('a run leaves the driver only for a hand back kind (WP16)', () => {
  const advance = `${CLI} state advance build_complete review`
  const note = (stage: string) => `${CLI} evidence add --stage ${stage} --phase note --kind input --claim '{text}'`
  const gateAsk = (stage: string, typed: { calls: string[]; again: boolean }): GoAsk => loose<GoAsk>({
    id: `${stage}.pass`, kind: 'gate',
    question: q(`${stage}: the check passed. Go on?`, ['Continue (Recommended)', 'Save for later']),
    options: [{ label: 'Continue (Recommended)', id: 'continue', move: 'advance', calls: [advance] }, { label: 'Save for later', id: 'save', move: 'pause', stop: true }],
    typed,
  })
  const TYPED = "make the route admin only, it's required"
  const QUOTED = "'make the route admin only, it'\\''s required'"

  test('a typed answer at a gate runs the typed calls: the driver fills {text}, runs them, and goes on; the end is never handback', async () => {
    const ask = gateAsk('build', { calls: [note('build'), `${CLI} state redo build --reason '{text}'`], again: false })
    const { p, log } = port({ goes: [{ action: 'ask', stage: 'build', ask }, { action: 'none', say: 'end' }], answers: [TYPED] })
    const end = await drive(p, CLI, null)
    expect(end).toEqual({ kind: 'done', text: 'end' })
    expect(log.ran).toEqual([`${CLI} go --taken-up`,
      `${CLI} evidence add --stage build --phase note --kind input --claim ${QUOTED}`, `${CLI} state redo build --reason ${QUOTED}`, `${CLI} go`])
  })

  test('a typed answer where the same question comes again (again): the note runs, and the question is asked again', async () => {
    const ask = gateAsk('review', { calls: [note('review')], again: true })
    const { p, log } = port({ goes: [{ action: 'ask', stage: 'review', ask }, { action: 'ask', stage: 'review', ask }, { action: 'none', say: 'end' }],
      answers: [TYPED, 'Continue (Recommended)'] })
    expect(await drive(p, CLI, null)).toEqual({ kind: 'done', text: 'end' })
    expect(log.asked.map(x => x.question)).toEqual(['review: the check passed. Go on?', 'review: the check passed. Go on?'])
    expect(log.ran).toContain(`${CLI} evidence add --stage review --phase note --kind input --claim ${QUOTED}`)
    expect(log.ran.filter(c => c === advance)).toEqual([advance])
  })

  test('Cancel at the accept question asks the gate question again', async () => {
    const accept = { id: 'review.pass.accept', kind: 'gate', question: q('Which open finding is kept as it is?', ['Accept finding 1', 'Cancel']),
      options: [{ label: 'Accept finding 1', id: 'choice-1', move: 'accept', calls: [`${CLI} evidence accept --stage review --id 1 --reason 'kept'`] },
        { label: 'Cancel', id: 'cancel', kind: 'cancel', needs: 'cancel', do: 'Ask the Review question again.' }] }
    const ask = loose<GoAsk>({ id: 'review.pass', kind: 'gate', question: q('Review: the check passed. Continue to Check?', ['Continue to Check (Recommended)', 'Accept a finding', 'Save for later']),
      options: [{ label: 'Continue to Check (Recommended)', id: 'continue', move: 'advance', calls: [`${CLI} state advance review_complete check`] },
        { label: 'Accept a finding', id: 'accept-finding', kind: 'accept', needs: 'accept', do: 'Ask the accept question.' },
        { label: 'Save for later', id: 'save', move: 'pause', stop: true }], accept })
    const { p, log } = port({ goes: [{ action: 'ask', stage: 'review', ask }, { action: 'none', say: 'end' }],
      answers: ['Accept a finding', 'Cancel', 'Continue to Check (Recommended)'] })
    expect(await drive(p, CLI, null)).toEqual({ kind: 'done', text: 'end' })
    expect(log.asked.map(x => x.question)).toEqual([ask.question.question, 'Which open finding is kept as it is?', ask.question.question])
    expect(log.ran).toContain(`${CLI} state advance review_complete check`)
    expect(log.ran.some(c => c.includes('evidence accept'))).toBe(false)
  })

  test('nobody answered ends as saved: a null answer at the gate, the reason, the name and a Blocking question each give done', async () => {
    const gate = port({ goes: [{ action: 'ask', ask: gateAsk('build', { calls: [note('build')], again: true }) }], answers: [] })
    const rq = q('Loop back to Plan. What is the reason?', ['The plan cannot be built', 'Cancel'])
    const reason = port({ goes: [{ action: 'ask', ask: { question: q('Group G1 is parked. What now?', ['Loop back to Plan', 'Save for later']), options: [
      { label: 'Loop back to Plan', calls: [`${CLI} state loop build plan --reason '{reason}'`], reason: true, reason_question: rq, reason_ids: ids(rq) }, { label: 'Save for later', stop: true }] } }],
      answers: ['Loop back to Plan', null] })
    const nameQ = { header: 'Manual task', question: 'Task 2: name?', options: [{ label: 'Type it below', description: '' }, { label: 'Cancel', description: '' }] }
    const name = port({ goes: [{ action: 'ask', ask: { question: q('Confirm?', ['Confirm', 'Stop']), options: [
      { label: 'Confirm', calls: [`${CLI} task confirm 2 --by '{answer}'`], answer_question: nameQ, answer_ids: ids(nameQ) }, { label: 'Stop', stop: true }] } }],
      answers: ['Confirm', null] })
    const blocking = port({ goes: [{ action: 'ask', stage: 'intent', ask: { question: q('Intent?', ['Continue']), options: [] }, blocking: [
      { question: q('Who may refund?', ['Admins', 'Carry forward'], 'Question 1'), answer: `${CLI} intent answer 'Who may refund?' '{answer}'`, carry: `${CLI} intent carry 'Who may refund?'` }] }] })
    blocking.p.askAll = async list => list.map(() => null)
    const ends = [await drive(gate.p, CLI, null), await drive(reason.p, CLI, null), await drive(name.p, CLI, null), await drive(blocking.p, CLI, null)]
    expect(ends.map(savedStop)).toEqual([SAVED, SAVED, SAVED, SAVED])
    expect([...reason.log.ran, ...name.log.ran, ...blocking.log.ran].filter(c => !/ go( --taken-up)?$/.test(c))).toEqual([])
  })

  test('a failed before call ends as saved with the CLI\'s FAIL line; the same for state init, a step and a Blocking answer call', async () => {
    const lines = {
      before: 'FAIL: branch temper/x/T1 is left by an earlier attempt; delete it, then run this again',
      init: 'FAIL: a run of refunds is active already',
      step: 'FAIL: git commit: the commit hook refused it',
      answer: "FAIL: intent.md has no open question 'Who may refund?'",
    }
    const t1: GoAgent = { ...agent('temper:temper-build-task', [`${CLI} task gate 1 --model haiku --if-running`]), before: [`${CLI} task start 1`] }
    const before = port({ goes: [{ action: 'work', agents: [t1] }], fail: c => c.endsWith('task start 1'), out: c => (c.endsWith('task start 1') ? `Task 1\n${lines.before}\n` : '') })
    const init = port({ goes: [{ action: 'none' }], fail: c => c.includes(' state init '), out: c => (c.includes(' state init ') ? lines.init : '') })
    const step = port({ goes: [{ action: 'work', steps: [`${CLI} spec commit 'feat: refunds'`] }], fail: c => c.includes('spec commit'), out: c => (c.includes('spec commit') ? lines.step : '') })
    const answer = port({ goes: [{ action: 'ask', stage: 'intent', ask: { question: q('Intent?', ['Continue']), options: [] }, blocking: [
      { question: q('Who may refund?', ['Admins', 'Carry forward'], 'Question 1'), answer: `${CLI} intent answer 'Who may refund?' '{answer}'`, carry: `${CLI} intent carry 'Who may refund?'` }] }],
      answers: ['Admins'], fail: c => c.includes('intent answer'), out: c => (c.includes('intent answer') ? lines.answer : '') })
    const ends = [await drive(before.p, CLI, null), await drive(init.p, CLI, 'Add refunds', 'refunds'), await drive(step.p, CLI, null), await drive(answer.p, CLI, null)]
    expect(ends.map(savedStop)).toEqual([SAVED, SAVED, SAVED, SAVED])
    expect(ends.map((e, i) => textOf(e).includes(Object.values(lines)[i]!))).toEqual([true, true, true, true])
    expect(before.log.spawned).toEqual([])
  })

  test('an agent that could not start ends as saved', async () => {
    const { p } = port({ goes: [{ action: 'work', agents: [agent('temper:temper-plan', [`${CLI} gate plan --brief`])] }] })
    p.spawn = async () => null
    const end = await drive(p, CLI, null)
    expect(savedStop(end)).toEqual(SAVED)
    expect(textOf(end)).toContain('temper:temper-plan')
  })

  test('a bound ends as saved with its reason: question depth, 120 waits, the same after calls, 300 turns', async () => {
    // a More question inside a More question, twelve deep: the driver goes no deeper than its bound
    let round: Record<string, unknown> | undefined
    for (let i = 0; i < 12; i++) round = { question: q(`Round ${i}?`, ['More options', 'Save for later']), options: [
      { label: 'More options', id: 'more', kind: 'more', needs: 'more', do: 'Ask the more question.' }, { label: 'Save for later', id: 'save', move: 'pause', stop: true }], more: round }
    const depth = port({ goes: [{ action: 'ask', ask: loose<GoAsk>(round) }], answers: Array<string>(12).fill('More options') })
    const waits = port({ goes: Array.from({ length: 125 }, (): GoOut => ({ action: 'wait' })) })
    const after = (): GoOut => ({ action: 'wait', tasks: [{ after: [`${CLI} task gate 2`] }] })
    const same = port({ goes: [after(), after(), after()] })
    const turns = port({ goes: Array.from({ length: 305 }, (): GoOut => ({ action: 'work' })) })
    const ends = [await drive(depth.p, CLI, null), await drive(waits.p, CLI, null), await drive(same.p, CLI, null), await drive(turns.p, CLI, null)]
    expect(ends.map(savedStop)).toEqual([SAVED, SAVED, SAVED, SAVED])
    // each bound says its own reason
    expect(new Set(ends.map(textOf)).size).toBe(4)
  })

  for (const [needs, id] of SEVEN) {
    test(`an option whose needs kind is on the list hands back that kind and the option id: ${needs}`, async () => {
      const ask = loose<GoAsk>({ id: 'check.pass', kind: 'gate', question: q('Check: the check passed. Commit?', ['Commit (Recommended)', `The ${needs} step`]),
        options: [{ label: 'Commit (Recommended)', id: 'commit', move: 'advance', calls: [`${CLI} state advance check_complete commit`] },
          { label: `The ${needs} step`, id, needs, do: 'The conversation does this one step, then the person types /temper:temper.' }] })
      const { p, log } = port({ goes: [{ action: 'ask', stage: 'check', ask }], answers: [`The ${needs} step`] })
      expect(handedBack(await drive(p, CLI, null))).toBe(`${needs} ${id}`)
      expect(log.ran.some(c => c.includes('state advance'))).toBe(false)
    })
  }

  test('a needs kind that is not on the list ends as saved, never a hand back; so does a do text with no needs', async () => {
    const ask = (o: Record<string, unknown>) => loose<GoAsk>({ id: 'build.pass', kind: 'gate', question: q('Build: the check passed. Go on?', ['Continue (Recommended)', 'Talk it through']),
      options: [{ label: 'Continue (Recommended)', id: 'continue', move: 'advance', calls: [advance] }, { label: 'Talk it through', ...o }] })
    const off = port({ goes: [{ action: 'ask', ask: ask({ id: 'choice-1', needs: 'discuss', do: 'Talk it through with the person.' }) }], answers: ['Talk it through'] })
    const bare = port({ goes: [{ action: 'ask', ask: ask({ id: 'choice-1', do: 'Talk it through with the person.' }) }], answers: ['Talk it through'] })
    expect([savedStop(await drive(off.p, CLI, null)), savedStop(await drive(bare.p, CLI, null))]).toEqual([SAVED, SAVED])
  })

  test('the Scope drift question is the CLI\'s: after an agent that lists DRIFT rows, the driver asks it as any question and runs the option\'s call', async () => {
    const b = agent('temper:temper-build', [`${CLI} gate build --brief`])
    const record = (choice: string) => `${CLI} evidence add --stage build --phase feedback --claim 'drift src/x.py: ${choice}: the parser needs it'`
    const drift = loose<GoAsk>({ id: 'scope.drift', kind: 'drift',
      question: q('Outside the plan: src/x.py\nWhy: the parser needs it\nChange: one helper', ['Add to plan', 'Revert', 'Allow once'], 'Scope drift'),
      options: [{ label: 'Add to plan', id: 'add-to-plan', move: 'drift', calls: [record('add')] },
        { label: 'Revert', id: 'revert', move: 'drift', calls: [record('revert')] }, { label: 'Allow once', id: 'allow-once', move: 'drift', calls: [record('allow-once')] }] })
    const { p, log } = port({ goes: [{ action: 'work', stage: 'build', agents: [b] }, { action: 'ask', stage: 'build', ask: drift }, { action: 'none', say: 'end' }],
      ends: { ag1: { text: '+--- DRIFT (1) ---+\n| src/x.py: the parser needs it |', ms: 5 } }, answers: ['Add to plan'] })
    expect(await drive(p, CLI, null)).toEqual({ kind: 'done', text: 'end' })
    expect(log.asked.map(x => x.header)).toEqual(['Scope drift'])
    expect(log.ran).toContain(record('add'))
  })

  test('broken asks the restart question: Start over runs its call, Cancel keeps the run and stops saved', async () => {
    const restart = { header: 'Temper resume', question: 'A run of pw is open at Build. Start over?', id: 'run.restart', kind: 'resume', multiSelect: false,
      options: [{ label: 'Start over', description: 'The saved run state goes; the spec files stay.', id: 'start-over', move: 'restart', calls: [`${CLI} state clear`] },
        { label: 'Cancel', description: 'Keep the run.', id: 'cancel', kind: 'cancel', move: null, calls: [] }] }
    const broken = loose<GoOut>({ action: 'broken', say: 'The run state cannot be read.', restart })
    const yes = port({ goes: [broken, { action: 'none', say: 'No run is active.' }], answers: ['Start over'] })
    const no = port({ goes: [loose<GoOut>({ ...broken })], answers: ['Cancel'] })
    const endYes = await drive(yes.p, CLI, null)
    const endNo = await drive(no.p, CLI, null)
    expect(yes.log.asked.map(x => [x.question, x.options.map(o => o.label).join('|')])).toEqual([[restart.question, 'Start over|Cancel']])
    expect(yes.log.ran).toContain(`${CLI} state clear`)
    expect(endOf(endYes).kind).toBe('done')
    expect(no.log.asked.map(x => x.question)).toEqual([restart.question])
    expect(no.log.ran).not.toContain(`${CLI} state clear`)
    expect(savedStop(endNo)).toEqual(SAVED)
  })
})

describe('the driver carries a /temper:fix run', () => {
  test('setup, the root cause agent with fix.md\'s prompt, the panel from rca.md, the run\'s state, the branch, then the loop', async () => {
    const { p, log } = port({
      goes: [
        { action: 'none', setup: [`bash /p/scripts/guards/install.sh`] },
        { action: 'ask', stage: 'rca', ask: { question: q('RCA: the root cause is in .temper/specs/totals/rca.md. Proceed to Fix?', ['Proceed to Fix (Recommended)', 'Save for later']),
          options: [{ label: 'Proceed to Fix (Recommended)', calls: [`${CLI} state advance rca_complete fix`] }, { label: 'Save for later', stop: true }] } },
        { action: 'none', say: 'The fix is committed.' },
      ],
      answers: ['Proceed to Fix (Recommended)'],
      out: call => (call.endsWith('model rca') ? 'claude-opus-5-5\n' : call.includes('panel rca') ? '| RCA: totals |' : ''),
    })
    const end = await driveFix(p, CLI, 'Totals drop a cent', 'totals')
    expect(end).toEqual({ kind: 'done', text: 'The fix is committed.' })
    expect(log.spawned.map(a => [a.type, a.model, a.prompt])).toEqual([['temper:temper-rca', 'claude-opus-5-5', rcaPrompt('/p', 'Totals drop a cent', 'totals')]])
    const at = (c: string) => log.ran.indexOf(c)
    expect(at(`bash /p/scripts/guards/install.sh`) < at(`${CLI} model rca`)).toBe(true)
    expect(at(`${CLI} panel rca .temper/specs/totals/rca.md`) < at(`${CLI} state init totals --command fix`)).toBe(true)
    expect(log.ran).toContain(`${CLI} usage add --stage rca --model claude-opus-5-5 --ms 1234`)
    expect(log.ran.some(c => c.includes("git checkout -q -b 'fix/totals'"))).toBe(true)
    expect(log.shown).toContain('| RCA: totals |')
    expect(log.ran).toContain(`${CLI} state advance rca_complete fix`)
  })
  test('a run already active: the fix command with a bug hands nothing back and starts no root cause agent (WP16)', async () => {
    const { p, log } = port({ goes: [{ action: 'ask', ask: { question: q('Approve?', ['Approve', 'No']), options: [] } }] })
    expect(endOf(await driveFix(p, CLI, 'a bug')).kind).toBe('done')
    expect(log.spawned).toEqual([])
  })
  test('the fix slug keeps a ticket key\'s case', () => {
    expect(fixSlug('JIRA-123 checkout answers 500')).toBe('JIRA-123-checkout-answers-500')
    expect(fixSlug('Totals drop a cent on export')).toBe('totals-drop-cent-export')
    expect(rcaPrompt('/p', 'x', 's')).toContain('RCA file: .temper/specs/s/rca.md')
  })
})

describe('the person interrupts', () => {
  test('the drive stops where it is, says how to take the run up again, and starts no model turn', async () => {
    const { p, log } = port({ goes: [{ action: 'work', steps: [`${CLI} report --end`] }, { action: 'none' }], stop: 1 })
    expect(await drive(p, CLI, null)).toEqual({ kind: 'done', text: STOPPED })
    expect(log.ran).toEqual([`${CLI} go --taken-up`])
  })
})

describe('a throw out of the driver', () => {
  test('at the interrupt it is the stop, with no hand back; otherwise a saved stop with the reason (WP16)', () => {
    expect(driverThrew(new Error('$.process.spawn(bash) aborted'), true)).toEqual({ kind: 'done', text: STOPPED })
    const end = driverThrew(new Error('boom'), false)
    expect(savedStop(end)).toEqual(SAVED)
    expect(textOf(end)).toContain('boom')
  })
})

describe('what the driver shows, as the rows the terminal draws', () => {
  test('a CLI panel is a few rows: the title, a row a fact, a row a section, and where the diagram is', () => {
    const W = 76
    const rule = '+' + '-'.repeat(W - 2) + '+'
    const row = (t: string) => '| ' + t.padEnd(W - 4) + ' |'
    const head = (n: string) => { const h = `+--- ${n} ---+`; return h + '-'.repeat(W - h.length - 1) + '+' }
    const plan = [rule, row('PLAN: List N jokes'), rule, row('INTENT: one joke a call -> 4 criteria'), row('ARCHITECTURE: create 1 files   RISK: L'),
      head('SCENARIOS (2)'), row('[Happy Path] N jokes, Covers: AC-01'), row('[Edge Cases] more than there are,'), row('  Covers: AC-02'),
      head('DECISIONS (1)'), row('argparse type= function'), rule, '+-----+  bad N  +-----+', '| cli | ------> | err |', '+-----+         +-----+'].join('\n')
    expect(compactPanel(plan)).toEqual([
      'PLAN: List N jokes',
      'INTENT: one joke a call -> 4 criteria',
      'ARCHITECTURE: create 1 files · RISK: L',
      'SCENARIOS (2): [Happy Path] N jokes, Covers: AC-01 · [Edge Cases] more than there are, Covers: AC-02',
      'DECISIONS (1): argparse type= function',
      "The plan's diagram is in plan.md, under Diagram.",
    ])
  })

  test('a title that wraps stays whole; a box with one fact row joins it to the title; two boxes stay two', () => {
    const W = 76
    const rule = '+' + '-'.repeat(W - 2) + '+'
    const row = (t: string) => '| ' + t.padEnd(W - 4) + ' |'
    const head = (n: string) => { const h = `+--- ${n} ---+`; return h + '-'.repeat(W - h.length - 1) + '+' }
    const task = (n: number) => [rule, row(`TASK ${n}: the title`), rule, row('Attempt: 1   Test: red exit 1, green exit 0   Gate: PASS'), head('CHANGED (1)'), row(`src/t${n}.py`), rule]
    expect(compactPanel([...task(1), ...task(2)].join('\n'))).toEqual([
      'TASK 1: the title. Attempt: 1 · Test: red exit 1, green exit 0 · Gate: PASS', 'CHANGED (1): src/t1.py',
      'TASK 2: the title. Attempt: 1 · Test: red exit 1, green exit 0 · Gate: PASS', 'CHANGED (1): src/t2.py',
    ])
    expect(compactPanel([rule, row('RCA: a total differs between the app and the export,'), row('  the credit notes and the payments'), rule,
      row('CAUSE: one formula too many'), row('AT: a.py:17'), rule].join('\n'))[0]).toBe('RCA: a total differs between the app and the export, the credit notes and the payments')
    expect(compactPanel('no box at all\nsecond line')).toEqual(['no box at all', 'second line'])
  })

  test('a panel is one row a line, a blank line stays a row, trailing blanks go, and a long line is cut in rows of 2000', () => {
    expect(logRows('+--+\n| a |\n+--+\n\n')).toEqual(['+--+', '| a |', '+--+'])
    expect(logRows('Report\n\nNext: commit\r\nDone')).toEqual(['Report', ' ', 'Next: commit', 'Done'])
    const long = 'x'.repeat(4500)
    expect(logRows(long).map(r => r.length)).toEqual([2000, 2000, 500])
  })
})

describe('the dialog of the driver\'s question', () => {
  test('several questions: the first one raised becomes the whole dialog, each with its descriptions', () => {
    const a = { header: 'Question 1', question: 'Who?', options: [{ label: 'Admins', description: 'Recommended' }, { label: 'Carry forward', description: ' Later. ' }] }
    const b = { header: 'Question 2', question: 'When?', options: [{ label: '60 days', description: '' }] }
    expect(dialogQuestionsAll([{ question: 'Who?', header: 'Question 1', options: [] }], [a, b])).toEqual([
      { question: 'Who?', header: 'Question 1', multiSelect: false, options: [{ label: 'Admins', description: 'Recommended' }, { label: 'Carry forward', description: 'Later.' }] },
      { question: 'When?', header: 'Question 2', multiSelect: false, options: [{ label: '60 days', description: '' }] },
    ])
    expect(dialogQuestionsAll([{ question: 'Other?' }], [a, b])).toBe(null)
    expect(dialogQuestionsAll([{ question: 'Who?' }, { question: 'x' }], [a, b])).toBe(null)
  })

  const q = { header: 'Temper gate', question: 'Plan: approve?', options: [
    { label: 'Approve (Recommended)', description: 'Go on to Design.', preview: '| a | b |' },
    { label: 'Save for later', description: ' Stop here. ' }] }
  const raised = [{ question: 'Plan: approve?', header: 'Temper gate', multiSelect: false,
    options: [{ label: 'Approve (Recommended)', description: '' }, { label: 'Save for later', description: '' }] }]

  test('each option gets its description and its preview back from the CLI\'s question', () => {
    expect(dialogQuestions(raised, q)).toEqual([{ question: 'Plan: approve?', header: 'Temper gate', multiSelect: false, options: [
      { label: 'Approve (Recommended)', description: 'Go on to Design.', preview: '| a | b |' },
      { label: 'Save for later', description: 'Stop here.' }] }])
  })

  test('an option with no description keeps what it had, and a call that is not this question is passed on as it is', () => {
    const bare = { header: 'Question 1', question: 'Who?', options: [{ label: 'Admins' }, { label: 'Carry forward', description: '' }] }
    const who = [{ question: 'Who?', options: [{ label: 'Admins', description: '' }, { label: 'Carry forward', description: '' }] }]
    expect(dialogQuestions(who, bare)).toEqual(who)
    expect(dialogQuestions([{ ...raised[0], question: 'Another?' }], q)).toBe(null)
    expect(dialogQuestions([{ ...raised[0], options: [{ label: 'Save for later' }, { label: 'Approve (Recommended)' }] }], q)).toBe(null)
    expect(dialogQuestions([...raised, ...raised], q)).toBe(null)
    expect(dialogQuestions('not a list', q)).toBe(null)
  })
})

describe('the driver\'s small parts', () => {
  test('parseGo reads the last JSON line; slugOf makes a slug from the request', () => {
    expect(parseGo('noise\n{"action":"none","say":"x"}\n')?.action).toBe('none')
    expect(parseGo('not json')).toBe(null)
    expect(slugOf('Add partial refunds to invoices: `POST /invoices/{id}/refunds`')).toBe('partial-refunds-invoices')
    expect(slugOf('!!!')).toBe('feature')
  })
  test('quoting: a request with a quote is one shell word; a filled placeholder keeps its quotes', () => {
    expect(shq("it's")).toBe("'it'\\''s'")
    expect(fill("x --reason '{reason}'", { reason: "it's" })).toBe("x --reason 'it'\\''s'")
  })
  test('step plans', () => {
    expect(stepPlan(`${CLI} spec commit 'x'`, CLI)).toEqual({ kind: 'run', call: `${CLI} spec commit 'x'` })
    expect(stepPlan(`${CLI} spec commit '{message}'`, CLI).kind).toBe('handback')
    expect(stepPlan('git push', CLI).kind).toBe('handback')
  })
})

// WP11: a run taken up again. A drive with no request (/temper:temper typed with no words) passes --taken-up on its first
// `temper go`, so the CLI records the stop of an unattended run and its stage asks its question once; never again in
// that drive, and never in a drive that starts a run from a request.
const goes = (ran: string[]): string[] => ran.filter(c => c === `${CLI} go` || c.startsWith(`${CLI} go `))
describe('a run taken up again (WP11)', () => {
  test('a drive with no request passes --taken-up on its first go and never again', async () => {
    const ask = { question: q('Build: the check passed. Continue to Review?', ['Continue to Review (Recommended)', 'Save for later']),
      options: [{ label: 'Continue to Review (Recommended)', calls: [`${CLI} state advance build_complete review`] }, { label: 'Save for later', stop: true }] }
    const { p, log } = port({ goes: [{ action: 'ask', stage: 'build', ask }, { action: 'none', say: 'end' }], answers: ['Continue to Review (Recommended)'] })
    expect(await drive(p, CLI, null)).toEqual({ kind: 'done', text: 'end' })
    expect(goes(log.ran)).toEqual([`${CLI} go --taken-up`, `${CLI} go`])
  })

  test('a drive that starts a run from a request never passes --taken-up', async () => {
    const { p, log } = port({ goes: [{ action: 'none' }, { action: 'none', say: 'end' }] })
    expect(await drive(p, CLI, 'Refund an invoice', 'refunds')).toEqual({ kind: 'done', text: 'end' })
    expect(goes(log.ran)).toEqual([`${CLI} go`, `${CLI} go`])
  })
})

// WP11: the notice of a stop. The mod toasts once when run.parked of the view turns from null to a stage (the stage
// itself does not change, so no stage toast is due), through the one toast call of the mod.
describe('a stop of an unattended run is toasted once (WP11)', () => {
  type Api = { session: { start: (a: unknown) => Promise<unknown> }; tool: { call: (a: unknown) => Promise<unknown> } }
  const START = { cwd: '/repo', surface: 'terminal', isInteractive: true } as const
  test('a view whose run.parked turns from null to a stage gives one toast', async ($, on) => {
    const api = $ as unknown as Api
    const w = world(on, runFiles({ nextStage: 'build', gates: { intent: 'PASS', plan: 'PASS' } }), { fakeCli: true, projectRoot: '/repo' })
    await api.session.start(START)
    await api.tool.call({ tool: 'Bash', command: 'ls' })
    const before = w.toasts.length
    const v = JSON.parse(deriveView(path => w.files.get(path)) ?? '{}') as { run: Record<string, unknown> }
    expect(v.run.parked ?? null).toBe(null)
    w.files.set('.temper/view.json', JSON.stringify({ ...v, run: { ...v.run, parked: 'build' } }))
    await api.tool.call({ tool: 'Bash', command: 'ls' })
    expect(w.toasts.length).toBe(before + 1)
    await api.tool.call({ tool: 'Bash', command: 'ls' })
    expect(w.toasts.length).toBe(before + 1)
  })
})
