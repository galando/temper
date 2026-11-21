// The scripted orchestrator: commands/temper.md as a loop over `temper next --json`, with scripted agents and a scripted person.
import { driveFixSync, driveSync, recordedVerdict } from '../../hooks/temper-mod/core/driver'
import type { DriveEnd, GoQuestion, SyncPort } from '../../hooks/temper-mod/core/driver'
import { Denied, TEMPER, World } from './world'
import type { Agent, Json, Person } from './world'

export type Script = {
  agents: Record<string, Agent>                       // by the agent type of the action: temper:temper-intent, ...
  person: Person
  // An instruction in a step or an option's `do` that is not a command: handled here, or ignored.
  instruction?: (w: World, text: string) => boolean
  stopAt?: (w: World, n: Json) => boolean             // end the loop early (a scenario that checks the middle of a run)
  afterFailStops?: boolean                            // a failed after call stops its action and the loop asks next (commands/temper.md); default: it throws
}

const looksLikeCommand = (s: string): boolean => /^(\/|git |gh |mkdir |cp |rm |bash |python3 |cd |t=)/.test(s.trim()) && !/each file the run changed|\{each/.test(s)

// F4: a call that exits non-zero stops its action, unless it recorded a verdict (9.8.5, WP09): any call whose own
// marker `VERDICT: <scope> <verdict>` is in its output, by the rule of the driver's recordedVerdict. The way back for
// a CLI that prints no marker (the replay of 9.8.4 and the base): a gate call (named `gate`, or 'any' for every
// `temper gate <stage>` call of an answer) whose output holds no VERDICT: line and printed `-> FAIL` recorded one too.
export function runCalls(w: World, calls: string[], fills: Record<string, string> = {}, gateCall = '', stopOnFail = false): boolean {
  for (const c of calls) {
    const text = w.fill(c, fills)
    w.guardBash(text)
    const r = w.run(text)
    w.trace.push(`  call ${text.replace(/^\S*\/scripts\/temper /, 'temper ').slice(0, 80)} -> ${r.code}`)
    const isGate = gateCall === 'any' ? / gate [a-z]+/.test(c) : gateCall !== '' && c === gateCall
    const old = isGate && !/^VERDICT: /m.test(r.out) && r.out.includes('-> FAIL')
    if (r.code !== 0 && recordedVerdict(text, r.out) === null && !old) {
      if (stopOnFail) {
        w.trace.push('  (the call failed: its action stops, and the loop asks `next` again)')
        return false
      }
      throw new Error(`call failed (${r.code}): ${text}\n${r.out}`)
    }
  }
  return true
}

function runSteps(w: World, script: Script, steps: string[], fills: Record<string, string> = {}): void {
  for (const s of steps) {
    if (looksLikeCommand(s)) runCalls(w, [s], fills)
    else if (!(script.instruction?.(w, s) ?? false)) w.trace.push(`  step ${s.slice(0, 60)}`)
  }
}

// The person's answer carried out: the option's calls, its `do` and its steps. True when the option stops the run.
// countBack: false where the run driver already recorded the answer (the floor counts a step back once).
function applyOption(w: World, script: Script, q: Json, label: string, note: string, countBack = true): boolean {
  const wanted = (q.options as Json[]).find(o => o.label === label)
  // an option with a reason or a name question: the person's note on the option is that answer
  if (wanted?.reason && !note) note = 'e2e reason'
  if (wanted?.answer_question && !note) note = 'Dana Cohen'
  const option = w.answer(q, label, note)
  if (countBack && option.move === 'back') w.counts.back++
  const fills: Record<string, string> = { reason: note || 'e2e reason', answer: note || 'Dana', K: '1', N: '1', text: note || 'x' }
  // a gate call of the answer that records FAIL is a verdict the next question asks about (9.8.5: with the Context check
  // pending, the gate an answer runs again fails on it until the person answers it)
  runCalls(w, option.calls ?? [], fills, 'any')
  if (option.do && !(script.instruction?.(w, option.do) ?? false)) w.trace.push(`  do ${String(option.do).slice(0, 60)}`)
  runSteps(w, script, option.steps ?? [], fills)
  return option.stop === true
}

// WP27: a scenario with no scripted revise agent of its own revises the plan as its scripted planner writes it, so a
// change to a plan that exists runs the same scripted work as the second planner pass it replaces
const scripted = (script: Script, type: string): Agent | undefined =>
  script.agents[type] ?? (type === 'temper:temper-plan-revise' ? script.agents['temper:temper-plan'] : undefined)

export function orchestrate(w: World, script: Script, limit = 400): Json {
  return w.mode === 'driver' ? driven(w, script, limit) : loop(w, script, limit)
}

// One line of the trace for a step of `next`: the action and the stage; for a question, its id and its options' ids
// (9.8.5: a reworded label moves no trace).
export const traceLine = (n: Json): string => {
  const a = n.action === 'ask' ? (n.ask as Json) : null
  return `${n.action}:${n.stage ?? ''}${a ? `:${a.id}:${(a.options as Json[]).map(o => o.id).join('|')}` : ''}`
}

// Every question of a step of `next`: the gate question, its More options and Accept questions, the Context check.
function asksOf(n: Json): Json[] {
  const out: Json[] = []
  const walk = (a: Json | undefined): void => {
    if (!a) return
    out.push(a)
    walk(a.more)
    walk(a.accept)
  }
  walk(n.ask)
  walk(n.context_check?.ask)
  return out
}

// A Blocking question as the person sees it: the dialog's options with their ids beside them (`question_ids`), the first
// recommended, as blocking_asks of scripts/flow_base.py writes them. The person's pick is the label, or the text typed.
function blockingAsk(b: Json): Json {
  const ids = ((b.question_ids?.options ?? []) as Json[])
  const opts = ((b.question?.options ?? []) as Json[]).map((o, k) => ({ ...o, ...(ids[k] ?? {}), recommended: k === 0 && ids[k]?.kind === undefined }))
  return { id: b.question_ids?.id ?? 'intent.blocking', kind: 'blocking', question: b.question, options: opts }
}
function blockingPick(script: Script, w: World, b: Json): string | null {
  const ask = blockingAsk(b)
  const pick = script.person(ask, w)
  if (pick === null) return null
  const label = typeof pick === 'string' ? pick : pick.label
  const option = (ask.options as Json[]).find(o => o.label === label)
  // the option that asks for a typed answer answers nothing itself: the text typed is the answer
  if (option?.kind === 'type') return typeof pick === 'string' ? 'e2e answer' : pick.note || 'e2e answer'
  return label
}
function blockingKind(b: Json, picked: string): string {
  const ask = blockingAsk(b)
  return ((ask.options as Json[]).find(o => o.label === picked)?.kind as string | undefined) ?? 'answer'
}

class Stopped {
  constructor(public n: Json) {}
}

// 9.8.0: the mod's run driver (core/driver.ts) carries the run, as with the mod loaded: the same core, each step done at
// once on this world. WP16: a hand back is one step the conversation does here (the option, or the action's steps), and
// then the driver takes the run up again, as the person's next command does in a session.
// /temper:fix with the mod: the driver's fix steps start the run (the root cause agent, the panel, the state), then the
// same loop.
export function orchestrateFix(w: World, script: Script, bug: string, slug: string, limit = 400): Json {
  return driven(w, script, limit, port => driveFixSync(port, TEMPER, bug, slug))
}

function driven(w: World, script: Script, limit: number, start: (port: SyncPort) => DriveEnd = port => driveSync(port, TEMPER, null)): Json {
  let note = ''
  const port: SyncPort = {
    run: call => {
      let before = ''
      if (call === `${TEMPER} go`) {
        const n = w.next()
        before = traceLine(n)
        w.trace.push(before)
        if (script.stopAt?.(w, n)) throw new Stopped(n)
        if (n.action === 'broken') throw new Error(`broken run: ${n.say}`)
      }
      const r = w.run(call)
      w.trace.push(`  call ${call.replace(/^\S*\/scripts\/temper /, 'temper ').slice(0, 80)} -> ${r.code}`)
      if (call === `${TEMPER} go`) {
        // `temper go` runs the CLI's own steps (Check's run, a gate) before it stops: each is traced as the model loop
        // traces the calls it runs, and the question a scenario stops at may first show here, in its output.
        let out: Json | null = null
        try {
          out = JSON.parse(r.out.trim().split('\n').pop() ?? '') as Json
        } catch {
          out = null
        }
        for (const c of (out?.ran ?? []) as string[]) w.trace.push(`  call ${c.slice(0, 80)} -> 0`)
        // WP15: the question `temper go` stopped at, when its own steps led there: its line, as the loop writes it
        if (out?.action === 'ask' && out.ask && traceLine(out) !== before) w.trace.push(traceLine(out))
        // the floor's `auto`: in driver mode, each call `temper go` ran by itself
        w.counts.auto += ((out?.ran ?? []) as string[]).length
        if (out !== null && script.stopAt?.(w, out)) throw new Stopped(w.next())
      }
      return r
    },
    spawn: a => {
      const agent = scripted(script, a.type)
      if (agent === undefined) throw new Error(`no scripted agent for ${a.type}`)
      w.guardAgent(a as Json)
      agent(w, a as Json)
      return `agent:${a.type}`
    },
    wait: ids => Object.fromEntries(ids.map(id => [id, { text: '', ms: 1 }])),
    ask: (q: GoQuestion) => {
      const n = w.next()
      // a reason question: one an option of this step carries (its question goes to the dialog as given, with no id)
      const reason = asksOf(n).some(x => (x.options as Json[]).some(o => o.reason_ids?.kind === 'reason' && o.reason_question?.question === q.question))
      const name = asksOf(n).some(x => (x.options as Json[]).some(o => o.answer_question?.question === q.question))
      const found = asksOf(n).find(x => x.question.question === q.question)
      w.guardAsk(q as Json, n.stage ?? '', reason ? 'reason' : name ? 'name' : found?.kind ?? '')
      if (reason) {
        const r = note || (q.options[0]?.label ?? 'e2e reason')
        note = ''
        return r
      }
      // WP16: a name question is asked until a name is typed: the person types the one the loop above fills in
      if (name) {
        const typed = note || 'Dana Cohen'
        note = ''
        return typed
      }
      const full = found ?? { question: q, options: q.options }
      const pick = script.person(full, w)
      if (pick === null) return null
      note = typeof pick === 'string' ? '' : pick.note ?? ''
      const label = typeof pick === 'string' ? pick : pick.label
      // WP21: as in plain mode, the person's note on an option that needs a reason is that reason (the driver then asks
      // no reason question, as the guard counts it)
      const wanted = ((full.options ?? []) as Json[]).find(o => o.label === label)
      if (wanted?.reason && note === '') note = 'e2e reason'
      return note !== '' ? { label, note } : label
    },
    // The Blocking questions of a step, four to a dialog: the person answers each as asked one at a time.
    askAll: (qs: GoQuestion[]) => {
      const n = w.next()
      w.guardAsk(qs as Json[], n.stage ?? '', 'blocking')
      return qs.map(q => {
        const b = ((n.blocking_asks ?? []) as Json[]).find(x => x.question?.question === q.question)
        return blockingPick(script, w, b ?? { question: q })
      })
    },
    record: (q, label) => {
      const full = asksOf(w.next()).find(x => x.question.question === q.question)
      if (full === undefined) return
      const option = w.answer(full, label, note)
      if (option.move === 'back') w.counts.back++
    },
    show: text => {
      w.trace.push(`  show ${text.split('\n')[0]!.slice(0, 60)}`)
    },
    // WP15: the card the driver gives before it asks; the trace names its kind, as the loop does
    card: () => {
      w.trace.push(`  card ${(w.next().card as Json | null)?.kind ?? 'none'}`)
    },
  }
  let end
  try {
    end = start(port)
  } catch (e) {
    if (e instanceof Stopped) return e.n
    throw e
  }
  w.trace.push(`  driver ${end.kind}: ${(end.kind === 'done' ? end.text : `step ${end.needs} ${end.option}`).slice(0, 100)}`)
  if (end.kind === 'done') return w.next()
  w.counts.handbacks++
  // WP16: the conversation does the one step of the hand back, as the person chose it: the option whole (by its id), or
  // the action's steps (a pull request). Then the person types the command again, and the driver takes the run up.
  const n = w.next()
  const q = asksOf(n).find(x => (x.options as Json[]).some(o => o.id === end.option))
  if (q !== undefined) {
    const label = String((q.options as Json[]).find(o => o.id === end.option)!.label)
    if (applyOption(w, script, q, label, note, false)) return n
  } else if (n.action === 'work') {
    runSteps(w, script, n.steps ?? [])
  } else {
    throw new Error(`step ${end.needs} ${end.option}: no such option or step at ${n.action}`)
  }
  // Each hand back takes the run up again with a fresh drive: the limit bounds how many, so a person who keeps picking
  // a hand back option fails here, never by the depth of the stack.
  if (limit <= 1) throw new Error(`step ${end.needs} ${end.option}: more hand backs than the limit`)
  return driven(w, script, limit - 1)
}

function loop(w: World, script: Script, limit = 400): Json {
  let last: Json = {}
  for (let i = 0; i < limit; i++) {
    const n = w.next()
    last = n
    const ask = n.action === 'ask' ? (n.ask as Json) : null
    w.trace.push(traceLine(n))
    // WP15: the card of the question (the approval, the commit, a stop), shown before the person answers
    if (ask !== null && n.card) w.trace.push(`  card ${(n.card as Json).kind}`)
    if (script.stopAt?.(w, n)) return n
    if (n.action === 'none') return n
    if (n.action === 'broken') throw new Error(`broken run: ${n.say}`)
    if (n.action === 'work' || n.action === 'auto') {
      if (n.action === 'auto') w.counts.auto++   // the floor's `auto`: a step the CLI decided with nobody asked
      if (!runCalls(w, n.calls ?? [], {}, '', true)) continue
      for (const a of (n.agents ?? []) as Json[]) {
        runCalls(w, a.before ?? [])
        const agent = scripted(script, a.type)
        if (agent === undefined) throw new Error(`no scripted agent for ${a.type}`)
        w.guardAgent(a)
        agent(w, a)
        runCalls(w, a.after ?? [], { ms: '1' }, a.gate ?? '', script.afterFailStops ?? false)
      }
      runSteps(w, script, n.steps ?? [])
      continue
    }
    if (n.action === 'wait') {
      for (const t of (n.tasks ?? []) as Json[]) runCalls(w, t.after ?? [], { ms: '1' })
      continue
    }
    if (n.action === 'ask' && ((n.blocking_asks ?? []) as Json[]).length > 0) {
      // The Blocking questions in one dialog, four at most (the rest in the next), as commands/temper.md and the run
      // driver ask them; each answer's call writes it into intent.md, then the action's gate runs again.
      const blocking = n.blocking_asks as Json[]
      for (let i = 0; i < blocking.length; i += 4) {
        const chunk = blocking.slice(i, i + 4)
        w.guardAsk(chunk.map(b => b.question), n.stage ?? '', 'blocking')
        for (const b of chunk) {
          const picked = blockingPick(script, w, b)
          if (picked === null) return n
          const kind = blockingKind(b, picked)
          runCalls(w, [kind === 'carry' ? b.carry : b.answer], { answer: picked })
        }
      }
      if (n.gate) runCalls(w, [n.gate], {}, n.gate)
      continue
    }
    if (n.action === 'ask') {
      w.guardAsk(ask!.question, n.stage ?? '', ask!.kind ?? '')
      const pick = script.person(ask!, w)
      if (pick === null) return n
      let label = typeof pick === 'string' ? pick : pick.label
      let note = typeof pick === 'string' ? '' : pick.note ?? ''
      let q: Json = ask!
      // More options (kind `more`) holds the rest of a full question: the person answers that question next
      if ((q.options as Json[]).find(o => o.label === label)?.kind === 'more' && q.more) {
        w.answer(q, label)
        q = q.more as Json
        w.guardAsk(q.question, n.stage ?? '', q.kind ?? ask!.kind ?? '')
        const second = script.person(q, w)
        if (second === null) return n
        label = typeof second === 'string' ? second : second.label
        note = typeof second === 'string' ? '' : second.note ?? ''
      }
      if (applyOption(w, script, q, label, note)) return n
      continue
    }
    throw new Error(`unknown action ${n.action}`)
  }
  throw new Error('the run did not end in time')
}

export { Denied }

// ---- the check of this file, on made up input ---------------------------------------------------------------------
//
//   bun scripts/e2e/loop.ts --check   asserts that a driven run whose person picks a hand back option at every question
//                                     fails at the limit; a made up world answers, with no run of the CLI; exit 0 or 1

function check(): number {
  let fails = 0
  const eq = (name: string, got: unknown, want: unknown): void => {
    const ok = JSON.stringify(got) === JSON.stringify(want)
    if (!ok) fails++
    const why = ok ? '' : ` (got ${JSON.stringify(got)}, want ${JSON.stringify(want)})`
    console.log(`${ok ? 'PASS' : 'FAIL'}: loop ${name}${why}`)
  }
  const teach = { label: 'Teach Me', id: 'teach-me', needs: 'talk', do: 'Use the teach-me skill, then ask this question again.', calls: [] }
  const ask = { id: 'review.pass', kind: 'gate', question: { header: 'Temper gate', question: 'Review: continue?', multiSelect: false,
    options: [{ label: 'Teach Me', description: '' }] }, options: [teach] }
  const n = { action: 'ask', stage: 'review', ask }
  const counts = { auto: 0, back: 0, handbacks: 0 }
  const w = {
    mode: 'driver', trace: [] as string[], counts,
    next: () => n,
    run: (call: string) => ({ code: 0, out: / go( --taken-up)?$/.test(call) ? JSON.stringify(n) : '' }),
    fill: (c: string) => c,
    guardAsk: () => undefined, guardAgent: () => undefined, guardBash: () => undefined,
    answer: () => teach,
  } as unknown as World
  const script: Script = { agents: {}, person: () => 'Teach Me', instruction: () => true }
  let thrown = ''
  try {
    orchestrate(w, script, 5)
  } catch (e) {
    thrown = (e as Error).message
  }
  eq('a person who keeps picking a hand back option fails at the limit, not at the depth of the stack',
    [thrown, counts.handbacks], ['step talk teach-me: more hand backs than the limit', 5])
  console.log(`loop --check: ${fails === 0 ? 'PASS' : `FAIL (${fails})`}`)
  return fails === 0 ? 0 : 1
}

if (import.meta.main) {
  if (process.argv[2] === '--check') process.exit(check())
  console.log('usage: bun scripts/e2e/loop.ts --check')
  process.exit(2)
}
