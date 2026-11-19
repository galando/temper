import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

import { orchestrate, orchestrateFix, runCalls } from './loop'
import type { Script } from './loop'
import { BASE_FILES, BYTES_CODE, BYTES_STUB, BYTES_TEST, INTENT_SCENARIOS, PLAN_MD, SHAPE_CODE, SHAPE_STUB, SHAPE_TEST, SUITE, TASKS_MD } from './project'
import { pickId, stagePerson } from './persons'
import { ROOT, TEMPER, World, reviewDone } from './world'
import type { Agent, Json, Person } from './world'

export const SPEC = '.temper/specs/ci'

// A scripted agent's shell call goes through the mod's rule engine like a real one.
export function sh(w: World, command: string): { code: number; out: string } {
  w.guardBash(command)
  return w.run(command)
}
export const t = (w: World, args: string) => sh(w, `${TEMPER} ${args}`)

export function startProject(w: World, config = '', before?: (w: World) => void): void {
  for (const [rel, text] of Object.entries(BASE_FILES)) {
    fs.mkdirSync(path.dirname(path.join(w.dir, rel)), { recursive: true })
    fs.writeFileSync(path.join(w.dir, rel), text)
  }
  w.sh('git add -A && git commit -qm base')
  w.sh(`mkdir -p .claude && cp ${ROOT}/templates/temper.config.default .claude/temper.config`)
  // 9.8.0: Check is run by the CLI. The driver names its commands (the suite, with a coverage total it prints), so a
  // run gives the same verdict on every machine. WP19: the lines go at the top of the check block, whatever the
  // template holds there, and no key turns the planted bug score off: it gates nothing.
  const cfg = path.join(w.dir, '.claude/temper.config')
  fs.writeFileSync(cfg, fs.readFileSync(cfg, 'utf8').replace(/^check:\n/m, `check:\n  commands:\n    test: ${SUITE}\n    coverage: ${SUITE} && echo 'TOTAL 100 10 90%'\n`))
  if (config) fs.appendFileSync(cfg, `\n${config}\n`)
  w.sh('git add -A && git commit -qm config')
  before?.(w)
  w.sh(`${TEMPER} init`)
  w.sh(`${TEMPER} state init ci --feature 'CI report'`)
}

export const worktreeOf = (show: string): string => /^WORKTREE:\s*(\S+)/m.exec(show)?.[1] ?? ''

// 9.8.0: a build agent gets one task (`Task: N`) or a chain (`Tasks: N, M`) and its `Model:`; it starts each next task,
// builds it, and gates it itself, stopping at the first refusal (agents/build-task.md).
export const tasksOf = (a: Json): number[] => {
  const m = /Tasks?:\s*([\d, ]+)/.exec(String(a.prompt))
  return m ? m[1]!.split(',').map(x => Number(x.trim())).filter(Boolean) : []
}
export const chained = (one: (w: World, n: number, a: Json) => void): Agent => (w, a) => {
  const model = /\nModel:\s*(\S+?)\.?\s*$/m.exec(String(a.prompt))?.[1] ?? 'haiku'
  tasksOf(a).every((n, i) => {
    if (i > 0 && t(w, `task start ${n}`).code !== 0) return false
    one(w, n, a)
    return t(w, `task gate ${n} --model ${model}`).code === 0
  })
}

export function buildOne(w: World, n: number): void {
  const show = t(w, `task show ${n}`).out
  const wt = path.relative(w.dir, worktreeOf(show))
  const [testFile, srcFile, stub, code, test] = n === 1
    ? ['unit/test_ci_shape.py', 'src/ci_shape.py', SHAPE_STUB, SHAPE_CODE, SHAPE_TEST]
    : ['unit/test_ci_bytes.py', 'src/ci_bytes.py', BYTES_STUB, BYTES_CODE, BYTES_TEST]
  w.write(path.join(wt, testFile), test)
  w.write(path.join(wt, srcFile), stub)
  const red = t(w, `task test ${n} --phase red`)
  if (red.code === 0) throw new Error('RED passed')
  w.write(path.join(wt, srcFile), code)
  const green = t(w, `task test ${n} --phase green`)
  if (green.code !== 0) throw new Error(`GREEN failed: ${green.out}`)
}

export const buildTask: Agent = chained(buildOne)

