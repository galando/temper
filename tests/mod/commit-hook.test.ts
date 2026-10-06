// The Temper commit hook (9.6.6). The hook git runs is <git common dir>/temper-gate/pre-commit (core.hooksPath names that
// folder), and the line an older Temper printed runs <git common dir>/temper-pre-commit. While a run is active the mod
// guards both exactly as it guards .git/hooks: the editing tools and every Bash form that changes them are refused, with
// the text the git hooks get, and that text names the Temper commit hook. With no run active, or a finished one, they
// pass, so the person can install the hook. Reading them always passes.
import { describe, expect, test } from 'claude-code/testing'

import { classifyBash, protectedKind } from '../../hooks/temper-mod/core/bash'
import type { Phase } from '../../hooks/temper-mod/core/events'
import { initialState } from '../../hooks/temper-mod/core/machine'
import type { RunState } from '../../hooks/temper-mod/core/machine'
import { evaluate } from '../../hooks/temper-mod/core/rules'
import type { RuleContext, RuleResult } from '../../hooks/temper-mod/core/rules'
import { adv, person, stateAt } from './helpers'
import { SPEC, runFiles } from './run-files'
import { denyText, world } from './world'

const HOOK_DENY =
  'Temper: the git hooks, the Temper commit hook and core.hooksPath are the native commit gate. Do not change them while a run is active. ' +
  'Next: ask the user, or finish the run first.'

const ctx: RuleContext = { root: '/repo', specDir: SPEC, planFiles: ['src/app.ts'] }

// The kept hook, the folder core.hooksPath names, and the file the older line runs; each with the .git/hooks path it
// stands next to, which the mod already guarded.
const HOOK = '.git/temper-gate/pre-commit'
const FOLDER = '.git/temper-gate'
const OLDER = '.git/temper-pre-commit'
const GIT_HOOK = '.git/hooks/pre-commit'
const GIT_HOOKS = '.git/hooks'

const ACTIVE: Array<[string, RunState]> = [
  ...(['intent', 'plan', 'build', 'review', 'check', 'fix'] as Phase[]).map((p): [string, RunState] => [p, stateAt(p)]),
  ['build, paused', stateAt('build', [{ type: 'pause', ...person }])],
]
const INACTIVE: Array<[string, RunState]> = [
  ['no run', initialState()],
  ['a finished run', stateAt('check', [adv('check', 'done')])],
]

const isDeny = (r: RuleResult): r is Extract<RuleResult, { deny: string }> => 'deny' in r
const bash = (s: RunState, command: string): RuleResult => evaluate(s, ctx, { tool: 'Bash', input: { command } })
const fill = (form: string, target: string): string => form.split('{}').join(target)
// A deny with the path it names written as {}, so the refusal for the new path and for the git hook can be compared.
const shape = (r: RuleResult, target: string): string => (isDeny(r) ? r.deny.split(target).join('{}') : 'allowed')

describe('the Temper commit hook paths are the native commit gate', () => {
  const guarded = [
    HOOK,
    FOLDER,
    `${FOLDER}/`,
    OLDER,
    // The temporary file install.sh makes in the folder before it moves it into place.
    `${FOLDER}/pre-commit.tmp.Xa81`,
    // A folder put where the older file was: the line runs the hook only when it is a file.
    `${OLDER}/x`,
    `/repo/${HOOK}`,
    `/repo/${OLDER}`,
    // A linked worktree: the git common dir is the main checkout's .git folder.
    `/main/${HOOK}`,
    `../main/${OLDER}`,
    `.git/./temper-gate/../temper-gate/pre-commit`,
    // Folders are case insensitive on macOS.
    '.GIT/Temper-Gate/PRE-COMMIT',
    '.git/TEMPER-PRE-COMMIT',
  ]
  for (const p of guarded) {
    test(`${p} is guarded as the git hooks are`, () => {
      expect(protectedKind(p)).toBe('hooks')
    })
  }
  for (const p of ['.git/temper-gate-notes', '.git/temper-pre-commit.bak', 'docs/temper-gate/pre-commit', 'temper-pre-commit', 'scripts/guards/temper-pre-commit', '.git/worktrees/x/HEAD']) {
    test(`${p} is no guarded path`, () => {
      expect(protectedKind(p)).toBeNull()
    })
  }
})

