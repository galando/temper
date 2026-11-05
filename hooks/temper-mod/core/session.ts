// The main session's own calls while a /temper run is active (9.8.0). The session relays: it runs the temper CLI and
// reads, launches the agent the CLI names, and asks the question the CLI gives; the stage agents and the CLI change the
// files. Each rule here is deterministic, so a cheaper model for the session cannot leave the script. Round 4 of the
// benchmark (docs/evidence/bench-2026-11.md) is why: a Haiku session edited design.md and tasks.md itself, went into a
// task worktree, changed code at Review, edited the locked acceptance tests and asked the person a question of its own,
// and a Sonnet session once launched an agent on a cheaper model than the CLI named. Pure.
//
// Only the main session is judged here; an agent's calls carry its agent id and keep their stage rules (rules.ts).
// Two openings are the person's: a small change window (`temper adhoc open`, their choice at a question) lets the
// session write by the stage's rules, and a skill they chose at a question (Grill Me, Teach Me) asks its own questions.
// A Bash call the CLI wrote whole (a setup call, a commit step, the calls of the person's answer) passes as written.
// Like the rest of the guard this is not a sandbox (docs/trust.md): it reads what a command names, not what it does.

import type { RuleContext, RuleResult, ToolCall } from './rules'
import { DRIFT_HEADER, DRIFT_PREFIX } from './rules'
import type { Ask, Option, Question, RunView } from './runview'
import { isScript, noteScriptVar, readShell, scriptViaVar, statements } from './shell'

// What the CLI's view says the session may do at this step.
export type SessionFacts = {
  // The agents of the CLI's current action, each as it is to be launched.
  agents: ReadonlyArray<{ type: string; model: string; prompt: string }>
  // Every question the CLI gives at this step: its header, its text and its option labels in order. A header of null
  // matches any: a Blocking question's header (`Question N`) counts the questions still open, so it changes as answers
  // are recorded, and it decides nothing (the answer is written by its own call).
  questions: ReadonlyArray<{ header: string | null; question: string; labels: readonly string[] }>
  // A skill the person chose at a question of this step is being carried out: its own questions pass.
  skill: boolean
}

// The facts of a view: its agents, and every question of this step (the gate question with its More options and Accept a
// finding questions, each option's reason and name questions, the Context check, the Temper resume question and the
// Blocking questions). `skill`: the person chose a skill option at this step (register.tsx keeps that).
// The view names the agents the session may launch: a work action's, and while the run waits on them at the same stage,
// the ones it named before (a Build task's `task start` turns the action into `wait` before the launch). The mod keeps no
// memory of its own for this: it is loaded again between turns.
export function factsOf(view: RunView | null, skill: boolean): SessionFacts {
  if (view === null) return { agents: [], questions: [], skill }
  const qs: Array<{ header: string | null; question: string; labels: string[] }> = []
  const put = (q: Question | null, anyHeader = false) => {
    if (q !== null) qs.push({ header: anyHeader ? null : q.header, question: q.question, labels: q.options.map(o => o.label) })
  }
  const opts = (os: readonly Option[]) => os.forEach(o => (put(o.reasonQuestion), put(o.answerQuestion)))
  const walk = (a: Ask | null) => {
    if (a === null) return
    put(a.question)
    opts(a.options)
    walk(a.more)
    walk(a.accept)
  }
  walk(view.ask)
  walk(view.contextCheck?.ask ?? null)
  if (view.restart !== null) {
    qs.push({ header: view.restart.header, question: view.restart.question, labels: view.restart.options.map(o => o.label) })
    opts(view.restart.options)
  }
  view.blockingAsks.forEach(q => put(q, true))
  return { agents: view.next.action === 'work' || view.next.action === 'wait' ? view.next.agents : [], questions: qs, skill }
}

// The skill a chosen option carries out, when the dialog's answer picked one of this view's options that has one.
export function skillChosen(view: RunView | null, result: unknown): string | null {
  if (view === null) return null
  const r = (result && typeof result === 'object' ? (result as { result?: unknown }).result : undefined) as { answers?: unknown } | undefined
  const answers = r && r.answers && typeof r.answers === 'object' ? Object.values(r.answers as Record<string, unknown>) : []
  const all: Option[] = []
  const walk = (a: Ask | null) => {
    if (a === null) return
    all.push(...a.options)
    walk(a.more)
    walk(a.accept)
  }
  walk(view.ask)
  for (const answer of answers) {
    const o = all.find(x => x.label === answer && x.skill !== null)
    if (o !== undefined) return o.skill
  }
  return null
}

const ALLOW: RuleResult = { allow: true }
const WRITE_TOOLS = new Set(['Write', 'Edit', 'MultiEdit', 'NotebookEdit'])
const AGENT_TOOLS = new Set(['Agent', 'Task'])