// The fresh reviewer of the plan (agents/plan-review.md): each lens of its launch prompt records its findings, then its completion,
// then (comprehension) the paraphrase, every row against the tasks.md it read.
export type FreshFinding = { lens: string; severity: string; claim: string }
export function freshReviewer(w: World, a: Json, found: FreshFinding[], skip: string[] = []): void {
  const inst = /Instance:\s*(\w)/.exec(a.prompt)?.[1] ?? 'A'
  const lenses = (/Lenses:\s*([^.]+)\./.exec(a.prompt)?.[1] ?? 'readiness, zoom-out, comprehension, tests').split(',').map(x => x.trim())
  const art = `--artifact ${SPEC}/tasks.md`
  const tasks = (w.read(`${SPEC}/tasks.md`).match(/^### Task \d+/gm) ?? []).length
  for (const lens of lenses) {
    for (const f of found.filter(x => x.lens === lens))
      t(w, `evidence add --stage plan --phase fresh --severity ${f.severity} --claim '[${f.lens}] ${f.claim}' ${art}`)
    if (skip.includes(lens)) continue
    // 9.8.4: a recheck round counts the earlier findings it checked (the prompt's `Earlier findings (N)`)
    const earlier = Number(/Earlier findings \((\d+)\)/.exec(a.prompt)?.[1] ?? 0)
    const value = lens === 'readiness' ? ` --value ${tasks}` : lens === 'recheck' ? ` --value ${earlier}` : ''
    t(w, `evidence add --stage plan --phase fresh --exit 0 --label PROVEN --claim 'fresh review completed: ${lens} ${inst}'${value} ${art}`)
    if (lens === 'comprehension')
      t(w, `evidence add --stage plan --phase fresh --claim 'paraphrase: two modules build a CI report from the gate ledger | the ledger is a JSON file the CLI writes' ${art}`)
  }
}

export const AGENTS: Record<string, Agent> = {
  'temper:temper-intent': w => w.write(`${SPEC}/intent.md`, fs.readFileSync(path.join(ROOT, 'templates/example-intent.md'), 'utf8')),
  'temper:temper-plan': w => {
    if (!w.read(`${SPEC}/intent.md`).includes(INTENT_SCENARIOS)) w.write(`${SPEC}/intent.md`, w.read(`${SPEC}/intent.md`).replace('## Scenarios (BDD)\n', INTENT_SCENARIOS))
    w.write(`${SPEC}/plan.md`, PLAN_MD)
    w.write(`${SPEC}/tasks.md`, TASKS_MD)
    t(w, 'state set complexity simple')
    t(w, 'risk')
  },
  'temper:temper-plan-review': (w, a) => freshReviewer(w, a, []),
  // 9.8.0: the acceptance writer: no test framework of its own in the driver, so it records why there are none.
  'temper:temper-acceptance': w => { t(w, "acceptance skip --reason 'the e2e driver writes no acceptance tests'") },
  'temper:temper-build-task': buildTask,
  'temper:temper-review': w => reviewDone(w),
  'temper:temper-check': w => {
    t(w, `evidence add --stage check --claim 'tests' --exit 0 --cmd 'python3 -m unittest discover -s unit -t .'`)
    t(w, `evidence add --stage check --claim 'coverage' --value 90 --exit 0 --cmd 'coverage report'`)
    for (const s of ['CI JSON shape is stable across a run', 'Override rows name the approver', 'Same ledger gives the same bytes'])
      t(w, `evidence add --stage check --scenario '${s}' --claim 'scenario: ${s}' --exit 0 --cmd 'python3 -m unittest discover -s unit -t .'`)
    t(w, `evidence add --stage check --criterion AC-02 --claim 'the override rows were read by hand' --exit 0 --cmd 'read the output'`)
  },
}

// The person: the recommended option of each question (its `recommended` field), else the first, unless a scenario says
// otherwise.
export const recommended: Person = ask => {
  const o = (ask.options as Json[]).find(x => x.recommended === true) ?? (ask.options as Json[])[0]
  if (ask.question.question.startsWith('Every gate passed. The report is above')) return 'Not now'
  return o.label
}

// WP11: the person who approves with Ask me at every stage (stagePerson of scripts/e2e/persons.ts, by the option's id)
// and takes the recommended option of every other question as `recommended` does. A scenario that tests the question of
// a later gate takes this person: with the default approval the run goes on by itself and asks none of them.
export const asksEveryStage: Person = (ask, wd) =>
  String(ask.id ?? '') === 'plan.approve' ? stagePerson(ask, wd) : recommended(ask, wd)

export const script = (extra: Partial<Script> = {}): Script => ({
  agents: AGENTS,
  person: recommended,
  instruction: (_w, text) => /each file the run changed|^Copy what|^When .* records deviations/.test(text),
  ...extra,
})

// An agent the session launches by hand, outside the loop over `next` (commands/fix.md launches the RCA agent itself):
// counted as a launch of its type, as the loop counts the agents the CLI names.
export function launchByHand(w: World, agents: Record<string, Agent>, type: string, a: Json = {}): void {
  w.countLaunch(type)
  agents[type]!(w, { type, ...a })
}

// 9.8.5 (WP05): the default run the floor counts: the project of full-run, the Context Map as agents/plan.md tells a
// planner to write it (the scripted Plan agent of every scenario does), and the person who takes the recommended option
// everywhere. It asserts nothing about numbers: scripts/e2e/floor.json holds them.
export const defaultRun = (w: World): void => {
  startProject(w)
  orchestrate(w, script())
}

// 9.8.5 (WP18): the scripted reviewer of full-run names the files `temper review files` prints. Its first Review names
// one file fewer: the Review gate fails on the row `review completed`, the question recommends Run Review again, and
// the second launch names the file not read. The second Review names every file, and the run goes on to its end.
// WP11: the person approves with Ask me at every stage (asksEveryStage), so every later gate asks its own question.
export const fullRun = (w: World): void => {
  startProject(w)
  const reviews: Array<{ files: string[]; prompt: string }> = []
  const reviewer: Agent = (wd, a) => {
    const r = t(wd, 'review files')
    const files = r.code === 0 ? r.out.split('\n').map(x => x.trim()).filter(x => x !== '') : []
    reviews.push({ files, prompt: String(a.prompt) })
    const read = (reviews.length === 1 ? files.slice(1) : files).map(f => ` --read ${f}`).join('')
    t(wd, `evidence add --stage review --claim 'review completed' --exit 0 --cmd 'review panel'${read}`)
  }
  // the row review completed and the recommended option, as the person sees them at the question after the short
  // Review, and at the first question after the second launch (whatever its stage)
  const look = (ask: Json, wd: World): { row: Json; rec: string } => {
    const rows = (wd.json('.temper/gates.json').review?.requirements ?? []) as Json[]
    const rec = (ask.options as Json[]).find(o => o.recommended === true)?.label
    return { row: rows.find(x => x.name === 'review completed') ?? {}, rec: String(rec) }
  }
  const seen: { short?: { row: Json; rec: string }; whole?: { row: Json; rec: string } } = {}
  const end = orchestrate(w, script({
    agents: { ...AGENTS, 'temper:temper-review': reviewer },
    person: (ask, wd) => {
      if (seen.short === undefined && String(ask.id ?? '') === 'review.fail') seen.short = look(ask, wd)
      if (seen.whole === undefined && reviews.length === 2) seen.whole = look(ask, wd)
      return asksEveryStage(ask, wd)
    },
  }))
  const first = reviews[0]?.files ?? []
  const n = first.length
  const { short, whole } = seen
  expect(short !== undefined, `a reviewer that names one file fewer fails the Review gate (review files printed ${n})`)
  const counted = `read ${n - 1} of ${n} changed files; not read: `
  expect(n >= 2 && short!.row.pass === false && String(short!.row.detail).startsWith(counted),
    `the row review completed fails and counts the files read (${JSON.stringify(short!.row)})`)
  expect(short!.rec === 'Run Review again (Recommended)', `the question recommends Run Review again (${short!.rec})`)
  expect(reviews.length === 2 && reviews[1]!.prompt.split('\n').some(l => l.includes(first[0]!)),
    `the second Review launch names the file not read, ${first[0]} (${reviews.length} launches)`)
  const all = `read ${n} of ${n} changed files`
  expect(whole !== undefined && whole.row.pass === true && String(whole.row.detail).startsWith(all),
    `the second Review names every file and the gate passes (${JSON.stringify(whole?.row)})`)
  expect(end.action === 'none', `the run goes on to its end (last action ${end.action})`)
  // WP15: the approval and the commit each show their card before the person answers. The trace holds one entry
  // `card approval` in the step of the question plan.approve, before the call that approves, and one `card commit` in
  // the step of the commit decision (this run asks at every stage, so its passed Check question), before the call that
  // goes on to the commit. A step of the trace starts at a line with no indent.
  const cardBefore = (kind: string, ask: RegExp, answer: RegExp): string => {
    const tr = w.trace
    const at = tr.flatMap((l, i) => (new RegExp(`^\\s*card ${kind}(\\s|$)`).test(l) ? [i] : []))
    if (at.length !== 1) return `${at.length} entries card ${kind}`
    const c = at[0]!
    const q = tr.findIndex(l => ask.test(l))
    const a = tr.findIndex((l, i) => i > q && answer.test(l))
    const inStep = q >= 0 && q < c && tr.slice(q + 1, c).every(l => l.startsWith(' '))
    return inStep && a > c ? 'before' : `card ${kind} at ${c}, its question at ${q}, the answer at ${a}`
  }
  const approval = cardBefore('approval', /^ask:plan:plan\.approve:/, /call temper state advance plan_complete /)
  expect(approval === 'before', `one entry card approval before the approval's answer (${approval})`)
  const commit = cardBefore('commit', /^ask:(check:check\.pass|commit:commit\.confirm):/,
    /call temper (state advance check_complete commit|spec commit|git commit)/)
  expect(commit === 'before', `one entry card commit before the commit's answer (${commit})`)
}
export { Json }

export const expect = (cond: unknown, message: string): void => {
  if (!cond) throw new Error(`expectation failed: ${message}`)
}
const stopAtAsk = (text: string): Partial<Script> => ({ stopAt: (_w, n) => n.action === 'ask' && String(n.ask.question.question).includes(text) })

// The mod guards the run (mod mode) and stands aside with no mod; the answer of the person is what lets a person only call through.
export const modGuards = (w: World): void => {
  startProject(w)
  const n = orchestrate(w, script(stopAtAsk('Plan: the check passed')))
  expect(n.action === 'ask', 'the run reached the plan question')
  const write = w.denies({ tool: 'Write', input: { file_path: `${w.dir}/src/other.py` } })
  const advance = w.denies({ tool: 'Bash', input: { command: `${TEMPER} state advance plan_complete build` } })
  if (w.mode !== 'plain') {
    expect(write?.includes('The run ci (Plan stage) owns this folder.') && write.includes('claude --worktree'), `the write refusal names the run and the worktree (${write})`)
    expect(advance !== null, 'leaving Plan is refused without the answer')
    // WP11: the option is selected by its id, never by its label
    const stage = ((n.ask as Json).options as Json[]).find(o => o.id === 'ask-every-stage')
    expect(stage !== undefined, 'the approval offers ask-every-stage')
    const option = w.answer(n.ask as Json, String(stage!.label))
    expect(option.id === 'ask-every-stage', 'the option exists')
    // WP12: the answer's advance carries the digests the question showed; that call passes, word for word
    const leave = ((option.calls ?? []) as string[]).find(c => c.includes('state advance plan_complete build --shown ')) ?? ''
    expect(leave !== '' && w.denies({ tool: 'Bash', input: { command: leave } }) === null, 'leaving Plan passes as the call the answer maps to')
    expect(w.denies({ tool: 'Bash', input: { command: `${TEMPER} state advance plan_complete build` } }) !== null, 'the advance without the digests the question showed is no call of the answer')
  } else {
    expect(write === null && advance === null, 'with no mod nothing is refused')
  }
}

// A small change at Check: the window opens (the person's answer), a code write passes inside it, and the closed change runs
// Review of the changed files, then Check, then the commit gate.
// WP11: the person approves with Ask me at every stage (asksEveryStage), so Check asks its own question.
export const smallChange = (w: World): void => {
  startProject(w)
  orchestrate(w, script({ person: asksEveryStage, ...stopAtAsk('Check: the check passed') }))
  const outside = w.denies({ tool: 'Write', input: { file_path: `${w.dir}/src/ci_shape.py` } })
  expect(w.mode === 'plain' || outside !== null, 'a code write at Check is refused before the window')
  let seen = ''
  orchestrate(w, script({
    person: (ask, wd) => {
      const q = String(ask.question.question)
      if (q.startsWith('Check: the check passed') && !seen) return 'More options'
      if (q.includes('more options') && !seen) return 'Make a small change'
      return asksEveryStage(ask, wd)
    },
    instruction: (wd, text) => {
      if (text.startsWith('Make the small change')) {
        seen = 'changed'
        wd.write('src/ci_shape.py', SHAPE_CODE + '\n# a small change made by hand\n')
        const r = t(wd, 'adhoc close')
        expect(r.code === 0 && r.out.includes('still to run: review, check, commit'), `adhoc close lists the steps (${r.out})`)
        return true
      }
      return /each file the run changed|^Copy what|^When .* records deviations/.test(text)
    },
  }))
  expect(seen === 'changed', 'the small change was made')
  const flow = w.trace.join('\n')
  expect(/work:check/.test(flow), 'the side steps ran')
  const after = w.denies({ tool: 'Write', input: { file_path: `${w.dir}/src/ci_shape.py` } })
  expect(w.mode === 'plain' || after !== null || !w.exists('.temper/build-state.json'), 'the window is closed again (or the run is over)')
}

// A task an earlier task already built (its RED run passes: the person accepts it) and a manual task (the person confirms it).
export const coveredAndManual = (w: World): void => {
  // the second task's code is already in the project, as an earlier task would have left it
  startProject(w, '', wd => {
    wd.write('src/ci_bytes.py', BYTES_CODE)
    wd.sh('git add -A && git commit -qm "an earlier change built the byte order"')
  })
  const tasks = TASKS_MD.replace('- [ ] done\n', '- [ ] done\n').trimEnd() + `

### Task 3: Write the guide
**Files:**
- \`docs/guide.md\`
**Depends:** none
**Test:** manual — the guide reads well and its links work
**Cases:**
- the guide names the install step
- the guide links the changelog
**Traced to:** Infrastructure: the report needs a guide
- [ ] done
`
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-plan': wd => {
      AGENTS['temper:temper-plan']!(wd, {})
      wd.write(`${SPEC}/tasks.md`, tasks)
      wd.write(`${SPEC}/plan.md`, PLAN_MD.replace('| unit/test_ci_bytes.py | tests the byte order | Same ledger gives the same bytes |', '| unit/test_ci_bytes.py | tests the byte order | Same ledger gives the same bytes |\n| docs/guide.md | the guide | Infrastructure: the report needs a guide |'))
    },
    'temper:temper-build-task': chained((wd, n) => {
      if (n === 3) {
        const wt = path.relative(wd.dir, worktreeOf(t(wd, 'task show 3').out))
        const refused = t(wd, 'task test 3 --phase red')
        expect(refused.code !== 0 && refused.out.includes('manual task'), `task test refuses a manual task (${refused.out})`)
        wd.write(path.join(wt, 'docs/guide.md'), '# Guide\n\nInstall with the plugin. See the CHANGELOG.\n')
      } else if (n === 2) {
        const wt = path.relative(wd.dir, worktreeOf(t(wd, 'task show 2').out))
        wd.write(path.join(wt, 'unit/test_ci_bytes.py'), BYTES_TEST)
        const red = t(wd, 'task test 2 --phase red')
        expect(red.code === 0, 'the RED run passes: an earlier task built it')
      } else buildOne(wd, n)
    }),
  }
  const asked: string[] = []
  orchestrate(w, script({
    agents,
    person: (ask, wd) => {
      const q = String(ask.question.question)
      asked.push(q)
      if (q.includes('its tests already pass before any change')) return { label: 'Accept it as done (Recommended)', note: 'an earlier change built it' }
      if (q.includes('is a manual task')) return { label: 'Confirm', note: 'Dana Cohen' }
      if (q.startsWith('Every gate passed. The report is above')) {
        const rows = JSON.stringify(wd.json('.temper/evidence/build.json'))
        expect(rows.includes('Task 3 confirmed by Dana Cohen'), 'the confirmation carries the name the person gave')
        expect(rows.includes('Task 2 accepted as done') && rows.includes('an earlier change built it'), 'the acceptance carries the reason the person gave')
      }
      return asksEveryStage(ask, wd)
    },
  }))
  expect(asked.some(q => q.includes('Task 2') && q.includes('its tests already pass before any change')), 'the covered question was asked for Task 2')
  expect(asked.some(q => q.includes('Task 3') && q.includes('is a manual task')), 'the manual question was asked for Task 3')
}

// Draft pull request and the Pipeline stage (a fake gh and a bare origin): the Check question's Commit and open PR option, the commit steps that
// open the PR as a draft, then Pipeline: red (the agent proposes a fix), the person applies it and pushes, green, end of run.
export const prAndPipeline = (w: World): void => {
  const bin = path.join(w.dir, '..', `bin-${path.basename(w.dir)}`)
  fs.mkdirSync(bin, { recursive: true })
  const log = path.join(bin, 'gh.log')
  fs.writeFileSync(path.join(bin, 'gh'), `#!/usr/bin/env bash\necho "gh $*" >> "${log}"\ncase "$*" in\n  "pr create"*) echo "https://github.com/example/ci/pull/7" ;;\nesac\n`, { mode: 0o755 })
  w.env.PATH = `${bin}:${w.env.PATH}`
  const origin = path.join(bin, 'origin.git')
  w.sh(`git init -q --bare ${origin}`)
  startProject(w, '', wd => wd.sh(`git remote add origin ${origin} && git push -q origin main`))
  let round = 0
  const launches: Record<string, number> = {}
  const counted = (type: string): Agent => (wd, a) => {
    launches[type] = (launches[type] ?? 0) + 1
    AGENTS[type]!(wd, a)
  }
  const opened: string[] = []
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-review': counted('temper:temper-review'),
    'temper:temper-check': counted('temper:temper-check'),
    'temper:temper-pipeline': wd => {
      round += 1
      expect(!/reason|Dana/.test(w.trace.join('')) || true, 'ok')
      wd.write(`${SPEC}/pipeline-context.json`, JSON.stringify(round === 1
        ? { status: 'red', round: 1, failed_jobs: [{ name: 'unit', stage: 'test', id: '11', error: 'AssertionError: 3 != 4' }], fix: ['src/ci_shape.py: add a trailing comment so the check reads it'] }
        : { status: 'green', round: 2, failed_jobs: [], fix: [] }))
    },
  }
  const refused: string[] = []
  const result = orchestrate(w, script({
    agents,
    person: (ask, wd) => {
      const q = String(ask.question.question)
      if (q.startsWith('Check: the check passed')) return { label: 'Commit and open PR', note: '' }
      return asksEveryStage(ask, wd)
    },
    instruction: (wd, text) => {
      if (text.startsWith('Pull request: follow')) return true
      if (text.includes('section One PR')) {
        const br = wd.sh('git branch --show-current').trim()
        expect(wd.denies({ tool: 'Bash', input: { command: `gh pr create --head ${br} --base main --title 't' --body-file b` } }) !== null || wd.mode === 'plain', 'a pull request without --draft is refused by the mod')
        expect(wd.denies({ tool: 'Bash', input: { command: 'gh pr ready 7' } }) !== null || wd.mode === 'plain', 'gh pr ready is refused by the mod')
        // The body goes in a file from mktemp, outside the project, as reference/pr.md says (a file in the project is a
        // change outside the plan, and the commit hook the driver installs refuses the next commit).
        const body = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'temper-pr-')), 'body.md')
        fs.writeFileSync(body, 'The body\n')
        runCalls(wd, [`git push -q -u origin ${br}`, `gh pr create --head ${br} --base main --title 'feat: CI report' --body-file ${body} --draft`])
        opened.push(br)
        return true
      }
      if (text.startsWith('If a pull request was opened')) {
        const call = /run (\S+ state advance commit_complete pipeline)/.exec(text)![1]!
        runCalls(wd, [call])
        return true
      }
      if (text.startsWith('Apply the changes the fix list')) {
        wd.write('src/ci_shape.py', SHAPE_CODE + '# the Pipeline fix\n')
        return true
      }
      if (text.startsWith('git add -- {each changed file')) {
        runCalls(wd, ['git add -- src/ci_shape.py'])
        return true
      }
      return /each file the run changed|^Copy what|^When .* records deviations/.test(text)
    },
  }))
  void result
  expect(opened.length === 1, 'one pull request was opened')
  const ghLog = fs.readFileSync(log, 'utf8')
  expect(/gh pr create .*--draft/.test(ghLog) && !/gh pr ready/.test(ghLog), 'the pull request is a draft and nothing marked it ready')
  expect(round === 2, `Pipeline ran twice (${round})`)
  // 9.8.0: Check is run by the CLI (temper check run), not an agent
  const checks = w.trace.filter(l => l.includes('call temper check run')).length
  expect(launches['temper:temper-review'] === 1 && checks === 1, `a CI fix sends no Review or Check again (review ${launches['temper:temper-review']}, check ${checks})`)
  expect(w.sh('git log --format=%s -n 3').includes('fix(ci): apply the Pipeline fix (CI fix round 1)'), 'the fix was committed with the agreed message')
  expect(w.sh(`git --git-dir=${origin} log --format=%s -n 1 feature/ci`).includes('fix(ci)'), 'the fix was pushed to origin')
  void refused
  // WP16: with the mod's driver a run leaves it only for a step of the closed list: here the pull request after the
  // commit and the Pipeline fix, each once, as the trace's hand back lines (`driver handback: step <kind> <option id>`)
  if (w.mode === 'driver') {
    const kinds = w.trace.filter(l => l.startsWith('  driver handback'))
      .map(l => /^ {2}driver handback: step (\S+) \S+/.exec(l)?.[1] ?? `(${l.trim().slice(0, 60)})`)
    expect(kinds.join(',') === 'pull-request,pipeline-fix',
      `in driver mode the run hands back exactly the kinds pull-request and pipeline-fix (${kinds.join(', ') || 'none'})`)
  }
}

