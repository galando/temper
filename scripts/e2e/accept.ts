// The acceptance scenarios of docs/plans/one-go/done.md (WP07, mechanism steps 7 and 8). One function a scenario; each
// starts with withRemote(w) (a bare origin and a fake gh, scripts/e2e/faketools.ts), ends with the shared assert of row
// D33b on its own run (no action the CLI took by itself ran a call only the person may cause) and with worldCheck(w), the
// shared assert of row D105 (scripts/e2e/persons.ts). Every expect message starts with the token of the row it proves, so
// scripts/check_done.py finds it and the first failing line names the promise.
//
// A scenario that is still expected to fail is on scripts/selftest/expected-fail.txt with the package that makes it
// pass. Where a scenario's package comes after WP13 (the run that asks twice), the scripted person allows only the
// questions of the promise and throws at the first other one, so the scenario fails in seconds, not after 400 steps.
// The persons select options by id, never by label. A scripted agent that plants a fault follows `failingScenario` and
// the reviewer of the replay. The CLI calls a scenario names itself are only those the plan names (`plan amend`,
// `plan patch`, `evidence resolve`): this file names none; everything else is read from `next --json`,
// `.temper/view.json`, `.temper/gates.json`, git and the tool logs.
//
//   two-dialogs            D01   a clean run asks plan.approve, then commit.confirm, and no other; no hand back
//   approval-first         D30a  at the approval the branch, the commit count and the project files are as at the start
//   flagged-map            D02   a flagged Context Map is whole on the approval card, 2 dialogs, the review line says so
//   fix-two                D03   a bug run asks rca.approve and commit.confirm; Review starts Check's run; D101 fix/ branch
//   vague-run              D04   5 open rules: 4 dialogs; no Design agent
//   repair-finding         D05   one High finding repaired in the stage, 2 dialogs; D37d the order; D39b, D39e the card
//   repair-worse           D37e  a repair that breaks a passing row is reverted and asked
//   group-fail             D06   a failed group check: one fix agent, one planner, no hand back; D39e the card
//   group-fail-twice       D06   the fix does not pass: one question shows what was tried; D33c one planner launch
//   integrate-fail         D07   a failed integrate reaches its question with no hand back (driver)
//   budget-stop            D08   no third launch for one failure; D38d the budget question shows the count
//   criteria-by-cli        D10   a code or metric criterion is recorded by the CLI: no record pass, no Check agent
//   ask-every-stage        D17   the second option of the approval keeps Build, Review and Check asking once each
//   design-on-ask          D20   a default run launches no Design agent; the approval offers run-design
//   acceptance-wrong-test  D21   a wrong locked test: one triage, one question, one writer launch, then Review
//   stop-keeps-mode        D32c  a stop of an unattended run keeps the mode and says the run goes on by itself
//   revise-narrow          D24   a revision of the plan is the narrow revise agent, not a second planner pass
import path from 'node:path'

import { recordOf, withRemote } from './faketools'
import { orchestrate, orchestrateFix } from './loop'
import { APPROVALS, defaultPerson, idOf, pickId, stagePerson, worldCheck, worldFindings } from './persons'
import { BYTES_STUB, SHAPE_CODE, SHAPE_STUB, SHAPE_TEST, SUITE } from './project'
import { AGENTS, SPEC, buildOne, chained, freshReviewer, launchByHand, script, startProject, t, worktreeOf } from './scenarios'
import type { FreshFinding } from './scenarios'
import { expect, promise } from './slow'
import { TEMPER, World, reviewDone } from './world'
import type { Agent, Json, Person } from './world'

// ---- what a scenario watches ------------------------------------------------------------------------------------------

// Rule 4 of docs/plans/one-go/README.md section 6, the calls only the person may cause (the same pattern as the walk of
// case 44): planning again, a patch of the plan, a skip, an accepted finding, a config write, a push, a pull request and
// the final commit.
export const FORBIDDEN = /state loop \S+ (plan|intent)\b|plan patch|\boverride\b|evidence accept|doctor .*--write|git push|gh pr|spec commit .* -- |git commit/

type Launch = { type: string; prompt: string; at: number }
type Watch = {
  autos: string[]               // every call of an action the CLI took by itself: `auto` in next, `ran` of temper go
  calls: string[]               // every command the world ran, and every call temper go ran by itself
  launches: Launch[]            // every agent launch, with the trace length at its launch
}
const WATCHES = new WeakMap<World, Watch>()

// The calls of an action: its own, its agents' before and after calls, and its steps that are commands.
const callsOf = (n: Json): string[] => [
  ...((n.calls ?? []) as string[]),
  ...((n.agents ?? []) as Json[]).flatMap(a => [...((a.before ?? []) as string[]), ...((a.after ?? []) as string[])]),
  ...((n.steps ?? []) as string[]),
].map(String)

// Called once, right after withRemote(w): it hooks `next`, `run` and the agent launch of this one World.
function watch(w: World): Watch {
  const wt: Watch = { autos: [], calls: [], launches: [] }
  WATCHES.set(w, wt)
  const next = w.next.bind(w)
  w.next = (extra = '') => {
    const n = next(extra)
    if (n.action === 'auto') wt.autos.push(...callsOf(n))
    return n
  }
  const run = w.run.bind(w)
  w.run = (command: string, cwd?: string) => {
    const r = run(command, cwd)
    wt.calls.push(command)
    if (command === `${TEMPER} go` || command.startsWith(`${TEMPER} go `)) {
      try {
        const out = JSON.parse(r.out.trim().split('\n').pop() ?? '') as Json
        for (const c of (out.ran ?? []) as string[]) {
          wt.autos.push(String(c))
          wt.calls.push(String(c))
        }
      } catch {
        // no JSON line: temper go printed an error, which the driver reports
      }
    }
    return r
  }
  const guardAgent = w.guardAgent.bind(w)
  w.guardAgent = a => {
    wt.launches.push({ type: String(a.type), prompt: String(a.prompt ?? ''), at: w.trace.length })
    guardAgent(a)
  }
  return wt
}
const watched = (w: World): Watch => WATCHES.get(w) ?? { autos: [], calls: [], launches: [] }
const launchesOf = (w: World, type: string, test: (p: string) => boolean = () => true): Launch[] =>
  watched(w).launches.filter(l => l.type === type && test(l.prompt))
const ran = (w: World, word: RegExp): number => watched(w).calls.findIndex(c => word.test(c))

