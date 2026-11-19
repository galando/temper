// The run driver (9.8.0, round 5): with the mod loaded, a /temper:temper run is carried by the mod itself, with no
// model in the main session. It runs `temper go` and the calls the CLI gives, launches the agents the CLI names with
// their type, model and prompt as given, asks the CLI's questions word for word and runs the calls of the answer the
// person picks. WP16: a run leaves it only for one step on a closed list of seven kinds (an option's or a step's
// `needs`: a skill to talk it through, the HTML review, the depth review, the config suggestions, a small change, a
// pull request, a CI fix), each one the person asked for by an option; the conversation does that step, and the
// person's next command takes the run up again. Everything else ends in the driver: a typed answer runs the question's
// `typed` calls; a failed call, a question nobody answered or a bound ends as a saved stop that says what stopped. The
// CLI holds the run, the driver holds nothing. Pure: the engine is reached through `Port`.

// 9.8.5: the CLI's ids. A question of `temper go` has its `id` and `kind` beside `question`; each option its `id`, and a
// `kind` when the driver acts on it (more, accept, cancel, carry, type). A question goes to the dialog exactly as given,
// so it holds no id: a reason, name or Blocking question has its ids beside it (`reason_ids`, `answer_ids`,
// `question_ids`), the ids of its options in the same order. The driver selects by kind; the label is only what the
// dialog returns, matched in one question.
export type GoQuestion = { header: string; question: string; options: Array<{ label: string; description?: string; preview?: string }>; multiSelect?: boolean }
export type GoIds = { id?: string; kind?: string; options: Array<{ id: string; kind?: string }> }
export type GoOption = {
  label: string
  id?: string
  kind?: string
  move?: string | null
  recommended?: boolean
  reason_ids?: GoIds
  answer_ids?: GoIds
  calls?: string[]
  steps?: string[]
  // WP16: the kind of each step beside `steps` (show-last, note, or "" for any other), as scripts/flow_base.py writes it
  step_kinds?: string[]
  do?: string
  stop?: boolean
  reason?: boolean
  reason_question?: GoQuestion
  answer_question?: GoQuestion
  // WP16: what the answer needs beyond its calls, a kind of NEEDS (scripts/flow_base.py)
  needs?: string
}
// WP16: the calls a typed answer runs, with the text in place of {text}; `again`: the same question comes after them
export type GoTyped = { calls: string[]; again?: boolean }
export type GoAsk = { id?: string; kind?: string; question: GoQuestion; options: GoOption[]; more?: GoAsk; accept?: GoAsk; typed?: GoTyped }
// WP16: the restart question of a run whose state cannot be read (`broken`), as `temper go` passes it
export type GoRestart = { header: string; question: string; id?: string; kind?: string; multiSelect?: boolean; options: Array<GoOption & { description?: string }> }
export type GoAgent = { type: string; model: string; prompt: string; before?: string[]; after?: string[]; gate?: string }
export type GoBlocking = { question: GoQuestion; question_ids?: GoIds; answer: string; carry: string }
export type GoOut = {
  action: string
  stage?: string
  say?: string
  agents?: GoAgent[]
  steps?: string[]
  step_kinds?: string[]
  ask?: GoAsk
  blocking?: GoBlocking[]
  gate?: string
  setup?: string[]
  tasks?: Array<{ after?: string[] }>
  // WP15: the rows of the question's card (the approval, the commit, a stop), as `temper card` prints them
  card?: string[]
  // WP16: steps that are the conversation's one step (a hand back kind) and the id of the option they came from
  needs?: string
  option?: string
  restart?: GoRestart
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
  // WP15: the card's rows, given once before the question is asked; absent: the card is not shown by the port.
  card?(rows: string[]): Promise<void>
  stopped(): boolean
}
// WP16: two ends. A hand back names the kind of the one step the conversation does (`needs`, one of HANDBACK_KINDS) and
// the id of the option the person picked; every other end is `done`, a saved stop whose text says what stopped.
export type DriveEnd = { kind: 'done'; text: string } | { kind: 'handback'; needs: string; option: string }

// The seven hand back kinds: NEEDS of scripts/flow_base.py but the three this driver does itself (more, accept,
// cancel).
export const HANDBACK_KINDS: readonly string[] = ['talk', 'html-review', 'depth-review', 'config-suggestions', 'small-change', 'pull-request', 'pipeline-fix']

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

