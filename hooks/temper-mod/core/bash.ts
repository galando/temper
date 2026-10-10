// Bash classifier. Structural and conservative: the command is split into statements (quote,
// heredoc and substitution aware), shell variables are resolved statement by statement in order,
// brace expansion is expanded, and every write capable construct is checked against the guarded
// Temper paths. A target that cannot be resolved fails closed when the command names Temper
// state, or when the file name itself cannot be known. Reading a guarded file is never flagged.
//
// Limits, stated honestly: a variable set in an earlier call, a profile or the environment cannot
// be seen, and Bash can write files in ways no classifier catches (an interpreter that builds its
// path at run time, for one). The hard guarantee is the tool layer and `git commit`; the native
// pre-commit hook is the backstop.

import { normalizePath } from './paths'

// `config` and `hooks` are protected while a run is active only (the person writes the config with
// /temper:init, and installs the hooks, when no run is on). `hooks` is the native commit gate: the git hooks, the git
// config (core.hooksPath) and the Temper commit hook (the temper-gate folder in the git folder, the older
// temper-pre-commit file there, and the older folders hooks-temper and temper-git-hooks, which git still runs when
// core.hooksPath stays on one because it holds hooks of other tools).
export type ProtectedKind = 'events' | 'gates' | 'status' | 'overrides' | 'state' | 'folder' | 'evidence' | 'loops' | 'config' | 'hooks'

export type DecisionKind = 'override' | 'accept' | 'advance' | 'back'

// A decision CLI call as the command spells it: which kind, the phase (stage) and finding id it
// names, and `invalid` when a flag the CLI reads (`--id`, `--stage`, `--reason`) is repeated, so
// the CLI and the mod could read different values. An invalid call is never authorised.
// `next` is the stage a `state advance <stage>_complete <next>` call names as next.
export type DecisionCall = { kind: DecisionKind; stage?: string; id?: string; next?: string; invalid?: boolean }

// A `scripts/temper state ...` call that moves or removes run state.
export type StateOp = { op: 'set'; key: string; value?: string } | { op: 'clear' } | { op: 'archive' } | { op: 'init' } | { op: 'loop'; from?: string; to?: string }

export type BashClass = {
  commits: boolean
  decisions: DecisionKind[]
  calls: DecisionCall[]
  stateOps: StateOp[]
  // Every write onto a guarded path, and every write whose target cannot be checked.
  protectedWrites: string[]
  // The subset of protectedWrites that could not be resolved (fail closed).
  uncheckable: string[]
  // What `git add` stages in this command: `all` when it stages the whole tree (-A, ., -u), else the
  // paths. A commit that stages only files under .temper/specs/ is the artifact chain (the CLI commit gate
  // lets it through in every phase).
  staged: { all: boolean; paths: string[] }
  // The command may run the Temper CLI in a way this classifier cannot read as a plain call (a
  // glob, an unresolved variable or substitution, a launcher, an interpreter, a shell fed by a
  // pipe) AND it holds a decision verb. Fail closed: only the person decides.
  opaque: boolean
  // Why `opaque` is set, so the refusal tells the true reason. `dynamic`: the subcommand (or the verb) of a Temper
  // call is written as a variable, a substitution or an escaped string, so the call cannot be read. `decision`:
  // otherwise, the text holds a decision word. `hidden`: the command may run the script and hides part of what it
  // runs (a substitution, an expansion, a here-string), with no decision word in the text. Null when `opaque` is false.
  opaqueWhy: 'dynamic' | 'decision' | 'hidden' | null
  // The command makes another name or copy of the Temper script, or sources it.
  alias: boolean
  // A shell, or a builtin that runs text as commands (source and the like), is given a program the text does not show (a pipe from an unknown command, a file on
  // stdin, a substitution) or one that is written to hide a word (quote splits, `$`, backslashes, braces, globs).
  hidden: boolean
  // A word names a guarded file (or a glob that can stand for one) in a command that is not a plain read.
  guardedUse: string[]
  // TEMPER_DIR or TEMPER_CONFIG is set for a command: the CLI would read other files than the run's.
  envTamper: boolean
  // `git commit --no-verify` / -n, or a change of core.hooksPath: the native pre-commit hook would not run.
  noVerify: boolean
  hookTamper: boolean
  // A commit is made in a way that is not a plain `git commit` of the index: a pathspec, -i, -o, merge,
  // cherry-pick, am, pull, revert, commit-tree. The artifact-only carve-out never applies to it.
  unplainCommit: boolean
  // The working directory after the command (relative to where it started, or absolute); null when unknown.
  cwdAfter: string | null
}

// Every name is compared without regard to case: macOS (APFS) and Windows folders are case
// insensitive, so `.TEMPER/Gates.json` is the same file.
const PROTECTED: ReadonlyArray<readonly [ProtectedKind, RegExp]> = [
  ['events', /(^|\/)\.temper\/specs\/[^/\s]+\/events(\/|$)/i],
  ['gates', /(^|\/)\.temper\/gates\.json$/i],
  ['status', /(^|\/)\.temper\/status\.json$/i],
  ['overrides', /(^|\/)\.temper\/overrides\.json$/i],
  ['state', /(^|\/)\.temper\/build-state\.json$/i],
  // The grouped Build record (every task verdict) and the token usage record: written by the CLI only.
  ['state', /(^|\/)\.temper\/groups\.json$/i],
  ['state', /(^|\/)\.temper\/usage\.json$/i],
  // The evidence ledger and the loop counter are written by the CLI only.
  // (The ledger files only: a report a command keeps next to them, `coverage-report.txt`, is no ledger.)
  ['evidence', /(^|\/)\.temper\/evidence\/[^/]+\.json$/i],
  ['loops', /(^|\/)\.temper\/feedback-loops\.json$/i],
  // What decides how the run is checked (autonomy, thresholds, blocking), and the native commit gate: the git hooks, the
  // git config, and the Temper commit hook (`.git/temper-gate`, the folder core.hooksPath names, with its pre-commit, and
  // `.git/temper-pre-commit`, the file an older Temper line runs). A path under `temper-pre-commit` counts too: the line
  // runs the hook only when it is a file, so a folder made in its place would switch the hook off. Temper's older
  // folders (`.git/hooks-temper` from --global up to 9.6.4, `.git/temper-git-hooks` from 9.6.5) count as well: the
  // installer leaves core.hooksPath on one that holds hooks of other tools, and git then runs its pre-commit.
  ['config', /(^|\/)\.claude\/temper\.config$/i],
  ['hooks', /(^|\/)\.git\/(?:hooks(\/|$)|hooks-temper(\/|$)|temper-git-hooks(\/|$)|config$|temper-gate(\/|$)|temper-pre-commit(\/|$))/i],
  // Folders that hold guarded files: removing or replacing one removes them too.
  ['folder', /(^|\/)\.temper(\/specs(\/[^/\s]+)?)?\/?$/i],
]

// Which guarded Temper path a path names, or null.
export function protectedKind(path: string): ProtectedKind | null {
  // `..` and `.` segments are collapsed first, so specs/a/../a/events is the events folder.
  const p = normalizePath(path)
  for (const [kind, re] of PROTECTED) if (re.test(p)) return kind
  return null
}

