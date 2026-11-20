---
description: "The TDD method of Build: what to test, in what order, and the fix pass"
---

# Build: Execute Plan with Quality Gates

**Goal:** Implement the approved plan with real TDD discipline.
The build brief (`${CLAUDE_PLUGIN_ROOT}/agents/build.md`) carries the exact `${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence run --phase red/green` invocations (the CLI runs the command; 9.8.5)
the gate needs; this doc is the methodology behind what to test and in what order.

**Modes:** the fix pass (`agents/build.md`, launched by the orchestrator) starts clean —
no `AskUserQuestion` gate, return the summary, the orchestrator owns it. Load `tasks.md`, `intent.md` (if it exists), `plan.md`'s
Prerequisites/blast-radius section, active packs' `rules.md` (project `.claude/packs/`
shadows global `~/.claude/packs/` shadows the built-in files listed in `${CLAUDE_PLUGIN_ROOT}/reference/pack.md`, kept
where `phases` is `all` or contains `build`), and the project's `.claude/packs/stacks/{stack}.md` if
present. The run is on its feature branch already: leaving Intent creates it (or switches to it), before the first commit of the run.

## Execute Tasks in Order

**Who runs this.** Build runs in groups, and the temper CLI runs the group loop (`temper next`
starts the groups, hands out the ready tasks and gates them): each chain of tasks is one task agent following `${CLAUDE_PLUGIN_ROOT}/agents/build-task.md` (9.8.0: tasks that run in order anyway, by a dependency or a shared file, go to one agent, which starts and gates each; independent tasks keep agents of their own, launched together),
which carries its own short method and reads nothing else (the CLI records its RED and GREEN runs and
makes its commits). This page is the method of the fix pass, and the background of that brief. The Build brief (`${CLAUDE_PLUGIN_ROOT}/agents/build.md`) runs it as a
fix pass when Review or Check loops back to Build: every task is already done, so it fixes what
the feedback file names, test-first, and does not re-run the tasks.

For each task in `tasks.md`:

**a. Read context** — existing files, adjacent patterns, conventions. Before writing
code for the task, use any connected cross-repo code search tool (for example a
Sourcegraph MCP) for definitions and prior art; with none connected, or
`tools.mode: heuristic-only`, proceed with local tools. Record the outcome in
`build-context.json` as `"code_search": {"tool": "{name}", "queries": N}` or
`{"available": false, "reason": "{why}"}` — the tool's absence never fails a gate,
a missing record does.

**b. Write the test first — priority order, first match wins:**

1. **`intent.md` exists** → scenario-driven, regardless of whether a TDD pack is enabled: one test per scenario minimum,
   written from its `Then` line (its assertions) and the Cases of the task that owns it. If a TDD pack is *also*
   enabled, intent.md drives WHAT to test and the pack enforces HOW (RED→GREEN→REFACTOR discipline, naming conventions).
2. **TDD pack enabled, no intent.md** → RED→GREEN→REFACTOR from the pack's rules.
3. **Neither** → implement without an enforced test-first step.

**c. Implement** the minimal code to pass the test / fulfill the spec.
**d. Validate** — run the test (must go GREEN) and the task's validation command.
**The moment a scenario's test goes GREEN, commit it on its own:** `git add {the
paths that scenario touched}`, then in a SEPARATE tool call `git commit -m
"feat({spec-slug}): {scenario} [AC-NN]"` — never `git add -A`, never `--no-verify`.
An infrastructure-only task (no scenario) makes no commit.
**e. Checkpoint:** leave `tasks.md` alone (the CLI ticks the boxes) and track deviations in the spec's
`build-context.json` (never `.temper/build-state.json`: the temper CLI owns the run state,
and a hand-written copy drops the fields the gates read): a file outside the plan is never
written before the person's `Drift decision:` line allows it (list it in the Build panel's
`DRIFT` section with why and the change, and the orchestrator asks); once allowed, log it in
`unplanned_files` with that decision and a one-line reason; a task skipped/failed →
`skipped_tasks` with a reason; an
approach that materially differs from the plan (different library/pattern) →
`approach_changes`. Only track when `tasks.md` exists. At the commit the CLI writes them to the spec's `deviations.md`
(`temper spec deviations`). **f. Simplify** — if the `code-simplifier` agent is available, run it on the files you just
touched (not the whole codebase); preserve behavior, improve clarity only.

## Scenario tests: the Build gate reads them

A scenario of `intent.md` carries a `Test:` command. A task owes the scenarios whose `Test:` command runs a file it
declares: write each test under the exact name the command gives. The task gate runs the scenarios the task owes in its
worktree (a scenario owed by several tasks runs at the task all the others precede, else at the group gate), and the
group gate runs the group's on the merged group branch. `temper integrate` then runs every `Test:` command on the merged
tree and records one CLI-run row each; a failing command records a failing row and Build's gate names the scenario, its
command and the exit. A pytest exit 4 or 5 means no test has that name: write it under the name the command gives.

## Scenario Coverage (BDD): the Check gate reads it

If `intent.md` exists: for every `Scenario:`, find or write the test that exercises it
(match by name/description), and it must PASS. **A scenario left without a passing test
fails the Check gate (row `scenarios traced to tests`).** Report:

```
Scenario Coverage: X/Y scenarios covered
 [x] Scenario: User resets password -> PasswordResetTest.test_successful_reset
 [ ] Scenario: Rate limiting -> MISSING — writing test...