// The Context check of Plan: the map has a gap, so the CLI asks the person (not Plan); the answer runs plan review through the mod.
// WP13: a flagged line that fits the approval is folded into it (the scenario context-fold). WP15: the card shows a
// flagged line of any length the map allows whole, so the gap here (93 characters, the longest a map line allows) is
// folded too; the config line plan.context-check: always keeps the Context check its own question.
const LONG_GAP = 'no rate limit policy was found in the code, the docs, the ticket or the notes of the releases'
export const contextCheck = (w: World): void => {
  startProject(w, 'plan:\n  context-check: always')
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-plan': (wd, a) => {
      AGENTS['temper:temper-plan']!(wd, a)
      wd.write(`${SPEC}/plan.md`, PLAN_MD.replace('- reviewed: pending', `- gap: ${LONG_GAP}\n- reviewed: pending`))
    },
  }
  let asked = 0
  orchestrate(w, script({
    agents,
    person: (ask, wd) => {
      if (String(ask.question.question) === `It could not find: ${LONG_GAP.slice(0, 87)}.... Is that right?`) {
        asked += 1
        const direct = wd.denies({ tool: 'Bash', input: { command: `${TEMPER} plan review --answer 'As planned'` } })
        expect(wd.mode === 'plain' || direct !== null, 'plan review is refused with no answer')
        // 9.8.0: the question names the gap; As planned, Something else (typed: Plan revises), Carry forward
        expect((ask.options as Json[]).map(o => o.label).join('|') === 'As planned (Recommended)|Something else|Carry forward', 'the options are As planned, Something else and Carry forward')
        return 'As planned (Recommended)'
      }
      return recommended(ask, wd)
    },
  }))
  expect(asked === 1, `the Context check was asked once (${asked})`)
}

// WP13: a flagged Context Map whose lines fit the approval is folded into it. The Context check is not asked on its
// own; the approval's text holds the flagged line whole; the option the person picks answers it with plan review, so
// plan.md records that the answer was given at the approval and how many lines were shown.
const SHORT_GAP = 'no rate limit policy was found in code, docs or the ticket'
export const contextFold = (w: World): void => {
  startProject(w)
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-plan': (wd, a) => {
      AGENTS['temper:temper-plan']!(wd, a)
      wd.write(`${SPEC}/plan.md`, PLAN_MD.replace('- reviewed: pending', `- gap: ${SHORT_GAP}\n- reviewed: pending`))
    },
  }
  const ids: string[] = []
  let whole = false
  let planAtCommit = ''
  orchestrate(w, script({
    agents,
    person: (ask, wd) => {
      const id = String(ask.id ?? '')
      ids.push(id)
      if (id === 'plan.approve') whole = String(ask.question.question).includes(SHORT_GAP)
      if (id === 'commit.confirm') planAtCommit = wd.exists(`${SPEC}/plan.md`) ? wd.read(`${SPEC}/plan.md`) : ''
      return recommended(ask, wd)
    },
  }))
  expect(!ids.includes('plan.context'),
    `the Context check is folded into the approval, not asked on its own (${ids.join(', ')})`)
  expect(whole, 'the approval holds the flagged line whole')
  const review = (/^- (reviewed|answer):.*$/m.exec(planAtCommit) ?? [''])[0]
  const answered = /^- answer: .*at the approval, 1 flagged lines? shown/m.test(planAtCommit)
  expect(/^- reviewed: human/m.test(planAtCommit) && answered,
    `plan.md records the answer given at the approval and the 1 line shown (${review})`)
}

// The run's branch exists from an earlier run with commits this checkout lacks. WP12: no branch is made before the approval,
// so the approval names the clash and continues on that branch; its More list offers a new branch, after which the
// approval is asked again with no clash.
export const branchClash = (w: World): void => {
  startProject(w, '', wd => {
    wd.sh('git checkout -q -b feature/ci && echo old > old.txt && git add old.txt && git commit -qm "an earlier run" && git checkout -q main')
  })
  const labels: string[] = []
  let named = false
  orchestrate(w, script({
    person: (ask, wd) => {
      const q = String(ask.question.question)
      if (String(ask.id ?? '') === 'plan.approve' && q.includes('exists from an earlier run')) {
        named = q.includes('The approval continues on it.')
        labels.push(...(ask.options as Json[]).map(o => String(o.label)))
        return String((ask.options as Json[]).find(o => o.kind === 'more')?.label ?? recommended(ask, wd))
      }
      if (String(ask.id ?? '') === 'plan.approve.more' && (ask.options as Json[]).some(o => o.id === 'new-branch')) {
        labels.push(...(ask.options as Json[]).map(o => String(o.label)))
        return 'Build on a new branch feature/ci-2'
      }
      return recommended(ask, wd)
    },
  }))
  expect(named && labels.includes('Build on a new branch feature/ci-2'), 'the approval named the clash and offered the new branch')
  expect(w.sh('git branch --show-current').trim() === 'feature/ci-2', 'the run went on the new branch')
}

// The commit hook gates the run's branch only, and turning Temper off removes it; the plugin gone passes the hook.
export const hookScope = (w: World): void => {
  startProject(w)
  w.sh(`bash ${ROOT}/scripts/guards/install.sh`)
  w.sh('git checkout -q -b elsewhere && echo x > other.txt && git add other.txt')
  const other = w.run('git commit -q -m "elsewhere"')
  expect(other.code === 0, `a commit on another branch passes the hook (${other.out})`)
  w.sh('git checkout -q -B feature/ci && echo y > y.txt && git add y.txt')
  const mine = w.run('git commit -q -m "on the run branch"')
  expect(mine.code !== 0, 'a commit on the run branch is gated (the gates are not green)')
  // a second session cannot start a run in the folder: the run owns it
  const second = w.denies({ tool: 'Bash', input: { command: `${TEMPER} state init other --feature 'another thing'` } })
  expect(w.mode === 'plain' || (second !== null && second.includes('Only the user decides')), `the mod refuses a second session's state init (${second})`)
  const off = w.run(`${TEMPER} guards uninstall`)
  expect(off.code === 0 && /removed the Temper hook/.test(off.out), `guards uninstall removes the hook (${off.out})`)
  expect(w.run(`${TEMPER} guards uninstall`).out.includes('nothing to change'), 'a second uninstall changes nothing')
  expect(!w.exists('.git/temper-gate'), 'the temper-gate folder is gone')
  if (w.mode !== 'plain') {
    const ref = w.denies({ tool: 'Bash', input: { command: `${TEMPER} guards uninstall` } })
    expect(ref !== null && ref.includes('turning the commit gate off'), 'the mod refuses uninstall while a run is active')
  }
}

// A scenario whose Test: command fails at integration: the Build gate names the scenario, its command and the exit.
export const failingScenario = (w: World): void => {
  startProject(w)
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-plan': (wd, a) => {
      AGENTS['temper:temper-plan']!(wd, a)
      const extra = `
- [ ] AC-04 [required]: an untraced behavior holds
  Why: it is proved by a test no task writes
  Validate: scenario — covered by "An untraced behavior holds"
`
      let intent = wd.read(`${SPEC}/intent.md`)
      intent = intent.replace('\n### Constraints', extra + '\n### Constraints')
      intent = intent.replace('## Scenario Coverage Checklist', '```gherkin\nScenario: An untraced behavior holds\n  Given a thing\n  When it runs\n  Then it holds\n  Note: unit\n  Covers: AC-04\n  Test: python3 -c "import sys; sys.exit(3)"\n```\n\n## Scenario Coverage Checklist')
      wd.write(`${SPEC}/intent.md`, intent)
    },
  }
  let seen = ''
  orchestrate(w, script({
    agents,
    person: (ask, wd) => {
      const q = String(ask.question.question)
      if (q.startsWith('Build: the check failed')) {
        seen = q
        return { label: 'Override and continue', note: 'I accept the risk' }
      }
      return asksEveryStage(ask, wd)
    },
    // the person overrode the failed scenario; Check then fails on it for the same reason, which is the end of this scenario
    stopAt: (_wd, n) => n.action === 'ask' && String(n.ask.question.question).startsWith('Check: the check failed'),
  }))
  expect(seen.includes("scenario 'An untraced behavior holds'") && seen.includes('exit 3') && seen.includes('python3 -c'), `the Build question names the scenario, its command and the exit (${seen.slice(0, 200)})`)
}

// WP11: the default run with one failed group (the scenario armed-run). The person takes the recommended option of every
// question, approve-run at the approval. Group G1's check fails once (its Validate also wants a line no task writes, which
// the group fix agent adds): the CLI takes the group fix by rule, and the run goes on by itself to the commit question,
// the only question after the approval. It plans once, never steps back to Plan, and pushes nothing.
export const armedRun = (w: World): void => {
  startProject(w)
  const g1 = 'python3 -m unittest unit.test_ci_shape'
  let groupFixes = 0
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-plan': (wd, a) => {
      AGENTS['temper:temper-plan']!(wd, a)
      wd.write(`${SPEC}/tasks.md`, wd.read(`${SPEC}/tasks.md`).replace(`**Validate:** \`${g1}\``, `**Validate:** \`${g1} && grep -q VERSION src/ci_shape.py\``))
    },
    // agents/build.md: a group fix works in the merged worktree its prompt names
    'temper:temper-build': (wd, a) => {
      const m = /worktree (\S+) \(the merged/.exec(String(a.prompt ?? ''))
      expect(m !== null, `the one Build agent of this run is the group fix (${String(a.prompt ?? '').slice(0, 160)})`)
      groupFixes++
      const wt = path.isAbsolute(m![1]!) ? path.relative(wd.dir, m![1]!) : m![1]!
      const file = path.join(wt, 'src/ci_shape.py')
      wd.write(file, `${(wd.exists(file) ? wd.read(file) : SHAPE_CODE).replace(/\n*$/, '\n')}VERSION = 1\n`)
    },
  }
  const picks: Array<{ question: string; option: string }> = []
  orchestrate(w, script({
    agents,
    person: (ask, wd) => {
      const o = (ask.options as Json[]).find(x => x.recommended === true) ?? (ask.options as Json[])[0]
      picks.push({ question: String(ask.id ?? ''), option: String(o?.id ?? '') })
      return recommended(ask, wd)
    },
  }))
  const flow = w.trace.join('\n')
  const approval = picks.findIndex(p => p.question === 'plan.approve')
  expect(approval >= 0 && picks[approval]!.option === 'approve-run',
    `the recommended option of the approval is approve-run (${picks.map(p => `${p.question}:${p.option}`).join(', ')})`)
  expect((w.counts.launches['temper:temper-plan'] ?? 0) === 1, `temper:temper-plan is launched once (${w.counts.launches['temper:temper-plan'] ?? 0})`)
  expect(groupFixes === 1, `the group fix agent is launched once for the failed group check (${groupFixes})`)
  expect(!/state loop \S+ plan/.test(flow), 'no step back to Plan: an unattended run never plans again')
  expect(picks.slice(approval + 1).map(p => p.question).join(',') === 'commit.confirm',
    `no question between the approval and the commit question (${picks.slice(approval + 1).map(p => p.question).join(', ')})`)
  expect(!/git push|gh pr/.test(flow), 'an unattended run never pushes')
  expect(!w.exists('.temper/build-state.json') && /VERSION = 1/.test(w.sh('git show HEAD:src/ci_shape.py')),
    'the run ended and the change is committed, the group fix with it')
}

