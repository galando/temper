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
//     CLI ran it once more before any agent, the ledger holds a row that calls it flaky, and no agent was launched for it.
import fs from 'node:fs'
import path from 'node:path'

import { POM, recordOf, toolRuns, withRemote } from './faketools'
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

// The project, its fake tools and its faults. The base tree of the late flaky test is the tree of the base commit.
export function startBroken(w: World, later: boolean): { log: string; db: string; initConfig: string } {
  const env: Record<string, string> = { MOCK_RED: RED, MOCK_FLAKY_BASE: FLAKY }
  if (later) env.MOCK_FLAKY_LATER = FLAKY_LATER
  const p = startMaven(w, BROKEN_FILES, { env, config: brokenConfig })
  fs.writeFileSync(path.join(p.db, 'flaky-later.base'), `${w.sh("git rev-parse 'HEAD^{tree}'").trim()}\n`)
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
    if (text.includes(RED)) redNamed = true
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
  // The rerun: the same command, after the failure and before the next agent launch.
  const check = (where: string): void => {
    const f = flakyFailure(p.db, p.log)
    if (f.at < 0) return
    const next = launches.find(l => l.runs > f.at)
    const runs = toolRuns(p.log)
    const again = runs.findIndex((r, i) => i > f.at && r.args === f.args)
    expect(again >= 0 && (next === undefined || again < next.runs),
      `D14 ${FLAKY_LATER} failed in \`mvn ${f.args}\` and the CLI did not run it once more before ${next ? `launching ${next.type}` : where}`)
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
