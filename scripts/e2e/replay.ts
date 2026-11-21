// The source run, replayed on a mock project, against any version of Temper (9.8.5 A/B proof).
//   TEMPER_E2E_ROOT=<plugin folder> bun scripts/e2e/replay.ts [label]   prints one JSON line of measurements
//
// The mock project has the faults of the measured run (a Java 24 Maven backend, 3.2 hours of agent time):
//   - the Maven enforcer needs JDK [24,); the shell has 21 (fake `mvn` and `java`, switched by TOOL_JDK);
//   - backend/pom.xml binds a JaCoCo check with a BUNDLE rule, and the plan's Validate line is a filtered verify
//     (`verify -Dtest=...`), which can never meet it: the tests pass, then the coverage rule fails;
//   - the integration tests need Postgres (fake pg_lsclusters, pg_isready, pg_ctlcluster; down at the start);
//   - Review finds one High defect that breaks a constraint of the intent.
// The project also has what a real project has: scripts/ensure-jdk24.sh --export, a test that reads IT_POSTGRES_PORT.
//
// The same scripted agents and the same scripted person run against both versions. The person takes the recommended
// option of every question. When a question shows an environment fault the version cannot repair (the JDK, the
// database), the person repairs the shell by hand, as the person and the orchestrator did in the measured run: export
// the JDK, start the database. Each such repair is counted. Every call of the fake tools is logged.
import fs from 'node:fs'
import path from 'node:path'

import { POM, installTools } from './faketools'
import { orchestrate } from './loop'
import type { Script } from './loop'
import { ROOT, TEMPER, World, reviewDone } from './world'
import type { Agent, Json } from './world'

// WP29: the config with lines at the top of its `check:` block, made when the template has none (the template of
// 9.8.5 holds the block only as a comment)
const checkLines = (text: string, lines: string): string =>
  /^check:\n/m.test(text) ? text.replace(/^check:\n/m, `check:\n${lines}`) : `${text.replace(/\n*$/, '\n')}check:\n${lines}`

const SPEC = '.temper/specs/report'
const label = process.argv[2] ?? 'run'
const NEW = fs.existsSync(path.join(ROOT, 'scripts/runs.py'))   // 9.8.5 and later: runs count only when the CLI ran them

// ---- the fake toolchain: scripts/e2e/faketools.ts (MVN, JAVA, PG, POM and the lines that install them) -----------

// ---- the plan the scripted Plan agent writes --------------------------------------------------------------------------
const BAD_VALIDATE = "cd backend && mvn -s settings.xml verify -Dtest='*Test' -DskipITs"
const GOOD_VALIDATE = 'cd backend && mvn -s settings.xml verify -DskipITs'   // what both Maven rows accept
const INTEGRATION = 'cd backend && mvn -s settings.xml verify'
const scenarios = `## Scenarios (BDD)

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
const planMd = `# Plan: CI report

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
| unit/shape_test.sh | tests the shape | CI JSON shape is stable across a run |
| backend/src/Bytes.java | writes the document in a fixed order | Same ledger gives the same bytes |
| unit/bytes_test.sh | tests the byte order | Same ledger gives the same bytes |

## Files to Modify

| File | Change | Traced to |
|------|--------|-----------|
`
const tasksMd = (validate: string): string => `# Tasks: CI report

**Integration:** \`${INTEGRATION}\`

## Group G1: Report
**Depends:** none
**Validate:** \`${validate}\`
**Context:**
A Maven backend (JDK 24). Each task's test runs its own class through mvn.

### Task 1: Stage objects
**File:** \`backend/src/Shape.java\`, \`unit/shape_test.sh\`
**Depends:** none
**Test:** \`bash unit/shape_test.sh\`
**Cases:**
- a stage becomes an object with stage, verdict and requirements
- a stage with no requirements keeps an empty requirements array
**Traced to:** Scenario: "CI JSON shape is stable across a run"
- [ ] done

### Task 2: Byte order
**File:** \`backend/src/Bytes.java\`, \`unit/bytes_test.sh\`
**Depends:** Task 1
**Test:** \`bash unit/bytes_test.sh\`
**Cases:**
- the same ledger gives the same bytes twice
- two stages are written in the order the ledger holds them
**Traced to:** Scenario: "Same ledger gives the same bytes"
- [ ] done
`

// WP21: the environment agent is gone from this version; the 9.8.4 and base CLIs this replay also drives may launch it,
// so its scripted agent stays, under a name built at run time
const ENV_AGENT = 'temper:temper-' + 'env'