export const SESSION_WRITE_DENY =
  'Temper: during a run this conversation does not write files; the stage agents and the temper CLI do. ' +
  'Next: run temper go and do what it says. A change the user asks for is their note, and the stage runs again with it (commands/temper.md, Typed text).'

export const SESSION_BASH_DENY = (what: string): string =>
  `Temper: during a run this conversation runs the temper CLI and commands that only read; ${what}. ` +
  'Next: run temper go and do what it says (a step it lists is run as written).'

export const SESSION_AGENT_DENY =
  'Temper: launch only the agent temper go names, with its type, its model and its prompt exactly as given. ' +
  'Next: run temper go and launch each agent of its action as given.'

export const SESSION_ASK_DENY =
  'Temper: ask only a question the CLI gives (its header, its question and its options, exactly as given), or a Scope drift question for a DRIFT row. ' +
  'Next: run temper go and ask its question as given.'

// Programs that only read (or change the folder of the call): their words are read for what they name.
const READERS = new Set([
  'cat', 'head', 'tail', 'ls', 'wc', 'grep', 'egrep', 'fgrep', 'rg', 'find', 'sed', 'sort', 'uniq', 'cut', 'tr', 'diff',
  'cmp', 'pwd', 'echo', 'printf', 'true', 'false', 'test', '[', 'date', 'basename', 'dirname', 'realpath', 'readlink',
  'jq', 'stat', 'file', 'tree', 'nl', 'column', 'fold', 'cd', 'which', 'type', 'md5sum', 'sha256sum', 'shasum', ':',
  'export', 'unset', 'set', 'exit', 'return', 'sleep',
])
// The git subcommands that only read.
const GIT_READS = new Set(['status', 'log', 'diff', 'show', 'rev-parse', 'ls-files', 'describe', 'blame', 'merge-base', 'cat-file',
  'show-ref', 'for-each-ref', 'shortlog', 'grep', 'rev-list', 'name-rev'])
// Words that start or join a statement before its program (`if`, `then`, `!`), or a statement that runs none.
const PREFIX = new Set(['if', 'then', 'elif', 'else', 'while', 'until', 'do', '!', '{', 'time'])
const HEADER = new Set(['for', 'select', 'case', 'done', 'fi', 'esac', '}', 'in'])
const ASSIGNMENT = /^[A-Za-z_][A-Za-z0-9_]*\+?=/
const REDIRECT = /^(?:>|>>|>\||&>|&>>|>&|<|<<|<<<|<>)$/
const DEVICES = new Set(['/dev/null', '/dev/stdout', '/dev/stderr'])

const base = (w: string): string => (w.split('/').pop() ?? '').toLowerCase()

// Why a statement is not one the session may run, or null when it may.
function statementWhy(words: readonly string[], publish: boolean, cliVars: ReadonlySet<string> = new Set()): string | null {
  let i = 0
  while (i < words.length && (ASSIGNMENT.test(words[i] as string) || PREFIX.has(words[i] as string))) i++
  const first = words[i]
  if (first === undefined || HEADER.has(first)) return null
  if (isScript(first) || scriptViaVar(first, cliVars)) return null
  const name = base(first)
  const rest = words.slice(i + 1).filter(w => !REDIRECT.test(w))
  if (publish && name === 'gh') return null
  if (name === 'git') {
    // git's own options before the subcommand (`-C dir`, `--no-pager`) are read past.
    let k = 0
    while (k < rest.length && (rest[k] as string).startsWith('-')) k += rest[k] === '-C' || rest[k] === '-c' ? 2 : 1
    const sub = rest[k] ?? ''
    const args = rest.slice(k + 1)
    if (GIT_READS.has(sub)) return null
    if (publish && (sub === 'push' || sub === 'fetch' || sub === 'remote')) return null
    if (sub === 'branch' && args.every(a => ['--show-current', '--list', '-a', '-r', '-v', '-vv', '--all'].includes(a))) return null
    if (sub === 'config' && args.some(a => ['--get', '--get-all', '--get-regexp', '--list', '-l'].includes(a))) return null
    if (sub === 'remote' && args.every(a => a === '-v')) return null
    if (sub === 'worktree' && args[0] === 'list') return null
    return `git ${sub || '(no subcommand)'} changes the repository`
  }
  // Any other program named by a variable: the guard cannot tell what runs (the CLI set in the same command, as
  // `T=/p/scripts/temper`, is read above as the CLI).
  if (first.startsWith('$')) return `${first} names the program through a variable: write the CLI's path out in full in every call`
  if (!READERS.has(name)) return `${name} is not the CLI and not a command that only reads`
  if (name === 'find' && rest.some(w => ['-exec', '-execdir', '-ok', '-okdir', '-delete', '-fprint', '-fprint0', '-fprintf', '-fls'].includes(w))) return 'find with an action that runs or writes'
  if (name === 'sed' && rest.some(w => w === '--in-place' || w.startsWith('--in-place=') || /^-[a-zA-Z]*i/.test(w))) return 'sed -i writes the file'
  if (name === 'sort' && rest.some(w => w === '-o' || w.startsWith('-o') || w.startsWith('--output'))) return 'sort -o writes a file'
  return null
}

