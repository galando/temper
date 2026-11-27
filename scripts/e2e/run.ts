// bun scripts/e2e/run.ts [mod|plain|driver|both|all] [scenario...] [--shard K/N] [--list] [--floor FILE | --write-floor FILE]  (all: plain, mod and the mod's run driver; a scenario of slow.ts, broken.ts or accept.ts runs only in the modes it names; a scenario on scripts/selftest/expected-fail.txt prints XFAIL when it throws)  (a live model smoke is not part of this: it stays off, and out of CI)
import { coverageDrop, defaultRun, redBaseAfterApproval, failedChecks, fixBreaksSuite, freshAsk, policyRun, freshContest, freshNotRun, freshReview, armedRun, branchClash, branchClashCarry, contextCheck, contextFold, designRun, failingScenario, fixRun, mavenRun, threeGroups, coveredAndManual, fullRun, hookScope, modGuards, prAndPipeline, saveAndResume, smallChange, trivialRun } from './scenarios'
import { pyjokesBlocked, pyjokesFull, pyjokesRun } from './pyjokes'
import { ACCEPT_SCENARIOS } from './accept'
import { BROKEN_SCENARIOS } from './broken'
import { SLOW_SCENARIOS } from './slow'
import { UPGRADE_SCENARIOS } from './upgrade'
import { planCommandFails, setupAtBuild } from './scenarios'   // WP21 and WP23, registered below with the scenarios of the base
import { blockedOutsidePlan, blockedTaskAmended } from './scenarios'   // WP25, registered below
import { listed, loadList, skipsCompare, stale, verdict } from './xfail'
import { Denied, World } from './world'
import type { Json, Mode } from './world'
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const SCENARIOS: Record<string, (w: World) => void> = { 'default-run': defaultRun, 'full-run': fullRun, 'mod-guards': modGuards, 'small-change': smallChange, 'covered-and-manual': coveredAndManual, 'pr-and-pipeline': prAndPipeline, 'context-check': contextCheck, 'context-fold': contextFold, 'branch-clash': branchClash, 'branch-clash-carry': branchClashCarry, 'hook-scope': hookScope, 'failing-scenario': failingScenario, 'armed-run': armedRun, 'red-base-after-approval': redBaseAfterApproval, 'save-and-resume': saveAndResume, design: designRun, 'three-groups': threeGroups, maven: mavenRun, fix: fixRun, 'fresh-review': freshReview, 'fresh-not-run': freshNotRun, 'fresh-contest': freshContest, 'fresh-ask': freshAsk, 'fix-breaks-suite': fixBreaksSuite, pyjokes: pyjokesRun, 'pyjokes-full': pyjokesFull, 'pyjokes-blocked': pyjokesBlocked, 'policy-run': policyRun, 'failed-checks': failedChecks, trivial: trivialRun , 'coverage-drop': coverageDrop }

// The scenarios of the two scripted projects (WP06) and the acceptance scenarios of docs/plans/one-go/done.md (WP07)
// run only in the modes each names.
const ONLY: Record<string, string[]> = {}
for (const [name, s] of Object.entries({ ...SLOW_SCENARIOS, ...BROKEN_SCENARIOS, ...ACCEPT_SCENARIOS, ...UPGRADE_SCENARIOS })) {
  SCENARIOS[name] = s.run
  ONLY[name] = s.modes
}
// WP21: a command the plan wrote fails on the base; every mode
SCENARIOS['plan-command-fails'] = planCommandFails
// WP23: a fault of the environment at integrate in an unattended run; every mode
SCENARIOS['setup-at-build'] = setupAtBuild
// WP25: a blocked task amended by rule, every mode; a file outside the plan, the person's patch, plain mode only
SCENARIOS['blocked-task-amended'] = blockedTaskAmended
SCENARIOS['blocked-outside-plan'] = blockedOutsidePlan
ONLY['blocked-outside-plan'] = ['plain']
// The expected to fail list (scripts/selftest/expected-fail.txt), read once: a line it cannot read, or an e2e line that
// names no scenario or a mode its scenario never runs in, fails the run at once (scripts/e2e/xfail.ts).
let LISTED: ReturnType<typeof loadList> = []
try {
  LISTED = loadList()
} catch (e) {
  console.log(`FAIL: ${(e as Error).message}`)
  process.exit(1)
}
const STALE = stale(LISTED, Object.keys(SCENARIOS), ONLY)
if (STALE.length > 0) {
  console.log(`FAIL: scripts/selftest/expected-fail.txt names no scenario, or a mode it never runs in: ${STALE.map(e => `${e.text} (line ${e.line})`).join(', ')}`)
  process.exit(1)
}

