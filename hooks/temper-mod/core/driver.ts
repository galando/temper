// The run driver (9.8.0, round 5): with the mod loaded, a /temper:temper run is carried by the mod itself, with no model
// in the main session. It runs `temper go` and the calls the CLI gives, launches the agents the CLI names with their
// type, model and prompt as given, asks the CLI's questions word for word and runs the calls of the answer the person
// picks. Whatever needs a model or the person's own words (a typed answer, a skill, a pull request, a DRIFT row, a
// small change window, an unknown step) it hands back to the model loop of commands/temper.md, which goes on from the
// same state: the CLI holds the run, the driver holds nothing. Pure: the engine is reached through `Port`.

export type GoQuestion = { header: string; question: string; options: Array<{ label: string; description?: string; preview?: string }>; multiSelect?: boolean }
export type GoOption = {
  label: string
  calls?: string[]
  steps?: string[]
  do?: string
  stop?: boolean
  reason?: boolean
  reason_question?: GoQuestion
  answer_question?: GoQuestion
}
export type GoAsk = { question: GoQuestion; options: GoOption[]; more?: GoAsk; accept?: GoAsk }
export type GoAgent = { type: string; model: string; prompt: string; before?: string[]; after?: string[]; gate?: string }
export type GoBlocking = { question: GoQuestion; answer: string; carry: string }
export type GoOut = {
  action: string
  stage?: string
  say?: string
  agents?: GoAgent[]
  steps?: string[]
  ask?: GoAsk
  blocking?: GoBlocking[]
  gate?: string
  setup?: string[]
  tasks?: Array<{ after?: string[] }>
}

export type Ran = { code: number; out: string }
export type AgentEnd = { text: string; ms: number | null }
export type Port = {
  run(call: string): Promise<Ran>
  spawn(agent: GoAgent): Promise<string | null>
  wait(ids: string[]): Promise<Record<string, AgentEnd>>
  ask(q: GoQuestion): Promise<string | null>
  record(q: GoQuestion, answer: string): Promise<void>
  show(text: string): Promise<void>
  stopped(): boolean
}
export type DriveEnd = { kind: 'done'; text: string } | { kind: 'handback'; args: string; why: string }

const MAX_TURNS = 300

export const STOPPED = 'Temper: stopped at your interrupt. The run is saved where the CLI shows it; an agent launched before it may ' +
  'still be finishing. /temper:temper takes the run up again.'

// What the dialog cannot show (a mod's question dialog takes labels alone): each option's description, and the preview the
// options share (the Context check's table), as lines printed above the question. Empty when there is nothing to add.
export function optionLines(q: GoQuestion): string {
  const described = q.options.filter(o => (o.description ?? '').trim() !== '')
  const preview = q.options.map(o => o.preview ?? '').find(p => p.trim() !== '') ?? ''
  if (described.length === 0 && preview === '') return ''
  const rows = described.map(o => `  ${o.label}: ${(o.description ?? '').trim()}`)
  return [preview.trim(), rows.length > 0 ? `${q.header}, the choices:` : '', ...rows].filter(l => l !== '').join('\n')
}

// The last line of `temper go` that is a JSON object, or null.
export function parseGo(stdout: string): GoOut | null {
  const lines = stdout.trim().split('\n').reverse()
  for (const l of lines) {
    if (!l.trim().startsWith('{')) continue
    try {
      const v = JSON.parse(l) as GoOut
      return v && typeof v.action === 'string' ? v : null
    } catch {
      return null
    }
  }
  return null
}

// A run's slug from the request: its first words, lower case, letters, digits and dashes, 40 characters at most.
export function slugOf(request: string): string {
  const words = request.toLowerCase().replace(/`[^`]*`/g, ' ').match(/[a-z0-9]+/g) ?? []
  const stop = new Set(['a', 'an', 'the', 'to', 'of', 'and', 'for', 'in', 'on', 'with', 'add', 'build', 'make'])
  const keep = words.filter(w => !stop.has(w)).slice(0, 5)
  const slug = (keep.length > 0 ? keep : words.slice(0, 5)).join('-').slice(0, 40).replace(/-+$/, '')
  return slug || 'feature'
}

// One shell word: the text in single quotes, each ' in it written as '\''.
export const shq = (s: string): string => `'${s.replace(/'/g, "'\\''")}'`

