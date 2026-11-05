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

// The driver is a generator of steps (an effect each: run a call, launch an agent, wait, ask, record, show, look for an
// interrupt), so one core runs in the mod (each step awaited on the engine) and in the e2e driver (each step done at once
// on its world).
export type Effect =
  | { k: 'run'; call: string }
  | { k: 'spawn'; agent: GoAgent }
  | { k: 'wait'; ids: string[] }
  | { k: 'ask'; q: GoQuestion }
  | { k: 'record'; q: GoQuestion; answer: string }
  | { k: 'show'; text: string }
  | { k: 'stopped' }
type Steps<R> = Generator<Effect, R, unknown>

function* run(call: string): Steps<Ran> {
  return (yield { k: 'run', call }) as Ran
}
function* ask(q: GoQuestion): Steps<string | null> {
  return (yield { k: 'ask', q }) as string | null
}
function* show(text: string): Steps<void> {
  yield { k: 'show', text }
}
function* stopped(): Steps<boolean> {
  return (yield { k: 'stopped' }) as boolean
}

function* runAll(calls: string[], fills: Record<string, string>): Steps<Ran | null> {
  let last: Ran = { code: 0, out: '' }
  for (const c of calls) {
    last = yield* run(fill(c, fills))
    if (last.code !== 0 && !(/ gate [a-z]+/.test(c) && last.out.includes('-> FAIL'))) return null
  }
  return last
}

const handback = (why: string, args = 'next'): DriveEnd => ({ kind: 'handback', args, why })

// One question of the CLI, asked as given; the option's calls run with the person's answer. Returns null when it went on,
// or how the drive ends.
function* answer(cli: string, q: GoAsk, depth = 0): Steps<DriveEnd | null> {
  if (depth > 6) return handback('the question went round too many times')
  const picked = yield* ask(q.question)
  if (picked === null) return handback('nobody answered the question')
  const opt = optionOf(q, picked)
  if (opt === undefined) return handback('the person typed an answer', `discuss ${picked}`)
  yield { k: 'record', q: q.question, answer: picked }
  if (opt.label === 'More options' && q.more) return yield* answer(cli, q.more, depth + 1)
  if (/^Ask the accept question/.test(opt.do ?? '') && q.accept) return yield* answer(cli, q.accept, depth + 1)
  // An option the conversation must carry out (a skill, the HTML review, a small change, a name to type, a step only a
  // model can do): nothing of it runs here; the conversation runs it whole, as the answer the person already gave.
  const needs = opt.answer_question ? 'the option needs the person\'s words'
    : opt.do ? opt.do.slice(0, 160)
      : (opt.steps ?? []).map(st => stepPlan(st, cli)).find(sp => sp.kind === 'handback')?.kind === 'handback' ? 'a step of the option needs the conversation' : null
  if (needs !== null) return handback(needs, `chose ${opt.label}`)
  const fills: Record<string, string> = {}
  if (opt.reason_question && (opt.calls ?? []).some(c => c.includes('{reason}'))) {
    const r = yield* ask(opt.reason_question)
    if (r === null) return handback('nobody answered the reason question')
    if (r === 'Cancel') return yield* answer(cli, q, depth + 1)
    yield { k: 'record', q: opt.reason_question, answer: r }
    fills.reason = r
  }
  if ((opt.calls ?? []).some(c => /\{(?!reason\})[a-z_]+\}/.test(c))) return handback('the option needs a value the driver does not have', `chose ${opt.label}`)
  if ((yield* runAll(opt.calls ?? [], fills)) === null) return handback('a call of the answer failed')
  for (const s of opt.steps ?? []) {
    const p = stepPlan(s, cli)
    if (p.kind === 'run') {
      if ((yield* run(p.call)).code !== 0) return handback(`the step ${s.slice(0, 80)} failed`)
    } else if (p.kind === 'note') yield* show(p.text)
  }
  if (opt.stop) return { kind: 'done', text: `Temper: ${opt.label}. The run is saved; /temper:temper takes it up again.` }
  return null
}

