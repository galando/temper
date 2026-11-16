// The broken scripted project: the project of the replay (scripts/e2e/replay.ts), with no model cost, where every fault
// is one of the environment or of the base: the plan is right (its Validate is the form both Maven rows accept) and the
// reviewer finds nothing. Two scenarios state the final promises of rows D13 and D14 of docs/plans/one-go/done.md and
// are expected to fail until phase 5 (scripts/selftest/expected-fail.txt).
//
// The project: backend/pom.xml wants JDK 24 (the enforcer rule [24,)) and binds a JaCoCo check; the shell has 21;
// scripts/ensure-jdk24.sh --export prints what fixes it; the integration tests read IT_POSTGRES_PORT and need Postgres,
// which is down (fake pg_lsclusters, pg_isready, pg_ctlcluster); its existing tests are LegacyTest, ClockTest and
// RetryTest. The config is the replay's: check.commands run the whole suite with the integration tests, and the
// mutation gate is off.
//
// The faults the fixture plants (scripts/e2e/faketools.ts):
//   TOOL_JDK unset             the wrong tool version: every mvn call fails the enforcer rule until a setup block exports it
//   no $MOCK_DB/up             the service that is down: a verify without -DskipITs fails with Connection refused
//   MOCK_RED=LegacyTest        a test that is red on the current code, on every tree
//   MOCK_FLAKY_BASE=ClockTest  a flaky test: it fails the first time it runs and passes after
//   MOCK_FLAKY_LATER=RetryTest (broken-flaky only) a test that passes on the base tree and fails once, the first time it
//                              runs on another tree
//
//   broken-first-run (plain, driver), row D13: in this order, the first question is asked with no agent launched and
//     names the tool version and the service; its recommended option adds the setup block; the block written to the
//     config is byte equal to the block that question showed; the red test is named in a question before the planner is
//     launched; no launch of temper:temper-env and no fix pass of temper:temper-build in the whole run; no call of the
//     trace steps back to Plan; the last question is commit.confirm, with the red test and the first flaky test on the
//     commit card; at most 4 dialogs.
//   broken-flaky (plain), row D14: the second flaky test fails once at the first gate that runs it on another tree; the
//     CLI ran it once more at once (the next mvn call is the same command on the same tree, before any agent), the
//     ledger holds a row that calls it flaky, and no agent was launched for it.
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

import { MVN, POM, recordOf, toolRuns, withRemote } from './faketools'
import type { ToolRun } from './faketools'
import { orchestrate } from './loop'
import { defaultPerson, idOf, withoutSetup, worldCheck } from './persons'
import { expect, mavenAgents, mavenScript, planMd, promise, startMaven, stepsBackToPlan, tasksMd, withCheckLines } from './slow'
import type { World } from './world'
import type { Json, Person } from './world'

export const INTEGRATION = 'cd backend && mvn -s settings.xml verify'
export const RED = 'LegacyTest'
export const FLAKY = 'ClockTest'
export const FLAKY_LATER = 'RetryTest'
const ALLOWED = ['base.red', 'plan.approve', 'commit.confirm']   // the setup block, the red base, the approval, the commit

const testClass = (name: string): string => `class ${name} { void check() { } }\n`
export const BROKEN_FILES: Record<string, string> = {
  'README.md': '# demo\n', '.gitignore': '__pycache__/\ntarget/\n', 'backend/pom.xml': POM, 'backend/settings.xml': '<settings/>\n',
  'backend/src/test/ItBase.java': 'class ItBase { String port = System.getenv("IT_POSTGRES_PORT"); }\n',
  [`backend/src/test/java/${RED}.java`]: testClass(RED),
  [`backend/src/test/java/${FLAKY}.java`]: testClass(FLAKY),
  [`backend/src/test/java/${FLAKY_LATER}.java`]: testClass(FLAKY_LATER),
  'scripts/ensure-jdk24.sh': '#!/usr/bin/env bash\n[ "$1" = --export ] && echo "export TOOL_JDK=24"\n',
}
// The config of the replay: the whole suite with the integration tests, a total it prints, and no mutation gate.
export const brokenConfig = (text: string): string =>
  withCheckLines(text, `  mutation-threshold: 0\n  commands:\n    test: ${INTEGRATION}\n    coverage: ${INTEGRATION} && echo 'TOTAL 100 5 95%'\n`)

