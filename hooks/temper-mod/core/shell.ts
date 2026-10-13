// What the guard reads in a Bash command (ADR 0013). It is not a shell parser: it splits the text into statements and
// words, honouring quotes, and looks for three things only:
//  - the temper CLI calls written out (`scripts/temper ...` or `temper ...`), so a call only the person may cause needs
//    the person's answer;
//  - a commit that switches the native pre-commit hook off (`--no-verify`, `-n`) or a change of `core.hooksPath`;
//  - the paths the command writes: a redirect's target, and the files a writing program names (rm, mv, cp, tee,
//    sed -i and the like). The guard holds them to the same list of protected files as the editing tools.
// Anything this does not see (a variable, a substitution, a script on disk, a program that builds a name at run time)
// passes. Temper is not a sandbox (docs/trust.md): the native hook and the editing tool rules are the hard guarantees.

// A temper call: what it does, in the words the command gives it.
export type DecisionKind = 'override' | 'accept' | 'advance' | 'back'
export type DecisionCall = { kind: DecisionKind; stage?: string; id?: string; next?: string; invalid?: boolean }
export type StateOp = { op: 'set'; key: string; value?: string } | { op: 'clear' } | { op: 'archive' } | { op: 'init' } | { op: 'loop'; from?: string; to?: string }

export type ShellRead = {
  calls: DecisionCall[]
  stateOps: StateOp[]
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
        if (command[j] === '\\' && j + 1 < command.length) j++
        word += command[j]
      }
      inWord = true
      i = j
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
      // A redirect: `>`, `>>`, `>|`, `&>`, `2>`. A file descriptor number before it belongs to it.
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

const ENV_WORD = /^[A-Za-z_][A-Za-z0-9_]*=/

// The program a statement runs: its first word after `VAR=value` words and `sudo`, `env`, `command`, `exec`, `nohup`.
function program(words: string[]): number {
  let i = 0
  while (i < words.length && (ENV_WORD.test(words[i] as string) || ['sudo', 'env', 'command', 'exec', 'nohup', 'time'].includes(words[i] as string))) i++
  return i
}

// The paths a statement writes: a redirect's target, and the files a writing program names.
function written(words: string[]): string[] {
  const out: string[] = []
  for (let i = 0; i < words.length; i++) {
    if (/^>[>|]?$/.test(words[i] as string) && words[i + 1] !== undefined) out.push(words[i + 1] as string)
  }
  const at = program(words)
  const cmd = (words[at] ?? '').split('/').pop() ?? ''
  const edits = cmd === 'sed' || cmd === 'perl'
  // The program's file words: no flag, no redirect and its file, and for sed and perl no script (`-e x`, or sed's
  // first word when no -e names the script).
  const args: string[] = []
  let script = false
  for (let i = at + 1; i < words.length; i++) {
    const w = words[i] as string
    if (/^[<>]/.test(w)) i++
    else if (edits && ['-e', '-f', '--expression', '--file'].includes(w)) {
      script = true
      i++
    } else if (edits && /^-[A-Za-z]*e$/.test(w)) {
      script = true
      i++
    } else if (!w.startsWith('-')) args.push(w)
  }
  if (cmd === 'sed' && !script) args.shift()
  if (WRITERS.has(cmd)) out.push(...(TO_LAST.has(cmd) ? args.slice(-1) : args))
  // sed -i, perl -i: they rewrite the files they are given.
  else if (edits && words.slice(at + 1).some(w => /^-[A-Za-z]*i/.test(w) || w === '--in-place')) out.push(...args)
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
    if (w === '--no-verify') return true
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

function readTemper(args: string[], calls: DecisionCall[], stateOps: StateOp[]): void {
  let i = 0
  while (i < args.length && (args[i] as string).startsWith('-')) i += args[i] === '--spec-path' ? 2 : 1
  const sub = args[i]
  const sub2 = args[i + 1]
  const rest = args.slice(i + 2)
  const flag = (name: string, from: string[]): string[] => {
    const found: string[] = []
    for (let k = 0; k < from.length; k++) {
      const w = from[k] as string
      if (w === name) found.push(from[k + 1] ?? '')
      else if (w.startsWith(`${name}=`)) found.push(w.slice(name.length + 1))
    }
    return found
  }
  if (sub === 'override') {
    const r = args.slice(i + 1)
    calls.push({ kind: 'override', ...(r[0] && !r[0].startsWith('-') ? { stage: r[0] } : {}), invalid: flag('--reason', r).length > 1 })
  } else if (sub === 'group' && sub2 === 'reopen' && rest.some(w => w === '--accept-foreign' || w.startsWith('--accept-foreign='))) {
    // Keeping a task agent's commits records an override inside the CLI: the person's choice.
    calls.push({ kind: 'override', stage: `foreign-commit:${rest[0] ?? ''}`, invalid: flag('--accept-foreign', rest).length > 1 })
  } else if (sub === 'evidence' && sub2 === 'accept') {
    const stage = flag('--stage', rest)
    const id = flag('--id', rest)
    calls.push({ kind: 'accept', ...(stage[0] !== undefined ? { stage: stage[0] } : {}), ...(id[0] !== undefined ? { id: id[0] } : {}), invalid: stage.length > 1 || id.length > 1 || flag('--reason', rest).length > 1 })
  } else if (sub === 'state' && sub2 === 'advance') {
    calls.push({ kind: 'advance', ...(rest[0] !== undefined ? { stage: rest[0] } : {}), ...(rest[1] !== undefined ? { next: rest[1] } : {}) })
  } else if (sub === 'state' && sub2 === 'set') {
    const key = rest[0] ?? ''
    stateOps.push({ op: 'set', key, ...(rest[1] !== undefined ? { value: rest[1] } : {}) })
    if (key === 'next_stage') calls.push({ kind: 'back', ...(rest[1] !== undefined ? { stage: rest[1] } : {}) })
  } else if (sub === 'state' && sub2 === 'loop') {
    stateOps.push({ op: 'loop', ...(rest[0] !== undefined ? { from: rest[0] } : {}), ...(rest[1] !== undefined ? { to: rest[1] } : {}) })
  } else if (sub === 'state' && (sub2 === 'clear' || sub2 === 'archive' || sub2 === 'init')) {
    stateOps.push({ op: sub2 })
  }
}

export function readShell(command: string): ShellRead {
  const read: ShellRead = { calls: [], stateOps: [], noVerify: false, hooksPath: false, writes: [] }
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
      }
    }
    // Every word that names the script starts a call: the words after it are the call's.
    for (let i = 0; i < words.length; i++) {
      if (SCRIPT.test(words[i] as string)) {
        readTemper(words.slice(i + 1), read.calls, read.stateOps)
        break
      }
    }
  }
  return read
}
