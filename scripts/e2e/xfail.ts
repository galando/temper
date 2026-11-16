// The expected to fail rule of the scenario runner, as pure functions (WP07's mechanism, steps 1 and 3).
//
// The list is scripts/selftest/expected-fail.txt: one check a line, `#` starts a comment, and a line is
//   <suite>:<name>   <package that makes it pass>   [<promise>]
// with the suite `selftest` (`selftest:<token>`: every assertion whose name starts with the token and a space) or `e2e`
// (`e2e:<scenario>`: the scenario in every mode; `e2e:<scenario>:<mode>`: in that mode). Nothing else may be listed: a
// mod test is never written failing across packages.
//
// The runner (scripts/e2e/run.ts) asks `verdict` what a finished scenario means:
//   listed and threw         XFAIL <name> [<mode>]: <first line of the error>      not counted as failed
//   listed and returned      FAIL <name> [<mode>]: unexpected pass ...             counted: take the line off the list
//   not listed and threw     FAIL <name> [<mode>]: <the error>                     counted
//   not listed and returned  PASS <name> [<mode>]                                  not counted
// The compare of the plain trace with the mod trace and the floor are skipped for a listed scenario (`skipsCompare`).
//
//   bun scripts/e2e/xfail.ts --check   asserts the four outcomes and the reader of the list on made up input; exit 0 or 1
//   bun scripts/e2e/xfail.ts --list    prints the e2e entries of the list as the runner reads them
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

export const LIST = path.resolve(import.meta.dir, '../selftest/expected-fail.txt')
export const MODES = ['plain', 'mod', 'driver'] as const
export const LIST_RULE = 'take its line off scripts/selftest/expected-fail.txt'

export type Entry = {
  suite: 'selftest' | 'e2e'
  name: string                  // the token of a selftest check, or the scenario
  mode: string | null           // e2e only: one mode, or null for every mode
  pkg: string                   // the package that makes it pass: WPnn
  promise: string               // the row of done.md it proves, or ''
  line: number                  // its line in the file
  text: string                  // `<suite>:<name>[:<mode>]` as written
}