describe('the editing tools while a run is active: refused exactly as a change to .git/hooks', () => {
  const tools = ['Write', 'Edit', 'MultiEdit', 'NotebookEdit'] as const
  const input = (tool: string, path: string) => (tool === 'NotebookEdit' ? { notebook_path: path } : { file_path: path })
  const paths: Array<[string, string]> = [
    [HOOK, GIT_HOOK],
    [FOLDER, GIT_HOOKS],
    [OLDER, GIT_HOOK],
    [`/repo/${HOOK}`, `/repo/${GIT_HOOK}`],
    [`/repo/${OLDER}`, `/repo/${GIT_HOOK}`],
    [`/main/${HOOK}`, `/main/${GIT_HOOK}`],
  ]
  for (const [name, s] of ACTIVE) {
    for (const tool of tools) {
      test(`${name}: ${tool}`, () => {
        for (const [path, gitPath] of paths) {
          const r = evaluate(s, ctx, { tool, input: input(tool, path) })
          expect(r, path).toEqual({ deny: HOOK_DENY })
          expect(r, path).toEqual(evaluate(s, ctx, { tool, input: input(tool, gitPath) }))
        }
      })
    }
  }
  test('the text names the Temper commit hook alongside the git hooks', () => {
    expect(HOOK_DENY).toContain('the git hooks, the Temper commit hook and core.hooksPath')
  })
})

describe('the editing tools with no run active: the person installs the hook', () => {
  for (const [name, s] of INACTIVE) {
    for (const tool of ['Write', 'Edit', 'MultiEdit'] as const) {
      test(`${name}: ${tool}`, () => {
        for (const path of [HOOK, OLDER, `${FOLDER}/pre-commit.tmp.Xa81`, `/repo/${HOOK}`, `/main/${OLDER}`]) {
          expect(isDeny(evaluate(s, ctx, { tool, input: { file_path: path } })), path).toBe(false)
        }
      })
    }
  }
})

// Each form changes the hook file or the folder; `{}` is the path. The same form on the git hook gets the same answer.
const FILE_FORMS = [
  'echo exit 0 > {}',
  "printf 'exit 0\\n' >> {}",
  'cat /tmp/h > {}',
  ': > {}',
  'cp /tmp/h {}',
  'cp -f /tmp/h {}',
  'mv /tmp/h {}',
  'mv -f {} /tmp/h',
  'install -m 755 /tmp/h {}',
  'rsync /tmp/h {}',
  'ln -sf /bin/true {}',
  'rm {}',
  'rm -f {}',
  'unlink {}',
  'touch {}',
  'truncate -s 0 {}',
  'chmod -x {}',
  'chmod 644 {}',
  "sed -i 's/exit 1/exit 0/' {}",
  "sed -i '' -e 's/exit 1/exit 0/' {}",
  "perl -pi -e 's/exit 1/exit 0/' {}",
  'tee {} < /tmp/h',
  'echo exit 0 | tee -a {}',
  'dd if=/tmp/h of={}',
  'curl -o {} https://example.com/h',
  "python3 -c \"open('{}', 'w').write('exit 0')\"",
  'H={}; echo exit 0 > "$H"',
  'mkdir {}',
]
const FOLDER_FORMS = [
  'rm -rf {}',
  'rm -r {}',
  'rmdir {}',
  'mv {} /tmp/old',
  'mv /tmp/new {}',
  'cp -R /tmp/new {}',
  'cp /tmp/h {}/',
  'chmod 000 {}',
  'chmod -R a-x {}',
  'ln -sfn /tmp/other {}',
  'tar -xf /tmp/h.tar -C {}',
  'echo exit 0 > {}/pre-commit',
  'mv {}/pre-commit.tmp.Xa81 {}/pre-commit',
  'cd {} && echo exit 0 > pre-commit',
  'cd {} && rm pre-commit',
  'find {} -delete',
]
// The same changes written from inside the git folder, or with an absolute path.
const SPELLED: Array<[string, string, string]> = [
  ['cd .git && rm {}', 'temper-pre-commit', 'hooks/pre-commit'],
  ['cd .git && echo exit 0 > {}', 'temper-gate/pre-commit', 'hooks/pre-commit'],
  ['echo exit 0 > {}', `/repo/${HOOK}`, `/repo/${GIT_HOOK}`],
  ['rm -f {}', `/repo/${OLDER}`, `/repo/${GIT_HOOK}`],
  ['cp /tmp/h {}', `/main/${HOOK}`, `/main/${GIT_HOOK}`],
]
const CASES: Array<[string, string, string]> = [
  ...FILE_FORMS.flatMap((f): Array<[string, string, string]> => [
    [f, HOOK, GIT_HOOK],
    [f, OLDER, GIT_HOOK],
  ]),
  ...FOLDER_FORMS.map((f): [string, string, string] => [f, FOLDER, GIT_HOOKS]),
  ...SPELLED,
]