// The base tree of the late flaky test: the tree of the code (the pom's folder) at HEAD, the key the fake mvn compares.
export const CODE_TREE = 'git rev-parse HEAD:backend'
// The project, its fake tools and its faults. The base tree of the late flaky test is the code of the base commit, so
// the commits of the run's spec and config leave it on the base.
export function startBroken(w: World, later: boolean): { log: string; db: string; initConfig: string } {
  const env: Record<string, string> = { MOCK_RED: RED, MOCK_FLAKY_BASE: FLAKY }
  if (later) env.MOCK_FLAKY_LATER = FLAKY_LATER
  const p = startMaven(w, BROKEN_FILES, { env, config: brokenConfig })
  fs.writeFileSync(path.join(p.db, 'flaky-later.base'), `${w.sh(CODE_TREE).trim()}\n`)
  return p
}
export const agents = () => mavenAgents({ plan: planMd(), tasks: tasksMd('', INTEGRATION) })

// The text the person reads at a question: the question, its options and the card.
const shown = (ask: Json): string =>
  [String(ask.question?.question ?? ''), ...((ask.options ?? []) as Json[]).map(o => `${o.label} ${o.description ?? ''}`), JSON.stringify(ask.card ?? '')].join('\n')
// The setup: block of a config, as it stands in the file.
const setupBlock = (config: string): string => {
  const m = /^setup:\n(?:(?:[ \t].*)?\n)*/m.exec(config)
  return m ? m[0].replace(/\n+$/, '\n') : ''
}

export const brokenFirstRun = (w: World): void => {
  withRemote(w)
  const p = startBroken(w, false)
  const rec = recordOf(w)!
  const asked: Json[] = []
  const types = (): string[] => rec.agents.map(a => a.type)
  let redNamed = false
  let redBeforePlan = false
  const base = defaultPerson(ALLOWED)
  const person: Person = (ask, wd) => {
    asked.push(ask)
    const text = shown(ask)
    if (asked.length === 1) {
      expect(rec.agents.length === 0, `D13 the first question is asked with no agent launched (launched: ${types().join(', ')}; asked ${idOf(ask)})`)
      expect(/JDK|Java/.test(text) && /\b24\b/.test(text), `D13 the first question names the tool version, JDK 24 (${idOf(ask)}: ${text.slice(0, 160)})`)
      expect(/Postgres|database|Connection refused/i.test(text), `D13 the first question names the service, the database (${idOf(ask)}: ${text.slice(0, 160)})`)
      const rec1 = ((ask.options ?? []) as Json[]).find(o => o.recommended === true)
      expect(rec1?.id === 'add-setup', `D13 the recommended option of the first question adds the setup block (it is ${rec1?.id ?? 'none'})`)
    }
    if (asked.length === 2) {
      const block = setupBlock(wd.exists('.claude/temper.config') ? wd.read('.claude/temper.config') : '')
      expect(block !== '' && shown(asked[0]!).includes(block.trimEnd()), `D13 the setup block written to the config is byte equal to the block the first question showed (${JSON.stringify(block.slice(0, 120))})`)
    }
    // WP07: only a question asked while the planner had not been launched names the red test before it
    expect(!types().includes('temper:temper-plan') || redBeforePlan, `D13 the red test ${RED} was named in a question before temper:temper-plan was launched (asked ${asked.map(idOf).join(', ')})`)
    if (text.includes(RED)) redNamed = true
    if (redNamed && !types().includes('temper:temper-plan')) redBeforePlan = true
    expect(redNamed || !types().includes('temper:temper-plan'), `D13 the red test ${RED} is named in a question before temper:temper-plan is launched (asked ${asked.map(idOf).join(', ')})`)
    expect(!types().includes('temper:temper-env') && !types().includes('temper:temper-build'), `D13 no environment agent and no fix pass are launched (${types().join(', ')})`)
    return base(ask, wd)
  }
  promise('D13', () => orchestrate(w, mavenScript(agents(), person)))
  expect(redNamed, `D13 the red test ${RED} is named in a question before the planner (asked ${asked.map(idOf).join(', ')})`)
  expect(!types().includes('temper:temper-env') && !types().includes('temper:temper-build'), `D13 no environment agent and no fix pass are launched (${types().join(', ')})`)
  const back = stepsBackToPlan(w)
  expect(back.length === 0, `D13 no call of the trace steps back to Plan (${back[0] ?? ''})`)
  const last = asked[asked.length - 1]
  expect(last !== undefined && idOf(last) === 'commit.confirm', `D13 the last question is commit.confirm (${last ? idOf(last) : 'none'})`)
  expect(shown(last!).includes(RED) && shown(last!).includes(FLAKY), `D13 the commit card lists the red test ${RED} and the flaky test ${FLAKY}`)
  expect(asked.length <= 4, `D13 the run asks at most 4 dialogs (${asked.length}: ${asked.map(idOf).join(', ')})`)
  expect(withoutSetup(w.read('.claude/temper.config')) === withoutSetup(p.initConfig), 'D13 the config changed only in a setup: block, which the person added')
  // WP07: the dialogs as the floor counts them, and the planner launched once (no step back to Plan)
  expect(w.counts.dialogs <= 4, `D13 the run asks at most 4 dialogs as the floor counts them (${w.counts.dialogs}: ${JSON.stringify(w.counts.by_stage)})`)
  const planners = w.counts.launches['temper:temper-plan'] ?? 0
  expect(planners === 1, `D13 no step back to Plan: temper:temper-plan is launched once (${planners})`)
  worldCheck(w)
}