const want = process.argv[2] ?? 'both'
const modes: Mode[] = want === 'both' ? ['plain', 'mod'] : want === 'all' ? ['plain', 'mod', 'driver'] : [want as Mode]
// After the mode: scenario names and flags, in any order. --shard K/N keeps the scenarios of SCENARIOS whose index modulo
// N is K minus 1; every mode of a scenario stays in this one process, since the compare of the flow with the mod and
// without it reads two traces of one process.
// --floor FILE (9.8.5, WP05): each finished scenario's counts (dialogs, launches by agent type, the CLI's own steps,
// steps back, hand backs, suite runs) are compared with the `now` values of FILE by scripts/check_floor.py; any
// difference, and a scenario with no entry, fails. --write-floor FILE writes the `now` values instead (one process
// writes the file, so it is refused with --shard). --list prints the names of the scenarios this call would run, one a
// line, and runs none: the shards of CI are checked with it (N calls cover every scenario once).
const words: string[] = []
let shard: [number, number] | null = null
let floor = ''
let writeFloor = ''
let list = false
const rest = process.argv.slice(3)
for (let i = 0; i < rest.length; i++) {
  const a = rest[i]!
  if (a === '--floor' || a === '--write-floor') {
    const f = rest[++i] ?? ''
    if (f === '' || f.startsWith('--')) {
      console.log(`FAIL: ${a} takes a file`)
      process.exit(2)
    }
    if (a === '--floor') floor = path.resolve(f)
    else writeFloor = path.resolve(f)
  } else if (a === '--shard') {
    const m = /^([1-9]\d*)\/([1-9]\d*)$/.exec(rest[++i] ?? '')
    if (m === null || Number(m[1]) > Number(m[2])) {
      console.log('FAIL: --shard takes K/N with 1 <= K <= N')
      process.exit(2)
    }
    shard = [Number(m[1]), Number(m[2])]
  } else if (a === '--list') {
    list = true
  } else if (a.startsWith('--')) {
    console.log(`FAIL: unknown flag ${a} (bun scripts/e2e/run.ts [mod|plain|driver|both|all] [scenario...] [--shard K/N])`)
    process.exit(2)
  } else words.push(a)
}
if (writeFloor !== '' && (shard !== null || floor !== '')) {
  console.log('FAIL: --write-floor writes the file from one process: not with --shard or --floor')
  process.exit(2)
}
const unknown = words.filter(n => !(n in SCENARIOS))
if (unknown.length > 0) {
  console.log(`FAIL: no scenario ${unknown.join(', ')}`)
  process.exit(2)
}
const order = Object.keys(SCENARIOS)
const names = (words.length > 0 ? words : order).filter(n => shard === null || order.indexOf(n) % shard[1] === shard[0] - 1)
if (list) {
  for (const n of names) console.log(n)
  process.exit(0)
}
// TEMPER_E2E_TRACE_DIR: each finished trace, calls included, goes to <dir>/<scenario>.<mode>.txt with the world's folder,
// commit ids and time stamps replaced by fixed text, so two runs of one tree give equal folders
const traceDir = process.env.TEMPER_E2E_TRACE_DIR ? path.resolve(process.env.TEMPER_E2E_TRACE_DIR) : ''
function dumpTrace(w: World): void {
  if (traceDir === '') return
  fs.mkdirSync(traceDir, { recursive: true })
  const text = w.trace.join('\n').split(w.dir).join('/project')
    .replace(/\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:?\d\d)?/g, '2026-01-01T00:00:00Z')
    .replace(/\b[0-9a-f]{7,40}\b/g, '0000000')
  fs.writeFileSync(path.join(traceDir, `${w.name}.${w.mode}.txt`), text + '\n')
}
let failed = 0
const traces: Record<string, string[]> = {}
const counted: Array<{ scenario: string; mode: string; counts: Json }> = []
for (const name of names) {
  const own = modes.filter(m => ONLY[name] === undefined || ONLY[name]!.includes(m))
  for (const mode of own) {
    const w = new World(mode, name)
    // a listed scenario (WP07 mechanism, step 3): one that throws is an XFAIL line and no failure, one that returns
    // fails and names the list; the floor leaves it out
    const entry = listed(LISTED, name, mode)
    let error: Error | null = null
    try {
      SCENARIOS[name]!(w)
      traces[`${name}:${mode}`] = w.trace.filter(l => !l.startsWith('  call'))
    } catch (e) {
      error = e as Error
    }
    const v = verdict(entry, name, mode, error, `(${w.trace.length} steps, ${w.denials.length} refusals)`)
    console.log(v.line)
    if (v.failed) failed++
    if (error !== null && entry === null) {
      if (error instanceof Denied) console.log('  (the mod refused a call the flow needs)')
      console.log(w.trace.slice(-12).join('\n'))
    }
    if (error === null && entry === null) {
      const counts = w.finalCounts()
      counted.push({ scenario: name, mode, counts })
      console.log(`COUNT ${name} [${mode}] ${JSON.stringify(counts)}`)
    }
    dumpTrace(w)
  }
  if (!skipsCompare(LISTED, name, own) && own.includes('plain') && own.includes('mod') && traces[`${name}:plain`] && traces[`${name}:mod`]) {
    const same = JSON.stringify(traces[`${name}:plain`]) === JSON.stringify(traces[`${name}:mod`])
    console.log(`${same ? 'PASS' : 'FAIL'} ${name}: the flow is identical with the mod and without it`)
    if (!same) failed++
  }
}
// The floor: one call of scripts/check_floor.py with the counts of every scenario that passed here.
if (floor !== '' || writeFloor !== '') {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'temper-floor-'))
  const file = path.join(tmp, 'counts.json')
  fs.writeFileSync(file, JSON.stringify(counted, null, 1) + '\n')
  const args = writeFloor !== '' ? ['--floor', writeFloor, '--counts', file, '--write'] : ['--floor', floor, '--counts', file]
  const r = spawnSync('python3', ['-I', path.join(import.meta.dir, '..', 'check_floor.py'), ...args], { encoding: 'utf8' })
  process.stdout.write((r.stdout ?? '') + (r.stderr ?? ''))
  if (r.status !== 0) failed++
  fs.rmSync(tmp, { recursive: true, force: true })
}
console.log(failed === 0 ? 'e2e: all passed' : `e2e: ${failed} failed`)
process.exit(failed === 0 ? 0 : 1)