describe('Bash while a run is active: every change is refused exactly as a change to .git/hooks', () => {
  for (const [name, s] of [ACTIVE[2], ACTIVE[4], ACTIVE[6]] as Array<[string, RunState]>) {
    for (const [form, target, gitTarget] of CASES) {
      const command = fill(form, target)
      test(`${name}: ${command}`, () => {
        const r = bash(s, command)
        expect(isDeny(r)).toBe(true)
        expect(shape(r, target)).toBe(shape(bash(s, fill(form, gitTarget)), gitTarget))
      })
    }
  }
  // The forms that write the path get the git hooks' own text, which names the Temper commit hook.
  const writes = [
    `echo exit 0 > ${HOOK}`,
    `cp /tmp/h ${HOOK}`,
    `mv /tmp/h ${OLDER}`,
    `rm ${OLDER}`,
    `rm -rf ${FOLDER}`,
    `chmod -x ${HOOK}`,
    `sed -i 's/exit 1/exit 0/' ${HOOK}`,
    `tee ${OLDER} < /tmp/h`,
    `ln -sf /bin/true ${HOOK}`,
    `cd ${FOLDER} && echo exit 0 > pre-commit`,
    `echo exit 0 > /main/${HOOK}`,
    'rm .git/temper-{gate/pre-commit,x}',
    'echo exit 0 > .GIT/Temper-Gate/pre-commit',
  ]
  for (const command of writes) {
    test(`the git hooks' text: ${command}`, () => {
      expect(bash(stateAt('build'), command)).toEqual({ deny: HOOK_DENY })
    })
  }
  test('a write the guard cannot resolve, in a command that names the hook, fails closed', () => {
    for (const command of [`ls ${FOLDER}; echo exit 0 > "$D/pre-commit"`, `cat ${OLDER}; cp /tmp/h "$G"`]) {
      const r = bash(stateAt('build'), command)
      expect(denyText(isDeny(r) ? r : {}), command).toContain('Temper cannot check')
      // The same command on the git hooks is refused the same way.
      expect(r).toEqual(bash(stateAt('build'), command.replace(FOLDER, GIT_HOOKS).replace(OLDER, GIT_HOOK)))
    }
  })
})

describe('core.hooksPath stays as it is while a run is active', () => {
  const changes = [
    'git config core.hooksPath .git/hooks',
    `git config core.hooksPath ${FOLDER}`,
    `git config --local core.hooksPath /repo/${FOLDER}`,
    'git config --local core.hooksPath "$(git rev-parse --git-common-dir)/temper-gate"',
    'git config --unset core.hooksPath',
    'git config --local --unset-all core.hooksPath',
    'git -c core.hooksPath=/dev/null commit -m x',
    'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null git commit -m x',
    "printf '[core]\\n\\thooksPath = /tmp\\n' >> .git/config",
  ]
  for (const command of changes) {
    test(command, () => {
      const r = bash(stateAt('build'), command)
      expect(isDeny(r)).toBe(true)
      expect(denyText(isDeny(r) ? r : {})).toContain('core.hooksPath')
    })
  }
})

