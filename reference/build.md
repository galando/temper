---
description: "Execute the plan, implementing tasks one-by-one with quality gates"
---

# Build: Execute Plan with Quality Gates

**Goal:** Implement the approved plan, task by task, with real TDD discipline.
`agents/build.md` carries the exact `temper evidence add --phase red/green` invocations
the gate needs; this doc is the methodology behind what to test and in what order.

**Modes:** Standalone (`/temper:build`) runs in the current context, own gate. Agent
subprocess (from `/temper`) starts clean — no `AskUserQuestion` gate, return the summary,
the orchestrator owns it. Load `tasks.md`, `intent.md` (if it exists), `plan.md`'s
Prerequisites/blast-radius section, active packs' `rules.md` (project `.claude/packs/`
shadows global `~/.claude/packs/` shadows built-in `$CLAUDE_PLUGIN_ROOT/packs/`, kept
where `phases` is `all` or contains `build`), and `.claude/packs/stacks/{stack}.md` if
present. Verify you're on a feature branch (auto-create `feature/{spec-slug}` if the git
pack is enabled and you're on main).

**If no plan exists** (trivial task, direct instructions): detect stack, read active pack
rules, read related existing code, skip branch verification (the user decides).

## Execute Tasks in Order

For each task in `tasks.md`:

**a. Read context** — existing files, adjacent patterns, conventions.

**b. Write the test first — priority order, first match wins:**

1. **`intent.md` exists** → scenario-driven, regardless of whether a TDD pack is
   enabled: one test per Gherkin scenario minimum, Given→setup, When→action, Then→
   assertions. If a TDD pack is *also* enabled, intent.md drives WHAT to test and the
   pack enforces HOW (RED→GREEN→REFACTOR discipline, naming conventions).
2. **TDD pack enabled, no intent.md** → RED→GREEN→REFACTOR from the pack's rules.
3. **Neither** → implement without an enforced test-first step.

**c. Implement** the minimal code to pass the test / fulfill the spec.
**d. Validate** — run the test (must go GREEN) and the task's validation command.
**e. Checkpoint** — write `.temper/build-state.json` (`last_task_completed`, per-task
status) and track deviations: a file touched that isn't in `tasks.md` → `unplanned_files`
with a one-line reason; a task skipped/failed → `skipped_tasks` with a reason; an
approach that materially differs from the plan (different library/pattern) →
`approach_changes`. Only track when `tasks.md` exists. The Traceability Check (below)
reconciles these against each task's `Traced to:` field.
**f. Simplify** — if the `code-simplifier` agent is available, run it on the files you
just touched (not the whole codebase); preserve behavior, improve clarity only.

## Scenario Coverage Gate (BDD enforcement) — blocks the build

If `intent.md` exists: for every `Scenario:`, find or write the test that exercises it
(match by name/description), and it must PASS. **Any scenario left without a passing
test means the build cannot proceed.** Report:

```
Scenario Coverage: X/Y scenarios covered
 [x] Scenario: User resets password -> PasswordResetTest.test_successful_reset
 [ ] Scenario: Rate limiting -> MISSING — writing test...
```

A scenario's `Note:` field picks the testing approach: `unit` (default), `mock`
(external dependency, verify the interaction), `integration` (write one if test infra
exists, else mock), `manual` (skip automated coverage, log "requires manual
verification" — still counts as covered in the tally, flagged with ⚠️ in the report).

Then write the results back into `intent.md`'s `## Scenario Coverage Checklist`:
`- [x] {Scenario Name} -> {TestClass.test_method}` per passing test (a `- [ ] ... NO
TEST` line should never survive the gate above — if it does, that's a gate-logic bug,
not an acceptable output). A test name should contain the scenario name; one test can't
satisfy two scenarios, but one scenario may need more than one test (happy path +
variant).

If no `intent.md`: skip this gate, proceed as before.

## Success Criteria Validation (IDD enforcement) — non-blocking

For each success criterion with `Validate: code — {pattern}`: grep for the pattern; ✅ if
found, WARN "Success criterion not met: {criterion}" if not. `Validate: scenario` is
already covered by the gate above; `Validate: metric`/`manual` defer to `/temper:review`.
This is a WARN, not a blocker — report it, don't stop the build over it.

## Traceability Check — non-blocking

If `tasks.md` has `Traced to:` fields: for each unplanned file from the deviation log
with no justification, WARN "trace to a scenario or mark as infrastructure"; for each
planned file that was never touched, WARN "is the task complete?". Report `N/M files
match plan ({D} deviations tracked)`. No `Traced to:` fields → skip (backward
compatible). This is signal, not a gate — the Scenario Coverage Gate above is the hard
one.

## Context Output

After the coverage gate passes, write `build-context.json`:

```json
{ "version": 1, "stage": "build", "timestamp": "{ISO timestamp}",
  "files_created": [], "files_modified": [],
  "test_results": { "total": {N}, "passed": {N}, "failed": {N} },
  "deviations": { "unplanned_files": [], "skipped_tasks": [], "approach_changes": [] },
  "scenarios_covered": [], "tasks_completed": {N}, "tasks_total": {N} }
```

## Feedback Re-entry

If `review-context.json` or `check-context.json` exists in the spec dir: read it, focus
fixes on the files/issues it names (for Check, read each `test_failures[]` entry's test
file + implementation file and fix the actual cause), then delete the file — it's stale
once consumed.

**Infeasible plan:** if the plan itself can't work (an API doesn't exist, the
architecture is incompatible), add "Revise plan" as a build-gate option, write
`build-context.json` with the infeasibility reason — the orchestrator routes back to
Plan. This is human-driven, no circuit breaker, max once per run.

## Post-Implementation

Standalone mode: run the full suite, show the summary box, then `AskUserQuestion` —
"Continue to Review (Recommended)" / "Save for later" (+ "Revise plan" per above when
applicable). A change typed via "Other" is never approval — make the edit, re-show this
same gate; the user must explicitly pick "Continue" to advance. Subprocess mode: skip the
gate, return the summary.

```
+-----------------------------------------------------------+
| BUILD — {Feature Name}                                    |
+-----------------------------------------------------------+
| Tasks: {N}/{N} complete   Tests: {N} added, all passing    |
| Files: {N} created, {N} modified   Coverage: {X}% (if known)|
| Deviations: none, or list (unplanned/skipped/approach)     |
+-----------------------------------------------------------+
```

**On Continue:** standalone loads only changed files (`git diff --name-only`) into
context for Review. Mark the spec header `**Status:** completed` /
`**Completed:** {date}` if `intent.md` exists. Cleanup of `build-state.json` happens
after commit, not here.

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
