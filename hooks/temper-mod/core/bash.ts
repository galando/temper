// Bash classifier. Best effort by design: Bash can write files in ways no pattern
// catches. The hard guarantee covers Write, Edit, NotebookEdit and `git commit`; the
// native pre-commit hook stays as the second layer.

import { normalizePath } from './paths'

export type ProtectedKind = 'events' | 'gates' | 'status' | 'overrides' | 'state'

export type DecisionKind = 'override' | 'accept' | 'advance'

// A decision CLI call as the command spells it: which kind, and the phase (stage) and finding
// id it names when it names them.
export type DecisionCall = { kind: DecisionKind; stage?: string; id?: string }

export type BashClass = {
  commits: boolean
  decisions: DecisionKind[]
  calls: DecisionCall[]
  protectedWrites: string[]
}

const PROTECTED: ReadonlyArray<readonly [ProtectedKind, RegExp]> = [
  ['events', /(^|\/)\.temper\/specs\/[^/\s]+\/events(\/|$)/],
  ['gates', /(^|\/)\.temper\/gates\.json$/],
  ['status', /(^|\/)\.temper\/status\.json$/],
  ['overrides', /(^|\/)\.temper\/overrides\.json$/],
  ['state', /(^|\/)\.temper\/build-state\.json$/],
]

// Which guarded Temper state file a path names, or null.
export function protectedKind(path: string): ProtectedKind | null {
  // `..` and `.` segments are collapsed first, so specs/a/../a/events is the events folder.
  const p = normalizePath(path)
  for (const [kind, re] of PROTECTED) if (re.test(p)) return kind
  return null
}