// The shared assert of row D33b on this scenario's own run: no action the CLI took by itself ran a call of rule 4.
function ownAutos(w: World): void {
  const bad = watched(w).autos.filter(c => FORBIDDEN.test(c))
  expect(bad.length === 0, `D33b an action the CLI took by itself ran a call only the person may cause: ${bad[0]?.replace(/^\S*\/scripts\/temper /, 'temper ').slice(0, 200) ?? ''}`)
}

// Each question the person met: its id, the ask, the trace length and the card of the view at that moment, and where
// the approval was.
type Seen = { ids: string[]; asks: Json[]; at: number[]; cards: Json[]; approvalAt: number }
function seeing(w: World, person: Person): { person: Person; seen: Seen } {
  const seen: Seen = { ids: [], asks: [], at: [], cards: [], approvalAt: -1 }
  return {
    seen,
    person: (ask, wd) => {
      let card: Json | null = null
      try {
        card = (wd.json('.temper/view.json').card ?? null) as Json | null
      } catch {
        card = null
      }
      seen.ids.push(idOf(ask))
      seen.asks.push(ask)
      seen.at.push(w.trace.length)
      seen.cards.push(card ?? {})
      const pick = person(ask, wd)
      const label = pick === null ? null : typeof pick === 'string' ? pick : pick.label
      const option = ((ask.options ?? []) as Json[]).find(o => o.label === label)
      if (APPROVALS.includes(idOf(ask)) && ['approve', 'arm'].includes(String(option?.move ?? ''))) seen.approvalAt = w.trace.length
      return pick
    },
  }
}
// The questions the person met after the approval.
const afterApproval = (seen: Seen): string[] => seen.ids.slice(seen.ids.lastIndexOf('plan.approve') + 1)
const cardAt = (seen: Seen, id: string): Json | null => {
  const i = seen.ids.lastIndexOf(id)
  return i >= 0 ? seen.cards[i]! : null
}
const shown = (ask: Json, card: Json | null): string =>
  [String(ask.question?.question ?? ''), ...((ask.options ?? []) as Json[]).map(o => `${o.label} ${o.description ?? ''}`), JSON.stringify(card ?? {})].join('\n')
const sectionOf = (card: Json | null, id: string): Json | null =>
  ((card?.sections ?? []) as Json[]).find(s => s.id === id) ?? null

// D39e: every action the CLI took by itself after the approval has its entry in the rule_log of the commit card,
// counted from the trace (plain and mod mode: the driver runs those actions inside temper go).
function ruleLogCovers(w: World, seen: Seen): void {
  if (w.mode === 'driver' || seen.approvalAt < 0) return
  const autos = w.trace.slice(seen.approvalAt).filter(l => l.startsWith('auto:')).length
  if (autos === 0) return
  const log = sectionOf(cardAt(seen, 'commit.confirm'), 'rule_log')
  const entries = Math.max(Number(log?.total ?? 0), Array.isArray(log?.rows) ? log!.rows.length : 0)
  expect(entries >= autos, `D39e the rule_log of the commit card holds ${entries} entries for the ${autos} actions a rule took after the approval`)
}

const runMode = (w: World): string => {
  try {
    return String(w.json('.temper/build-state.json').run_mode ?? '')
  } catch {
    return ''
  }
}
const ended = (w: World): boolean => !w.exists('.temper/build-state.json')
const headTree = (w: World): string => w.sh("git rev-parse 'HEAD^{tree}'").trim()
const suiteRuns = (w: World): number => w.finalCounts().suite_runs

// ---- the scripted agents these scenarios plant faults with -------------------------------------------------------------

// The planner of every scenario here: the plan of full-run, with what a scenario changes in tasks.md, plan.md or the
// intent, and the tier and the risk it sets.
export function planner(opts: { tasks?: (s: string) => string; plan?: (s: string) => string; complexity?: string; riskH?: boolean } = {}): Agent {
  return (wd, a) => {
    AGENTS['temper:temper-plan']!(wd, a)
    if (opts.tasks) wd.write(`${SPEC}/tasks.md`, opts.tasks(wd.read(`${SPEC}/tasks.md`)))
    if (opts.plan) wd.write(`${SPEC}/plan.md`, opts.plan(wd.read(`${SPEC}/plan.md`)))
    if (opts.complexity) t(wd, `state set complexity ${opts.complexity}`)
    if (opts.riskH) t(wd, "risk --raise H --reason 'the scenario wants a plan of risk H'")
  }
}

// A group check that fails after every task of the group passed: Validate also wants a line no task writes.
const G1_VALIDATE = 'python3 -m unittest unit.test_ci_shape'
export const groupCheck = (tasks: string): string =>
  tasks.replace(`**Validate:** \`${G1_VALIDATE}\``, `**Validate:** \`${G1_VALIDATE} && grep -q VERSION src/ci_shape.py\``)
export const integrationCheck = (tasks: string): string =>
  tasks.replace(`**Integration:** \`${SUITE}\``, `**Integration:** \`${SUITE} && grep -q VERSION src/ci_bytes.py\``)

