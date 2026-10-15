// Hardening round (9.6.0): each test is an exploit of a hand traced review finding, driven through the real
// guard and adapter (the world stands in for the engine; no decision is handed to the guard by the test).
// A test that passes before the fix is recorded in the CHANGELOG as "not a real exploit" and stays as a
// regression test. Findings are numbered as in the review.
import { describe, expect, test } from 'claude-code/testing'

import { LATER, SPEC, questionOf, runFiles } from './run-files'
import { viewText, world } from './world'
import type { Answer, World } from './world'

type Api = {
  session: { start: (a: unknown) => Promise<unknown> }
  command: { run: (a: unknown) => Promise<{ text?: string }> }
  tool: { call: (a: unknown) => Promise<{ deny?: string; isError?: boolean; text?: string }> }
}
const START = { cwd: '/repo', surface: null, isInteractive: false } as const

type Opts = {
  next?: string
  gates?: string[]
  head?: string
  branch?: string
  command?: string
  complexity?: string
  green?: boolean
  design?: boolean
  extra?: Record<string, string>
  store?: Record<string, unknown>
  cwd?: string
  // The person's answers to the Temper gate questions, in order.
  answers?: Answer[]
  // Stages whose check failed.
  fail?: string[]
}

// A run as the CLI leaves it, on a feature branch (or main), with the gates that passed.
async function begin($: unknown, on: Parameters<typeof world>[0], o: Opts = {}): Promise<{ w: World; api: Api }> {
  const api = $ as Api
  const f = runFiles({ nextStage: o.next ?? 'plan' })
  f['.temper/build-state.json'] = JSON.stringify({
    stage: 'x_complete',
    spec: 'pw',
    spec_path: SPEC,
    next_stage: o.next ?? 'plan',
    command: o.command ?? 'temper',
    branch: o.branch ?? 'feature/pw',
    run_id: 'run-pw',
    step: 3,
    ...(o.complexity ? { complexity: o.complexity } : {}),
  })
  f['.temper/gates.json'] = JSON.stringify(Object.fromEntries([...(o.gates ?? ['intent', 'plan']).map(g => [g, { verdict: 'PASS', ts: LATER }]), ...(o.fail ?? []).map(g => [g, { verdict: 'FAIL', ts: LATER }])]))
  f['/repo/.git/HEAD'] = `ref: refs/heads/${o.head ?? 'feature/pw'}\n`
  if (o.green) f['.temper/evidence/build.json'] = JSON.stringify([{ claim: 'unit tests', exit_code: 0, phase: 'green' }])
  if (o.design) f[`${SPEC}/design.md`] = '# Design\n'
  const w = world(on, { ...f, ...(o.extra ?? {}) }, { fakeCli: true, projectRoot: '/repo', ...(o.store ? { store: o.store } : {}), ...(o.answers ? { answers: o.answers } : {}) })
  await api.session.start({ ...START, ...(o.cwd ? { cwd: o.cwd } : {}) })
  return { w, api }
}

const sh = async (api: Api, command: string): Promise<string | undefined> => (await api.tool.call({ tool: 'Bash', command })).deny
const wr = async (api: Api, path: string): Promise<string | undefined> => (await api.tool.call({ tool: 'Write', file_path: path, content: 'x' })).deny
const refresh = (api: Api) => api.command.run({ command: 'temper:temper', args: 'status', origin: { kind: 'composer' } })
// The orchestrator asks the question `temper next --json` gives, exactly; the world answers it with the next of the
// test's answers.
const ask = (api: Api, w: World) => api.tool.call({ tool: 'AskUserQuestion', questions: [{ ...questionOf(viewText(w) ?? ''), multiSelect: false }] })
const why = (label: string, note: string): Answer => ({ label, note })
// Every refusal starts with Temper: or says that only the user decides.
const T = /Temper:|Only the user/

