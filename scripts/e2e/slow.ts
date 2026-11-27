// The slow scripted project: an ordinary existing Maven project whose suite is slower than every default limit, with no
// model cost. Two scenarios state the final promises of rows D11 and D12 of docs/plans/one-go/done.md and are expected
// to fail until phase 5 (scripts/selftest/expected-fail.txt).
//
// The project: `backend/pom.xml` and no build file in the root, the shape of the measured run, which the CLI's
// detect() cannot read; the JDK is right (TOOL_JDK=24) and no service is needed (every suite line skips the integration
// tests); no coverage tool that Temper can run (the pom binds JaCoCo's check, as the plan gate's Maven rows want, and
// prints no total) and, but in `slow-at55`, no `check.commands` in the config, which is the file `temper init` writes. The plan is one group of two tasks in a chain, so the three whole suite runs of the
// promise are the base, the group and Check, whoever owns the suite command; its Validate and Integration lines are
// `cd backend && mvn -s settings.xml verify -DskipITs`, the form both Maven rows of the plan gate accept (WP21: in
// slow-first-run they are `cd backend && mvn -q verify`, the suite the CLI finds and the baseline runs).
//
// The faults the fixture plants (scripts/e2e/faketools.ts):
//   MOCK_SLOW_S=3                  a whole suite run (no -Dtest= filter) takes 3 seconds
//   TEMPER_TASK_TEST_TIMEOUT_S=1   the default limits of the head, set below the suite through the World's environment:
//   TEMPER_CHECK_TIMEOUT_S=1       a group gate, Check's run and the mutation budget each end in exit 124 at the head.
//   TEMPER_MUTATION_BUDGET_S=1     A limit of three times the measured time on the base (9 seconds) times out nothing.
// Slow without waiting: 3 seconds against 1 and against 9 leaves a factor of three on each side. Do not shorten it.
//
//   slow-first-run (plain, driver), row D11: the default person; the questions asked are plan.approve and commit.confirm
//     and no other; no line of the tool log has exit 124; at most 3 whole suite runs; Check passed with its coverage row
//     not measured, which the commit card names so (WP19); no call of the trace steps back to Plan; the config at the
//     end is byte equal to what init wrote.
//     WP20 adds (W20): the baseline runs in its own process; the approval card's baseline line shows it as it stands
//     (`running` when the approval comes first); at the end it is green with its seconds, and no group gate timed out.
//     WP22 adds (W22): the whole suite runs at most once for the one group and once on the base, and the floor's
//     `suite_runs` counts those runs of the tool log; each scenario test runs at most twice (they run through
//     unit/scenario.sh, which counts them apart from the task tests of the same script).
//   slow-at55 (plain), row D12: check.commands set; the coverage command prints backend/coverage-total.txt, which holds
//     `TOTAL 100 45 55%` on the base. Check passes at 55%. A second pass, whose builder writes 50% into that file: Check
//     fails with a row that names the drop.
import fs from 'node:fs'
import path from 'node:path'

import { POM, installTools, toolRuns, withRemote } from './faketools'
import { orchestrate } from './loop'
import type { Script } from './loop'
import { defaultPerson, idOf, pickId, worldCheck } from './persons'
import { ROOT, TEMPER, World, acceptanceLock, reviewDone } from './world'
import type { Agent, Json, Person } from './world'

export const SPEC = '.temper/specs/report'
export const SUITE = 'cd backend && mvn -s settings.xml verify -DskipITs'   // what both Maven rows accept
// WP21: the suite as the CLI finds it for this project (check_run.suite_owner, the one folder one level down with a pom);
// both Maven rows accept it too. In slow-first-run the plan's Validate and Integration line are this text, the suite
// the baseline ran, so `baseline plan` runs nothing more on the base
export const OWNER = 'cd backend && mvn -q verify'
export const SLOW_S = '3'
// WP20: the baseline's own limit is Check's unless TEMPER_BASELINE_TIMEOUT_S is set: set to the default here, so the
// base is measured whole and every later limit comes from it
export const LIMITS = { TEMPER_TASK_TEST_TIMEOUT_S: '1', TEMPER_CHECK_TIMEOUT_S: '1', TEMPER_MUTATION_BUDGET_S: '1', TEMPER_BASELINE_TIMEOUT_S: '1800' }