// 9.8.5 (WP09): `gate <stage>`, `task gate <N>`, `group gate <G>` and `integrate` print one line once they recorded a
// verdict, `VERDICT: <scope> <PASS or FAIL or PARKED>`. The rule of `recorded` in scripts/go.py: the verdict when the
// call is one of the four and the last marker line of its output names the call's scope (a task gate's own task, or any
// group: a parked group refuses it); else null. Such a call is no failure whatever its exit code: `temper go` asks
// next. The marker decides only that the driver goes on; what comes next is always the CLI's.
export function recordedVerdict(call: string, out: string): 'PASS' | 'FAIL' | 'PARKED' | null {
  const c = /^(?:\S*\/)?temper (?:gate ([a-z]+)|task gate (\d+)|group gate (G\d+)|(integrate))(?:\s|$)/
    .exec(call.trim())
  if (c === null) return null
  const want = c[1] !== undefined ? `gate:${c[1]}`
    : c[2] !== undefined ? `task:${c[2]}`
    : c[3] !== undefined ? `group:${c[3]}` : 'integrate'
  const marks = [...out.matchAll(/^VERDICT: (\S+) (PASS|FAIL|PARKED)$/gm)]
  const last = marks[marks.length - 1]
  if (last === undefined) return null
  const scope = last[1] as string
  const verdict = last[2] as 'PASS' | 'FAIL' | 'PARKED'
  const group = /^group:G\d+$/.test(scope)
  if (verdict === 'PARKED' && !group) return null
  return scope === want || (want.startsWith('task:') && group) ? verdict : null
}

// A CLI panel (`temper panel ...`) as the few rows the driver shows. A mod's log line is one row with the plugin's name
// before it, and a dialog's preview cannot hold a panel of forty rows, so a box drawn row by row read as forty rows of
// "temper:". Each box becomes its title (joined with its one fact row, as a task's panel has), a row a fact row, and a
// row a section, its items joined; the lines outside the boxes give way (WP15: the Plan panel and its diagram
// are gone).
export function compactPanel(text: string): string[] {
  const out: string[] = []
  const rule = /^\+[-+]*\+$/
  const sectionHead = /^\+--- (.+?) ---\+-*\+$/
  type Box = { title: string; facts: string[]; sections: Array<{ name: string; items: string[] }> }
  let box: Box | null = null
  let phase: 'title' | 'body' = 'title'
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
  }
  if (box !== null) flush(box)
  return out.length > 0 ? out : text.split(/\r?\n/).filter(l => l.trim() !== '')
}

// A throw out of the driver. At the person's interrupt the engine aborts the child the driver was reading, and the read
// throws: that is the stop, with no model turn after it. Any other throw is a defect: a saved stop with its reason.
export function driverThrew(x: unknown, interrupted: boolean): DriveEnd {
  if (interrupted) return { kind: 'done', text: STOPPED }
  return saved(`the driver stopped on a defect (${String(x).slice(0, 160)})`)
}

// WP16: a saved stop. Its text starts with what stopped, so it never reads as success; the run is where the CLI says.
const SAVED_PREFIX = 'Temper stopped: '
export function saved(what: string): DriveEnd {
  return { kind: 'done', text: `${SAVED_PREFIX}${what}. The run is saved where the CLI shows it; /temper:temper takes it up again (/temper:fix for a fix run).` }
}
export const isSavedStop = (end: DriveEnd): boolean => end.kind === 'done' && end.text.startsWith(SAVED_PREFIX)

