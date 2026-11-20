---
description: "Transform a feature request into a structured implementation plan with impact analysis"
argument-hint: "<feature-name-or-JIRA-123>"
---

# Plan: Feature Planning with Impact Analysis

**Goal:** Turn a feature request into the scenarios of `intent.md`, `tasks.md` and, above the simple tier, a short
`plan.md`, grounded in a real blast radius, not an estimated one. Write only what a script, a gate row or a later agent
reads. This doc states the outcome and the handful of rules a strong model would not derive on its own; it does not
choreograph your steps.

## Usage

Plan runs as a stage of `/temper`, in a clean subprocess from the plan brief
(`${CLAUDE_PLUGIN_ROOT}/agents/plan.md`), also when `/temper:plan` starts the run (it is a door
into `/temper`). It returns a summary and never shows an `AskUserQuestion` gate: the
orchestrator owns the gate.

## What You Produce

**Hard rule: write only these files under `.temper/specs/{feature-slug}/`, never another (no `spec.md`,
`quickstart.md`, `evals/evalset.json`, README).**

- **`intent.md`**: Intent wrote it; you add the Gherkin **Scenarios** (below).
- **`tasks.md`**: the groups and their tasks, each declaring its files, its test command and its Cases.
- **`plan.md`**, above the simple tier only: `## Context Map` and `## Blast Radius`, nothing else.

**Count production files only.** The tier counts the files that hold the product's code: test
files, docs (README, CHANGELOG, guides) and a one-line export or registration edit follow from the
code and add no design question, so they do not count.

**Trivial** (one file, no product problem): no artifacts — say so and implement directly (in
`/temper` the Intent stage decides this). **Simple** (up to 3 production files, with new functions,
options or fields in existing modules only): `tasks.md` and the scenarios, no `plan.md`. The CLI bounds it: a run
recorded as `simple` fails the plan gate's `tier recorded` row when `tasks.md` has more than one group, declares more
than 3 production files, or the run's risk is H, and the row names `temper state set complexity medium`.
**Medium** (4-10 production files, or a new module, data model or external interface) / **Complex**
(10+): `plan.md` as well. The risk multipliers below still push a tier up. No tier runs Design: it runs
only when the person asks for it at the approval (`Run Design first`). A policy conflict or a product call becomes
one line under intent.md's `### Open Questions`, `- Blocking: {question} choices: {the answer the plan assumes} |
{another}`, and the tasks are written under the first choice (a `(house rule)` choice goes first).

**intent.md usually already exists when you start.** In the orchestrated `/temper` flow, the Intent stage wrote it and a
human accepted it at the intent gate (`Status: accepted`) before you launched. It is your input: derive Scenarios from
it, refine its wording only with a stated reason, never re-derive the Problem from scratch. **Re-read every
`- consulted:` source its `### Context Sources` records** — the intent summarizes them, but you plan against them; treat
every `- unavailable:` line as an explicit gap (a `- gap:` line of the Context Map, and add an Open Question back into
`intent.md` if it hides a decision). Do not re-derive context Intent already gathered. A `Status: draft` intent
(captured via `/temper:intent` or a control-band breach) is the same input, plus: resolve or explicitly re-carry each
Open Question (you ask nobody: a question that must be settled is marked `Blocking`, and the orchestrator asks it before
the gate question); the intent is accepted (`temper intent accept`) when the person leaves Intent. **Risk multipliers**
(each pushes complexity up one tier): touches auth/payment/security code; changes what the consumers of a library with
5+ consumers already use (a signature, a behaviour, a default; adding a new function or option they never call does not
count); changes a DB schema; a module with a historically high defect rate (`.temper/metrics.json` if present); a
CRITICAL/HIGH security hot path (below).

## What `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate plan` Checks

Quoted from the plan gate in the temper CLI (`${CLAUDE_PLUGIN_ROOT}/scripts/temper`) so this doc cannot drift from the gate.
## Context Map and the Context check