export function* driveSteps(cli: string, request: string | null, slug: string | null = null): Steps<DriveEnd> {
  let started = false
  let waits = 0
  for (let turn = 0; turn < MAX_TURNS; turn++) {
    // The person interrupted: stop here, with no model turn they did not ask for. The CLI holds the run.
    if (yield* stopped()) return { kind: 'done', text: STOPPED }
    const g = parseGo((yield* run(`${cli} go`)).out)
    if (g === null) return handback('temper go gave no action')
    for (const c of g.setup ?? []) {
      const r = yield* run(c)
      if (r.code !== 0) yield* show(`Temper: a setup call failed (${c.split('/').pop()}): ${r.out.trim().split('\n').slice(-3).join(' ')}`)
    }
    if (g.action === 'none') {
      if (!started && request !== null) {
        const init = yield* run(`${cli} state init ${slug ?? slugOf(request)} --feature ${shq(request)}`)
        if (init.code !== 0) return handback('state init failed')
        started = true
        continue
      }
      return { kind: 'done', text: g.say || 'Temper: the run is done.' }
    }
    if (g.action === 'error' || g.action === 'broken') return handback(g.say || g.action)
    if (g.say) yield* show(g.say)
    if (g.action === 'wait') {
      // Tasks started in an earlier conversation (the driver waits on its own agents before it asks again): their after
      // calls run now, as the command page says. With none to run, wait a little and ask again, up to ten minutes.
      const after = (g.tasks ?? []).flatMap(t => t.after ?? [])
      if (after.length > 0) {
        for (const c of after) yield* run(fill(c, { ms: 'none' }))
        continue
      }
      if (++waits > 120) return handback('the run waited too long')
      yield { k: 'wait', ids: [] }
      continue
    }
    waits = 0
    if (g.action === 'ask') {
      for (const b of g.blocking ?? []) {
        const picked = yield* ask(b.question)
        if (picked === null) return handback('nobody answered a Blocking question')
        const call = picked === 'Carry forward' ? b.carry : fill(b.answer, { answer: picked })
        if ((yield* run(call)).code !== 0) return handback('the answer call failed')
      }
      if ((g.blocking ?? []).length > 0) {
        // The answers are in intent.md: the action's gate call reads them (a FAIL is a verdict, the next question's).
        if (g.gate) yield* run(g.gate)
        continue
      }
      if (!g.ask) return handback('a question with no question')
      const end = yield* answer(cli, g.ask)
      if (end !== null) return end
      continue
    }
    if (g.action === 'work') {
      const agents = g.agents ?? []
      let drift = false
      if (agents.length > 0) {
        const ids: Array<[string, GoAgent]> = []
        for (const a of agents) {
          if (yield* stopped()) return { kind: 'done', text: STOPPED }
          if ((yield* runAll(a.before ?? [], {})) === null) return handback('a before call failed')
          const id = (yield { k: 'spawn', agent: a }) as string | null
          if (id === null) return handback(`the ${a.type} agent could not start`)
          ids.push([id, a])
        }
        const ends = (yield { k: 'wait', ids: ids.map(([id]) => id) }) as Record<string, AgentEnd>
        for (const [id, a] of ids) {
          const end = ends[id] ?? { text: '', ms: null }
          if (hasDrift(end.text)) drift = true
          for (const c of a.after ?? []) {
            const r = yield* run(fill(c, { ms: end.ms === null ? 'none' : String(Math.round(end.ms)) }))
            if (/ panel [a-z]+/.test(c) && r.code === 0) yield* show(r.out)
            if (r.code !== 0 && !(c === a.gate && r.out.includes('-> FAIL'))) return handback(`an after call of the ${a.type} agent failed`)
          }
        }
      }
      if (drift) return handback('an agent listed files outside the plan (DRIFT)')
      // Steps only the conversation can do (a pull request, a commit message to write): the conversation runs them all,
      // before any of them runs here, so none is left half done.
      const model = (g.steps ?? []).map(st => stepPlan(st, cli)).find(sp => sp.kind === 'handback')
      if (model !== undefined && model.kind === 'handback') return handback(model.why)
      let last = ''
      for (const s of g.steps ?? []) {
        if (yield* stopped()) return { kind: 'done', text: STOPPED }
        const p = stepPlan(s, cli)
        if (p.kind === 'run') {
          const r = yield* run(p.call)
          if (r.code !== 0) return handback(`the step ${s.slice(0, 80)} failed`)
          last = r.out
        } else if (p.kind === 'show-last') yield* show(last)
        else if (p.kind === 'note') yield* show(p.text)
        else return handback(p.why)
      }
      continue
    }
    return handback(`unknown action ${g.action}`)
  }
  return handback('the run did not end in time')
}

// A fix run's slug from the bug: a ticket key keeps its case (`JIRA-123-checkout-500`), the rest as a request's slug.
export function fixSlug(bug: string): string {
  const key = /^\s*([A-Z][A-Z0-9]+-\d+)\b(.*)$/s.exec(bug)
  if (key === null) return slugOf(bug)
  const rest = slugOf(key[2] ?? '')
  return rest === 'feature' ? (key[1] as string) : `${key[1]}-${rest}`.slice(0, 48)
}

// The root cause agent's prompt, as commands/fix.md writes it.
export function rcaPrompt(plugin: string, bug: string, slug: string): string {
  return [
    `Follow ${plugin}/agents/rca.md exactly. Bug: ${bug}.`,
    `RCA file: .temper/specs/${slug}/rca.md`,
    `Plugin folder: ${plugin}; wherever the brief or a reference page writes the CLAUDE_PLUGIN_ROOT variable, use this folder.`,
  ].join('\n')
}