// The line of a failed call's output that says why: the CLI's own FAIL line, else its first line, else the exit code.
export function failLine(r: Ran): string {
  const lines = r.out.split('\n').map(l => l.trim()).filter(l => l !== '')
  return (lines.find(l => /^FAIL\b/.test(l)) ?? lines[0] ?? `exit ${r.code}`).slice(0, 300)
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

// What the driver does with one `steps` entry: a CLI call it runs; by the step's kind (`step_kinds`, WP16), the report
// it shows or a note; anything else is the conversation's, and the action's `needs` says which kind of step it is.
export function stepPlan(step: string, cli: string, kind = ''): StepPlan {
  const s = step.trim()
  if (s.startsWith(cli + ' ') && !/\{[a-z_]+\}/.test(s)) return { kind: 'run', call: s }
  if (kind === 'show-last') return { kind: 'show-last' }
  if (kind === 'note') return { kind: 'note', text: s }
  return { kind: 'handback', why: s.slice(0, 160) }
}
// The plan of each step of an action or an option, with its kind.
const plansOf = (x: { steps?: string[]; step_kinds?: string[] }, cli: string): StepPlan[] =>
  (x.steps ?? []).map((st, i) => stepPlan(st, cli, x.step_kinds?.[i] ?? ''))

// A question the driver asks with the labels the CLI gave: at most four (the CLI puts the rest under More options).
export const labelsOf = (q: GoQuestion): string[] => q.options.map(o => o.label).slice(0, 4)

function optionOf(ask: GoAsk, label: string): GoOption | undefined {
  return ask.options.find(o => o.label === label)
}

// The kind of the option the person picked in a dialog question (a reason, name or Blocking question): the label the
// dialog returns finds its place in the question, and the ids beside the question give that place's kind; undefined for
// a typed answer.
const kindOf = (q: GoQuestion, ids: GoIds | undefined, label: string): string | undefined => {
  const i = q.options.findIndex(o => o.label === label)
  return i < 0 ? undefined : ids?.options[i]?.kind
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
  | { k: 'card'; rows: string[] }
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

// The calls of an answer, in order: null when they all ran (a call that recorded a verdict did, whatever its exit
// code), else the failed call's FAIL line.
function* runAll(calls: string[], fills: Record<string, string>): Steps<string | null> {
  for (const c of calls) {
    const r = yield* run(fill(c, fills))
    if (r.code !== 0 && recordedVerdict(fill(c, fills), r.out) === null) return failLine(r)
  }
  return null
}

// An agent's before calls: null when they all ran, else the CLI's FAIL line of the one that failed.
function* runBefore(calls: string[]): Steps<string | null> {
  for (const c of calls) {
    const r = yield* run(fill(c, {}))
    if (r.code !== 0) return `a before call failed: ${failLine(r)}`
  }
  return null
}

// The one hand back: an option or a step whose `needs` is a kind of the closed list leaves the driver with that kind
// and the option's id; any other needs, or a step or a `do` text with none, is a saved stop.
const handback = (needs: string, option: string): DriveEnd => ({ kind: 'handback', needs, option })
function leave(needs: string | undefined, option: string, what: string): DriveEnd {
  return needs !== undefined && HANDBACK_KINDS.includes(needs) ? handback(needs, option) : saved(`${what} needs ${needs ? `a ${needs} step` : 'a step'} the run driver does not carry`)
}

// The name question is asked until a name is typed or Cancel; this many asks at most.
const NAME_ASKS = 20

// One question of the CLI, asked as given; the option's calls run with the person's answer. Returns null when it went on,
// or how the drive ends. `back` is the gate question a More or accept question came from: a Cancel asks that one again.
function* answer(cli: string, q: GoAsk, depth = 0, back: GoAsk | null = null): Steps<DriveEnd | null> {
  if (depth > 6) return saved('the question went round more than six times')
  const picked = yield* ask(q.question)
  if (picked === null) return saved('nobody answered the question')
  const opt = optionOf(q, picked)
  if (opt === undefined) {
    // A typed answer is a change request by rule: the question's typed calls carry it (a note for the next agent, and
    // at a stage that writes the work, the stage run again with it), then the CLI says what comes next.
    const typed = q.typed?.calls ?? []
    if (typed.length === 0 || picked.trim() === '') return saved('a typed answer, at a question that takes none')
    const failed = yield* runAll(typed, { text: picked.trim() })
    return failed === null ? null : saved(`a call of your typed answer failed: ${failed}`)
  }
  yield { k: 'record', q: q.question, answer: picked }
  const nav = opt.kind ?? opt.needs
  // The More question holds the options past the fourth (the review's Accept a finding among them); the accept question
  // the CLI writes on the gate question is its too, and its Cancel asks the gate question again.
  if (nav === 'more' && q.more) return yield* answer(cli, { ...q.more, accept: q.more.accept ?? q.accept }, depth + 1, back ?? q)
  if (nav === 'accept' && q.accept) return yield* answer(cli, q.accept, depth + 1, back ?? q)
  if (nav === 'cancel' && back !== null) return yield* answer(cli, back, depth + 1)
  // What the conversation carries out (a skill, the HTML review, a small change, a pull request, a CI fix): nothing of
  // it runs here; the conversation runs it whole, as the answer the person already gave.
  const step = plansOf(opt, cli).some(p => p.kind === 'handback')
  if (opt.needs !== undefined || opt.do !== undefined || step) return leave(opt.needs, opt.id ?? opt.label, `the option ${opt.label}`)
  const fills: Record<string, string> = {}
  if (opt.reason_question && (opt.calls ?? []).some(c => c.includes('{reason}'))) {
    const r = yield* ask(opt.reason_question)
    if (r === null) return saved('nobody answered the reason question')
    if (kindOf(opt.reason_question, opt.reason_ids, r) === 'cancel') return yield* answer(cli, q, depth + 1, back)
    yield { k: 'record', q: opt.reason_question, answer: r }
    fills.reason = r
  }
  // A name question (who confirms a manual task, a change typed for a group): the person types it in the dialog; its
  // own options only say to type (asked again) or go back (Cancel).
  if (opt.answer_question && (opt.calls ?? []).some(c => c.includes('{answer}'))) {
    for (let k = 0; fills.answer === undefined; k++) {
      if (k >= NAME_ASKS) return saved(`no answer was typed in ${NAME_ASKS} asks`)
      const typed = yield* ask(opt.answer_question)
      if (typed === null) return saved('nobody answered the name question')
      if (kindOf(opt.answer_question, opt.answer_ids, typed) === 'cancel') return yield* answer(cli, q, depth + 1, back)
      if (opt.answer_question.options.some(o => o.label === typed) || typed.trim() === '') continue
      yield { k: 'record', q: opt.answer_question, answer: typed }
      fills.answer = typed.trim()
    }
  }
  if ((opt.calls ?? []).some(c => [...c.matchAll(/\{([a-z_]+)\}/g)].some(m => !((m[1] as string) in fills)))) return saved(`the option ${opt.label} needs a value no question asked`)
  const failed = yield* runAll(opt.calls ?? [], fills)
  if (failed !== null) return saved(`a call of your answer failed: ${failed}`)
  for (const p of plansOf(opt, cli)) {
    if (p.kind === 'run') {
      const r = yield* run(p.call)
      if (r.code !== 0) return saved(`a step of your answer failed: ${failLine(r)}`)
    } else if (p.kind === 'note') yield* show(p.text)
  }
  if (opt.stop) return { kind: 'done', text: `Temper: ${opt.label}. The run is saved; /temper:temper takes it up again.` }
  return null
}

// WP16: `broken` asks the CLI's restart question (run.restart): Start over runs its calls and the run goes on from what
// the CLI says next; Cancel, or no answer, keeps the run as it is, a saved stop.
function* restart(g: GoOut): Steps<DriveEnd | null> {
  const r = g.restart
  if (!r || !Array.isArray(r.options)) return saved(`the run state cannot be read (${g.say ?? 'broken'})`)
  const q: GoQuestion = { header: r.header, question: r.question, multiSelect: false, options: r.options.map(o => ({ label: o.label, description: o.description ?? '' })) }
  const picked = yield* ask(q)
  const opt = picked === null ? undefined : r.options.find(o => o.label === picked)
  if (opt === undefined || opt.move !== 'restart') return saved(`the run state cannot be read (${g.say ?? 'broken'}), and the run was kept`)
  yield { k: 'record', q, answer: opt.label }
  const failed = yield* runAll(opt.calls ?? [], {})
  return failed === null ? null : saved(`a call of Start over failed: ${failed}`)
}

export function* driveSteps(cli: string, request: string | null, slug: string | null = null): Steps<DriveEnd> {
  let started = false
  // WP11: a drive with no request takes the run up again: its first `temper go` passes --taken-up, so a run that goes on
  // by itself records a stop and its stage asks the person once
  let takenUp = request === null
  let waits = 0
  let lastAfter = ''
  for (let turn = 0; turn < MAX_TURNS; turn++) {
    // The person interrupted: stop here, with no model turn they did not ask for. The CLI holds the run.
    if (yield* stopped()) return { kind: 'done', text: STOPPED }
    const g = parseGo((yield* run(takenUp ? `${cli} go --taken-up` : `${cli} go`)).out)
    takenUp = false
    if (g === null) return saved('temper go gave no action')
    for (const c of g.setup ?? []) {
      const r = yield* run(c)
      if (r.code !== 0) yield* show(`Temper: a setup call failed (${c.split('/').pop()}): ${r.out.trim().split('\n').slice(-3).join(' ')}`)
    }
    if (g.action === 'none') {
      if (!started && request !== null) {
        const init = yield* run(`${cli} state init ${slug ?? slugOf(request)} --feature ${shq(request)}`)
        if (init.code !== 0) return saved(`the run could not start: ${failLine(init)}`)
        started = true
        continue
      }
      return { kind: 'done', text: g.say || 'Temper: the run is done.' }
    }
    if (g.action === 'error') return saved(g.say || 'temper go failed')
    if (g.action === 'broken') {
      const end = yield* restart(g)
      if (end !== null) return end
      continue
    }
    if (g.say) yield* show(g.say)
    if (g.action === 'wait') {
      // Tasks started in an earlier conversation (the driver waits on its own agents before it asks again): their after
      // calls run now, as the command page says. With none to run, wait a little and ask again, up to ten minutes.
      // Each look counts toward the same bound; the same after calls asked for again changed nothing, and are not run twice.
      const after = (g.tasks ?? []).flatMap(t => t.after ?? [])
      if (++waits > 120) return saved('the run waited on its tasks for more than 120 looks')
      if (after.length > 0) {
        const key = after.join('\n')
        if (key === lastAfter) return saved('the after calls of the waiting tasks changed nothing')
        lastAfter = key
        // A failed after call stops the run saved with the CLI's FAIL line, as an agent's after call does.
        for (const c of after) {
          const r = yield* run(fill(c, { ms: 'none' }))
          if (r.code !== 0 && recordedVerdict(c, r.out) === null) return saved(`an after call of a waiting task failed: ${failLine(r)}`)
        }
        continue
      }
      yield { k: 'wait', ids: [] }
      continue
    }
    waits = 0
    lastAfter = ''
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
          if (picked === null) return saved('nobody answered a Blocking question')
          const call = kindOf(b.question, b.question_ids, picked) === 'carry' ? b.carry : fill(b.answer, { answer: picked })
          const r = yield* run(call)
          if (r.code !== 0) return saved(`the call of your answer failed: ${failLine(r)}`)
        }
      }
      if ((g.blocking ?? []).length > 0) {
        // The answers are in intent.md: the action's gate call reads them (a FAIL is a verdict, the next question's).
        if (g.gate) yield* run(g.gate)
        continue
      }
      if (!g.ask) return saved('temper go gave a question with no question')
      if ((g.card ?? []).length > 0) yield { k: 'card', rows: g.card as string[] }
      const end = yield* answer(cli, g.ask)
      if (end !== null) return end
      continue
    }
    if (g.action === 'work') {
      const agents = g.agents ?? []
      if (agents.length > 0) {
        // Every agent's before calls (a Build task's `task start`) run before any agent starts. When one fails, the
        // agents whose calls ran start and are followed to their after calls, and only then does the run stop (9.8.0:
        // a run once left Task 1's agent running with nobody to follow it).
        if (yield* stopped()) return { kind: 'done', text: STOPPED }
        const ids: Array<[string, GoAgent]> = []
        const ready: GoAgent[] = []
        let failed: string | null = null
        for (const a of agents) {
          failed = yield* runBefore(a.before ?? [])
          if (failed !== null) break
          ready.push(a)
        }
        for (const a of ready) {
          const id = (yield { k: 'spawn', agent: a }) as string | null
          if (id === null) {
            failed = `the ${a.type} agent could not start`
            break
          }
          ids.push([id, a])
        }
        if (ids.length === 0) return saved(failed ?? 'no agent started')
        const ends = (yield { k: 'wait', ids: ids.map(([id]) => id) }) as Record<string, AgentEnd>
        for (const [id, a] of ids) {
          const end = ends[id] ?? { text: '', ms: null }
          // What stopped a Build task agent is the one thing the CLI did not record: its own line, shown as it wrote it.
          const stoppedLines = end.text.split('\n').filter(l => /^\s*TASK \d+: stopped:/.test(l)).map(l => l.trim())
          if (stoppedLines.length > 0) yield* show(stoppedLines.join('\n'))
          for (const c of a.after ?? []) {
            const r = yield* run(fill(c, { ms: end.ms === null ? 'none' : String(Math.round(end.ms)) }))
            if (/ panel [a-z]+/.test(c) && r.code === 0) yield* show(compactPanel(r.out).join('\n'))
            if (r.code !== 0 && recordedVerdict(c, r.out) === null) return saved(`an after call of the ${a.type} agent failed: ${failLine(r)}`)
          }
        }
        if (failed !== null) return saved(failed)
      }
      // Steps only the conversation can do (a pull request): the conversation runs them all, before any of them runs
      // here, so none is left half done; the action's `needs` names the kind of that one step.
      if (plansOf(g, cli).some(p => p.kind === 'handback')) return leave(g.needs, g.option ?? '', 'the next step')
      let last = ''
      for (const p of plansOf(g, cli)) {
        if (yield* stopped()) return { kind: 'done', text: STOPPED }
        if (p.kind === 'run') {
          const r = yield* run(p.call)
          if (r.code !== 0) return saved(`a step failed: ${failLine(r)}`)
          last = r.out
        } else if (p.kind === 'show-last') yield* show(last)
        else if (p.kind === 'note') yield* show(p.text)
      }
      continue
    }
    return saved(`temper go gave an action the driver does not know (${g.action})`)
  }
  return saved(`the run did not end in ${MAX_TURNS} turns`)
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
// cause agent, the run's state with the bug as typed), then the same loop as /temper. WP17: no shell line and no panel:
// the approval card shows rca.md, and the approving option makes the fix branch (`spec branch --if-protected`).
// With a run active it starts nothing: a saved stop that says so (the person's command with no words takes it up).
export function* fixSteps(cli: string, bug: string, slug: string | null = null): Steps<DriveEnd> {
  const plugin = cli.replace(/\/scripts\/temper$/, '')
  const s = slug ?? fixSlug(bug)
  const g = parseGo((yield* run(`${cli} go`)).out)
  if (g === null) return saved('temper go gave no action')
  for (const c of g.setup ?? []) {
    const r = yield* run(c)
    if (r.code !== 0) yield* show(`Temper: a setup call failed (${c.split('/').pop()}): ${r.out.trim().split('\n').slice(-3).join(' ')}`)
  }
  if (g.action !== 'none') return saved('a run is active, so the fix starts no new one')
  const model = ((yield* run(`${cli} model rca`)).out.trim().split('\n').pop() ?? '').trim()
  const agent: GoAgent = { type: 'temper:temper-rca', model, prompt: rcaPrompt(plugin, bug, s) }
  yield* show(`RCA: the root cause agent is working${model ? ` on ${model}` : ''}. The run goes on when it returns.`)
  const id = (yield { k: 'spawn', agent }) as string | null
  if (id === null) return saved('the temper:temper-rca agent could not start')
  const ends = (yield { k: 'wait', ids: [id] }) as Record<string, AgentEnd>
  const ms = ends[id]?.ms ?? null
  const init = yield* run(`${cli} state init ${s} --command fix --feature ${shq(bug)}`)
  if (init.code !== 0) return saved(`the fix run could not start: ${failLine(init)}`)
  yield* run(`${cli} usage add --stage rca --model ${model || 'unknown'} --ms ${ms === null ? 'none' : String(Math.round(ms))}`)
  return yield* driveSteps(cli, null)
}