// The group fix agent (agents/build.md, "A group fix"): it works in the worktree its prompt names.
export function groupFixer(write: (text: string) => string): Agent {
  return (wd, a) => {
    const prompt = String(a.prompt ?? '')
    const m = /worktree (\S+) \(the merged/.exec(prompt)
    if (m === null) return
    const wt = path.isAbsolute(m[1]!) ? path.relative(wd.dir, m[1]!) : m[1]!
    const file = path.join(wt, 'src/ci_shape.py')
    wd.write(file, write(wd.exists(file) ? wd.read(file) : SHAPE_CODE))
  }
}

// A builder whose code of task 1 keeps the caller's list: the shape test passes, and a reviewer can name the defect.
export const SHAPE_DEFECT = 'def stage_object(stage, verdict, requirements):\n    return {"stage": stage, "verdict": verdict, "requirements": requirements}\n'
export const buildWithDefect: Agent = chained((wd, n) => {
  if (n !== 1) return buildOne(wd, n)
  const wt = path.relative(wd.dir, worktreeOf(t(wd, 'task show 1').out))
  wd.write(path.join(wt, 'unit/test_ci_shape.py'), SHAPE_TEST)
  wd.write(path.join(wt, 'src/ci_shape.py'), SHAPE_STUB)
  t(wd, 'task test 1 --phase red')
  wd.write(path.join(wt, 'src/ci_shape.py'), SHAPE_DEFECT)
  t(wd, 'task test 1 --phase green')
})

// The reviewer of the repair scenarios: the first full Review records one High finding with its detail, its fix and its
// proof field (the flags of WP24; where the CLI does not take them yet, the finding alone) and its completion; a recheck
// (the `Re-check:` section of agents/review.md) confirms the finding fixed.
const FINDING = "src/ci_shape.py:2 the stage object keeps the caller's list, so a later change to that list changes the report"
export function repairReviewer(state: { full: number; rechecks: number; reviewedTree: string }): Agent {
  return (wd, a) => {
    const prompt = String(a.prompt ?? '')
    if (/Re-check:/.test(prompt)) {
      state.rechecks++
      for (const id of new Set([...prompt.matchAll(/#(\d+)/g)].map(m => m[1]!)))
        t(wd, `evidence add --stage review --claim 'recheck #${id}: fixed' --exit 0 --cmd 'recheck'`)
      t(wd, "evidence add --stage review --claim 'review completed' --exit 0 --cmd 'recheck' --read src/ci_shape.py")
      return
    }
    state.full++
    if (state.full === 1) {
      state.reviewedTree = headTree(wd)
      const whole = `--detail 'stage_object returns the requirements list it was given' --fix 'return list(requirements)' --proof none`
      if (t(wd, `evidence add --stage review --severity high --label PROVEN --claim '${FINDING.replace(/'/g, "'\\''")}' ${whole}`).code !== 0)
        t(wd, `evidence add --stage review --severity high --label PROVEN --claim '${FINDING.replace(/'/g, "'\\''")}'`)
    }
    reviewDone(wd)
  }
}

// The fixer of a repair in the stage (a fresh temper:temper-build with the line `Repair in place:`): it mends the finding;
// `worse` also breaks the byte order module, a row that passed.
export function repairFixer(state: { fixes: number; suiteBefore: number }, worse = false): Agent {
  return (wd, a) => {
    if (!/Repair in place/.test(String(a.prompt ?? ''))) return
    state.fixes++
    state.suiteBefore = suiteRuns(wd)
    wd.write('src/ci_shape.py', SHAPE_CODE)
    if (worse) wd.write('src/ci_bytes.py', BYTES_STUB)
  }
}

// ---- the scenarios -------------------------------------------------------------------------------------------------------

// D01: a clean feature run with a clean Context Map asks 2 dialogs, the approval before any code and the commit.
export const twoDialogs = (w: World): void => {
  withRemote(w)
  watch(w)
  startProject(w)
  const { person, seen } = seeing(w, defaultPerson(['plan.approve', 'commit.confirm']))
  promise('D01', () => orchestrate(w, script({ person })))
  expect(seen.ids.join(',') === 'plan.approve,commit.confirm', `D01 the questions asked are plan.approve, then commit.confirm, and no other (${seen.ids.join(', ')})`)
  expect(w.counts.dialogs === 2, `D01 the run asks 2 dialogs (${w.counts.dialogs})`)
  expect(w.counts.handbacks === 0, `D01 the run is never handed back (${w.counts.handbacks} hand backs)`)
  expect(ended(w), 'D01 the run reaches its commit and ends')
  ownAutos(w)
  worldCheck(w)
}

// D30a, rule 1: before the approval a run writes only its spec folder and Temper's own run files. The run goes to the
// approval and its answer; the shared assert's rule 1 half is then read for this row, and fails the scenario.
export const approvalFirst = (w: World): void => {
  withRemote(w)
  watch(w)
  startProject(w)
  const rec = recordOf(w)!
  promise('D30a', () => orchestrate(w, script({ person: defaultPerson(), stopAt: () => rec.approvals > 0 })))
  expect(rec.approval !== null, `D30a the run reached the approval (asked ${rec.picks.map(p => p.question).join(', ')})`)
  const found = worldFindings(rec).filter(l => l.startsWith('D105 at the approval')).map(l => l.replace(/^D105 at the approval /, ''))
  expect(found.length === 0, `D30a at the approval ${found.join('; ')}`)
  ownAutos(w)
  worldCheck(w)
}

// D02: a flagged Context Map is shown whole on the approval card and still costs 2 dialogs; plan.md records that the
// answer was given at the approval and how many lines were shown.
export const GAP = 'no rate limit policy for the CI report was found in the code, the docs or the ticket of today'
export const IGNORE = 'docs/legacy-report/ (14 files) - the old HTML report that the CLI no longer builds'
export const flaggedMap = (w: World): void => {
  withRemote(w)
  watch(w)
  startProject(w)
  const agents = { ...AGENTS, 'temper:temper-plan': planner({ plan: p => p.replace('- reviewed: pending', `- ignore: ${IGNORE}\n- gap: ${GAP}\n- reviewed: pending`) }) }
  let planAtCommit = ''
  const base = defaultPerson(['plan.approve', 'commit.confirm'])
  const { person, seen } = seeing(w, (ask, wd) => {
    if (idOf(ask) === 'commit.confirm') planAtCommit = wd.exists(`${SPEC}/plan.md`) ? wd.read(`${SPEC}/plan.md`) : ''
    return base(ask, wd)
  })
  promise('D02', () => orchestrate(w, script({ agents, person })))
  expect(seen.ids.join(',') === 'plan.approve,commit.confirm' && w.counts.dialogs === 2,
    `D02 a flagged map still costs 2 dialogs, plan.approve and commit.confirm (${seen.ids.join(', ')}; ${w.counts.dialogs} dialogs)`)
  const context = JSON.stringify(sectionOf(cardAt(seen, 'plan.approve'), 'context') ?? '')
  expect(context.includes(GAP) && context.includes(IGNORE),
    `D02 the context section of the approval card holds each flagged line whole (${context.slice(0, 200)})`)
  expect(/^- reviewed: human/m.test(planAtCommit) && /at the approval, 2 flagged lines shown/.test(planAtCommit),
    `D02 the review line of plan.md records the answer given at the approval and the 2 lines shown (${(/^- (reviewed|answer):.*$/m.exec(planAtCommit) ?? [''])[0]})`)
  ownAutos(w)
  worldCheck(w)
}

// D03: a clean bug run asks 2 dialogs, the root cause with its fix and the commit; Review's launch starts Check's run.
// D101 (driver): a run started on main ends with its commit on a fix/ branch.
export const fixTwo = (w: World): void => {
  withRemote(w)
  watch(w)
  startProject(w, '', wd => {
    wd.write('src/ci_shape.py', 'def stage_object(stage, verdict, requirements):\n    return {"stage": stage}\n')
    wd.sh('git add -A && git commit -qm "a shape with a bug"')
  })
  t(w, 'state clear')
  if (w.mode !== 'driver') w.sh(`${TEMPER} state init bug --command fix`)
  const bug = '.temper/specs/bug'
  const agents: Record<string, Agent> = {
    'temper:temper-rca': wd => wd.write(`${bug}/rca.md`, '# RCA: the shape drops the verdict\n\n## Root cause\n\n`stage_object` returns only the stage.\n\n## Fix\n\nReturn verdict and requirements.\n'),
    'temper:temper-fix': wd => {
      wd.write('unit/test_ci_shape.py', SHAPE_TEST)
      t(wd, `evidence run --stage build --phase red --claim 'regression test: the shape keeps its verdict' -- python3 -m unittest unit.test_ci_shape`)
      wd.write('src/ci_shape.py', SHAPE_CODE)
      t(wd, `evidence run --stage build --phase green --claim 'regression test: the shape keeps its verdict' -- python3 -m unittest unit.test_ci_shape`)
    },
    'temper:temper-review': wd => reviewDone(wd),
    'temper:temper-check': wd => {
      t(wd, "evidence add --stage check --claim 'tests' --exit 0 --cmd 'python3 -m unittest discover -s unit -t .'")
      t(wd, "evidence add --stage check --claim 'coverage' --value 90 --exit 0 --cmd 'coverage report'")
    },
    'temper:temper-build': () => undefined,
  }
  const { person, seen } = seeing(w, defaultPerson(['rca.approve', 'commit.confirm']))
  const fixScript = script({
    agents,
    person,
    instruction: (wd, text) => {
      if (text.startsWith('Append one entry for this fix')) {
        wd.write('.temper/lessons.md', '# Lessons\n\n- the shape must keep its verdict: a regression test names it\n')
        return true
      }
      return /each file the run changed|^Copy what|^When .* records deviations/.test(text)
    },
  })
  promise('D03', () => {
    if (w.mode === 'driver') orchestrateFix(w, fixScript, 'the shape drops the verdict', 'bug')
    else {
      launchByHand(w, agents, 'temper:temper-rca')
      orchestrate(w, fixScript)
    }
  })
  expect(seen.ids.join(',') === 'rca.approve,commit.confirm' && w.counts.dialogs === 2,
    `D03 the bug run asks rca.approve, then commit.confirm, and no other (${seen.ids.join(', ')}; ${w.counts.dialogs} dialogs)`)
  const review = launchesOf(w, 'temper:temper-review')[0]
  const ahead = w.trace.findIndex(l => /^\s*call .*\bcheck ahead\b/.test(l))
  expect(review !== undefined && ahead >= 0 && ahead <= review.at, `D03 the Review launch starts the run of Check (check ahead at ${ahead}, Review launched at ${review?.at ?? 'never'})`)
  const branch = w.sh('git branch --show-current').trim()
  const own = Number(w.run('git rev-list --count main..HEAD').out.trim() || '0')
  expect(branch.startsWith('fix/') && own > 0 && ended(w), `D101 the run ends with its commit on a fix/ branch (on ${branch}, ${own} commits beyond main)`)
  ownAutos(w)
  worldCheck(w)
}

// D04: a vague run asks 2 dialogs plus one for every four rules the request left open; a design concern is one of those
// questions, never a stage. The scripted Intent agent leaves 5 rules open, the last a design concern: 4 dialogs.
export const OPEN_RULES = [
  '- Blocking: Who may run report --ci, anyone with the CLI or only a release engineer? choices: anyone with the CLI | only a release engineer.',
  '- Blocking: When does a stage with no verdict yet appear in the report? choices: never | as pending.',
  "- Blocking: How much of a failed row's detail goes into the report? choices: the whole detail | the first 200 characters.",
  '- Blocking: Which stages are exempt from the report? choices: none | the skipped ones.',
  '- Blocking: Does the report read gates.json itself or through the module the table uses? choices: through the module the table uses | gates.json itself.',
]
export const vagueRun = (w: World): void => {
  withRemote(w)
  watch(w)
  startProject(w)
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-intent': (wd, a) => {
      AGENTS['temper:temper-intent']!(wd, a)
      const intent = wd.read(`${SPEC}/intent.md`)
        .replace('### Open Questions\n', `### Open Questions\n\n${OPEN_RULES.join('\n')}\n`)
        .replace(/^- (Who|When|How much|Exempt|States): .*$/gm, (_m, k: string) => `- ${k}: asked (an open question below)`)
      wd.write(`${SPEC}/intent.md`, intent)
    },
    'temper:temper-plan': planner({ complexity: 'complex' }),
    'temper:temper-design': () => { throw new Error('D04 a vague run launched temper:temper-design: a design concern is a question, never a stage') },
  }
  let blocking = 0
  const base = defaultPerson(['plan.approve', 'commit.confirm'])
  const { person, seen } = seeing(w, (ask, wd) => {
    if (ask.kind === 'blocking') {
      blocking++
      return defaultPerson()(ask, wd)
    }
    return base(ask, wd)
  })
  promise('D04', () => orchestrate(w, script({ agents, person })))
  expect(blocking === 5, `D04 the 5 open rules are asked, each once (${blocking})`)
  expect(w.counts.dialogs === 4, `D04 5 open rules cost 4 dialogs: two of open rules, the approval and the commit (${w.counts.dialogs}: ${seen.ids.join(', ')})`)
  expect(launchesOf(w, 'temper:temper-design').length === 0, 'D04 no Design agent is launched')
  expect(ended(w), 'D04 the run reaches its commit and ends')
  ownAutos(w)
  worldCheck(w)
}

// D05, D37d, D39b, D39e: one High finding of Review is repaired in the stage with 0 dialogs. One full Review, then one
// fix agent and one narrow recheck; the repair commit, the checks on its tree, the recheck and the resolve in that order;
// the commit card lists the repair, its files and the recheck's answer.
export const repairFinding = (w: World): void => {
  withRemote(w)
  watch(w)
  startProject(w)
  const review = { full: 0, rechecks: 0, reviewedTree: '' }
  const fix = { fixes: 0, suiteBefore: -1 }
  let atRecheck: { subject: string; suite: number; build: string } | null = null
  const reviewer = repairReviewer(review)
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-build-task': buildWithDefect,
    'temper:temper-review': (wd, a) => {
      if (/Re-check:/.test(String(a.prompt ?? ''))) {
        let build = ''
        try {
          build = String(wd.json('.temper/gates.json').build?.verdict ?? '')
        } catch {
          build = ''
        }
        atRecheck = { subject: wd.sh('git log -1 --format=%s').trim(), suite: suiteRuns(wd), build }
      }
      reviewer(wd, a)
    },
    'temper:temper-build': repairFixer(fix),
  }
  let ledgerAtCommit = ''
  const base = defaultPerson(['plan.approve', 'commit.confirm'])
  const { person, seen } = seeing(w, (ask, wd) => {
    if (idOf(ask) === 'commit.confirm') ledgerAtCommit = wd.exists('.temper/evidence/review.json') ? wd.read('.temper/evidence/review.json') : ''
    return base(ask, wd)
  })
  promise('D05', () => orchestrate(w, script({ agents, person })))
  expect(seen.ids.join(',') === 'plan.approve,commit.confirm' && w.counts.dialogs === 2,
    `D05 a repaired finding costs no dialog: the run asks plan.approve and commit.confirm (${seen.ids.join(', ')}; ${w.counts.dialogs} dialogs)`)
  expect(review.full === 1 && fix.fixes === 1 && review.rechecks === 1,
    `D05 one full Review, one fix agent and one narrow recheck (${review.full} full, ${fix.fixes} fix, ${review.rechecks} recheck)`)
  const commitAt = ran(w, /\brepair commit\b/)
  const recheck = launchesOf(w, 'temper:temper-review', p => /Re-check:/.test(p))[0]
  const resolveAt = w.trace.findIndex((l, i) => recheck !== undefined && i >= recheck.at && /^\s*call .*\b(repair close|evidence resolve)\b/.test(l))
  const r = atRecheck as { subject: string; suite: number; build: string } | null
  expect(commitAt >= 0 && r !== null && /repair \d+ at review/.test(r.subject) && r.suite > fix.suiteBefore && r.build === 'PASS' && resolveAt >= 0,
    `D37d the order is repair commit, integrate and gate build on its tree, the recheck, then the resolve (commit ${commitAt >= 0}; at the recheck: ${JSON.stringify(r)}, suite runs before ${fix.suiteBefore}; resolve at ${resolveAt})`)
  const sha = w.sh("git log --all --format='%h %s'").split('\n').find(l => /repair \d+ at review/.test(l))?.split(' ')[0] ?? ''
  const finding = ledgerAtCommit.split('\n').find(l => l.includes('the stage object keeps')) ?? ''
  expect(sha !== '' && (ledgerAtCommit.includes(sha) || finding.includes(sha)), `D37d the finding is resolved by the repair commit (${sha || 'no repair commit'})`)
  const log = JSON.stringify(sectionOf(cardAt(seen, 'commit.confirm'), 'rule_log') ?? '')
  expect(/repair/i.test(log) && log.includes('src/ci_shape.py') && /fixed/i.test(log),
    `D39b the commit card lists the repair, its files and the recheck's answer (${log.slice(0, 200)})`)
  ruleLogCovers(w, seen)
  ownAutos(w)
  worldCheck(w)
}

// D37e: a repair that breaks a row that passed is reverted, the tree is the reviewed tree again, and one question names
// what broke.
export const repairWorse = (w: World): void => {
  withRemote(w)
  watch(w)
  startProject(w)
  const review = { full: 0, rechecks: 0, reviewedTree: '' }
  const fix = { fixes: 0, suiteBefore: -1 }
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-build-task': buildWithDefect,
    'temper:temper-review': repairReviewer(review),
    'temper:temper-build': repairFixer(fix, true),
  }
  let stopText = ''
  let tree = ''
  let dirty = ''
  const base = defaultPerson(['plan.approve', 'repair.stop'])
  const { person, seen } = seeing(w, (ask, wd) => {
    if (idOf(ask) === 'repair.stop') {
      stopText = shown(ask, (wd.json('.temper/view.json').card ?? null) as Json | null)
      tree = headTree(wd)
      dirty = wd.run("git status --porcelain --untracked-files=no -- . ':!.temper'").out.trim()
      return null
    }
    return base(ask, wd)
  })
  promise('D37e', () => orchestrate(w, script({ agents, person })))
  expect(fix.fixes === 1 && seen.ids.join(',') === 'plan.approve,repair.stop',
    `D37e after one repair the run asks one question, repair.stop (${seen.ids.join(', ')}; ${fix.fixes} repairs)`)
  expect(tree !== '' && tree === review.reviewedTree && dirty === '', `D37e the repair is reverted: the tree is the reviewed tree and nothing is left changed (${dirty.split('\n')[0] ?? ''})`)
  expect(/ci_bytes|BytesTest/.test(stopText), `D37e the question names what broke, the byte order test (${stopText.slice(0, 200)})`)
  ownAutos(w)
  worldCheck(w)
}

// D06, D39e: a failed group check hands nothing back; the fix agent is launched once and the planner once in the run.
export const groupFail = (w: World): void => {
  withRemote(w)
  watch(w)
  startProject(w)
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-plan': planner({ tasks: groupCheck }),
    'temper:temper-build': groupFixer(text => `${text.replace(/\n*$/, '\n')}VERSION = 1\n`),
  }
  // the person takes the recommended option of every question: which questions come before the approval is row D01's
  // promise, not this one's
  const { person, seen } = seeing(w, defaultPerson())
  promise('D06', () => orchestrate(w, script({ agents, person })))
  expect(w.counts.handbacks === 0, `D06 a failed group check hands nothing back (${w.counts.handbacks} hand backs)`)
  expect(launchesOf(w, 'temper:temper-build').length === 1, `D06 the fix agent is launched once (${launchesOf(w, 'temper:temper-build').length})`)
  expect(launchesOf(w, 'temper:temper-plan').length === 1, `D06 temper:temper-plan is launched once in the run (${launchesOf(w, 'temper:temper-plan').length})`)
  // no question of the Build stage after the approval (a group, build or task question, build.fail among them): the
  // failed check is fixed by rule (group.pass after a passed group, and the questions of the later stages, are other
  // rows' promises)
  const buildAsks = afterApproval(seen).filter(i => /^(group|build|task)\./.test(i) && i !== 'group.pass')
  expect(buildAsks.length === 0 && ended(w), `D06 the fixed group goes on to the commit with no question (${buildAsks.join(', ') || 'not ended'})`)
  ruleLogCovers(w, seen)
  ownAutos(w)
  worldCheck(w)
}