// ---- 1. a shell that reads its program from standard input ---------------------------------------------------
// A program a shell reads from standard input is a known limit (ADR 0013, known-limits.test.ts). The usual idioms run.
describe('finding 1: plain, visible stdin programs and the usual eval idioms still run', () => {
  const fine: Record<string, string> = {
    'echo | bash of a plain line': "echo 'ls src' | bash",
    'heredoc bash of plain lines': "bash <<'EOF'\nls src\nwc -l README.md\nEOF",
    'a temper read in a heredoc bash': "bash <<'EOF'\nscripts/temper gate build\nEOF",
    'eval of rbenv': 'eval "$(rbenv init -)"',
    'eval of pyenv': 'eval "$(pyenv init -)"',
    'a python heredoc': "python3 - <<'EOF'\nprint('hi')\nEOF",
    'bash -c plain': "bash -c 'ls src'",
    'echo | bash /dev/stdin of a plain line': "echo 'ls src' | bash /dev/stdin",
    'echo | bash /dev/./stdin of a plain line': "echo 'ls src' | bash /dev/./stdin",
    'echo | source //dev/stdin of a plain line': "echo 'export A=1' | source //dev/stdin",
    'echo | python3 /dev/stdin of a plain program': "echo 'print(1)' | python3 /dev/stdin",
    'a script file still runs': 'bash scripts/run.sh',
    'a script file under a variable folder still runs': 'bash "$TMPDIR/run.sh"',
    'a file under /dev that is not standard input is a file': 'bash /dev/null',
  }
  for (const [name, cmd] of Object.entries(fine)) {
    test(name, async ($, on) => {
      const { api } = await begin($, on, { next: 'build' })
      expect(await sh(api, cmd)).toBeUndefined()
    })
  }
})

describe('release review 15: scripts and visible programs still run', () => {
  const fine: Record<string, string> = {
    'a script in the project fed a file': 'cat data.txt | bash scripts/run.sh',
    'a script one folder up fed a file': 'cat data.txt | bash ../run.sh',
    'a script under a long variable folder fed a file': 'cat data.csv | python3 "$TOOLS/report.py"',
    'a script named by a long variable, not fed': 'bash "$INSTALLER"',
    'a file called stdin in the project, not fed': 'bash stdin',
    'a plain program after --rcfile': "echo 'ls src' | bash --rcfile x /dev/stdin",
    'a script after --rcfile': 'bash --rcfile x scripts/run.sh',
    'a script after --init-file': 'bash --init-file x scripts/run.sh',
    'a plain program into bash stdin after cd /dev': "cd /dev && echo 'ls' | bash stdin",
    'a glob of scripts fed a file is not standard input': 'cat data.txt | bash *.sh',
    // Final review: input from /dev/null is no input, and a `<` inside a quoted argument is no redirect.
    'a loop over test scripts with input from /dev/null': 'for script in scripts/selftest/*.sh; do bash "$script" < /dev/null; done',
    'a script named by a variable with input from /dev/null': 'bash "$TEST_SCRIPT" </dev/null',
    'a script named by a variable with fd 0 from /dev/null': 'bash "$TEST_SCRIPT" 0</dev/null',
    'a script named by a variable with a quoted < in an argument': `bash "$SCRIPT" --grep '<title>'`,
    'a script named by a variable with a < inside a quoted option value': 'bash "$RUNNER" --filter="x<3"',
    // A startup file that is an ordinary file, and xargs with a program written out.
    'a -c program after --rcfile with a plain file': "bash --rcfile .bashrc -ic 'ls src'",
    'a -c program with BASH_ENV set to a plain file': "BASH_ENV=./env.sh bash -c 'ls src'",
    'a script with ENV set and input from a file': 'ENV=staging bash scripts/run.sh < input.txt',
    'xargs runs bash -c with a program written out': "ls scripts/*.sh | xargs -n 1 bash -c 'shellcheck \"$0\"'",
  }
  for (const [name, cmd] of Object.entries(fine)) {
    test(name, async ($, on) => {
      const { api } = await begin($, on, { next: 'build' })
      expect(await sh(api, cmd)).toBeUndefined()
    })
  }
})

