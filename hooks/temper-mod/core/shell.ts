// What the guard reads in a Bash command (ADR 0013). It is not a shell parser: it splits the text into statements and
// words, honouring quotes, and looks for three things only:
//  - the temper CLI calls written out (`scripts/temper ...` or `temper ...`), so a call only the person may cause needs
//    the person's answer;
//  - a commit that switches the native pre-commit hook off (`--no-verify`, `-n`) or a change of `core.hooksPath`;
//  - the paths the command writes: a redirect's target, and the files a writing program names (rm, mv, cp, tee,
//    sed -i and the like). The guard holds them to the same list of protected files as the editing tools.
// Anything this does not see (a variable, a substitution, a script on disk, a program that builds a name at run time)
// passes. Temper is not a sandbox (docs/trust.md): the native hook and the editing tool rules are the hard guarantees.

export type ShellRead = {
  // Each temper call written out: its words after the script (`state advance plan_complete build`).
  calls: string[][]
  // `git commit --no-verify` or `-n`: the native pre-commit hook would not run.
  noVerify: boolean
  // A change of `core.hooksPath`: git would run other hooks than Temper's.
  hooksPath: boolean
  // The paths the command writes, as written.
  writes: string[]
}

// The text as statements of words. A quoted part keeps its spaces and loses its quotes; an operator outside quotes
// (`;`, `&`, `|`, a newline, a bracket, a backquote) ends the statement. A redirect is a word of its own (`>`, `>>`).
// The body of a here document is text, not commands: it is skipped.
export function statements(command: string): string[][] {
  const out: string[][] = []
  let words: string[] = []
  let word = ''
  let inWord = false
  // The here documents of the current line, in order: their end words, and whether `<<-` lets the end word be indented.
  const docs: Array<{ end: string; dash: boolean }> = []
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
    } else if (';&|()`'.includes(ch)) {
      endStatement()
    } else if (ch === '$' && command[i + 1] === '(') {
      endStatement()
      i++
    } else {
      word += ch
      inWord = true
    }
  }
  endStatement()
  return out
}

const SCRIPT = /(?:^|\/)temper$/
// Programs that write, remove or lock the files they name.
const WRITERS = new Set(['rm', 'rmdir', 'unlink', 'shred', 'truncate', 'touch', 'chmod', 'chown', 'tee', 'mv', 'cp', 'install', 'ln', 'rsync'])
// The ones whose last word is where they write.
const TO_LAST = new Set(['cp', 'install', 'ln', 'rsync'])
// The ones that take the folder they write into as `-t DIR`.
const TARGET_DIR = new Set(['cp', 'mv', 'install', 'ln'])

const ENV_WORD = /^[A-Za-z_][A-Za-z0-9_]*=/

// Words a statement may start with before the program it runs: shell keywords (`then rm x`, `do rm x`, `{ rm x; }`,
// `! rm x`) and programs that run the words after them.
const LEAD = new Set(['if', 'then', 'else', 'elif', 'do', 'while', 'until', '!', '{', 'time', 'command', 'builtin', 'exec', 'nohup', 'setsid', 'sudo', 'doas', 'env', 'nice', 'timeout', 'stdbuf', 'ionice', 'taskset'])
// Their options that take a value in the next word, and the words they take before the program (timeout's duration,
// taskset's mask).
const LEAD_VALUE: Record<string, readonly string[]> = {
  sudo: ['-u', '--user', '-g', '--group', '-C', '--close-from', '-h', '--host', '-p', '--prompt', '-r', '--role', '-t', '--type', '-U', '--other-user'],
  doas: ['-u', '-C'],
  env: ['-u', '--unset', '-C', '--chdir'],
  nice: ['-n', '--adjustment'],
  timeout: ['-s', '--signal', '-k', '--kill-after'],
  stdbuf: ['-i', '-o', '-e', '--input', '--output', '--error'],
  ionice: ['-c', '--class', '-n', '--classdata', '-p', '--pid', '-P', '--pgid', '-u', '--uid'],
}
const LEAD_POSITIONAL: Record<string, number> = { timeout: 1, taskset: 1 }

// The program a statement runs: its first word after `VAR=value` words, the keywords and the wrappers above with their
// options.
function program(words: string[]): number {
  let i = 0
  while (i < words.length) {
    const w = words[i] as string
    if (ENV_WORD.test(w)) {
      i++
      continue
    }
    if (!LEAD.has(w)) break
    i++
    // The wrapper's own options, then the words it takes before the program.
    while (i < words.length && (words[i] as string).startsWith('-') && words[i] !== '--') i += (LEAD_VALUE[w] ?? []).includes(words[i] as string) ? 2 : 1
    if (words[i] === '--') i++
    while (i < words.length && ENV_WORD.test(words[i] as string)) i++
    i += LEAD_POSITIONAL[w] ?? 0
  }
  return i
}

// `{a,b}` in a word, as bash expands it (one list at a time, at most 64 words).
function braces(word: string): string[] {
  const m = /^(.*?)\{([^{}]*,[^{}]*)\}(.*)$/.exec(word)
  if (m === null) return [word]
  const out: string[] = []
  for (const alt of (m[2] as string).split(',')) for (const w of braces(`${m[1]}${alt}${m[3]}`)) if (out.length < 64) out.push(w)
  return out
}

// The paths a statement writes: a redirect's target, and the files a writing program names.
function written(words: string[]): string[] {
  const out: string[] = []
  for (let i = 0; i < words.length; i++) {
    const op = words[i] as string
    const to = words[i + 1]
    if (to === undefined) continue
    // `>`, `>>`, `>|` and `<>` write their file; `>&` and `>>&` write a file unless they name a file descriptor (`2>&1`).
    if (/^(?:>[>|]?|<>)$/.test(op) || (/^>>?&$/.test(op) && !/^(?:\d+|-)$/.test(to))) out.push(...braces(to))
  }
  const at = program(words)
  const cmd = (words[at] ?? '').split('/').pop() ?? ''
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
    } else if (!w.startsWith('-')) args.push(...braces(w))
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

function gitParts(words: string[]): { sub: string; rest: string[]; opts: string[] } | null {
  const at = program(words)
  if ((words[at] ?? '').split('/').pop() !== 'git') return null
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
  const read: ShellRead = { calls: [], noVerify: false, hooksPath: false, writes: [] }
  for (const words of statements(command)) {
    read.writes.push(...written(words))
    const git = gitParts(words)
    if (git !== null) {
      // `git -c core.hooksPath=...`, or the same key handed to git in its environment (GIT_CONFIG_KEY_0=core.hooksPath).
      if (git.opts.some(o => HOOKS_PATH.test(o)) || words.slice(0, program(words)).some(w => HOOKS_PATH.test(w))) read.hooksPath = true
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