// D06, D33c: the fix of a failed group check does not pass: one question shows what was tried; the planner is launched
// once in the whole run.
export const groupFailTwice = (w: World): void => {
  withRemote(w)
  watch(w)
  startProject(w)
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-plan': planner({ tasks: groupCheck }),
    'temper:temper-build': groupFixer(text => `${text.replace(/\n*$/, '\n')}# the fix agent tried\n`),
  }
  let stop = ''
  const base = defaultPerson()
  const { person, seen } = seeing(w, (ask, wd) => {
    if (seen.approvalAt >= 0) {
      stop = shown(ask, (wd.json('.temper/view.json').card ?? null) as Json | null)
      return null
    }
    return base(ask, wd)
  })
  promise('D06', () => orchestrate(w, script({ agents, person })))
  expect(w.counts.handbacks === 0, `D06 a failed group check hands nothing back (${w.counts.handbacks} hand backs)`)
  expect(launchesOf(w, 'temper:temper-build').length === 1, `D06 the fix agent is launched once (${launchesOf(w, 'temper:temper-build').length})`)
  expect(seen.approvalAt >= 0 && afterApproval(seen).length === 1 && /tried|fix of its merged work did not/i.test(stop),
    `D06 when the fix does not pass, one question shows what was tried (${seen.ids.join(', ')}: ${stop.slice(0, 200)})`)
  expect(launchesOf(w, 'temper:temper-plan').length === 1, `D33c temper:temper-plan is launched once in the whole run (${launchesOf(w, 'temper:temper-plan').length})`)
  ownAutos(w)
  worldCheck(w)
}

