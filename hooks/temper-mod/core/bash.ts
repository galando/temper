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
export type DecisionCall = { kind: DecisionKind; stage?: string; id?: string; invalid?: boolean }

// A `scripts/temper state ...` call that moves or removes run state.
export type StateOp = { op: 'set'; key: string; value?: string } | { op: 'clear' } | { op: 'archive' }

export type BashClass = {
  commits: boolean
  decisions: DecisionKind[]
  calls: DecisionCall[]
  stateOps: StateOp[]
  // Every write onto a guarded path, and every write whose target cannot be checked.
  protectedWrites: string[]
  // The subset of protectedWrites that could not be resolved (fail closed).
  uncheckable: string[]
}

const PROTECTED: ReadonlyArray<readonly [ProtectedKind, RegExp]> = [
  ['events', /(^|\/)\.temper\/specs\/[^/\s]+\/events(\/|$)/],
  ['gates', /(^|\/)\.temper\/gates\.json$/],
  ['status', /(^|\/)\.temper\/status\.json$/],
  ['overrides', /(^|\/)\.temper\/overrides\.json$/],
  ['state', /(^|\/)\.temper\/build-state\.json$/],
  // Folders that hold guarded files: removing or replacing one removes them too.
  ['folder', /(^|\/)\.temper(\/specs(\/[^/\s]+)?)?\/?$/],
]

// Which guarded Temper path a path names, or null.
export function protectedKind(path: string): ProtectedKind | null {
  // `..` and `.` segments are collapsed first, so specs/a/../a/events is the events folder.
  const p = normalizePath(path)
  for (const [kind, re] of PROTECTED) if (re.test(p)) return kind
  return null
}

const MENTION = /\.temper\/(?:specs\/[^\s'"`]+\/events[^\s'"`]*|gates\.json|status\.json|overrides\.json|build-state\.json)/g

// The command names Temper state: strict mode, where an unresolvable write target is refused.
const NAMED = /\.temper|gates\.json|status\.json|overrides\.json|build-state\.json|\bevents\b/

// A path whose text names a guarded thing even when the rest cannot be resolved.
const NAMES_GUARDED = /gates\.json|status\.json|overrides\.json|build-state\.json|(^|\/)events(\/|$)|(^|\/)\.temper(\/|$)/

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

function globRegExp(glob: string): RegExp {
  let re = ''
  for (const c of glob) {
    if (c === '*') re += '.*'
    else if (c === '?') re += '.'
    else re += c.replace(/[.+^${}()|[\]\\]/g, '\\$&')
  }
  return new RegExp(`^${re}$`)
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
    for (let i = 0; i < ws.length; i++) {
      const t = ws[i]?.text ?? ''
      const m = /^(?:\d*|&)>{1,2}(?!&)(.*)$/.exec(t)
      if (m && !/^\d*>&/.test(t)) {
        const target = m[1] ? { text: m[1], dynamic: ws[i]?.dynamic ?? false } : ws[++i]
        if (target) check(target)
      } else if (/^\d*<</.test(t) || /^\d*<(?!\()/.test(t)) {
        if (t === '<' || /^\d*<<-?$/.test(t)) i++
      } else argv.push(ws[i] as Word)
    }

    let w = unwrap(argv)
    // `bash scripts/temper ...` and `sh -c STRING`.
    while (w.length > 0 && ['bash', 'sh', 'zsh', 'dash'].includes(BASE(w[0]?.text ?? ''))) {
      const rest = w.slice(1)
      const ci = rest.findIndex(x => /^-\w*c$/.test(x.text))
      if (ci >= 0) {
        const script = rest[ci + 1]?.text ?? ''
        for (const s of topStatements(script)) analyse(s, depth + 1)
        return
      }
      const nonOpt = rest.filter(x => !x.text.startsWith('-'))
      if (nonOpt.length === 0) return
      w = unwrap(nonOpt)
      if (BASE(w[0]?.text ?? '') === 'temper') break
      return
    }
    if (w.length === 0) return
    const cmd = BASE(w[0]?.text ?? '')
    const args = w.slice(1)
    const argText = args.map(a => expandVars(a.text, vars))

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
        if (t === '-c' || t === '-C') i += 2
        else if (t.startsWith('-')) i += 1
        else break
      }
      if (argText[i] === 'commit') commits = true
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
        calls.push({ kind: 'advance', stage: r[0] ? expandVars(r[0].text, vars) : undefined })
      } else if (sub === 'state' && sub2 === 'set') {
        const key = argText[i + 2] ?? ''
        const value = argText[i + 3]
        stateOps.push({ op: 'set', key, value })
        if (key === 'next_stage') {
          decisions.push('back')
          calls.push({ kind: 'back', stage: value })
        }
      } else if (sub === 'state' && (sub2 === 'clear' || sub2 === 'archive')) {
        stateOps.push({ op: sub2 })
      }
    }

    if (INTERPRETERS.test(cmd)) interpreter = true

    // ---- Write capable constructs ----
    if (WRITES_ANY.has(cmd)) for (const a of args) if (!a.text.startsWith('-') || a.dynamic) check(a)
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

  return { commits, decisions, calls, stateOps, protectedWrites: [...new Set(writes)], uncheckable: [...new Set(uncheckable)] }
}