// The looks (two seconds apart) an ended agent's answer is waited for before the driver goes on without it.
export const ANSWER_LOOKS = 3

// One look at the agents the driver waits on: an agent whose answer is recorded (its turn.complete) is done with it; one
// whose status says it ended with no answer recorded yet is looked at again, ANSWER_LOOKS times, before it is done
// with no answer (its status can change before its turn.complete reaches the mod, and that answer is what the driver
// reads: a DRIFT row, a stopped task). Fills `out`, counts the looks in `unanswered`; returns how many are still open.
export function lookAtAgents(ids: readonly string[], ends: ReadonlyMap<string, AgentEnd>, list: ReadonlyArray<{ id: string; status: string }>,
  unanswered: Record<string, number>, out: Record<string, AgentEnd>): number {
  let open = 0
  for (const id of ids) {
    if (id in out) continue
    const kept = ends.get(id)
    const info = list.find(x => x.id === id)
    if (kept !== undefined) out[id] = kept
    else if (info !== undefined && info.status !== 'running' && info.status !== 'pending' && (unanswered[id] = (unanswered[id] ?? 0) + 1) > ANSWER_LOOKS) out[id] = { text: '', ms: null }
    else open++
  }
  return open
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
    case 'card': return port.card ? port.card(e.rows) : undefined
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
// At the person's interrupt every step ends STOPPED, whichever step saw it: a call the engine aborted reads as exit 130,
// and a dialog closed by it as no answer, and neither is a call that failed or a question nobody answered, which would
// hand the run to a model turn the person did not ask for.
async function driveAll(port: Port, steps: Steps<DriveEnd>): Promise<DriveEnd> {
  let input: unknown = undefined
  for (;;) {
    const next = steps.next(input)
    if (next.done === true) return next.value
    input = await perform(port, next.value)
    if (port.stopped()) return { kind: 'done', text: STOPPED }
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
  card?(rows: string[]): void
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
      : e.k === 'record' ? port.record(e.q, e.answer) : e.k === 'show' ? port.show(e.text)
      : e.k === 'card' ? port.card?.(e.rows) : false
  }
}