// D07 (driver): a failed integrate is a verdict for every carrier: the run is carried to its question with 0 hand backs.
const integrationFailed = (w: World): boolean => {
  try {
    if (String(w.json('.temper/groups.json').integration?.verdict ?? '') === 'FAIL') return true
  } catch {
    // no groups file
  }
  try {
    const rows = (w.json('.temper/gates.json').build?.requirements ?? []) as Json[]
    return rows.some(r => r.name === 'integration' && r.pass === false)
  } catch {
    return false
  }
}
export const integrateFail = (w: World): void => {
  withRemote(w)
  watch(w)
  startProject(w)
  // the Build fix pass after the failed integrate: it adds the line the Integration command wants
  let fixedAfterFail = false
  const fixer: Agent = wd => {
    expect(wd.counts.handbacks === 0, `D07 the failed integrate was handed back to the model loop (${wd.counts.handbacks} hand backs) before its fix pass`)
    if (integrationFailed(wd)) fixedAfterFail = true
    wd.write('src/ci_bytes.py', `${wd.read('src/ci_bytes.py').replace(/\n*$/, '\n')}VERSION = 1\n`)
  }
  const agents: Record<string, Agent> = { ...AGENTS, 'temper:temper-plan': planner({ tasks: integrationCheck }), 'temper:temper-build': fixer }
  let reached = ''
  const base = defaultPerson()
  const atQuestion = (wd: World): boolean =>
    fixedAfterFail || (ran(wd, /\/scripts\/temper integrate\b/) >= 0 && integrationFailed(wd))
  const person: Person = (ask, wd) => {
    if (atQuestion(wd)) {
      reached = idOf(ask)
      return null
    }
    return base(ask, wd)
  }
  // the scenario ends at the question itself (WP09): in driver mode a person who answers nothing is a hand back of the
  // driver ("nobody answered the question"), which the count would read as the failed integrate's
  const stopAt = (wd: World, n: Json): boolean => {
    if (n.action !== 'ask' || !atQuestion(wd)) return false
    reached = idOf(n.ask as Json)
    return true
  }
  // a failed after call stops its action and the loop asks next, as commands/temper.md says: a hand back is counted
  promise('D07', () => orchestrate(w, script({ agents, person, stopAt, afterFailStops: true })))
  expect(ran(w, /\/scripts\/temper integrate\b/) >= 0 && (fixedAfterFail || integrationFailed(w)), 'D07 integrate ran and recorded FAIL')
  expect(reached !== '' && w.counts.handbacks === 0, `D07 a failed integrate is carried to its question with 0 hand backs (${w.counts.handbacks} hand backs; question ${reached || 'none'})`)
  ownAutos(w)
  worldCheck(w)
}

