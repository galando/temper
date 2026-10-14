// What the guard reads in a Bash command (ADR 0013). It is not a shell parser: it splits the text into statements and
// words, honouring quotes (`'...'`, `"..."`, `$'...'` with its escapes, `$"..."`, a backslash), expands every word's
// brace lists as bash does, and looks for three things only:
//  - the temper CLI calls written out (`scripts/temper ...` or `temper ...`), so a call only the person may cause needs
//    the person's answer;
//  - a commit that switches the native pre-commit hook off (`--no-verify`, `-n`), a change of `core.hooksPath`, or a
//    config git is handed that can do either (an included file, an alias, a home folder);
//  - the paths the command writes: a redirect's target, and the files a writing program names (rm, mv, cp, tee,
//    sed -i and the like). The guard holds them to the same list of protected files as the editing tools.
// A program is named by its last path segment, without regard to case (macOS and Windows file systems ignore it), and
// by a glob that can expand to its name (`/usr/bin/gi[t]`). Anything this does not see (a variable, the output of a
// substitution, a script on disk, a program that builds a name at run time) passes. Temper is not a sandbox
// (docs/trust.md): the native hook and the editing tool rules are the hard guarantees.

export type ShellRead = {
  // Each temper call written out: its words after the script (`state advance plan_complete build`).
  calls: string[][]
  // `git commit --no-verify` or `-n`: the native pre-commit hook would not run.
  noVerify: boolean
  // A change of `core.hooksPath`, or a config handed to git that could make one: git would run other hooks than Temper's.
  hooksPath: boolean
  // The paths the command writes, as written.
  writes: string[]
  // The last word of a copy, move or link (`cp a b DIR`), kept apart from `writes`: when it is a folder the files land
  // inside it and the folder itself is not replaced; when it is a file it is written.
  targets: string[]
  // Where the files of such a command land when its last word is a folder (`DIR/a`, `DIR/b`).
  landings: string[]
  // A word that expands to more words than the guard reads (a brace list): what it writes is not known.
  tooMany: boolean
  // A temper call with an unquoted glob in a word before its reason (`temper o?erride ...`): bash may expand it to a
  // file's name, so the call it makes is not known.
  globCall: boolean
}

// A quoted character that bash does not expand (a brace list's braces and commas, a glob's characters) is kept apart
// from an unquoted one while the guard reads the command: a private use character stands for it until the words are
// expanded.
const MASK: Record<string, string> = { '{': '', '}': '', ',': '', '*': '', '?': '', '[': '', ']': '' }
const UNMASK: Record<string, string> = Object.fromEntries(Object.entries(MASK).map(([k, v]) => [v, k]))
const mask = (text: string): string => text.replace(/[{},*?[\]]/g, c => MASK[c] ?? c)
const unmask = (text: string): string => text.replace(/[-]/g, c => UNMASK[c] ?? c)

// The text of an ANSI-C quote (`$'...'`, without its quotes) as bash reads it: `\n`, `\t`, `\\`, `\'`, octal `\nnn`,
// `\xHH`, `\uHHHH`, `\UHHHHHHHH`, `\cX` and the rest.
function ansiC(s: string): string {
  const simple: Record<string, string> = { a: '\x07', b: '\b', e: '\x1b', E: '\x1b', f: '\f', n: '\n', r: '\r', t: '\t', v: '\v', '\\': '\\', "'": "'", '"': '"', '?': '?' }
  let out = ''
  for (let i = 0; i < s.length; i++) {
    const c = s[i] as string
    if (c !== '\\' || i + 1 >= s.length) {
      out += c
      continue
    }
    const n = s[++i] as string
    const digits = (re: RegExp, max: number): string => {
      let d = ''
      while (d.length < max && re.test(s[i + 1] ?? '')) d += s[++i]
      return d
    }
    if (n in simple) out += simple[n]
    else if (/[0-7]/.test(n)) out += String.fromCharCode(parseInt(n + digits(/[0-7]/, 2), 8) & 0xff)
    else if (n === 'x') {
      const h = digits(/[0-9a-fA-F]/, 2)
      out += h === '' ? '\\x' : String.fromCharCode(parseInt(h, 16))
    } else if (n === 'u' || n === 'U') {
      const h = digits(/[0-9a-fA-F]/, n === 'u' ? 4 : 8)
      out += h === '' ? `\\${n}` : String.fromCodePoint(Math.min(parseInt(h, 16), 0x10ffff))
    } else if (n === 'c' && i + 1 < s.length) out += String.fromCharCode((s[++i] as string).charCodeAt(0) & 31)
    else out += `\\${n}`
  }
  return out
}

