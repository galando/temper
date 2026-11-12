// Three runs of Temper on a mock pyjokes project (9.8.4), with the real CLI, the mod's rule engine (mod mode) and
// scripted agents and person. Each walks faults one failed live run found:
//   pyjokes          a first plan whose G1 Validate runs a test G2 updates (the plan gate's group validate order row),
//                    a loop back to Intent that the next Plan agent hears about, a complex plan built on sonnet, a fresh
//                    review with a tests lens whose medium finding reaches the builder, a group check that fails after
//                    every task passed (fixed by one fix agent on the merged tree), temper output, a usage time filled late.
//   pyjokes-full     a medium plan at risk H: two fresh reviewers, a high finding answered and rechecked, Design, a
//                    critical Review finding that loops back to the Build fix pass, then a /temper:fix run.
//   pyjokes-blocked  a task whose test needs a file another task declares: `temper task blocked` parks it at once (no
//                    retry, no escalation) and the person's question recommends the loop back to Plan.
import fs from 'node:fs'
import path from 'node:path'

import { orchestrate, orchestrateFix } from './loop'
import type { Script } from './loop'
import { chained, expect, recommended, t, worktreeOf } from './scenarios'
import { ROOT, TEMPER, World } from './world'
import type { Json } from './world'

const SPEC = '.temper/specs/pyjokes'
const SUITE = 'python3 -m unittest discover -s unit -t .'
const EXPORTS = 'from .core import CategoryNotFoundError, get_joke, get_jokes\n\n__all__ = ["CategoryNotFoundError", "get_joke", "get_jokes"]\n'
const CORE = 'import random\n\nfrom .jokes_en import JOKES\n\n\nclass CategoryNotFoundError(KeyError):\n    """The category asked for does not exist."""\n\n\ndef get_jokes(category="neutral"):\n    if category not in JOKES:\n        raise CategoryNotFoundError(category)\n    return list(JOKES[category])\n\n\ndef get_joke(category="neutral"):\n    return random.choice(get_jokes(category))\n'

// ---- the project: pyjokes, a list of jokes by language and category ----
const BASE: Record<string, string> = {
  'README.md': '# pyjokes (mock)\n\nOne line jokes for programmers.\n',
  '.gitignore': '__pycache__/\n',
  'pyjokes/__init__.py': 'from .core import get_joke, get_jokes\n\n__all__ = ["get_joke", "get_jokes"]\n',
  'pyjokes/jokes_en.py': 'JOKES = {\n    "neutral": [\n        "There are 10 kinds of people: those who know binary and those who do not.",\n        "A SQL query walks into a bar, walks up to two tables and asks: may I join you?",\n    ],\n}\n',
  'pyjokes/core.py': 'import random\n\nfrom .jokes_en import JOKES\n\n\ndef get_jokes(category="neutral"):\n    return list(JOKES.get(category, []))\n\n\ndef get_joke(category="neutral"):\n    jokes = get_jokes(category)\n    return random.choice(jokes) if jokes else ""\n',
  'unit/__init__.py': '',
  'unit/test_core.py': 'import unittest\n\nfrom pyjokes import get_joke, get_jokes\n\n\nclass CoreTest(unittest.TestCase):\n    def test_neutral_has_jokes(self):\n        self.assertTrue(get_jokes("neutral"))\n\n    def test_a_joke_is_text(self):\n        self.assertIsInstance(get_joke(), str)\n\n    def test_unknown_category_is_empty(self):\n        self.assertEqual(get_jokes("nope"), [])\n',
  'unit/test_api.py': 'import inspect\nimport unittest\n\nimport pyjokes\nimport pyjokes.core\n\n\nclass ApiTest(unittest.TestCase):\n    def test_every_public_name_of_core_is_exported(self):\n        names = {n for n, v in vars(pyjokes.core).items() if not n.startswith("_") and (inspect.isfunction(v) or inspect.isclass(v)) and v.__module__ == "pyjokes.core"}\n        self.assertEqual(sorted(names - set(pyjokes.__all__)), [])\n',
}