// D08, D38d: repeats are bounded: 2 for one failure, then one question that shows the count; no third launch.
export const budgetStop = (w: World): void => {
  withRemote(w)
  watch(w)
  startProject(w)
  const repeats = (): number =>
    launchesOf(w, 'temper:temper-build').length + Math.max(0, launchesOf(w, 'temper:temper-build-task').length - 2) + Math.max(0, launchesOf(w, 'temper:temper-plan').length - 1)
  const counted = (type: string, a: Agent): Agent => (wd, x) => {
    expect(repeats() <= 2, `D08 a third launch for the same failure: ${type} after ${repeats() - 1} repeats of group G1's check`)
    a(wd, x)
  }
  const raw: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-plan': planner({ tasks: groupCheck }),
    'temper:temper-build': groupFixer(text => `${text.replace(/\n*$/, '\n')}# the fix agent tried\n`),
  }
  const agents = Object.fromEntries(Object.entries(raw).map(([k, a]) => [k, counted(k, a)]))
  let budget = ''
  const base = defaultPerson()
  const { person, seen } = seeing(w, (ask, wd) => {
    if (idOf(ask) === 'run.budget') budget = shown(ask, (wd.json('.temper/view.json').card ?? null) as Json | null)
    return base(ask, wd)
  })
  promise('D08', () => orchestrate(w, script({ agents, person })))
  expect(repeats() <= 2, `D08 at most 2 repeats for the one failure (${repeats()})`)
  expect(seen.ids.filter(i => i === 'run.budget').length === 1 && /\b2\b/.test(budget),
    `D38d at the limit one question, run.budget, shows the count (${seen.ids.join(', ')}: ${budget.slice(0, 200)})`)
  ownAutos(w)
  worldCheck(w)
}

// D10: a criterion validated by `code` or `metric` is recorded by the CLI: no record pass and no Check agent. The intent
// of every scenario has three criteria; AC-02 becomes a required criterion of type `code` (the count of criteria stays,
// so the plan's scenarios still cover them).
export const CODE_CRITERION = `- [ ] AC-02 [required]: The shape module has one function that builds a stage object
  Why: one builder keeps the shape in one place.
  Validate: code — \`grep -q "def stage_object" src/ci_shape.py\`
`
export const criteriaByCli = (w: World): void => {
  withRemote(w)
  watch(w)
  startProject(w)
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-intent': (wd, a) => {
      AGENTS['temper:temper-intent']!(wd, a)
      wd.write(`${SPEC}/intent.md`, wd.read(`${SPEC}/intent.md`).replace(/^- \[ \] AC-02 [\s\S]*?(?=^- \[ \] AC-03 )/m, CODE_CRITERION))
    },
    'temper:temper-build': (_wd, a) => { throw new Error(`D10 a record pass was launched for the code criterion: ${String(a.prompt ?? '').split('\n').find(l => /Record/i.test(l))?.slice(0, 160) ?? 'temper:temper-build'}`) },
    'temper:temper-check': () => { throw new Error('D10 a Check agent was launched for the code criterion') },
  }
  let ledger = ''
  const base = defaultPerson()   // the questions asked are not row D10's promise
  const { person } = seeing(w, (ask, wd) => {
    if (idOf(ask) === 'commit.confirm')
      ledger = ['build', 'check'].map(s => (wd.exists(`.temper/evidence/${s}.json`) ? wd.read(`.temper/evidence/${s}.json`) : '[]')).join('\n')
    return base(ask, wd)
  })
  promise('D10', () => orchestrate(w, script({ agents, person })))
  const record = watched(w).launches.filter(l => /Record (evidence )?only/i.test(l.prompt))
  expect(record.length === 0, `D10 no record pass is launched (${record.map(l => l.type).join(', ')})`)
  expect(launchesOf(w, 'temper:temper-check').length === 0, 'D10 no Check agent is launched')
  const rows = ledger.split('\n').flatMap(text => {
    try {
      return JSON.parse(text) as Json[]
    } catch {
      return []
    }
  })
  const byCli = rows.some(r => r.criterion === 'AC-02' && r.executed_by === 'cli' && (r.exit_code ?? r.exit) === 0)
  expect(byCli, `D10 the CLI recorded the code criterion AC-02 with exit 0 (${JSON.stringify(rows.filter(r => r.criterion === 'AC-02')).slice(0, 200)})`)
  ownAutos(w)
  worldCheck(w)
}