// Where the ANSI-C quote that starts at `i` (`$'`) ends: the index of its closing quote, or the end of the text.
function ansiEnd(command: string, i: number): number {
  for (let j = i + 2; j < command.length; j++) {
    if (command[j] === '\\') j++
    else if (command[j] === "'") return j
  }
  return command.length
}

// Where the command substitution that starts at `i` (`$(` or a backquote) ends: the index of its `)` or backquote, or
// the end of the text.
function substitutionEnd(command: string, i: number): number {
  if (command[i] === '`') {
    for (let j = i + 1; j < command.length; j++) {
      if (command[j] === '\\') j++
      else if (command[j] === '`') return j
    }
    return command.length
  }
  let depth = 0
  for (let j = i + 1; j < command.length; j++) {
    const c = command[j]
    if (c === '\\') j++
    else if (c === "'") {
      const close = command.indexOf("'", j + 1)
      j = close < 0 ? command.length : close
    } else if (c === '"') {
      for (j++; j < command.length && command[j] !== '"'; j++) if (command[j] === '\\') j++
    } else if (c === '`') j = substitutionEnd(command, j)
    else if (c === '(') depth++
    else if (c === ')' && --depth === 0) return j
  }
  return command.length
}

// The text as statements of words, with quoted characters masked (see MASK). A quoted part keeps its spaces and loses
// its quotes; an operator outside quotes (`;`, `&`, `|`, a newline, a bracket) ends the statement. A redirect is a word
// of its own (`>`, `>>`). A command substitution (`$(...)` or a backquote, inside double quotes too) keeps its text in
// the word around it, as bash expands braces before it runs one (`{a,$(b)}`); its commands are statements of their
// own, after the others. The body of a here document is text, not commands: it is skipped.
function tokens(command: string): string[][] {
  const out: string[][] = []
  let words: string[] = []
  let word = ''
  let inWord = false
  // The here documents of the current line, in order: their end words, and whether `<<-` lets the end word be indented.
  const docs: Array<{ end: string; dash: boolean }> = []
  const inner: string[][] = []
  // A substitution at `i`: its commands are read, and its text joins the word (masked inside double quotes, where bash
  // expands no brace list of it). Returns where it ends.
  const substitution = (i: number, quoted: boolean): number => {
    const end = substitutionEnd(command, i)
    inner.push(...tokens(command.slice(command[i] === '`' ? i + 1 : i + 2, end)))
    const text = command.slice(i, end + 1)
    word += quoted ? mask(text) : text
    inWord = true
    return end
  }
  const endWord = () => {
    if (inWord) words.push(word)
    word = ''
    inWord = false
  }
  const endStatement = () => {
    endWord()
    if (words.length > 0) out.push(words)
    words = []
  }
  for (let i = 0; i < command.length; i++) {
    const ch = command[i] as string
    if (ch === "'") {
      const close = command.indexOf("'", i + 1)
      const end = close < 0 ? command.length : close
      word += mask(command.slice(i + 1, end))
      inWord = true
      i = end
    } else if (ch === '$' && command[i + 1] === "'") {
      // `$'...'`: a quote whose escapes bash decodes.
      const end = ansiEnd(command, i)
      word += mask(ansiC(command.slice(i + 2, end)))
      inWord = true
      i = end
    } else if (ch === '$' && command[i + 1] === '"') {
      // `$"..."`: a double quote (bash translates it, and with no translation it is the text as it is).
      continue
    } else if (ch === '"') {
      let j = i + 1
      for (; j < command.length && command[j] !== '"'; j++) {
        if (command[j] === '\\' && command[j + 1] === '\n') {
          j++
          continue
        }
        if (command[j] === '`' || (command[j] === '$' && command[j + 1] === '(')) {
          j = substitution(j, true)
          continue
        }
        if (command[j] === '\\' && j + 1 < command.length) j++
        word += mask(command[j] as string)
      }
      inWord = true
      i = j
    } else if (ch === '\\' && command[i + 1] === '\n') {
      // A line continuation: bash joins the two lines.
      i++
    } else if (ch === '\\' && i + 1 < command.length) {
      word += mask(command[i + 1] as string)
      inWord = true
      i++
    } else if (ch === '<' && command[i + 1] === '<' && command[i + 2] !== '<') {
      endWord()
      let j = i + 2
      const dash = command[j] === '-'
      if (dash) j++
      while (command[j] === ' ' || command[j] === '\t') j++
      let end = ''
      for (; j < command.length && !/[\s;&|<>()]/.test(command[j] as string); j++) if (command[j] !== "'" && command[j] !== '"' && command[j] !== '\\') end += command[j]
      if (end !== '') docs.push({ end, dash })
      words.push('<<')
      i = j - 1
    } else if (ch === '>' || ch === '<') {
      // A redirect: `>`, `>>`, `>|`, `&>`, `2>`, `>&`, `<>`. A file descriptor number before it belongs to it.
      if (/^\d+$/.test(word)) {
        word = ''
        inWord = false
      }
      endWord()
      let op = ch
      while (i + 1 < command.length && (command[i + 1] === '>' || command[i + 1] === '|' || command[i + 1] === '&')) op += command[++i]
      words.push(op)
    } else if (/\s/.test(ch)) {
      if (ch !== '\n') endWord()
      else {
        endStatement()
        // Skip each here document's body, up to its end word.
        for (const doc of docs.splice(0)) {
          while (i < command.length) {
            const next = command.indexOf('\n', i + 1)
            const line = command.slice(i + 1, next < 0 ? command.length : next)
            i = next < 0 ? command.length : next
            if ((doc.dash ? line.replace(/^\t+/, '') : line) === doc.end) break
          }
        }
      }
    } else if (ch === '&' && command[i + 1] === '>') {
      // `&>`: the redirect of both outputs; the `>` comes next.
      endWord()
    } else if (ch === '`' || (ch === '$' && command[i + 1] === '(')) {
      i = substitution(i, false)
    } else if (';&|()'.includes(ch)) {
      endStatement()
    } else {
      word += ch
      inWord = true
    }
  }
  endStatement()
  return [...out, ...inner]
}