const MENTION = /\.temper\/(?:specs\/[^\s'"`]+\/events[^\s'"`]*|gates\.json|status\.json|overrides\.json|build-state\.json)/g

// Any mention of a protected name: when a write target cannot be resolved (a shell variable,
// an unknown directory) the command is judged by this, conservatively.
const NAMED = /\.temper|gates\.json|status\.json|overrides\.json|build-state\.json|\bevents\b/

// Common command wrappers, stripped before a segment is classified so that `env -i temper
// override`, `timeout 5 git commit`, `nice`, `nohup`, `xargs`, `sudo`, `command`, `builtin`
// and `exec` do not hide the command they run. Each pattern removes one wrapper layer.
// A command word in quotes, as in `"git" commit`.
const QUOTED_WORD = /^(['"])([\w./-]+)\1(?=\s|$)/

const WRAPPERS = [
  /^[A-Za-z_]\w*=\S*\s+/,
  /^sudo\s+(?:(?:-u|-g|-h|-p|-C|-D|-R|-T)\s+\S+\s+|-\S+\s+)*/,
  /^env\s+(?:(?:-u|-C|-S)\s+\S+\s+|--(?:unset|chdir)=\S+\s+|-\S*\s+|[A-Za-z_]\w*=\S*\s+)*/,
  /^timeout\s+(?:(?:-s|-k|--signal|--kill-after)\s+\S+\s+|-\S+\s+)*\d[\d.]*[smhd]?\s+/,
  /^nice\s+(?:-n\s+-?\d+\s+|-\d+\s+)?/,
  /^ionice\s+(?:(?:-c|-n|-p)\s*\d+\s+|-t\s+)*/,
  /^xargs\s+(?:(?:-n|-P|-I|-L|-s|-d|-E)\s*\S+\s+|-\S+\s+)*/,
  /^(?:time|command|builtin|exec|nohup|stdbuf|setsid|then|do|else|!|\{)\s+(?:-\w+\s+)*/,
  /^--\s+/,
  /^\\+(?=\S)/,
  QUOTED_WORD,
]

function stripWrappers(seg: string): string {
  let s = seg.trim()
  for (let again = true; again; ) {
    again = false
    for (const re of WRAPPERS) {
      const t = s.replace(re, re === QUOTED_WORD ? '$2' : '')
      if (t !== s) {
        s = t.trim()
        again = true
      }
    }
  }
  return s
}

// Break a command line into the simple commands it runs. Quotes are not parsed: a
// fragment that merely sits inside a quoted string never starts with a command word.
function segments(command: string): string[] {
  return command
    .split(/&&|\|\||[;|\n]|\$\(|`|\(|\)/)
    .map(stripWrappers)
    .filter(s => s.length > 0)
}

const SHELL_C = /^(?:bash|sh|zsh|dash)\s+(?:-\w+\s+)*-\w*c\s+['"]?/
const EVAL = /^eval\s+['"]?/
const GIT_COMMIT = /^(?:\S*\/)?git(?:\s+(?:-[cC]\s+\S+|--[\w-]+(?:=\S+)?|-[a-zA-Z]))*\s+commit(?:['")\s]|$)/
// `temper` global options may come before the subcommand (`temper --spec-path P override ...`).
const DECISION = /^(?:(?:bash|sh|zsh)\s+)?['"]?(?:\S*\/)?temper['"]?(?:\s+(?:--spec-path\s+\S+|-{1,2}[\w-]+(?:=\S+)?))*\s+(override|evidence\s+accept|state\s+advance)\b(.*)$/

function unwrapShell(seg: string): string {
  const t = seg.replace(SHELL_C, '').replace(EVAL, '')
  return t === seg ? seg : stripWrappers(t)
}

// Commands that write every path they name, and commands whose last path is the destination.
const WRITES_ANY = new Set(['tee', 'rm', 'touch', 'truncate', 'dd', 'shred', 'unlink'])
const WRITES_LAST = new Set(['cp', 'mv', 'install', 'ln', 'rsync'])
const INTERPRETERS = /^(?:python[\d.]*|node|deno|bun|perl|ruby|php|osascript)$/

// Quotes and backslashes are removed before any path is judged, so `gates.js''on` and
// `"gates".json` name the file they spell.
const unquote = (t: string): string => t.replace(/['"\\]/g, '')

function tokens(seg: string): string[] {
  return seg
    .split(/\s+/)
    .map(t => unquote(t).replace(/^of=/, ''))
    .filter(Boolean)
}

function decisionCall(sub: string, rest: string): DecisionCall {
  if (sub.startsWith('evidence')) {
    return { kind: 'accept', stage: /--stage[=\s]+(\S+)/.exec(rest)?.[1], id: /--id[=\s]+(\S+)/.exec(rest)?.[1] }
  }
  const first = /^\s+(\S+)/.exec(rest)?.[1]
  const stage = first && !first.startsWith('-') ? unquote(first) : undefined
  return { kind: sub.startsWith('state') ? 'advance' : 'override', stage }
}

// Where a path lands after the `cd`s so far: null when it cannot be known (a variable, `~`).
function resolveTarget(cwd: string | null, raw: string): string | null {
  const t = unquote(raw)
  if (/[$`]|^~/.test(t)) return null
  if (t.startsWith('/')) return normalizePath(t)
  if (cwd === null) return null
  return normalizePath(cwd ? `${cwd}/${t}` : t)
}

const GLOB = /[*?[\]{}]/
const PROTECTED_NAMES = ['.temper', 'events', 'gates.json', 'status.json', 'overrides.json', 'build-state.json']

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
  return path.split('/').some(seg => GLOB.test(seg) && PROTECTED_NAMES.some(n => globRegExp(seg.replace(/[[\]{}]/g, '?')).test(n)))
}

// A folder that holds guarded files: writing into it (tar -C, cp -t, rsync) can overwrite them.
const GUARDED_DIR = /(^|\/)\.temper(\/specs\/[^/]+)?\/?$/

const CD = /^(?:cd|pushd)\s+(\S+)/

export function classifyBash(command: string): BashClass {
  // `>|` is a redirect that overrides noclobber; the pipe split below would cut it in two.
  const segs = segments(command.replace(/>\|/g, '>')).map(unwrapShell)
  const decisions: DecisionKind[] = []
  const calls: DecisionCall[] = []
  let commits = false
  let interpreter = false
  let sawSed = false
  const writes: string[] = []
  // The working directory the command has moved to (relative to where it started).
  let cwd: string | null = ''

  // A write to `raw` is protected when it lands on a guarded file, when a glob in it could
  // match a guarded name, or when it cannot be resolved and the command names a guarded
  // path anywhere. Only called for a redirect target or the argument of a write verb.
  const check = (raw: string, isDir = false) => {
    const where = resolveTarget(cwd, raw)
    if (where === null) {
      if (NAMED.test(command)) writes.push(unquote(raw))
    } else if (GLOB.test(where) ? globCouldMatch(where) : protectedKind(where) || (isDir && GUARDED_DIR.test(where))) {
      writes.push(where)
    }
  }

  for (const seg of segs) {
    if (GIT_COMMIT.test(seg)) commits = true
    const d = DECISION.exec(seg)
    if (d) {
      const sub = d[1] ?? ''
      decisions.push(sub.startsWith('evidence') ? 'accept' : sub.startsWith('state') ? 'advance' : 'override')
      calls.push(decisionCall(sub, d[2] ?? ''))
    }
    if (INTERPRETERS.test(seg.split(/\s+/)[0] ?? '')) interpreter = true

    const cd = CD.exec(seg)
    if (cd) {
      cwd = resolveTarget(cwd, cd[1] ?? '')
      continue
    }

    const t = tokens(seg)
    const cmd = (t[0] ?? '').replace(/^.*\//, '')
    const args = t.slice(1)
    if (WRITES_ANY.has(cmd)) args.forEach(a => check(a))
    if (WRITES_LAST.has(cmd)) {
      // `cp -t DIR a b` and `--target-directory=DIR` name the destination folder first.
      args.forEach((a, i) => {
        if (a === '-t' || a === '--target-directory') check(args[i + 1] ?? '', true)
        else if (a.startsWith('--target-directory=')) check(a.slice(19), true)
      })
      const last = args[args.length - 1]
      if (last && !last.startsWith('-')) check(last, cmd === 'rsync')
    }
    if (cmd === 'sed' || cmd === 'perl' || cmd === 'awk') {
      if (args.some(a => a === '--in-place' || /^-[a-zA-Z]*i/.test(a))) args.forEach(a => check(a))
      // sed's `w FILE` command and `s///w FILE` flag write the file named after them.
      if (cmd === 'sed') sawSed = true
    }
    if (cmd === 'curl') {
      args.forEach((a, i) => {
        if (a === '-o' || a === '--output') check(args[i + 1] ?? '')
        else if (a.startsWith('--output=')) check(a.slice(9))
        else if (/^-[a-zA-Z]*o.+/.test(a) && !a.startsWith('--')) check(a.replace(/^-[a-zA-Z]*o/, ''))
      })
    }
    if (cmd === 'wget') {
      args.forEach((a, i) => {
        if (a === '-O' || a === '--output-document') check(args[i + 1] ?? '')
        else if (a.startsWith('--output-document=')) check(a.slice(18))
        else if (a.startsWith('-O') && a.length > 2) check(a.slice(2))
      })
    }
    if (cmd === 'tar') {
      args.forEach((a, i) => {
        if (a === '-C' || a === '--directory') check(args[i + 1] ?? '', true)
        else if (a.startsWith('--directory=')) check(a.slice(12), true)
        else if (a.startsWith('-C') && a.length > 2) check(a.slice(2), true)
      })
    }
    for (const m of seg.matchAll(/\d?>{1,2}(?!&)\s*([^\s;&|)<>]+)/g)) check(m[1] ?? '')
  }

  // sed's `w FILE` can sit after a `;` that the segment split cut, so the whole command is read.
  if (sawSed) for (const m of command.matchAll(/(?:^|[\s;{}/'"])w\s+([^\s;}'"]+)/g)) check(m[1] ?? '')

  if (interpreter) writes.push(...(command.match(MENTION) ?? []))

  return { commits, decisions, calls, protectedWrites: [...new Set(writes)] }
}
