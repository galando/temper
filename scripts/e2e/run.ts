// bun scripts/e2e/run.ts [mod|plain|driver|both|all] [scenario...] [--shard K/N]  (all: plain, mod and the mod's run driver)  (a live model smoke is not part of this: it stays off, and out of CI)
import { freshAsk, freshContest, freshNotRun, freshReview, armedRun, branchClash, branchClashCarry, contextCheck, designRun, failingScenario, fixRun, mavenRun, threeGroups, coveredAndManual, fullRun, hookScope, modGuards, prAndPipeline, saveAndResume, smallChange } from './scenarios'
import { pyjokesBlocked, pyjokesFull, pyjokesRun } from './pyjokes'
import { Denied, World } from './world'
import type { Mode } from './world'
import fs from 'node:fs'
import path from 'node:path'

const SCENARIOS: Record<string, (w: World) => void> = { 'full-run': fullRun, 'mod-guards': modGuards, 'small-change': smallChange, 'covered-and-manual': coveredAndManual, 'pr-and-pipeline': prAndPipeline, 'context-check': contextCheck, 'branch-clash': branchClash, 'branch-clash-carry': branchClashCarry, 'hook-scope': hookScope, 'failing-scenario': failingScenario, 'armed-run': armedRun, 'save-and-resume': saveAndResume, design: designRun, 'three-groups': threeGroups, maven: mavenRun, fix: fixRun, 'fresh-review': freshReview, 'fresh-not-run': freshNotRun, 'fresh-contest': freshContest, 'fresh-ask': freshAsk, pyjokes: pyjokesRun, 'pyjokes-full': pyjokesFull, 'pyjokes-blocked': pyjokesBlocked }

const want = process.argv[2] ?? 'both'
const modes: Mode[] = want === 'both' ? ['plain', 'mod'] : want === 'all' ? ['plain', 'mod', 'driver'] : [want as Mode]
// After the mode: scenario names and flags, in any order. --shard K/N keeps the scenarios of SCENARIOS whose index modulo
// N is K minus 1; every mode of a scenario stays in this one process, since the compare of the flow with the mod and
// without it reads two traces of one process.
const words: string[] = []
let shard: [number, number] | null = null
const rest = process.argv.slice(3)
for (let i = 0; i < rest.length; i++) {
  const a = rest[i]!
  if (a === '--shard') {
    const m = /^([1-9]\d*)\/([1-9]\d*)$/.exec(rest[++i] ?? '')
    if (m === null || Number(m[1]) > Number(m[2])) {
      console.log('FAIL: --shard takes K/N with 1 <= K <= N')
      process.exit(2)
    }
    shard = [Number(m[1]), Number(m[2])]
  } else if (a.startsWith('--')) {
    console.log(`FAIL: unknown flag ${a} (bun scripts/e2e/run.ts [mod|plain|driver|both|all] [scenario...] [--shard K/N])`)
    process.exit(2)
  } else words.push(a)
}
const unknown = words.filter(n => !(n in SCENARIOS))
if (unknown.length > 0) {
  console.log(`FAIL: no scenario ${unknown.join(', ')}`)
  process.exit(2)
}
const order = Object.keys(SCENARIOS)
const names = (words.length > 0 ? words : order).filter(n => shard === null || order.indexOf(n) % shard[1] === shard[0] - 1)
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
for (const name of names) {
  for (const mode of modes) {
    const w = new World(mode, name)
    try {
      SCENARIOS[name]!(w)
      traces[`${name}:${mode}`] = w.trace.filter(l => !l.startsWith('  call'))
      console.log(`PASS ${name} [${mode}] (${w.trace.length} steps, ${w.denials.length} refusals)`)
    } catch (e) {
      failed++
      console.log(`FAIL ${name} [${mode}]: ${(e as Error).message.slice(0, 1500)}`)
      if (e instanceof Denied) console.log('  (the mod refused a call the flow needs)')
      console.log(w.trace.slice(-12).join('\n'))
    }
    dumpTrace(w)
  }
  if (modes.includes('plain') && modes.includes('mod') && traces[`${name}:plain`] && traces[`${name}:mod`]) {
    const same = JSON.stringify(traces[`${name}:plain`]) === JSON.stringify(traces[`${name}:mod`])
    console.log(`${same ? 'PASS' : 'FAIL'} ${name}: the flow is identical with the mod and without it`)
    if (!same) failed++
  }
}
console.log(failed === 0 ? 'e2e: all passed' : `e2e: ${failed} failed`)
process.exit(failed === 0 ? 0 : 1)