// D17: the second option of the approval, Ask me at every stage, keeps every gate's own question: Build, Review and Check
// each ask once.
export const askEveryStage = (w: World): void => {
  withRemote(w)
  watch(w)
  startProject(w)
  const rec = recordOf(w)!
  const { person, seen } = seeing(w, stagePerson)
  orchestrate(w, script({ person }))
  expect(rec.picks.some(p => APPROVALS.includes(p.question) && p.option === 'ask-every-stage'), `D17 the approval offered ask-every-stage and the person took it (${rec.picks.map(p => `${p.question}:${p.option}`).join(', ')})`)
  const count = (stage: string): number => seen.ids.filter(i => i.startsWith(`${stage}.`)).length
  expect(count('build') === 1 && count('review') === 1 && count('check') === 1,
    `D17 Build, Review and Check each ask once (build ${count('build')}, review ${count('review')}, check ${count('check')}: ${seen.ids.join(', ')})`)
  expect(ended(w), 'D17 the run reaches its commit and ends')
  ownAutos(w)
  worldCheck(w)
}

// D20: Design runs only when asked: a default run of a medium plan at risk H launches no Design agent; the approval
// offers it.
export const designOnAsk = (w: World): void => {
  withRemote(w)
  watch(w)
  startProject(w)
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-plan': planner({ complexity: 'medium', riskH: true }),
    'temper:temper-design': () => { throw new Error('D20 a default run launched temper:temper-design') },
  }
  let offered: string[] | null = null
  const base = defaultPerson()
  const person: Person = (ask, wd) => {
    if (APPROVALS.includes(idOf(ask)) && offered === null) {
      const ids = (o: Json): string[] => [String(o.id ?? ''), ...((o.more?.options ?? []) as Json[]).flatMap(ids)]
      offered = [...((ask.options ?? []) as Json[]).flatMap(ids), ...((ask.more?.options ?? []) as Json[]).flatMap(ids)]
      expect(offered.includes('run-design'), `D20 the approval offers run-design (${offered.join(' | ')})`)
    }
    return base(ask, wd)
  }
  promise('D20', () => orchestrate(w, script({ agents, person })))
  expect(offered !== null, 'D20 the run reached the approval')
  expect(launchesOf(w, 'temper:temper-design').length === 0 && ended(w), 'D20 the run went to its end with no Design agent')
  ownAutos(w)
  worldCheck(w)
}

// D21: the locked acceptance tests run when Build ends, inside integrate. A failing one gets the triage first, no fix
// agent changes code for a test the triage calls wrong, and correcting the test is one question.
export const ACC = `${SPEC}/acceptance`
export const ACC_CMD = `python3 -m unittest discover -s ${ACC} -t ${ACC}`
export const accTest = (key: string): string => `import unittest

from src.ci_shape import stage_object


class AcceptanceTest(unittest.TestCase):
    def test_ac01_each_stage_is_one_object(self):
        self.assertEqual(sorted(stage_object('build', 'PASS', [])), ['requirements', '${key}', 'verdict'])
`
export const acceptanceWrongTest = (w: World): void => {
  withRemote(w)
  watch(w)
  startProject(w)
  const acc = { writes: 0, triages: 0, corrections: 0 }
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-acceptance': (wd, a) => {
      const prompt = String(a.prompt ?? '')
      if (/^Triage:/m.test(prompt)) {
        acc.triages++
        t(wd, "acceptance triage --reason 'test: the test wants the field state; the intent says stage'")
        return
      }
      if (/^Correction:/m.test(prompt)) {
        acc.corrections++
        wd.write(`${ACC}/test_ac01.py`, accTest('stage'))
        const lock = /^Lock command:\s*(.+)$/m.exec(prompt)?.[1]?.trim() || ACC_CMD
        t(wd, `acceptance lock --cmd '${lock.replace(/'/g, "'\\''")}'`)
        return
      }
      acc.writes++
      wd.write(`${ACC}/test_ac01.py`, accTest('state'))   // wrong: the intent says `stage`
      t(wd, `acceptance lock --cmd '${ACC_CMD}'`)
    },
    'temper:temper-build': () => { throw new Error('D21 a fix agent was launched for a test the triage calls wrong') },
  }
  const asked: string[] = []
  const base = defaultPerson()
  const { person, seen } = seeing(w, (ask, wd) => {
    const opts = (ask.options ?? []) as Json[]
    if (opts.some(o => o.id === 'correct-test')) {
      asked.push(idOf(ask))
      expect(opts.find(o => o.recommended === true)?.id === 'correct-test', `D21 the triage called the test wrong, so correct-test is recommended at ${idOf(ask)}`)
      return base(ask, wd)
    }
    if (!['plan.approve', 'commit.confirm'].includes(idOf(ask))) throw new Error(`D21 unexpected question ${idOf(ask)}`)
    return base(ask, wd)
  })
  promise('D21', () => orchestrate(w, script({ agents, person })))
  const triage = launchesOf(w, 'temper:temper-acceptance', p => /^Triage:/m.test(p))
  const fixAt = seen.ids.findIndex(i => asked.includes(i))
  expect(triage.length === 1 && fixAt >= 0 && triage[0]!.at <= seen.at[fixAt]!, `D21 one triage launch, before the question (${triage.length} triage launches)`)
  expect(asked.length === 1 && asked[0]!.startsWith('build.'), `D21 correcting the test is one question, at Build where integrate ran the locked tests (${asked.join(', ') || 'none'})`)
  const writer = launchesOf(w, 'temper:temper-acceptance', p => /^Correction:/m.test(p))
  const reviewAt = launchesOf(w, 'temper:temper-review')[0]?.at ?? -1
  expect(writer.length === 1 && reviewAt > writer[0]!.at, `D21 one writer launch corrects the test, then Review (${writer.length} writer launches; Review at ${reviewAt})`)
  expect(launchesOf(w, 'temper:temper-build-task').length === 2 && launchesOf(w, 'temper:temper-build').length === 0,
    'D21 no builder is launched for the wrong test')
  expect(seen.ids.filter(i => !asked.includes(i)).join(',') === 'plan.approve,commit.confirm' && ended(w), `D21 the run asks the approval, the one question and the commit (${seen.ids.join(', ')})`)
  ownAutos(w)
  worldCheck(w)
}