// The reader of the list. A line it cannot read is an error: a typing mistake must never list nothing.
export function readList(text: string): { entries: Entry[]; errors: string[] } {
  const entries: Entry[] = []
  const errors: string[] = []
  const seen = new Set<string>()
  text.split('\n').forEach((raw, i) => {
    const line = raw.replace(/#.*$/, '').trim()
    if (line === '') return
    const at = `line ${i + 1}`
    const words = line.split(/\s+/)
    if (words.length < 2 || words.length > 3) {
      errors.push(`${at}: a line is <suite>:<name>, the package and the promise, not "${line}"`)
      return
    }
    const [check, pkg, promise = ''] = words as [string, string, string?]
    const before = errors.length
    if (!/^WP\d{2}$/.test(pkg)) errors.push(`${at}: "${pkg}" is no package (WPnn)`)
    if (promise !== '' && !/^D\d+[a-z]?$/.test(promise)) errors.push(`${at}: "${promise}" is no row of done.md (Dnn)`)
    const parts = check.split(':')
    const suite = parts[0]
    let entry: Entry | null = null
    if (suite === 'selftest' && parts.length === 2 && /^[A-Za-z0-9][\w.-]*$/.test(parts[1]!)) {
      entry = { suite, name: parts[1]!, mode: null, pkg, promise, line: i + 1, text: check }
    } else if (suite === 'e2e' && (parts.length === 2 || parts.length === 3) && /^[a-z0-9]+(-[a-z0-9]+)*$/.test(parts[1]!)) {
      const mode = parts.length === 3 ? parts[2]! : null
      if (mode !== null && !(MODES as readonly string[]).includes(mode)) errors.push(`${at}: "${mode}" is no mode (${MODES.join(', ')})`)
      else entry = { suite, name: parts[1]!, mode, pkg, promise, line: i + 1, text: check }
    } else {
      errors.push(`${at}: "${check}" is neither selftest:<token> nor e2e:<scenario>[:<mode>]; nothing else may be listed`)
    }
    if (entry !== null && errors.length === before) {
      if (seen.has(check)) errors.push(`${at}: ${check} is listed twice`)
      seen.add(check)
      entries.push(entry)
    }
  })
  return { entries, errors }
}

// The list of this tree; a missing file lists nothing. A line it cannot read throws, so the runner fails at once.
export function loadList(file = LIST): Entry[] {
  if (!fs.existsSync(file)) return []
  const { entries, errors } = readList(fs.readFileSync(file, 'utf8'))
  if (errors.length > 0) throw new Error(`${path.basename(file)}: ${errors.join('; ')}`)
  return entries
}

// The entry that lists a scenario in a mode, or null.
export function listed(entries: Entry[], scenario: string, mode: string): Entry | null {
  return entries.find(e => e.suite === 'e2e' && e.name === scenario && (e.mode === null || e.mode === mode)) ?? null
}

// The e2e entries that name no scenario the runner knows (a stale line cannot stay).
export function stale(entries: Entry[], scenarios: string[]): Entry[] {
  return entries.filter(e => e.suite === 'e2e' && !scenarios.includes(e.name))
}

export type Verdict = { failed: boolean; line: string; listed: boolean }

// What a finished scenario means: `error` is what it threw, or null when it returned.
export function verdict(entry: Entry | null, scenario: string, mode: string, error: Error | null, steps = ''): Verdict {
  const tag = `${scenario} [${mode}]`
  if (entry !== null) {
    if (error !== null) return { failed: false, listed: true, line: `XFAIL ${tag}: ${firstLine(error.message)}` }
    return { failed: true, listed: true, line: `FAIL ${tag}: unexpected pass; ${LIST_RULE} (${entry.text} ${entry.pkg})` }
  }
  if (error !== null) return { failed: true, listed: false, line: `FAIL ${tag}: ${error.message.slice(0, 1500)}` }
  return { failed: false, listed: false, line: `PASS ${tag}${steps ? ` ${steps}` : ''}` }
}

// The compare of the plain trace with the mod trace, and the floor, leave out a listed scenario.
export const skipsCompare = (entries: Entry[], scenario: string, modes: string[]): boolean =>
  modes.some(m => listed(entries, scenario, m) !== null)

const firstLine = (s: string): string => (s.split('\n').find(l => l.trim() !== '') ?? '').trim().slice(0, 300)

// ---- the check of this file, on made up input --------------------------------------------------------------------------

function check(): number {
  let fails = 0
  const eq = (name: string, got: unknown, want: unknown): void => {
    const ok = JSON.stringify(got) === JSON.stringify(want)
    if (!ok) fails++
    console.log(`${ok ? 'PASS' : 'FAIL'}: xfail ${name}${ok ? '' : ` (got ${JSON.stringify(got)}, want ${JSON.stringify(want)})`}`)
  }
  const made = [
    '# suite:name                   passes after   promise',
    'selftest:D31a                  WP12           D31',
    'e2e:two-dialogs                WP13           D01   # a comment after the line',
    '',
    'e2e:slow-first-run:plain       WP23           D11',
  ].join('\n')
  const { entries, errors } = readList(made)
  eq('the reader reads three entries and no error', [entries.map(e => `${e.suite}:${e.name}:${e.mode ?? '*'}:${e.pkg}:${e.promise}:${e.line}`), errors],
    [['selftest:D31a:*:WP12:D31:2', 'e2e:two-dialogs:*:WP13:D01:3', 'e2e:slow-first-run:plain:WP23:D11:5'], []])
  eq('an entry with no mode lists the scenario in every mode', MODES.map(m => listed(entries, 'two-dialogs', m)?.text ?? null),
    ['e2e:two-dialogs', 'e2e:two-dialogs', 'e2e:two-dialogs'])
  eq('an entry with a mode lists it in that mode only', MODES.map(m => listed(entries, 'slow-first-run', m) !== null), [true, false, false])
  eq('a selftest token lists no scenario of the same name', listed(entries, 'D31a', 'plain'), null)
  const bad = readList(['mod:ids.test.ts WP04 D65', 'e2e:x:fast WP06 D11', 'e2e:x WP6 D11', 'e2e:Two_Dialogs WP13', 'e2e:x WP06 D11', 'e2e:x WP06 D11', 'selftest:D1 WP07 D1 extra'].join('\n'))
  eq('the reader refuses a mod test, a mode, a package, a name, a twice listed line and a long line, one error each',
    bad.errors.map(e => e.replace(/:.*$/, '')), ['line 1', 'line 2', 'line 3', 'line 4', 'line 6', 'line 7'])
  eq('a list the reader refuses throws when the runner loads it', (() => {
    const tmp = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'xfail-')), 'list.txt')
    fs.writeFileSync(tmp, 'e2e:x:fast WP06 D11\n')
    try {
      loadList(tmp)
      return 'loaded'
    } catch (e) {
      return (e as Error).message.includes('"fast" is no mode') ? 'threw' : (e as Error).message
    }
  })(), 'threw')
  eq('a missing list lists nothing', loadList(path.join(import.meta.dir, 'no-such-list.txt')), [])
  const err = new Error('D11 unexpected question intent.accept\n  at the second line')
  const one = listed(entries, 'two-dialogs', 'plain')
  eq('listed and throws: XFAIL with the first line of the error, not failed', verdict(one, 'two-dialogs', 'plain', err),
    { failed: false, listed: true, line: 'XFAIL two-dialogs [plain]: D11 unexpected question intent.accept' })
  eq('listed and passes: a failure that names the list', verdict(one, 'two-dialogs', 'plain', null),
    { failed: true, listed: true, line: `FAIL two-dialogs [plain]: unexpected pass; ${LIST_RULE} (e2e:two-dialogs WP13)` })
  eq('not listed and throws: a failure (the list never hides an unlisted failure)', verdict(listed(entries, 'slow-first-run', 'driver'), 'slow-first-run', 'driver', err),
    { failed: true, listed: false, line: 'FAIL slow-first-run [driver]: D11 unexpected question intent.accept\n  at the second line' })
  eq('not listed and passes: a pass', verdict(null, 'full-run', 'plain', null, '(3 steps, 0 refusals)'),
    { failed: false, listed: false, line: 'PASS full-run [plain] (3 steps, 0 refusals)' })
  eq('the compare and the floor skip a listed scenario, in any mode it runs', [skipsCompare(entries, 'slow-first-run', ['plain', 'mod']), skipsCompare(entries, 'slow-first-run', ['mod']), skipsCompare(entries, 'full-run', ['plain', 'mod'])], [true, false, false])
  eq('an e2e entry that names no scenario is stale', stale(entries, ['two-dialogs', 'full-run']).map(e => e.text), ['e2e:slow-first-run:plain'])
  eq('the list of this tree reads', (() => {
    try {
      return loadList().every(e => e.suite === 'selftest' || e.suite === 'e2e')
    } catch (e) {
      return (e as Error).message
    }
  })(), true)
  console.log(`xfail --check: ${fails === 0 ? 'PASS' : `FAIL (${fails})`}`)
  return fails === 0 ? 0 : 1
}

if (import.meta.main) {
  const word = process.argv[2] ?? ''
  if (word === '--check') process.exit(check())
  if (word === '--list') {
    for (const e of loadList()) if (e.suite === 'e2e') console.log(`${e.text} ${e.pkg} ${e.promise}`.trim())
    process.exit(0)
  }
  console.log('usage: bun scripts/e2e/xfail.ts --check | --list')
  process.exit(2)
}