// ---- what the scripted agents write ---------------------------------------------------------------------------------

export const SCENARIOS_MD = `## Scenarios (BDD)

#### Happy Path

\`\`\`gherkin
Scenario: CI JSON shape is stable across a run
  Given a run with two stages
  When the CI report is built
  Then each stage is one object with stage, verdict and requirements
  Note: unit
  Covers: AC-01
  Test: bash unit/shape_test.sh
\`\`\`

\`\`\`gherkin
Scenario: Override rows name the approver
  Given a run with one override
  When the CI report is built
  Then the override row names the approver
  Note: manual
  Covers: AC-02
  Test: bash unit/shape_test.sh
\`\`\`

\`\`\`gherkin
Scenario: Same ledger gives the same bytes
  Given one ledger
  When the CI report is built twice
  Then both documents are byte for byte equal
  Note: unit
  Covers: AC-03
  Test: bash unit/bytes_test.sh
\`\`\`

`
export const BLOCKING = '- Blocking: Context check: is this the right context for the plan? choices: Right direction | Narrow the focus | Fix the sources.\n'

// The plan as agents/plan.md tells a planner to write it: the Context Map ends `reviewed: pending`.
export const planMd = (extra = ''): string => `# Plan: CI report

## Context Map

- use: intent.md AC-01, AC-03 - the accepted scope
- use: backend/ (2 files) - where the report code goes
- reviewed: pending

## Architecture

Two small classes build the report.

## Blast Radius

Two new classes and their tests. Nothing else reads them yet.

## Cross-Repo Search

- not available: no cross-repo search tool is connected, so local tools were used.

## Files to Create

| File | Purpose | Traced to |
|------|---------|-----------|
| backend/src/Shape.java | builds the stage objects | CI JSON shape is stable across a run |
| backend/src/test/java/ShapeTest.java | tests the shape | CI JSON shape is stable across a run |
| unit/shape_test.sh | runs the shape test | CI JSON shape is stable across a run |
| backend/src/Bytes.java | writes the document in a fixed order | Same ledger gives the same bytes |
| backend/src/test/java/BytesTest.java | tests the byte order | Same ledger gives the same bytes |
| unit/bytes_test.sh | runs the byte order test | Same ledger gives the same bytes |

## Files to Modify

| File | Change | Traced to |
|------|--------|-----------|
${extra}`

export const tasksMd = (extraFile = '', integration = SUITE, validate = SUITE): string => `# Tasks: CI report

**Integration:** \`${integration}\`

## Group G1: Report
**Depends:** none
**Validate:** \`${validate}\`
**Context:**
A Maven backend (JDK 24). Each task's test runs its own class through mvn.

### Task 1: Stage objects
**File:** \`backend/src/Shape.java\`, \`backend/src/test/java/ShapeTest.java\`, \`unit/shape_test.sh\`
**Depends:** none
**Test:** \`bash unit/shape_test.sh\`
**Cases:**
- a stage becomes an object with stage, verdict and requirements
- a stage with no requirements keeps an empty requirements array
**Traced to:** Scenario: "CI JSON shape is stable across a run"
- [ ] done

### Task 2: Byte order
**File:** \`backend/src/Bytes.java\`, \`backend/src/test/java/BytesTest.java\`, \`unit/bytes_test.sh\`${extraFile}
**Depends:** Task 1
**Test:** \`bash unit/bytes_test.sh\`
**Cases:**
- the same ledger gives the same bytes twice
- two stages are written in the order the ledger holds them
**Traced to:** Scenario: "Same ledger gives the same bytes"
- [ ] done
`

export const t = (w: World, args: string): { code: number; out: string } => {
  w.guardBash(`${TEMPER} ${args}`)
  return w.run(`${TEMPER} ${args}`)
}
const wtOf = (w: World, n: number): string => path.relative(w.dir, /^WORKTREE:\s*(\S+)/m.exec(t(w, `task show ${n}`).out)?.[1] ?? '')