// D32c: a stop of an unattended run keeps the mode, and its question says the run goes on by itself. The stop is an
// unfinished Review: the first Review records no completion.
export const stopKeepsMode = (w: World): void => {
  withRemote(w)
  watch(w)
  startProject(w)
  let reviews = 0
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-review': (wd, a) => {
      reviews++
      if (reviews > 1) AGENTS['temper:temper-review']!(wd, a)
    },
  }
  const modes: string[] = []
  let stopText = ''
  const base = defaultPerson()
  const { person, seen } = seeing(w, (ask, wd) => {
    if (idOf(ask) === 'plan.approve' && seen.approvalAt < 0) {
      const run = ((ask.options ?? []) as Json[]).find(o => o.id === 'approve-run')
      expect(run !== undefined, 'D32c the approval offers approve-run')
      return pickId(wd, ask, 'approve-run')   // WP12: picked as a person picks, so the world check sees the approval
    }
    if (seen.approvalAt >= 0) {
      modes.push(`${idOf(ask)}=${runMode(wd)}`)
      expect(runMode(wd) === 'autonomous', `D32c a stop keeps the mode: at ${idOf(ask)} run_mode is ${runMode(wd) || 'unset'}`)
      if (idOf(ask) !== 'commit.confirm' && stopText === '') {
        stopText = shown(ask, null)
        expect(/goes on by itself/.test(stopText), `D32c the question of the stop says the run goes on by itself (${idOf(ask)}: ${stopText.slice(0, 160)})`)
      }
    }
    return base(ask, wd)
  })
  promise('D32c', () => orchestrate(w, script({ agents, person })))
  expect(stopText !== '' && reviews >= 2, `D32c the unfinished Review stopped the run and asked (${modes.join(', ')})`)
  expect(ended(w), 'D32c the run reaches its commit and ends')
  ownAutos(w)
  worldCheck(w)
}

// D24: a revision of the plan is a narrow agent that gets the findings and the task blocks they name, not a full
// planner pass.
const REVISE_FINDING: FreshFinding = { lens: 'readiness', severity: 'high', claim: 'Task 2: the Case "two stages are written in the order" names no expected value' }
const REVISED = (tasks: string): string => tasks.replace('- two stages are written in the order the ledger holds them',
  '- two stages are written in the order the ledger holds them: build first, then review, as a JSON array')
export const reviseNarrow = (w: World): void => {
  withRemote(w)
  watch(w)
  startProject(w, 'plan:\n  fresh-review: auto')
  let reviews = 0
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-plan': (wd, a) => {
      expect(launchesOf(wd, 'temper:temper-plan').length <= 1, 'D24 the revision launched temper:temper-plan, a full planner pass, not the narrow revise agent')
      planner({ complexity: 'medium' })(wd, a)
    },
    'temper:temper-plan-revise': wd => {
      wd.write(`${SPEC}/tasks.md`, REVISED(wd.read(`${SPEC}/tasks.md`)))
      t(wd, 'gate plan')
    },
    'temper:temper-plan-review': (wd, a) => { reviews++; freshReviewer(wd, a, reviews === 1 ? [REVISE_FINDING] : []) },
    'temper:temper-design': wd => wd.write(`${SPEC}/design.md`, '# Design: CI report\n\n## Architecture\n\nTwo small modules.\n\n## Areas of Concern\n\nNone flagged.\n'),
  }
  promise('D24', () => orchestrate(w, script({ agents, person: defaultPerson() })))
  const revise = launchesOf(w, 'temper:temper-plan-revise')
  expect(revise.length === 1 && launchesOf(w, 'temper:temper-plan').length === 1,
    `D24 one narrow revise launch and one planner launch (${revise.length} revise, ${launchesOf(w, 'temper:temper-plan').length} planner)`)
  const prompt = revise[0]?.prompt ?? ''
  expect(prompt.includes(REVISE_FINDING.claim) && /^Affected tasks:[^\n]*\b2\b/m.test(prompt) && !/^Project brief:/m.test(prompt),
    `D24 the revise agent gets the finding whole and the task it names, and no project brief (${prompt.slice(0, 200)})`)
  expect(ended(w), 'D24 the run reaches its commit and ends')
  ownAutos(w)
  worldCheck(w)
}

// The registered names and the modes each runs in (the runner leaves out a mode a scenario does not name). Each row of
// docs/plans/one-go/done.md that names a scenario with no mode runs in plain, mod and driver mode.
const ALL = ['plain', 'mod', 'driver']
export const ACCEPT_SCENARIOS: Record<string, { run: (w: World) => void; modes: string[] }> = {
  'two-dialogs': { run: twoDialogs, modes: ALL },
  'approval-first': { run: approvalFirst, modes: ['plain', 'mod'] },
  'flagged-map': { run: flaggedMap, modes: ALL },
  'fix-two': { run: fixTwo, modes: ['plain', 'driver'] },
  'vague-run': { run: vagueRun, modes: ALL },
  'repair-finding': { run: repairFinding, modes: ALL },
  'repair-worse': { run: repairWorse, modes: ALL },
  'group-fail': { run: groupFail, modes: ALL },
  'group-fail-twice': { run: groupFailTwice, modes: ALL },
  'integrate-fail': { run: integrateFail, modes: ['driver'] },
  'budget-stop': { run: budgetStop, modes: ALL },
  'criteria-by-cli': { run: criteriaByCli, modes: ['plain'] },
  'ask-every-stage': { run: askEveryStage, modes: ALL },
  'design-on-ask': { run: designOnAsk, modes: ['plain'] },
  'acceptance-wrong-test': { run: acceptanceWrongTest, modes: ALL },
  'stop-keeps-mode': { run: stopKeepsMode, modes: ALL },
  'revise-narrow': { run: reviseNarrow, modes: ['plain'] },
}
