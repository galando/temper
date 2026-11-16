// The slow scripted project: an ordinary existing Maven project whose suite is slower than every default limit, with no
// model cost. Two scenarios state the final promises of rows D11 and D12 of docs/plans/one-go/done.md and are expected
// to fail until phase 5 (scripts/selftest/expected-fail.txt).
//
// The project: `backend/pom.xml` and no build file in the root, the shape of the measured run, which the CLI's
// detect() cannot read; the JDK is right (TOOL_JDK=24) and no service is needed (every suite line skips the integration
// tests); no coverage tool that Temper can run (the pom binds JaCoCo's check, as the plan gate's Maven rows want, and
// prints no total) and, but in `slow-at55`, no `check.commands` in the config, which is the file `temper init` writes. The plan is one group of two tasks in a chain, so the three whole suite runs of the
// promise are the base, the group and Check, whoever owns the suite command; its Validate and Integration lines are
// `cd backend && mvn -s settings.xml verify -DskipITs`, the form both Maven rows of the plan gate accept.
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
//     not measured; no call of the trace steps back to Plan; the config at the end is byte equal to what init wrote.
//   slow-at55 (plain), row D12: check.commands set; the coverage command prints backend/coverage-total.txt, which holds
//     `TOTAL 100 45 55%` on the base. Check passes at 55%. A second pass, whose builder writes 50% into that file: Check
//     fails with a row that names the drop.
import fs from 'node:fs'
import path from 'node:path'

import { POM, installTools, toolRuns, withRemote } from './faketools'
import { orchestrate } from './loop'
import type { Script } from './loop'
import { defaultPerson, idOf, worldCheck } from './persons'
import { ROOT, TEMPER, World } from './world'
import type { Agent, Json, Person } from './world'

export const SPEC = '.temper/specs/report'
export const SUITE = 'cd backend && mvn -s settings.xml verify -DskipITs'   // what both Maven rows accept
export const SLOW_S = '3'
export const LIMITS = { TEMPER_TASK_TEST_TIMEOUT_S: '1', TEMPER_CHECK_TIMEOUT_S: '1', TEMPER_MUTATION_BUDGET_S: '1' }

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

export const tasksMd = (extraFile = '', integration = SUITE): string => `# Tasks: CI report

**Integration:** \`${integration}\`

## Group G1: Report
**Depends:** none
**Validate:** \`${SUITE}\`
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
    'temper:temper-acceptance': w => { t(w, "acceptance skip --reason 'the scripted project writes no acceptance tests'") },
    'temper:temper-build-task': buildTasks(after),
    'temper:temper-build': () => undefined,
    'temper:temper-review': w => { t(w, "evidence add --stage review --claim 'review completed' --exit 0 --cmd 'review panel'") },
    // Check of a version whose CLI found no test command: the agent runs the suite and the scenarios' tests through the
    // CLI; it has no coverage tool to run
    'temper:temper-check': w => {
      t(w, `evidence run --stage check --claim 'tests' -- bash -c '${SUITE}'`)
      for (const [s, cmd] of [['CI JSON shape is stable across a run', 'bash unit/shape_test.sh'], ['Override rows name the approver', 'bash unit/shape_test.sh'], ['Same ledger gives the same bytes', 'bash unit/bytes_test.sh']])
        t(w, `evidence run --stage check --scenario '${s}' --claim 'scenario: ${s}' -- ${cmd}`)
    },
    'temper:temper-env': () => undefined,
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
    if (idOf(ask) === 'commit.confirm' || idOf(ask).startsWith('check.')) {
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

export const slowFirstRun = (w: World): void => {
  withRemote(w)
  const p = startMaven(w, SLOW_FILES, { env: { TOOL_JDK: '24', MOCK_SLOW_S: SLOW_S, ...LIMITS } })
  const seen: Seen = { ids: [], gates: null }
  promise('D11', () => orchestrate(w, mavenScript(mavenAgents(), watching(defaultPerson(['plan.approve', 'commit.confirm']), seen))))
  const runs = toolRuns(p.log)
  const timedOut = runs.filter(r => r.exit === 124)
  expect(timedOut.length === 0, `D11 no limit is hit, and ${timedOut.length} run(s) of the tool log ended in exit 124: ${timedOut[0]?.line ?? ''}`)
  const suites = runs.filter(r => r.suite).length
  expect(suites <= 3, `D11 the whole suite runs at most 3 times, and the tool log holds ${suites} whole suite runs`)
  expect(JSON.stringify([...new Set(seen.ids)].sort()) === JSON.stringify(['commit.confirm', 'plan.approve']) && seen.ids.length === 2,
    `D11 the questions asked are plan.approve and commit.confirm and no other (${seen.ids.join(', ')})`)
  expect(verdictOf(seen.gates, 'check') === 'PASS', `D11 Check passed on correct code (its verdict: ${verdictOf(seen.gates, 'check') || 'none'})`)
  const cov = rowsOf(seen.gates, 'check').find(r => /^coverage\b/.test(String(r.name)))
  expect(cov !== undefined && cov.pass === null && cov.state === 'not measured', `D11 Check shows its coverage row as not measured (${JSON.stringify(cov ?? null)})`)
  const back = stepsBackToPlan(w)
  expect(back.length === 0, `D11 no call of the trace steps back to Plan (${back[0] ?? ''})`)
  const cfg = w.exists('.claude/temper.config') ? w.read('.claude/temper.config') : ''
  expect(cfg === p.initConfig, 'D11 .claude/temper.config at the end is byte equal to the file temper init left')
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
    if (id === 'check.fail' && drop) return null   // the second pass ends at the failed Check
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
  const failing = rowsOf(second.gates, 'check').filter(r => r.pass === false)
  const drop = failing.find(r => /coverage/i.test(String(r.name)) && /55/.test(String(r.detail ?? '')) && /50/.test(String(r.detail ?? '')))
  expect(verdictOf(second.gates, 'check') === 'FAIL' && drop !== undefined,
    `D12 a drop from 55% to 50% fails Check with a row that names it (verdict ${verdictOf(second.gates, 'check') || 'none'}; failed rows: ${failing.map(r => `${r.name}: ${r.detail}`).join('; ').slice(0, 300)})`)
  worldCheck(w2)
}

// The registered names, and the modes each runs in (the runner leaves out a mode a scenario does not name).
export const SLOW_SCENARIOS: Record<string, { run: (w: World) => void; modes: string[] }> = {
  'slow-first-run': { run: slowFirstRun, modes: ['plain', 'driver'] },
  'slow-at55': { run: slowAt55, modes: ['plain'] },
}