// A build task: the test class and its runner first (RED), then the class (GREEN); `after` writes more in the worktree.
export function buildOne(w: World, n: number, after?: (w: World, wt: string, n: number) => void): void {
  const wt = wtOf(w, n)
  const [cls, val] = n === 1 ? ['Shape', 1] : ['Bytes', 2]
  w.write(path.join(wt, `backend/src/test/java/${cls}Test.java`), `class ${cls}Test { void check() { assert new ${cls}().v() == ${val}; } }\n`)
  w.write(path.join(wt, `unit/${cls.toLowerCase()}_test.sh`), `#!/usr/bin/env bash\ncd backend && mvn -q -s settings.xml test -Dtest=${cls}Test\n`)
  t(w, `task test ${n} --phase red`)
  w.write(path.join(wt, `backend/src/${cls}.java`), `class ${cls} { int v() { return ${val}; } }\n`)
  after?.(w, wt, n)
  t(w, `task test ${n} --phase green`)
}

export const buildTasks = (after?: (w: World, wt: string, n: number) => void): Agent => (w, a) => {
  const model = /\nModel:\s*(\S+?)\.?\s*$/m.exec(String(a.prompt))?.[1] ?? 'haiku'
  const tasks = (/Tasks?:\s*([\d, ]+)/.exec(String(a.prompt))?.[1] ?? '').split(',').map(x => Number(x.trim())).filter(Boolean)
  tasks.every((n, i) => {
    if (i > 0 && t(w, `task start ${n}`).code !== 0) return false
    buildOne(w, n, after)
    return t(w, `task gate ${n} --model ${model}`).code === 0
  })
}

// The scripted agents of a Maven project: a planner that writes the plan right and runs its own gate (agents/plan.md),
// builders that pass, a reviewer that finds nothing, and a Check agent for a version whose CLI finds no test command.
export function mavenAgents(plan: { plan?: string; tasks?: string } = {}, after?: (w: World, wt: string, n: number) => void): Record<string, Agent> {
  return {
    'temper:temper-intent': w => {
      w.write(`${SPEC}/intent.md`, fs.readFileSync(path.join(ROOT, 'templates/example-intent.md'), 'utf8'))
    },
    'temper:temper-plan': w => {
      let intent = w.read(`${SPEC}/intent.md`)
      if (!intent.includes('Test: bash unit/shape_test.sh')) intent = intent.replace('## Scenarios (BDD)\n', SCENARIOS_MD)
      if (!intent.includes(BLOCKING)) intent = intent.replace('### Open Questions\n', `### Open Questions\n\n${BLOCKING}`)
      w.write(`${SPEC}/intent.md`, intent)
      w.write(`${SPEC}/plan.md`, plan.plan ?? planMd())
      w.write(`${SPEC}/tasks.md`, plan.tasks ?? tasksMd())
      t(w, 'state set complexity simple')
      t(w, 'risk')
      t(w, 'gate plan')
    },
    'temper:temper-plan-review': () => undefined,
    'temper:temper-acceptance': w => { t(w, acceptanceLock(w, SPEC)) },
    'temper:temper-build-task': buildTasks(after),
    'temper:temper-build': () => undefined,
    'temper:temper-review': w => reviewDone(w),
    // Check of a version whose CLI found no test command: the agent runs the suite and the scenarios' tests through the
    // CLI; it has no coverage tool to run
    'temper:temper-check': w => {
      t(w, `evidence run --stage check --claim 'tests' -- bash -c '${SUITE}'`)
      for (const [s, cmd] of [['CI JSON shape is stable across a run', 'bash unit/shape_test.sh'], ['Override rows name the approver', 'bash unit/shape_test.sh'], ['Same ledger gives the same bytes', 'bash unit/bytes_test.sh']])
        t(w, `evidence run --stage check --scenario '${s}' --claim 'scenario: ${s}' -- ${cmd}`)
    },
  }
}

export const mavenScript = (agents: Record<string, Agent>, person: Person, extra: Partial<Script> = {}): Script => ({
  agents,
  person,
  afterFailStops: true,
  instruction: (_w, text) => /each file the run changed|^Copy what|^When .* records deviations/.test(text),
  ...extra,
})