// ---- what is measured ---------------------------------------------------------------------------------------------
const AGENT_MIN: Record<string, number> = {   // minutes per launch, from the measured run's own agent times
  'temper:temper-intent': 1, 'temper:temper-plan': 12, 'temper:temper-plan-review': 5, 'temper:temper-design': 5,
  'temper:temper-acceptance': 8, 'temper:temper-build-task': 25, 'temper:temper-build': 40, 'temper:temper-review': 3,
  'temper:temper-check': 5, [ENV_AGENT]: 5,
}
const m = { questions: 0, question_texts: [] as string[], agents: {} as Record<string, number>, manual_repairs: [] as string[],
  setup_clicks: 0, overrides: 0, loops: [] as string[], cli_ms: 0,
  // WP20: the first question that names the JDK fault, and whether the Intent agent had been launched by then (9.8.5
  // names it in the environment check before any agent; the head names it at the plan gate)
  jdk_named_at: '', jdk_named_before_intent: false }

const t = (w: World, args: string) => w.run(`${TEMPER} ${args}`)
const wtOf = (w: World, n: number): string => {
  const show = t(w, `task show ${n}`).out
  return path.relative(w.dir, /^WORKTREE:\s*(\S+)/m.exec(show)?.[1] ?? '')
}
const count = (type: string): Agent => (w, a) => {
  m.agents[type] = (m.agents[type] ?? 0) + 1
  AGENTS[type]!(w, a)
}

const buildOne = (w: World, n: number): void => {
  const wt = wtOf(w, n)
  const [cls, val] = n === 1 ? ['Shape', 1] : ['Bytes', 2]
  w.write(path.join(wt, `unit/${cls.toLowerCase()}_test.sh`), `#!/usr/bin/env bash\ncd backend && mvn -q -s settings.xml test -Dtest=${cls}Test\n`)
  t(w, `task test ${n} --phase red`)
  w.write(path.join(wt, `backend/src/${cls}.java`), `class ${cls} { int v() { return ${val}; } }\n`)
  t(w, `task test ${n} --phase green`)
}