// Why a Bash command is not one the session may run, or null when it may.
export function bashWhy(command: string, publish = false): string | null {
  const read = readShell(command)
  const writes = [...read.writes, ...read.targets, ...read.landings].filter(p => !DEVICES.has(p))
  if (writes.length > 0) return `it writes ${writes[0]}`
  const cliVars = new Set<string>()
  for (const st of statements(command)) {
    noteScriptVar(st, cliVars)
    const why = statementWhy(st, publish, cliVars)
    if (why !== null) return why
  }
  return null
}

// The family of a model name (`claude-opus-5-5`, `opus`), or the name itself.
const family = (m: string): string => {
  const f = ['opus', 'sonnet', 'haiku', 'fable'].find(x => m.toLowerCase().includes(x))
  return f ?? m.trim().toLowerCase()
}
const prompt = (p: unknown): string => (typeof p === 'string' ? p.replace(/[ \t]+$/gm, '').trim() : '')

// Why a launch is none of the CLI's agents (the part that differs from the closest one), or null when it is one.
export function agentWhy(input: Record<string, unknown>, facts: SessionFacts): string | null {
  const type = typeof input.subagent_type === 'string' ? input.subagent_type : typeof input.subagentType === 'string' ? input.subagentType : ''
  const model = typeof input.model === 'string' ? input.model : ''
  if (facts.agents.length === 0) return 'the CLI names no agent to launch now'
  const why = facts.agents.map(a => {
    // The general purpose agent stands in where the CLI's agent type is not offered (commands/temper.md); its prompt then
    // names the brief, and the model and the prompt still have to be the CLI's.
    if (!(type === a.type || type === '' || type === 'general-purpose')) return `the type is ${type}, the CLI names ${a.type}`
    if (!(a.model === '' || family(model) === family(a.model))) return `the model is ${model}, the CLI names ${a.model}`
    if (prompt(input.prompt) !== prompt(a.prompt)) return `the prompt differs from the one the CLI gives for ${a.type}`
    return null
  })
  return why.includes(null) ? null : (why.find(w => w !== null && !w.startsWith('the type')) ?? why[0] ?? null)
}

function questionFits(q: unknown, facts: SessionFacts): boolean {
  const x = (q && typeof q === 'object' ? q : {}) as { header?: unknown; question?: unknown; options?: unknown }
  const header = typeof x.header === 'string' ? x.header : ''
  const text = typeof x.question === 'string' ? x.question : ''
  const labels = Array.isArray(x.options) ? x.options.map(o => (o && typeof o === 'object' && typeof (o as { label?: unknown }).label === 'string' ? (o as { label: string }).label : '')) : []
  if (header === DRIFT_HEADER && text.startsWith(DRIFT_PREFIX)) return true
  return facts.questions.some(f => (f.header === null || f.header === header) && f.question === text && f.labels.length === labels.length && f.labels.every((l, i) => l === labels[i]))
}

// The main session's call: allowed, or denied with what to do instead. `ctx` is the rule context of rules.ts; the
// stage rules there have already passed the call.
export function evaluateSession(ctx: RuleContext, facts: SessionFacts, call: ToolCall): RuleResult {
  const r = ctx.run
  if (r === null) return ALLOW
  const adhoc = r.adhocStage != null && r.adhocStage === r.stage
  if (WRITE_TOOLS.has(call.tool)) return adhoc ? ALLOW : { deny: SESSION_WRITE_DENY }
  if (call.tool === 'Bash') {
    const command = typeof call.input.command === 'string' ? call.input.command : ''
    // A command the CLI wrote whole (a setup call, a commit step, the calls of the person's answer), as written.
    if (ctx.allowed.some(written => written === command.trim())) return ALLOW
    if (adhoc) return ALLOW
    // At the commit and after it (Pipeline), the steps of a pull request push and open it (reference/pr.md).
    const why = bashWhy(command, r.stage === 'commit' || r.stage === 'pipeline')
    return why === null ? ALLOW : { deny: SESSION_BASH_DENY(why) }
  }
  if (AGENT_TOOLS.has(call.tool)) {
    const why = agentWhy(call.input, facts)
    return why === null ? ALLOW : { deny: `${SESSION_AGENT_DENY} (Here ${why}.)` }
  }
  if (call.tool === 'AskUserQuestion') {
    if (facts.skill) return ALLOW
    const qs = Array.isArray(call.input.questions) ? call.input.questions : []
    return qs.length > 0 && qs.every(q => questionFits(q, facts)) ? ALLOW : { deny: SESSION_ASK_DENY }
  }
  return ALLOW
}