// ---- 2. enforcement dropped when build-state.json is unreadable, missing or removed ---------------------------
describe('finding 2: the run state cannot be switched off by hiding build-state.json', () => {
  const STATE = '.temper/build-state.json'
  test('chmod 000 on the file is refused', async ($, on) => {
    const { api } = await begin($, on, { next: 'build' })
    for (const cmd of ['chmod 000 .temper/build-state.json', 'chmod -R a-r .temper', 'chown nobody .temper/gates.json', 'rm .temper/view.json']) {
      expect(await sh(api, cmd), cmd).toMatch(T)
    }
  })

  test('chmod of an ordinary file is fine', async ($, on) => {
    const { api } = await begin($, on, { next: 'build' })
    expect(await sh(api, 'chmod +x scripts/run.sh')).toBeUndefined()
  })

  for (const cmd of ["find . -name '*.pyc' -delete", 'find src -name "*.tmp" -exec rm {} +', 'find . -name "*.ts" -newer x', 'git clean -n', 'git clean --dry-run -fd', 'git stash', 'git stash list', 'xargs echo']) {
    test(`still fine: ${cmd}`, async ($, on) => {
      const { api } = await begin($, on, { next: 'build' })
      expect(await sh(api, cmd)).toBeUndefined()
    })
  }

  test('the file removed: enforcement stays (a write outside the plan is still refused at Plan)', async ($, on) => {
    const { w, api } = await begin($, on)
    expect(await wr(api, 'src/app.ts')).toContain('Plan stage')
    w.files.delete(STATE)
    await refresh(api)
    expect(await wr(api, 'src/app.ts')).toContain('Plan stage')
    expect((await refresh(api)).text ?? '').not.toContain('No Temper run is active')
  })

  test('the file unreadable (chmod 000 by someone else): enforcement stays', async ($, on) => {
    const { w, api } = await begin($, on)
    w.unreadable = new Set([STATE])
    await refresh(api)
    expect(await wr(api, 'src/app.ts')).toContain('Plan stage')
    expect(await sh(api, 'scripts/temper override plan --reason x')).toMatch(T)
  })

  test('the file corrupt: enforcement stays', async ($, on) => {
    const { w, api } = await begin($, on)
    w.files.set(STATE, '{"spec":')
    await refresh(api)
    expect(await wr(api, 'src/app.ts')).toContain('Plan stage')
  })

  test('the file removed: the native hook still may not be switched off', async ($, on) => {
    const { w, api } = await begin($, on, { next: 'review', gates: ['intent', 'plan', 'build'], head: 'main' })
    w.files.delete(STATE)
    await refresh(api)
    expect(await sh(api, 'git commit --no-verify -m x')).toMatch(T)
  })

  test('the file comes back readable: the real state is read again', async ($, on) => {
    const { w, api } = await begin($, on)
    const saved = w.files.get(STATE) ?? ''
    w.files.delete(STATE)
    await refresh(api)
    w.files.set(STATE, saved.replace('"next_stage":"plan"', '"next_stage":"build"'))
    await refresh(api)
    // (src/app.ts is a file of the plan: another file shows the Build phase is the one that applies)
    expect(await wr(api, 'lib/other.ts')).toContain('scope drift')
  })

  test('legit: a finished run (Done) whose state is archived is no run any more', async ($, on) => {
    const { w, api } = await begin($, on, { next: 'commit', gates: ['intent', 'plan', 'build', 'review', 'check'], head: 'main' })
    w.files.delete(STATE)
    const text = (await refresh(api)).text ?? ''
    expect(text).toContain('No Temper run is active')
    expect(await wr(api, 'src/app.ts')).toBeUndefined()
  })

  test('the person turns enforcement off: that is the way out', async ($, on) => {
    const { w, api } = await begin($, on)
    w.files.delete(STATE)
    await refresh(api)
    await api.command.run({ command: 'temper:temper', args: 'enforcement off', origin: { kind: 'composer' } })
    expect(await wr(api, 'src/app.ts')).toBeUndefined()
  })
})

