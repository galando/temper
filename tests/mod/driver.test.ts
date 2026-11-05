// The run driver (9.8.0, round 5): the mod carries a /temper:temper run with no model in the main session. Its core is
// pure; here a scripted port stands for the engine and a list of `temper go` answers for the CLI.
import { describe, expect, test } from 'claude-code/testing'
import { STOPPED, drive, fill, hasDrift, optionLines, parseGo, shq, slugOf, stepPlan } from '../../hooks/temper-mod/core/driver'
import type { AgentEnd, GoAgent, GoOut, GoQuestion, Port } from '../../hooks/temper-mod/core/driver'

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
      if (call === `${CLI} go`) {
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
const agent = (type: string, after: string[] = []): GoAgent => ({ type, model: 'opus', prompt: `Follow ${type}.`, after, gate: after.find(c => / gate /.test(c)) })

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
    expect(log.shown).toContain('+----+\n| PLAN |\n+----+')
    expect(log.recorded).toEqual(['Plan: the check passed. Approve the plan? -> Approve (Recommended)'])
    expect(log.ran).toContain(`${CLI} state advance plan_complete build`)
  })

  test('Blocking questions: each answer is written by its call, Carry forward by its own', async () => {
    const { p, log } = port({
      goes: [{ action: 'ask', stage: 'intent', gate: `${CLI} gate intent`, ask: { question: q('Intent: answer the questions?', ['Continue']), options: [] }, blocking: [
        { question: q('Who may refund?', ['Admins only (Recommended)', 'Everyone', 'Carry forward'], 'Question 1'), answer: `${CLI} intent answer 'Who may refund?' '{answer}'`, carry: `${CLI} intent carry 'Who may refund?'` },
        { question: q('A window?', ['60 days', 'Carry forward'], 'Question 2'), answer: `${CLI} intent answer 'A window?' '{answer}'`, carry: `${CLI} intent carry 'A window?'` },
      ] }],
      answers: ['Admins only (Recommended)', 'Carry forward'],
    })
    await drive(p, CLI, null)
    expect(log.ran).toContain(`${CLI} intent answer 'Who may refund?' 'Admins only (Recommended)'`)
    expect(log.ran).toContain(`${CLI} intent carry 'A window?'`)
    // Then the action's gate call reads the answers, before `temper go` asks again.
    expect(log.ran.slice(-2)).toEqual([`${CLI} gate intent`, `${CLI} go`])
  })

  test('a typed answer goes to the conversation as the person\'s message (discuss), with nothing run', async () => {
    const { p, log } = port({
      goes: [{ action: 'ask', ask: { question: q('Approve?', ['Approve', 'Loop back']), options: [{ label: 'Approve', calls: [`${CLI} state advance plan_complete build`] }, { label: 'Loop back' }] } }],
      answers: ['make the route admin only'],
    })
    expect(await drive(p, CLI, null)).toEqual({ kind: 'handback', args: 'discuss make the route admin only', why: 'the person typed an answer' })
    expect(log.ran.filter(c => c.includes('state advance'))).toEqual([])
    expect(log.recorded).toEqual([])
  })

  test('an option that needs a reason asks the reason question as given; Cancel asks the first question again', async () => {
    const rq = q('Loop back to Plan. What is the reason?', ['The plan cannot be built', 'Cancel'])
    const opts = { question: q('Group G1 is parked. Run the task again?', ['Loop back to Plan', 'Run the task again']), options: [
      { label: 'Loop back to Plan', calls: [`${CLI} state loop build plan --reason '{reason}'`], reason: true, reason_question: rq },
      { label: 'Run the task again', calls: [`${CLI} group reopen G1 --task 2`] },
    ] }
    const { p, log } = port({ goes: [{ action: 'ask', ask: opts }, { action: 'none', say: 'end' }], answers: ['Loop back to Plan', 'Cancel', 'Loop back to Plan', 'The plan cannot be built'] })
    await drive(p, CLI, null)
    expect(log.asked.map(x => x.question)).toEqual([opts.question.question, rq.question, opts.question.question, rq.question])
    expect(log.ran).toContain(`${CLI} state loop build plan --reason 'The plan cannot be built'`)
    expect(log.recorded).toContain(`${rq.question} -> The plan cannot be built`)
  })

  test('More options asks the rest of the question; an option with a `do` (a skill) runs its calls, then hands back', async () => {
    const more = { question: q('More choices?', ['Grill Me', 'Cancel']), options: [{ label: 'Grill Me', do: 'Use the grill-me skill on this stage\'s work, then ask this question again.' }, { label: 'Cancel' }] }
    const { p, log } = port({ goes: [{ action: 'ask', ask: { question: q('Approve?', ['Approve', 'More options']), options: [{ label: 'Approve' }, { label: 'More options', do: 'Ask the more question.' }], more } }], answers: ['More options', 'Grill Me'] })
    const end = await drive(p, CLI, null)
    expect(end.kind).toBe('handback')
    expect(log.asked.map(x => x.question)).toEqual(['Approve?', 'More choices?'])
  })

  test('Save for later ends the drive and says the run is saved', async () => {
    const { p } = port({ goes: [{ action: 'ask', ask: { question: q('Approve?', ['Approve', 'Save for later']), options: [{ label: 'Approve' }, { label: 'Save for later', stop: true }] } }], answers: ['Save for later'] })
    const end = await drive(p, CLI, null)
    expect(end.kind).toBe('done')
    expect(end.kind === 'done' && end.text).toContain('saved')
  })

  test('an agent that lists DRIFT rows: its after calls run, then the conversation asks the Scope drift question', async () => {
    const b = agent('temper:temper-build-task', [`${CLI} task gate 1 --model haiku`])
    const { p, log } = port({ goes: [{ action: 'work', agents: [b] }], ends: { ag1: { text: '+--- DRIFT (1) ---+\n| src/x.py: needed |', ms: 5 } } })
    const end = await drive(p, CLI, null)
    expect(end.kind === 'handback' && end.why).toContain('DRIFT')
    expect(log.ran).toContain(`${CLI} task gate 1 --model haiku`)
  })

  test('the report steps: CLI calls run, the report is shown as printed; a step only a model can do hands back', async () => {
    const { p, log } = port({
      goes: [{ action: 'work', steps: [`${CLI} report --end`, 'Copy what temper report printed into your reply, as it printed it.', 'Follow /p/reference/pr.md, section One PR.'] }],
      out: call => (call.endsWith('report --end') ? 'REPORT TEXT' : ''),
    })
    const end = await drive(p, CLI, null)
    expect(log.shown).toContain('REPORT TEXT')
    expect(end.kind === 'handback' && end.why).toContain('pr.md')
  })

  test('a failed call, an error action and a gate that records FAIL', async () => {
    const g = agent('temper:temper-plan', [`${CLI} gate plan --brief`])
    const { p: p1 } = port({ goes: [{ action: 'work', agents: [g] }, { action: 'none', say: 'end' }], fail: c => c.includes('gate plan'), out: c => (c.includes('gate plan') ? 'temper gate plan -> FAIL' : '') })
    expect((await drive(p1, CLI, null)).kind).toBe('done')
    const { p: p2 } = port({ goes: [{ action: 'error', say: 'temper next failed' }] })
    expect(await drive(p2, CLI, null)).toEqual({ kind: 'handback', args: 'next', why: 'temper next failed' })
    const { p: p3 } = port({ goes: [{ action: 'ask', ask: { question: q('Approve?', ['Approve', 'No']), options: [{ label: 'Approve', calls: [`${CLI} state advance plan_complete build`] }, { label: 'No' }] } }], answers: ['Approve'], fail: c => c.includes('state advance') })
    expect((await drive(p3, CLI, null)).kind).toBe('handback')
  })

  test('a wait for tasks started in an earlier conversation runs their after calls now', async () => {
    const { p, log } = port({ goes: [{ action: 'wait', tasks: [{ after: [`${CLI} usage add --stage build --ms {ms} --task 2`, `${CLI} task gate 2`] }] }, { action: 'none', say: 'end' }] })
    expect((await drive(p, CLI, null)).kind).toBe('done')
    expect(log.ran).toContain(`${CLI} usage add --stage build --ms none --task 2`)
    expect(log.ran).toContain(`${CLI} task gate 2`)
  })

  test('nobody answers (a session with no one to ask): the conversation takes the run on', async () => {
    const { p } = port({ goes: [{ action: 'ask', ask: { question: q('Approve?', ['Approve', 'No']), options: [{ label: 'Approve' }, { label: 'No' }] } }], answers: [] })
    expect((await drive(p, CLI, null)).kind).toBe('handback')
  })
})