// Where the late flaky test failed: the index of the failing call in the tool log, or -1 while it has not failed.
function flakyFailure(db: string, log: string): { at: number; args: string } {
  const mark = path.join(db, 'flaky-later.failed')
  if (!fs.existsSync(mark)) return { at: -1, args: '' }
  const before = Number(fs.readFileSync(mark, 'utf8').trim().split(/\s+/)[1] ?? '0')
  const runs = toolRuns(log)
  const at = runs.findIndex((r, i) => i >= before && r.suite && r.exit !== 0)
  return { at, args: at >= 0 ? runs[at]!.args : '' }
}

// The rerun of row D14 (WP22 step 9: once more at once, on the same tree): the mvn call right after the failure at `at`
// is the same command on the tree of the failure, before the next agent launch. `launchAt` is the number of tool runs
// before that launch, or null when none came after the failure.
export function reranAtOnce(runs: ToolRun[], at: number, launchAt: number | null): boolean {
  const failed = runs[at]
  const again = runs[at + 1]
  if (failed === undefined || again === undefined) return false
  return again.args === failed.args && again.tree !== '' && again.tree === failed.tree && (launchAt === null || at + 1 < launchAt)
}

export const brokenFlaky = (w: World): void => {
  withRemote(w)
  const p = startBroken(w, true)
  const launches: { type: string; runs: number }[] = []   // each launch, with the number of tool runs before it
  const watched = Object.fromEntries(Object.entries(agents()).map(([type, a]) => [type, ((wd: World, x: Json) => {
    launches.push({ type, runs: toolRuns(p.log).length })
    a(wd, x)
  })]))
  // Every row of every ledger, and of the gates, one JSON text a row.
  let ledgers: string[] = []
  const read = (wd: World): string[] => {
    const rows: string[] = []
    const add = (v: unknown): void => { if (Array.isArray(v)) for (const r of v) rows.push(JSON.stringify(r)) }
    const files = wd.exists('.temper/evidence') ? fs.readdirSync(path.join(wd.dir, '.temper/evidence')).filter(f => f.endsWith('.json')).map(f => `.temper/evidence/${f}`) : []
    for (const f of files) {
      try {
        add(JSON.parse(wd.read(f)))
      } catch {
        continue
      }
    }
    try {
      for (const g of Object.values(wd.json('.temper/gates.json'))) add((g as Json)?.requirements)
    } catch {
      // no gates yet
    }
    return rows
  }
  // The rerun: the next mvn call, on the same tree, before the next agent launch.
  const check = (where: string): void => {
    const f = flakyFailure(p.db, p.log)
    if (f.at < 0) return
    const next = launches.find(l => l.runs > f.at)
    const runs = toolRuns(p.log)
    expect(reranAtOnce(runs, f.at, next?.runs ?? null),
      `D14 ${FLAKY_LATER} failed in \`mvn ${f.args}\` and the CLI did not run it once more at once, on the same tree, before ${next ? `launching ${next.type}` : where} (the next call: ${runs[f.at + 1]?.line ?? 'none'})`)
    const fixers = launches.filter(l => l.runs > f.at && ['temper:temper-build', 'temper:temper-env'].includes(l.type))
    expect(fixers.length === 0, `D14 no agent is launched for the flaky test (${fixers.map(l => l.type).join(', ')})`)
  }
  const flakyRow = (where: string): void => {
    const rows = [...ledgers, ...read(w)].filter(l => l.includes(FLAKY_LATER) && /flaky/i.test(l))
    expect(rows.length > 0, `D14 the ledger holds no row that calls ${FLAKY_LATER} flaky at ${where}`)
  }
  const base = defaultPerson()
  let n = 0
  const person: Person = (ask, wd) => {
    n++
    ledgers = read(wd)
    check(`asking ${idOf(ask)}`)
    expect(n <= 12, `D14 the run asked more than 12 questions and ${FLAKY_LATER} never failed (${idOf(ask)})`)
    return base(ask, wd)
  }
  promise('D14', () => {
    try {
      orchestrate(w, mavenScript(watched, person))
    } catch (e) {
      const m = (e as Error).message
      if (m.startsWith('D14 ')) throw e
      if (flakyFailure(p.db, p.log).at < 0) throw new Error(`D14 the run stopped before ${FLAKY_LATER} failed at a gate: ${m}`)
      const where = `the run stopped (${m.split('\n')[0]!.slice(0, 120)})`
      check(where)
      flakyRow(where)
      throw e
    }
  })
  check('the end of the run')
  expect(flakyFailure(p.db, p.log).at >= 0, `D14 ${FLAKY_LATER} failed at no gate: the fixture planted no fault`)
  flakyRow('the end of the run')
  worldCheck(w)
}