`plan.md` opens with `## Context Map`: what Plan left out on purpose (`ignore`) and what it could not find (`gap`), one
line per source and never per code file. A `use` line is allowed and counted, never asked for. The plan gate row
`context map reviewed` passes a plan.md with no map, or a map with no entry (nothing is flagged); a map holds at most 12
entries, each line at most 100 characters, and a `- reviewed: human|auto` line. Plan writes `- reviewed: pending`; the
CLI replaces it. `plan.context-check` is `auto` (ask only when the map has an `ignore` or a `gap`), `always` (ask every
run) or `off` (never ask; the map is still written and gated). 9.8.5: a map nobody is asked about passes with
`- reviewed: pending`; under `auto` a flagged map whose lines the approval shows whole (three `ignore`, two `gap`, each
at most 90 characters) is answered there: the approving option writes
`As planned (at the approval, N flagged lines shown)`. 9.8.0: the question names what the plan leaves out and could not
find (the `ignore` and `gap` lines, so write each as the decision it is: "refunds in the CSV export are out of scope");
any answer but "As planned" sends Plan back with the person's words as a note
(`temper plan review --answer '...' --redo`). The question is the CLI's own (`temper next` and `view.json` carry
`context_map` and `context_check`); the person's choice runs `temper plan review --answer '<choice>'`, then
`temper gate plan`. Plan never asks it and never writes `reviewed: human`. Auto mode may refuse an edit of that line,
which is why the CLI writes it ([auto mode](../docs/auto-mode.md)).

Every scenario carries a `Test:` line, a scoped shell command that proves it on the merged tree and names the test the plan's
task writes; the gate row `scenario test commands` fails for one without it, and for a `Test:` file no task declares and the
project lacks. A task owes the scenarios whose `Test:` command runs a file it declares (`temper task show` lists them
with their exact commands); a scenario no task owes is run at integration. Build runs each `Test:` command and records
a row: that row is what lets a `Validate: scenario` criterion pass.

The rows: the artifacts exist (`intent.md` + `tasks.md`); every criterion has explicit validation links
(`acceptance.py plan`: stable `AC-NN` ids, `Why:` and `Validate:` on each, every `Covers:` id names a real criterion,
and a `scenario` criterion is covered by a scenario); every `Scenario:` sits inside a ```gherkin fence. No tier needs a
`plan.md`. Record `${CLAUDE_PLUGIN_ROOT}/scripts/temper state set complexity <tier>` as soon as you classify it. The
call also writes the tier into the `**Complexity:**` line of `intent.md` (and of `plan.md`, when it has one), where a
later door reads it; the gate's `tier recorded` row fails when such a line names another tier than the run, or when
a simple run crosses the bound above.

Fix any FAIL before returning. The three fresh review rows below are the one exception: they fail until the reviewer
has run, which happens after you return. Leave them.

## The fresh review (9.7.6)

A reviewer with no context reads the plan before the person approves it (`agents/plan-review.md`). It checks three things
through three lenses: that each task can be built from its own block with no guess (readiness), that nothing unneeded or
already in the code is planned (zoom-out), and that a newcomer can say in their own words what the plan does
(comprehension). A plan of risk `H` gets two independent reviewers (A and B; `plan.fresh-review-twice: false` turns that off).

When it runs is `plan.fresh-review`:

- `ask` (the default): the plan question offers **Fresh review first**, at every tier. The review applies once the person
  chooses it (`temper plan fresh request`).
- `auto`: the CLI runs it by itself for `medium` and `complex` plans.
- `always`: every plan. `off`: never.

How the CLI counts it:

- The orchestrator marks each launch (`temper plan fresh start`, after Plan returned): the digest of intent.md, plan.md and
  tasks.md, and how many rows the plan ledger held. Only rows appended after the mark count, so a row the Plan agent wrote
  itself never does.
  An edit of any of the three files after the launch makes the review stale, and it runs again on the new text.
- `plan.fresh-review-rounds` (default 3) caps the launches of one run. At the cap the plan question offers no more
  revisions: the person accepts a finding, skips the check or steps back.
- Three plan gate rows: `fresh review ran` (a completion row for each lens and reviewer; the readiness row must name as
  many tasks as tasks.md has), `fresh reader's paraphrase` (two parts of 6 words or more) and `no open plan blockers`
  (no `high` or `critical` finding open). A lens with no completion row is `not run`, never a lens with no findings.
