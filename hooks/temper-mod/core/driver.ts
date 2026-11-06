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
  // Several questions in one dialog (up to four, as AskUserQuestion takes them); absent: asked one at a time.
  askAll?(qs: GoQuestion[]): Promise<Array<string | null>>
  record(q: GoQuestion, answer: string): Promise<void>
  show(text: string): Promise<void>
  stopped(): boolean
}
export type DriveEnd = { kind: 'done'; text: string } | { kind: 'handback'; args: string; why: string }

const MAX_TURNS = 300

export const STOPPED = 'Temper: stopped at your interrupt. The run is saved where the CLI shows it; an agent launched before it may ' +
  'still be finishing. /temper:temper takes the run up again.'

// The dialog's question, filled in: a mod's `$.ui.ask` raises the engine's AskUserQuestion with the labels alone, and the
// mod's tool.call hook gives each option back its description and preview (the Context check's table) from the CLI's
// question, so the person reads in the dialog itself what each choice does. Null when the call is not this question
// (another text, or other labels): it is then passed on as it is.
export function dialogQuestions(questions: unknown, q: GoQuestion): unknown[] | null {
  if (!Array.isArray(questions) || questions.length !== 1) return null
  const first = questions[0] as { question?: unknown; options?: unknown }
  if (first.question !== q.question || !Array.isArray(first.options)) return null
  const want = labelsOf(q)
  const opts = first.options as Array<Record<string, unknown>>
  if (opts.length !== want.length || opts.some((o, i) => o.label !== want[i])) return null
  return [{
    ...first,
    options: opts.map((o, i) => {
      const src = q.options[i]!
      const d = (src.description ?? '').trim()
      const p = src.preview ?? ''
      return { ...o, ...(d !== '' ? { description: d } : {}), ...(p.trim() !== '' ? { preview: p } : {}) }
    }),
  }]
}

// A Build task's gate run after its agent (`task gate N`): a failed verdict exits 1 and says what comes next (a retry,
// a stronger model, the group parked), and a gate refused because the group is parked names the park. Both are the
// CLI's verdict, which `temper go` turns into the next step or the person's question, never a call that broke.
export function taskVerdict(call: string, out: string): boolean {
  return / task gate \d+ /.test(` ${call} `) && (/^NEXT: /m.test(out) || /\bis parked\b/.test(out))
}

// A CLI panel (`temper panel ...`) as the few rows the driver shows. A mod's log line is one row with the plugin's name
// before it, and a dialog's preview cannot hold a panel of forty rows, so a box drawn row by row read as forty rows of
// "temper:". Each box becomes its title (joined with its one fact row, as a task's panel has), a row a fact row, and a
// row a section, its items joined; the lines outside the boxes (the Plan's diagram) give way to where they are.
export function compactPanel(text: string): string[] {
  const out: string[] = []
  const rule = /^\+[-+]*\+$/
  const sectionHead = /^\+--- (.+?) ---\+-*\+$/
  type Box = { title: string; facts: string[]; sections: Array<{ name: string; items: string[] }> }
  let box: Box | null = null
  let phase: 'title' | 'body' = 'title'
  let dropped = false
  const add = (to: string[], cell: string) => {
    if (/^ {2}\S/.test(cell) && to.length > 0) to[to.length - 1] += ' ' + cell.trim()
    else to.push(cell.trim())
  }
  const flush = (b: Box) => {
    const facts = b.facts.map(f => f.replace(/\s{3,}/g, ' · '))
    if (b.title !== '') out.push(facts.length === 1 ? `${b.title}. ${facts[0]}` : b.title)
    if (facts.length !== 1) out.push(...facts)
    for (const sct of b.sections) if (sct.items.length > 0) out.push(`${sct.name}: ${sct.items.join(' · ')}`)
  }
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trimEnd()
    const head = sectionHead.exec(line)
    if (box !== null && phase === 'body' && head !== null) {
      box.sections.push({ name: head[1] as string, items: [] })
      continue
    }
    if (rule.test(line)) {
      if (box === null) {
        box = { title: '', facts: [], sections: [] }
        phase = 'title'
      } else if (phase === 'title') {
        phase = 'body'
      } else {
        flush(box)
        box = null
      }
      continue
    }
    const row = box === null ? null : /^\| (.*?) *\|$/.exec(line)
    if (box !== null && row !== null) {
      const cell = row[1] as string
      if (phase === 'title') box.title = box.title === '' ? cell.trim() : `${box.title} ${cell.trim()}`
      else add(box.sections.length > 0 ? box.sections[box.sections.length - 1]!.items : box.facts, cell)
      continue
    }
    if (line.trim() !== '') dropped = true
  }
  if (box !== null) flush(box)
  if (dropped && out.some(l => l.startsWith('PLAN:'))) out.push("The plan's diagram is in plan.md, under Diagram.")
  return out.length > 0 ? out : text.split(/\r?\n/).filter(l => l.trim() !== '')
}

// A throw out of the driver. At the person's interrupt the engine aborts the child the driver was reading, and the read
// throws: that is the stop, with no model turn after it. Any other throw hands the run to the conversation, which takes
// it up from the CLI's state.
export function driverThrew(x: unknown, interrupted: boolean): DriveEnd {
  if (interrupted) return { kind: 'done', text: STOPPED }
  return { kind: 'handback', args: 'next', why: `the driver stopped: ${String(x).slice(0, 120)}` }
}