describe('Bash with no run active: the person installs, updates and removes the hook', () => {
  const forms = [
    ...CASES.filter(([form]) => !form.startsWith('find ')).map(([form, target]) => fill(form, target)),
    `git config --local core.hooksPath /repo/${FOLDER}`,
    'git config --unset core.hooksPath',
    'bash scripts/guards/install.sh',
  ]
  for (const [name, s] of INACTIVE) {
    for (const command of forms) {
      test(`${name}: ${command}`, () => {
        expect(bash(s, command)).toEqual({ allow: true })
      })
    }
  }
})

describe('reading the hook stays allowed while a run is active', () => {
  const reads = [
    `cat ${HOOK}`,
    `cat ${OLDER}`,
    `ls -la ${FOLDER}`,
    `head -n 5 ${OLDER}`,
    `grep -n temper ${HOOK}`,
    `test -x ${HOOK}`,
    `[ -f ${OLDER} ] && echo yes`,
    `stat ${HOOK}`,
    `diff ${HOOK} /tmp/h`,
    `shasum ${HOOK}`,
    `sed -n 1,5p ${HOOK}`,
    `wc -l ${OLDER}`,
    `cat /repo/${HOOK}`,
    'git config --get core.hooksPath',
    'git config core.hooksPath',
    'git rev-parse --git-common-dir',
  ]
  for (const command of reads) {
    test(command, () => {
      expect(bash(stateAt('build'), command)).toEqual({ allow: true })
      const c = classifyBash(command)
      expect(c.protectedWrites).toEqual([])
      expect(c.guardedUse).toEqual([])
      expect(c.hookTamper).toBe(false)
    })
  }
  test('the Read tool', () => {
    for (const path of [HOOK, OLDER, FOLDER]) expect(evaluate(stateAt('build'), ctx, { tool: 'Read', input: { file_path: path } })).toEqual({ allow: true })
  })
})

describe('what the classifier reports for the hook', () => {
  test('a write onto each path is a guarded write', () => {
    expect(classifyBash(`echo exit 0 > ${HOOK}`).protectedWrites).toEqual([HOOK])
    expect(classifyBash(`rm -rf ${FOLDER}`).protectedWrites).toEqual([FOLDER])
    expect(classifyBash(`mv /tmp/h ${OLDER}`).protectedWrites).toEqual([OLDER])
    expect(classifyBash(`cd ${FOLDER} && rm pre-commit`).protectedWrites).toEqual([HOOK])
  })
  test('an interpreter told the path can write it', () => {
    expect(classifyBash(`node -e "require('fs').writeFileSync('${HOOK}', '')"`).protectedWrites.map(p => protectedKind(p))).toContain('hooks')
    expect(classifyBash(`ruby -e "File.delete('${OLDER}')"`).protectedWrites.map(p => protectedKind(p))).toContain('hooks')
  })
  test('a command that names the hook and is not a plain read is a guarded use', () => {
    expect(classifyBash(`mkdir ${OLDER}`).guardedUse).toEqual([OLDER])
    expect(classifyBash(`bash ${HOOK}`).guardedUse).toEqual([HOOK])
  })
})