- The plan gate row `request routes kept` (9.8.0): every `METHOD /path` the request names (the run's feature text) is in
  plan.md or tasks.md, method and shape unchanged (a parameter may be renamed). A route the intent's Decisions name, or
  a plan route of the same method they name, is the person's change and passes. A request that names no route passes.

## Answering the fresh review

A finding below high passes the plan gate: the plan question names the open findings and offers Revise the plan, never
recommended (9.8.4); an open `medium` or `low` finding that names a task reaches that task's builder as a note. The
first round of the fresh review runs four lenses (`tests` among them: which existing tests the change breaks, and which
task updates them); each later round is a recheck that reads only the changed task blocks and checks only whether each
earlier finding is fixed, so the rounds converge instead of reading the whole plan again.


When the person chooses **Revise the plan**, you run again with a `Fresh review findings to answer`
line. Answer each finding in one of four ways, and say which in the lines you return (`#{id}: fixed`, `contested`,
`escalated` or `left`):

- **Fix it** in tasks.md or plan.md (the usual answer). The changed tasks.md makes the review run
  again on the new text.
- **Contest it** only with evidence the reviewer could have read:
  `${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence contest --stage plan --id N --cite <file>[:<line>|:<symbol>] --quote '<the text there>' --reason '...'`.
  The CLI checks that the file is in the project and holds the line or symbol. "This was intentional"
  is not evidence.
- **Escalate it** when the evidence is outside every file (a team rule, a decision someone said):
  `${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence escalate --stage plan --id N --reason '...'`. Do not
  add text to the plan only so a reader with no context is satisfied.
- **Leave a `low` one** as it is, and say so.

A comprehension finding is never contested or escalated (the CLI refuses it): if a newcomer could not follow the plan,
the plan is missing context. Never change a severity. A contested or escalated finding stays open: the person accepts it
at the plan question, or sends it back. You wrote this plan; wanting to contest a finding is not
evidence that the reviewer is wrong.

## Explore: Your Own Tools, By Default

Explore the repo with your own tools, in your own context — stack, structure, patterns,
similar code, test coverage. A nested Explore subagent is an escape hatch for a repo
large enough that reading it directly would blow your context, not a mandatory first
step; that judgment call is yours, not a fixed procedure. Read `.claude/temper.config`
and enabled packs' `rules.md` (project shadows global shadows the built-in files listed in `${CLAUDE_PLUGIN_ROOT}/reference/pack.md`;
keep rules whose `phases` is `all` or contains `plan`, and also those that contain `build`: the
groups' Context distils them, below) before you plan.

## Blast Radius: Measured, Not Estimated

The Blast Radius section of `plan.md` holds only what the change reaches outside the files tasks.md declares, and each
row comes from something you opened or grepped (an importer list you read, a call site you found), never a guess.
When a cross-repo code search tool is connected (a Sourcegraph MCP, for example), use it for callers outside this
repo: such a row carries a `[CROSS-REPO]` label and names the repo (`temper risk` reads the label). If a
`code-review-graph` MCP server is available, prefer `get_impact_radius_tool` (label
findings `[PROVEN]`); otherwise grep for importers/consumers and label `[HEURISTIC]`.
For each changed file: who imports it, does the importer have test coverage for the
affected path, does it change a contract (API shape, event payload, DB schema), does it
bypass an established pattern. One line per consumer: `- {file}: {what it uses} ({covered by tests | not covered})`.

**Security hot paths** — classify each blast-radius file by sensitivity and trace it to
its entry point:

| Level | Signal | Example |
|---|---|---|
| CRITICAL | auth, crypto, payment, secret, token | AuthService, PaymentService |
| HIGH | session, permission, role, rate-limit, validate | SessionManager, RateLimiter |
| MEDIUM | logging, error-handling, route, middleware | ErrorHandler, ApiMiddleware |
| LOW | config, constants, types, helpers | AppConfig, Types |

For CRITICAL/HIGH files, find every importer and classify it as an entry point (HTTP
handler, CLI command, worker, WebSocket handler, event subscriber), then the exposure
reachable from it (PUBLIC / AUTHENTICATED / ADMIN / INTERNAL, from unauthenticated →
admin-only → unreachable). A CRITICAL file reachable from a PUBLIC endpoint is a CRITICAL
finding; add a scenario for it in the next step. Each CRITICAL finding pushes complexity
up a tier; each HIGH finding is a candidate for its own scenario.

## BDD: Derive Scenarios From the Blast Radius, Before Architecture

Scenarios define required behavior; architecture should follow from them, not the other
way: this keeps the file list from over-engineering (no file exists without a scenario or an infrastructure reason).

- Every blast-radius **risk area** → at least one scenario.
- Every **acceptance criterion** → at least one scenario.
- Every **affected consumer** → a regression-guard scenario ("existing X still works").
- Every scenario is concrete (specific inputs/outputs) and testable — never "system works
  correctly".

Medium: 3-8 scenarios. Complex: 5-15. **Every scenario is one fenced ```gherkin block of four lines**, never a bare
`Scenario:` line (markdown renders it as one run-on paragraph): the `Scenario:` line, one `Then` line (the result its
test checks; Review judges the test against it), `Covers:` (the AC ids it verifies; a regression-only scenario may
omit it) and `Test:`. Nothing else: the CLI reads only the name, `Covers:` and `Test:`. Example:

    ```gherkin
    Scenario: a locked account gets 423
      Then the response is 423 and carries the unlock time
      Covers: AC-02
      Test: npm test -- test/auth/lockout.test.ts -t "423"
    ```

After deriving scenarios, reconcile against your
preliminary file list: add files scenarios now require, and drop or justify-as-
infrastructure any file no scenario touches.

**Success-criteria validation types** — prefer the first two, mechanically checkable:

| Type | Example |
|---|---|
| `scenario` | `Validate: scenario — covered by "User resets password"` |
| `code` | ``Validate: code — `grep -q "POST /api/reset" src/routes.ts` `` |
| `metric` | ``Validate: metric — `test "$(wc -c < dist/app.js)" -lt 200000` `` |
| `manual` | `Validate: manual — UX review needed` |

A `code` or `metric` criterion carries its command in backticks: a command that exits 0 when the criterion holds. The
CLI runs it when Build ends and at Check and records the row itself (9.8.5); no agent records it. One with no command
fails the intent gate's `criteria validate` row. A metric that can only be read after release is `manual`.

You run headless and ask nobody. Where an uncertainty changes the outcome, write it into
`intent.md`'s Open Questions as `Blocking`, with concrete choices ("integrate with the existing
PaymentService, or create a new one?", never "what should the architecture be?"); the
orchestrator asks it before the gate question. Skip it entirely when the requirements are clear.

## File-to-Scenario Traceability

Every planned file justifies its existence: a file a scenario's test needs, or an infrastructure file another file
needs (`db/migrations/001_x.sql`, required by the service). A file that is neither: question whether it is needed: if
it is, a scenario is missing; add one. A scenario is owed by the task that declares the file its `Test:` command runs,
so declare each test file in the task that writes it.

Order tasks by layer (infra → core → integration → tests). Tasks with disjoint files and
no `**Depends:**` between them run in parallel; give a task `**Depends:**` on another when it
needs that task's output or config change (see "Grouped tasks" below).

## Grouped tasks

Build runs in groups, so write `tasks.md` as groups of tasks; the example to copy is in
`${CLAUDE_PLUGIN_ROOT}/templates/tasks.md` (between the `grouped-example` markers). The format below is what the CLI parser
(`_grouped_parse`) reads and the plan gate (`_grouped_plan_reqs`) checks.

**Format.**
- A top-level `**Integration:**` line with the full-suite command in backticks. Required.
- `## Group G<n>: title`, then `**Depends:**` (`none` or `G1, G2`), `**Validate:**` (a backticked
  group-level test command), `**Interfaces:**` (optional; each entry is `` `path` — `literal` ``, a path and
  a string that must appear in it after integration) and `**Context:**` (a block that runs until the
  first `### Task`). Every group needs a Context.
