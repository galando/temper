// What the guard reads in a Bash command (ADR 0013). It is not a shell parser: it splits the text into statements and
// words, honouring quotes, and looks for three things only:
//  - the temper CLI calls written out (`scripts/temper ...` or `temper ...`), so a call only the person may cause needs
//    the person's answer;
//  - a commit that switches the native pre-commit hook off (`--no-verify`, `-n`) or a change of `core.hooksPath`;
//  - the paths the command writes: a redirect's target, and the files a writing program names (rm, mv, cp, tee,
//    sed -i and the like). The guard holds them to the same list of protected files as the editing tools.
// Anything this does not see (a variable, the output of a substitution, a script on disk, a program that builds a name at
// run time) passes. Temper is not a sandbox (docs/trust.md): the native hook and the editing tool rules are the hard
// guarantees.

export type ShellRead = {
  // Each temper call written out: its words after the script (`state advance plan_complete build`).
  calls: string[][]
  // `git commit --no-verify` or `-n`: the native pre-commit hook would not run.
  noVerify: boolean
  // A change of `core.hooksPath`: git would run other hooks than Temper's.
  hooksPath: boolean
  // The paths the command writes, as written.
  writes: string[]
  // A word that expands to more words than the guard reads (a brace list): what it writes is not known.
  tooMany: boolean
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

// The text as statements of words. A quoted part keeps its spaces and loses its quotes; an operator outside quotes
// (`;`, `&`, `|`, a newline, a bracket) ends the statement. A redirect is a word of its own (`>`, `>>`). A command
// substitution (`$(...)` or a backquote, inside double quotes too) keeps its text in the word around it, as bash
// expands braces before it runs one (`{a,$(b)}`); its commands are statements of their own, after the others. The body
// of a here document is text, not commands: it is skipped.
export function statements(command: string): string[][] {
  const out: string[][] = []
  let words: string[] = []
  let word = ''
  let inWord = false
  // The here documents of the current line, in order: their end words, and whether `<<-` lets the end word be indented.
  const docs: Array<{ end: string; dash: boolean }> = []
  const inner: string[][] = []
  // A substitution at `i`: its commands are read, and its text joins the word. Returns where it ends.
  const substitution = (i: number): number => {
    const end = substitutionEnd(command, i)
    inner.push(...statements(command.slice(command[i] === '`' ? i + 1 : i + 2, end)))
    word += command.slice(i, end + 1)
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
      word += command.slice(i + 1, end)
      inWord = true
      i = end
    } else if (ch === '"') {
      let j = i + 1
      for (; j < command.length && command[j] !== '"'; j++) {
        if (command[j] === '\\' && command[j + 1] === '\n') {
          j++
          continue
        }
        if (command[j] === '`' || (command[j] === '$' && command[j + 1] === '(')) {
          j = substitution(j)
          continue
        }
        if (command[j] === '\\' && j + 1 < command.length) j++
        word += command[j]
      }
      inWord = true
      i = j
    } else if (ch === '\\' && command[i + 1] === '\n') {
      // A line continuation: bash joins the two lines.
      i++
    } else if (ch === '\\' && i + 1 < command.length) {
      word += command[i + 1]
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
      i = substitution(i)
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

const SCRIPT = /(?:^|\/)temper$/
// Programs that write, remove or lock the files they name.
const WRITERS = new Set(['rm', 'rmdir', 'unlink', 'shred', 'truncate', 'touch', 'chmod', 'chown', 'tee', 'mv', 'cp', 'install', 'ln', 'rsync'])
// The ones whose last word is where they write.
const TO_LAST = new Set(['cp', 'install', 'ln', 'rsync'])
// The ones that take the folder they write into as `-t DIR`.
const TARGET_DIR = new Set(['cp', 'mv', 'install', 'ln'])

// A word's program name: its last path segment (`/usr/bin/env` is env).
const base = (word: string): string => word.split('/').pop() ?? ''

// Where a program the guard reads may run in a statement: every word that names it. Bash runs a program after
// `VAR=value` words, after a keyword (`then`, `do`, `{`, `!`, `coproc`, `function f {`), and after a program that runs
// the words that follow (`env`, `timeout 5`, `sudo -D /x`, `exec -a x`, `flock f`, a full path to one); no list of
// these is ever whole, so each word that names the program is read as where it starts. The price: a statement that
// only names such a command as words (`echo rm .temper/gates.json`) is read as running it.
function starts(words: string[], named: (cmd: string) => boolean): number[] {
  const at: number[] = []
  for (let i = 0; i < words.length; i++) if (named(base(words[i] as string))) at.push(i)
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

// A word as bash expands its brace lists, without the words it repeats; null when it expands to more than the cap.
function braces(word: string): string[] | null {
  const out = new Set<string>()
  const seen = new Set<string>()
  const expand = (w: string): boolean => {
    if (seen.has(w)) return true
    seen.add(w)
    if (seen.size > BRACE_CAP * 8) return false
    const list = braceList(w)
    if (list === null) {
      out.add(w)
      return out.size <= BRACE_CAP
    }
    return list.alts.every(alt => expand(`${list.pre}${alt}${list.post}`))
  }
  return expand(word) ? [...out] : null
}

const WRITES = (cmd: string): boolean => WRITERS.has(cmd) || cmd === 'sed' || cmd === 'perl' || cmd === 'dd'

// The paths a statement writes: a redirect's target, and the files a writing program names. `expand` gives a word's
// brace expansion.
function written(words: string[], expand: (word: string) => string[]): string[] {
  const out: string[] = []
  for (let i = 0; i < words.length; i++) {
    const op = words[i] as string
    const to = words[i + 1]
    if (to === undefined) continue
    // `>`, `>>`, `>|` and `<>` write their file; `>&` and `>>&` write a file unless they name a file descriptor (`2>&1`).
    if (/^(?:>[>|]?|<>)$/.test(op) || (/^>>?&$/.test(op) && !/^(?:\d+|-)$/.test(to))) out.push(...expand(to))
  }
  for (const at of starts(words, WRITES)) out.push(...programWrites(words, at, expand))
  return out
}

// The files the writing program at `at` names.
function programWrites(words: string[], at: number, expand: (word: string) => string[]): string[] {
  const out: string[] = []
  const cmd = base(words[at] as string)
  const edits = cmd === 'sed' || cmd === 'perl'
  // The program's file words: no flag, no redirect and its file, and for sed and perl no script (`-e x`, or sed's
  // first word when no -e names the script).
  const args: string[] = []
  let script = false
  // `cp -t DIR SRC...` (also mv, install, ln): the files land in DIR.
  let into: string | null = null
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
    } else if (!w.startsWith('-')) args.push(...expand(w))
  }
  if (cmd === 'sed' && !script) args.shift()
  if (into !== null) {
    const dir = into.replace(/\/+$/, '')
    out.push(...(cmd === 'mv' ? args : []), ...args.map(a => `${dir}/${a.split('/').pop() ?? a}`))
  } else if (WRITERS.has(cmd)) out.push(...(TO_LAST.has(cmd) ? args.slice(-1) : args))
  // sed -i, perl -i: they rewrite the files they are given.
  else if (edits && words.slice(at + 1).some(w => /^-[A-Za-z]*i/.test(w) || w === '--in-place' || w.startsWith('--in-place='))) out.push(...args)
  else if (cmd === 'dd') out.push(...args.filter(a => a.startsWith('of=')).map(a => a.slice(3)))
  return out
}

// The git command that starts at `at`: its subcommand, the words after it, and git's own options before it.
function gitParts(words: string[], at: number): { sub: string; rest: string[]; opts: string[] } {
  const opts: string[] = []
  let i = at + 1
  for (; i < words.length; i++) {
    const w = words[i] as string
    if (w === '-c' || w === '-C' || w === '--git-dir' || w === '--work-tree') {
      opts.push(w, words[i + 1] ?? '')
      i++
    } else if (w.startsWith('-')) opts.push(w)
    else break
  }
  return { sub: words[i] ?? '', rest: words.slice(i + 1), opts }
}

const HOOKS_PATH = /core\.hookspath/i

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

export function readShell(command: string): ShellRead {
  const read: ShellRead = { calls: [], noVerify: false, hooksPath: false, writes: [], tooMany: false }
  const expand = (word: string): string[] => {
    const all = braces(word)
    if (all === null) read.tooMany = true
    return all ?? [word]
  }
  for (const words of statements(command)) {
    read.writes.push(...written(words, expand))
    // A variable set to name core.hooksPath, before git or in a statement of its own (`export GIT_CONFIG_KEY_0=...`):
    // git reads its config from the environment it is given.
    if (words.some(w => /^[A-Za-z_][A-Za-z0-9_]*=/.test(w) && HOOKS_PATH.test(w))) read.hooksPath = true
    for (const gitAt of starts(words, cmd => cmd === 'git')) {
      const git = gitParts(words, gitAt)
      // `git -c core.hooksPath=...`.
      if (git.opts.some(o => HOOKS_PATH.test(o))) read.hooksPath = true
      if (git.sub === 'commit' && skipsHook(git.rest)) read.noVerify = true
      if (git.sub === 'config') {
        const at = git.rest.findIndex(w => HOOKS_PATH.test(w))
        const reads = git.rest.some(w => ['--get', '--get-all', '--get-regexp', '--list', '-l'].includes(w))
        // `git config core.hooksPath` with no value reads it; with a value, or with --unset, it changes it.
        if (at >= 0 && !reads && (git.rest[at + 1] !== undefined || git.rest.some(w => w.startsWith('--unset') || w === '--replace-all' || w === '--add'))) read.hooksPath = true
        // Removing or renaming the core section drops core.hooksPath with it (also git 2.46's `git config remove-section`).
        const section = git.rest.findIndex(w => ['--remove-section', '--rename-section', 'remove-section', 'rename-section'].includes(w))
        if (section >= 0 && (git.rest.slice(section + 1).find(w => !w.startsWith('-')) ?? '').toLowerCase() === 'core') read.hooksPath = true
        // git 2.46's `git config unset core.hooksPath`.
        if (at >= 0 && !reads && git.rest.slice(0, at).includes('unset')) read.hooksPath = true
        // A config file included from the repository's config can set core.hooksPath (include.path, includeIf.*.path).
        const include = git.rest.findIndex(w => /^include(?:if\..*)?\.path$/i.test(w))
        if (include >= 0 && !reads && git.rest.slice(include + 1).some(w => !w.startsWith('-'))) read.hooksPath = true
      }
    }
    // The first word that names the script starts a call: the words after it are the call's.
    for (let i = 0; i < words.length; i++) {
      if (SCRIPT.test(words[i] as string)) {
        read.calls.push(words.slice(i + 1))
        break
      }
    }
  }
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
  const st = statements(written)[0] ?? []
  const at = st.findIndex(w => SCRIPT.test(w))
  if (at < 0) return false
  const want = callWords(st.slice(at + 1))
  const have = callWords(words)
  return want.length === have.length && want.every((w, i) => (/^\{[^{}]*\}$/.test(w) ? (have[i] ?? '') !== '' : w === have[i]))
}