// Through the real hook, with the world standing in for the engine.
describe('through tool.call', () => {
  const edit = (path: string) => ({ tool: 'Edit', file_path: path, old_string: 'exit 1', new_string: 'exit 0' })
  const multi = (path: string) => ({ tool: 'MultiEdit', file_path: path, edits: [{ old_string: 'exit 1', new_string: 'exit 0' }] })
  const START = { cwd: '/repo', surface: null, isInteractive: false } as const
  test('a run in Build: Write, Edit, MultiEdit and Bash are refused; a read passes', async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }), { projectRoot: '/repo' })
    await $.session.start(START)
    expect(denyText(await $.tool.call({ tool: 'Write', file_path: HOOK, content: 'exit 0\n' }))).toBe(HOOK_DENY)
    expect(denyText(await $.tool.call(edit(`/repo/${HOOK}`)))).toBe(HOOK_DENY)
    expect(denyText(await $.tool.call(multi(OLDER)))).toBe(HOOK_DENY)
    expect(denyText(await $.tool.call({ tool: 'Bash', command: `echo exit 0 > ${HOOK}` }))).toBe(HOOK_DENY)
    expect(denyText(await $.tool.call({ tool: 'Bash', command: `rm -rf ${FOLDER}` }))).toBe(HOOK_DENY)
    expect(denyText(await $.tool.call({ tool: 'Bash', command: `cat ${HOOK}` }))).toBe('')
  })
  test('no run in the project: the hook can be written', async ($, on) => {
    world(on, {}, { projectRoot: '/repo' })
    await $.session.start(START)
    expect(denyText(await $.tool.call({ tool: 'Write', file_path: HOOK, content: 'exit 0\n' }))).toBe('')
    expect(denyText(await $.tool.call(edit(HOOK)))).toBe('')
    expect(denyText(await $.tool.call(multi(OLDER)))).toBe('')
    expect(denyText(await $.tool.call({ tool: 'Bash', command: `cp /tmp/h ${HOOK} && chmod +x ${HOOK}` }))).toBe('')
  })
})

// Temper's older hook folders: `.git/hooks-temper` (--global up to 9.6.4) and `.git/temper-git-hooks` (--global in
// 9.6.5). When one also holds hooks of other tools, install.sh leaves core.hooksPath on it and git runs its pre-commit,
// so while a run is active the mod guards both exactly as it guards .git/hooks.
describe("Temper's older hook folders are guarded as .git/hooks is", () => {
  for (const f of ['.git/hooks-temper', '.git/temper-git-hooks']) {
    const hook = `${f}/pre-commit`
    for (const p of [f, `${f}/`, hook, `${f}/pre-push`, `/repo/${hook}`, `/main/${hook}`, `${f.toUpperCase()}/PRE-COMMIT`]) {
      test(`${p} is guarded as the git hooks are`, () => {
        expect(protectedKind(p)).toBe('hooks')
      })
    }
    for (const p of [`${f}-notes`, `${f}.bak/pre-commit`, `docs/${f.slice('.git/'.length)}/pre-commit`]) {
      test(`${p} is no guarded path`, () => {
        expect(protectedKind(p)).toBeNull()
      })
    }
    for (const [name, s] of ACTIVE) {
      test(`${name}: the editing tools on ${hook} get the git hooks' text`, () => {
        for (const tool of ['Write', 'Edit', 'MultiEdit'] as const) {
          expect(evaluate(s, ctx, { tool, input: { file_path: hook } }), tool).toEqual({ deny: HOOK_DENY })
        }
      })
    }
    for (const [form, target, gitTarget] of [
      ...FILE_FORMS.map((form): [string, string, string] => [form, hook, GIT_HOOK]),
      ...FOLDER_FORMS.map((form): [string, string, string] => [form, f, GIT_HOOKS]),
    ]) {
      const command = fill(form, target)
      test(`build: ${command}`, () => {
        const r = bash(stateAt('build'), command)
        expect(isDeny(r)).toBe(true)
        expect(shape(r, target)).toBe(shape(bash(stateAt('build'), fill(form, gitTarget)), gitTarget))
      })
    }
    test(`reading ${f} stays allowed while a run is active`, () => {
      for (const command of [`cat ${hook}`, `ls -la ${f}`, `grep -n temper ${hook}`, `test -x ${hook}`]) {
        expect(bash(stateAt('build'), command), command).toEqual({ allow: true })
      }
    })
    test(`with no run active, ${f} can be changed`, () => {
      for (const [, s] of INACTIVE) {
        for (const command of [`rm -rf ${f}`, `echo exit 0 > ${hook}`]) expect(bash(s, command), command).toEqual({ allow: true })
      }
    })
  }
})