describe('the person interrupts', () => {
  test('the drive stops where it is, says how to take the run up again, and starts no model turn', async () => {
    const { p, log } = port({ goes: [{ action: 'work', steps: [`${CLI} report --end`] }, { action: 'none' }], stop: 1 })
    expect(await drive(p, CLI, null)).toEqual({ kind: 'done', text: STOPPED })
    expect(log.ran).toEqual([`${CLI} go`])
  })
})

describe('what the dialog cannot show', () => {
  test('each option\'s description and the shared preview are printed above the question', () => {
    const q = { header: 'Temper gate', question: 'Plan: approve?', options: [
      { label: 'Approve (Recommended)', description: 'Go on to Design.', preview: '| a | b |' },
      { label: 'Save for later', description: 'Stop here.', preview: '| a | b |' }] }
    expect(optionLines(q)).toBe('| a | b |\nTemper gate, the choices:\n  Approve (Recommended): Go on to Design.\n  Save for later: Stop here.')
    expect(optionLines({ header: 'Question 1', question: 'Who?', options: [{ label: 'Admins' }, { label: 'Carry forward', description: '' }] })).toBe('')
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
  test('step plans and DRIFT', () => {
    expect(stepPlan(`${CLI} spec commit 'x'`, CLI)).toEqual({ kind: 'run', call: `${CLI} spec commit 'x'` })
    expect(stepPlan(`${CLI} spec commit '{message}'`, CLI).kind).toBe('handback')
    expect(stepPlan('git push', CLI).kind).toBe('handback')
    expect(hasDrift('| DRIFT: src/a.py |')).toBe(true)
    expect(hasDrift('no drift here, all in scope')).toBe(false)
  })
})