// WP20: the baseline turns red after the approval (the scenario red-base-after-approval). The config's test command
// is base.sh, which waits until the first task agent starts and then fails: the baseline, in its own process, is
// running at the approval and ends red while that agent works. The agent waits for the red result, then builds its
// task. No new task agent is launched after it, the work in flight is kept (its task passed), and the run stops with a
// notice (the rule log's stop) and the red base question, where the person stops.
export const BASE_SH = '#!/usr/bin/env bash\n# the base suite: it waits for the first task agent, then fails\ni=0\n' +
  'while [ ! -f "${MOCK_BASE_GATE:-/nonexistent}" ] && [ "$i" -lt 600 ]; do sleep 0.1; i=$((i+1)); done\n' +
  'echo "FAIL: test_base_red expected the final value"\nexit 1\n'
export const redBaseAfterApproval = (w: World): void => {
  const gate = `${w.dir}.base-gate`
  w.env.MOCK_BASE_GATE = gate
  delete w.env.TEMPER_BASELINE_FOREGROUND   // the baseline must run in its own process here
  startProject(w, '', wd => {
    wd.write('base.sh', BASE_SH)
    const cfg = '.claude/temper.config'
    wd.write(cfg, wd.read(cfg).replace(/^ {4}test: .*$/m, '    test: bash base.sh').replace(/^ {4}coverage: .*$/m, '    coverage: bash base.sh'))
    wd.sh('git add -A && git commit -qm "the base suite"')
  })
  const result = (wd: World): string => {
    try {
      return String(wd.json('.temper/evidence/baseline.json').result ?? '')
    } catch {
      return ''
    }
  }
  const tasks: string[] = []   // the baseline's result at each launch of a task agent
  let atApproval = ''
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-build-task': (wd, a) => {
      tasks.push(result(wd))
      if (tasks.length === 1) {
        fs.writeFileSync(gate, '')
        // with no baseline on record there is nothing to wait for (a CLI before WP20)
        for (let i = 0; i < 600 && tasks[0] !== '' && result(wd) !== 'red'; i++) spawnSync('sleep', ['0.1'])
      }
      buildTask(wd, a)
    },
  }
  const asked: string[] = []
  orchestrate(w, script({
    agents,
    // a run that went past Build after the first task agent did not stop at the red base: the checks below say why
    stopAt: (_wd, n) => tasks.length > 0 && ['review', 'check', 'commit'].includes(String(n.stage ?? '')),
    person: (ask, wd) => {
      const id = String(ask.id ?? '')
      asked.push(id)
      if (id === 'plan.approve') atApproval = result(wd)
      if (id === 'base.red') return null   // the person stops at the red base question
      return recommended(ask, wd)
    },
  }))
  expect(atApproval === 'running', `the baseline was still running at the approval, so the approval came first (${atApproval || 'no file'})`)
  expect(tasks.length === 1, `no new task agent is launched once the base is red (${tasks.length} launches, the base at each: ${tasks.join(', ')})`)
  expect(result(w) === 'red', `the baseline ended red while the first task agent worked (${result(w) || 'no file'})`)
  const groups = w.exists('.temper/groups.json') ? w.json('.temper/groups.json') : {}
  expect(groups?.tasks?.['1']?.status === 'passed', `the work in flight is kept: task 1 passed (${JSON.stringify(groups?.tasks?.['1'] ?? null)})`)
  const last = asked[asked.length - 1]
  expect(last === 'base.red' && asked.indexOf('plan.approve') >= 0 && asked.indexOf('plan.approve') < asked.lastIndexOf('base.red'),
    `the run stops with the red base question after the approval (asked ${asked.join(', ')})`)
  let log: Json[] = []
  try {
    const d = w.json('.temper/rule-log.json')
    log = (Array.isArray(d) ? d : Array.isArray(d?.rule_log) ? d.rule_log : []) as Json[]
  } catch {
    log = []
  }
  expect(log.some(e => e?.kind === 'stop' && /base/i.test(String(e?.what ?? ''))),
    `the stop of the run that went on by itself is recorded with a notice that names the red base (${JSON.stringify(log).slice(0, 200)})`)
}

// Save for later stops the run; /temper:temper takes it up again at the same question.
export const saveAndResume = (w: World): void => {
  startProject(w)
  const first = orchestrate(w, script({ person: (ask, wd) => (String(ask.question.question).startsWith('Plan: the check passed') ? 'More options' : String(ask.question.question).includes('more options') ? 'Save for later' : recommended(ask, wd)) }))
  expect(first.action === 'ask' && String(first.ask.question.question).startsWith('Plan: the check passed'), 'the run stopped at the plan question')
  expect(w.exists('.temper/build-state.json'), 'the run state is kept')
  orchestrate(w, script())
  expect(!w.exists('.temper/build-state.json'), 'the resumed run went to its end')
}

// WP14: Design runs only when the person asks for it. A medium plan adds no stage by itself; the person picks the
// option run-design of the approval (in its More list), and Design runs between Plan and Build.
export const designRun = (w: World): void => {
  startProject(w)
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-plan': (wd, a) => {
      AGENTS['temper:temper-plan']!(wd, a)
      t(wd, 'state set complexity medium')
    },
    'temper:temper-design': wd => wd.write(`${SPEC}/design.md`, '# Design: CI report\n\n## Architecture\n\nTwo small modules.\n\n## Areas of Concern\n\nNone flagged — the change is two new files.\n'),
  }
  const asked: string[] = []
  let picked = false
  const byId = (ask: Json, id: string): Json | undefined => (ask.options as Json[]).find(o => o.id === id)
  const person: Person = (ask, wd) => {
    asked.push(String(ask.question.question))
    if (!picked && (ask.id === 'plan.approve' || ask.id === 'plan.approve.more')) {
      const run = byId(ask, 'run-design')
      if (run) {
        picked = true
        return run.label
      }
      const more = byId(ask, 'more')
      if (more && ask.more) return more.label
      throw new Error(`the approval offers no run-design (${(ask.options as Json[]).map(o => o.id).join(', ')})`)
    }
    return recommended(ask, wd)
  }
  orchestrate(w, script({ agents, person }))
  expect(picked, 'the person asked for Design with the option run-design of the approval')
  expect(asked.some(q => q.startsWith('Design: the check passed')), 'the Design question was asked')
  expect(/work:design/.test(w.trace.join('\n')), 'the Design agent ran between Plan and Build')
}

// Three groups: only max-groups (two) start at once; the third waits for a place.
// WP22: the same command on the same tree runs once. The scenario tests run through scen.sh, which writes the
// scenario's name to a count file outside the project before it runs the test, so their runs are told apart from the
// task tests that run the same module (a task's RED and GREEN are not stored, on purpose).
export const threeGroups = (w: World): void => {
  const scenLog = `${w.dir}.scenario-runs`
  fs.writeFileSync(scenLog, '')
  startProject(w, '', wd => {
    wd.write('scen.sh', `echo "$1" >> '${scenLog}'\nexec python3 -m unittest "unit.test_ci_$1"\n`)
    wd.sh('git add scen.sh && git commit -qm "the scenario test runner"')
  })
  const tasks = TASKS_MD.trimEnd() + `

## Group G3: Extra
**Depends:** none
**Validate:** \`python3 -m unittest unit.test_ci_extra\`
**Context:**
Plain python, standard library only.

### Task 3: Extra module
**File:** \`src/ci_extra.py\`, \`unit/test_ci_extra.py\`
**Depends:** none
**Test:** \`python3 -m unittest unit.test_ci_extra\`
**Cases:**
- the extra value is one
- the extra value is an int
**Traced to:** Infrastructure: a third group for the e2e
- [ ] done
`
  const extraTest = 'import unittest\n\nfrom src.ci_extra import VALUE\n\n\nclass ExtraTest(unittest.TestCase):\n    def test_the_extra_value_is_one(self):\n        self.assertEqual(VALUE, 1)\n\n    def test_the_extra_value_is_an_int(self):\n        self.assertIsInstance(VALUE, int)\n'
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-plan': (wd, a) => {
      AGENTS['temper:temper-plan']!(wd, a)
      wd.write(`${SPEC}/tasks.md`, tasks)
      wd.write(`${SPEC}/plan.md`, PLAN_MD.replace('## Files to Modify', '| src/ci_extra.py | an extra module | Infrastructure: a third group for the e2e |\n| unit/test_ci_extra.py | its test | Infrastructure: a third group for the e2e |\n\n## Files to Modify'))
      wd.write(`${SPEC}/intent.md`, wd.read(`${SPEC}/intent.md`).replace(/Test: python3 -m unittest unit\.test_ci_(shape|bytes)\n/g, 'Test: bash scen.sh $1\n'))
    },
    'temper:temper-build-task': chained((wd, n) => {
      if (n !== 3) return buildOne(wd, n)
      const wt = path.relative(wd.dir, worktreeOf(t(wd, 'task show 3').out))
      wd.write(path.join(wt, 'unit/test_ci_extra.py'), extraTest)
      wd.write(path.join(wt, 'src/ci_extra.py'), 'VALUE = None\n')
      expect(t(wd, 'task test 3 --phase red').code !== 0, 'RED fails')
      wd.write(path.join(wt, 'src/ci_extra.py'), 'VALUE = 1\n')
      expect(t(wd, 'task test 3 --phase green').code === 0, 'GREEN passes')
    }),
  }
  orchestrate(w, script({ agents }))
  const starts = w.trace.filter(l => l.includes('group start'))
  expect(starts.length === 3, `all three groups started in the end (${starts.length})`)
  const firstWork = w.trace.findIndex(l => l.includes('group start'))
  const batch = w.trace.slice(firstWork).findIndex((l, i) => i > 0 && !l.includes('group start'))
  expect(batch === 2, `the first batch started two groups (max-groups 2), not ${batch}`)
  // WP22: the whole suite runs at most once per group plus once on the base (the floor's suite_runs), and each scenario
  // test at most twice: once where its task or group first meets it, once on the merged project; Check reuses that
  const suites = w.finalCounts().suite_runs
  expect(suites <= 3 + 1, `W22 the whole suite runs at most once per group plus once on the base (${suites} runs for 3 groups)`)
  const scen = fs.readFileSync(scenLog, 'utf8').split('\n').filter(Boolean)
  const byName = Object.fromEntries(['shape', 'bytes'].map(n => [n, scen.filter(x => x === n).length]))
  expect(scen.length > 0, 'W22 the scenario tests ran through scen.sh (none ran: the intent kept its own Test: lines)')
  expect(Object.values(byName).every(n => n >= 1 && n <= 2), `W22 each scenario test runs at most twice (${JSON.stringify(byName)})`)
}

