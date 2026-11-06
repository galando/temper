// The scripted orchestrator: commands/temper.md as a loop over `temper next --json`, with scripted agents and a scripted person.
import { driveFixSync, driveSync } from '../../hooks/temper-mod/core/driver'
import type { DriveEnd, GoQuestion, SyncPort } from '../../hooks/temper-mod/core/driver'
import { Denied, TEMPER, World } from './world'
import type { Agent, Json, Person } from './world'

export type Script = {
  agents: Record<string, Agent>                       // by the agent type of the action: temper:temper-intent, ...
  person: Person
  // An instruction in a step or an option's `do` that is not a command: handled here, or ignored.
  instruction?: (w: World, text: string) => boolean
  stopAt?: (w: World, n: Json) => boolean             // end the loop early (a scenario that checks the middle of a run)
}

const looksLikeCommand = (s: string): boolean => /^(\/|git |gh |mkdir |cp |rm |bash |python3 |cd |t=)/.test(s.trim()) && !/each file the run changed|\{each/.test(s)

// F4: a call that exits non-zero stops its action, except an agent's gate call (named `gate`) that printed `-> FAIL`: it recorded a verdict.
export function runCalls(w: World, calls: string[], fills: Record<string, string> = {}, gateCall = '', stopOnFail = false): boolean {
  for (const c of calls) {
    const text = w.fill(c, fills)
    w.guardBash(text)
    const r = w.run(text)
    w.trace.push(`  call ${text.replace(/^\S*\/scripts\/temper /, 'temper ').slice(0, 80)} -> ${r.code}`)
    if (r.code !== 0 && !(gateCall !== '' && c === gateCall && r.out.includes('-> FAIL'))) {
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
function applyOption(w: World, script: Script, q: Json, label: string, note: string): boolean {
  const wanted = (q.options as Json[]).find(o => o.label === label)
  // an option with a reason or a name question: the person's note on the option is that answer
  if (wanted?.reason && !note) note = 'e2e reason'
  if (wanted?.answer_question && !note) note = 'Dana Cohen'
  const option = w.answer(q, label, note)
  const fills: Record<string, string> = { reason: note || 'e2e reason', answer: note || 'Dana', K: '1', N: '1', text: note || 'x' }
  runCalls(w, option.calls ?? [], fills)
  if (option.do && !(script.instruction?.(w, option.do) ?? false)) w.trace.push(`  do ${String(option.do).slice(0, 60)}`)
  runSteps(w, script, option.steps ?? [], fills)
  return option.stop === true
}

export function orchestrate(w: World, script: Script, limit = 400): Json {
  return w.mode === 'driver' ? driven(w, script, limit) : loop(w, script, limit)
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

class Stopped {
  constructor(public n: Json) {}
}

// 9.8.0: the mod's run driver (core/driver.ts) carries the run, as with the mod loaded: the same core, each step done at
// once on this world. A hand back goes on in the model loop above, from the same state, as in a session.
// /temper:fix with the mod: the driver's fix steps start the run (the root cause agent, the panel, the state), then the
// same loop; a hand back goes on in the model loop, as in a session.
export function orchestrateFix(w: World, script: Script, bug: string, slug: string, limit = 400): Json {
  return driven(w, script, limit, port => driveFixSync(port, TEMPER, bug, slug))
}

function driven(w: World, script: Script, limit: number, start: (port: SyncPort) => DriveEnd = port => driveSync(port, TEMPER, null)): Json {
  let note = ''
  const port: SyncPort = {
    run: call => {
      if (call === `${TEMPER} go`) {
        const n = w.next()
        const a = n.action === 'ask' ? (n.ask as Json) : null
        w.trace.push(`${n.action}:${n.stage ?? ''}${a ? ':' + (a.options as Json[]).map(o => o.label).join('|') : ''}`)
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
        if (out !== null && script.stopAt?.(w, out)) throw new Stopped(w.next())
      }
      return r
    },
    spawn: a => {
      const agent = script.agents[a.type]
      if (agent === undefined) throw new Error(`no scripted agent for ${a.type}`)
      w.guardAgent(a as Json)
      agent(w, a as Json)
      return `agent:${a.type}`
    },
    wait: ids => Object.fromEntries(ids.map(id => [id, { text: '', ms: 1 }])),
    ask: (q: GoQuestion) => {
      w.guardAsk(q as Json)
      if (/What is the reason\?$/.test(q.question)) {
        const r = note || (q.options[0]?.label ?? 'e2e reason')
        note = ''
        return r
      }
      const full = asksOf(w.next()).find(x => x.question.question === q.question) ?? { question: q, options: q.options }
      const pick = script.person(full, w)
      if (pick === null) return null
      note = typeof pick === 'string' ? '' : pick.note ?? ''
      return typeof pick === 'string' ? pick : pick.label
    },
    record: (q, label) => {
      const full = asksOf(w.next()).find(x => x.question.question === q.question)
      if (full !== undefined) w.answer(full, label, note)
    },
    show: text => {
      w.trace.push(`  show ${text.split('\n')[0]!.slice(0, 60)}`)
    },
  }
  let end
  try {
    end = start(port)
  } catch (e) {
    if (e instanceof Stopped) return e.n
    throw e
  }
  w.trace.push(`  driver ${end.kind}: ${(end.kind === 'done' ? end.text : `${end.args}: ${end.why}`).slice(0, 100)}`)
  if (end.kind === 'done') return w.next()
  if (end.args.startsWith('chose ')) {
    // The person chose an option the conversation carries out: it runs it whole, as the answer given, with no new question.
    const label = end.args.slice('chose '.length)
    const n = w.next()
    const q = asksOf(n).find(x => (x.options as Json[]).some(o => o.label === label))
    if (q === undefined) throw new Error(`chose ${label}: no such option at ${n.action}`)
    if (applyOption(w, script, q, label, note)) return n
  }
  return loop(w, script, limit)
}

function loop(w: World, script: Script, limit = 400): Json {
  let last: Json = {}
  for (let i = 0; i < limit; i++) {
    const n = w.next()
    last = n
    const ask = n.action === 'ask' ? (n.ask as Json) : null
    w.trace.push(`${n.action}:${n.stage ?? ''}${ask ? ':' + (ask.options as Json[]).map(o => o.label).join('|') : ''}`)
    if (script.stopAt?.(w, n)) return n
    if (n.action === 'none') return n
    if (n.action === 'broken') throw new Error(`broken run: ${n.say}`)
    if (n.action === 'work' || n.action === 'auto') {
      if (!runCalls(w, n.calls ?? [], {}, '', true)) continue
      for (const a of (n.agents ?? []) as Json[]) {
        runCalls(w, a.before ?? [])
        const agent = script.agents[a.type]
        if (agent === undefined) throw new Error(`no scripted agent for ${a.type}`)
        w.guardAgent(a)
        agent(w, a)
        runCalls(w, a.after ?? [], { ms: '1' }, a.gate ?? '')
      }
      runSteps(w, script, n.steps ?? [])
      continue
    }
    if (n.action === 'wait') {
      for (const t of (n.tasks ?? []) as Json[]) runCalls(w, t.after ?? [], { ms: '1' })
      continue
    }
    if (n.action === 'ask') {
      w.guardAsk(ask!.question)
      const pick = script.person(ask!, w)
      if (pick === null) return n
      let label = typeof pick === 'string' ? pick : pick.label
      let note = typeof pick === 'string' ? '' : pick.note ?? ''
      let q: Json = ask!
      // More options holds the rest of a full question: the person answers that question next
      if (label === 'More options' && q.more) {
        w.answer(q, label)
        q = q.more as Json
        w.guardAsk(q.question)
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