// ---- 3. the denylist for writes to guarded files -----------------------------------------------------------
describe('finding 3: a plain write onto a file of the CLI is refused; a read is not', () => {
  const G = '.temper/gates.json'
  // A write the reader does not see (a program that builds the path, an archive, a cd first, a glob) is a known limit.
  const attempts: Record<string, string> = {
    'a here string to tee': `tee ${G} <<< '{}'`,
    'a quote split name': 'cp /tmp/g .tem""per/gates.json',
    'sed -i on a guarded file': `sed -i s/a/b/ ${G}`,
    'jq write by redirect': `jq . /tmp/g > ${G}`,
    'cp -l (a hard link)': `cp -l /tmp/g ${G}`,
    'sed -i on events': `sed -i s/a/b/ ${SPEC}/events/1.json`,
    'mv over the file': `mv /tmp/g ${G}`,
    'mv the file away': `mv ${G} /tmp/g`,
    'rm of the evidence ledger': 'rm .temper/evidence/build.json',
    'a redirect onto the view': 'echo {} > .temper/view.json',
    'truncate': `truncate -s 0 ${G}`,
  }
  for (const [name, cmd] of Object.entries(attempts)) {
    test(`refused: ${name}`, async ($, on) => {
      const { api } = await begin($, on, { next: 'build' })
      expect(await sh(api, cmd)).toMatch(T)
    })
  }

  const fine: Record<string, string> = {
    cat: `cat ${G}`,
    jq: `jq '.build.verdict' ${G}`,
    grep: `grep -n verdict ${G}`,
    head: 'head -20 .temper/overrides.json',
    'ls -la': 'ls -la .temper/',
    stat: 'stat .temper/build-state.json',
    wc: `wc -l ${G} .temper/status.json`,
    'git diff': `git diff -- ${G}`,
    'git log': 'git log --oneline -- .temper/status.json',
    'git show': `git show HEAD:${G}`,
    'test -f': 'test -f .temper/build-state.json && echo yes',
    'cat to a copy elsewhere': `cat ${G} > /tmp/g.json`,
    'reading with a redirect in': `grep verdict < ${G}`,
    'the temper cli': 'scripts/temper gate build',
    'the temper cli on a spec path': `scripts/temper gate build --spec-path ${SPEC}`,
    'a find that only lists': "find . -name '*.json' -not -path './node_modules/*'",
    'echo of the name': `echo ${G}`,
    'git add of the spec folder': `git add ${SPEC}/`,
    'git add of the spec folder, then status': `git add ${SPEC}/ && git status --short`,
    'a grep in the specs for events': `grep -rn events ${SPEC}/plan.md`,
    'find with a cat exec': "find .temper -name 'gates.json' -exec cat {} \\;",
  }
  for (const [name, cmd] of Object.entries(fine)) {
    test(`allowed: ${name}`, async ($, on) => {
      const { api } = await begin($, on, { next: 'build' })
      expect(await sh(api, cmd)).toBeUndefined()
    })
  }

  test('a commit message that names a guarded file is a commit, not a write', async ($, on) => {
    const { api } = await begin($, on, { next: 'check', gates: ['intent', 'plan', 'build', 'review', 'check'], head: 'main' })
    expect(await sh(api, 'git commit -m "docs: explain gates.json and build-state.json"')).toBeUndefined()
  })

  test('with no run active the new rule is silent (a sort that only reads the file)', async ($, on) => {
    const w = world(on, {}, { fakeCli: true, projectRoot: '/repo' })
    await ($ as Api).session.start(START)
    expect(w.files.size).toBe(0)
    expect(await sh($ as Api, `sort -o /tmp/out ${G}`)).toBeUndefined()
  })
})

// ---- 4. the commit gate is the native pre-commit hook (ADR 0012) ---------------------------------------------
describe('finding 4: a plain commit is for the native hook; a commit the hook does not see waits', () => {
  const REVIEW: Opts = { next: 'review', head: 'main', gates: ['intent', 'plan', 'build'] }

  // The mod does not judge what a staging holds: the hook checks every gate on the commit itself.
  for (const cmd of ['git stage src/x.ts', 'git stash pop', 'git reset --soft HEAD~1', 'git add src/*.ts', 'cd src && git add x.ts']) {
    test(`${cmd}, then a plain commit: left to the native hook`, async ($, on) => {
      const { api } = await begin($, on, REVIEW)
      expect(await sh(api, cmd), cmd).toBeUndefined()
      expect(await sh(api, 'git commit -m "docs: x"')).toBeUndefined()
    })
  }

  test('legit: with no run active a merge is the person\'s own', async ($, on) => {
    world(on, {}, { fakeCli: true, projectRoot: '/repo' })
    await ($ as Api).session.start(START)
    expect(await sh($ as Api, 'git merge feature/evil')).toBeUndefined()
  })

  test('commit --no-verify and -n skip the native pre-commit hook: refused', async ($, on) => {
    const { api } = await begin($, on, { next: 'build', green: true })
    for (const cmd of ['git commit --no-verify -m x', 'git commit -n -m x', 'git commit -nm x', 'git commit -m x --no-verify', 'git -c core.hooksPath=/dev/null commit -m x']) {
      expect(await sh(api, cmd), cmd).toMatch(T)
    }
    expect(await sh(api, 'git commit -m "fix: the -n flag"')).toBeUndefined()
  })

  test('the hooks of git are not changed while a run is active', async ($, on) => {
    const { api } = await begin($, on, { next: 'build' })
    for (const cmd of ['git config core.hooksPath /tmp/h', 'git config core.hookspath /tmp/h', 'git config --local core.hooksPath ""', 'echo exit 0 > .git/hooks/pre-commit', 'rm .git/hooks/pre-commit', 'chmod -x .git/hooks/pre-commit', 'cp /tmp/h .git/hooks/pre-commit', 'git config --unset core.hooksPath', 'ln -sf /bin/true .git/hooks/pre-commit']) {
      expect(await sh(api, cmd), cmd).toMatch(T)
    }
    expect(await wr(api, '.git/hooks/pre-commit')).toMatch(T)
    expect(await sh(api, 'git config user.name "A"')).toBeUndefined()
    expect(await sh(api, 'cat .git/hooks/pre-commit')).toBeUndefined()
  })
})