// ---- the project ------------------------------------------------------------------------------------------------------

export type Project = { log: string; db: string; initConfig: string }

// The base commit of a Maven project, the fake tools on the PATH, the setup of /temper:init (`temper init` and
// `temper config init`; the config it writes is kept, and committed) and the run's state. `config` edits the config
// before the run; `env` sets the World's environment.
export function startMaven(w: World, files: Record<string, string>, opts: { env?: Record<string, string>; config?: (text: string) => string } = {}): Project {
  const { log, db } = installTools(w)
  for (const [k, v] of Object.entries(opts.env ?? {})) w.env[k] = v
  for (const [rel, text] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(w.dir, rel)), { recursive: true })
    fs.writeFileSync(path.join(w.dir, rel), text)
    if (rel.endsWith('.sh')) fs.chmodSync(path.join(w.dir, rel), 0o755)
  }
  w.sh('git add -A && git commit -qm base')
  // set up as /temper:init does: the .temper scaffold and the project's config from the template of the day, committed
  w.sh(`${TEMPER} init && ${TEMPER} config init`)
  const cfg = path.join(w.dir, '.claude/temper.config')
  if (opts.config) fs.writeFileSync(cfg, opts.config(fs.readFileSync(cfg, 'utf8')))
  const initConfig = fs.readFileSync(cfg, 'utf8')
  w.sh('git add .claude/temper.config && git commit -qm "chore: set up temper"')
  w.sh(`${TEMPER} state init report --feature 'CI report'`)
  return { log, db, initConfig }
}

export const SLOW_FILES: Record<string, string> = {
  'README.md': '# demo\n', '.gitignore': 'target/\n', 'backend/pom.xml': POM, 'backend/settings.xml': '<settings/>\n',
  'backend/src/test/java/.keep': '',
}

// The error of an assertion names its row.
export const expect = (cond: unknown, message: string): void => {
  if (!cond) throw new Error(message)
}
// A promise: whatever the run throws (an unexpected question, a broken run) is reported under the row it breaks.
export function promise<T>(token: string, fn: () => T): T {
  try {
    return fn()
  } catch (e) {
    const m = (e as Error).message
    throw new Error(m.startsWith(`${token} `) ? m : `${token} ${m}`)
  }
}

// Each question the person met, by id, and the gates as the CLI wrote them at the last Check or commit question.
export type Seen = { ids: string[]; gates: Json | null }
export function watching(person: Person, seen: Seen): Person {
  return (ask, w) => {
    seen.ids.push(idOf(ask))
    if (idOf(ask) === 'commit.confirm' || idOf(ask).startsWith('check.') || idOf(ask) === 'build.fail') {   // WP23: build.fail too
      seen.gates = w.exists('.temper/gates.json') ? w.json('.temper/gates.json') : null
    }
    return person(ask, w)
  }
}

export const stepsBackToPlan = (w: World): string[] => w.trace.filter(l => /^\s*call temper state loop \w+ plan\b/.test(l))
export const rowsOf = (gates: Json | null, stage: string): Json[] => {
  const g = gates?.[stage] ?? gates?.stages?.[stage] ?? null
  return (Array.isArray(g?.requirements) ? g.requirements : Array.isArray(g?.rows) ? g.rows : []) as Json[]
}
export const verdictOf = (gates: Json | null, stage: string): string => String(gates?.[stage]?.verdict ?? gates?.stages?.[stage]?.verdict ?? '')

// ---- the scenarios ------------------------------------------------------------------------------------------------------