const INTENT = `# Intent: Unknown categories raise, and a chuck category

**Author:** the person
**Status:** draft
**Created:** 2026-11-12
**Complexity:** complex

## Problem
A caller who asks pyjokes for a category that does not exist gets an empty list today, so a typo looks like a category
with no jokes. We want an unknown category to raise CategoryNotFoundError, and a chuck category of jokes to exist.

### Success Criteria
- [ ] AC-01 [required]: get_jokes and get_joke raise CategoryNotFoundError for a category that does not exist
  Why: a typo must not look like an empty category
  Validate: scenario — traced to a test below
- [ ] AC-02 [required]: a chuck category holds at least two jokes
  Why: the request asks for it
  Validate: scenario — traced to a test below

### Constraints
- standard library only (proposed)

### Scope and Non-goals
- In scope: the error and the chuck category
- Out of scope: other languages
- Must keep working: the neutral category and the public names of the package

### Target Users
- developer: asks for a category → gets jokes or a clear error

### Open Questions

### Rules covered

- Who: not applicable (a library call; any caller)
- When: not applicable (no time rule)
- How much: not applicable (no amounts)
- Exempt: not applicable (every category is checked)
- States: assumed (the jokes are constants; nothing changes state)
- Where it shows: assumed (the exception reaches the caller)
- Exceptions: assumed (the default category is neutral, which exists)

### Decisions

## Scenarios (BDD)

## Scenario Coverage Checklist

## Source Traceability
### Context Sources
- none: description only, nothing linked
`

const SCENARIOS = `## Scenarios (BDD)

#### Happy Path
\`\`\`gherkin
Scenario: an unknown category raises
  Given the pyjokes package
  When get_jokes is asked for the category nope
  Then CategoryNotFoundError is raised
  Note: unit
  Covers: AC-01
  Test: python3 -m unittest unit.test_errors
\`\`\`
\`\`\`gherkin
Scenario: chuck jokes exist
  Given the pyjokes package
  When get_jokes is asked for the category chuck
  Then it returns two jokes or more
  Note: unit
  Covers: AC-02
  Test: python3 -m unittest unit.test_chuck
\`\`\`

`

const PLAN = `# Plan: Unknown categories raise, and a chuck category

## Context Map
- use: pyjokes/ (3 files) - the package the change reaches
- use: unit/ (2 files) - the suite that checks it
- reviewed: auto - every source is current and on topic

## Architecture
core.py raises a new CategoryNotFoundError; jokes_en.py gains a chuck list.

## Blast Radius
pyjokes/core.py and pyjokes/__init__.py change; unit/test_core.py checks the old empty list and must be updated.

## Cross-Repo Search
- not available: no cross-repo search tool is connected, so local tools were used.
`

const task = (n: number, title: string, files: string[], depends: string, test: string, cases: string[], scen: string) =>
  `### Task ${n}: ${title}\n**File:** ${files.map(f => '`' + f + '`').join(', ')}\n**Depends:** ${depends}\n**Test:** \`${test}\`\n**Cases:**\n${cases.map(c => '- ' + c).join('\n')}\n**Traced to:** Scenario: "${scen}"\n- [ ] done\n`
const T1 = task(1, 'Raise CategoryNotFoundError', ['pyjokes/core.py', 'pyjokes/__init__.py', 'unit/test_errors.py'], 'none',
  'python3 -m unittest unit.test_errors', ['get_jokes("nope") raises CategoryNotFoundError', 'get_joke("nope") raises CategoryNotFoundError'], 'an unknown category raises')
const T3 = (dep: string) => task(3, 'Update the old empty list test', ['unit/test_core.py'], dep,
  'python3 -m unittest unit.test_core', ['test_unknown_category_is_empty now expects CategoryNotFoundError', 'the neutral tests still pass'], 'an unknown category raises')
const T2 = (anyCase: boolean) => task(2, 'A chuck category', ['pyjokes/jokes_en.py', 'unit/test_chuck.py'], 'none', 'python3 -m unittest unit.test_chuck',
  [anyCase ? 'get_jokes("Chuck") returns two jokes or more (the category in any case)' : 'get_jokes("chuck") returns two jokes or more', 'every chuck joke is a non empty string'], 'chuck jokes exist')
const group = (id: string, title: string, dep: string, validate: string, body: string) =>
  `## Group ${id}: ${title}\n**Depends:** ${dep}\n**Validate:** \`${validate}\`\n**Context:**\nPlain python, standard library only. Keep every public name of pyjokes.core in pyjokes.__all__.\n\n${body}\n`