// ---- 5. a decision counts at the run and the step it was made at ----------------------------------------------
describe('finding 5: a decision counts at its run and step, and no longer', () => {
  test('advance; exit 1 executed the advance: the approval does not approve a second advance', async ($, on) => {
    const { w, api } = await begin($, on, { gates: ['intent', 'plan'], head: 'main', answers: ['Continue to Build (Recommended)'] })
    await ask(api, w)
    const first = await api.tool.call({ tool: 'Bash', command: 'scripts/temper state advance plan_complete build; exit 1' })
    expect(first.deny).toBeUndefined()
    expect(first.isError).toBe(true)
    expect(JSON.parse(w.files.get('.temper/build-state.json') ?? '{}').next_stage).toBe('build')
    expect(await sh(api, 'scripts/temper state advance plan_complete build')).toMatch(T)
  })

  test('a call that failed with no effect leaves the approval in place (the retry works)', async ($, on) => {
    const { w, api } = await begin($, on, { gates: ['intent', 'plan'], head: 'main', answers: ['Continue to Build (Recommended)'] })
    await ask(api, w)
    w.cliFailures = 1
    const failed = await api.tool.call({ tool: 'Bash', command: 'scripts/temper state advance plan_complete build' })
    expect(failed.isError).toBe(true)
    expect(await sh(api, 'scripts/temper state advance plan_complete build')).toBeUndefined()
  })

  test('an approval made before a step back to the plan is not an approval any more', async ($, on) => {
    const { w, api } = await begin($, on, { gates: ['intent', 'plan'], answers: ['Continue to Build (Recommended)', why('Loop back to Plan', 'rework the plan')] })
    await ask(api, w)
    expect(await sh(api, 'scripts/temper state advance plan_complete build')).toBeUndefined()
    w.files.set('.temper/gates.json', JSON.stringify({ intent: { verdict: 'PASS' }, plan: { verdict: 'PASS' }, build: { verdict: 'FAIL' } }))
    w.files.delete('.temper/view.json')
    await ask(api, w)
    expect(await sh(api, "scripts/temper state loop build plan --reason 'rework the plan'")).toBeUndefined()
    expect(JSON.parse(w.files.get('.temper/build-state.json') ?? '{}').next_stage).toBe('plan')
    expect(await sh(api, 'scripts/temper state advance plan_complete build')).toMatch(T)
  })

  test('a decision of another run does not count', async ($, on) => {
    const store = { 'dec:run-old': [{ id: 'd1', run: 'run-old', step: 3, stage: 'plan', ts: 1, kind: 'gate', label: 'Continue to Build (Recommended)', move: 'approve', calls: ['scripts/temper state advance plan_complete build'], steps: [], reason: '' }], decruns: ['run-old'] }
    const { api } = await begin($, on, { gates: ['intent', 'plan'], store })
    expect(await sh(api, 'scripts/temper state advance plan_complete build')).toMatch(T)
  })

  test('a decision of an earlier step of the same run does not count', async ($, on) => {
    const store = { 'dec:run-pw': [{ id: 'd1', run: 'run-pw', step: 2, stage: 'plan', ts: 1, kind: 'gate', label: 'Continue to Build (Recommended)', move: 'approve', calls: ['scripts/temper state advance plan_complete build'], steps: [], reason: '' }], decruns: ['run-pw'] }
    const { api } = await begin($, on, { gates: ['intent', 'plan'], store })
    expect(await sh(api, 'scripts/temper state advance plan_complete build')).toMatch(T)
  })

  test('control: the same decision at the current step counts', async ($, on) => {
    const store = { 'dec:run-pw': [{ id: 'd1', run: 'run-pw', step: 3, stage: 'plan', ts: 1, kind: 'gate', label: 'Continue to Build (Recommended)', move: 'approve', calls: ['scripts/temper state advance plan_complete build'], steps: [], reason: '' }], decruns: ['run-pw'] }
    const { api } = await begin($, on, { gates: ['intent', 'plan'], store })
    expect(await sh(api, 'scripts/temper state advance plan_complete build')).toBeUndefined()
  })
})