// WP20: the baseline's file, and its line on the approval card. The card shows one of four forms: passes (with its
// seconds and the floor), running, fails on the current code, unknown with the reason. Read when the approval is asked:
// a baseline still running says `running` there.
export const BASELINE = '.temper/evidence/baseline.json'
export function baselineLine(wd: World): void {
  const b = wd.exists(BASELINE) ? wd.json(BASELINE) : null
  let card: Json | null = null
  try {
    card = wd.exists('.temper/view.json') ? ((wd.json('.temper/view.json').card ?? null) as Json | null) : null
  } catch {
    card = null
  }
  const sec = ((card?.sections ?? []) as Json[]).find(s => s?.id === 'baseline')
  const line = ((sec?.rows ?? []) as Json[]).map(r => String(r?.text ?? '')).join(' ')
  const want: Record<string, RegExp> = { running: /running/i, green: /pass/i, red: /fail/i, unknown: /unknown/i }
  const result = String(b?.result ?? 'none')
  expect(want[result] !== undefined && want[result]!.test(line),
    `W20 the approval card's baseline line shows the baseline as it stands (${result}): ${JSON.stringify(line).slice(0, 160)}`)
}

// WP22: the scenario tests of slow-first-run run through unit/scenario.sh, which writes the scenario's name to a count
// file outside the project before it runs the test, so their runs are told apart from the task tests of the same script
const scenarioRunner = (log: string): string => `#!/usr/bin/env bash\necho "$1" >> '${log}'\nexec bash "unit/$1_test.sh"\n`
const viaRunner = (intent: string): string => intent.replace(/Test: bash unit\/(shape|bytes)_test\.sh\n/g, 'Test: bash unit/scenario.sh $1\n')