const G1_VALIDATE = 'python3 -m unittest unit.test_core unit.test_errors unit.test_api'
// pass 1 of the first scenario: G1 changes the behavior unit/test_core.py checks, and its Validate runs that file, but the
// update is in G2
const TASKS_BAD = `# Tasks: pyjokes\n\n**Integration:** \`${SUITE}\`\n\n` +
  group('G1', 'Errors', 'none', G1_VALIDATE, T1) + group('G2', 'Chuck', 'G1', 'python3 -m unittest unit.test_chuck', T2(false) + '\n' + T3('none'))
// the update moves into G1, after Task 1
const tasksGood = (anyCase = false) => `# Tasks: pyjokes\n\n**Integration:** \`${SUITE}\`\n\n` +
  group('G1', 'Errors', 'none', G1_VALIDATE, T1 + '\n' + T3('Task 1')) + group('G2', 'Chuck', 'G1', 'python3 -m unittest unit.test_chuck', T2(anyCase))

type Code = { test: [string, string]; green: [string, string][] }
// exportsNew: the task agent of Task 1 exports the new name; without it, its own test passes and G1's Validate (test_api) does not
const code = (exportsNew: boolean, anyCase: boolean): Record<number, Code> => ({
  1: {
    test: ['unit/test_errors.py', 'import unittest\n\nfrom pyjokes.core import CategoryNotFoundError, get_joke, get_jokes\n\n\nclass ErrorsTest(unittest.TestCase):\n    def test_get_jokes_raises(self):\n        with self.assertRaises(CategoryNotFoundError):\n            get_jokes("nope")\n\n    def test_get_joke_raises(self):\n        with self.assertRaises(CategoryNotFoundError):\n            get_joke("nope")\n'],
    green: exportsNew ? [['pyjokes/__init__.py', EXPORTS], ['pyjokes/core.py', CORE]] : [['pyjokes/core.py', CORE]],
  },
  3: {
    test: ['unit/test_core.py', 'import unittest\n\nfrom pyjokes import get_joke, get_jokes\nfrom pyjokes.core import CategoryNotFoundError\n\n\nclass CoreTest(unittest.TestCase):\n    def test_neutral_has_jokes(self):\n        self.assertTrue(get_jokes("neutral"))\n\n    def test_a_joke_is_text(self):\n        self.assertIsInstance(get_joke(), str)\n\n    def test_unknown_category_is_empty(self):\n        with self.assertRaises(CategoryNotFoundError):\n            get_jokes("nope")\n'],
    green: [],
  },
  2: {
    test: ['unit/test_chuck.py', `import unittest\n\nfrom pyjokes import get_jokes\n\n\nclass ChuckTest(unittest.TestCase):\n    def test_chuck_has_two_jokes(self):\n        self.assertGreaterEqual(len(get_jokes("${anyCase ? 'Chuck' : 'chuck'}")), 2)\n\n    def test_every_chuck_joke_is_text(self):\n        self.assertTrue(all(isinstance(j, str) and j for j in get_jokes("chuck")))\n`],
    green: [['pyjokes/jokes_en.py', 'JOKES = {\n    "neutral": [\n        "There are 10 kinds of people: those who know binary and those who do not.",\n        "A SQL query walks into a bar, walks up to two tables and asks: may I join you?",\n    ],\n    "chuck": [\n        "Chuck Norris writes code that optimizes itself.",\n        "Chuck Norris can divide by zero.",\n    ],\n}\n']],
  },
})

// ---- what every run shares ----
const FINISH = /each file the run changed|^Copy what|^When .* records deviations/

function startPyjokes(w: World): void {
  for (const [rel, text] of Object.entries(BASE)) {
    fs.mkdirSync(path.dirname(path.join(w.dir, rel)), { recursive: true })
    fs.writeFileSync(path.join(w.dir, rel), text)
  }
  w.sh('git add -A && git commit -qm base')
  w.sh(`mkdir -p .claude && cp ${ROOT}/templates/temper.config.default .claude/temper.config`)
  const cfg = path.join(w.dir, '.claude/temper.config')
  fs.writeFileSync(cfg, fs.readFileSync(cfg, 'utf8').replace('  coverage-threshold: 80', `  coverage-threshold: 80\n  mutation-threshold: 0\n  commands:\n    test: ${SUITE}\n    coverage: ${SUITE} && echo 'TOTAL 100 10 90%'`))
  fs.appendFileSync(cfg, '\nplan:\n  fresh-review: auto\n')
  w.sh('git add -A && git commit -qm config')
  w.sh(`${TEMPER} init`)
  w.sh(`${TEMPER} state init pyjokes --feature 'Unknown categories raise CategoryNotFoundError, and a chuck category of jokes'`)
}