// /temper:fix <bug> with no run active: the steps of commands/fix.md before the run exists (the CLI's setup, the root
// cause agent, the panel the CLI draws from rca.md, the run's state and the fix branch), then the same loop as /temper.
export function* fixSteps(cli: string, bug: string, slug: string | null = null): Steps<DriveEnd> {
  const plugin = cli.replace(/\/scripts\/temper$/, '')
  const s = slug ?? fixSlug(bug)
  const g = parseGo((yield* run(`${cli} go`)).out)
  if (g === null) return handback('temper go gave no action')
  for (const c of g.setup ?? []) {
    const r = yield* run(c)
    if (r.code !== 0) yield* show(`Temper: a setup call failed (${c.split('/').pop()}): ${r.out.trim().split('\n').slice(-3).join(' ')}`)
  }
  if (g.action !== 'none') return handback('a run is active')
  const model = ((yield* run(`${cli} model rca`)).out.trim().split('\n').pop() ?? '').trim()
  const agent: GoAgent = { type: 'temper:temper-rca', model, prompt: rcaPrompt(plugin, bug, s) }
  yield* show(`RCA: the root cause agent is working${model ? ` on ${model}` : ''}. The run goes on when it returns.`)
  const id = (yield { k: 'spawn', agent }) as string | null
  if (id === null) return handback('the temper:temper-rca agent could not start')
  const ends = (yield { k: 'wait', ids: [id] }) as Record<string, AgentEnd>
  const ms = ends[id]?.ms ?? null
  const panel = yield* run(`${cli} panel rca .temper/specs/${s}/rca.md`)
  if (panel.code === 0) yield* show(panel.out)
  if ((yield* run(`${cli} state init ${s} --command fix`)).code !== 0) return handback('state init failed')
  yield* run(`${cli} usage add --stage rca --model ${model || 'unknown'} --ms ${ms === null ? 'none' : String(Math.round(ms))}`)
  // The fix branch, as commands/fix.md says: with the git pack on, off main or master.
  yield* run(`if grep -Eq '^packs:.*\\bgit\\b' .claude/temper.config 2>/dev/null; then case "$(git branch --show-current)" in main|master) git checkout -q -b ${shq(`fix/${s}`)} ;; esac; fi; true`)
  return yield* driveSteps(cli, null)
}

// The engine's side of one step: what it gives back to the core.
async function perform(port: Port, e: Effect): Promise<unknown> {
  switch (e.k) {
    case 'run': return port.run(e.call)
    case 'spawn': return port.spawn(e.agent)
    case 'wait': return port.wait(e.ids)
    case 'ask': return port.ask(e.q)
    case 'record': return port.record(e.q, e.answer)
    case 'show': return port.show(e.text)
    case 'stopped': return port.stopped()
  }
}

// The mod: each step awaited on the engine.
export async function drive(port: Port, cli: string, request: string | null, slug: string | null = null): Promise<DriveEnd> {
  return driveAll(port, driveSteps(cli, request, slug))
}
export async function driveFix(port: Port, cli: string, bug: string, slug: string | null = null): Promise<DriveEnd> {
  return driveAll(port, fixSteps(cli, bug, slug))
}
async function driveAll(port: Port, steps: Steps<DriveEnd>): Promise<DriveEnd> {
  let input: unknown = undefined
  for (;;) {
    const next = steps.next(input)
    if (next.done === true) return next.value
    input = await perform(port, next.value)
  }
}

// The e2e driver: the same core, each step done at once on its world.
export type SyncPort = {
  run(call: string): Ran
  spawn(agent: GoAgent): string | null
  wait(ids: string[]): Record<string, AgentEnd>
  ask(q: GoQuestion): string | null
  record(q: GoQuestion, answer: string): void
  show(text: string): void
}
export function driveSync(port: SyncPort, cli: string, request: string | null, slug: string | null = null): DriveEnd {
  return runSync(port, driveSteps(cli, request, slug))
}
export function driveFixSync(port: SyncPort, cli: string, bug: string, slug: string | null = null): DriveEnd {
  return runSync(port, fixSteps(cli, bug, slug))
}
function runSync(port: SyncPort, steps: Steps<DriveEnd>): DriveEnd {
  let input: unknown = undefined
  for (;;) {
    const next = steps.next(input)
    if (next.done === true) return next.value
    const e = next.value
    input = e.k === 'run' ? port.run(e.call) : e.k === 'spawn' ? port.spawn(e.agent) : e.k === 'wait' ? port.wait(e.ids)
      : e.k === 'ask' ? port.ask(e.q) : e.k === 'record' ? port.record(e.q, e.answer) : e.k === 'show' ? port.show(e.text) : false
  }
}