// Maven (a fake mvn): the declared test classes only, offline, a new surefire report per class; the group verifies with JaCoCo.
export const mavenRun = (w: World): void => {
  const bin = path.join(w.dir, '..', `bin-${path.basename(w.dir)}`)
  fs.mkdirSync(bin, { recursive: true })
  const log = path.join(bin, 'mvn.log')
  const green = path.join(bin, 'green')
  fs.writeFileSync(path.join(bin, 'mvn'), `#!/usr/bin/env bash
printf '%s\\n' "$*" >> "${log}"
for a in "$@"; do
  case "$a" in -Dtest=*) for c in $(echo "\${a#-Dtest=}" | tr ',' ' '); do c="\${c%%#*}"; mkdir -p target/surefire-reports; echo "<testsuite/>" > "target/surefire-reports/TEST-com.acme.$c.xml"; done ;; esac
done
case "$*" in *verify*) exit 0 ;; esac
[ -f "${green}" ] && exit 0 || exit 1
`, { mode: 0o755 })
  w.env.PATH = `${bin}:${w.env.PATH}`
  startProject(w)
  // 9.8.0: Check is the CLI's; this project has no Python tests, so its Check commands are mvn's
  const cfg = path.join(w.dir, '.claude/temper.config')
  fs.writeFileSync(cfg, fs.readFileSync(cfg, 'utf8').replace(`    test: ${SUITE}`, '    test: mvn -q verify').replace(`    coverage: ${SUITE} && echo 'TOTAL 100 10 90%'`, "    coverage: mvn -q verify && echo 'TOTAL 100 10 90%'"))
  const tasks = TASKS_MD
    .replace(/\*\*Validate:\*\* `python3 -m unittest unit\.test_ci_shape`/, '**Validate:** `mvn verify -Pjacoco`')
    .replace(/\*\*Validate:\*\* `python3 -m unittest unit\.test_ci_bytes`/, '**Validate:** `mvn verify -Pjacoco`')
    .replace(`**Integration:** \`${SUITE}\``, '**Integration:** `mvn verify -Pjacoco`')
    .replace('`src/ci_shape.py`, `unit/test_ci_shape.py`', '`src/main/java/com/acme/Shape.java`, `src/test/java/com/acme/ShapeTest.java`')
    .replace('`src/ci_bytes.py`, `unit/test_ci_bytes.py`', '`src/main/java/com/acme/Bytes.java`, `src/test/java/com/acme/BytesTest.java`')
    .replace(/\*\*Test:\*\* `python3 -m unittest unit\.test_ci_(shape|bytes)`/g, '**Test:** `mvn test`')
  const plan = PLAN_MD.replace(/src\/ci_shape\.py/g, 'src/main/java/com/acme/Shape.java').replace(/unit\/test_ci_shape\.py/g, 'src/test/java/com/acme/ShapeTest.java')
    .replace(/src\/ci_bytes\.py/g, 'src/main/java/com/acme/Bytes.java').replace(/unit\/test_ci_bytes\.py/g, 'src/test/java/com/acme/BytesTest.java')
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-plan': (wd, a) => {
      AGENTS['temper:temper-plan']!(wd, a)
      wd.write(`${SPEC}/tasks.md`, tasks)
      wd.write(`${SPEC}/plan.md`, plan)
      // the scenario Test: commands are Maven ones too
      wd.write(`${SPEC}/intent.md`, wd.read(`${SPEC}/intent.md`).replace(/Test: python3 -m unittest unit\.test_ci_\w+/g, 'Test: mvn test'))
    },
    'temper:temper-build-task': chained((wd, n) => {
      const [main, test] = n === 1 ? ['Shape', 'ShapeTest'] : ['Bytes', 'BytesTest']
      const wt = path.relative(wd.dir, worktreeOf(t(wd, `task show ${n}`).out))
      fs.rmSync(green, { force: true })
      wd.write(path.join(wt, `src/test/java/com/acme/${test}.java`), `package com.acme;\npublic class ${test} {}\n`)
      // 9.8.5 (Q4): a stub at RED, the code before GREEN (a RED on the final code is no failing-first proof)
      wd.write(path.join(wt, `src/main/java/com/acme/${main}.java`), `package com.acme;\npublic class ${main} { /* stub */ }\n`)
      expect(t(wd, `task test ${n} --phase red`).code !== 0, 'RED fails')
      wd.write(path.join(wt, `src/main/java/com/acme/${main}.java`), `package com.acme;\npublic class ${main} { int v() { return 1; } }\n`)
      fs.writeFileSync(green, '')
      const g = t(wd, `task test ${n} --phase green`)
      expect(g.code === 0, `GREEN passes with a new report for the class (${g.out.slice(0, 200)})`)
    }),
  }
  orchestrate(w, script({ agents }))
  const calls = fs.readFileSync(log, 'utf8')
  expect(/-o /.test(calls) && /-Dtest=ShapeTest/.test(calls) && /-Dtest=BytesTest/.test(calls), `Maven ran offline with only the declared classes (${calls.slice(0, 300)})`)
  expect(/verify -Pjacoco/.test(calls) || /-Pjacoco/.test(calls), 'the group verified with JaCoCo')
}

// WP16: one group check fails once, then `integrate` fails once, in a default run (the person approves with the
// recommended option and takes it at every question). Each failure is a verdict the CLI asks or repairs next: in driver
// mode the trace holds no hand back and ends `driver done`; in plain and mod mode the same questions are asked (the
// question ids of each mode, compared with every mode run before it in this process).
const G1_CHECK = 'python3 -m unittest unit.test_ci_shape'
const FAILED_CHECKS_ASKED = new Map<string, string>()
export const failedChecks = (w: World): void => {
  startProject(w)
  // every verdict a call recorded: the markers of the calls the world ran, and those `temper go` read
  const verdicts: string[] = []
  const run = w.run.bind(w)
  w.run = (command: string, cwd?: string) => {
    const r = run(command, cwd)
    for (const m of r.out.matchAll(/^VERDICT: (\S+) (PASS|FAIL|PARKED)$/gm)) verdicts.push(`${m[1]} ${m[2]}`)
    if (command === `${TEMPER} go` || command.startsWith(`${TEMPER} go `)) {
      try {
        const out = JSON.parse(r.out.trim().split('\n').pop() ?? '') as Json
        for (const v of (out.verdicts ?? []) as Json[]) verdicts.push(`${v.scope} ${v.verdict}`)
      } catch {
        // no JSON line: temper go printed an error, which the driver reports
      }
    }
    return r
  }
  const fixes = { group: 0, integrate: 0 }
  const agents: Record<string, Agent> = {
    ...AGENTS,
    // the plan: G1's check also wants a line no task writes, and so does the Integration command
    'temper:temper-plan': (wd, a) => {
      AGENTS['temper:temper-plan']!(wd, a)
      wd.write(`${SPEC}/tasks.md`, wd.read(`${SPEC}/tasks.md`)
        .replace(`**Validate:** \`${G1_CHECK}\``, `**Validate:** \`${G1_CHECK} && grep -q VERSION src/ci_shape.py\``)
        .replace(`**Integration:** \`${SUITE}\``, `**Integration:** \`${SUITE} && grep -q VERSION src/ci_bytes.py\``))
    },
    // the one fix agent: on the group's merged work it adds the line G1's check wants; after the failed integrate it
    // adds the line the Integration command wants
    'temper:temper-build': (wd, a) => {
      const m = /worktree (\S+) \(the merged/.exec(String(a.prompt ?? ''))
      if (m !== null) {
        const wt = path.isAbsolute(m[1]!) ? path.relative(wd.dir, m[1]!) : m[1]!
        const file = path.join(wt, 'src/ci_shape.py')
        wd.write(file, `${(wd.exists(file) ? wd.read(file) : SHAPE_CODE).replace(/\n*$/, '\n')}VERSION = 1\n`)
        fixes.group++
      } else {
        wd.write('src/ci_bytes.py', `${wd.read('src/ci_bytes.py').replace(/\n*$/, '\n')}VERSION = 1\n`)
        fixes.integrate++
      }
    },
  }
  const asked: string[] = []
  const end = orchestrate(w, script({
    agents,
    person: (ask, wd) => {
      asked.push(String(ask.id ?? ''))
      return recommended(ask, wd)
    },
  }))
  const count = (v: string): number => verdicts.filter(x => x === v).length
  expect(count('group:G1 FAIL') === 1 && count('integrate FAIL') === 1,
    `the group check of G1 failed once and integrate failed once (${verdicts.join(', ')})`)
  expect(fixes.group >= 1 && fixes.integrate >= 1, `each failure got its repair (group ${fixes.group}, integrate ${fixes.integrate})`)
  expect(w.counts.handbacks === 0, `a failed group check and a failed integrate hand nothing back (${w.counts.handbacks} hand backs)`)
  expect(end.action === 'none', `the run goes on to its end (last action ${end.action})`)
  if (w.mode === 'driver') {
    const ends = w.trace.filter(l => l.startsWith('  driver '))
    expect(!ends.some(l => l.startsWith('  driver handback')), `the driver hands nothing back (${ends.join('; ')})`)
    expect((ends.at(-1) ?? '').startsWith('  driver done'), `the trace ends driver done (${ends.at(-1) ?? 'no driver end'})`)
  }
  const ids = asked.join(',')
  for (const [mode, other] of FAILED_CHECKS_ASKED)
    expect(other === ids, `the same questions are asked in ${w.mode} mode as in ${mode} mode (${ids}; ${other})`)
  FAILED_CHECKS_ASKED.set(w.mode, ids)
}

// A /temper:fix run: RCA, Fix (a regression test first), Review, Check and the commit; the mod stands aside for it.
// WP17: a clean bug run asks twice: the root cause with the fix it proposes (rca.approve, the approval: Approve and fix
// makes the fix branch off main and starts the run to the commit), then the commit (commit.confirm); its commit is on
// fix/bug, in driver mode too. The harness clears the run startProject began as the person would, outside the run.
export const fixRun = (w: World): void => {
  startProject(w, '', wd => {
    wd.write('src/ci_shape.py', 'def stage_object(stage, verdict, requirements):\n    return {"stage": stage}\n')
    wd.sh('git add -A && git commit -qm "a shape with a bug"')
  })
  w.sh(`${TEMPER} state clear`)
  // commands/fix.md starts the run with the bug as typed; with the mod's run driver, the driver starts it itself
  if (w.mode !== 'driver') w.sh(`${TEMPER} state init bug --command fix --feature 'the shape drops the verdict'`)
  const bug = '.temper/specs/bug'
  let atReview = ''
  const agents: Record<string, Agent> = {
    'temper:temper-rca': wd => wd.write(`${bug}/rca.md`, '# RCA: the shape drops the verdict\n\n## Root cause\n\n`stage_object` returns only the stage.\n\n## Fix\n\nReturn verdict and requirements.\n'),
    // 9.8.5 (Q3): the CLI runs the regression test (evidence run), as agents/fix.md says; a claimed run counts nowhere
    'temper:temper-fix': wd => {
      wd.write('unit/test_ci_shape.py', SHAPE_TEST)
      const red = t(wd, `evidence run --stage build --phase red --claim 'regression test: the shape keeps its verdict' -- python3 -m unittest unit.test_ci_shape`)
      expect(/exit [1-9]/.test(red.out), `the regression test fails first (${red.out.slice(0, 200)})`)
      wd.write('src/ci_shape.py', SHAPE_CODE)
      const green = t(wd, `evidence run --stage build --phase green --claim 'regression test: the shape keeps its verdict' -- python3 -m unittest unit.test_ci_shape`)
      expect(/exit 0\b/.test(green.out), `the fix passes the regression test (${green.out.slice(0, 200)})`)
    },
    // WP23: the first Review launch reads what the Fix agent's after calls left in the Build ledger: the suite the CLI
    // ran (check build-checks), before any Review is paid for
    'temper:temper-review': wd => {
      if (atReview === '') {
        const rows = (wd.exists('.temper/evidence/build.json') ? wd.json('.temper/evidence/build.json') : []) as unknown as Json[]
        const suite = (Array.isArray(rows) ? rows : []).filter(r => r?.claim === 'Integration suite' && r?.executed_by === 'cli')
        atReview = suite.length > 0 ? `suite exit ${suite[suite.length - 1]!.exit_code}` : 'no suite row the CLI ran'
      }
      reviewDone(wd)
    },
    'temper:temper-check': wd => {
      t(wd, `evidence add --stage check --claim 'tests' --exit 0 --cmd 'python3 -m unittest discover -s unit -t .'`)
      t(wd, `evidence add --stage check --claim 'coverage' --value 90 --exit 0 --cmd 'coverage report'`)
    },
  }
  const asked: string[] = []
  const ids: string[] = []
  const fixScript = script({
    agents,
    person: (ask, wd) => {
      asked.push(String(ask.question.question))
      ids.push(String(ask.id))
      return recommended(ask, wd)
    },
    instruction: (wd, text) => {
      if (text.startsWith('Append one entry for this fix')) {
        wd.write('.temper/lessons.md', '# Lessons\n\n- the shape must keep its verdict: a regression test names it\n')
        return true
      }
      return /each file the run changed|^Copy what|^When .* records deviations/.test(text)
    },
  })
  if (w.mode === 'driver') {
    orchestrateFix(w, fixScript, 'the shape drops the verdict', 'bug')
  } else {
    // commands/fix.md launches the RCA agent itself; the loop over `temper next` starts at its question, whose card
    // shows the root cause and the fix (no RCA panel is printed)
    launchByHand(w, agents, 'temper:temper-rca')
    orchestrate(w, fixScript)
  }
  expect(atReview === 'suite exit 0', `W23 the suite ran before the Review agent was launched: the Fix agent's after calls left the CLI's suite row in the Build ledger (${atReview || 'no Review launch'})`)
  expect(asked[0] === 'RCA: the root cause and the proposed fix are on the card. Approve the fix?', `the RCA question is the approval (${asked[0] ?? 'not asked'})`)
  expect(ids.join(',') === 'rca.approve,commit.confirm' && w.counts.dialogs === 2,
    `the bug run asks the root cause with the fix, then the commit, and nothing else (${ids.join(', ')}; ${w.counts.dialogs} dialogs)`)
  expect(w.sh('git log --format=%s -n 1').length > 0 && !w.exists('.temper/build-state.json'), 'the fix run ended with its commit')
  const branch = w.sh('git branch --show-current').trim()
  const own = Number(w.run('git rev-list --count main..HEAD').out.trim() || '0')
  expect(branch === 'fix/bug' && own > 0 && w.sh('git log --format=%s -n 1').startsWith('fix(bug):'),
    `the fix is committed on fix/bug, off main (on ${branch}, ${own} commits beyond main: ${w.sh('git log --format=%s -n 1').trim()})`)
}

// WP23: a fault of the environment met when Build ends, in a run that goes on by itself (the person approved with
// the recommended approve-run). The suite passes on the base and at every group; once the last task agent returned,
// its setup line fails (`temper-setup: FAIL`, exit 125), so `integrate` meets the fault. The run makes a recorded
// stop at Build and asks the setup question; no fix agent is launched for it. The person repairs the environment (the
// flag goes) and answers check-again: integrate and the Build gate run again, pass, and the run goes on to the commit.
export const setupAtBuild = (w: World): void => {
  const down = `${w.dir}.env-down`
  startProject(w, '', wd => {
    wd.write('suite.sh', `[ -f '${down}' ] && { echo 'temper-setup: FAIL (exit 1)'; exit 125; }\n${wd.read('suite.sh')}`)
    wd.sh('git add suite.sh && git commit -qm "the suite meets the setup line"')
  })
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-build-task': (wd, a) => {
      buildTask(wd, a)
      if (tasksOf(a).includes(2)) fs.writeFileSync(down, '')
    },
  }
  const met: string[] = []
  let stopped = ''
  let mode = ''
  let ids: string[] = []
  let said = ''
  const end = orchestrate(w, script({
    agents,
    stopAt: (_wd, n) => n.stage === 'commit',
    person: (ask, wd) => {
      const id = String(ask.id ?? '')
      met.push(id)
      if (!id.startsWith('build.')) return recommended(ask, wd)
      if (ids.length === 0) {
        ids = ((ask.options ?? []) as Json[]).concat(((ask.more?.options ?? []) as Json[])).map(o => String(o.id ?? ''))
        said = String(ask.question?.question ?? '')
        const log = (wd.exists('.temper/rule-log.json') ? wd.json('.temper/rule-log.json') : []) as unknown as Json[]
        stopped = (Array.isArray(log) ? log : []).some(e => e?.kind === 'stop' && e?.stage === 'build') ? 'recorded' : 'not recorded'
        mode = String(wd.json('.temper/build-state.json').run_mode ?? '')
      }
      if (fs.existsSync(down)) fs.unlinkSync(down)   // the person repairs the environment
      // with no check-again to pick the person stops here, and the checks below say what the question was
      return ids.includes('check-again') ? pickId(wd, ask, 'check-again') : null
    },
  }))
  const builds = met.filter(i => i.startsWith('build.'))
  expect(builds.length === 1, `W23 the fault at integrate asks one question at Build (${met.join(', ')})`)
  expect(['check-again', 'it-is-the-code', 'save'].every(i => ids.includes(i)) && /SETUP/.test(said),
    `W23 it is the setup question: SETUP, with check-again, it-is-the-code and save (${ids.join(', ')}: ${said.slice(0, 160)})`)
  expect(stopped === 'recorded' && mode === 'autonomous', `W23 the unattended run made a recorded stop there (${stopped}, run_mode ${mode || 'unset'})`)
  expect((w.counts.launches['temper:temper-build'] ?? 0) === 0, `W23 no fix agent is launched for a fault of the environment (${w.counts.launches['temper:temper-build'] ?? 0})`)
  expect(end.stage === 'commit', `W23 after the repair and check-again the run goes on to the commit (${end.action} ${end.stage ?? ''})`)
}