- `### Task N: description`, with `**File:**`, `**Depends:**` (`none` or `Task 1, Task 2`),
  `**Test:**`, `**Cases:**` and a closing `- [ ] done` box. The parser takes a task's group from the `## Group` heading
  it sits under (a `[group: G<n>]` tag in the title is not read). Task numbers are unique across the whole file.

**Declared files.** `**File:**` lists backticked paths, one per file the task will write, including its test file.
They can stand on one line or on a `**File:**` line each; every line counts.
Give exact file paths, one per file. The plan gate refuses any glob
character (`*`, `?`, `[`) in a `**File:**` path and the commit check compares changed files to the
declared union by exact path, so name every file, the test file included. Two tasks that can
run together (neither depends on the other, directly or through their groups) must declare disjoint files;
the gate rejects an overlap. Order the tasks with `**Depends:**` when they must touch the same file.

**Test per task.** Every task declares its own scoped `**Test:**` command: its own test file or a filter
for it, never the whole suite. The CLI runs it and judges the task on it alone. The whole suite runs only
at the group's `**Validate:**` and at `**Integration:**`. The test file a task creates must be in that
task's `**File:**`: the plan gate fails a task whose `**Test:**` command names a path (its first path
argument) that is neither declared by the task nor already in the project, because the task's commit check
would otherwise reject the new test file as an undeclared change.