// What the scripted agents and person saw, by kind.
class Seen {
  all: Record<string, string[]> = {}
  note(k: string, v: string): void { (this.all[k] ??= []).push(v) }
  of(k: string): string[] { return this.all[k] ?? [] }
}

// A task agent: RED, then GREEN, in its worktree. Task 3 is a test update: its RED is the old test against Task 1's
// new behavior, then the test is updated. `before` runs after RED and may stop the task (returns true).
const builder = (seen: Seen, c: Record<number, Code>, before?: (w: World, n: number, wt: string) => boolean) =>
  chained((w: World, n: number, a: Json): void => {
    seen.note('build-prompt', `Task ${n}: ${a.prompt}`)
    seen.note('build-model', `Task ${n}: ${a.model}`)
    const wt = path.relative(w.dir, worktreeOf(t(w, `task show ${n}`).out))
    const k = c[n]!
    if (n !== 3) w.write(path.join(wt, k.test[0]), k.test[1])
    const red = t(w, `task test ${n} --phase red`)
    if (red.code === 0) throw new Error(`Task ${n} RED passed: ${red.out}`)
    if (n === 3) w.write(path.join(wt, k.test[0]), k.test[1])
    if (before?.(w, n, wt)) return
    for (const [f, text] of k.green) w.write(path.join(wt, f), text)
    const green = t(w, `task test ${n} --phase green`)
    if (green.code !== 0) throw new Error(`Task ${n} GREEN failed: ${green.out}`)
  })

