// Bash classifier. Best effort by design: Bash can write files in ways no pattern
// catches. The hard guarantee covers Write, Edit, NotebookEdit and `git commit`; the
// native pre-commit hook stays as the second layer.

export type ProtectedKind = 'events' | 'gates' | 'status' | 'overrides'

export type DecisionKind = 'override' | 'accept' | 'advance'

export type BashClass = {
  commits: boolean
  decisions: DecisionKind[]
  protectedWrites: string[]
}

const PROTECTED: ReadonlyArray<readonly [ProtectedKind, RegExp]> = [
  ['events', /(^|\/)\.temper\/specs\/[^/\s]+\/events(\/|$)/],
  ['gates', /(^|\/)\.temper\/gates\.json$/],
  ['status', /(^|\/)\.temper\/status\.json$/],
  ['overrides', /(^|\/)\.temper\/overrides\.json$/],
]

// Which guarded Temper state file a path names, or null.
export function protectedKind(path: string): ProtectedKind | null {
  const p = path.replace(/\\/g, '/').replace(/\/{2,}/g, '/')
  for (const [kind, re] of PROTECTED) if (re.test(p)) return kind
  return null
}

const MENTION = /\.temper\/(?:specs\/[^\s'"`]+\/events[^\s'"`]*|gates\.json|status\.json|overrides\.json)/g

const WRAPPERS = [
  /^[A-Za-z_]\w*=\S*\s+/,
  /^sudo\s+(?:-\S+\s+)*/,
  /^(?:time|command|exec|nohup|env|then|do|else|!|\{)\s+/,
]

function stripWrappers(seg: string): string {
  let s = seg.trim()
  for (let again = true; again; ) {
    again = false
    for (const re of WRAPPERS) {
      const t = s.replace(re, '')
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
const GIT_COMMIT = /^git(?:\s+(?:-[cC]\s+\S+|--[\w-]+(?:=\S+)?|-[a-zA-Z]))*\s+commit(?:['")\s]|$)/
const DECISION = /^(?:(?:bash|sh|zsh)\s+)?['"]?(?:\S*\/)?temper['"]?\s+(override|evidence\s+accept|state\s+advance)\b/

function unwrapShell(seg: string): string {
  const t = seg.replace(SHELL_C, '').replace(EVAL, '')
  return t === seg ? seg : stripWrappers(t)
}

const WRITES_ANY = new Set(['tee', 'rm', 'touch', 'truncate', 'dd', 'install', 'ln', 'rsync', 'shred', 'unlink'])
const WRITES_LAST = new Set(['cp', 'mv'])
const INTERPRETERS = /^(?:python[\d.]*|node|deno|bun|perl|ruby|php|osascript)$/

function tokens(seg: string): string[] {
  return seg
    .split(/\s+/)
    .map(t => t.replace(/^of=/, '').replace(/^['"]+|['"]+$/g, ''))
    .filter(Boolean)
}

function writesFrom(seg: string): string[] {
  const t = tokens(seg)
  if (t.length === 0) return []
  const cmd = (t[0] ?? '').replace(/^.*\//, '')
  const args = t.slice(1)
  if (WRITES_ANY.has(cmd)) return args.filter(a => protectedKind(a))
  if (WRITES_LAST.has(cmd)) {
    const last = args[args.length - 1]
    return last && protectedKind(last) ? [last] : []
  }
  const inPlace = args.some(a => a === '--in-place' || /^-[a-zA-Z]*i/.test(a))
  if ((cmd === 'sed' || cmd === 'perl' || cmd === 'awk') && inPlace) return args.filter(a => protectedKind(a))
  return []
}

export function classifyBash(command: string): BashClass {
  const segs = segments(command).map(unwrapShell)
  const decisions: DecisionKind[] = []
  let commits = false
  let interpreter = false
  const writes: string[] = []

  for (const seg of segs) {
    if (GIT_COMMIT.test(seg)) commits = true
    const d = DECISION.exec(seg)
    const word = d?.[1] ?? ''
    if (d) decisions.push(word.startsWith('evidence') ? 'accept' : word.startsWith('state') ? 'advance' : 'override')
    if (INTERPRETERS.test(seg.split(/\s+/)[0] ?? '')) interpreter = true
    writes.push(...writesFrom(seg))
  }

  for (const m of command.matchAll(/\d?>{1,2}(?!&)\s*['"]?([^\s'";&|)<>]+)/g)) {
    const target = m[1] ?? ''
    if (protectedKind(target)) writes.push(target)
  }
  if (interpreter) writes.push(...(command.match(MENTION) ?? []))

  return { commits, decisions, protectedWrites: [...new Set(writes)] }
}