// The registered names, and the modes each runs in (the runner leaves out a mode a scenario does not name).
export const BROKEN_SCENARIOS: Record<string, { run: (w: World) => void; modes: string[] }> = {
  'broken-first-run': { run: brokenFirstRun, modes: ['plain', 'driver'] },
  'broken-flaky': { run: brokenFlaky, modes: ['plain'] },
}

// ---- the check of this file, on made up input -------------------------------------------------------------------------
//
//   bun scripts/e2e/broken.ts --check   asserts the faults of the fixture and the checks of the two scenarios on made up
//                                       input, with no run of the CLI; exit 0 or 1

function check(): number {
  let fails = 0
  const eq = (name: string, got: unknown, want: unknown): void => {
    const ok = JSON.stringify(got) === JSON.stringify(want)
    if (!ok) fails++
    console.log(`${ok ? 'PASS' : 'FAIL'}: broken ${name}${ok ? '' : ` (got ${JSON.stringify(got)}, want ${JSON.stringify(want)})`}`)
  }
  // the fake mvn in a scratch copy of the project, with the late flaky test on and its base written as startBroken does
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'broken-check-'))
  const tools = path.join(dir, 'tools')
  const db = path.join(dir, 'db')
  const proj = path.join(dir, 'project')
  for (const d of [tools, db, proj]) fs.mkdirSync(d)
  fs.writeFileSync(path.join(tools, 'mvn'), MVN, { mode: 0o755 })
  const log = path.join(tools, 'calls.log')
  fs.writeFileSync(log, '')
  const env: Record<string, string> = {
    PATH: `${tools}:${process.env.PATH ?? ''}`, HOME: dir, MOCK_LOG: log, MOCK_DB: db, TOOL_JDK: '24', MOCK_FLAKY_LATER: FLAKY_LATER,
    GIT_AUTHOR_NAME: 't', GIT_AUTHOR_EMAIL: 't@t', GIT_COMMITTER_NAME: 't', GIT_COMMITTER_EMAIL: 't@t', GIT_CONFIG_NOSYSTEM: '1',
  }
  const sh = (cmd: string): { code: number; out: string } => {
    const r = spawnSync('bash', ['-c', cmd], { cwd: proj, env, encoding: 'utf8' })
    return { code: r.status ?? -1, out: `${r.stdout ?? ''}${r.stderr ?? ''}` }
  }
  for (const [rel, text] of Object.entries(BROKEN_FILES)) {
    fs.mkdirSync(path.dirname(path.join(proj, rel)), { recursive: true })
    fs.writeFileSync(path.join(proj, rel), text)
  }
  sh('git init -q && git add -A && git commit -qm base')
  fs.writeFileSync(path.join(db, 'flaky-later.base'), `${sh(CODE_TREE).out.trim()}\n`)
  const suite = (): number => sh('cd backend && mvn -s settings.xml verify -DskipITs').code
  sh('mkdir -p .temper/specs/report && echo intent > .temper/specs/report/intent.md && git add -A && git commit -qm spec')
  eq(`the late flaky test passes after a commit of the spec alone: the code is still on the base`, suite(), 0)
  sh('echo "class Shape { }" > backend/src/Shape.java && git add -A && git commit -qm code')
  eq(`the late flaky test fails once, the first time it runs on another code tree, and passes after`, [suite(), suite()], [1, 0])
  const real = toolRuns(log)
  eq('each line of the tool log carries the tree it ran on, and a run again at once on it is the rerun of D14',
    [real.every(r => /^[0-9a-f]{40}$/.test(r.tree)), reranAtOnce(real, real.length - 2, null)], [true, true])
  // made up tool logs: the failure is the first line
  const made = (...lines: string[]): ToolRun[] => {
    const f = path.join(dir, 'made.log')
    fs.writeFileSync(f, lines.map(l => `mvn ${l} exit=0 port=\n`).join(''))
    return toolRuns(f)
  }
  const fail = 'verify -DskipITs jdk=24 db=up tree=t1'
  eq('D14 rerun: the same command later, after another call, is no rerun (what the head of phase 2 passed with)',
    reranAtOnce(made(fail, 'verify jdk=24 db=up tree=t1', fail), 0, null), false)
  eq('D14 rerun: the next call on the same tree is the rerun', reranAtOnce(made(fail, fail), 0, null), true)
  eq('D14 rerun: the next call on another tree is no rerun', reranAtOnce(made(fail, 'verify -DskipITs jdk=24 db=up tree=t2'), 0, null), false)
  eq('D14 rerun: another command next, on the same tree, is no rerun', reranAtOnce(made(fail, 'test -Dtest=ShapeTest jdk=24 db=up tree=t1'), 0, null), false)
  eq('D14 rerun: the next call after an agent launch is no rerun', reranAtOnce(made(fail, fail), 0, 1), false)
  fs.rmSync(dir, { recursive: true, force: true })
  console.log(`broken --check: ${fails === 0 ? 'PASS' : `FAIL (${fails})`}`)
  return fails === 0 ? 0 : 1
}

if (import.meta.main) {
  if (process.argv[2] === '--check') process.exit(check())
  console.log('usage: bun scripts/e2e/broken.ts --check')
  process.exit(2)
}