// WP17: a trivial request is a verdict the CLI records. The Intent agent calls `temper intent trivial --why TEXT`,
// changes one line of one file and returns; the flow closes the run by its own call (`intent trivial --close`), with no
// question. The change is not committed: the commit is the person's, and the commit hook holds it to the bound.
export const trivialRun = (w: World): void => {
  startProject(w)
  const agents: Record<string, Agent> = {
    'temper:temper-intent': wd => {
      const v = t(wd, "intent trivial --why 'the README title is one word to capitalize'")
      expect(v.code === 0, `the CLI recorded the trivial verdict (${v.out.trim().slice(0, 200)})`)
      wd.write('README.md', '# Scratch\n')
    },
  }
  const asked: string[] = []
  orchestrate(w, script({ agents, person: ask => { asked.push(String(ask.id)); return null } }))
  expect(asked.length === 0 && w.counts.dialogs === 0, `a trivial request asks nothing (${asked.join(', ')}; ${w.counts.dialogs} dialogs)`)
  expect(!w.exists('.temper/build-state.json'), 'no run is active after the flow closed the trivial request')
  expect(w.exists('.temper/trivial.json'), 'the trivial record is kept for the commit hook')
  const head = w.sh('git log --format=%s -n 1').trim()
  const diff = w.sh('git diff --numstat').trim()
  expect(head === 'config' && diff === '1\t1\tREADME.md', `the one line change is left uncommitted (last commit: ${head}; diff: ${diff})`)
}

// The run's branch exists from an earlier run: the approval continues on it, and its switch carries the new spec files
// across through a temp folder (WP12). The mod lets the call through whole, as the CLI wrote it (the only Temper path it
// writes is the spec folder).
export const branchClashCarry = (w: World): void => {
  startProject(w, '', wd => {
    wd.sh('git checkout -q -b feature/ci && echo old > old.txt && git add old.txt && git commit -qm "an earlier run" && git checkout -q main')
  })
  orchestrate(w, script({ person: recommended }))
  expect(w.sh('git branch --show-current').trim() === 'feature/ci', 'the run went on the earlier branch')
  expect(w.sh('git log --format=%s feature/ci').includes('docs(plan): accept the intent and approve the plan of ci'), 'the intent and the plan were approved and committed there, with the new spec files carried across')
  expect(w.exists('old.txt') || !w.exists('.temper/build-state.json'), 'the earlier work is on the branch')
}

// 9.7.6, the fresh review of a medium plan: the reviewer finds a task that leaves the expected value to the builder; the person
// chooses Revise the plan; the Plan agent fixes tasks.md; the review runs again on the new text, passes, and the run goes on.
const FIX_FINDING: FreshFinding = { lens: 'readiness', severity: 'high', claim: 'Task 2: the Case "two stages are written in the order" names no expected value' }
const mediumPlan = (wd: World, a: Json): void => {
  AGENTS['temper:temper-plan']!(wd, a)
  t(wd, 'state set complexity medium')
}
const designAgent: Agent = wd => wd.write(`${SPEC}/design.md`, '# Design: CI report\n\n## Architecture\n\nTwo small modules.\n\n## Areas of Concern\n\nNone flagged — the change is two new files.\n')
export const freshReview = (w: World): void => {
  startProject(w, 'plan:\n  fresh-review: auto')
  const prompts: string[] = []
  let reviews = 0
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-plan': (wd, a) => {
      prompts.push(String(a.prompt))
      mediumPlan(wd, a)
      if (String(a.prompt).includes('Fresh review findings to answer'))
        wd.write(`${SPEC}/tasks.md`, wd.read(`${SPEC}/tasks.md`).replace('- two stages are written in the order the ledger holds them',
          '- two stages are written in the order the ledger holds them: build first, then review, as a JSON array'))
    },
    'temper:temper-plan-review': (wd, a) => { reviews++; freshReviewer(wd, a, reviews === 1 ? [FIX_FINDING] : []) },
    'temper:temper-design': designAgent,
  }
  const asked: string[] = []
  orchestrate(w, script({ agents, person: (ask, wd) => { asked.push(String(ask.question.question)); return recommended(ask, wd) } }))
  expect(reviews === 2, `the fresh review ran twice, once on each tasks.md (${reviews})`)
  expect(asked.some(q => q.startsWith('Plan: the check failed') && q.includes('no open plan blockers') && q.includes('Revise the plan?')), 'the plan question named the blocker and offered Revise the plan')
  expect(prompts.length === 2 && prompts[1]!.includes('Fresh review findings to answer') && prompts[1]!.includes('names no expected value'), 'the Plan agent ran again with the finding')
  expect(asked.some(q => q.startsWith('Plan: the check passed. A reader with no context took it as: two modules build a CI report')), 'the plan question showed the paraphrase')
  expect(!w.exists('.temper/build-state.json'), 'the run went to its end')
}

// A reviewer that stops before a lens is done is not run, never zero findings: the gate fails and names the lens, and the run
// launches it only when the person asks for it again.
export const freshNotRun = (w: World): void => {
  startProject(w, 'plan:\n  fresh-review: auto')
  let reviews = 0
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-plan': mediumPlan,
    'temper:temper-plan-review': (wd, a) => { reviews++; freshReviewer(wd, a, [], reviews === 1 ? ['comprehension'] : []) },
    'temper:temper-design': designAgent,
  }
  const asked: string[] = []
  orchestrate(w, script({ agents, person: (ask, wd) => { asked.push(String(ask.question.question)); return recommended(ask, wd) } }))
  expect(asked.some(q => q.includes('not run: comprehension A') && q.includes('Run the fresh review again?')), 'the gate named the lens that did not run')
  expect(reviews === 2, `the reviewer ran again only on the person's answer (${reviews})`)
  expect(!w.exists('.temper/build-state.json'), 'the run went to its end')
}

// The author contests a finding with a citation the CLI checks; the finding stays open, and the person accepts it with that citation.
export const freshContest = (w: World): void => {
  startProject(w, 'plan:\n  fresh-review: auto')
  let reviews = 0
  let lastAsk: Json = {}
  const refused: string[] = []
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-plan': (wd, a) => {
      mediumPlan(wd, a)
      const id = /#(\d+) \[high\]/.exec(String(a.prompt))?.[1]
      if (id) {
        const bad = t(wd, `evidence contest --stage plan --id ${id} --cite src/nothing.py --quote 'it is intentional here' --reason 'it is intentional'`)
        if (bad.code !== 0) refused.push(bad.out)
        const ok = t(wd, `evidence contest --stage plan --id ${id} --cite .gitignore:1 --quote '__pycache__/' --reason 'the project ignores its byte code, so no new module is needed'`)
        expect(ok.code === 0, `the contest with a real citation was recorded (${ok.out})`)
      }
    },
    'temper:temper-plan-review': (wd, a) => { reviews++; freshReviewer(wd, a, reviews === 1 ? [{ lens: 'zoom-out', severity: 'high', claim: 'src/ci_bytes.py: a byte order module is not needed' }] : []) },
    'temper:temper-design': designAgent,
  }
  orchestrate(w, script({
    agents,
    person: (ask, wd) => {
      lastAsk = ask
      const q = String(ask.question.question)
      if (q.startsWith('Plan: the check failed') && q.includes('contested')) return 'Accept a finding'
      return recommended(ask, wd)
    },
    instruction: (wd, text) => {
      if (text === 'Ask the accept question.') {
        const aq = lastAsk.accept as Json
        const opt = (aq.options as Json[]).find(o => String(o.label).startsWith('Accept finding'))!
        expect(String(opt.description).startsWith('[contested]'), 'the accept option marks the contested finding')
        expect(opt.reason_question.options[0].label === 'Contested with evidence: .gitignore:1', 'the first reason is the checked citation')
        expect(opt.reason_question.options[1].label === 'The quoted text answers it: __pycache__/', 'the second reason is the checked quote')
        wd.answer(aq, opt.label, 'Contested with evidence: .gitignore:1')
        // the option's gate call records a verdict: the Context check the plan still waits for fails it, and the next
        // question asks that check
        runCalls(wd, opt.calls, { reason: 'Contested with evidence: .gitignore:1' }, 'any')
        return true
      }
      return /each file the run changed|^Copy what|^When .* records deviations/.test(text)
    },
  }))
  expect(refused.length === 1 && refused[0]!.includes('no file src/nothing.py') && refused[0]!.includes('escalate'), `a contest with no readable citation was refused (${refused.join(' / ')})`)
  expect(reviews === 1, 'a contest leaves tasks.md as it was, so the review does not run again')
  expect(!w.exists('.temper/build-state.json'), 'the run went to its end')
}

