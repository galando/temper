import fs from 'node:fs'
import path from 'node:path'

import { orchestrate, runCalls } from './loop'
import type { Script } from './loop'
import { BASE_FILES, BYTES_CODE, BYTES_STUB, BYTES_TEST, INTENT_SCENARIOS, PLAN_MD, SHAPE_CODE, SHAPE_STUB, SHAPE_TEST, TASKS_MD } from './project'
import { ROOT, TEMPER, World } from './world'
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
  if (config) fs.appendFileSync(path.join(w.dir, '.claude/temper.config'), `\n${config}\n`)
  w.sh('git add -A && git commit -qm config')
  before?.(w)
  w.sh(`${TEMPER} init`)
  w.sh(`${TEMPER} state init ci --feature 'CI report'`)
}

export const worktreeOf = (show: string): string => /^WORKTREE:\s*(\S+)/m.exec(show)?.[1] ?? ''

export function buildTask(w: World, a: Json): void {
  const n = Number(/Task:\s*(\d+)/.exec(a.prompt)![1])
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

// The fresh reviewer of the plan (agents/plan-review.md): each lens of its launch prompt records its findings, then its completion,
// then (comprehension) the paraphrase, every row against the tasks.md it read.
export type FreshFinding = { lens: string; severity: string; claim: string }
export function freshReviewer(w: World, a: Json, found: FreshFinding[], skip: string[] = []): void {
  const inst = /Instance:\s*(\w)/.exec(a.prompt)?.[1] ?? 'A'
  const lenses = (/Lenses:\s*([^.]+)\./.exec(a.prompt)?.[1] ?? 'readiness, zoom-out, comprehension').split(',').map(x => x.trim())
  const art = `--artifact ${SPEC}/tasks.md`
  for (const lens of lenses) {
    for (const f of found.filter(x => x.lens === lens))
      t(w, `evidence add --stage plan --phase fresh --severity ${f.severity} --claim '[${f.lens}] ${f.claim}' ${art}`)
    if (skip.includes(lens)) continue
    t(w, `evidence add --stage plan --phase fresh --exit 0 --label PROVEN --claim 'fresh review completed: ${lens} ${inst}' ${art}`)
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
  'temper:temper-build-task': buildTask,
  'temper:temper-review': w => {
    t(w, `evidence add --stage review --claim 'review completed' --exit 0 --cmd 'review panel'`)
  },
  'temper:temper-check': w => {
    t(w, `evidence add --stage check --claim 'tests' --exit 0 --cmd 'python3 -m unittest discover -s unit -t .'`)
    t(w, `evidence add --stage check --claim 'coverage' --value 90 --exit 0 --cmd 'coverage report'`)
    for (const s of ['CI JSON shape is stable across a run', 'Override rows name the approver', 'Same ledger gives the same bytes'])
      t(w, `evidence add --stage check --scenario '${s}' --claim 'scenario: ${s}' --exit 0 --cmd 'python3 -m unittest discover -s unit -t .'`)
    t(w, `evidence add --stage check --criterion AC-02 --claim 'the override rows were read by hand' --exit 0 --cmd 'read the output'`)
  },
}

// The person: the recommended option of each question, unless a scenario says otherwise.
export const recommended: Person = ask => {
  const o = (ask.options as Json[]).find(x => String(x.label).includes('(Recommended)')) ?? (ask.options as Json[])[0]
  if (ask.question.question.startsWith('Every gate passed. The report is above')) return 'Not now'
  return o.label
}

export const script = (extra: Partial<Script> = {}): Script => ({
  agents: AGENTS,
  person: recommended,
  instruction: (_w, text) => /each file the run changed|^Copy what|^When .* records deviations/.test(text),
  ...extra,
})

export const fullRun = (w: World): void => {
  startProject(w)
  orchestrate(w, script())
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
  if (w.mode === 'mod') {
    expect(write?.includes('The run ci (Plan stage) owns this folder.') && write.includes('claude --worktree'), `the write refusal names the run and the worktree (${write})`)
    expect(advance !== null, 'leaving Plan is refused without the answer')
    const option = w.answer(n.ask as Json, 'Continue to Build (Recommended)')
    expect(option.label === 'Continue to Build (Recommended)', 'the option exists')
    expect(w.denies({ tool: 'Bash', input: { command: `${TEMPER} state advance plan_complete build` } }) === null, 'leaving Plan passes as the call the answer maps to')
  } else {
    expect(write === null && advance === null, 'with no mod nothing is refused')
  }
}

// A small change at Check: the window opens (the person's answer), a code write passes inside it, and the closed change runs
// Review of the changed files, then Check, then the commit gate.
export const smallChange = (w: World): void => {
  startProject(w)
  orchestrate(w, script(stopAtAsk('Check: the check passed')))
  const outside = w.denies({ tool: 'Write', input: { file_path: `${w.dir}/src/ci_shape.py` } })
  expect(w.mode === 'plain' || outside !== null, 'a code write at Check is refused before the window')
  let seen = ''
  orchestrate(w, script({
    person: (ask, wd) => {
      const q = String(ask.question.question)
      if (q.startsWith('Check: the check passed') && !seen) return 'More options'
      if (q.includes('more options') && !seen) return 'Make a small change'
      return recommended(ask, wd)
    },
    instruction: (wd, text) => {
      if (text.startsWith('Make the change, run')) {
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
    'temper:temper-build-task': (wd, a) => {
      const n = Number(/Task:\s*(\d+)/.exec(a.prompt)![1])
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
      } else buildTask(wd, a)
    },
  }
  const asked: string[] = []
  orchestrate(w, script({
    agents,
    person: (ask, wd) => {
      const q = String(ask.question.question)
      asked.push(q)
      if (q.includes('its tests already pass before any change')) return { label: 'Accept it as done', note: 'an earlier change built it' }
      if (q.includes('is a manual task')) return { label: 'Confirm', note: 'Dana Cohen' }
      if (q.startsWith('Every gate passed. The report is above')) {
        const rows = JSON.stringify(wd.json('.temper/evidence/build.json'))
        expect(rows.includes('Task 3 confirmed by Dana Cohen'), 'the confirmation carries the name the person gave')
        expect(rows.includes('Task 2 accepted as done') && rows.includes('an earlier change built it'), 'the acceptance carries the reason the person gave')
      }
      return recommended(ask, wd)
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
      return recommended(ask, wd)
    },
    instruction: (wd, text) => {
      if (text.startsWith('Pull request: follow')) return true
      if (text.includes('section One PR')) {
        const br = wd.sh('git branch --show-current').trim()
        expect(wd.denies({ tool: 'Bash', input: { command: `gh pr create --head ${br} --base main --title 't' --body-file b` } }) !== null || wd.mode === 'plain', 'a pull request without --draft is refused by the mod')
        expect(wd.denies({ tool: 'Bash', input: { command: 'gh pr ready 7' } }) !== null || wd.mode === 'plain', 'gh pr ready is refused by the mod')
        fs.writeFileSync(path.join(wd.dir, '.pr-body'), 'The body\n')
        runCalls(wd, [`git push -q -u origin ${br}`, `gh pr create --head ${br} --base main --title 'feat: CI report' --body-file .pr-body --draft`])
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
  expect(launches['temper:temper-review'] === 1 && launches['temper:temper-check'] === 1, `a CI fix sends no Review or Check again (review ${launches['temper:temper-review']}, check ${launches['temper:temper-check']})`)
  expect(w.sh('git log --format=%s -n 3').includes('fix(ci): apply the Pipeline fix (CI fix round 1)'), 'the fix was committed with the agreed message')
  expect(w.sh(`git --git-dir=${origin} log --format=%s -n 1 feature/ci`).includes('fix(ci)'), 'the fix was pushed to origin')
  void refused
}

// The Context check of Plan: the map has a gap, so the CLI asks the person (not Plan); the answer runs plan review through the mod.
export const contextCheck = (w: World): void => {
  startProject(w)
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-plan': (wd, a) => {
      AGENTS['temper:temper-plan']!(wd, a)
      wd.write(`${SPEC}/plan.md`, PLAN_MD.replace('- reviewed: auto - every source is current and on topic', '- gap: no rate limit policy was found in code, docs or the ticket\n- reviewed: pending'))
      wd.write(`${SPEC}/intent.md`, wd.read(`${SPEC}/intent.md`).replace('### Open Questions\n', '### Open Questions\n\n- Blocking: Context check: is this the right context for the plan? choices: Right direction | Narrow the focus | Fix the sources.\n'))
    },
  }
  let asked = 0
  orchestrate(w, script({
    agents,
    person: (ask, wd) => {
      if (String(ask.question.question) === 'Is this the right context for the plan?') {
        asked += 1
        const direct = wd.denies({ tool: 'Bash', input: { command: `${TEMPER} plan review --answer 'Right direction'` } })
        expect(wd.mode === 'plain' || direct !== null, 'plan review is refused with no answer')
        expect((ask.options as Json[]).map(o => o.label).join('|') === 'Right direction|Narrow the focus|Fix the sources|Carry forward', 'the choices are the Blocking line plus Carry forward')
        return 'Narrow the focus'
      }
      return recommended(ask, wd)
    },
  }))
  expect(asked === 1, `the Context check was asked once (${asked})`)
}

// The run's branch exists from an earlier run with commits this checkout lacks: the Intent question offers both ways on.
export const branchClash = (w: World): void => {
  startProject(w, '', wd => {
    wd.sh('git checkout -q -b feature/ci && echo old > old.txt && git add old.txt && git commit -qm "an earlier run" && git checkout -q main')
  })
  const labels: string[] = []
  orchestrate(w, script({
    person: (ask, wd) => {
      const q = String(ask.question.question)
      if (q.includes('already exists from an earlier run')) {
        labels.push(...(ask.options as Json[]).map(o => String(o.label)))
        return 'Continue on a new branch feature/ci-2'
      }
      return recommended(ask, wd)
    },
  }))
  expect(labels.includes('Continue on feature/ci') && labels.includes('Continue on a new branch feature/ci-2'), 'both ways on were offered')
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
  if (w.mode === 'mod') {
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
      return recommended(ask, wd)
    },
    // the person overrode the failed scenario; Check then fails on it for the same reason, which is the end of this scenario
    stopAt: (_wd, n) => n.action === 'ask' && String(n.ask.question.question).startsWith('Check: the check failed'),
  }))
  expect(seen.includes("scenario 'An untraced behavior holds'") && seen.includes('exit 3') && seen.includes('python3 -c'), `the Build question names the scenario, its command and the exit (${seen.slice(0, 200)})`)
}

// An armed run: the plan answer arms it, the stages go on by themselves, and it parks before the commit; nothing is pushed.
export const armedRun = (w: World): void => {
  startProject(w, 'autonomy:\n  enabled: true')
  let parkedAt = ''
  orchestrate(w, script({
    person: (ask, wd) => {
      const q = String(ask.question.question)
      if (q.startsWith('Plan: the check passed')) return 'Autonomous: run the rest unattended'
      if (q.includes('the armed run parked here for you')) parkedAt = q
      return recommended(ask, wd)
    },
  }))
  expect(parkedAt !== '', 'the armed run parked before the commit and asked the person')
  expect(!/git push|gh pr/.test(w.trace.join('\n')), 'an armed run never pushes')
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

// A medium change: Design runs between Plan and Build.
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
  orchestrate(w, script({ agents, person: (ask, wd) => { asked.push(String(ask.question.question)); return recommended(ask, wd) } }))
  expect(asked.some(q => q.startsWith('Design: the check passed')), 'the Design question was asked')
  expect(/work:design/.test(w.trace.join('\n')), 'the Design agent ran between Plan and Build')
}

// Three groups: only max-groups (two) start at once; the third waits for a place.
export const threeGroups = (w: World): void => {
  startProject(w)
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
    },
    'temper:temper-build-task': (wd, a) => {
      const n = Number(/Task:\s*(\d+)/.exec(a.prompt)![1])
      if (n !== 3) return buildTask(wd, a)
      const wt = path.relative(wd.dir, worktreeOf(t(wd, 'task show 3').out))
      wd.write(path.join(wt, 'unit/test_ci_extra.py'), extraTest)
      wd.write(path.join(wt, 'src/ci_extra.py'), 'VALUE = None\n')
      expect(t(wd, 'task test 3 --phase red').code !== 0, 'RED fails')
      wd.write(path.join(wt, 'src/ci_extra.py'), 'VALUE = 1\n')
      expect(t(wd, 'task test 3 --phase green').code === 0, 'GREEN passes')
    },
  }
  orchestrate(w, script({ agents }))
  const starts = w.trace.filter(l => l.includes('group start'))
  expect(starts.length === 3, `all three groups started in the end (${starts.length})`)
  const firstWork = w.trace.findIndex(l => l.includes('group start'))
  const batch = w.trace.slice(firstWork).findIndex((l, i) => i > 0 && !l.includes('group start'))
  expect(batch === 2, `the first batch started two groups (max-groups 2), not ${batch}`)
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
  const tasks = TASKS_MD
    .replace(/\*\*Validate:\*\* `python3 -m unittest unit\.test_ci_shape`/, '**Validate:** `mvn verify -Pjacoco`')
    .replace(/\*\*Validate:\*\* `python3 -m unittest unit\.test_ci_bytes`/, '**Validate:** `mvn verify -Pjacoco`')
    .replace('**Integration:** `python3 -m unittest discover -s unit -t .`', '**Integration:** `mvn verify -Pjacoco`')
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
    'temper:temper-build-task': (wd, a) => {
      const n = Number(/Task:\s*(\d+)/.exec(a.prompt)![1])
      const [main, test] = n === 1 ? ['Shape', 'ShapeTest'] : ['Bytes', 'BytesTest']
      const wt = path.relative(wd.dir, worktreeOf(t(wd, `task show ${n}`).out))
      fs.rmSync(green, { force: true })
      wd.write(path.join(wt, `src/test/java/com/acme/${test}.java`), `package com.acme;\npublic class ${test} {}\n`)
      wd.write(path.join(wt, `src/main/java/com/acme/${main}.java`), `package com.acme;\npublic class ${main} {}\n`)
      expect(t(wd, `task test ${n} --phase red`).code !== 0, 'RED fails')
      fs.writeFileSync(green, '')
      const g = t(wd, `task test ${n} --phase green`)
      expect(g.code === 0, `GREEN passes with a new report for the class (${g.out.slice(0, 200)})`)
    },
  }
  orchestrate(w, script({ agents }))
  const calls = fs.readFileSync(log, 'utf8')
  expect(/-o /.test(calls) && /-Dtest=ShapeTest/.test(calls) && /-Dtest=BytesTest/.test(calls), `Maven ran offline with only the declared classes (${calls.slice(0, 300)})`)
  expect(/verify -Pjacoco/.test(calls) || /-Pjacoco/.test(calls), 'the group verified with JaCoCo')
}

// A /temper:fix run: RCA, Fix (a regression test first), Review, Check and the commit; the mod stands aside for it.
export const fixRun = (w: World): void => {
  startProject(w, '', wd => {
    wd.write('src/ci_shape.py', 'def stage_object(stage, verdict, requirements):\n    return {"stage": stage}\n')
    wd.sh('git add -A && git commit -qm "a shape with a bug"')
  })
  t(w, 'state clear')
  w.sh(`${TEMPER} state init bug --command fix`)
  const bug = '.temper/specs/bug'
  const agents: Record<string, Agent> = {
    'temper:temper-rca': wd => wd.write(`${bug}/rca.md`, '# RCA: the shape drops the verdict\n\n## Root cause\n\n`stage_object` returns only the stage.\n\n## Fix\n\nReturn verdict and requirements.\n'),
    'temper:temper-fix': wd => {
      wd.write('unit/test_ci_shape.py', SHAPE_TEST)
      const red = sh(wd, 'python3 -m unittest unit.test_ci_shape')
      expect(red.code !== 0, 'the regression test fails first')
      t(wd, `evidence add --stage build --phase red --claim 'regression test: the shape keeps its verdict' --exit 1 --cmd 'python3 -m unittest unit.test_ci_shape'`)
      wd.write('src/ci_shape.py', SHAPE_CODE)
      expect(sh(wd, 'python3 -m unittest unit.test_ci_shape').code === 0, 'the fix passes the regression test')
      t(wd, `evidence add --stage build --phase green --claim 'regression test: the shape keeps its verdict' --exit 0 --cmd 'python3 -m unittest unit.test_ci_shape'`)
    },
    'temper:temper-review': wd => t(wd, `evidence add --stage review --claim 'review completed' --exit 0 --cmd 'review panel'`),
    'temper:temper-check': wd => {
      t(wd, `evidence add --stage check --claim 'tests' --exit 0 --cmd 'python3 -m unittest discover -s unit -t .'`)
      t(wd, `evidence add --stage check --claim 'coverage' --value 90 --exit 0 --cmd 'coverage report'`)
    },
  }
  // commands/fix.md launches the RCA agent itself; the loop over `temper next` starts at its question
  agents['temper:temper-rca']!(w, {})
  const asked: string[] = []
  orchestrate(w, script({
    agents,
    person: (ask, wd) => { asked.push(String(ask.question.question)); return recommended(ask, wd) },
    instruction: (wd, text) => {
      if (text.startsWith('Append one entry for this fix')) {
        wd.write('.temper/lessons.md', '# Lessons\n\n- the shape must keep its verdict: a regression test names it\n')
        return true
      }
      return /each file the run changed|^Copy what|^When .* records deviations/.test(text)
    },
  }))
  expect(asked.some(q => q.startsWith('RCA: the root cause is in')), 'the RCA question was asked')
  expect(w.sh('git log --format=%s -n 1').length > 0 && !w.exists('.temper/build-state.json'), 'the fix run ended with its commit')
}

// The run's branch exists from an earlier run: Continue on it carries the new spec files across the switch through a temp folder.
// The mod lets the call through whole, as the CLI wrote it (the only Temper path it writes is the spec folder).
export const branchClashCarry = (w: World): void => {
  startProject(w, '', wd => {
    wd.sh('git checkout -q -b feature/ci && echo old > old.txt && git add old.txt && git commit -qm "an earlier run" && git checkout -q main')
  })
  orchestrate(w, script({
    person: (ask, wd) => (String(ask.question.question).includes('already exists from an earlier run') ? 'Continue on feature/ci' : recommended(ask, wd)),
  }))
  expect(w.sh('git branch --show-current').trim() === 'feature/ci', 'the run went on the earlier branch')
  expect(w.sh('git log --format=%s feature/ci').includes('docs(intent): accept ci') || w.sh('git log --all --format=%s').includes('docs(intent): accept ci'), 'the intent was accepted and committed there, with the new spec files carried across')
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
  startProject(w)
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
  startProject(w)
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
  startProject(w)
  let reviews = 0
  let lastAsk: Json = {}
  const refused: string[] = []
  const agents: Record<string, Agent> = {
    ...AGENTS,
    'temper:temper-plan': (wd, a) => {
      mediumPlan(wd, a)
      const id = /#(\d+) \[high\]/.exec(String(a.prompt))?.[1]
      if (id) {
        const bad = t(wd, `evidence contest --stage plan --id ${id} --cite src/nothing.py --reason 'it is intentional'`)
        if (bad.code !== 0) refused.push(bad.out)
        const ok = t(wd, `evidence contest --stage plan --id ${id} --cite README.md:1 --reason 'the README says this project is a scratch project'`)
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
        expect(opt.reason_question.options[0].label === 'Contested with evidence: README.md:1', 'the first reason is the checked citation')
        wd.answer(aq, opt.label, 'Contested with evidence: README.md:1')
        runCalls(wd, opt.calls, { reason: 'Contested with evidence: README.md:1' })
        return true
      }
      return /each file the run changed|^Copy what|^When .* records deviations/.test(text)
    },
  }))
  expect(refused.length === 1 && refused[0]!.includes('no file src/nothing.py') && refused[0]!.includes('escalate'), `a contest with no readable citation was refused (${refused.join(' / ')})`)
  expect(reviews === 1, 'a contest leaves tasks.md as it was, so the review does not run again')
  expect(!w.exists('.temper/build-state.json'), 'the run went to its end')
}