// A call's {placeholders}, each inside the single quotes the CLI wrote around it, with each ' in the value escaped.
export function fill(call: string, fills: Record<string, string>): string {
  return call.replace(/\{(\w+)\}/g, (m, k: string) => (k in fills ? (fills[k] as string).replace(/'/g, "'\\''") : m))
}

export type StepPlan = { kind: 'run'; call: string } | { kind: 'show-last' } | { kind: 'note'; text: string } | { kind: 'handback'; why: string }

// What the driver does with one `steps` entry: a CLI call it runs; the report it shows; anything else is the model's.
export function stepPlan(step: string, cli: string): StepPlan {
  const s = step.trim()
  if (s.startsWith(cli + ' ') && !/\{[a-z_]+\}/.test(s)) return { kind: 'run', call: s }
  if (/^Copy what temper report printed/.test(s)) return { kind: 'show-last' }
  if (/^There is no record commit/.test(s)) return { kind: 'note', text: s }
  return { kind: 'handback', why: s.slice(0, 160) }
}

// An agent's answer that lists files outside the plan: the Scope drift question is the model loop's to ask.
export const hasDrift = (answer: string): boolean => /^\s*[|+]?[-\s]*DRIFT\b/m.test(answer) || /\+--- DRIFT \(\d+\)/.test(answer)

// A question the driver asks with the labels the CLI gave: at most four (the CLI puts the rest under More options).
export const labelsOf = (q: GoQuestion): string[] => q.options.map(o => o.label).slice(0, 4)

function optionOf(ask: GoAsk, label: string): GoOption | undefined {
  return ask.options.find(o => o.label === label)
}

async function runAll(port: Port, calls: string[], fills: Record<string, string>): Promise<Ran | null> {
  let last: Ran = { code: 0, out: '' }
  for (const c of calls) {
    last = await port.run(fill(c, fills))
    if (last.code !== 0 && !(/ gate [a-z]+/.test(c) && last.out.includes('-> FAIL'))) return null
  }
  return last
}

const handback = (why: string, args = 'next'): DriveEnd => ({ kind: 'handback', args, why })

// One question of the CLI, asked as given; the option's calls run with the person's answer. Returns null when it went on,
// or how the drive ends.
async function answer(port: Port, cli: string, ask: GoAsk, depth = 0): Promise<DriveEnd | null> {
  if (depth > 6) return handback('the question went round too many times')
  const picked = await port.ask(ask.question)
  if (picked === null) return handback('nobody answered the question')
  const opt = optionOf(ask, picked)
  if (opt === undefined) return handback('the person typed an answer', `discuss ${picked}`)
  await port.record(ask.question, picked)
  if (opt.label === 'More options' && ask.more) return answer(port, cli, ask.more, depth + 1)
  if (/^Ask the accept question/.test(opt.do ?? '') && ask.accept) return answer(port, cli, ask.accept, depth + 1)
  if (opt.answer_question) return handback('the option needs the person\'s words')
  const fills: Record<string, string> = {}
  if (opt.reason_question && (opt.calls ?? []).some(c => c.includes('{reason}'))) {
    const r = await port.ask(opt.reason_question)
    if (r === null) return handback('nobody answered the reason question')
    if (r === 'Cancel') return answer(port, cli, ask, depth + 1)
    await port.record(opt.reason_question, r)
    fills.reason = r
  }
  if ((opt.calls ?? []).some(c => /\{(?!reason\})[a-z_]+\}/.test(c))) return handback('the option needs a value the driver does not have')
  if ((await runAll(port, opt.calls ?? [], fills)) === null) return handback('a call of the answer failed')
  if (opt.do && !/^Ask the (more|accept) question/.test(opt.do)) return handback(opt.do.slice(0, 160))
  for (const s of opt.steps ?? []) {
    const p = stepPlan(s, cli)
    if (p.kind === 'run') {
      if ((await port.run(p.call)).code !== 0) return handback(`the step ${s.slice(0, 80)} failed`)
    } else if (p.kind === 'note') await port.show(p.text)
    else if (p.kind === 'handback') return handback(p.why)
  }
  if (opt.stop) return { kind: 'done', text: `Temper: ${opt.label}. The run is saved; /temper:temper takes it up again.` }
  return null
}

export async function drive(port: Port, cli: string, request: string | null, slug: string | null = null): Promise<DriveEnd> {
  let started = false
  let waits = 0
  for (let turn = 0; turn < MAX_TURNS; turn++) {
    // The person interrupted: stop here, with no model turn they did not ask for. The CLI holds the run.
    if (port.stopped()) return { kind: 'done', text: STOPPED }
    const go = await port.run(`${cli} go`)
    const g = parseGo(go.out)
    if (g === null) return handback('temper go gave no action')
    for (const c of g.setup ?? []) {
      const r = await port.run(c)
      if (r.code !== 0) await port.show(`Temper: a setup call failed (${c.split('/').pop()}): ${r.out.trim().split('\n').slice(-3).join(' ')}`)
    }
    if (g.action === 'none') {
      if (!started && request !== null) {
        const init = await port.run(`${cli} state init ${slug ?? slugOf(request)} --feature ${shq(request)}`)
        if (init.code !== 0) return handback('state init failed')
        started = true
        continue
      }
      return { kind: 'done', text: g.say || 'Temper: the run is done.' }
    }
    if (g.action === 'error' || g.action === 'broken') return handback(g.say || g.action)
    if (g.say) await port.show(g.say)
    if (g.action === 'wait') {
      // Tasks started in an earlier conversation (the driver waits on its own agents before it asks again): their after
      // calls run now, as the command page says. With none to run, wait a little and ask again, up to ten minutes.
      const after = (g.tasks ?? []).flatMap(t => t.after ?? [])
      if (after.length > 0) {
        for (const c of after) await port.run(fill(c, { ms: 'none' }))
        continue
      }
      if (++waits > 120) return handback('the run waited too long')
      await port.wait([])
      continue
    }
    waits = 0
    if (g.action === 'ask') {
      for (const b of g.blocking ?? []) {
        const picked = await port.ask(b.question)
        if (picked === null) return handback('nobody answered a Blocking question')
        const call = picked === 'Carry forward' ? b.carry : fill(b.answer, { answer: picked })
        if ((await port.run(call)).code !== 0) return handback('the answer call failed')
      }
      if ((g.blocking ?? []).length > 0) {
        // The answers are in intent.md: the action's gate call reads them (a FAIL is a verdict, the next question's).
        if (g.gate) await port.run(g.gate)
        continue
      }
      if (!g.ask) return handback('a question with no question')
      const end = await answer(port, cli, g.ask)
      if (end !== null) return end
      continue
    }
    if (g.action === 'work') {
      const agents = g.agents ?? []
      let drift = false
      if (agents.length > 0) {
        const ids: Array<[string, GoAgent]> = []
        for (const a of agents) {
          if (port.stopped()) return { kind: 'done', text: STOPPED }
          if ((await runAll(port, a.before ?? [], {})) === null) return handback('a before call failed')
          const id = await port.spawn(a)
          if (id === null) return handback(`the ${a.type} agent could not start`)
          ids.push([id, a])
        }
        const ends = await port.wait(ids.map(([id]) => id))
        for (const [id, a] of ids) {
          const end = ends[id] ?? { text: '', ms: null }
          if (hasDrift(end.text)) drift = true
          for (const c of a.after ?? []) {
            const r = await port.run(fill(c, { ms: end.ms === null ? 'none' : String(Math.round(end.ms)) }))
            if (/ panel [a-z]+/.test(c) && r.code === 0) await port.show(r.out)
            if (r.code !== 0 && !(c === a.gate && r.out.includes('-> FAIL'))) return handback(`an after call of the ${a.type} agent failed`)
          }
        }
      }
      if (drift) return handback('an agent listed files outside the plan (DRIFT)')
      let last = ''
      for (const s of g.steps ?? []) {
        if (port.stopped()) return { kind: 'done', text: STOPPED }
        const p = stepPlan(s, cli)
        if (p.kind === 'run') {
          const r = await port.run(p.call)
          if (r.code !== 0) return handback(`the step ${s.slice(0, 80)} failed`)
          last = r.out
        } else if (p.kind === 'show-last') await port.show(last)
        else if (p.kind === 'note') await port.show(p.text)
        else return handback(p.why)
      }
      continue
    }
    return handback(`unknown action ${g.action}`)
  }
  return handback('the run did not end in time')
}