// plan.fresh-review: ask (the default): nothing runs by itself; the person chooses Fresh review first at the plan question, the
// reviewer runs with the CLI's launch mark before it, and the plan question comes back with the reader's paraphrase.
export const freshAsk = (w: World): void => {
  startProject(w)
  let reviews = 0
  const asked: string[] = []
  const agents: Record<string, Agent> = { ...AGENTS, 'temper:temper-plan': mediumPlan, 'temper:temper-plan-review': (wd, a) => { reviews++; freshReviewer(wd, a, []) }, 'temper:temper-design': designAgent }
  orchestrate(w, script({
    agents,
    person: (ask, wd) => {
      const q = String(ask.question.question)
      asked.push(q)
      if (q.startsWith('Plan: the check passed') && reviews === 0) return 'Fresh review first'
      return recommended(ask, wd)
    },
  }))
  expect(reviews === 1, `the reviewer ran once, on the person's answer (${reviews})`)
  expect(asked.filter(q => q.startsWith('Plan: the check passed')).length === 2, 'the plan question was asked before and after the review')
  expect(asked.some(q => q.includes('A reader with no context took it as: two modules build a CI report')), 'the second plan question carries the paraphrase')
  expect(/plan fresh start/.test(w.trace.join('\n')), 'the launch was marked by the CLI before the reviewer ran')
  expect(!w.exists('.temper/build-state.json'), 'the run went to its end')
}

// WP08 (M1, row D41): after a loop back from Review, the fix pass commits a change that breaks the Integration suite.
// integrate records the failure and the run asks the Build question; the second pass repairs the code, integrate
// passes again on the merged tree, and the run reaches the commit. No call tries to merge a group branch the first pass
// deleted.
const SHAPE_BROKEN = 'def stage_object(stage, verdict, requirements):\n    return {"stage": stage, "verdict": verdict}\n'
const CALLER_TEST = '\n    def test_the_stage_object_drops_the_caller_list(self):\n' +
  "        self.assertNotIn('requirements', stage_object('build', 'PASS', [{'name': 'a'}]))\n"
export const fixBreaksSuite = (w: World): void => {
  startProject(w)
  const merged: string[] = []
  const run = w.run.bind(w)
  w.run = (command: string, cwd?: string) => {
    const r = run(command, cwd)
    if (r.out.includes('not something we can merge')) {
      merged.push(command)
      throw new Error(`M1: a call failed with "not something we can merge": ${command.replace(/^\S*\/scripts\/temper /, 'temper ')}\n${r.out.slice(0, 300)}`)
    }
    return r
  }
  let reviews = 0
  let fixes = 0
  const asked: string[] = []
  const agents: Record<string, Agent> = {
    ...AGENTS,
    // the scripted reviewer: one High finding on its first review, none after
    'temper:temper-review': wd => {
      reviews++
      if (reviews === 1)
        t(wd, "evidence add --stage review --severity high --label PROVEN --claim 'src/ci_shape.py:2 the stage object keeps the caller list'")
      reviewDone(wd)
    },
    // the scripted fix agent: its first pass misreads the finding, writes a regression test that the stage object drops
    // the caller list (RED), and a change that passes it (GREEN) and breaks the shape tests (so the Integration suite);
    // it runs only the test it wrote. Its second takes the wrong test and change back and runs the shape tests. Each
    // records its runs with the CLI (a loop back cleared Build's rows, so the first records RED then GREEN, as
    // agents/build.md step 2 tells a fix pass) and commits its change on the feature branch, as steps 4 and 5 tell it
    // (git add and git commit in two calls; the commit hook takes it as a build checkpoint). The git calls are a
    // subagent's: the mod's guard holds them (rules.ts), not the rules of the session.
    'temper:temper-build': wd => {
      fixes++
      const own = 'unit.test_ci_shape.ShapeTest.test_the_stage_object_drops_the_caller_list'
      if (fixes === 1) {
        wd.write('unit/test_ci_shape.py', `${wd.read('unit/test_ci_shape.py').replace(/\n*$/, '\n')}${CALLER_TEST}`)
        const red = t(wd, `evidence run --stage build --phase red --claim 'unit tests' -- python3 -m unittest ${own}`)
        expect(/exit [1-9]/.test(red.out), `the fix agent's regression test failed first (${red.out.slice(0, 200)})`)
      } else wd.write('unit/test_ci_shape.py', SHAPE_TEST)
      wd.write('src/ci_shape.py', fixes === 1 ? SHAPE_BROKEN : SHAPE_CODE)
      const green = t(wd, `evidence run --stage build --phase green --claim 'unit tests' -- python3 -m unittest ${fixes === 1 ? own : 'unit.test_ci_shape'}`)
      expect(/exit 0\b/.test(green.out), `the fix agent's own test run passed (${green.out.slice(0, 200)})`)
      const add = 'git add src/ci_shape.py unit/test_ci_shape.py'
      for (const c of [add, `git commit -q -m 'fix(ci): pass ${fixes} of the stage object'`]) {
        wd.guard({ tool: 'Bash', input: { command: c } })
        const r = wd.run(c)
        expect(r.code === 0, `the fix agent's call ran: ${c} (${r.out.slice(0, 200)})`)
      }
    },
  }
  const end = orchestrate(w, script({
    agents,
    person: (ask, wd) => {
      asked.push(String(ask.id ?? ''))
      return asksEveryStage(ask, wd)
    },
    afterFailStops: true,
    stopAt: (_wd, n) => n.stage === 'commit',
  }))
  expect(merged.length === 0, `no call failed with "not something we can merge" (${merged.join(', ')})`)
  expect(fixes === 2 && (w.counts.launches['temper:temper-build'] ?? 0) === 2, `the fix agent ran twice (${fixes} passes, ${w.counts.launches['temper:temper-build'] ?? 0} launches)`)
  // the question of the broken suite itself, after the first failed Review: build.pass is asked at every Build gate
  const firstReviewFail = asked.indexOf('review.fail')
  expect(firstReviewFail >= 0 && asked.slice(firstReviewFail + 1).includes('build.fail'), `the failed suite asked the Build question (${asked.join(', ')})`)
  expect(end.stage === 'commit', `the run reached the commit (${end.action} ${end.stage ?? ''})`)
  expect(String(w.json('.temper/groups.json').integration?.verdict ?? '') === 'PASS', 'integrate passed again on the repaired tree')
}

// 9.8.5 (WP08, U21): the run to the commit end to end, plain and mod mode (driver mode is WP09's: `temper go` reports a
// failed group gate as an error and the driver hands the run back). WP11: the key autonomy.policy is gone; this is a
// default run, the template's park-on-touch and max-blast-radius apply. The person takes the recommended option of the
// approval, approve-run; group G1's check fails once (its Validate also wants a line no task writes, which the group fix
// agent adds); the first Review leaves one High finding, which fails Review (block-on critical, high) and is repaired by
// the one loop back to Build the rule takes. The run plans once, launches the group fix once, never steps back to Plan,
// asks nothing between the approval and the commit question, and commits the change.
export const policyRun = (w: World): void => {
  startProject(w)
  const g1 = 'python3 -m unittest unit.test_ci_shape'
  const REPAIRED = 'the caller list is copied'
  let reviews = 0
  let groupFixes = 0
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-plan': (wd, a) => {
      AGENTS['temper:temper-plan']!(wd, a)
      wd.write(`${SPEC}/tasks.md`, wd.read(`${SPEC}/tasks.md`).replace(`**Validate:** \`${g1}\``, `**Validate:** \`${g1} && grep -q VERSION src/ci_shape.py\``))
    },
    // agents/build.md: a group fix works in the merged worktree its prompt names. The fix pass of the loop back from
    // Review has no worktree: test first, it records RED and GREEN with evidence run (the CLI runs the check) around
    // the repair of the finding.
    'temper:temper-build': (wd, a) => {
      const m = /worktree (\S+) \(the merged/.exec(String(a.prompt ?? ''))
      if (m === null) {
        const check = `-- grep -q '${REPAIRED}' src/ci_shape.py`
        t(wd, `evidence run --stage build --claim 'unit tests' --phase red ${check}`)
        wd.write('src/ci_shape.py', `${wd.read('src/ci_shape.py').replace(/\n*$/, '\n')}# ${REPAIRED}\n`)
        t(wd, `evidence run --stage build --claim 'unit tests' --phase green ${check}`)
        return
      }
      groupFixes++
      const wt = path.isAbsolute(m[1]!) ? path.relative(wd.dir, m[1]!) : m[1]!
      const file = path.join(wt, 'src/ci_shape.py')
      wd.write(file, `${(wd.exists(file) ? wd.read(file) : SHAPE_CODE).replace(/\n*$/, '\n')}VERSION = 1\n`)
    },
    // the reviewer reports the High finding while the code has it
    'temper:temper-review': wd => {
      reviews++
      if (!wd.read('src/ci_shape.py').includes(REPAIRED))
        t(wd, "evidence add --stage review --severity high --label PROVEN --claim 'src/ci_shape.py:2 the stage object keeps the caller list, so a later change to that list changes the report'")
      reviewDone(wd)
    },
  }
  const ids: string[] = []
  const picked: string[] = []
  orchestrate(w, script({
    agents,
    person: (ask, wd) => {
      ids.push(String(ask.id ?? ''))
      if (ask.id === 'plan.approve') picked.push(String((ask.options as Json[]).find(o => o.recommended === true)?.id ?? ''))
      return recommended(ask, wd)
    },
  }))
  const flow = w.trace.join('\n')
  const approval = ids.indexOf('plan.approve')
  expect(approval >= 0 && picked[0] === 'approve-run', `the person took approve-run, the recommended option of the approval (${ids.join(', ')}; ${picked.join(', ')})`)
  expect((w.counts.launches['temper:temper-plan'] ?? 0) === 1, `temper:temper-plan is launched once (${w.counts.launches['temper:temper-plan'] ?? 0})`)
  expect(groupFixes === 1, `the group fix agent is launched once for the failed group check (${groupFixes})`)
  expect(!/state loop build plan/.test(flow), 'no call state loop build plan: the run never steps back to Plan by rule')
  expect(reviews === 2 && (flow.match(/state loop review build/g) ?? []).length === 1,
    `the High finding loops back to Build once and Review runs again (${reviews} reviews)`)
  expect(ids.slice(approval + 1).join(',') === 'commit.confirm', `no question between the approval and the commit question (${ids.slice(approval + 1).join(', ')})`)
  expect(!w.exists('.temper/build-state.json') && w.sh('git log --format=%s -1 -- src/ci_shape.py').trim() !== '' && /VERSION = 1/.test(w.sh('git show HEAD:src/ci_shape.py')),
    'the run ended and the change is committed, the group fix with it')
}