// ---- 6. no advance lowers the stage --------------------------------------------------------------------------
describe('finding 6: an advance does not move the run backwards, and does not switch write enforcement off', () => {
  const AT_REVIEW: Opts = { next: 'review', gates: ['intent', 'plan', 'build'] }

  test('at Review, advance plan_complete build is refused', async ($, on) => {
    const { w, api } = await begin($, on, AT_REVIEW)
    expect(await sh(api, 'scripts/temper state advance plan_complete build')).toMatch(T)
    expect(JSON.parse(w.files.get('.temper/build-state.json') ?? '{}').next_stage).toBe('review')
  })

  test('and a write outside the Review stage stays refused afterwards', async ($, on) => {
    const { api } = await begin($, on, AT_REVIEW)
    await sh(api, 'scripts/temper state advance plan_complete build')
    await refresh(api)
    expect(await wr(api, 'src/app.ts')).toContain('Review')
  })

  test('a lowering advance is refused even with the person\'s override at Review', async ($, on) => {
    const { w, api } = await begin($, on, { ...AT_REVIEW, fail: ['review'], answers: [why('Override and continue', 'reviewed by hand')] })
    await ask(api, w)
    expect(await sh(api, 'scripts/temper state advance plan_complete build')).toMatch(T)
  })

  test('legit: a skip of Plan, then the advance out of Plan, at Plan', async ($, on) => {
    const { w, api } = await begin($, on, { next: 'plan', gates: ['intent'], fail: ['plan'], answers: [why('Override and continue', 'skip plan')] })
    await ask(api, w)
    expect(await sh(api, "scripts/temper override plan --reason 'skip plan'")).toBeUndefined()
    expect(await sh(api, 'scripts/temper state advance plan_complete build')).toBeUndefined()
  })
})

// ---- 7. files and keys that control the run ---------------------------------------------------------------
describe('finding 7: the run controls are not writable by the model', () => {
  const dir = async ($: unknown, on: Parameters<typeof world>[0]) => begin($, on, { next: 'build' })
  test('.claude/temper.config by the editing tools while a run is active', async ($, on) => {
    const { api } = await dir($, on)
    expect(await wr(api, '.claude/temper.config')).toMatch(T)
    expect(await wr(api, '/repo/.claude/temper.config')).toMatch(T)
  })
  for (const cmd of ["echo 'autonomy:' >> .claude/temper.config", 'sed -i s/false/true/ .claude/temper.config', 'cp /tmp/weak .claude/temper.config', 'tee .claude/temper.config < /tmp/weak', 'mv /tmp/weak .claude/temper.config', 'rm .claude/temper.config', "printf 'x' > .claude/Temper.config"]) {
    test(`Bash: ${cmd}`, async ($, on) => {
      const { api } = await dir($, on)
      expect(await sh(api, cmd)).toMatch(T)
    })
  }
  test('the evidence ledger and the loop counter are the CLI\'s', async ($, on) => {
    const { api } = await dir($, on)
    expect(await wr(api, '.temper/evidence/build.json')).toMatch(T)
    expect(await wr(api, '.temper/feedback-loops.json')).toMatch(T)
    expect(await sh(api, 'echo [] > .temper/evidence/review.json')).toMatch(T)
    expect(await sh(api, 'echo {} > .temper/feedback-loops.json')).toMatch(T)
    expect(await sh(api, 'rm .temper/evidence/build.json')).toMatch(T)
    expect(await sh(api, 'cat .temper/evidence/build.json')).toBeUndefined()
    expect(await sh(api, 'scripts/temper evidence add build --claim "unit tests" --exit-code 0')).toBeUndefined()
  })
  test('with no run active the config can be written (the person /temper:init)', async ($, on) => {
    const w = world(on, {}, { fakeCli: true, projectRoot: '/repo' })
    await ($ as Api).session.start(START)
    expect(w.files.size).toBe(0)
    expect(await wr($ as Api, '.claude/temper.config')).toBeUndefined()
  })
  test('state keys: command is not the model\'s', async ($, on) => {
    const { api } = await dir($, on)
    expect(await sh(api, 'scripts/temper state set command fix')).toMatch(T)
  })
  test('state keys: complexity is set while planning, not after the plan was approved', async ($, on) => {
    const plan = await begin($, on, { next: 'plan' })
    expect(await sh(plan.api, 'scripts/temper state set complexity medium')).toBeUndefined()
  })
  test('state keys: complexity after the plan is refused (it would skip Design)', async ($, on) => {
    const { api } = await dir($, on)
    expect(await sh(api, 'scripts/temper state set complexity simple')).toMatch(T)
  })
  test('state keys: base_sha is the reviewed form, in Plan or Build only', async ($, on) => {
    const { api } = await dir($, on)
    expect(await sh(api, 'scripts/temper state set base_sha "$(git rev-parse HEAD)"')).toBeUndefined()
    expect(await sh(api, 'scripts/temper state set base_sha 0a1b2c3d4e5f')).toBeUndefined()
    expect(await sh(api, 'scripts/temper state set base_sha "$(git rev-parse HEAD~1)"')).toMatch(T)
    expect(await sh(api, 'scripts/temper state set base_sha HEAD')).toMatch(T)
  })
  test('state keys: base_sha is refused at Review', async ($, on) => {
    const { api } = await begin($, on, { next: 'review', gates: ['intent', 'plan', 'build'] })
    expect(await sh(api, 'scripts/temper state set base_sha "$(git rev-parse HEAD)"')).toMatch(T)
  })
  test('state keys: regression_test and task stay (Fix and Build bookkeeping)', async ($, on) => {
    const { api } = await dir($, on)
    expect(await sh(api, 'scripts/temper state set regression_test tests/a.test.ts')).toBeUndefined()
    expect(await sh(api, 'scripts/temper state set task 2')).toBeUndefined()
  })
})