```

A test name should contain the scenario name; one test cannot satisfy two scenarios, but one scenario may need more
than one test (happy path and a variant).

If no `intent.md`: skip this gate, proceed as before.

## Success Criteria Validation (IDD enforcement)

A criterion validated by `code` or `metric` carries its command in backticks, and the CLI runs it when Build ends
(`temper integrate`) and at Check, and records the row itself (9.8.5): the Build gate's `criteria validated` row passes
it only from that row. Record nothing for it. `Validate: scenario` is covered by the gate above; a `manual` criterion,
or a `code` or `metric` one with no command, is the person's to confirm at the Check question.

## Context Output

After the coverage gate passes, write `build-context.json`:

```json
{ "version": 1, "stage": "build", "timestamp": "{ISO timestamp}",
  "code_search": { "tool": "{name}", "queries": {N} },
  "files_created": [], "files_modified": [],
  "test_results": { "total": {N}, "passed": {N}, "failed": {N} },
  "deviations": { "unplanned_files": [], "skipped_tasks": [], "approach_changes": [] },
  "scenarios_covered": [], "tasks_completed": {N}, "tasks_total": {N} }
```

(`code_search` is `{"available": false, "reason": "{why}"}` when no cross-repo
search tool is connected.)

## Feedback Re-entry

If `review-context.json` or `check-context.json` exists in the spec dir: read it, focus
fixes on the files/issues it names (for Check, read each `test_failures[]` entry's test
file + implementation file and fix the actual cause), then delete that one file, the
project's `.temper/specs/{slug}/review-context.json` or
`.temper/specs/{slug}/check-context.json`. It's stale once consumed.

**Infeasible plan:** if the plan itself can't work (an API doesn't exist, the
architecture is incompatible), write the infeasibility reason in `build-context.json` and
say so in the panel. The person can choose "Loop back to Plan" at the Build question, which
the CLI writes; the budget counts it.

**Writing framework code:** apply the `source-driven-development` skill when a task
uses a framework/library API — detect the pinned version, verify the call against
current official docs rather than trained-in memory, and cite the source. It's how a
"hallucinated API" (the exact defect the orders-api fixture plants) gets caught while
writing, before Review has to flag it. Skip it for plain application logic.

## Post-Implementation

Run the full suite and return the summary panel. The gate is the orchestrator's (its Build
completion gate); a stage never shows one.

The panel format is owned by the build brief (`${CLAUDE_PLUGIN_ROOT}/agents/build.md`) — render exactly the panel it defines
(76 columns, fact rows then titled sections; `SEARCH:` row). Never carry a second, different box here: whichever
box a clean-context stage reads first is the one that renders, and two shapes means
two different reviews.

**On Continue:** Review loads only changed files —
diffed against the sha `${CLAUDE_PLUGIN_ROOT}/scripts/temper state get base_sha` prints when one is recorded (checkpoint commits
already landed, so a plain `git diff --name-only` returns nothing), plus
still-uncommitted paths. The commit steps mark the intent completed (`temper intent
complete`); the stage does not.

## Quality Gates (pattern → pack rule → level)

Apply the temper-core skill for SUGGEST/WARN/BLOCK definitions. Representative mapping —
the packs are the source of truth, this is illustrative, not exhaustive:

| Pattern | Rule | Level |
|---|---|---|
| SQL string concatenation | security: no SQL concat | BLOCK |
| Hardcoded secret/API key | security: no secrets | BLOCK |
| DB access from controller | architecture: use service layer | BLOCK |
| Public method with no test | tdd: test all public methods | WARN |
| Method > 30 lines | quality: method length | WARN |
| 4+ nesting levels | quality: max 3 nesting | WARN |
| Empty catch block | quality: no swallowed exceptions | WARN |
| Magic numbers | quality: named constants | SUGGEST |

## Error Recovery

- **Compilation error:** read the full error, identify the type, fix, retry (max 3).
- **New-test failure:** either the test or the implementation could be wrong —
  investigate before assuming either.
- **Existing-test failure:** a regression — your change broke it, fix your code.
- **Stuck:** re-read the plan, re-read similar code in the repo, break the task down
  further, or ask the user if genuinely blocked.