// The text as statements of words, as bash reads its quotes (brace lists not expanded).
export function statements(command: string): string[][] {
  return tokens(command).map(st => st.map(unmask))
}

// Programs that write, remove or lock the files they name.
const WRITERS = new Set(['rm', 'rmdir', 'unlink', 'shred', 'truncate', 'touch', 'chmod', 'chown', 'tee', 'mv', 'cp', 'install', 'ln', 'rsync'])
// Every program whose words name what it writes: the writers, and sed and perl in place, and dd.
const WRITER_NAMES = [...WRITERS, 'sed', 'perl', 'dd']
// The ones whose last word is where they write.
const TO_LAST = new Set(['cp', 'install', 'ln', 'rsync'])
// The ones that take the folder they write into as `-t DIR`.
const TARGET_DIR = new Set(['cp', 'mv', 'install', 'ln'])
// A word that sets a variable (`NAME=value`).
const ASSIGNMENT = /^[A-Za-z_][A-Za-z0-9_]*=/

// A word's program name: its last path segment (`/usr/bin/env` is env).
const base = (word: string): string => word.split('/').pop() ?? ''

// Whether a (masked) word can name the program `name`: its last segment is the name without regard to case, or an
// unquoted glob with some literal text that matches it (`gi[t]`, `scripts/tempe?`). A glob of no literal text (`*`)
// names no program here.
function nameIs(word: string, name: string): boolean {
  const b = base(word)
  if (!/[*?[]/.test(b)) return unmask(b).toLowerCase() === name
  let re = ''
  let literal = 0
  for (let i = 0; i < b.length; i++) {
    const c = b[i] as string
    if (c === '*') re += '.*'
    else if (c === '?') re += '.'
    else if (c === '[' && bracketEnd(b, i) > 0) {
      const close = bracketEnd(b, i)
      const inner = b.slice(i + 1, close)
      // A class (`[[:alpha:]]`), an equivalence class or a collating symbol in it: read as any one character.
      if (/\[[:=.]/.test(inner)) re += '.'
      else re += `[${unmask(inner).replace(/^!/, '^').replace(/\\/g, '\\\\').replace(/\]/g, '\\]')}]`
      i = close
    } else {
      literal++
      re += unmask(c).replace(/[.*+?^${}()|\\[\]]/g, '\\$&')
    }
  }
  if (literal === 0) return false
  try {
    return new RegExp(`^${re}$`, 'i').test(name)
  } catch {
    return false
  }
}

// Where the bracket expression that opens at `i` closes, or -1: a `]` first in it (after any `!` or `^`) is one of its
// characters, and so is a `]` inside `[:...:]`, `[=...=]` or `[. ... .]`.
function bracketEnd(b: string, i: number): number {
  let j = i + 1
  if (b[j] === '!' || b[j] === '^') j++
  if (b[j] === ']') j++
  for (; j < b.length; j++) {
    const kind = b[j] === '[' ? b[j + 1] : undefined
    if (kind === ':' || kind === '=' || kind === '.') {
      const end = b.indexOf(`${kind}]`, j + 2)
      if (end < 0) return -1
      j = end + 1
    } else if (b[j] === ']') return j
  }
  return -1
}

// The temper script: a word naming it that sets no variable.
const isScript = (word: string): boolean => !ASSIGNMENT.test(unmask(word)) && nameIs(word, 'temper')

// Where a program the guard reads may run in a statement: every word that names it. Bash runs a program after
// `VAR=value` words, after a keyword (`then`, `do`, `{`, `!`, `coproc`, `function f {`), and after a program that runs
// the words that follow (`env`, `timeout 5`, `sudo -D /x`, `exec -a x`, `flock f`, a full path to one); no list of
// these is ever whole, so each word that names the program is read as where it starts. The price: a statement that
// only names such a command as words (`echo rm .temper/gates.json`) is read as running it.
function starts(words: readonly string[], named: (word: string) => boolean): number[] {
  const at: number[] = []
  for (let i = 0; i < words.length; i++) if (named(words[i] as string)) at.push(i)
  return at
}

// More words than one word of a command may expand to before the guard stops reading it.
const BRACE_CAP = 1024

// The first brace list bash expands in a word: the text before it, its words (`{a,b}`, or a sequence `{1..3}`,
// `{a..c}`, `{1..9..2}`) and the text after it. A `{` with no list or sequence in it, or one of `${`, stays as it is.
function braceList(w: string): { pre: string; alts: string[]; post: string } | null {
  for (let i = 0; i < w.length; i++) {
    if (w[i] !== '{' || w[i - 1] === '$') continue
    let depth = 0
    let end = -1
    const commas: number[] = []
    for (let j = i; j < w.length && end < 0; j++) {
      if (w[j] === '{') depth++
      else if (w[j] === '}' && --depth === 0) end = j
      else if (w[j] === ',' && depth === 1) commas.push(j)
    }
    if (end < 0) continue
    let alts: string[] | null = null
    if (commas.length > 0) {
      alts = []
      let from = i + 1
      for (const c of commas) {
        alts.push(w.slice(from, c))
        from = c + 1
      }
      alts.push(w.slice(from, end))
    } else alts = sequence(w.slice(i + 1, end))
    if (alts !== null) return { pre: w.slice(0, i), alts, post: w.slice(end + 1) }
  }
  return null
}

// The words of a sequence `x..y` or `x..y..step` (two integers, or two letters), at most one more than the cap; null when
// the text is no sequence. Integers keep the width of a bound written with a leading zero (`{08..10}`).
function sequence(text: string): string[] | null {
  const num = /^(-?\d+)\.\.(-?\d+)(?:\.\.(-?\d+))?$/.exec(text)
  const chr = /^([A-Za-z])\.\.([A-Za-z])(?:\.\.(-?\d+))?$/.exec(text)
  const m = num ?? chr
  if (m === null) return null
  const from = num !== null ? Number(m[1]) : (m[1] as string).charCodeAt(0)
  const to = num !== null ? Number(m[2]) : (m[2] as string).charCodeAt(0)
  const step = Math.abs(Number(m[3] ?? 1)) || 1
  const padded = num !== null && [m[1], m[2]].some(b => /^-?0\d/.test(b as string))
  const width = padded ? Math.max((m[1] as string).length, (m[2] as string).length) : 0
  const out: string[] = []
  for (let v = from; (from <= to ? v <= to : v >= to) && out.length <= BRACE_CAP; v += from <= to ? step : -step) {
    out.push(num !== null ? (v < 0 ? '-' + String(-v).padStart(width - 1, '0') : String(v).padStart(width, '0')) : String.fromCharCode(v))
  }
  return out
}

// A word as bash expands its brace lists, each word as many times as bash gives it (`-m {-n,-n}` is `-m -n -n`); null
// when it expands to more than the cap.
function braces(word: string): string[] | null {
  const out: string[] = []
  let steps = 0
  const expand = (w: string): boolean => {
    if (++steps > BRACE_CAP * 8) return false
    const list = braceList(w)
    if (list === null) {
      out.push(w)
      return out.length <= BRACE_CAP
    }
    return list.alts.every(alt => expand(`${list.pre}${alt}${list.post}`))
  }
  return expand(word) ? out : null
}

type Written = { writes: string[]; targets: string[]; landings: string[] }

// The paths a statement writes: a redirect's target, and the files a writing program names. `plain` are the words,
// `masked` the same words with their quoted characters masked (to tell what names a program), and `known` says whether
// the guard read a word whole (a word past the cap is not).
function written(plain: string[], masked: string[], known: (word: string) => void): Written {
  const out: Written = { writes: [], targets: [], landings: [] }
  for (let i = 0; i < plain.length; i++) {
    const op = plain[i] as string
    const to = plain[i + 1]
    if (to === undefined) continue
    // `>`, `>>`, `>|` and `<>` write their file; `>&` and `>>&` write a file unless they name a file descriptor (`2>&1`).
    if (/^(?:>[>|]?|<>)$/.test(op) || (/^>>?&$/.test(op) && !/^(?:\d+|-)$/.test(to))) {
      known(to)
      out.writes.push(to)
    }
  }
  for (let i = 0; i < masked.length; i++) {
    const cmd = WRITER_NAMES.find(n => nameIs(masked[i] as string, n))
    if (cmd === undefined) continue
    const w = programWrites(plain, i, cmd, known)
    out.writes.push(...w.writes)
    out.targets.push(...w.targets)
    out.landings.push(...w.landings)
  }
  return out
}

const lastName = (path: string): string => path.replace(/\/+$/, '').split('/').pop() ?? path

// The files the writing program `cmd` at `at` names.
function programWrites(words: string[], at: number, cmd: string, known: (word: string) => void): Written {
  const out: Written = { writes: [], targets: [], landings: [] }
  const edits = cmd === 'sed' || cmd === 'perl'
  // The program's file words: no flag, no redirect and its file, and for sed and perl no script (`-e x`, or sed's
  // first word when no -e names the script).
  const args: string[] = []
  let script = false
  // `cp -t DIR SRC...` (also mv, install, ln): the files land in DIR.
  let into: string | null = null
  // `cp -T`, `mv --no-target-directory`: the last word is the file itself, never a folder to land in.
  let noTarget = false
  for (let i = at + 1; i < words.length; i++) {
    const w = words[i] as string
    const cluster = /^-([A-Za-su-z]*)t(.*)$/.exec(w)
    const long = w.startsWith('--t') && '--target-directory'.startsWith(w.split('=')[0] as string)
    if (/^[<>]/.test(w)) i++
    // `-t DIR`, `-at DIR`, `-tDIR`, `--target-directory DIR`, `--target=DIR` (git and coreutils take an abbreviation).
    else if (TARGET_DIR.has(cmd) && cluster !== null) into = cluster[2] !== '' ? (cluster[2] as string) : (words[++i] ?? null)
    else if (TARGET_DIR.has(cmd) && long) into = w.includes('=') ? w.slice(w.indexOf('=') + 1) : (words[++i] ?? null)
    else if (edits && ['-e', '-f', '--expression', '--file'].includes(w)) {
      script = true
      i++
    } else if (edits && (/^--(?:expression|file)=/.test(w) || /^-[A-Za-z]*e./.test(w))) {
      // The script in the same word: `--expression=s/a/b/`, `-es/a/b/`.
      script = true
    } else if (edits && /^-[A-Za-z]*e$/.test(w)) {
      script = true
      i++
    } else if (!w.startsWith('-')) {
      known(w)
      args.push(w)
    } else if (/^-[A-Za-z]*T[A-Za-z]*$/.test(w) || w === '--no-target-directory') noTarget = true
  }
  if (cmd === 'sed' && !script) args.shift()
  if (into !== null) {
    known(into)
    const dir = into.replace(/\/+$/, '')
    out.writes.push(...(cmd === 'mv' ? args : []), ...args.map(a => `${dir}/${lastName(a)}`))
    return out
  }
  if (WRITERS.has(cmd)) {
    // A copy, move or link into a folder (`cp a .temper/specs/pw/`): the files land in it, and it is not replaced. Its
    // last word is a target, not a write, so that another statement's write of the same path is still read as one. rsync
    // with a source that ends in `/` copies that folder's files, whose names the guard does not know.
    const contents = cmd === 'rsync' && args.slice(0, -1).some(a => a.endsWith('/'))
    const sources = cmd === 'mv' ? args.slice(0, -1) : []
    if ((TO_LAST.has(cmd) || cmd === 'mv') && args.length >= 2 && !noTarget && !contents) {
      const target = args[args.length - 1] as string
      out.writes.push(...sources)
      out.targets.push(target)
      out.landings.push(...args.slice(0, -1).map(a => `${target.replace(/\/+$/, '')}/${lastName(a)}`))
    } else out.writes.push(...(TO_LAST.has(cmd) ? args.slice(-1) : args))
    return out
  }
  // sed -i, perl -i: they rewrite the files they are given.
  if (edits && words.slice(at + 1).some(w => /^-[A-Za-z]*i/.test(w) || w === '--in-place' || w.startsWith('--in-place='))) out.writes.push(...args)
  else if (cmd === 'dd') out.writes.push(...args.filter(a => a.startsWith('of=')).map(a => a.slice(3)))
  return out
}

// The git command that starts at `at`: its subcommand, the words after it, and git's own options before it.
function gitParts(words: string[], at: number): { sub: string; rest: string[]; opts: string[] } {
  const opts: string[] = []
  let i = at + 1
  for (; i < words.length; i++) {
    const w = words[i] as string
    if (['-c', '-C', '--git-dir', '--work-tree', '--config-env', '--namespace'].includes(w)) {
      opts.push(w, words[i + 1] ?? '')
      i++
    } else if (w.startsWith('-')) opts.push(w)
    else break
  }
  return { sub: words[i] ?? '', rest: words.slice(i + 1), opts }
}

const HOOKS_PATH = /core\.hookspath/i
// A config key that loads another config file, which can set core.hooksPath.
const INCLUDE = /^include(?:if\..*)?\.path$/i
// A git alias: its body runs as a git command (or, after `!`, as a shell command).
const ALIAS = /^alias\.[^=]+$/i

// `git commit` with `--no-verify` or `-n`. In a cluster of short flags a letter that takes a value (`-m`, `-F`, `-C`,
// `-c`, `-t`) takes the rest of the cluster, or the next word.
function skipsHook(args: string[]): boolean {
  for (let i = 0; i < args.length; i++) {
    const w = args[i] as string
    // git takes an unambiguous abbreviation of a long option: `--no-veri` and `--no-verif` are `--no-verify`.
    if (/^--no-veri(?:fy?)?$/.test(w)) return true
    if (w === '--') return false
    if (!/^-[A-Za-z]+$/.test(w)) continue
    for (let k = 1; k < w.length; k++) {
      const letter = w[k] as string
      if (letter === 'n') return true
      if ('mFCct'.includes(letter)) {
        if (k === w.length - 1) i++
        break
      }
    }
  }
  return false
}

// What a git alias body does, read as the command it runs, added to `read`.
function aliasBody(read: ShellRead, body: string): void {
  const text = body.trim()
  const sub = readShell(text.startsWith('!') ? text.slice(1) : `git ${text}`)
  read.noVerify ||= sub.noVerify
  read.hooksPath ||= sub.hooksPath
  read.tooMany ||= sub.tooMany
  read.globCall ||= sub.globCall
  read.calls.push(...sub.calls)
  read.writes.push(...sub.writes)
  read.targets.push(...sub.targets)
  read.landings.push(...sub.landings)
}

// One config pair handed to git for this call (`-c key=value`, `--config-env key=VAR`): a hooks path, an included file
// or an alias. `known`: the value is in the text (an environment variable's value is not).
function configPair(read: ShellRead, pair: string, known: boolean): void {
  const eq = pair.indexOf('=')
  const key = eq < 0 ? pair : pair.slice(0, eq)
  if (HOOKS_PATH.test(key) || INCLUDE.test(key)) read.hooksPath = true
  if (ALIAS.test(key)) {
    if (!known) read.hooksPath = true
    else aliasBody(read, eq < 0 ? '' : pair.slice(eq + 1))
  }
}

export function readShell(command: string): ShellRead {
  const read: ShellRead = { calls: [], noVerify: false, hooksPath: false, writes: [], targets: [], landings: [], tooMany: false, globCall: false }
  // git reads the config of the home folder it is given (`HOME=/tmp/h git ci`, `$XDG_CONFIG_HOME/git/config`), which
  // can hold an alias or a hooks path.
  let home = false
  let runsGit = false
  for (const raw of tokens(command)) {
    // Every word as bash expands its brace lists, so no list hides a program, a call or a path (`{git,commit}`). A word
    // past the cap is read as it is: it is refused when it holds a list of words (which could name a program) or when
    // it is a path a program writes.
    const masked: string[] = []
    const over = new Set<string>()
    for (const w of raw) {
      const all = braces(w)
      if (all !== null) masked.push(...all)
      else {
        masked.push(w)
        over.add(unmask(w))
        if (/\{[^{}]*,/.test(w)) read.tooMany = true
      }
    }
    const words = masked.map(unmask)
    const w = written(words, masked, word => {
      if (over.has(word)) read.tooMany = true
    })
    read.writes.push(...w.writes)
    read.targets.push(...w.targets)
    read.landings.push(...w.landings)
    // A variable set to name core.hooksPath, before git or in a statement of its own (`export GIT_CONFIG_KEY_0=...`):
    // git reads its config from the environment it is given. Also a config file, an included file or an alias handed
    // to git that way.
    for (const x of words) {
      if (!ASSIGNMENT.test(x)) continue
      if (/^(?:HOME|XDG_CONFIG_HOME)=/.test(x)) home = true
      if (HOOKS_PATH.test(x)) read.hooksPath = true
      if (/^GIT_CONFIG(?:_[A-Z0-9_]*)?=/i.test(x) && /include(?:if\.[^=\s]*)?\.path|alias\.|^GIT_CONFIG(?:_GLOBAL|_SYSTEM)?=/i.test(x)) read.hooksPath = true
    }
    for (const gitAt of starts(masked, x => nameIs(x, 'git'))) {
      runsGit = true
      const git = gitParts(words, gitAt)
      // `git -c core.hooksPath=...`, `git -c include.path=...`, `git -c alias.x=...`, `git --config-env ...`.
      if (git.opts.some(o => HOOKS_PATH.test(o))) read.hooksPath = true
      git.opts.forEach((o, i) => {
        if (o === '-c') configPair(read, git.opts[i + 1] ?? '', true)
        else if (o === '--config-env') configPair(read, git.opts[i + 1] ?? '', false)
        else if (o.startsWith('--config-env=')) configPair(read, o.slice('--config-env='.length), false)
      })
      if (git.sub === 'commit' && skipsHook(git.rest)) read.noVerify = true
      if (git.sub === 'config') {
        const at = git.rest.findIndex(x => HOOKS_PATH.test(x))
        const reads = git.rest.some(x => ['--get', '--get-all', '--get-regexp', '--list', '-l'].includes(x))
        // `git config core.hooksPath` with no value reads it; with a value, or with --unset, it changes it.
        if (at >= 0 && !reads && (git.rest[at + 1] !== undefined || git.rest.some(x => x.startsWith('--unset') || x === '--replace-all' || x === '--add'))) read.hooksPath = true
        // Removing or renaming the core section drops core.hooksPath with it (also git 2.46's `git config remove-section`).
        const section = git.rest.findIndex(x => ['--remove-section', '--rename-section', 'remove-section', 'rename-section'].includes(x))
        if (section >= 0 && (git.rest.slice(section + 1).find(x => !x.startsWith('-')) ?? '').toLowerCase() === 'core') read.hooksPath = true
        // git 2.46's `git config unset core.hooksPath`.
        if (at >= 0 && !reads && git.rest.slice(0, at).includes('unset')) read.hooksPath = true
        // A config file included from the repository's config can set core.hooksPath (include.path, includeIf.*.path).
        const include = git.rest.findIndex(x => INCLUDE.test(x))
        if (include >= 0 && !reads && git.rest.slice(include + 1).some(x => !x.startsWith('-'))) read.hooksPath = true
        // An alias written into the config runs its body later: read the body as the command it is.
        const alias = git.rest.findIndex(x => ALIAS.test(x))
        if (alias >= 0 && !reads && git.rest[alias + 1] !== undefined) aliasBody(read, git.rest[alias + 1] as string)
      }
    }
    // Every word that names the script starts a call: the words after it are the call's.
    for (let i = 0; i < masked.length; i++) {
      if (!isScript(masked[i] as string)) continue
      read.calls.push(words.slice(i + 1))
      const rest = masked.slice(i + 1)
      const reason = rest.findIndex(x => x === '--reason' || x.startsWith('--reason='))
      if (rest.slice(0, reason < 0 ? rest.length : reason).some(x => /[*?]|\[.*\]/.test(x))) read.globCall = true
    }
  }
  if (home && runsGit) read.hooksPath = true
  return read
}

// A call's words with its leading flags left out (`--spec-path X` takes a value).
export function callWords(words: readonly string[]): string[] {
  let i = 0
  while (i < words.length && (words[i] as string).startsWith('-')) i += words[i] === '--spec-path' ? 2 : 1
  return words.slice(i)
}

// Whether `words` are the call the CLI wrote in `written` (a command line it printed), word for word. A placeholder in
// braces (`{reason}`) stands for one word that is not empty.
export function sameCall(written: string, words: readonly string[]): boolean {
  const st = tokens(written)[0] ?? []
  const at = st.findIndex(isScript)
  if (at < 0) return false
  const want = callWords(st.slice(at + 1).map(unmask))
  const have = callWords(words)
  return want.length === have.length && want.every((w, i) => (/^\{[^{}]*\}$/.test(w) ? (have[i] ?? '') !== '' : w === have[i]))
}