export const slowFirstRun = (w: World): void => {
  withRemote(w)
  const scenLog = `${w.dir}.scenario-runs`
  fs.writeFileSync(scenLog, '')
  const p = startMaven(w, { ...SLOW_FILES, 'unit/scenario.sh': scenarioRunner(scenLog) }, { env: { TOOL_JDK: '24', MOCK_SLOW_S: SLOW_S, ...LIMITS } })
  // WP20: the baseline runs in its own process here, as in a session, so the approval may come before it ends
  delete w.env.TEMPER_BASELINE_FOREGROUND
  const seen: Seen = { ids: [], gates: null }
  // WP19: the text of the commit card, as `temper card` renders it, at the commit question
  let card = ''
  // WP20: the run's files as they stand at the commit question; the end of the run (state clear) removes them
  let atCommit: { base: Json | null; groups: Json | null } = { base: null, groups: null }
  const person = watching(defaultPerson(['plan.approve', 'commit.confirm']), seen)
  const reading: Person = (ask, wd) => {
    if (idOf(ask) === 'plan.approve') baselineLine(wd)
    if (idOf(ask) === 'commit.confirm') {
      card = wd.run(`python3 -B ${path.join(ROOT, 'scripts/card.py')} text .temper/view.json`).out
      atCommit = { base: wd.exists(BASELINE) ? wd.json(BASELINE) : null, groups: wd.exists('.temper/groups.json') ? wd.json('.temper/groups.json') : null }
    }
    return person(ask, wd)
  }
  const agents = mavenAgents({ tasks: tasksMd('', OWNER, OWNER) })
  const plan0 = agents['temper:temper-plan']!
  agents['temper:temper-plan'] = (wd, a) => {
    plan0(wd, a)
    wd.write(`${SPEC}/intent.md`, viaRunner(wd.read(`${SPEC}/intent.md`)))
    t(wd, 'gate plan')
  }
  promise('D11', () => orchestrate(w, mavenScript(agents, reading)))
  // WP20: the first group gate read the measured result: the base is green with its seconds, and no gate timed out
  const b = w.exists(BASELINE) ? w.json(BASELINE) : atCommit.base
  expect(b?.result === 'green' && typeof b?.seconds === 'number' && b.seconds >= Number(SLOW_S),
    `W20 the baseline measured the slow suite green, with its seconds (${JSON.stringify(b ?? null).slice(0, 200)})`)
  const groups = w.exists('.temper/groups.json') ? w.json('.temper/groups.json') : atCommit.groups
  const gTimed = Object.entries((groups?.groups ?? {}) as Json).filter(([, g]) => Number((g as Json)?.gate?.timeout_s ?? 0) > 0)
  expect(gTimed.length === 0, `W20 the first group gate read the measured result and timed out nowhere (${gTimed.map(([k]) => k).join(', ')})`)
  const runs = toolRuns(p.log)
  // WP22: the floor's suite_runs of this scenario are the whole suite runs of the tool log (the fake mvn writes nothing
  // to the count file of the World). The suite runs at most once for the one group and once on the base, and each
  // scenario test at most twice
  const whole = runs.filter(r => r.suite).length
  fs.appendFileSync(w.countFile, 'suite\n'.repeat(whole))
  expect(whole <= 1 + 1, `W22 the whole suite runs at most once per group plus once on the base (${whole} runs for 1 group: ${runs.filter(r => r.suite).map(r => r.args).join(' / ').slice(0, 200)})`)
  const scen = fs.readFileSync(scenLog, 'utf8').split('\n').filter(Boolean)
  const byName = Object.fromEntries(['shape', 'bytes'].map(n => [n, scen.filter(x => x === n).length]))
  expect(scen.length > 0, 'W22 the scenario tests ran through unit/scenario.sh (none ran: the intent kept its own Test: lines)')
  expect(Object.values(byName).every(n => n >= 1 && n <= 2), `W22 each scenario test runs at most twice (${JSON.stringify(byName)})`)
  const timedOut = runs.filter(r => r.exit === 124)
  expect(timedOut.length === 0, `D11 no limit is hit, and ${timedOut.length} run(s) of the tool log ended in exit 124: ${timedOut[0]?.line ?? ''}`)
  const suites = runs.filter(r => r.suite).length
  expect(suites <= 3, `D11 the whole suite runs at most 3 times, and the tool log holds ${suites} whole suite runs`)
  expect(JSON.stringify([...new Set(seen.ids)].sort()) === JSON.stringify(['commit.confirm', 'plan.approve']) && seen.ids.length === 2,
    `D11 the questions asked are plan.approve and commit.confirm and no other (${seen.ids.join(', ')})`)
  expect(verdictOf(seen.gates, 'check') === 'PASS', `D11 Check passed on correct code (its verdict: ${verdictOf(seen.gates, 'check') || 'none'})`)
  const cov = rowsOf(seen.gates, 'check').find(r => /^coverage\b/.test(String(r.name)))
  expect(cov !== undefined && cov.pass === null && cov.state === 'not measured', `D11 Check shows its coverage row as not measured (${JSON.stringify(cov ?? null)})`)
  expect(!seen.ids.some(id => id.startsWith('check.')), `D11 the run never stops at Check (${seen.ids.join(', ')})`)
  expect(/coverage: not measured/i.test(card), `D11 the commit card text holds coverage: not measured (${card.split('\n').filter(l => /coverage/i.test(l)).join(' / ').slice(0, 200) || 'no coverage line'})`)
  const back = stepsBackToPlan(w)
  expect(back.length === 0, `D11 no call of the trace steps back to Plan (${back[0] ?? ''})`)
  const cfg = w.exists('.claude/temper.config') ? w.read('.claude/temper.config') : ''
  expect(cfg === p.initConfig, 'D11 .claude/temper.config at the end is byte equal to the file temper init left')
  // WP07: the dialogs as the floor counts them (a Blocking or a More dialog is one too), and the planner launched once
  expect(w.counts.dialogs === 2, `D11 the run asks 2 dialogs (${w.counts.dialogs}: ${JSON.stringify(w.counts.by_stage)})`)
  const planners = w.counts.launches['temper:temper-plan'] ?? 0
  expect(planners === 1, `D11 the run never steps back to Plan: temper:temper-plan is launched once (${planners})`)
  // WP21: the plan's Validate and Integration line are the owner's text, which the baseline ran, so `baseline plan` has
  // nothing to run: the whole suite runs on the base (the tree of the commit the run started on) once, not twice
  const baseTree = w.run("git log --all --format=%T -1 --grep='^chore: set up temper$'").out.trim()
  const onBase = runs.filter(r => r.suite && baseTree !== '' && r.tree === baseTree)
  expect(onBase.length === 1, `W21 the whole suite runs on the base once, not twice (${onBase.length} runs: ${onBase.map(r => r.args).join(' / ').slice(0, 200)})`)
  worldCheck(w)
}

