// The run driver's calls as argument lists (9.8.1). Pure.
//
// The driver runs only one program: the plugin's own Temper CLI, by its full path. A call the CLI wrote is a line of
// words, each plain or in the quotes the CLI puts around a value (`'...'`, with `'\''` or `'"'"'` for a quote inside).
// This reads that line into the argument list the mod hands to `$.process.spawn`, with no shell between: a call that
// needs a shell (a pipe, a redirection, a `;` or `&&`, a `$` or a backquote outside quotes) or that names any other
// program is not run by the mod, and the run goes on in the conversation, where the person's own permission settings
// apply to it.

import { CLI } from './cli'

// The characters that only a shell gives a meaning to, outside quotes.
const SHELL_ONLY = new Set(['|', '&', ';', '<', '>', '(', ')', '$', '`', '\n', '\r'])

// The words of `call`, or null when reading it needs a shell.
export function splitCall(call: string): string[] | null {
  const words: string[] = []
  let cur = ''
  let inWord = false
  let i = 0
  while (i < call.length) {
    const ch = call[i] as string
    if (ch === ' ' || ch === '\t') {
      if (inWord) words.push(cur)
      cur = ''
      inWord = false
      i++
      continue
    }
    if (ch === "'") {
      const end = call.indexOf("'", i + 1)
      if (end < 0) return null
      cur += call.slice(i + 1, end)
      inWord = true
      i = end + 1
      continue
    }
    if (ch === '"') {
      i++
      let closed = false
      while (i < call.length) {
        const c = call[i] as string
        if (c === '"') {
          closed = true
          i++
          break
        }
        if (c === '$' || c === '`') return null
        if (c === '\\' && i + 1 < call.length && '"\\$`'.includes(call[i + 1] as string)) {
          cur += call[i + 1] as string
          i += 2
          continue
        }
        cur += c
        i++
      }
      if (!closed) return null
      inWord = true
      continue
    }
    if (ch === '\\') {
      if (i + 1 >= call.length || call[i + 1] === '\n') return null
      cur += call[i + 1] as string
      inWord = true
      i += 2
      continue
    }
    if (SHELL_ONLY.has(ch)) return null
    cur += ch
    inWord = true
    i++
  }
  if (inWord) words.push(cur)
  return words
}

// The argument list for a call of the Temper CLI, or null when the call is not one: another program, or a line that
// needs a shell. The CLI is the plugin's own `scripts/temper` (`cli`, as the mod found it), or a path that ends in it:
// the CLI writes its calls with its own folder resolved (`cd -P`), which is not always the spelling the mod has.
export function cliArgv(call: string, cli: string): string[] | null {
  const words = splitCall(call)
  if (words === null || words.length === 0) return null
  const program = words[0] as string
  if (program !== cli && program !== CLI && !program.endsWith(`/${CLI}`)) return null
  return words
}