// A text as the rows `$.ui.log` can draw: one row a line (a line break inside a row is drawn as a mark), each at most
// 2000 characters (the terminal cuts a row there), trailing blank lines left out. A blank line inside stays a row of
// one space, so a report keeps its paragraphs.
export function logRows(text: string): string[] {
  const out: string[] = []
  for (const line of text.replace(/\s+$/, '').split(/\r?\n/)) {
    if (line.length === 0) out.push(' ')
    for (let i = 0; i < line.length; i += 2000) out.push(line.slice(i, i + 2000))
  }
  return out
}

// The dialog of several questions at once: `$.ui.ask` raises the first alone, and the mod's tool.call hook puts every one
// in, each with its options' descriptions and previews. Null when the call is not the first of them.
export function dialogQuestionsAll(questions: unknown, qs: GoQuestion[]): unknown[] | null {
  if (qs.length === 0 || !Array.isArray(questions) || questions.length !== 1) return null
  const first = questions[0] as { question?: unknown }
  if (first.question !== qs[0]!.question) return null
  return qs.slice(0, 4).map(q => ({
    question: q.question,
    header: q.header,
    multiSelect: false,
    options: q.options.slice(0, 4).map(o => {
      const d = (o.description ?? '').trim()
      const p = o.preview ?? ''
      return { label: o.label, description: d, ...(p.trim() !== '' ? { preview: p } : {}) }
    }),
  }))
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
  | { k: 'askAll'; qs: GoQuestion[] }
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
  const needs = opt.do ? opt.do.slice(0, 160)
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
  // A name question (who confirms a manual task): the person types it in the dialog; its own options only say to type
  // (asked again) or go back (Cancel).
  if (opt.answer_question && (opt.calls ?? []).some(c => c.includes('{answer}'))) {
    for (let k = 0; k < 3 && fills.answer === undefined; k++) {
      const typed = yield* ask(opt.answer_question)
      if (typed === null) return handback('nobody answered the name question')
      if (typed === 'Cancel') return yield* answer(cli, q, depth + 1)
      if (opt.answer_question.options.some(o => o.label === typed) || typed.trim() === '') continue
      yield { k: 'record', q: opt.answer_question, answer: typed }
      fills.answer = typed.trim()
    }
    if (fills.answer === undefined) return handback('no name was typed', `chose ${opt.label}`)
  }
  if ((opt.calls ?? []).some(c => [...c.matchAll(/\{([a-z_]+)\}/g)].some(m => !((m[1] as string) in fills)))) return handback('the option needs a value the driver does not have', `chose ${opt.label}`)
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
      // The Blocking questions in one dialog, four at most (the rest in the next), as the loop without the mod asks them:
      // a person answered six in six dialogs and asked why they did not come at once.
      const blocking = g.blocking ?? []
      for (let i = 0; i < blocking.length; i += 4) {
        const chunk = blocking.slice(i, i + 4)
        const picks = (yield { k: 'askAll', qs: chunk.map(b => b.question) }) as Array<string | null>
        for (let j = 0; j < chunk.length; j++) {
          const b = chunk[j] as GoBlocking
          const picked = picks[j] ?? null
          if (picked === null) return handback('nobody answered a Blocking question')
          const call = picked === 'Carry forward' ? b.carry : fill(b.answer, { answer: picked })
          if ((yield* run(call)).code !== 0) return handback('the answer call failed')
        }
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
          // What stopped a Build task agent is the one thing the CLI did not record: its own line, shown as it wrote it.
          const stoppedLines = end.text.split('\n').filter(l => /^\s*TASK \d+: stopped:/.test(l)).map(l => l.trim())
          if (stoppedLines.length > 0) yield* show(stoppedLines.join('\n'))
          for (const c of a.after ?? []) {
            const r = yield* run(fill(c, { ms: end.ms === null ? 'none' : String(Math.round(end.ms)) }))
            if (/ panel [a-z]+/.test(c) && r.code === 0) yield* show(compactPanel(r.out).join('\n'))
            if (r.code !== 0 && !(c === a.gate && r.out.includes('-> FAIL')) && !taskVerdict(c, r.out)) return handback(`an after call of the ${a.type} agent failed`)
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
  if (panel.code === 0) yield* show(compactPanel(panel.out).join('\n'))
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
    case 'askAll': return port.askAll ? port.askAll(e.qs) : askEach(port, e.qs)
    case 'record': return port.record(e.q, e.answer)
    case 'show': return port.show(e.text)
    case 'stopped': return port.stopped()
  }
}

async function askEach(port: Port, qs: GoQuestion[]): Promise<Array<string | null>> {
  const out: Array<string | null> = []
  for (const q of qs) {
    const a = await port.ask(q)
    out.push(a)
    if (a === null) break
  }
  return out
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
  askAll?(qs: GoQuestion[]): Array<string | null>
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
      : e.k === 'ask' ? port.ask(e.q) : e.k === 'askAll' ? (port.askAll ? port.askAll(e.qs) : e.qs.map(q => port.ask(q)))
      : e.k === 'record' ? port.record(e.q, e.answer) : e.k === 'show' ? port.show(e.text) : false
  }
}