**Each Validate runs once on the base.** A group's Validate and the Integration line must pass on the current code.
The plan gate runs no command: after the planner returns, the CLI runs each once (`temper baseline plan`) in the
baseline's worktree, with the project's `setup:` block, under the limit Build gives it, in a process of its own. Left
out: a command whose text is the suite the baseline ran, a command that names a file a task creates, and every task
and scenario Test and every criterion command (they fail on the base by design; their programs are still looked up). The exit code alone decides: 0 passes; a time out is no fault of
the environment and offers more time; exit 125 (the setup line) and a program the shell does not find are the
environment's; any other exit fails, unless the base itself is red. A failed or timed out command is the person's
question `plan.command`: more time, another command, a revised plan, or a skip with a reason.

**A group passes its own Validate.** A group's worktree holds its own work and the work of the groups it
depends on, nothing else. So the task that updates an existing test file a group's `**Validate:**` runs
(named in the command as a path or a dotted Python module, inside a folder it names, or named by a script it runs) belongs to that group or to
one it depends on. The plan gate's `group validate order` row fails when a task of another group edits
such a file, and names the file and both groups: move the task, or take the file out of that Validate.
When a change breaks existing tests, the task that changes the code and the task that updates those tests
go in the same group.

**Cases: write the test cases, not just the test file.** Under `**Cases:**`, one bullet per case the
task's test must check, each a concrete input and its exact expected result (a value, an output line, an
error message or exit code), never a vague "works correctly". List the normal result first, then the edge
cases (empty, boundary, a value just over a limit) and the error cases the intent and scenarios name. The
plan gate fails a task with fewer than 2 cases. The task agent, often a small model, writes one test per
case and is judged on them, so the cases you write here are the quality of its tests: a case you leave out
is a gap Review finds later.