const MENTION = /\.temper\/(?:specs\/[^\s'"`]+\/events[^\s'"`]*|gates\.json|status\.json|overrides\.json|build-state\.json|groups\.json|usage\.json|feedback-loops\.json|evidence\/[^\s'"`]*\.json)|\.claude\/temper\.config(?![\w.])|\.git\/(?:hooks|hooks-temper|temper-git-hooks|config|temper-gate|temper-pre-commit)(?![\w.-])/gi
// An interpreter program that holds a guarded file name on its own (`os.path.join('.temper', 'gates.json')`), or the
// folder itself next to a call that removes or moves things (`shutil.rmtree('.temper')`).
const BARE_NAMES = /(?<![\w.-])(?:gates|status|overrides)\.json(?![\w])|(?<![\w.-])build-state\.json|(?<![\w.-])groups\.json|(?<![\w.-])usage\.json|(?<![\w.-])feedback-loops\.json/gi
const FOLDER_QUOTED = /(?<=['"`])\.temper\/?(?=['"`])/
const REMOVER = /\b(?:rmtree|rmdir|removedirs|unlink|rimraf|rmSync|unlinkSync|renameSync|os\.rename|os\.replace|os\.remove|shutil\.move|truncate|chmod|chown)\w*/i

// The command names Temper state: strict mode, where an unresolvable write target is refused.
const NAMED = /\.temper|gates\.json|status\.json|overrides\.json|build-state\.json|\bevents\b|temper\.config|\.git\/(?:hooks|temper-git-hooks|config|temper-gate|temper-pre-commit)/i

// A path whose text names a guarded thing even when the rest cannot be resolved.
const NAMES_GUARDED = /gates\.json|status\.json|overrides\.json|build-state\.json|temper\.config|feedback-loops\.json|\.git\/(?:hooks|temper-git-hooks|config|temper-gate|temper-pre-commit)|(^|\/)events(\/|$)|(^|\/)\.temper(\/|$)/i

const PROTECTED_NAMES = ['.temper', 'events', 'gates.json', 'status.json', 'overrides.json', 'build-state.json', 'groups.json', 'usage.json', 'feedback-loops.json', 'temper.config']

// A command that names one of these files is a plain read, or it is refused while a run is active.
const GUARDED_FILE = /gates\.json|status\.json|overrides\.json|build-state\.json|feedback-loops\.json|(?:^|\/)temper\.config$|\.temper\/specs\/[^/\s'"`]+\/events|\.temper\/evidence\/[^\s'"`]*\.json|\.git\/(?:hooks|temper-git-hooks|config$|temper-gate|temper-pre-commit)/i

// Whether one word (quotes already removed, variables filled in) names a guarded file, or a glob that
// can stand for one: `.tem*/gates.js*`. A glob counts when its segment has three literal characters or
// starts with a dot (`.t*`), so `*` and `build/*` do not.
function mentionsGuarded(word: string, globs = true): boolean {
  if (GUARDED_FILE.test(word)) return true
  if (!globs) return false
  for (const seg of word.split(/[\s/=:,'"`;()&|<>]+/)) {
    if (!GLOB.test(seg)) continue
    const literals = seg.replace(/[*?[\]]/g, '').length
    if (literals < 3 && !seg.startsWith('.')) continue
    if (PROTECTED_NAMES.some(n => globRegExp(seg.replace(/[[\]]/g, '?')).test(n))) return true
  }
  return false
}

// ---- Statements and words ----------------------------------------------------------------

type Word = { text: string; dynamic: boolean }

// Splits a command into top level statements on `;`, `&`, `&&`, `||`, `|` and newlines, outside
// quotes and substitutions, and leaves heredoc bodies out (they are data or code for another
// interpreter, which the interpreter rule reads from the whole text).
function topStatements(cmd: string): string[] {
  return statementsOf(cmd).map(x => x.stmt)
}

// The same, with the statement a single `|` pipes into this one (null when there is none): a shell that
// reads its program from a pipe needs to know what produced it.
function statementsOf(cmd: string): Array<{ stmt: string; from: string | null }> {
  const out: Array<{ stmt: string; from: string | null }> = []
  let cur = ''
  let quote: '' | "'" | '"' = ''
  let depth = 0
  let heredoc: { tag: string; dash: boolean } | null = null
  const pending: Array<{ tag: string; dash: boolean }> = []
  let piped = false
  let prev: string | null = null
  const flush = () => {
    if (cur.trim()) {
      out.push({ stmt: cur.trim(), from: piped ? prev : null })
      prev = cur.trim()
      piped = false
    }
    cur = ''
  }
  for (let i = 0; i < cmd.length; i++) {
    const c = cmd[i] ?? ''
    if (heredoc) {
      // Skip lines until the terminator.
      const nl = cmd.indexOf('\n', i)
      const line = (nl < 0 ? cmd.slice(i) : cmd.slice(i, nl)).replace(/\r$/, '')
      const body = heredoc.dash ? line.replace(/^\t+/, '') : line
      if (body === heredoc.tag) heredoc = pending.shift() ?? null
      i = nl < 0 ? cmd.length : nl
      continue
    }
    if (quote) {
      cur += c
      if (c === '\\' && quote === '"' && i + 1 < cmd.length) cur += cmd[++i] ?? ''
      else if (c === quote) quote = ''
      continue
    }
    if (c === '\\' && i + 1 < cmd.length) {
      cur += c + (cmd[++i] ?? '')
      continue
    }
    if (c === "'" || c === '"') {
      quote = c
      cur += c
      continue
    }
    // A comment (`# ...` at the start of a word) is not part of any command: `npm test  # see .git/hooks`.
    if (c === '#' && (i === 0 || /[\s;&|(]/.test(cmd[i - 1] ?? ''))) {
      const nl = cmd.indexOf('\n', i)
      i = nl < 0 ? cmd.length : nl - 1
      continue
    }
    if (c === '$' && cmd[i + 1] === '(') {
      depth++
      cur += '$('
      i++
      continue
    }
    if ((c === '<' || c === '>') && cmd[i + 1] === '(') {
      depth++
      cur += c + '('
      i++
      continue
    }
    if (c === '(') depth++
    if (c === ')' && depth > 0) depth--
    if (c === '`') {
      // A backtick span is one substitution.
      const end = cmd.indexOf('`', i + 1)
      const stop = end < 0 ? cmd.length : end + 1
      cur += cmd.slice(i, stop)
      i = stop - 1
      continue
    }
    if (c === '<' && cmd[i + 1] === '<' && cmd[i + 2] !== '<') {
      const m = /^<<(-?)\s*(['"]?)([\w.-]+)\2/.exec(cmd.slice(i))
      if (m) {
        const tag = { tag: m[3] ?? '', dash: m[1] === '-' }
        if (cmd.indexOf('\n', i) >= 0) pending.push(tag)
        cur += m[0]
        i += m[0].length - 1
        continue
      }
    }
    if (depth === 0 && (c === ';' || c === '|' || c === '\n' || c === '&')) {
      if (c === '&' && (cmd[i - 1] === '>' || cmd[i + 1] === '>' || /\d/.test(cmd[i + 1] ?? ''))) {
        cur += c
        continue
      }
      const single = c === '|' && cmd[i + 1] !== '|'
      if ((c === '&' || c === '|') && cmd[i + 1] === c) i++
      flush()
      if (single) piped = true
      else prev = null
      if (c === '\n' && pending.length > 0) heredoc = pending.shift() ?? null
      continue
    }
    cur += c
  }
  flush()
  return out
}

// Splits a statement into words (quotes removed, backslashes processed outside single quotes).
// `dynamic` marks a word holding a command or process substitution.
function wordsOf(stmt: string): Word[] {
  const words: Word[] = []
  let cur = ''
  let dynamic = false
  let started = false
  let quote: '' | "'" | '"' = ''
  let depth = 0
  const push = () => {
    if (started) words.push({ text: cur, dynamic })
    cur = ''
    dynamic = false
    started = false
  }
  for (let i = 0; i < stmt.length; i++) {
    const c = stmt[i] ?? ''
    if (quote === "'") {
      if (c === "'") quote = ''
      else cur += c
      continue
    }
    if (quote === '"') {
      if (c === '"') quote = ''
      else if (c === '\\' && i + 1 < stmt.length) cur += stmt[++i] ?? ''
      else {
        if (c === '$' && stmt[i + 1] === '(') dynamic = true
        if (c === '`') dynamic = true
        cur += c
      }
      continue
    }
    if (depth > 0) {
      cur += c
      if (c === '(') depth++
      if (c === ')') depth--
      continue
    }
    if (c === "'" || c === '"') {
      quote = c
      started = true
      continue
    }
    if (c === '\\' && i + 1 < stmt.length) {
      cur += stmt[++i] ?? ''
      started = true
      continue
    }
    if ((c === '$' || c === '<' || c === '>') && stmt[i + 1] === '(') {
      dynamic = true
      started = true
      depth = 1
      cur += c + '('
      i++
      continue
    }
    if (c === '`') {
      const end = stmt.indexOf('`', i + 1)
      const stop = end < 0 ? stmt.length : end + 1
      cur += stmt.slice(i, stop)
      dynamic = true
      started = true
      i = stop - 1
      continue
    }
    if (/\s/.test(c)) {
      push()
      continue
    }
    cur += c
    started = true
  }
  push()
  return words
}

// Command and process substitutions inside a statement, as nested commands to analyse.
function substitutions(stmt: string): string[] {
  const out: string[] = []
  let single = false
  for (let i = 0; i < stmt.length; i++) {
    // Inside single quotes nothing is substituted.
    if (stmt[i] === "'" && stmt[i - 1] !== '\\') single = !single
    if (single) continue
    if ((stmt[i] === '$' || stmt[i] === '<' || stmt[i] === '>') && stmt[i + 1] === '(') {
      let d = 1
      let j = i + 2
      for (; j < stmt.length && d > 0; j++) {
        if (stmt[j] === '(') d++
        if (stmt[j] === ')') d--
      }
      out.push(stmt.slice(i + 2, j - 1))
      i = j - 1
    } else if (stmt[i] === '`') {
      const end = stmt.indexOf('`', i + 1)
      const stop = end < 0 ? stmt.length : end
      out.push(stmt.slice(i + 1, stop))
      i = stop
    }
  }
  return out
}

// ---- Variables and braces -----------------------------------------------------------------

type Vars = Map<string, string>

// Replaces $NAME and ${NAME} with known values, repeatedly (a fixed cap) so nested references
// resolve; an unknown name is left in place.
function expandVars(text: string, vars: Vars): string {
  let t = text
  for (let n = 0; n < 8; n++) {
    const next = t.replace(/\$\{(\w+)\}|\$(\w+)/g, (m, a, b) => vars.get(a ?? b ?? '') ?? m)
    if (next === t) break
    t = next
  }
  return t
}

// Expands `{a,b}` and `{1..3}` (a fixed cap); null when the expansion is too large.
function braceExpand(word: string): string[] | null {
  const out: string[] = []
  const walk = (w: string, depth: number): boolean => {
    if (depth > 6 || out.length > 64) return false
    const open = w.search(/\{[^{}]*(,|\.\.)[^{}]*\}/)
    if (open < 0) {
      out.push(w)
      return true
    }
    const close = w.indexOf('}', open)
    const body = w.slice(open + 1, close)
    const head = w.slice(0, open)
    const tail = w.slice(close + 1)
    const alts = body.includes(',') ? body.split(',') : seq(body)
    if (alts === null) return false
    for (const a of alts) if (!walk(head + a + tail, depth + 1)) return false
    return true
  }
  return walk(word, 0) && out.length <= 64 ? out : null
}

function seq(body: string): string[] | null {
  const m = /^(-?\d+)\.\.(-?\d+)$/.exec(body)
  if (!m) return null
  const a = Number(m[1])
  const b = Number(m[2])
  if (Math.abs(b - a) > 32) return null
  const r: string[] = []
  for (let i = a; a <= b ? i <= b : i >= b; i += a <= b ? 1 : -1) r.push(String(i))
  return r
}

const GLOB = /[*?[\]]/

// A file name that is `temper`, or a glob (`tempe[r]`, `temp*`, `*`) that can match it.
function namesTemper(text: string): boolean {
  const base = BASE(text).toLowerCase()
  if (base === 'temper') return true
  if (!GLOB.test(base)) return false
  let re = ''
  for (let i = 0; i < base.length; i++) {
    const c = base[i] ?? ''
    if (c === '*') re += '.*'
    else if (c === '?') re += '.'
    else if (c === '[' && base.indexOf(']', i + 2) > 0) {
      const end = base.indexOf(']', i + 2)
      re += `[${base.slice(i + 1, end).replace(/^!/, '^').replace(/\\/g, '\\\\')}]`
      i = end
    } else re += c.replace(/[.+^${}()|[\]\\]/g, '\\$&')
  }
  try {
    return new RegExp(`^${re}$`).test('temper')
  } catch {
    return true
  }
}

// ---- Standard input by any of its names -----------------------------------------------------

// Standard input is /dev/stdin, /dev/fd/N, /proc/self/fd/N, /proc/thread-self/fd/N, /proc/<pid>/fd/N or
// /proc/<pid>/task/<tid>/fd/N. Case is ignored (a folder on macOS may not tell case apart).
const STDIN_PATH = /^\/(?:dev\/(?:stdin|fd\/\d+)|proc\/(?:self|thread-self|\d+)\/(?:task\/\d+\/)?fd\/\d+)$/i
// What a glob, or a path with a part that cannot be read, is tried against.
const STDIN_SAMPLES: string[] = ['/dev/stdin']
for (let n = 0; n < 10; n++) {
  STDIN_SAMPLES.push(`/dev/fd/${n}`)
  for (const p of ['self', 'thread-self', '1', '42']) STDIN_SAMPLES.push(`/proc/${p}/fd/${n}`, `/proc/${p}/task/1/fd/${n}`)
}
// A part of a word the shell fills in that this command did not set: ${..}, $(..), `..`, $NAME (the whole name), $$
// and the like.
const UNREAD = /\$\{[^}]*\}|\$\([^)]*\)|`[^`]*`|\$(?:\w+|[$!#?*@-])/g
const MARK = '\u0000'

// A glob (with MARK for a part that cannot be read) as the text of a regular expression.
function stdinGlob(p: string): string {
  let re = ''
  for (let i = 0; i < p.length; i++) {
    const c = p[i] ?? ''
    if (c === MARK) re += '.*'
    else if (c === '*') re += '[^/]*'
    else if (c === '?') re += '[^/]'
    else if (c === '[' && p.indexOf(']', i + 2) > 0) {
      const end = p.indexOf(']', i + 2)
      re += `[${p.slice(i + 1, end).replace(/^!/, '^').replace(/\\/g, '\\\\')}]`
      i = end
    } else re += c.replace(/[.+^${}()|[\]\\]/g, '\\$&')
  }
  return re
}

// Whether one of the names of standard input can be matched by a regular expression.
function anyStdin(re: string, anchored: boolean): boolean {
  try {
    const glob = new RegExp(`${anchored ? '^' : ''}${re}$`, 'i')
    return STDIN_SAMPLES.some(s => glob.test(s))
  } catch {
    return true
  }
}

// The end of a path that is all that is known of it: what follows the last part that cannot be read (MARK), or the
// whole of a relative path, and of that only what follows its last `..` step (such a step can undo anything before
// it). `.` steps and doubled slashes are taken out. The result is matched against the end of the names of standard
// input; a path that ends in a part that cannot be read can be any name.
function stdinTail(text: string): boolean {
  const parts = text.split('/')
  const glued = parts[0] ?? ''
  let rest = parts.slice(1).filter(x => x !== '' && x !== '.')
  const up = rest.lastIndexOf('..')
  const head = up >= 0 ? '' : glued
  if (up >= 0) rest = rest.slice(up + 1)
  const tail = rest.length > 0 || head === '' ? `${head}/${rest.join('/')}` : head
  if (tail === '/' || tail === '') return true
  return anyStdin(stdinGlob(tail), false)
}

// The last part of a path is `stdin`, or the last two are `fd/<n>`.
const STDIN_NAME = /(?:^|\/)(?:stdin|fd\/\d+)$/i

// Whether a path names standard input, in any spelling. The variables this command set are filled in first, and
// `.`, `..`, doubled slashes and a /proc/<pid>/root prefix (the root folder again) are taken out, so /dev/./stdin,
// //dev/stdin, /dev//stdin and /dev/../dev/stdin all count. Of a brace expansion the first word counts (it is the
// script). A glob counts when it can match one of the names.
// A relative path is read against `cwd`, the folder the shell is in (see classifyBash): a full folder gives the
// full path. A folder in the project (relative to its root, whose place is not known here) gives a file of the
// project, unless `..` steps leave the project: they may reach the root folder, so ../../../dev/stdin counts.
// When `fed` says the command is given input (a pipe, a heredoc, a here-string or a file), that input is what may
// run, so more counts:
//  - a part that cannot be read (an unknown variable, a substitution) stands for any text, `..` steps too: the path
//    counts when what follows that part can end a name of standard input (`$D/stdin`, `$S`);
//  - a relative path counts when it can end a name of standard input (stdin, fd/0, dev/stdin), whatever the folder:
//    the folder may not be known (`cd "$X"`), and a link in the project can lead anywhere;
//  - a full path counts when it ends in stdin or fd/<n>, since a link can make any folder /dev.
function readsStdin(text: string, vars: Vars, fed: boolean, cwd: string | null): boolean {
  const t = expandVars(text, vars)
  let marked = (braceExpand(t)?.[0] ?? t).replace(UNREAD, MARK)
  // `$'..'` and `$".."` leave a `$` before the text. An escape inside `$'..'` cannot be read here, so it stands for any text.
  if (marked.includes('$')) marked = /\\/.test(marked) ? MARK : marked.replace(/\$/g, '')
  if (marked.includes(MARK)) return fed && stdinTail(marked.slice(marked.lastIndexOf(MARK) + 1))
  if (!marked.startsWith('/')) {
    if (cwd !== null && cwd.startsWith('/')) marked = `${cwd}/${marked}`
    else if (fed) return STDIN_NAME.test(normalizePath(marked)) || stdinTail(`/${marked}`)
    else if (cwd === null) return false
    else {
      const rel = normalizePath(cwd ? `${cwd}/${marked}` : marked)
      if (!rel.startsWith('..')) return false
      marked = `/${rel}`
    }
  }
  let p = normalizePath(marked).replace(/^\/(?:\.\.\/)+/, '/')
  for (let n = 0; n < 8 && /^\/proc\/[^/]*\/root\//i.test(p); n++) p = p.replace(/^\/proc\/[^/]*\/root/i, '')
  if (fed && STDIN_NAME.test(p)) return true
  if (!GLOB.test(p)) return STDIN_PATH.test(p)
  return anyStdin(stdinGlob(p), true)
}

// The text of a statement with its quoted parts ('..', "..", $'..') and its escaped characters taken out.
function unquoted(stmt: string): string {
  let out = ''
  let quote: '' | "'" | '"' | '$' = ''
  for (let i = 0; i < stmt.length; i++) {
    const c = stmt[i] ?? ''
    if (quote === "'") {
      if (c === "'") quote = ''
    } else if (quote === '"' || quote === '$') {
      if (c === '\\') i++
      else if (c === (quote === '"' ? '"' : "'")) quote = ''
    } else if (c === '\\') i++
    else if (c === '$' && stmt[i + 1] === "'") {
      quote = '$'
      i++
    } else if (c === "'" || c === '"') quote = c
    else out += c
  }
  return out
}

// Whether a statement is given input: a pipe into it, a heredoc, a here-string or a file on standard input. A `<` inside
// a quoted argument (`--grep '<title>'`) is no redirect, and input from /dev/null (`<`, `0<`) is no input.
const fedInput = (stmt: string, pipedFrom: string | null): boolean =>
  pipedFrom !== null || /(?:^|[^<>&\d])\d*<(?![(&])/.test(unquoted(stmt).replace(/(^|[^<>&\d])0?<\s*\/dev\/null(?![^\s;&|)])/g, '$1'))

// Words in a command that name a decision on the run. Read on the whole text of an opaque launch.
const VERB = /\b(?:override|accept|advance|next_stage|run_mode|clear|archive|init|loop)\b/i
const verbIn = (text: string): boolean => VERB.test(text) || (/\bstate\b/i.test(text) && /\bset\b/i.test(text))

// `temper` as a word or a path component inside any text (a quoted string holds several words).
const TEMPER_WORD = /(?:^|[\s/'"=;(&|<>`])temper(?=$|[\s/'"`;)&|<>])/i
// A construct that hides what the shell will really run: ANSI-C string, substitution, parameter
// expansion, here-string, process substitution, brace expansion.
const HIDES = /\$'|\$\(|`|\$\{|<<<|<\(|>\(|\{[^{}\s]*,[^{}\s]*\}/
const pieceNamesTemper = (text: string): boolean => TEMPER_WORD.test(text) || text.split(/[\s'"`;()&|<>=]+/).some(p => p !== '' && namesTemper(p))

// Commands that only read or print: they never run the Temper script. awk and sed read too, unless
// the program runs something (see readerDanger).
const READERS = new Set([
  'cat', 'grep', 'egrep', 'fgrep', 'rg', 'head', 'tail', 'less', 'more', 'wc', 'ls', 'stat', 'file', 'diff', 'cmp',
  'git', 'echo', 'printf', 'cd', 'pushd', 'test', '[', 'shellcheck', 'basename', 'dirname', 'realpath', 'readlink', 'which', 'type',
  'sed', 'awk', 'gawk', 'nl', 'tr', 'cut', 'sort', 'uniq', 'bat', 'strings', 'xxd', 'od', 'pytest', 'find',
])

// Whether a text holds a git command that creates a commit: commit, cherry-pick, merge, revert, am,
// commit-tree, rebase --continue, and a pull that merges. The read only and stopping forms
// (--abort, --quit, --skip, --show-current-patch) and `git push` are not. The pre-commit hook of
// git does not run for most of these, so the guard has to refuse them while the commit gate is open.
export function gitCreatesCommit(text: string, anchored = false): boolean {
  for (const m of text.matchAll(/\bgit\s+((?:(?:-c|-C)\s+\S+\s+|--[\w-]+(?:=\S+)?\s+|-\w\s+)*)(commit-tree|commit|cherry-pick|merge|revert|am|rebase|pull)\b([^;&|\n]*)/gi)) {
    if (anchored && m.index !== 0) break
    const sub = (m[2] ?? '').toLowerCase()
    const rest = m[3] ?? ''
    if (/--(?:abort|quit|skip|show-current-patch|edit-todo)\b/.test(rest) && sub !== 'commit') continue
    if (sub === 'rebase') {
      if (/--continue\b/.test(rest)) return true
      continue
    }
    if (sub === 'pull') {
      if (/--ff-only\b|--rebase\b|-r\b/.test(rest)) continue
      return true
    }
    if (sub === 'merge' && /--(?:abort|quit)\b/.test(rest)) continue
    return true
  }
  return false
}

// The arguments after a command word that cannot be read are the arguments of a plain Temper read or
// record call: the words that say what it does are literal (no $, no substitution) and name a call that
// decides nothing (gate, report, status, model, config, evidence add|run|list|resolve, state get, state set of
// a bookkeeping key).
function plainTemperArgs(args: Word[], argText: string[]): boolean {
  const lit = (i: number): string | null => (i < args.length && !args[i]?.dynamic && !/[$`]/.test(argText[i] ?? '') ? (argText[i] ?? null) : null)
  const a0 = lit(0)
  if (a0 === null) return false
  if (['gate', 'report', 'status', 'model', 'config', 'bands', 'metrics'].includes(a0)) return true
  const a1 = lit(1)
  if (a0 === 'evidence') return a1 !== null && ['add', 'run', 'list', 'resolve'].includes(a1)
  if (a0 === 'state') {
    if (a1 === 'get') return true
    if (a1 === 'set') {
      const key = lit(2)
      return key !== null && ['complexity', 'base_sha', 'regression_test', 'task'].includes(key)
    }
  }
  return false
}

// An awk program that runs a command (system, getline, a pipe) or a sed program that does (the e command or flag).
function readerDanger(cmd: string, args: Word[]): boolean {
  const text = args.map(a => a.text).join(' ')
  if (cmd === 'find') return args.some(a => /^-(?:exec|execdir|ok|okdir|delete|fprint\w*|fls)$/.test(a.text))
  if (cmd === 'awk' || cmd === 'gawk') return /system\s*\(|getline|\|\s*["']?\w|\|&/.test(text)
  if (cmd === 'sed') return /(?:^|[;{}\s])[0-9$,]*e(?:\s|;|$)|s(.)(?:(?!\1).)*\1(?:(?!\1).)*\1[a-z]*e/.test(text)
  return false
}

// Shells that take a program as a string (-c) or from a file.
const SHELLS = new Set(['bash', 'sh', 'zsh', 'dash', 'ksh', 'fish', 'ash', 'tcsh', 'csh'])
// Commands that run another command or program.
const EXEC = new Set([...SHELLS, 'make', 'gmake', 'awk', 'gawk', 'watch', 'script', 'parallel', 'busybox', 'xargs', 'env', 'eval', 'exec', 'find', 'nohup', 'timeout', 'sudo'])
// A file name that is a script by its extension.
const SCRIPT_FILE = /\.(?:sh|bash|zsh|ksh|fish|py|pl|rb|js|mjs|cjs|ts|php|mk|awk)$|(?:^|\/)makefile$/i
// A program given on the command line to an interpreter (python -c, node -e, perl -e, php -r).
const PROGRAM_FLAG = /^-[a-zA-Z]*[cer]$|^--eval$/

function globRegExp(glob: string): RegExp {
  let re = ''
  for (const c of glob) {
    if (c === '*') re += '.*'
    else if (c === '?') re += '.'
    else re += c.replace(/[.+^${}()|[\]\\]/g, '\\$&')
  }
  return new RegExp(`^${re}$`, 'i')
}

// A glob such as `ev*`, `.temper/g*` or `status.js?n` could match a guarded name.
function globCouldMatch(path: string): boolean {
  return path.split('/').some(seg => GLOB.test(seg) && PROTECTED_NAMES.some(n => globRegExp(seg.replace(/[[\]]/g, '?')).test(n)))
}

// ---- Commands -------------------------------------------------------------------------------

const BASE = (w: string): string => w.replace(/^.*\//, '')

const KEYWORDS = new Set(['then', 'do', 'else', 'elif', 'if', 'while', 'until', '!', '{', '}', 'time', 'command', 'builtin', 'exec', 'nohup', 'stdbuf', 'setsid'])
const DECLARE = new Set(['export', 'declare', 'typeset', 'local', 'readonly'])

// Removes wrapper words from the front: env, timeout, nice, ionice, xargs, sudo and keywords.
function unwrap(ws: Word[]): Word[] {
  let w = ws
  for (let guard = 0; guard < 20 && w.length > 0; guard++) {
    const first = BASE(w[0]?.text ?? '')
    const rest = w.slice(1)
    const skipOpts = (list: Word[], withArg: string[] = []): Word[] => {
      let i = 0
      while (i < list.length) {
        const t = list[i]?.text ?? ''
        if (withArg.includes(t)) i += 2
        else if (t.startsWith('-') && t !== '--') i += 1
        else break
      }
      return list.slice(i)
    }
    if (KEYWORDS.has(first)) {
      w = skipOpts(rest)
    } else if (first === 'sudo') {
      w = skipOpts(rest, ['-u', '-g', '-h', '-p', '-C', '-D', '-R', '-T'])
    } else if (first === 'env') {
      let i = 0
      while (i < rest.length) {
        const t = rest[i]?.text ?? ''
        if (['-u', '-C', '-S'].includes(t)) i += 2
        else if (t.startsWith('-') || /^[A-Za-z_]\w*=/.test(t)) i += 1
        else break
      }
      w = rest.slice(i)
    } else if (first === 'timeout') {
      const r = skipOpts(rest, ['-s', '-k', '--signal', '--kill-after'])
      w = /^\d/.test(r[0]?.text ?? '') ? r.slice(1) : r
    } else if (first === 'caffeinate') {
      w = skipOpts(rest, ['-t', '-w'])
    } else if (first === 'nice') {
      w = skipOpts(rest, ['-n'])
    } else if (first === 'ionice') {
      w = skipOpts(rest, ['-c', '-n', '-p'])
    } else if (first === 'xargs') {
      w = skipOpts(rest, ['-n', '-P', '-I', '-L', '-s', '-d', '-E'])
    } else if (first === '--') {
      w = rest
    } else break
  }
  return w
}

// The files an in place editor (`sed -i`, `perl -i`, `awk -i`) rewrites: not its options, not an
// empty backup suffix (`-i ''`), and not the script, which is the first plain word unless it was
// given with -e, -f or a combined flag such as -pe.
function inPlaceFiles(args: Word[]): Word[] {
  const files: Word[] = []
  let scriptGiven = false
  for (let i = 0; i < args.length; i++) {
    const t = args[i]?.text ?? ''
    if (/^-[a-zA-Z]*[ef]$/.test(t) || t === '--expression' || t === '--file') {
      scriptGiven = true
      i++
    } else if (t.startsWith('-')) continue
    else if (t === '') continue
    else if (!scriptGiven) scriptGiven = true
    else files.push(args[i] as Word)
  }
  return files
}

const WRITES_ANY = new Set(['tee', 'rm', 'touch', 'truncate', 'shred', 'unlink'])
const WRITES_LAST = new Set(['cp', 'mv', 'install', 'ln', 'rsync'])
const INTERPRETERS = /^(?:python[\d.]*|node|deno|bun|perl|ruby|php|osascript)$/

const GUARD_KEYS = new Set(['stage', 'next_stage', 'branch', 'spec_path', 'run_mode'])

type Flags = Map<string, string[]>

// Reads `--flag value` / `--flag=value` pairs the way the CLI does: a flag takes the next word
// whatever it is. Returns every value per flag so a repeat can be seen.
function readFlags(ws: Word[], names: readonly string[]): Flags {
  const flags: Flags = new Map()
  for (let i = 0; i < ws.length; i++) {
    const t = ws[i]?.text ?? ''
    const eq = t.indexOf('=')
    const name = eq > 0 ? t.slice(0, eq) : t
    if (!names.includes(name)) continue
    const value = eq > 0 ? t.slice(eq + 1) : (ws[++i]?.text ?? '')
    flags.set(name, [...(flags.get(name) ?? []), value])
  }
  return flags
}

// Shell setup tools: what one of them prints may be run as commands (sourced, or run from a substitution). Anything else
// built by a substitution is a program the text does not show.
const ENV_NAMES = new Set(['ssh-agent', 'pyenv', 'rbenv', 'nodenv', 'jenv', 'goenv', 'direnv', 'fnm', 'mise', 'asdf', 'brew', 'conda', 'minikube', 'docker-machine', 'starship', 'zoxide', 'dircolors', 'opam', 'keychain', 'gpg-agent', 'thefuck', 'register-python-argcomplete'])

// Substitutions of a plain lookup that cannot build a command: `$(pwd)`, `$(git rev-parse HEAD)`.
const TRIVIAL_SUBST = /^\s*(?:pwd|date|nproc|uname|whoami|hostname|git\s+rev-parse|which|command\s+-v|basename|dirname|realpath|mktemp)\b/
// Programs that print any text they are given: a substitution of one of them can build a command from pieces.
const GENERATORS = new Set([
  // Text tools.
  'echo', 'printf', 'cat', 'awk', 'gawk', 'sed', 'tr', 'xxd', 'rev', 'head', 'tail', 'cut', 'jq',
  // Transfer and encoding tools.
  'base64', 'curl', 'wget', 'openssl',
  // Shells, language runtimes and other producers.
  'python', 'python3', 'node', 'perl', 'ruby', 'sh', 'bash', 'zsh', 'env', 'printenv', 'yes', 'seq', 'tee', 'dd', 'php', 'deno', 'bun',
])
// A substitution whose command is a shell setup tool, a plain lookup, or a program run by its path
// (`$(scripts/ensure-jdk.sh --export)`): the text shows what produces the program. A text generator is not that.
function safeSubst(inner: string): boolean {
  const first = inner.trim().split(/\s+/)[0] ?? ''
  const base = first.replace(/^.*\//, '').toLowerCase()
  if (ENV_NAMES.has(base) || TRIVIAL_SUBST.test(inner)) return true
  return first.includes('/') && !GENERATORS.has(base.replace(/[\d.]+$/, ''))
}
const stripSafe = (t: string): string => t.replace(/\$\(([^()`$]*)\)/g, (m: string, inner: string) => (safeSubst(inner) ? '' : m))
// A program text that still holds a substitution or a variable after the shell setup idioms and the plain lookups.
const hiddenText = (t: string): boolean => /[$`]/.test(stripSafe(t))

// Commands that only read when they are given a guarded file.
const PLAIN_READERS = new Set([
  'cat', 'grep', 'egrep', 'fgrep', 'rg', 'head', 'tail', 'less', 'more', 'wc', 'ls', 'stat', 'file', 'diff', 'cmp', 'jq',
  'echo', 'printf', 'test', '[', 'basename', 'dirname', 'realpath', 'readlink', 'which', 'type', 'nl', 'cut', 'tr', 'strings',
  'xxd', 'od', 'bat', 'md5', 'md5sum', 'shasum', 'sha1sum', 'sha256sum', 'sha512sum', 'cd', 'pushd', 'temper', 'true', 'false',
])
// git subcommands that only read.
const GIT_READS = new Set([
  'diff', 'log', 'show', 'status', 'ls-files', 'blame', 'grep', 'cat-file', 'rev-parse', 'show-ref', 'check-ignore', 'ls-tree',
  'shortlog', 'describe', 'rev-list', 'diff-tree', 'diff-files', 'diff-index', 'whatchanged', 'reflog', 'name-rev', 'version', 'help',
])
// git subcommands that never change the index.
const GIT_NO_INDEX = new Set([
  ...GIT_READS, 'branch', 'push', 'fetch', 'remote', 'tag', 'config', 'init', 'clone', 'switch', 'worktree', 'gc', 'fsck', 'bisect',
  'submodule', 'prune', 'remote-show', 'notes', 'archive', 'bundle', 'apply',
])
const PERMS = new Set(['chmod', 'chown', 'chgrp', 'chflags', 'setfacl', 'chattr', 'xattr'])
// Commands that change files, as they would be run through xargs.
const XARGS_WRITERS = new Set(['tee', 'rm', 'touch', 'truncate', 'shred', 'unlink', 'cp', 'mv', 'install', 'ln', 'rsync', 'dd', 'sed', 'perl', 'tar', 'unzip', 'patch', ...PERMS])
// `-exec` commands of find that only read.
const FIND_SAFE_EXEC = new Set(['cat', 'grep', 'egrep', 'fgrep', 'rg', 'head', 'tail', 'wc', 'ls', 'stat', 'file', 'echo', 'printf', 'basename', 'dirname', 'shasum', 'md5', 'md5sum', 'sha256sum', 'jq', 'diff', 'cmp', 'test', '['])
const FIND_PATH_FILTERS = new Set(['-name', '-iname', '-path', '-ipath', '-wholename', '-iwholename', '-regex', '-iregex', '-lname', '-ilname'])
// Paths find looks at that no command reads from: a temporary folder cannot hold the run.
const FIND_ELSEWHERE = /^\/(?:private\/)?(?:tmp|var\/folders|var\/tmp)(?:\/|$)|^\/dev(?:\/|$)/
const FIND_SAMPLES = ['.temper', '.temper/gates.json', '.temper/status.json', '.temper/overrides.json', '.temper/build-state.json', '.temper/feedback-loops.json', '.temper/evidence/build.json', '.temper/specs/x/events/1.json']

// Whether a find filter (-name '*.pyc', -path '*/node_modules/*', -regex ...) can match a guarded file.
function findFilterCouldMatch(flag: string, value: string): boolean {
  if (/^-i?regex$/.test(flag)) {
    try {
      const re = new RegExp(`^(?:${value})$`, 'i')
      return FIND_SAMPLES.some(p => re.test(`./${p}`) || re.test(p))
    } catch {
      return true
    }
  }
  if (/name$/.test(flag)) {
    const re = globRegExp(value.replace(/\[[^\]]*\]/g, '?'))
    return PROTECTED_NAMES.some(n => re.test(n))
  }
  const re = globRegExp(value.replace(/\[[^\]]*\]/g, '?'))
  return FIND_SAMPLES.some(p => re.test(`./${p}`) || re.test(p))
}

// A find that deletes, writes a file, or runs something that is not a plain reader.
function findWrites(args: Word[]): boolean {
  for (let i = 0; i < args.length; i++) {
    const t = args[i]?.text ?? ''
    if (t === '-delete' || /^-f(?:print0?|printf|ls)$/.test(t)) return true
    if (/^-(?:exec|execdir|ok|okdir)$/.test(t)) {
      if (!FIND_SAFE_EXEC.has(BASE(args[i + 1]?.text ?? '').toLowerCase())) return true
    }
  }
  return false
}

// Index of the git subcommand in the words after `git`, skipping the options that take a value.
function gitSubAt(list: string[]): number {
  let i = 0
  while (i < list.length) {
    const t = list[i] ?? ''
    if (['-C', '-c', '--git-dir', '--work-tree', '--namespace', '--super-prefix', '--exec-path'].includes(t)) i += 2
    else if (t.startsWith('-')) i += 1
    else break
  }
  return i
}

export function classifyBash(command: string, startCwd: string | null = ''): BashClass {
  const text = command.replace(/>\|/g, '>')
  // The same text without the quotes and backslashes that split a word (`te""mper`, `ov\erride`).
  const squash = text.replace(/["'\\]/g, '')
  const strict = NAMED.test(text)
  const decisions: DecisionKind[] = []
  const calls: DecisionCall[] = []
  const stateOps: StateOp[] = []
  const writes: string[] = []
  const uncheckable: string[] = []
  let commits = false
  let interpreter = false
  let sawSed = false
  // Launch facts for the fail closed rule: see BashClass.opaque.
  let alias = false
  let mentionAny = false
  let mentionLoud = false
  let dynamicCommand = false
  let shellStdin = false
  // A Temper call whose subcommand or verb cannot be read from the text ($'..', ${..}, $(..)).
  let opaqueCall = false
  // The same for a script found by a substitution: `$T $c`, where the command names the script.
  let dynamicSub = false
  // Files this command writes, so a script that is written and then run can be seen.
  const created: string[] = []
  // A file this command wrote is run by it (as a command, or as the script of a shell or interpreter).
  let ranCreated = false
  // A script file (by its extension) is written.
  let wroteScript = false
  // An interpreter reads its program from standard input (a heredoc or a pipe).
  let stdinProgram = false
  const staged = { all: false, paths: [] as string[] }
  // `cat scripts/temper` was read: a following `tee` or redirect makes a copy.
  let readsScript = false
  const vars: Vars = new Map()
  // The working directory the command has moved to (relative to where it started); null when unknown.
  let cwd: string | null = startCwd
  // Hardening facts (see BashClass).
  let hidden = false
  let envTamper = false
  let noVerify = false
  let hookTamper = false
  let unplainCommit = false
  const guardedUse: string[] = []
  // Any statement names a guarded file; a write through xargs is read against it after the walk.
  let anyMention = false
  let xargsWriter = false
  // A shell reads its program from standard input.
  let stdinShell = false

  const flag = (path: string, unknown = false) => {
    writes.push(path)
    if (unknown) uncheckable.push(path)
  }

  // The paths a word can stand for: every brace expansion with variables filled in, resolved
  // against the working directory; `null` for one that cannot be resolved.
  const candidates = (w: Word): Array<string | null> => {
    const expanded = expandVars(w.text, vars)
    const alts = braceExpand(expanded)
    if (alts === null || w.dynamic) return [null]
    return alts.map(a => {
      if (/[$`]|^~|[<>]\(/.test(a)) return null
      if (a.startsWith('/')) return normalizePath(a)
      if (cwd === null) return null
      return normalizePath(cwd ? `${cwd}/${a}` : a)
    })
  }

  // One write target. `dest` is a directory the sources land in (cp, mv, install, ln, rsync):
  // such a directory is only refused when a source landing in it would be a guarded file.
  const check = (w: Word, sources: Word[] = [], isDest = false) => {
    const raw = expandVars(w.text, vars)
    const list = candidates(w)
    for (const r of list) {
      if (r === null) {
        const unknownName = /[$`]|\{|[<>]\(/.test(raw.split('/').pop() ?? '') || w.dynamic || (raw.split('/').pop() ?? '') === ''
        if (strict || unknownName || NAMES_GUARDED.test(raw)) flag(raw, true)
        continue
      }
      if (GLOB.test(r)) {
        if (strict || globCouldMatch(r)) flag(r, true)
        continue
      }
      const k = protectedKind(r)
      if (k === null) continue
      if (isDest && (k === 'folder' || k === 'events')) {
        const lands = sources.length === 0 ? [''] : sources.map(s => BASE(expandVars(s.text, vars)))
        const bad = lands.some(b => b === '' || b === '.' || b === '..' || /[$`*?[{]/.test(b) || protectedKind(`${r}/${b}`) !== null && protectedKind(`${r}/${b}`) !== 'folder')
        if (bad || k === 'events') flag(r)
        continue
      }
      flag(r)
    }
  }

  const analyse = (stmt: string, depth: number, pipedFrom: string | null = null): void => {
    if (depth > 6) return
    // A substitution or a subshell runs in a copy of the shell: a `cd` inside does not move this one.
    for (const sub of substitutions(stmt)) {
      const keep = cwd
      for (const s of statementsOf(sub)) analyse(s.stmt, depth + 1, s.from)
      cwd = keep
    }
    let ws = wordsOf(stmt)
    // A subshell or group: analyse what is inside.
    if (ws.length > 0 && /^\(.*\)$/.test(stmt.trim())) {
      const keep = cwd
      for (const s of statementsOf(stmt.trim().slice(1, -1))) analyse(s.stmt, depth + 1, s.from)
      cwd = keep
      return
    }

    // Assignments, in order, left to right, including after export/declare and in an env prefix.
    for (let guard = 0; guard < 40 && ws.length > 0; guard++) {
      const first = ws[0]?.text ?? ''
      if (DECLARE.has(first)) {
        ws = ws.slice(1).filter((w, i, a) => !(w.text.startsWith('-') && !a.slice(0, i).some(x => !x.text.startsWith('-'))))
        continue
      }
      const m = /^([A-Za-z_]\w*)\+?=(.*)$/.exec(first)
      if (!m) break
      if (/^TEMPER_(?:DIR|CONFIG)$/i.test(m[1] ?? '')) envTamper = true
      vars.set(m[1] ?? '', expandVars(m[2] ?? '', vars))
      ws = ws.slice(1)
    }
    if (ws.length === 0) return

    // Redirects first: they apply whatever the command is.
    const argv: Word[] = []
    const targets: string[] = []
    for (let i = 0; i < ws.length; i++) {
      const t = ws[i]?.text ?? ''
      const m = /^(?:\d*|&)>{1,2}(?!&)(.*)$/.exec(t)
      if (m && !/^\d*>&/.test(t)) {
        const target = m[1] ? { text: m[1], dynamic: ws[i]?.dynamic ?? false } : ws[++i]
        if (target) {
          check(target)
          targets.push(expandVars(target.text, vars))
        }
      } else if (/^\d*<</.test(t) || /^\d*<(?!\()/.test(t)) {
        if (t === '<' || /^\d*<<<?-?$/.test(t)) i++
      } else argv.push(ws[i] as Word)
    }
    for (const t of targets) {
      created.push(t)
      if (SCRIPT_FILE.test(t)) wroteScript = true
    }
    // A copy of the Temper script by redirect: `cat scripts/temper > /tmp/t`.
    if (targets.length > 0 && argv.some(x => namesTemper(expandVars(x.text, vars))) && ['cat', 'head', 'tail', 'dd', 'tee', 'sed', 'awk'].includes(BASE(argv[0]?.text ?? '').toLowerCase())) alias = true
    // Words that name the script, before any wrapper is taken off (env -S 'scripts/temper ...').
    const named = argv.some(x => pieceNamesTemper(expandVars(x.text, vars)))

    // The command word, with variables filled in (`T=scripts/temper; $T gate x` runs the script).
    const fill = (list: Word[]): Word[] => (list[0] ? [{ ...list[0], text: expandVars(list[0].text, vars) }, ...list.slice(1)] : list)
    const viaXargs = argv.some(x => BASE(x.text).toLowerCase() === 'xargs')
    let w = fill(unwrap(argv))
    // TEMPER_DIR / TEMPER_CONFIG set for the command (`env TEMPER_DIR=x ...`, `env -S "TEMPER_CONFIG=x ..."`).
    if (argv.some(x => /(?:^|[\s;&|(])TEMPER_(?:DIR|CONFIG)\+?=/i.test(x.text))) envTamper = true
    // A guarded file named by this command is read, or the command is refused while a run is active.
    {
      const first = BASE(expandVars(w[0]?.text ?? '', vars)).toLowerCase()
      const shellC = SHELLS.has(first) && w.slice(1).some(x => /^-\w*c$/.test(x.text))
      if (!shellC && (w.length > 0 || argv.length > 0)) {
        let words = (w.length > 0 ? w.slice(1) : argv).map(x => expandVars(x.text, vars))
        // A commit message is text, not a file: `git commit -m "fix gates.json"`.
        if (first === 'git') {
          const skip = new Set<number>()
          words.forEach((t, k) => {
            if (t === '-m' || t === '--message' || /^-[a-zA-Z]*m$/.test(t)) skip.add(k + 1)
            if (/^--message=/.test(t)) skip.add(k)
            if (/^-m./.test(t)) skip.add(k)
          })
          words = words.filter((_, k) => !skip.has(k))
        }
        // The program of sed and awk is a program, not a path: only a name written out counts there, not a glob.
        const progLike = first === 'sed' || first === 'awk' || first === 'gawk'
        const hits = words.filter(t => mentionsGuarded(t, !progLike))
        if (hits.length > 0) {
          anyMention = true
          let reads = PLAIN_READERS.has(first)
          if (first === 'git') {
            const sub = words[gitSubAt(words)]
            reads = sub !== undefined && (GIT_READS.has(sub) || sub === 'commit')
          }
          if (first === 'find') reads = !findWrites(w.slice(1))
          // sed reads unless it edits in place or runs a command; its `w file` is read from the whole text below.
          if (first === 'sed') reads = !words.some(t => /^-[a-zA-Z]*i|^--in-place/.test(t)) && !readerDanger('sed', w.slice(1))
          // awk reads unless a guarded name sits in its program (a redirect inside it writes) or it edits in place.
          if (first === 'awk' || first === 'gawk') {
            const progAt = words.findIndex((t, k) => !t.startsWith('-') && !['-v', '-F', '-f', '-i'].includes(words[k - 1] ?? ''))
            reads = !readerDanger(first, w.slice(1)) && !words.some(t => /^-[a-zA-Z]*i$|^--in-place$/.test(t)) && (progAt < 0 || !mentionsGuarded(words[progAt] ?? '', false))
          }
          // The plugin's own acceptance checker reads the evidence ledger and prints.
          if (INTERPRETERS.test(first) && /(^|\/)scripts\/acceptance\.py$/.test(words.find(t => !t.startsWith('-')) ?? '')) reads = true
          if (!reads) guardedUse.push(hits[0] ?? '')
        }
      }
    }
    if (XARGS_WRITERS.has(BASE(w[0]?.text ?? '').toLowerCase()) && viaXargs) xargsWriter = true
    if (viaXargs && BASE(w[0]?.text ?? '').toLowerCase() === 'git') staged.all = true
    // A file this command wrote is run: as the command itself, or as the script of a shell,
    // interpreter, make or source.
    {
      const first = expandVars(w[0]?.text ?? '', vars)
      const base = BASE(first).toLowerCase()
      const runner = SHELLS.has(base) || INTERPRETERS.test(base) || EXEC.has(base) || base === 'source' || base === '.'
      if (created.includes(first) || (runner && w.slice(1).some(x => created.includes(expandVars(x.text, vars))))) ranCreated = true
    }
    // `source scripts/temper ...` and `. scripts/temper ...` run the script in this shell.
    if (['source', '.'].includes(w[0]?.text ?? '') && w.slice(1).some(a => namesTemper(expandVars(a.text, vars)))) alias = true
    // A shell given the script as a file (after options such as -o), -s, or a program string after -c.
    while (w.length > 0 && SHELLS.has(BASE(w[0]?.text ?? '').toLowerCase())) {
      const rest = w.slice(1)
      // The shell reads its commands from standard input: a heredoc or a here-string is in the text; a pipe is shown
      // only when an echo or a printf (or a cat of a heredoc) feeds it.
      const fromStdin = (): void => {
        shellStdin = true
        stdinShell = true
        const shown = /<</.test(stmt) || (pipedFrom !== null && (/^(?:echo|printf)\s/.test(pipedFrom) || (/^cat\b/.test(pipedFrom) && /<</.test(pipedFrom))))
        if (!shown) hidden = true
      }
      // The startup files the shell reads before its program or script: the value after --rcfile or --init-file among
      // its options, BASH_ENV for bash, and ENV for an interactive shell (-i). BASH_ENV and ENV count when this command set
      // them, before the shell or through env. One that names standard input runs the program from the pipe.
      {
        const startup: string[] = []
        let interactive = false
        for (let i = 0; i < rest.length; i++) {
          const t = rest[i]?.text ?? ''
          if (/^-[a-zA-Z]*i[a-zA-Z]*$/.test(t)) interactive = true
          if (t === '--rcfile' || t === '--init-file') startup.push(rest[i + 1]?.text ?? '')
          if (['-o', '+o', '-O', '+O', '--rcfile', '--init-file'].includes(t)) i++
          else if (!/^[-+]/.test(t)) break
        }
        const setHere = (name: string): string[] => [
          ...(vars.has(name) ? [vars.get(name) ?? ''] : []),
          ...argv.flatMap(x => (x.text.startsWith(`${name}=`) ? [x.text.slice(name.length + 1)] : [])),
        ]
        if (BASE(w[0]?.text ?? '').toLowerCase() === 'bash') startup.push(...setHere('BASH_ENV'))
        if (interactive) startup.push(...setHere('ENV'))
        const fed = fedInput(stmt, pipedFrom)
        if (startup.some(f => f !== '' && readsStdin(f, vars, fed, cwd))) {
          fromStdin()
          return
        }
      }
      const ci = rest.findIndex(x => /^-\w*c$/.test(x.text))
      if (ci >= 0) {
        const script = rest[ci + 1]
        const scriptText = expandVars(script?.text ?? '', vars)
        if (script?.dynamic || /[$`]/.test(script?.text ?? '')) shellStdin = true
        // The program is built by a substitution (or is a variable nothing set): it is not shown by the text.
        if (script?.dynamic ? hiddenText(scriptText) : /^\s*\$/.test(scriptText)) hidden = true
        // xargs hands the words it reads to the shell as its program: a -c program that is only the {} placeholder, or
        // no program word at all (the first word xargs reads is the program).
        if (viaXargs && (script === undefined || /^\s*(?:\{\}|"?\$(?:@|\*|\d)"?)\s*$/.test(scriptText))) hidden = true
        // A string given to a shell: git commit inside it counts, and so does a name of the script.
        if (/\bgit\b/i.test(scriptText) && gitCreatesCommit(scriptText)) commits = true
        for (const s of statementsOf(scriptText)) analyse(s.stmt, depth + 1, s.from)
        if (named || pieceNamesTemper(scriptText)) mentionAny = true
        return
      }
      // The first word that is not an option (an option such as -o, --rcfile or --init-file takes a value) is the script.
      let fileAt = -1
      let sSeen = false
      for (let i = 0; i < rest.length; i++) {
        const t = rest[i]?.text ?? ''
        if (t === '-s') {
          shellStdin = true
          sSeen = true
        }
        if (['-o', '+o', '-O', '+O', '--rcfile', '--init-file'].includes(t)) i++
        else if (!/^[-+]/.test(t)) {
          fileAt = i
          break
        }
      }
      // A script argument that names standard input in any spelling (see readsStdin) is a program read from the
      // pipe, the same as no script file at all.
      const stdinFile = fileAt >= 0 && readsStdin(rest[fileAt]?.text ?? '', vars, fedInput(stmt, pipedFrom), cwd)
      if (fileAt < 0 || sSeen || stdinFile) {
        // No script file (or -s with arguments, the words after the options are arguments): the shell reads its
        // commands from standard input.
        fromStdin()
        return
      }
      w = fill(unwrap(rest.slice(fileAt)))
      if (BASE(w[0]?.text ?? '').toLowerCase() === 'temper') break
      // A script that is not named temper: a glob or a variable could still stand for it, and a
      // script given by a process substitution cannot be read.
      if (namesTemper(w[0]?.text ?? '') || named) {
        mentionAny = true
        mentionLoud = true
      }
      if (w[0]?.dynamic || /[$`]|[<>]\(/.test(w[0]?.text ?? '')) dynamicCommand = true
      return
    }
    if (w.length === 0) {
      // Everything was a wrapper: `env -S 'scripts/temper ...'` holds its command in a string.
      if (named) {
        mentionAny = true
        mentionLoud = true
      }
      return
    }
    const cmd = BASE(w[0]?.text ?? '').toLowerCase()
    const args = w.slice(1)
    const argText = args.map(a => expandVars(a.text, vars))

    // Facts for the fail closed rule: a statement that is not a plain Temper call but names the
    // script (a word, a glob that can match it, a name inside a string, a directory called temper in
    // command position) or runs a command that cannot be read. Reading commands are exempt.
    // A command word that cannot be read, followed by a plain Temper read or record call, is a script found by a
    // command substitution, then used for reads (`T=$(command -v temper); $T state get next_stage`): it is not read
    // as a mention of the script at all.
    const plainDynamic = (w[0]?.dynamic || /[$`]|[<>]\(/.test(w[0]?.text ?? '')) && plainTemperArgs(args, argText)
    if ((cmd !== 'temper' || viaXargs) && !plainDynamic) {
      const cmdText = w[0]?.text ?? ''
      // `python3 -m pytest -k "temper and accept"` runs tests: it only reads the word.
      const testRun = INTERPRETERS.test(cmd) && args.some((a, k) => a.text === '-m' && /^(?:pytest|unittest|coverage)$/.test(argText[k + 1] ?? ''))
      const safeReader = (READERS.has(cmd) && !readerDanger(cmd, args)) || testRun
      if ((cmd === 'make' || cmd === 'gmake') && args.some(a => a.text === '-f') && !args.some(a => /^[^-]/.test(a.text) && a.text !== '')) stdinProgram = true
      const names = named || w.some(x => namesTemper(expandVars(x.text, vars))) || cmdText.toLowerCase().split('/').includes('temper')
      if (names) {
        mentionAny = true
        if (!safeReader) mentionLoud = true
        if (cmd === 'cat') readsScript = true
      }
      if (viaXargs && cmd === 'temper') mentionLoud = true
      // A command word that cannot be read (`T=$(command -v temper); $T ...`) may be a script found by a command
      // substitution. It is fine for plain reads; anything else about it fails closed.
      if ((w[0]?.dynamic || /[$`]|[<>]\(/.test(cmdText)) && !plainTemperArgs(args, argText)) {
        dynamicCommand = true
        // The script found that way, given a subcommand that cannot be read either (`T=$(ls scripts/temper); $T $c`).
        if (names && args[0] !== undefined && (args[0].dynamic || /[$`]/.test(argText[0] ?? ''))) dynamicSub = true
      }
      // An interpreter program (python -c, node -e, perl -e) or a program on standard input that names
      // the script. A file run by an interpreter, and a test run (-m pytest -k "temper"), are not read here.
      if (INTERPRETERS.test(cmd)) {
        const flagAt = args.findIndex(a => PROGRAM_FLAG.test(a.text))
        const program = flagAt >= 0 ? argText.slice(flagAt + 1) : []
        if (program.some(a => /temper|subprocess/i.test(a))) mentionLoud = true
        if (!args.some(a => !a.text.startsWith('-')) && flagAt < 0) stdinProgram = true
        // A program file that is standard input in any spelling (python3 /dev/stdin) is a program on standard input too.
        const fileArg = args.find(a => !a.text.startsWith('-'))
        if (flagAt < 0 && fileArg !== undefined && readsStdin(fileArg.text, vars, fedInput(stmt, pipedFrom), cwd)) stdinProgram = true
      }
    }
    // A git command that creates a commit, wherever it sits (find -exec, env, watch, ...).
    if (cmd !== 'git' && cmd !== 'temper' && (!READERS.has(cmd) || cmd === 'find') && gitCreatesCommit(argText.join(' '))) {
      commits = true
      unplainCommit = true
    }

    if (cmd === 'eval') {
      const joined = args.map(a => expandVars(a.text, vars)).join(' ')
      // A program built by a substitution (not a shell setup idiom from ENV_NAMES) is not shown.
      if ((args.some(a => a.dynamic) || /[$`]/.test(joined)) && hiddenText(joined)) hidden = true
      for (const s of statementsOf(stripSafe(joined))) analyse(s.stmt, depth + 1, s.from)
      if (strict && args.some(a => /[$`]/.test(expandVars(a.text, vars)))) flag('(built program)', true)
      return
    }
    if (cmd === 'source' || cmd === '.') {
      const arg = args.find(a => !a.text.startsWith('-'))
      const t = expandVars(arg?.text ?? '', vars)
      // The same names of standard input as for a shell's script (see readsStdin).
      if (arg !== undefined && readsStdin(arg.text, vars, fedInput(stmt, pipedFrom), cwd)) {
        stdinShell = true
        if (!(/<</.test(stmt) || (pipedFrom !== null && /^(?:echo|printf)\s/.test(pipedFrom)))) hidden = true
      } else if (/[<>]\(/.test(t) ? !/^<\(\s*(?:direnv|pyenv|rbenv|fnm|mise|asdf|brew|conda|starship|zoxide|thefuck|register-python-argcomplete)\b/.test(t) : (arg?.dynamic ?? false) && hiddenText(t)) hidden = true
    }
    if (cmd === 'cd' || cmd === 'pushd') {
      // `cd` alone goes home and `cd -` goes back: neither place is known. A flag such as -P is not a place.
      const target = args.find(a => !/^-[LPe@]+$/.test(a.text))
      cwd = target && target.text !== '-' ? (candidates(target)[0] ?? null) : null
      return
    }

    if (cmd === 'git') {
      const i = gitSubAt(argText)
      // The folder the command works in: the shell's, moved by `-C`. `--git-dir` and `--work-tree` make it unknown.
      const joinPath = (base: string | null, p: string): string | null => (p.startsWith('/') ? normalizePath(p) : base === null ? null : normalizePath(base ? `${base}/${p}` : p))
      let gitCwd: string | null = cwd
      for (let k = 0; k < i; k++) {
        const t = argText[k] ?? ''
        if (t === '-c') {
          const kv = argText[k + 1] ?? ''
          // `-c alias.x=commit` or `-c alias.x=!...`: an alias can run a commit or any shell command.
          if (/^alias\./i.test(kv) && /=(?:!|.*\bcommit\b)/i.test(kv)) commits = true
          if (/^core\.hookspath=/i.test(kv)) hookTamper = true
          k++
        } else if (t === '-C') {
          gitCwd = joinPath(gitCwd, argText[k + 1] ?? '')
          k++
        } else if (t === '--git-dir' || t === '--work-tree') {
          gitCwd = null
          k++
        } else if (t.startsWith('--git-dir=') || t.startsWith('--work-tree=')) gitCwd = null
        else if (['--namespace', '--super-prefix', '--exec-path'].includes(t)) k++
      }
      const sub = argText[i] ?? ''
      // A redirect that stays in the words (`2>&1`) is no argument.
      const subArgs = argText.slice(i + 1).filter(a => !/^(?:\d*|&)(?:>>?|<)&\S*$/.test(a))
      if (gitCreatesCommit(`git ${argText.slice(i).join(' ')}`, true)) {
        commits = true
        if (sub !== 'commit') unplainCommit = true
      }
      if (sub === 'commit') {
        // Flags that take a value, so the value is not read as a path. A path after `commit` (or after `--`) is a
        // pathspec commit: it commits those files whatever the index holds. -i and -o are the same thing.
        const VALUE = new Set(['-m', '--message', '-F', '--file', '-C', '--reuse-message', '-c', '--reedit-message', '--author', '--date', '--template', '-t', '--fixup', '--squash', '--cleanup', '--trailer'])
        let afterDashes = false
        for (let k = 0; k < subArgs.length; k++) {
          const t = subArgs[k] ?? ''
          if (afterDashes) {
            unplainCommit = true
            continue
          }
          if (t === '--') afterDashes = true
          else if (VALUE.has(t)) k++
          else if (/^--(?:message|file|reuse-message|reedit-message|author|date|template|fixup|squash|cleanup|trailer)=/.test(t)) continue
          else if (t === '--no-verify') noVerify = true
          else if (t === '--all') staged.all = true
          else if (t === '--include' || t === '--only' || t === '--pathspec-from-file' || /^--pathspec-from-file=/.test(t)) unplainCommit = true
          else if (t.startsWith('--')) continue
          else if (/^-[a-zA-Z]+$/.test(t)) {
            // A cluster such as -am or -nm: `a` commits every changed file, `n` skips the hook, `i` and `o` make a
            // pathspec commit; a value flag takes the rest of the cluster or the next word.
            for (let c = 1; c < t.length; c++) {
              const ch = t[c] ?? ''
              if (ch === 'n') noVerify = true
              if (ch === 'a') staged.all = true
              if (ch === 'i' || ch === 'o') unplainCommit = true
              if (ch === 'S' || ch === 'u') break
              if ('mFCct'.includes(ch)) {
                if (c === t.length - 1) k++
                break
              }
            }
          } else if (!t.startsWith('-')) unplainCommit = true
        }
      } else if (sub === 'add' || sub === 'stage') {
        for (let k = 0; k < subArgs.length; k++) {
          const a = subArgs[k] ?? ''
          if (a === '--') continue
          // A redirect is no path (found live: `git add .temper/specs/x/ 2>&1` made the staging look like code).
          if (/^(?:\d*|&)(?:>>?|<)&?\S*$/.test(a)) {
            if (/^(?:\d*|&)(?:>>?|<)$/.test(a)) k += 1
            continue
          }
          // Staging the whole tree, and the forms whose staged set the text does not show (patch mode, a path list
          // in a file, intent to add): the staged set is not known, so the commit rule is strict.
          if (/^(?:-A|--all|--no-ignore-removal|-u|--update|\.|\*)$/.test(a) || /^-[a-zA-Z]*[Au]/.test(a)) staged.all = true
          else if (/^(?:--patch|--interactive|--edit|--intent-to-add|--chmod(?:=.*)?|--pathspec-from-file(?:=.*)?|--pathspec-file-nul)$/.test(a) || /^-[a-zA-Z]*[pieN]/.test(a)) staged.all = true
          else if (a.startsWith('-')) continue
          else if (a.startsWith(':')) staged.all = true
          else {
            const full = joinPath(gitCwd, a)
            if (full === null) staged.all = true
            else staged.paths.push(full)
          }
        }
      } else if (sub === 'config') {
        const flags = subArgs.filter(a => a.startsWith('-'))
        const pos = subArgs.filter(a => !a.startsWith('-'))
        // Setting or unsetting core.hooksPath moves the native pre-commit hook away; reading it is fine.
        if (pos.some(a => /^core\.hookspath$/i.test(a)) && (pos.length >= 2 || flags.some(f => /^--(?:unset|unset-all|replace-all|add|edit)$|^-e$/.test(f)))) hookTamper = true
      } else if (sub === 'clean') {
        // Removes untracked files, which can include .temper (the run) unless it is a dry run.
        if (!subArgs.some(a => /^-[a-zA-Z]*n|^--dry-run$/.test(a))) flag('.temper')
      } else if (sub === 'stash') {
        const verb = subArgs.find(a => !a.startsWith('-')) ?? 'push'
        if (['list', 'show', 'drop', 'clear', 'branch'].includes(verb)) {
          // no change to the index
        } else {
          if (subArgs.some(a => /^-[a-zA-Z]*[ua]|^--(?:include-untracked|all)$/.test(a))) flag('.temper')
          staged.all = true
        }
      } else if (sub === 'checkout') {
        // `git checkout <tree> -- path` and `git checkout <tree> path` put files in the index.
        let positional = 0
        let dashes = false
        for (let k = 0; k < subArgs.length; k++) {
          const a = subArgs[k] ?? ''
          if (a === '--') dashes = true
          else if (['-b', '-B', '--orphan'].includes(a)) k++
          else if (!a.startsWith('-')) positional++
        }
        if (dashes || positional >= 2) staged.all = true
      } else if (sub === 'restore') {
        if (subArgs.some(a => a === '--staged' || /^-[a-zA-Z]*S/.test(a))) staged.all = true
      } else if (sub === 'apply') {
        if (subArgs.some(a => /^--(?:cached|index)$/.test(a))) staged.all = true
      } else if (sub !== '' && !GIT_NO_INDEX.has(sub)) {
        // merge, cherry-pick, am, pull, revert, rebase, mv, rm, reset, update-index, an alias: the index is not known.
        staged.all = true
      }
    }

    if (cmd === 'temper') {
      let i = 0
      while (i < args.length) {
        const t = argText[i] ?? ''
        if (t === '--spec-path') i += 2
        else if (t.startsWith('-')) i += 1
        else break
      }
      const sub = argText[i]
      const sub2 = argText[i + 1]
      const rest = args.slice(i + 2)
      // The words that say what the call does must be literal. A verb built by $'..', ${..}, $(..) or
      // a variable that cannot be resolved cannot be read, so the call fails closed.
      const unreadable = (j: number): boolean => argText[j] !== undefined && (/[$`]/.test(argText[j] ?? '') || (args[j]?.dynamic ?? false))
      if (sub !== undefined && unreadable(i)) opaqueCall = true
      else if ((sub === 'state' || sub === 'evidence') && sub2 !== undefined && unreadable(i + 1)) opaqueCall = true
      else if (sub === 'state' && sub2 === 'set' && argText[i + 2] !== undefined && unreadable(i + 2)) opaqueCall = true
      if (sub === 'override') {
        const r = args.slice(i + 1)
        const fl = readFlags(r, ['--reason'])
        const stage = r[0] && !r[0].text.startsWith('-') ? expandVars(r[0].text, vars) : undefined
        decisions.push('override')
        calls.push({ kind: 'override', stage, invalid: (fl.get('--reason')?.length ?? 0) > 1 })
      } else if (sub === 'evidence' && sub2 === 'accept') {
        const fl = readFlags(rest, ['--stage', '--id', '--reason'])
        decisions.push('accept')
        calls.push({
          kind: 'accept',
          stage: fl.get('--stage')?.[0],
          id: fl.get('--id')?.[0],
          invalid: [...fl.values()].some(v => v.length > 1),
        })
      } else if (sub === 'state' && sub2 === 'advance') {
        const r = args.slice(i + 2)
        decisions.push('advance')
        calls.push({ kind: 'advance', stage: r[0] ? expandVars(r[0].text, vars) : undefined, next: r[1] ? expandVars(r[1].text, vars) : undefined })
      } else if (sub === 'state' && sub2 === 'set') {
        const key = argText[i + 2] ?? ''
        const value = argText[i + 3]
        stateOps.push({ op: 'set', key, value })
        if (key === 'next_stage') {
          decisions.push('back')
          calls.push({ kind: 'back', stage: value })
        }
      } else if (sub === 'state' && sub2 === 'loop') {
        // The stage the loop goes back to, only when it is a plain word: a built or unresolved one is not read.
        const from = argText[i + 2]
        const to = argText[i + 3]
        const plain = (j: number): boolean => argText[j] !== undefined && !/[$`]/.test(argText[j] ?? '') && !(args[j]?.dynamic ?? false)
        stateOps.push({ op: 'loop', ...(plain(i + 2) ? { from } : {}), ...(plain(i + 3) ? { to } : {}) })
      } else if (sub === 'state' && (sub2 === 'clear' || sub2 === 'archive' || sub2 === 'init')) {
        stateOps.push({ op: sub2 })
      }
    }

    // (The plugin's acceptance checker only reads: python3 scripts/acceptance.py check intent.md .temper/evidence/check.json.)
    if (INTERPRETERS.test(cmd) && !/(^|\/)scripts\/acceptance\.py$/.test(argText.find(t => !t.startsWith('-')) ?? '')) interpreter = true

    // ---- Write capable constructs ----
    if (WRITES_ANY.has(cmd)) for (const a of args) if (!a.text.startsWith('-') || a.dynamic) check(a)
    if (cmd === 'tee') {
      for (const a of args) {
        if (a.text.startsWith('-')) continue
        const t = expandVars(a.text, vars)
        created.push(t)
        if (SCRIPT_FILE.test(t)) wroteScript = true
      }
      // `cat scripts/temper | tee /tmp/t` makes a copy.
      if (readsScript) alias = true
    }
    // A link (hard or symbolic) to Temper state, or to the folder that holds it, by another name:
    // a write through the link would not be seen as a write to the guarded path.
    if (cmd === 'ln') {
      for (const a of args) {
        if (a.text.startsWith('-')) continue
        const raw = expandVars(a.text, vars)
        if (NAMES_GUARDED.test(raw) || candidates(a).some(r => r !== null && protectedKind(r) !== null)) flag(raw)
      }
    }
    if (cmd === 'dd') for (const a of args) if (a.text.startsWith('of=')) check({ text: a.text.slice(3), dynamic: a.dynamic })
    if (WRITES_LAST.has(cmd)) {
      const files = args.filter(a => !a.text.startsWith('-'))
      args.forEach((a, i) => {
        if (a.text === '-t' || a.text === '--target-directory') {
          const d = args[i + 1]
          if (d) check(d, files.filter(f => f !== d), true)
        } else if (a.text.startsWith('--target-directory=')) check({ text: a.text.slice(19), dynamic: a.dynamic }, files, true)
      })
      const last = files[files.length - 1]
      // A link or copy of the script is another name for it, whatever the command says.
      const tDir = args.findIndex(a => a.text === '-t' || a.text === '--target-directory')
      const sources = tDir >= 0 ? files.filter(f => f !== args[tDir + 1]) : files.slice(0, -1)
      if (sources.some(f => namesTemper(expandVars(f.text, vars)))) alias = true
      if (last) check(last, files.slice(0, -1), true)
      // Moving a guarded file or folder away removes it.
      if (cmd === 'mv') for (const f of files.slice(0, -1)) check(f)
    }
    // chmod, chown, chflags, setfacl, chattr: a file made unreadable or immutable switches the run off as surely as a delete.
    if (PERMS.has(cmd)) {
      const recursive = args.some(a => /^-[a-zA-Z]*[Rr]|^--recursive$/.test(a.text))
      for (const a of args) {
        if (a.text.startsWith('-') && !a.dynamic) continue
        // `chmod +x scripts/*` is no business of the run's; a glob that can stand for a guarded file is.
        if (GLOB.test(a.text) && !mentionsGuarded(expandVars(a.text, vars))) continue
        check(a)
        // `chmod -R 000 .` reaches .temper through the folder that holds it.
        if (recursive && ['.', '..', '~', '/', './', '../'].includes(expandVars(a.text, vars))) flag('.temper')
      }
    }
    // find: delete, write or run something in the folders that hold the run. A filter that cannot match a guarded
    // name (-name '*.pyc') and a start folder that cannot reach .temper are the usual, harmless uses.
    if (cmd === 'find' && findWrites(args)) {
      const starts: Word[] = []
      for (const a of args) {
        if (a.text.startsWith('-') || a.text === '(' || a.text === '!') break
        starts.push(a)
      }
      // -maxdepth 0 looks at the start paths themselves and goes into none of them.
      const shallow = args.some((a, k) => a.text === '-maxdepth' && args[k + 1]?.text === '0')
      const reaches = (starts.length === 0 && !shallow) || starts.some(a => {
        const raw = expandVars(a.text, vars)
        if (/^\//.test(raw)) return !FIND_ELSEWHERE.test(raw) && !shallow
        return candidates(a).some(r => r === null || (!shallow && (r === '' || r.startsWith('..') || r.startsWith('/'))) || protectedKind(r) !== null || r.toLowerCase().startsWith('.temper') || (GLOB.test(r) && globCouldMatch(r)))
      })
      const negated = args.some(a => a.text === '!' || a.text === '-not')
      const filters: Array<[string, string]> = []
      args.forEach((a, k) => {
        if (FIND_PATH_FILTERS.has(a.text) && args[k + 1]) filters.push([a.text, expandVars(args[k + 1]?.text ?? '', vars)])
      })
      const narrowed = !negated && filters.length > 0 && !filters.some(([f, v]) => findFilterCouldMatch(f, v))
      if (reaches && !narrowed) flag('.temper')
      // The file a -fprint, -fprintf or -fls writes.
      args.forEach((a, k) => {
        if (/^-f(?:print0?|printf|ls)$/.test(a.text) && args[k + 1]) check(args[k + 1] as Word)
      })
    }
    if (cmd === 'sed' || cmd === 'perl' || cmd === 'awk') {
      if (args.some(a => a.text === '--in-place' || /^-[a-zA-Z]*i/.test(a.text))) for (const a of inPlaceFiles(args)) check(a)
      if (cmd === 'sed') sawSed = true
    }
    if (cmd === 'curl') {
      args.forEach((a, i) => {
        if (a.text === '-o' || a.text === '--output') {
          const t = args[i + 1]
          if (t) check(t)
        } else if (a.text.startsWith('--output=')) check({ text: a.text.slice(9), dynamic: a.dynamic })
        else if (/^-[a-zA-Z]*o.+/.test(a.text) && !a.text.startsWith('--')) check({ text: a.text.replace(/^-[a-zA-Z]*o/, ''), dynamic: a.dynamic })
      })
    }
    if (cmd === 'wget') {
      args.forEach((a, i) => {
        if (a.text === '-O' || a.text === '--output-document') {
          const t = args[i + 1]
          if (t) check(t)
        } else if (a.text.startsWith('--output-document=')) check({ text: a.text.slice(18), dynamic: a.dynamic })
        else if (a.text.startsWith('-O') && a.text.length > 2) check({ text: a.text.slice(2), dynamic: a.dynamic })
      })
    }
    if (cmd === 'tar') {
      args.forEach((a, i) => {
        if (a.text === '-C' || a.text === '--directory') {
          const d = args[i + 1]
          if (d) checkDirTarget(d)
        } else if (a.text.startsWith('--directory=')) checkDirTarget({ text: a.text.slice(12), dynamic: a.dynamic })
        else if (a.text.startsWith('-C') && a.text.length > 2) checkDirTarget({ text: a.text.slice(2), dynamic: a.dynamic })
      })
    }
    if (cmd === 'rsync' && args.some(a => a.text === '--delete' || a.text.startsWith('--delete-'))) {
      const last = args.filter(a => !a.text.startsWith('-')).pop()
      if (last) check(last)
    }
  }

  // Extracting into a folder that holds guarded files (tar -C .temper) can overwrite them.
  const checkDirTarget = (w: Word) => {
    for (const r of candidates(w)) {
      if (r === null) {
        if (strict) flag(expandVars(w.text, vars), true)
      } else if (protectedKind(r) !== null) flag(r)
    }
  }

  for (const s of statementsOf(text)) analyse(s.stmt, 0, s.from)

  // sed's `w FILE` can sit after a `;` inside the script, so the whole command is read.
  if (sawSed) for (const m of text.matchAll(/(?:^|[\s;{}/'"])w\s+([^\s;}'"]+)/g)) check({ text: m[1] ?? '', dynamic: false })

  // An interpreter that is told a guarded path: it can write it however it likes.
  if (interpreter) {
    for (const m of text.match(MENTION) ?? []) flag(m)
    // The folder written as a string of its own is a path built in pieces: a guarded name next to it, or a call that
    // removes or moves things, is the run's files by the back door.
    if (FOLDER_QUOTED.test(text)) {
      for (const m of text.match(BARE_NAMES) ?? []) flag(`.temper/${m.toLowerCase()}`)
      if (REMOVER.test(text)) flag('.temper')
    }
  }
  // A program given on standard input or in a heredoc is read from the whole text, without the quote and
  // backslash splits that hide a word (`te""mper`).
  const textNames = TEMPER_WORD.test(squash)
  // The program is the heredoc body when there is one: a plain Temper call elsewhere in the command does
  // not make a program that does not name the script a suspect. Without a heredoc (a pipe), the whole text is read.
  const bodies = [...text.matchAll(/<<-?\s*['"]?(\w+)['"]?[^\n]*\n([\s\S]*?)\n\s*\1(?:\s|$)/g)].map(m => m[2] ?? '')
  // (`.temper/specs/...` is a path inside the project, not the script: only the word `temper` counts.)
  if (stdinProgram && (bodies.length > 0 ? bodies : [text]).some(b => TEMPER_WORD.test(b.replace(/["'\\]/g, '')) || /subprocess/i.test(b))) mentionLoud = true

  // Fail closed: the command may run the Temper script in a way the text does not show. Reading
  // commands and plain, readable calls are not touched. A script that is written and run, or a
  // program that holds the script name and a decision word, is.
  const verb = verbIn(squash)
  const opaque =
    opaqueCall ||
    (verb && textNames && (ranCreated || wroteScript)) ||
    (mentionLoud && (verb || HIDES.test(text))) ||
    (verb && (dynamicCommand || (shellStdin && (mentionAny || /temper/i.test(squash)))))
  // A shell that reads its program from standard input: what hides a word in it (quote splits, `$`, backticks,
  // backslashes, braces, globs) makes the program one the text does not show.
  if (stdinShell && /[$`\\]|\{[^{}\s]*,[^{}\s]*\}|""|''|[*?]/.test(text)) hidden = true
  // A write through xargs names its files on stdin: when the command names a guarded file anywhere, it is refused.
  if (xargsWriter && anyMention) flag('.temper')
  // git reads core.hooksPath from the environment too.
  if (/GIT_CONFIG_(?:KEY_\d+|PARAMETERS)\s*=[^\n;&|]*hookspath/i.test(text)) hookTamper = true
  return {
    commits,
    decisions,
    calls,
    stateOps,
    protectedWrites: [...new Set(writes)],
    uncheckable: [...new Set(uncheckable)],
    staged,
    opaque,
    opaqueWhy: !opaque ? null : opaqueCall || dynamicSub ? 'dynamic' : verb ? 'decision' : 'hidden',
    alias,
    hidden,
    guardedUse: [...new Set(guardedUse)],
    envTamper,
    noVerify,
    hookTamper,
    unplainCommit,
    cwdAfter: cwd,
  }
}