// ---- 8. state loop is for the person's Loop back ----------------------------------------------------------
describe('finding 8: state loop names the stage the run is at, and the back answer counts once', () => {
  const AT_CHECK: Opts = { next: 'check', gates: ['intent', 'plan', 'build', 'review'], fail: ['check'], answers: [why('Loop back to Build (Recommended)', 'rework')] }
  test('the same loop twice is refused the second time', async ($, on) => {
    const { w, api } = await begin($, on, AT_CHECK)
    await ask(api, w)
    expect(await sh(api, "scripts/temper state loop check build --reason 'rework'")).toBeUndefined()
    expect(await sh(api, "scripts/temper state loop check build --reason 'rework'")).toMatch(T)
    // A set to the stage the run is at changes nothing, so it needs no decision.
    expect(await sh(api, 'scripts/temper state set next_stage build')).toBeUndefined()
  })
  test('a loop from another stage than the one the run is at is refused', async ($, on) => {
    const { w, api } = await begin($, on, AT_CHECK)
    await ask(api, w)
    expect(await sh(api, "scripts/temper state loop plan build --reason 'x'")).toMatch(T)
    expect(await sh(api, "scripts/temper state loop build build --reason 'x'")).toMatch(T)
    expect(await sh(api, "scripts/temper state loop check build --reason 'x'")).toBeUndefined()
  })
  test('a loop that changed nothing leaves the answer in place (the retry works)', async ($, on) => {
    const { w, api } = await begin($, on, AT_CHECK)
    await ask(api, w)
    // `; exit 1` after a loop is the fake CLI's stand in for a loop that failed and moved nothing.
    const first = await api.tool.call({ tool: 'Bash', command: "scripts/temper state loop check build --reason 'x'; exit 1" })
    expect(first.deny).toBeUndefined()
    expect(await sh(api, "scripts/temper state loop check build --reason 'x'")).toBeUndefined()
  })
  test('without the answer the loop is refused', async ($, on) => {
    const { api } = await begin($, on, { ...AT_CHECK, answers: [] })
    expect(await sh(api, "scripts/temper state loop check build --reason 'x'")).toMatch(T)
  })
})