// A fresh reviewer: one completion row per lens it was given, a paraphrase for comprehension, and the findings `find`
// returns for each lens.
const reviewer = (seen: Seen, find: (lens: string, inst: string, prompt: string) => string[]) => (w: World, a: Json): void => {
  seen.note('review-prompt', a.prompt)
  const inst = /Instance:\s*(\w)/.exec(a.prompt)?.[1] ?? 'A'
  const lenses = (/Lenses:\s*([^.]+)\./.exec(a.prompt)?.[1] ?? '').split(',').map((x: string) => x.trim())
  const art = `--artifact ${SPEC}/tasks.md`
  const ntasks = (w.read(`${SPEC}/tasks.md`).match(/^### Task \d+/gm) ?? []).length
  const earlier = Number(/Earlier findings \((\d+)\)/.exec(a.prompt)?.[1] ?? 0)
  for (const lens of lenses) {
    for (const f of find(lens, inst, String(a.prompt))) t(w, `evidence add --stage plan --phase fresh ${f} ${art}`)
    const v = lens === 'readiness' ? ` --value ${ntasks}` : lens === 'recheck' ? ` --value ${earlier}` : ''
    t(w, `evidence add --stage plan --phase fresh --exit 0 --label PROVEN --claim 'fresh review completed: ${lens} ${inst}'${v} ${art}`)
    if (lens === 'comprehension')
      t(w, `evidence add --stage plan --phase fresh --claim 'paraphrase: an unknown category raises an error and chuck jokes are added | pyjokes keeps its jokes in a dictionary by category' ${art}`)
  }
}
const TESTS_FINDING = "--severity medium --claim '[tests] Task 3: name the exception in the updated test so a reader finds it'"

// The Plan agent: the scenarios into intent.md, plan.md, the tasks `tasks(pass)` gives, the complexity.
const planner = (seen: Seen, tasks: (pass: number) => string, after: (w: World) => void) => {
  let passes = 0
  const agent = (w: World, a: Json): void => {
    passes++
    seen.note('plan-prompt', a.prompt)
    const intent = w.read(`${SPEC}/intent.md`)
    if (!intent.includes('Scenario: an unknown category raises')) w.write(`${SPEC}/intent.md`, intent.replace('## Scenarios (BDD)\n\n', SCENARIOS))
    w.write(`${SPEC}/plan.md`, PLAN)
    w.write(`${SPEC}/tasks.md`, tasks(passes))
    after(w)
  }
  return { agent, passes: () => passes }
}

const intentAgent = (seen: Seen) => (w: World, a: Json): void => {
  seen.note('intent-prompt', a.prompt)
  if (!w.exists(`${SPEC}/intent.md`)) w.write(`${SPEC}/intent.md`, INTENT)
}
const acceptance = (w: World): void => { t(w, "acceptance skip --reason 'the e2e driver writes no acceptance tests'") }
const reviewDone = (w: World): void => { t(w, `evidence add --stage review --claim 'review completed' --exit 0 --cmd 'review panel'`) }
const groupFix = (w: World, a: Json): boolean => {
  // the fix agent reads the FAIL lines, runs the Validate command, and exports the new name
  const m = /Work only in its worktree (\S+) \(/.exec(String(a.prompt))
  if (!m) return false
  const wt = path.isAbsolute(m[1]!) ? path.relative(w.dir, m[1]!) : m[1]!
  w.write(path.join(wt, 'pyjokes/__init__.py'), EXPORTS)
  return true
}

// ---- pyjokes: the faults of the failed run, in one run ----
export const pyjokesRun = (w: World): void => {
  const seen = new Seen()
  startPyjokes(w)
  const plan = planner(seen, pass => pass === 1 ? TASKS_BAD : tasksGood(), wd => { t(wd, 'state set complexity complex') })
  const agents: Script['agents'] = {
    'temper:temper-intent': intentAgent(seen),
    'temper:temper-plan': plan.agent,
    'temper:temper-plan-review': reviewer(seen, lens => lens === 'tests' ? [TESTS_FINDING] : []),
    'temper:temper-acceptance': acceptance,
    'temper:temper-build-task': builder(seen, code(false, false)),
    'temper:temper-build': (wd, a) => { seen.note('fix-prompt', a.prompt); groupFix(wd, a) },
    'temper:temper-review': reviewDone,
  }
  const person = (ask: Json, wd: World): string | { label: string; note?: string } | null => {
    const q = String(ask.question.question)
    const labels = (ask.options as Json[]).map(o => String(o.label))
    seen.note('question', `${q} [${labels.join(' | ')}]`)
    if (q.startsWith('Plan: the check failed') && q.includes('group validate order')) {
      seen.note('plan-fail', q)
      const back = labels.find(l => l.startsWith('Loop back to Intent'))
      if (back) return { label: back, note: 'G1 must update the tests its Validate runs' }
    }
    if (q.includes('failed its check')) {
      seen.note('group-fail', q)
      seen.note('output-G1', wd.run(`${TEMPER} output G1`).out)
    }
    return recommended(ask, wd)
  }
  const end = orchestrate(w, { agents, person, instruction: (_w, text) => FINISH.test(text) }, 160)

  const plans = seen.of('plan-prompt')
  expect(seen.of('plan-fail').some(q => q.includes("G1's Validate runs unit/test_core.py, which Task 3 of G2 edits")), '1: the plan gate names the file and both groups')
  expect(seen.of('intent-prompt').some(p => p.includes('Loop back from Plan') && p.includes('G1 must update the tests its Validate runs')), '3a: the Intent agent gets the loop back and its reason')
  expect(plans.length >= 2 && plans[1]!.includes('Earlier loop back from Plan to Intent') && plans[1]!.includes('G1 must update the tests'), '3a: the next Plan agent gets the earlier loop back and its reason')
  expect(seen.of('review-prompt')[0]?.includes('Lenses: readiness, zoom-out, comprehension, tests.'), '4: the first fresh review round runs the tests lens')
  const models = seen.of('build-model')
  expect(models.length > 0 && models.every(m => /sonnet/.test(m)), `5: a complex plan builds its tasks on sonnet (${models.join('; ')})`)
  expect(seen.of('build-prompt').some(p => p.startsWith('Task 3') && p.includes('Plan review note: [tests] Task 3')), '4: the medium finding reaches the builder of Task 3 as a note')
  const gq = seen.of('group-fail')[0] ?? ''
  expect(gq.includes('What failed:') && gq.includes('Fix its merged work?'), `2: the group question shows what failed and asks to fix the merged work (${gq.slice(0, 300)})`)
  expect(seen.of('question').some(q => q.includes('failed its check') && q.includes("[Fix the group's merged work (Recommended)")), '2: the fix of the merged tree is the first, recommended option')
  expect(seen.of('fix-prompt').some(p => p.includes('Group fix: group G1')), '2: one Build fix agent works on the group')
  expect(/What failed:/.test(seen.of('output-G1')[0] ?? ''), '7c: temper output G1 prints the FAIL lines of the last Validate')
  const head = w.run('git log --oneline -1').out.trim()
  expect(end.action === 'none' || /feat\(pyjokes\)/.test(head), `the run ended with the change committed (${head}; last action ${end.action})`)
  const files = w.run('git diff --stat main...HEAD').out
  expect(/pyjokes\/core\.py/.test(files) && /unit\/test_chuck\.py/.test(files) && /pyjokes\/__init__\.py/.test(files), 'the commit holds the code, the fix and the tests')
  expect(w.run(SUITE).code === 0, 'the suite passes on the committed tree')
  const u1 = w.run(`${TEMPER} usage add --stage review --model sonnet --ms none`).code
  const u2 = w.run(`${TEMPER} usage add --stage review --model sonnet --ms 4200 --fill`).out
  expect(u1 !== 0 || /filled|recorded/.test(u2), `7d: a late time fills the row recorded without one (${u2.trim()})`)
}

// ---- pyjokes-full: risk H, a recheck, Design, a Review loop back to Build, then /temper:fix ----
export const pyjokesFull = (w: World): void => {
  const seen = new Seen()
  startPyjokes(w)
  const plan = planner(seen, pass => pass > 1
    ? tasksGood().replace('- get_joke("nope") raises CategoryNotFoundError', '- get_joke("nope") raises CategoryNotFoundError with the category name as its message')
    : tasksGood(), wd => {
    t(wd, 'state set complexity medium')
    t(wd, "risk --raise H --reason 'the public API changes: callers that relied on an empty list now get an error'")
  })
  let reviews = 0
  const agents: Script['agents'] = {
    'temper:temper-intent': intentAgent(seen),
    'temper:temper-plan': plan.agent,
    'temper:temper-plan-review': reviewer(seen, (lens, inst, prompt) => [
      ...(lens === 'readiness' && inst === 'A' ? ["--severity high --claim '[readiness] Task 1: the Case for get_joke names no message for the error'"] : []),
      ...(lens === 'tests' || (lens === 'recheck' && /\[tests\] Task 3/.test(prompt)) ? [TESTS_FINDING] : []),
    ]),
    'temper:temper-acceptance': acceptance,
    'temper:temper-build-task': builder(seen, code(true, false)),
    'temper:temper-build': (wd, a) => {
      seen.note('fix-prompt', a.prompt)
      if (groupFix(wd, a) || wd.exists('unit/test_empty.py')) return
      wd.write('unit/test_empty.py', 'import unittest\nfrom unittest import mock\n\nimport pyjokes.core\n\n\nclass EmptyTest(unittest.TestCase):\n    def test_an_empty_category_raises_the_clear_error(self):\n        with mock.patch.dict(pyjokes.core.JOKES, {"empty": []}):\n            with self.assertRaises(pyjokes.core.CategoryNotFoundError):\n                pyjokes.core.get_joke("empty")\n')
      t(wd, `evidence run --stage build --phase red --claim 'unit tests: an empty category' -- python3 -m unittest unit.test_empty`)
      wd.write('pyjokes/core.py', wd.read('pyjokes/core.py').replace('    return random.choice(get_jokes(category))\n', '    jokes = get_jokes(category)\n    if not jokes:\n        raise CategoryNotFoundError(category)\n    return random.choice(jokes)\n'))
      t(wd, `evidence run --stage build --phase green --claim 'unit tests: an empty category' -- python3 -m unittest unit.test_empty`)
    },
    'temper:temper-design': (wd, a) => {
      seen.note('design-prompt', a.prompt)
      wd.write(`${SPEC}/design.md`, '# Design: unknown categories raise\n\n## Architecture\n\nOne exception class in core.py, exported by the package.\n\n## API Contracts\n\nget_jokes(category) raises CategoryNotFoundError(category).\n\n## Areas of Concern\n\nNone flagged: the change is one module and its export.\n')
    },
    'temper:temper-review': wd => {
      reviews++
      if (reviews === 1) t(wd, `evidence add --stage review --severity critical --claim 'pyjokes/core.py:14 get_joke on an empty category raises IndexError from random.choice, not a clear error' --exit 1 --cmd 'review panel'`)
      reviewDone(wd)
    },
  }
  const person = (ask: Json, wd: World): string | { label: string; note?: string } | null => {
    seen.note('question', `${String(ask.question.question)} [${(ask.options as Json[]).map(o => String(o.label)).join(' | ')}]`)
    return recommended(ask, wd)
  }
  const end = orchestrate(w, { agents, person, instruction: (_w, text) => FINISH.test(text) }, 160)

  const qs = seen.of('question')
  const rp = seen.of('review-prompt')
  expect(rp.length >= 2 && rp.slice(0, 2).every(p => p.includes('Lenses: readiness, zoom-out, comprehension, tests.')) && rp.some(p => p.includes('Instance: B.')), 'risk H: two independent fresh reviewers (A and B), four lenses each')
  expect(qs.some(q => q.startsWith('Plan: the check failed') && q.includes('[Revise the plan (Recommended)')), 'a high fresh finding fails the plan gate and Revise the plan is recommended')
  expect(plan.passes() >= 2 && seen.of('plan-prompt')[1]!.includes('the Case for get_joke names no message'), 'the Plan agent gets the finding to answer')
  expect(rp.some(p => p.includes('Lenses: recheck.') && p.includes('Earlier findings (') && p.includes('Changed task blocks: Task 1.')), 'round 2 is a recheck of the earlier findings on the changed block')
  expect(seen.of('design-prompt').length === 1, 'Design ran once (risk H)')
  const models = seen.of('build-model')
  expect(models.length > 0 && models.every(m => /sonnet/.test(m)), `risk H builds its tasks on sonnet (${models.join('; ')})`)
  expect(seen.of('build-prompt').some(p => p.startsWith('Task 3') && p.includes('Plan review note: [tests] Task 3')), 'the medium finding reaches the builder as a note')
  expect(qs.some(q => q.startsWith('Review: the check failed')) && seen.of('fix-prompt').some(p => p.includes('Feedback re-entry') || p.includes('What the stage before the loop left open')), 'a critical Review finding loops back to the Build fix pass, with the finding in its prompt')
  expect(reviews === 2, `Review ran again after the fix pass (${reviews})`)
  expect(end.action === 'none', `the feature run ended (last action ${end.action})`)
  const files = w.run('git diff --stat main...HEAD').out
  expect(/pyjokes\/core\.py/.test(files) && /unit\/test_empty\.py/.test(files) && /unit\/test_chuck\.py/.test(files), 'the branch holds the code, the regression test of the fix pass and the tests')
  expect(w.run(SUITE).code === 0, 'the suite passes on the committed tree')

  // then a /temper:fix run on the same project
  w.sh('git checkout -q main && git merge -q --no-ff -m "merge the feature" HEAD@{1} 2>/dev/null || true')
  const before = w.run('git log --oneline -1').out.trim()
  w.write('pyjokes/core.py', w.read('pyjokes/core.py').replace('def get_jokes(category="neutral"):\n', 'def get_jokes(category="neutral"):\n    category = category.upper()\n'))
  w.sh('git add -A && git commit -qm "a bug: categories are upper cased"')
  w.run(`${TEMPER} state clear`)
  const bug = '.temper/specs/bug'
  const fixAgents: Script['agents'] = {
    'temper:temper-rca': wd => wd.write(`${bug}/rca.md`, '# RCA: every category is looked up upper cased\n\n## Root cause\n\nget_jokes upper cases the category before the lookup, and every key is lower case.\n\n## Fix\n\nLook the category up as given.\n'),
    'temper:temper-fix': wd => {
      wd.write('unit/test_case.py', 'import unittest\n\nfrom pyjokes import get_jokes\n\n\nclass CaseTest(unittest.TestCase):\n    def test_neutral_is_found_as_given(self):\n        self.assertTrue(get_jokes("neutral"))\n')
      t(wd, `evidence run --stage build --phase red --claim 'regression test: a category is found as given' -- python3 -m unittest unit.test_case`)
      wd.write('pyjokes/core.py', wd.read('pyjokes/core.py').replace('    category = category.upper()\n', ''))
      t(wd, `evidence run --stage build --phase green --claim 'regression test: a category is found as given' -- python3 -m unittest unit.test_case`)
    },
    'temper:temper-review': reviewDone,
  }
  const fixScript: Script = { agents: fixAgents, person, instruction: (wd, text) => {
    if (text.startsWith('Append one entry for this fix')) { wd.write('.temper/lessons.md', '# Lessons\n\n- a lookup key is used as given\n'); return true }
    return FINISH.test(text)
  } }
  let fixEnd: Json
  if (w.mode === 'driver') fixEnd = orchestrateFix(w, fixScript, 'every category is looked up upper cased', 'bug')
  else {
    // commands/fix.md starts the state and launches the root cause agent itself; the loop over `temper next` starts after it
    w.sh(`${TEMPER} state init bug --command fix`)
    fixAgents['temper:temper-rca']!(w, {})
    fixEnd = orchestrate(w, fixScript, 120)
  }
  expect(fixEnd.action === 'none' && w.run('git log --oneline -1').out.trim() !== before, `the fix run ended with a commit (${w.run('git log --oneline -3').out.trim().replace(/\n/g, ' / ')})`)
  expect(w.run(SUITE).code === 0, 'the suite passes after the fix')
}

// ---- pyjokes-blocked: a task that needs another task's file parks at once ----
export const pyjokesBlocked = (w: World): void => {
  const seen = new Seen()
  startPyjokes(w)
  // pass 1 leaves core.py out of Task 2; after the loop back, Plan declares it
  const plan = planner(seen, pass => pass === 1 ? tasksGood(true)
    : tasksGood(true).replace('**File:** `pyjokes/jokes_en.py`, `unit/test_chuck.py`', '**File:** `pyjokes/jokes_en.py`, `pyjokes/core.py`, `unit/test_chuck.py`'),
  wd => { t(wd, 'state set complexity complex') })
  const lower = (w2: World, n: number, wt: string): boolean => {
    if (n !== 2) return false
    if (!/pyjokes\/core\.py/.test(t(w2, 'task show 2').out.split('TASK')[1] ?? '')) {
      seen.note('blocked', t(w2, "task blocked 2 --needs pyjokes/core.py --reason 'the chuck case is looked up in any case, and the lookup is in core.py'").out)
      return true
    }
    w2.write(path.join(wt, 'pyjokes/core.py'), fs.readFileSync(path.join(w2.dir, wt, 'pyjokes/core.py'), 'utf8').replace('def get_jokes(category="neutral"):\n', 'def get_jokes(category="neutral"):\n    category = category.lower()\n'))
    return false
  }
  const agents: Script['agents'] = {
    'temper:temper-intent': intentAgent(seen),
    'temper:temper-plan': plan.agent,
    'temper:temper-plan-review': reviewer(seen, lens => lens === 'tests' ? [TESTS_FINDING] : []),
    'temper:temper-acceptance': acceptance,
    'temper:temper-build-task': builder(seen, code(true, true), lower),
    'temper:temper-build': (wd, a) => { seen.note('fix-prompt', a.prompt); groupFix(wd, a) },
    'temper:temper-review': reviewDone,
  }
  const person = (ask: Json, wd: World): string | { label: string; note?: string } | null => {
    seen.note('question', `${String(ask.question.question)} [${(ask.options as Json[]).map(o => String(o.label)).join(' | ')}]`)
    return recommended(ask, wd)
  }
  const end = orchestrate(w, { agents, person, instruction: (_w, text) => FINISH.test(text) }, 160)

  const t2 = seen.of('build-prompt').filter(p => /Task 2/.test(p.split(':')[0]!))
  expect(/OK: Task 2 is blocked: its test needs pyjokes\/core\.py \(declared by Task 1\)/.test(seen.of('blocked')[0] ?? ''), `the CLI records the block and names Task 1 (${seen.of('blocked')[0]})`)
  expect(t2.length === 2, `Task 2 ran once before the loop back and once after it, no retry and no escalation (${t2.length} runs)`)
  expect(seen.of('question').some(q => q.includes('Task 2 needs pyjokes/core.py, which Task 1 declares') && q.includes('[Loop back to Plan (Recommended)')), 'the parked question names the file and its task, and recommends the loop back to Plan')
  expect(plan.passes() === 2, `Plan ran again after the loop back (${plan.passes()})`)
  expect(end.action === 'none', `the run ended (last action ${end.action})`)
  expect(w.run(SUITE).code === 0, 'the suite passes on the committed tree')
}