**Context: distil the pack rules.** A task agent reads only its task and its group's Context, never the
packs. Distil the rules of the enabled packs that apply to that group into its Context, in your own words
and short: the quality, tdd and performance rules for the kind of code the group writes, and the
security rules always, even for a group that looks harmless. Add the conventions to follow and the
interfaces the group must keep. Review still checks the full packs, so the Context is a working summary,
not a substitute.

**Budgets (the gate fails a plan over them).** A group's Context is at most 4096 bytes. A task block (its
heading through its last field, the cases included) is at most 2048 bytes: no long background in tasks.md.

**Few groups, parallel tasks.** A group costs a worktree, a merge commit and a human gate; a dependency
between two tasks of the same group costs nothing extra. Make a new group only for a separate review unit
(another area of the code, or work a human should approve before the next part starts), not for every
step: a small feature is usually one group. Inside a group, give independent tasks disjoint files and no
`**Depends:**`, so they run at the same time; where one task needs another's code, give it
`**Depends:** Task N` in the same group rather than a second group. Say in the Context which code from
earlier tasks the tests call for real: task agents test the real code and mock only what a test cannot
run (network, clock, randomness, an error that cannot be triggered).

**Splitting a group.** The gate counts the distinct files a group declares and fails a group over
`autonomy.max-blast-radius` (default 15). Split it into two groups, with `**Depends:**` between them when
the second needs the first's files.

**Interfaces and Integration.** Name in `**Interfaces:**` each seam another group relies on, so
`temper integrate` can confirm it after the merge. `**Integration:**` is the command that runs after every
group branch is merged.

## Evidence + State (batch these into one Bash call)

```
${CLAUDE_PLUGIN_ROOT}/scripts/temper state set complexity <trivial|simple|medium|complex>
${CLAUDE_PLUGIN_ROOT}/scripts/temper gate plan
```

The CLI runs `temper risk` itself after the planner (and the revise agent) returned, before the plan gate (9.8.5).
`temper risk` computes the rating from the blast radius, so the same blast radius always gives the same rating:
production files (declared files that are not tests or docs) up to 3 is L, up to 10 is M, more is H; a CRITICAL entry
in `.temper/security-map.json` is H; a HIGH entry, or a `[CROSS-REPO]` row in the Blast Radius section, moves it up one
tier. The approval card's risk is the letter it printed (the CLI reads it from the run state). To raise it,
`temper risk --raise L|M|H --reason '<why>'`: a raise needs a reason and never lowers the rating.

If a security-hot-path scan ran, also persist `.temper/security-map.json` (one entry per
CRITICAL/HIGH file: `file`, `function`, `sensitivity`, `entry_points[]` with `route`,
`exposure`, `has_auth_middleware`, `has_authorization_check`) for Review/Check to read.

## Summary Panel

The CLI draws the approval card (`temper card`, 9.8.5) from intent.md, plan.md, tasks.md and the run state. This
stage draws no box: it returns `PLAN DONE {spec path}`, and after a fresh review one line per finding it answered.

## Approval

The orchestrator owns the plan gate (`temper next --json` gives its question); this stage never
shows it: return the summary and stop. A change typed via "Other" is never approval: make the
edit, then ask the same gate again.

## Edge Cases

- Vague description ("improve performance") → a `Blocking` Open Question on which part, before exploring.
- No tests in the project → flag lower coverage expectations, add a Task 0 "set up test
  infrastructure", scope new tests to the new code only.
- Monorepo → a `Blocking` Open Question on which package; still check blast radius across shared libraries.
- DB migration needed → Task 1, before code depending on the new schema; +1 risk tier;
  note the rollback path.
- Feature partially exists → build on the similar code found, don't duplicate; say so.
