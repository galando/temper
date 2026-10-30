// The scripted orchestrator: commands/temper.md as a loop over `temper next --json`, with scripted agents and a scripted person.
import { Denied, World } from './world'
import type { Agent, Json, Person } from './world'

export type Script = {
  agents: Record<string, Agent>                       // by the agent type of the action: temper:temper-intent, ...
  person: Person
  // An instruction in a step or an option's `do` that is not a command: handled here, or ignored.
  instruction?: (w: World, text: string) => boolean
  stopAt?: (w: World, n: Json) => boolean             // end the loop early (a scenario that checks the middle of a run)
}

const looksLikeCommand = (s: string): boolean => /^(\/|git |gh |mkdir |cp |rm |bash |python3 |cd |t=)/.test(s.trim()) || s.includes('/scripts/temper ')

export function runCalls(w: World, calls: string[], fills: Record<string, string> = {}): void {
  for (const c of calls) {
    const text = w.fill(c, fills)
    w.guardBash(text)
    const r = w.run(text)
    w.trace.push(`  call ${text.replace(/^\S*\/scripts\/temper /, 'temper ').slice(0, 80)} -> ${r.code}`)
    if (r.code !== 0) throw new Error(`call failed (${r.code}): ${text}\n${r.out}`)
  }
}

function runSteps(w: World, script: Script, steps: string[], fills: Record<string, string> = {}): void {
  for (const s of steps) {
    if (looksLikeCommand(s)) runCalls(w, [s], fills)
    else if (!(script.instruction?.(w, s) ?? false)) w.trace.push(`  step ${s.slice(0, 60)}`)
  }
}

export function orchestrate(w: World, script: Script, limit = 400): Json {
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
      runCalls(w, n.calls ?? [])
      for (const a of (n.agents ?? []) as Json[]) {
        runCalls(w, a.before ?? [])
        const agent = script.agents[a.type]
        if (agent === undefined) throw new Error(`no scripted agent for ${a.type}`)
        agent(w, a)
        runCalls(w, a.after ?? [], { ms: '1' })
      }
      runSteps(w, script, n.steps ?? [])
      continue
    }
    if (n.action === 'wait') {
      for (const t of (n.tasks ?? []) as Json[]) runCalls(w, t.after ?? [], { ms: '1' })
      continue
    }
    if (n.action === 'ask') {
      const pick = script.person(ask!, w)
      if (pick === null) return n
      let label = typeof pick === 'string' ? pick : pick.label
      let note = typeof pick === 'string' ? '' : pick.note ?? ''
      let q: Json = ask!
      // More options holds the rest of a full question: the person answers that question next
      if (label === 'More options' && q.more) {
        w.answer(q, label)
        q = q.more as Json
        const second = script.person(q, w)
        if (second === null) return n
        label = typeof second === 'string' ? second : second.label
        note = typeof second === 'string' ? '' : second.note ?? ''
      }
      const wanted = (q.options as Json[]).find(o => o.label === label)
      // an option with a reason or a name question: the person's note on the option is that answer
      if (wanted?.reason && !note) note = 'e2e reason'
      if (wanted?.answer_question && !note) note = 'Dana Cohen'
      const option = w.answer(q, label, note)
      const fills: Record<string, string> = { reason: note || 'e2e reason', answer: note || 'Dana', K: '1', N: '1', text: note || 'x' }
      runCalls(w, option.calls ?? [], fills)
      if (option.do && !(script.instruction?.(w, option.do) ?? false)) w.trace.push(`  do ${String(option.do).slice(0, 60)}`)
      runSteps(w, script, option.steps ?? [], fills)
      if (option.stop) return n
      continue
    }
    throw new Error(`unknown action ${n.action}`)
  }
  throw new Error('the run did not end in time')
}

export { Denied }
