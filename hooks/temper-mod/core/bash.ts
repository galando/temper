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

export type ProtectedKind = 'events' | 'gates' | 'status' | 'overrides' | 'state' | 'folder'

export type DecisionKind = 'override' | 'accept' | 'advance' | 'back'

// A decision CLI call as the command spells it: which kind, the phase (stage) and finding id it
// names, and `invalid` when a flag the CLI reads (`--id`, `--stage`, `--reason`) is repeated, so
// the CLI and the mod could read different values. An invalid call is never authorised.
// `next` is the stage a `state advance <stage>_complete <next>` call names as next.
export type DecisionCall = { kind: DecisionKind; stage?: string; id?: string; next?: string; invalid?: boolean }

// A `scripts/temper state ...` call that moves or removes run state.
export type StateOp = { op: 'set'; key: string; value?: string } | { op: 'clear' } | { op: 'archive' } | { op: 'init' } | { op: 'loop' }

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
  // The command makes another name or copy of the Temper script, or sources it.
  alias: boolean
}

// Every name is compared without regard to case: macOS (APFS) and Windows folders are case
// insensitive, so `.TEMPER/Gates.json` is the same file.
const PROTECTED: ReadonlyArray<readonly [ProtectedKind, RegExp]> = [
  ['events', /(^|\/)\.temper\/specs\/[^/\s]+\/events(\/|$)/i],
  ['gates', /(^|\/)\.temper\/gates\.json$/i],
  ['status', /(^|\/)\.temper\/status\.json$/i],
  ['overrides', /(^|\/)\.temper\/overrides\.json$/i],
  ['state', /(^|\/)\.temper\/build-state\.json$/i],
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

const MENTION = /\.temper\/(?:specs\/[^\s'"`]+\/events[^\s'"`]*|gates\.json|status\.json|overrides\.json|build-state\.json)/gi

// The command names Temper state: strict mode, where an unresolvable write target is refused.
const NAMED = /\.temper|gates\.json|status\.json|overrides\.json|build-state\.json|\bevents\b/i

// A path whose text names a guarded thing even when the rest cannot be resolved.
const NAMES_GUARDED = /gates\.json|status\.json|overrides\.json|build-state\.json|(^|\/)events(\/|$)|(^|\/)\.temper(\/|$)/i

const PROTECTED_NAMES = ['.temper', 'events', 'gates.json', 'status.json', 'overrides.json', 'build-state.json']

// ---- Statements and words ----------------------------------------------------------------

type Word = { text: string; dynamic: boolean }

// Splits a command into top level statements on `;`, `&`, `&&`, `||`, `|` and newlines, outside
// quotes and substitutions, and leaves heredoc bodies out (they are data or code for another
// interpreter, which the interpreter rule reads from the whole text).
function topStatements(cmd: string): string[] {
  const out: string[] = []
  let cur = ''
  let quote: '' | "'" | '"' = ''
  let depth = 0
  let heredoc: { tag: string; dash: boolean } | null = null
  const pending: Array<{ tag: string; dash: boolean }> = []
  const flush = () => {
    if (cur.trim()) out.push(cur.trim())
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
      if ((c === '&' || c === '|') && cmd[i + 1] === c) i++
      flush()
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

export function classifyBash(command: string): BashClass {
  const text = command.replace(/>\|/g, '>')
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
  let cwd: string | null = ''

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

  const analyse = (stmt: string, depth: number): void => {
    if (depth > 6) return
    for (const sub of substitutions(stmt)) for (const s of topStatements(sub)) analyse(s, depth + 1)
    let ws = wordsOf(stmt)
    // A subshell or group: analyse what is inside.
    if (ws.length > 0 && /^\(.*\)$/.test(stmt.trim())) {
      for (const s of topStatements(stmt.trim().slice(1, -1))) analyse(s, depth + 1)
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
        if (t === '<' || /^\d*<<-?$/.test(t)) i++
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
    // `bash scripts/temper ...`, `bash -o pipefail scripts/temper ...`, `bash -s` and `sh -c STRING`.
    while (w.length > 0 && SHELLS.has(BASE(w[0]?.text ?? '').toLowerCase())) {
      const rest = w.slice(1)
      const ci = rest.findIndex(x => /^-\w*c$/.test(x.text))
      if (ci >= 0) {
        const script = rest[ci + 1]
        if (script?.dynamic || /[$`]/.test(script?.text ?? '')) shellStdin = true
        // A string given to a shell: git commit inside it counts, and so does a name of the script.
        if (/\bgit\b/i.test(script?.text ?? '') && gitCreatesCommit(script?.text ?? '')) commits = true
        for (const s of topStatements(script?.text ?? '')) analyse(s, depth + 1)
        if (named || pieceNamesTemper(script?.text ?? '')) mentionAny = true
        return
      }
      // The first word that is not an option (an option such as -o takes a value) is the script.
      let fileAt = -1
      for (let i = 0; i < rest.length; i++) {
        const t = rest[i]?.text ?? ''
        if (t === '-s') shellStdin = true
        if (['-o', '+o', '-O', '+O'].includes(t)) i++
        else if (!/^[-+]/.test(t)) {
          fileAt = i
          break
        }
      }
      if (fileAt < 0) {
        // No script file: the shell reads its commands from standard input.
        shellStdin = true
        return
      }
      if (shellStdin) {
        // `bash -s ARGS`: the words after the options are arguments, not a script.
        return
      }
      w = fill(unwrap(rest.slice(fileAt)))
      if (BASE(w[0]?.text ?? '').toLowerCase() === 'temper') break
      // A script that is not named temper: a glob or a variable could still stand for it, and a
      // script given by a substitution (`bash <(cat scripts/temper)`) cannot be read.
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
    // A command word that cannot be read, followed by a plain Temper read or record call, is the
    // orchestrator's own idiom (`T=$(ls .../scripts/temper); $T state get next_stage`): it is not read as a
    // mention of the script at all.
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
      // A command word that cannot be read (`T=$(ls .../scripts/temper); $T ...`) is the orchestrator's own
      // idiom for finding the script. It is fine for plain reads; anything else about it fails closed.
      if ((w[0]?.dynamic || /[$`]|[<>]\(/.test(cmdText)) && !plainTemperArgs(args, argText)) dynamicCommand = true
      // An interpreter program (python -c, node -e, perl -e) or a program on standard input that names
      // the script. A file run by an interpreter, and a test run (-m pytest -k "temper"), are not read here.
      if (INTERPRETERS.test(cmd)) {
        const flagAt = args.findIndex(a => PROGRAM_FLAG.test(a.text))
        const program = flagAt >= 0 ? argText.slice(flagAt + 1) : []
        if (program.some(a => /temper|subprocess/i.test(a))) mentionLoud = true
        if (!args.some(a => !a.text.startsWith('-')) && flagAt < 0) stdinProgram = true
      }
    }
    // A git command that creates a commit, wherever it sits (find -exec, env, watch, ...).
    if (cmd !== 'git' && cmd !== 'temper' && (!READERS.has(cmd) || cmd === 'find') && gitCreatesCommit(argText.join(' '))) commits = true

    if (cmd === 'eval') {
      for (const s of topStatements(args.map(a => expandVars(a.text, vars)).join(' '))) analyse(s, depth + 1)
      if (strict && args.some(a => /[$`]/.test(expandVars(a.text, vars)))) flag('eval', true)
      return
    }
    if (cmd === 'cd' || cmd === 'pushd') {
      const target = args[0]
      cwd = target ? (candidates(target)[0] ?? null) : cwd
      return
    }

    if (cmd === 'git') {
      let i = 0
      while (i < args.length) {
        const t = argText[i] ?? ''
        // `-c alias.x=commit` or `-c alias.x=!...`: an alias can run a commit or any shell command.
        if (t === '-c' && /^alias\./i.test(argText[i + 1] ?? '') && /=(?:!|.*\bcommit\b)/i.test(argText[i + 1] ?? '')) commits = true
        if (t === '-c' || t === '-C') i += 2
        else if (t.startsWith('-')) i += 1
        else break
      }
      if (gitCreatesCommit(`git ${argText.slice(i).join(' ')}`, true)) commits = true
      // `git commit -a` or `-am` commits every changed file, whatever was staged.
      if (argText[i] === 'commit' && argText.slice(i + 1).some(a => a === '--all' || /^-[a-zA-Z]*a[a-zA-Z]*$/.test(a))) staged.all = true
      if (argText[i] === 'add') {
        for (const a of argText.slice(i + 1)) {
          if (a === '--') continue
          if (/^(?:-A|--all|-u|--update|\.|\*)$/.test(a) || /^-[a-zA-Z]*[Au]/.test(a)) staged.all = true
          else if (!a.startsWith('-')) staged.paths.push(a)
        }
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
      } else if (sub === 'state' && (sub2 === 'clear' || sub2 === 'archive' || sub2 === 'init' || sub2 === 'loop')) {
        stateOps.push({ op: sub2 })
      }
    }

    if (INTERPRETERS.test(cmd)) interpreter = true

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
    if (cmd === 'find' && (args.some(a => a.text === '-delete') || args.some(a => a.text === '-exec' || a.text === '-execdir'))) {
      for (const a of args) {
        if (a.text.startsWith('-') || a.text === '(' || a.text === '!') break
        check(a)
      }
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

  for (const stmt of topStatements(text)) analyse(stmt, 0)

  // sed's `w FILE` can sit after a `;` inside the script, so the whole command is read.
  if (sawSed) for (const m of text.matchAll(/(?:^|[\s;{}/'"])w\s+([^\s;}'"]+)/g)) check({ text: m[1] ?? '', dynamic: false })

  // An interpreter that is told a guarded path: it can write it however it likes.
  if (interpreter) for (const m of text.match(MENTION) ?? []) flag(m)
  // A program given on standard input or in a heredoc is read from the whole text.
  const textNames = TEMPER_WORD.test(text)
  // The program is the heredoc body when there is one: a plain Temper call elsewhere in the command does
  // not make a program that does not name the script a suspect. Without a heredoc (a pipe), the whole text is read.
  const bodies = [...text.matchAll(/<<-?\s*['"]?(\w+)['"]?[^\n]*\n([\s\S]*?)\n\s*\1(?:\s|$)/g)].map(m => m[2] ?? '')
  // (`.temper/specs/...` is a path inside the project, not the script: only the word `temper` counts.)
  if (stdinProgram && (bodies.length > 0 ? bodies : [text]).some(b => TEMPER_WORD.test(b) || /subprocess/i.test(b))) mentionLoud = true

  // Fail closed: the command may run the Temper script in a way the text does not show. Reading
  // commands and plain, readable calls are not touched. A script that is written and run, or a
  // program that holds the script name and a decision word, is.
  const verb = verbIn(text)
  const opaque =
    opaqueCall ||
    (verb && textNames && (ranCreated || wroteScript)) ||
    (mentionLoud && (verb || HIDES.test(text))) ||
    (verb && (dynamicCommand || (shellStdin && (mentionAny || /temper/i.test(text)))))
  return { commits, decisions, calls, stateOps, protectedWrites: [...new Set(writes)], uncheckable: [...new Set(uncheckable)], staged, opaque, alias }
}