// WP21: the rows the planner's own first gate failed on. The filtered verify is caught by the row
// `maven filtered verify` as before; the plan gate runs no project command, so no other row names the JDK or the
// database there.
const planGateFailed: string[] = []
const AGENTS: Record<string, Agent> = {
  'temper:temper-intent': w => {
    w.write(`${SPEC}/intent.md`, fs.readFileSync(path.join(ROOT, 'templates/example-intent.md'), 'utf8'))
  },
  // The Plan agent writes the plan, then runs the plan gate itself and fixes what it names (agents/plan.md step 8). After a
  // loop back that names the coverage failure, it writes the line that can pass.
  'temper:temper-plan': (w, a) => {
    if (!w.read(`${SPEC}/intent.md`).includes('Test: bash unit/shape_test.sh'))
      w.write(`${SPEC}/intent.md`, w.read(`${SPEC}/intent.md`).replace('## Scenarios (BDD)\n', scenarios))
    const looped = /Rule violated|Coverage checks|coverage|filtered verify|jacoco/i.test(String(a.prompt))
    w.write(`${SPEC}/plan.md`, planMd)
    w.write(`${SPEC}/tasks.md`, tasksMd(looped ? GOOD_VALIDATE : BAD_VALIDATE))
    t(w, 'state set complexity simple')
    t(w, 'risk')
    const gate = t(w, 'gate plan').out
    if (planGateFailed.length === 0) planGateFailed.push(...[...gate.matchAll(/^\s*\[x\]\s+(.+?)\s+—/gm)].map(x => x[1]!), '')
    if (/\[x\] maven filtered verify/.test(gate)) w.write(`${SPEC}/tasks.md`, tasksMd(GOOD_VALIDATE))
  },
  'temper:temper-plan-review': () => undefined,
  'temper:temper-acceptance': w => { t(w, "acceptance skip --reason 'the replay writes no acceptance tests'") },
  'temper:temper-build-task': (w, a) => {
    const model = /\nModel:\s*(\S+?)\.?\s*$/m.exec(String(a.prompt))?.[1] ?? 'haiku'
    const tasks = (/Tasks?:\s*([\d, ]+)/.exec(String(a.prompt))?.[1] ?? '').split(',').map(x => Number(x.trim())).filter(Boolean)
    tasks.every((n, i) => {
      if (i > 0 && t(w, `task start ${n}`).code !== 0) return false
      buildOne(w, n)
      return t(w, `task gate ${n} --model ${model}`).code === 0
    })
  },
  // Build's fix pass: a review finding is a defect in the code, and the agent mends it; a group check that failed on the
  // environment or on its own command has nothing in the code to mend (as the measured run's fix agents found).
  // WP24: a repair in place (the prompt's line `Repair in place:`) mends the finding and commits nothing; the finding
  // has no proof field (the scripted reviewer writes none), so no failing test is asked for and none is written.
  'temper:temper-build': (w, a) => {
    if (/Repair in place:/.test(String(a.prompt))) {
      w.write('backend/src/Bytes.java', 'class Bytes { int v() { return 2; } /* fixed order */ }\n')
      return
    }
    if (/High|breaks AC-03/.test(String(a.prompt))) {
      // test first: a test for the defect fails, then the fix, then it passes; recorded as this version's brief says
      // (9.8.5: `evidence run`, the CLI runs it; before: `evidence add --exit`, the agent reports it)
      w.write('unit/bytes_order_test.sh', "#!/usr/bin/env bash\ngrep -q 'fixed order' backend/src/Bytes.java\n")
      const record = (phase: string): void => {
        if (NEW) { t(w, `evidence run --stage build --claim 'unit tests' --phase ${phase} -- bash unit/bytes_order_test.sh`); return }
        const rc = w.run('bash unit/bytes_order_test.sh').code
        t(w, `evidence add --stage build --claim 'unit tests' --cmd 'bash unit/bytes_order_test.sh' --exit ${rc} --phase ${phase}`)
      }
      record('red')
      w.write('backend/src/Bytes.java', 'class Bytes { int v() { return 2; } /* fixed order */ }\n')
      record('green')
    }
  },
  'temper:temper-review': (w, a) => {
    const fixed = /fixed order/.test(w.exists('backend/src/Bytes.java') ? w.read('backend/src/Bytes.java') : '')
    // WP24: the narrow recheck of a repair (the brief's section `Re-check:`): one row for each finding it names, and a
    // completion row that names the changed files and the count of ids checked
    if (/Re-check:/.test(String(a.prompt))) {
      const ids = [...new Set([...String(a.prompt).matchAll(/#(\d+)/g)].map(x => x[1]!))]
      for (const id of ids) t(w, `evidence add --stage review --claim 'recheck #${id}: ${fixed ? 'fixed' : 'not fixed'}' --exit ${fixed ? 0 : 1} --cmd recheck`)
      t(w, `evidence add --stage review --claim 'review completed' --exit 0 --cmd recheck --value ${ids.length} --read backend/src/Bytes.java`)
      return
    }
    // the defect is in the code until the fix pass mends it: the reviewer reports it while it is there
    if (!fixed)
      t(w, "evidence add --stage review --severity high --claim 'backend/src/Bytes.java:1 the byte order breaks AC-03, a constraint of the intent'")
    reviewDone(w)
  },
  'temper:temper-check': () => undefined,
  [ENV_AGENT]: () => undefined,   // an older version may still launch it
}

const ENV_FAULT = /allowed range|Connection refused|environment fault|SETUP|needs JDK/

// WP24: a commit whose subject says `repair N at review` and whose tree holds the mended byte order
function repairedInStage(w: World): boolean {
  const subjects = w.run("git log --format='%H %s'").out.split('\n').filter(l => / repair \d+ at review\b/.test(l))
  return subjects.some(l => /fixed order/.test(w.run(`git show ${l.split(' ')[0]}:backend/src/Bytes.java`).out))
}

function main(): void {
  const w = new World('plain', `replay-${label}`)
  const { tools, db, log } = installTools(w)
  // the project
  const files: Record<string, string> = {
    'README.md': '# demo\n', '.gitignore': '__pycache__/\n', 'backend/pom.xml': POM, 'backend/settings.xml': '<settings/>\n',
    'backend/src/test/ItBase.java': 'class ItBase { String port = System.getenv("IT_POSTGRES_PORT"); }\n',
    'scripts/ensure-jdk24.sh': '#!/usr/bin/env bash\n[ "$1" = --export ] && echo "export TOOL_JDK=24"\n',
  }
  for (const [rel, text] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(w.dir, rel)), { recursive: true })
    fs.writeFileSync(path.join(w.dir, rel), text)
  }
  fs.chmodSync(path.join(w.dir, 'scripts/ensure-jdk24.sh'), 0o755)
  w.sh('git add -A && git commit -qm base')
  w.sh(`mkdir -p .claude && cp ${ROOT}/templates/temper.config.default .claude/temper.config`)
  const cfg = path.join(w.dir, '.claude/temper.config')
  // WP19: the commands go at the top of the check block, whatever the template holds there
  fs.writeFileSync(cfg, checkLines(fs.readFileSync(cfg, 'utf8'),
    `  commands:\n    test: ${INTEGRATION}\n    coverage: ${INTEGRATION} && echo 'TOTAL 100 5 95%'\n`))
  w.sh('git add -A && git commit -qm config')
  w.sh(`${TEMPER} init`)
  w.sh(`${TEMPER} state init report --feature 'CI report'`)

  // the person: the recommended option; a repair by hand when a question shows an environment fault the version left open
  const repaired = { jdk: false, db: false }
  // a diligent person (and orchestrator) reads what ran, not only the question: the fake tools' log shows each run and its
  // environment. Seen before each answer and each agent launch; a version that offers its own repair is left to it.
  let looked = 0   // the runs since the person last looked; the same rule on both versions
  const diligence = (q: string, offersSetup: boolean): void => {
    const all = fs.readFileSync(log, 'utf8')
    const ran = all.slice(looked)
    looked = all.length
    const seen = q + (/jdk=21/.test(ran) ? ' allowed range' : '') + (/ verify(?!.*-Dtest)(?!.*-DskipITs).*db=down/.test(ran) ? ' Connection refused' : '')
    if (ENV_FAULT.test(seen) && !offersSetup) {
      if (!repaired.jdk && /allowed range|needs JDK|JDK/.test(seen)) {
        repaired.jdk = true
        w.env.TOOL_JDK = '24'
        m.manual_repairs.push('exported the JDK 24 settings into the shell by hand')
      }
      if (!repaired.db && /Connection refused|Postgres|database/.test(seen)) {
        repaired.db = true
        w.env.IT_POSTGRES_PORT = '5432'
        fs.writeFileSync(path.join(db, 'up'), '')
        m.manual_repairs.push('started the database and set IT_POSTGRES_PORT by hand')
      }
    }
  }
  const person = (ask: Json): string | { label: string; note?: string } => {
    m.questions++
    const q = String(ask.question.question)
    m.question_texts.push(q.slice(0, 160))
    const opts = ask.options as Json[]
    if (m.jdk_named_at === '' && /JDK|allowed range/.test([q, ...opts.map(o => `${o.label} ${o.description ?? ''}`)].join('\n'))) {
      m.jdk_named_at = String(ask.id ?? `question ${m.questions}`)
      m.jdk_named_before_intent = (m.agents['temper:temper-intent'] ?? 0) === 0
    }
    // the `recommended` field when the CLI writes ids (9.8.5); the label's suffix for a plugin folder without them (9.8.4,
    // the base), since the same script drives both through TEMPER_E2E_ROOT
    const fields = opts.some(o => typeof o.id === 'string')
    const rec = opts.find(o => (fields ? o.recommended === true : String(o.label).includes('(Recommended)'))) ?? opts[0]!
    diligence(q, opts.some(o => /setup block|find the setup/.test(String(o.label))))
    if (/setup block|find the setup/.test(String(rec.label))) m.setup_clicks++
    if (/^Override/.test(String(rec.label))) m.overrides++
    if (/^Loop back/.test(String(rec.label))) m.loops.push(String(rec.label))
    if (rec.answer_question) return { label: rec.label, note: GOOD_VALIDATE }
    // WP11: at the approval the person takes the run to the commit, by its id (a plugin folder with no ids, the base,
    // has no such option: its recommended one is taken, as before)
    const arm = opts.find(o => o.id === 'approve-run')
    if (arm) return arm.label
    if (/Every gate passed. The report is above/.test(q)) return 'Not now'
    return rec.label
  }
  const agents = Object.fromEntries(Object.keys(AGENTS).map(k => [k, ((w2: World, a: Json) => { diligence('', false); count(k)(w2, a) }) as Agent]))
  const script: Script = { agents, person, afterFailStops: true, instruction: (_w, text) => /each file the run changed|^Copy what|^When .* records deviations/.test(text) }

  // a database stops when the worker restarts (the measured run): not replayed, to keep both sides equal
  const t0 = Date.now()
  let end: Json = {}
  let error = ''
  try {
    end = orchestrate(w, script, 160)
  } catch (e) {
    error = (e as Error).message.split('\n')[0]!.slice(0, 300)
  }
  m.cli_ms = Date.now() - t0

  // accuracy: what reached the commit
  const committed = w.run('git log --oneline').out.split('\n').filter(Boolean)
  const head = w.run('git show HEAD:' + SPEC + '/tasks.md 2>/dev/null || true').out
  const calls = fs.readFileSync(log, 'utf8').split('\n').filter(l => l.startsWith('mvn '))
  const envRuns = calls.filter(l => /jdk=21/.test(l) || (/ verify/.test(l) && !/-DskipITs/.test(l) && !/-Dtest/.test(l) && /db=down|port= *$/.test(l)))
  const agentMin = Object.entries(m.agents).reduce((s, [k, n]) => s + (AGENT_MIN[k] ?? 5) * n, 0)
  const result = {
    label, version: JSON.parse(fs.readFileSync(path.join(ROOT, '.claude-plugin/plugin.json'), 'utf8')).version,
    ended: error ? `error: ${error}` : String(end.action ?? ''),
    shipped: committed.some(l => /feat|CI report|report/i.test(l) && !/base|config/.test(l)) && !error,
    questions: m.questions, agent_launches: m.agents, agent_launch_total: Object.values(m.agents).reduce((a, b) => a + b, 0),
    agent_minutes_estimate: agentMin, manual_repairs: m.manual_repairs, setup_clicks: m.setup_clicks, overrides: m.overrides,
    loops_recommended: m.loops,
    mvn_calls: calls.length, mvn_calls_failed_on_environment: envRuns.length,
    defect_in_commit: committed.length > 2 && !/fixed order/.test(w.run('git show HEAD:backend/src/Bytes.java 2>/dev/null').out),
    plan_gate_failed_rows: planGateFailed.filter(Boolean),
    bad_validate_line_in_plan_at_end: (w.exists(`${SPEC}/tasks.md`) ? w.read(`${SPEC}/tasks.md`) : head).includes(BAD_VALIDATE),
    cli_seconds: Math.round(m.cli_ms / 1000),
    jdk_named_at: m.jdk_named_at || 'never', jdk_named_before_intent: m.jdk_named_before_intent,
    // WP24 (D58): the High defect is repaired in its stage: a commit of the CLI `fix(...): repair N at review` holds
    // the mended file; and the steps back the run took, by the person's answer or by a rule (the calls `state loop`)
    repaired_in_stage: repairedInStage(w), loops_taken: w.trace.filter(l => /^\s*call temper state loop\b/.test(l)).length,
    questions_asked: m.question_texts,
  }
  console.log(JSON.stringify(result))
  // WP24 (D58): the run of this tree (the label `final`, as scripts/verify.sh runs it) holds the promise of the replay:
  // the High defect repaired in its stage, no loop recommended or taken, Plan launched once. The JSON line stays the
  // last line of the output; a miss is said on stderr and the exit code is 1.
  if (label === 'final') {
    const miss = [
      result.repaired_in_stage ? '' : 'the High defect was not repaired in its stage (no commit `repair N at review` holds the fix)',
      result.loops_recommended.length === 0 ? '' : `loops were recommended: ${result.loops_recommended.join('; ')}`,
      result.loops_taken === 0 ? '' : `the run took ${result.loops_taken} step(s) back (state loop)`,
      (m.agents['temper:temper-plan'] ?? 0) === 1 ? '' : `Plan was launched ${m.agents['temper:temper-plan'] ?? 0} times, not once`,
    ].filter(Boolean)
    for (const x of miss) console.error(`FAIL replay final: ${x}`)
    if (miss.length > 0) process.exitCode = 1
  }
  fs.rmSync(tools, { recursive: true, force: true })
  fs.rmSync(db, { recursive: true, force: true })
  // WP20 (Tests first, item 14): the tree under test names the JDK fault before the Intent agent is launched; another
  // plugin folder (TEMPER_E2E_ROOT, the base of the A/B replay) is only measured
  if (!process.env.TEMPER_E2E_ROOT && !m.jdk_named_before_intent) {
    console.error(`replay: the JDK fault was not named before the Intent agent (first named at: ${m.jdk_named_at || 'no question'})`)
    process.exit(1)
  }
}

main()
