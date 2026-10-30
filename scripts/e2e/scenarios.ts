import fs from 'node:fs'
import path from 'node:path'

import { orchestrate } from './loop'
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

export const AGENTS: Record<string, Agent> = {
  'temper:temper-intent': w => w.write(`${SPEC}/intent.md`, fs.readFileSync(path.join(ROOT, 'templates/example-intent.md'), 'utf8')),
  'temper:temper-plan': w => {
    w.write(`${SPEC}/intent.md`, w.read(`${SPEC}/intent.md`).replace('## Scenarios (BDD)\n', INTENT_SCENARIOS))
    w.write(`${SPEC}/plan.md`, PLAN_MD)
    w.write(`${SPEC}/tasks.md`, TASKS_MD)
    t(w, 'state set complexity simple')
    t(w, 'risk')
  },
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