// 9.8.5 (WP19): coverage judged against the project. A stand-in for coverage.py (the module the CLI runs as
// `python3 -m coverage`, found through PYTHONPATH outside the project) traces the lines that ran and writes its
// report in coverage.py's JSON shape, so the Check of the Python project has line data. The config names no Check command, so
// the CLI detects the stack and runs that tool; the base value is written by hand, as WP20's baseline writes it.
export const FAKE_COVERAGE = `import fnmatch, json, os, runpy, sys, threading, types

DATA = ".coverage"


def executable(path):
    try:
        code = compile(open(path, encoding="utf-8").read(), path, "exec")
    except (OSError, SyntaxError, ValueError):
        return set()
    lines, todo = set(), [code]
    while todo:
        c = todo.pop()
        lines.update(n for _, _, n in c.co_lines() if n)
        todo.extend(k for k in c.co_consts if isinstance(k, types.CodeType))
    return lines


def run(args):
    omit, append, i = [], False, 0
    while i < len(args) and args[i] != "-m":
        if args[i].startswith("--omit="):
            omit = [x for x in args[i][7:].split(",") if x]
        elif args[i] == "-a":
            append = True
        i += 1
    module, rest, root, seen = args[i + 1], args[i + 2:], os.getcwd() + os.sep, {}
    try:
        old = json.load(open(DATA)) if append else {}
    except (OSError, ValueError):
        old = {}

    def tracer(frame, event, arg):
        f = frame.f_code.co_filename
        if f.startswith(root):
            seen.setdefault(f[len(root):], set()).add(frame.f_lineno)
        return tracer

    sys.argv = [module] + rest
    sys.settrace(tracer)
    threading.settrace(tracer)
    code = 0
    try:
        runpy.run_module(module, run_name="__main__", alter_sys=True)
    except SystemExit as e:
        code = e.code if isinstance(e.code, int) else (0 if e.code is None else 1)
    finally:
        sys.settrace(None)
    files = old.get("files", {})
    for f, ls in seen.items():
        files[f] = sorted(set(files.get(f, [])) | ls)
    json.dump({"files": files, "omit": omit or old.get("omit", [])}, open(DATA, "w"))
    return code


def report(args):
    out = args[args.index("-o") + 1]
    try:
        data = json.load(open(DATA))
    except (OSError, ValueError):
        data = {"files": {}, "omit": []}
    files, total, ran = {}, 0, 0
    for d, dirs, names in os.walk("."):
        dirs[:] = sorted(x for x in dirs if not x.startswith(".") and x != "__pycache__")
        for n in sorted(names):
            rel = os.path.relpath(os.path.join(d, n), ".")
            if not n.endswith(".py") or any(fnmatch.fnmatch(rel, p) for p in data.get("omit", [])):
                continue
            lines = executable(rel)
            hit = sorted(lines & set(data["files"].get(rel, [])))
            miss = sorted(lines - set(hit))
            total, ran = total + len(lines), ran + len(hit)
            files[rel] = {"executed_lines": hit, "missing_lines": miss,
                          "summary": {"covered_lines": len(hit), "num_statements": len(lines)}}
    pct = 100.0 * ran / total if total else 100.0
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    json.dump({"files": files, "totals": {"covered_lines": ran, "num_statements": total, "percent_covered": pct}},
              open(out, "w"))
    print("TOTAL %d %d %d%%" % (total, total - ran, round(pct)))
    return 0


def main(argv):
    if argv[:1] == ["--version"]:
        print("Coverage.py, version 7.0.0 (the e2e stand-in)")
        return 0
    if argv[:1] == ["run"]:
        return run(argv[1:])
    if argv[:1] == ["json"]:
        return report(argv[1:])
    print("the e2e stand-in of coverage.py knows run, json and --version", file=sys.stderr)
    return 2


sys.exit(main(sys.argv[1:]))
`
// The scripted builder's code: 12 executable lines, of which the tests run 4 (the two lambdas, VERSION and the line
// def stage_summary; no test calls stage_summary, so its 8 body lines never run).
export const LOW_SHAPE = `VERSION = 1
stage_object = lambda stage, verdict, requirements: {"stage": stage, "verdict": verdict, "requirements": list(requirements)}


def stage_summary(stages):
    out = []
    failed = 0
    for s in stages:
        if s["verdict"] == "FAIL":
            failed += 1
            out.append(s["stage"])
    out.sort()
    return out, failed
`
export const LOW_BYTES = 'import json; document = lambda ledger: json.dumps(ledger, sort_keys=True, separators=(",", ":"))\n'

// WP19 test 9: the scripted builder leaves 12 new lines of which 4 run; the base value is 71%. Check fails on the row
// coverage (a measured drop, class code); the run the person approved takes its one counted repair, whose scripted
// agent records RED and GREEN as a fix pass does and changes no line that runs; Check fails again and the run stops
// with one question that names the row. It never passes on to the commit and never takes a second repair by itself.
// WP24 turns the repair into one in place.
export const coverageDrop = (w: World): void => {
  const fake = `${w.dir}.fakecov`
  fs.mkdirSync(path.join(fake, 'coverage'), { recursive: true })
  fs.writeFileSync(path.join(fake, 'coverage/__init__.py'), '')
  fs.writeFileSync(path.join(fake, 'coverage/__main__.py'), FAKE_COVERAGE)
  w.env.PYTHONPATH = fake
  startProject(w, '', wd => {
    // no Check command and no old key: the CLI detects the Python stack and its coverage tool, and judges the project
    const cfg = '.claude/temper.config'
    const text = wd.read(cfg).split('\n').filter(l => !/^\s*(commands:|test: |coverage: |coverage-threshold:)/.test(l)).join('\n')
    fs.writeFileSync(path.join(wd.dir, cfg), text)
    wd.sh('git add -A && git commit -qm "config: no Check commands"')
  })
  fs.mkdirSync(path.join(w.dir, '.temper/evidence'), { recursive: true })
  fs.writeFileSync(path.join(w.dir, '.temper/evidence/baseline.json'), JSON.stringify({ result: 'green', coverage: 71 }) + '\n')
  const lowOne = (wd: World, n: number): void => {
    const wt = path.relative(wd.dir, worktreeOf(t(wd, `task show ${n}`).out))
    const [testFile, srcFile, stub, code, test] = n === 1
      ? ['unit/test_ci_shape.py', 'src/ci_shape.py', SHAPE_STUB, LOW_SHAPE, SHAPE_TEST]
      : ['unit/test_ci_bytes.py', 'src/ci_bytes.py', BYTES_STUB, LOW_BYTES, BYTES_TEST]
    wd.write(path.join(wt, testFile), test)
    wd.write(path.join(wt, srcFile), stub)
    if (t(wd, `task test ${n} --phase red`).code === 0) throw new Error('RED passed')
    wd.write(path.join(wt, srcFile), code)
    const green = t(wd, `task test ${n} --phase green`)
    if (green.code !== 0) throw new Error(`GREEN failed: ${green.out}`)
  }
  let repairs = 0
  const asked: Json[] = []
  let approved = false
  const end = orchestrate(w, script({
    agents: {
      ...AGENTS,
      'temper:temper-build-task': chained(lowOne),
      // the repair the rule takes: test first, as a fix pass records it, its scripted agent adds only a comment, so the
      // share of the changed lines that ran stays 4 of 12
      'temper:temper-build': wd => {
        repairs++
        const check = "-- grep -q 'a comment of the repair' src/ci_shape.py"
        t(wd, `evidence run --stage build --claim 'unit tests' --phase red ${check}`)
        wd.write('src/ci_shape.py', `${wd.read('src/ci_shape.py').replace(/\n*$/, '\n')}# a comment of the repair\n`)
        t(wd, `evidence run --stage build --claim 'unit tests' --phase green ${check}`)
      },
    },
    person: (ask, wd) => {
      if (String(ask.id ?? '') === 'plan.approve') {
        approved = true
        return recommended(ask, wd)
      }
      if (!approved) return recommended(ask, wd)
      asked.push(ask)
      return null   // the person reads the stop and ends the scenario there
    },
    afterFailStops: true,
  }))
  const flow = w.trace.join('\n')
  const rows = ((w.json('.temper/gates.json').check?.requirements ?? []) as Json[])
  const cov = rows.find(r => r.name === 'coverage')
  expect(cov !== undefined && cov.pass === false && String(w.json('.temper/gates.json').check?.verdict) === 'FAIL',
    `Check fails on the row coverage, a measured drop (${JSON.stringify(rows.filter(r => r.pass !== true)).slice(0, 300)})`)
  expect(!rows.some(r => /mutation/i.test(String(r.name))), 'no row of Check names the planted bugs')
  const log = (w.exists('.temper/rule-log.json') ? w.json('.temper/rule-log.json') : []) as unknown as Json[]
  const ruled = log.filter(x => x.kind === 'repair' && x.stage === 'check').length
  expect(repairs === 1 && ruled === 1, `the run takes its one counted repair and no second (${repairs} launches of the repair agent, ${ruled} repairs by rule at Check)`)
  expect(asked.length === 1 && end.action === 'ask', `after the approval the run asks one question, at the stop (${asked.map(a => a.id).join(', ')})`)
  const q = String(asked[0]?.question?.question ?? '')
  expect(/\bcoverage\b/.test(q), `the stop's question names the row coverage (${q.slice(0, 200)})`)
  expect(!/state advance check_complete/.test(flow) && !asked.some(a => a.id === 'commit.confirm'), 'the run never passes on to the commit')
}

// WP21: a command the plan wrote fails on the base (the scenario plan-command-fails). The scripted planner writes a
// Validate for G1 that exits 2 on the current code and names no file a task creates; the base suite is green (a
// passing test is committed first, so the base is not red and the failure is the command's own). The CLI runs the
// Validate once after the planner returned (`temper baseline plan`, in the foreground here) and asks `plan.command`
// before any task agent is launched; the person changes the command (a typed answer, `plan patch`), and Build goes on
// with both tasks, to the commit.
const PCF_BAD = 'python3 -m unittest discover -s unit -t . --no-such-flag'
const PCF_GOOD = 'python3 -m unittest unit.test_ci_shape'
export const planCommandFails = (w: World): void => {
  w.env.TEMPER_BASELINE_FOREGROUND = '1'
  startProject(w, '', wd => {
    wd.write('unit/test_base.py', 'import unittest\n\n\nclass BaseTest(unittest.TestCase):\n    def test_the_base_holds(self):\n        self.assertTrue(True)\n')
    wd.sh('git add -A && git commit -qm "a passing test on the base"')
  })
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-plan': (wd, a) => {
      AGENTS['temper:temper-plan']!(wd, a)
      wd.write(`${SPEC}/tasks.md`, wd.read(`${SPEC}/tasks.md`).replace(`**Validate:** \`${PCF_GOOD}\``, `**Validate:** \`${PCF_BAD}\``))
    },
  }
  const patches = (o: Json): boolean => ((o.calls ?? []) as string[]).some(c => /\splan patch\s/.test(` ${c}`))
  const asked: string[] = []
  const atQuestion: Array<{ tasks: number; text: string }> = []
  let atApproval = ''
  const end = orchestrate(w, script({
    agents,
    person: (ask, wd) => {
      const id = String(ask.id ?? '')
      asked.push(id)
      if (id === 'plan.fail')
        throw new Error(`the Validate that fails on the base failed the plan gate (plan.fail), where the gate runs no command: ${String(ask.question?.question ?? '').slice(0, 200)}`)
      if (id === 'plan.approve') atApproval = wd.exists(`${SPEC}/tasks.md`) ? wd.read(`${SPEC}/tasks.md`) : ''
      const opts = (ask.options ?? []) as Json[]
      const change = opts.find(patches)
      if (id === 'plan.command') atQuestion.push({ tasks: wd.counts.launches['temper:temper-build-task'] ?? 0, text: String(ask.question?.question ?? '') })
      if (change !== undefined) return { label: String(change.label), note: PCF_GOOD }
      const more = opts.find(o => o.kind === 'more')
      if (id === 'plan.command' && more !== undefined && ((ask.more?.options ?? []) as Json[]).some(patches)) return String(more.label)
      return recommended(ask, wd)
    },
  }))
  expect(atQuestion.length >= 1, `the Validate that fails on the base is asked as plan.command (asked ${asked.join(', ')})`)
  expect(atQuestion[0]!.tasks === 0, `the person is asked before any task agent is launched (${atQuestion[0]!.tasks} launched)`)
  expect(atQuestion[0]!.text.includes(PCF_BAD), `the question names the command (${atQuestion[0]!.text.slice(0, 200)})`)
  expect(asked.filter(x => x === 'plan.command').length === 1 && asked.indexOf('plan.command') < asked.indexOf('plan.approve'),
    `one plan.command, before the approval (asked ${asked.join(', ')})`)
  expect(atApproval.includes(`**Validate:** \`${PCF_GOOD}\``) && !atApproval.includes(PCF_BAD) && (atApproval.match(/^### Task \d+/gm) ?? []).length === 2,
    `the answer patched the command and kept every task (${atApproval.split('\n').filter(l => /Validate:|^### Task/.test(l)).join(' / ')})`)
  expect((w.counts.launches['temper:temper-plan'] ?? 0) === 1 && !/state (loop \S+|redo) plan\b/.test(w.trace.join('\n')),
    `no second planner and no step back to Plan (${w.counts.launches['temper:temper-plan'] ?? 0} planner launches)`)
  expect(end.action === 'none' && !w.exists('.temper/build-state.json') && w.run('git show HEAD:src/ci_bytes.py').code === 0 &&
    w.run('git show HEAD:src/ci_shape.py').code === 0, `Build went on with both tasks to the commit (last action ${end.action})`)
}
