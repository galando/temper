// Path helpers shared by the rules and the plan file reader. Pure string work: the
// module environment has no Node `path`.

// Collapse `.`, `..`, doubled slashes and backslashes; strip `root` when the path is
// absolute and inside it. The result never starts with `./` or `/` for in-root paths.
export function normalizePath(input: string, root = ''): string {
  let p = input.replace(/\\/g, '/')
  const r = root.replace(/\\/g, '/').replace(/\/+$/, '')
  if (r && (p === r || p.startsWith(r + '/'))) p = p.slice(r.length).replace(/^\/+/, '')
  const out: string[] = []
  for (const part of p.split('/')) {
    if (part === '' || part === '.') continue
    if (part === '..') {
      if (out.length > 0 && out[out.length - 1] !== '..') out.pop()
      else out.push('..')
    } else out.push(part)
  }
  return (p.startsWith('/') ? '/' : '') + out.join('/')
}

function globToRegExp(glob: string): RegExp {
  let re = ''
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i] ?? ''
    if (c === '*') {
      if (glob[i + 1] === '*') {
        re += '.*'
        i++
        if (glob[i + 1] === '/') i++
      } else re += '[^/]*'
    } else if (c === '?') re += '[^/]'
    else re += c.replace(/[.+^${}()|[\]\\]/g, '\\$&')
  }
  return new RegExp('^' + re + '$')
}

// True when `path` is named by one plan entry: an exact file, a `dir/` prefix, or a glob.
export function matchesPlanEntry(path: string, entry: string): boolean {
  const e = normalizePath(entry)
  const p = normalizePath(path)
  if (entry.endsWith('/')) return p === e || p.startsWith(e + '/')
  if (e.includes('*') || e.includes('?')) return globToRegExp(e).test(p)
  return p === e
}

export function matchesPlan(path: string, entries: readonly string[]): boolean {
  return entries.some(e => matchesPlanEntry(path, e))
}