// ---- the everyday commands of a Build agent stay allowed ------------------------------------------------------
describe('everyday Build commands are not touched by the stricter rules', () => {
  const everyday = [
    'npm test',
    'npm run build 2>&1 | tail -20',
    'python3 -m pytest tests -k foo -q',
    'git status',
    'git diff --stat',
    'git log --oneline -5',
    'git add src/a.ts tests/a.test.ts',
    'git add src/a.ts && git commit -m "feat(pw): a scenario [AC-01]"',
    'git commit -am "feat(pw): b [AC-02]"',
    'git push origin feature/pw',
    'git checkout -b feature/other',
    'git checkout main',
    'git checkout -- src/a.ts',
    'git stash list',
    'mkdir -p .temper/specs/x && echo hi > .temper/specs/x/notes.md',
    'ls -la .temper/specs/',
    'cat .temper/specs/pw/plan.md | head -50',
    "find . -name '*.test.ts' -not -path './node_modules/*' | head",
    "find src -type f -name '*.ts' | xargs wc -l",
    "find . -name '*.tmp' -delete",
    "find . -name '*.pyc' -exec rm {} +",
    'rm -rf node_modules/.cache',
    'rm -f /tmp/x.log',
    'cp src/a.ts src/b.ts',
    "sed -i 's/a/b/' src/a.ts",
    'chmod +x scripts/*.sh',
    'chmod 755 scripts/run.sh',
    'bash scripts/selftest/test-temper.sh',
    'T=$(ls /opt/plugins/temper/1/scripts/temper); $T gate build',
    "python3 - <<'PY'\nimport json\nprint(json.dumps({'a': 1}))\nPY",
    'echo "x" | tee notes.txt',
    'cat package.json | jq .name',
    'eval "$(mise activate zsh)"',
    'source venv/bin/activate && pytest',
    'cd src && npm test',
    'git ls-files | xargs grep -n foo',
    'ls | xargs echo',
    'npm ls --depth=0',
    'bash -c "cd $(pwd) && make test"',
    "bash -c 'echo $PWD'",
    'scripts/temper evidence run --stage build --claim "unit tests" --phase green -- npm test',
    'scripts/temper gate build',
    'scripts/temper state get next_stage',
    'cat .temper/gates.json | jq .build',
    // Seen in real sessions: the plugin's acceptance checker, a sed that only prints, an eval of a project script,
    // a report kept next to the evidence ledger, a regular expression that looks like a glob.
    'python3 /Users/x/plugin/scripts/acceptance.py check .temper/specs/pw/intent.md .temper/evidence/check.json',
    'python3 scripts/acceptance.py plan .temper/specs/pw/intent.md .temper/evidence/plan.json',
    'sed -n 1,30p .temper/gates.json',
    "awk '{print $1}' .temper/gates.json",
    'eval "$(scripts/ensure-jdk24.sh --export)" >/dev/null',
    'mkdir -p .temper/evidence && node --test --experimental-test-coverage 2>&1 | tee .temper/evidence/coverage-report.txt | tail -20',
    "grep -E 'status=.(SURVIVED|NO_COVERAGE)' mutations.xml | sed -E 's/.*status=.([A-Z_]+).*<line>([0-9]+)<.*/\\1 \\2/' | head -20",
    "env -i | sed 's/=.*//' | sort",
    'sed -n 20,35p templates/temper.config.default',
    "ls -t /var/log/x/*.log | xargs -I{} sh -c 'echo {}; grep -c foo {}'",
    // A comment is not part of the command.
    'npm test          # the hook in .git/hooks/pre-commit runs on commit',
    'npm test # the verdict goes to .temper/gates.json',
    'echo "a # b" && ls src # build-state.json',
  ]
  for (const cmd of everyday) {
    test(cmd, async ($, on) => {
      const { api } = await begin($, on, { next: 'build', green: true })
      expect(await sh(api, cmd)).toBeUndefined()
    })
  }
})

// ---- 9. the guard fails closed for Bash; the root -------------------------------------------------------------
describe('finding 9: failures', () => {
  test('an error inside the guard lets a tool that is not Bash through (the mod fails open)', async ($, on) => {
    const { w, api } = await begin($, on, { next: 'build', answers: ['Allow once'] })
    await api.tool.call({ tool: 'AskUserQuestion', questions: [{ question: 'Outside the plan: src/once.ts\nWhy: a fix\nChange: one line', header: 'Scope drift', multiSelect: false, options: [{ label: 'Allow once', description: 'x' }] }] })
    w.failWrites = true
    // The write spends the Allow once answer: the store write fails and the guard throws.
    expect(await wr(api, 'src/once.ts')).toBeUndefined()
  })
  test('an error inside the guard does not stop a tool that is not Bash', async ($, on) => {
    const { w, api } = await begin($, on, { next: 'check', gates: ['intent', 'plan', 'build', 'review', 'check'], head: 'main' })
    w.failWrites = true
    expect(await api.tool.call({ tool: 'Read', file_path: 'src/app.ts' }).then(r => r.deny)).toBeUndefined()
  })

  test('a run that starts above the folder the session began in is found (the root is looked for again)', async ($, on) => {
    const api = $ as Api
    const w = world(on, {}, { fakeCli: true, projectRoot: '/repo', runAt: '/repo' })
    await api.session.start({ ...START, cwd: '/repo/pkg' })
    // No run yet: nothing is enforced.
    expect(await wr(api, 'src/app.ts')).toBeUndefined()
    // The run starts at /repo (the CLI root), above the session folder.
    for (const [k, v] of Object.entries({ ...runFiles({ nextStage: 'plan' }), '.temper/build-state.json': JSON.stringify({ spec: 'pw', spec_path: SPEC, next_stage: 'plan', command: 'temper', branch: 'feature/pw' }) })) w.files.set(k, v)
    await refresh(api)
    expect(await wr(api, '/repo/src/app.ts')).toContain('Plan stage')
  })
})
