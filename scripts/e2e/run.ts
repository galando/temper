// bun scripts/e2e/run.ts [mod|plain|both] [scenario...]  (a live model smoke is not part of this: it stays off, and out of CI)
import { freshContest, freshNotRun, freshReview, armedRun, branchClash, branchClashCarry, contextCheck, designRun, failingScenario, fixRun, mavenRun, threeGroups, coveredAndManual, fullRun, hookScope, modGuards, prAndPipeline, saveAndResume, smallChange } from './scenarios'
import { Denied, World } from './world'
import type { Mode } from './world'

const SCENARIOS: Record<string, (w: World) => void> = { 'full-run': fullRun, 'mod-guards': modGuards, 'small-change': smallChange, 'covered-and-manual': coveredAndManual, 'pr-and-pipeline': prAndPipeline, 'context-check': contextCheck, 'branch-clash': branchClash, 'branch-clash-carry': branchClashCarry, 'hook-scope': hookScope, 'failing-scenario': failingScenario, 'armed-run': armedRun, 'save-and-resume': saveAndResume, design: designRun, 'three-groups': threeGroups, maven: mavenRun, fix: fixRun, 'fresh-review': freshReview, 'fresh-not-run': freshNotRun, 'fresh-contest': freshContest }

const want = process.argv[2] ?? 'both'
const modes: Mode[] = want === 'both' ? ['plain', 'mod'] : [want as Mode]
const names = process.argv.slice(3).length > 0 ? process.argv.slice(3) : Object.keys(SCENARIOS)
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
  }
  if (modes.length === 2 && traces[`${name}:plain`] && traces[`${name}:mod`]) {
    const same = JSON.stringify(traces[`${name}:plain`]) === JSON.stringify(traces[`${name}:mod`])
    console.log(`${same ? 'PASS' : 'FAIL'} ${name}: the flow is identical with the mod and without it`)
    if (!same) failed++
  }
}
console.log(failed === 0 ? 'e2e: all passed' : `e2e: ${failed} failed`)
process.exit(failed === 0 ? 0 : 1)