// The config with lines added at the top of its `check:` block (the block is made when the template has none).
export const withCheckLines = (text: string, lines: string): string =>
  /^check:\n/m.test(text) ? text.replace(/^check:\n/m, `check:\n${lines}`) : `${text.replace(/\n*$/, '\n')}check:\n${lines}`
// The coverage command prints the line of backend/coverage-total.txt after the suite ran.
export const at55Config = (text: string): string =>
  withCheckLines(text, `  commands:\n    test: ${SUITE}\n    coverage: ${SUITE} && cat coverage-total.txt\n`)
export const AT55_FILES = { ...SLOW_FILES, 'backend/coverage-total.txt': 'TOTAL 100 45 55%\n' }

// One pass of slow-at55: the run to its end, or to the first question that says the run failed. The check rows the
// person saw at Check.
function at55Pass(w: World, drop: boolean): Seen {
  withRemote(w)
  startMaven(w, AT55_FILES, { env: { TOOL_JDK: '24', MOCK_SLOW_S: SLOW_S, ...LIMITS }, config: at55Config })
  const seen: Seen = { ids: [], gates: null }
  const base = defaultPerson()
  const person: Person = (ask, wd) => {
    const id = idOf(ask)
    if (id === 'build.fail' && drop) return null   // the second pass ends at the failed Build gate (WP23: integrate measures coverage)
    // WP20: the second pass asks at every stage: a run that goes on by itself would take the one repair of the measured
    // drop (WP19) and loop back to Build, where this scripted builder has nothing to fix
    if (id === 'plan.approve' && drop) return pickId(wd, ask, 'ask-every-stage')
    if (/\.fail$|^group\.parked$|^task\.env$|^base\.red$|^plan\.command$|^run\.budget$/.test(id))
      throw new Error(`the run failed before Check passed: ${id}: ${String(ask.question?.question ?? '').split('\n')[0]!.slice(0, 200)}`)
    return base(ask, wd)
  }
  const agents = drop
    ? mavenAgents({ plan: planMd('| backend/coverage-total.txt | the measured total | Same ledger gives the same bytes |\n'), tasks: tasksMd(', `backend/coverage-total.txt`') },
      (wd, wt, n) => { if (n === 2) wd.write(path.join(wt, 'backend/coverage-total.txt'), 'TOTAL 100 50 50%\n') })
    : mavenAgents()
  promise('D12', () => orchestrate(w, mavenScript(agents, watching(person, seen))))
  return seen
}

export const slowAt55 = (w: World): void => {
  const first = at55Pass(w, false)
  const cov = rowsOf(first.gates, 'check').find(r => /^coverage\b/.test(String(r.name)))
  expect(verdictOf(first.gates, 'check') === 'PASS', `D12 Check passes at 55% (its verdict: ${verdictOf(first.gates, 'check') || 'none'}; coverage: ${JSON.stringify(cov ?? null)})`)
  worldCheck(w)
  // the second pass: the builder lowers the total to 50%
  const w2 = new World(w.mode, `${w.name}-drop`)
  w2.limitS = w.limitS
  const second = at55Pass(w2, true)
  const failing = rowsOf(second.gates, 'build').filter(r => r.pass === false)
  const drop = failing.find(r => /coverage/i.test(String(r.name)) && /55/.test(String(r.detail ?? '')) && /50/.test(String(r.detail ?? '')))
  expect(verdictOf(second.gates, 'build') === 'FAIL' && drop !== undefined,
    `D12 a drop from 55% to 50% fails the Build gate with a row that names it (verdict ${verdictOf(second.gates, 'build') || 'none'}; failed rows: ${failing.map(r => `${r.name}: ${r.detail}`).join('; ').slice(0, 300)})`)
  worldCheck(w2)
}

// The registered names, and the modes each runs in (the runner leaves out a mode a scenario does not name).
export const SLOW_SCENARIOS: Record<string, { run: (w: World) => void; modes: string[] }> = {
  'slow-first-run': { run: slowFirstRun, modes: ['plain', 'driver'] },
  'slow-at55': { run: slowAt55, modes: ['plain'] },
}
