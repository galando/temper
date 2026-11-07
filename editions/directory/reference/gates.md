# Gate Checklists

Each stage ends at a gate. The stage agent walks its checklist below before it returns and
reports one row per item, `PASS` or `FAIL` with the reason. The orchestrator then re-reads the
files for each row it can confirm cheaply (a heading, a count, an exit code in `evidence.md`),
shows the rows to the person, and asks the gate question. The person decides; a checklist only
informs the decision.

**What this is not.** These checklists are applied by Claude, reading files. Nothing computes
them, and nothing stops a `git commit` when one fails. Treat a `PASS` as a careful reading, not
a proof. The full edition computes the same floors with its CLI and blocks the commit with a
hook.

A checklist is a floor, not the whole method: a stage that passes every row can still be wrong,
which is why the person reads the work at each gate.

## Intent

1. **Problem**: present, not a placeholder; names who is affected and one concrete example.
2. **Criteria**: at least one; each has a stable `AC-NN` id, `[required]` or `[optional]`, a
   `Why:` line and a `Validate:` line (`scenario`, `code`, `metric` or `manual`).
3. **Header**: `Status`, `Created` and `Complexity` lines have values.
4. **Firm words**: no `should`, `may`, `might` or `possibly` in a criterion or constraint unless
   it carries a `(source: ...)` marker.
5. **Open questions**: each is labeled `Blocking:` or `Deferred:`; no Blocking question is left
   unanswered when the gate is asked (the orchestrator asks them first).
6. **Rules covered**: one line each for Who, When, How much, Exempt, States, Where it shows and
   Exceptions. "Not applicable" only when the feature has no such rule at all.
7. **Context sources**: at least one `consulted:`, `unavailable:` or `none:` line.
8. **No scenarios yet**: the Scenarios section holds no `Scenario:` line.

## Plan

1. **Files**: `intent.md`, `plan.md` and `tasks.md` exist in the spec folder; no other spec
   document (no `spec.md`, no README).
2. **Tier recorded**: the `Complexity:` line of `intent.md` and of `plan.md` name the same tier,
   and `state.json` holds it.
3. **Scenarios**: at least as many as Success Criteria; each is one fenced `gherkin` block with
   `Note:`, `Covers:` (real `AC-NN` ids) and `Test:` (a scoped command naming the test a task
   writes). Every `[required]` criterion with `Validate: scenario` is covered by one.
4. **Context Map**: `## Context Map` with 1 to 12 `use:`, `ignore:` or `gap:` lines.
5. **Cross-Repo Search**: the section is present, with `used:` or `not available:` lines.
6. **Blast Radius**: present for `medium` and `complex`, each row from a file read or a grep.
7. **Tasks**: grouped as `templates/tasks.md` shows; each task has `File:` (exact paths, no
   glob, its test file included), `Depends:`, `Test:` (scoped, never the whole suite), at least
   two `Cases:` with exact expected values, `Traced to:` and a `- [ ] done` box. Two tasks that
   can run at the same time declare disjoint files.
8. **Routes kept**: every `METHOD /path` the request names appears in plan.md or tasks.md,
   unless the person changed it in the intent's Decisions.

## Design (medium and complex)

1. **Areas of Concern**: the heading is present, with concerns (each its own heading, with an
   owner) or a `None flagged: {why}` line.
2. **Open concerns named**: each concern without a `resolved:` line is listed for the person.

## Build

1. **Tasks**: every box in `tasks.md` is ticked, or the task is listed as skipped with a reason
   the person has seen.
2. **Test first**: for each task, `evidence.md` holds a `red` row (non-zero exit, a failing
   assertion, not a missing command or an import error) before a `green` row (exit 0) for the
   same test command.
3. **Scenario tests**: each scenario's `Test:` command ran after the last task, with exit 0.
4. **Drift**: every file changed outside the plan has a recorded decision of the person.
5. **Feedback**: on a loop back, every item of the review or check feedback is fixed or
   answered.

## Review

1. **Review ran**: `review.md` has a `Review completed:` line.
2. **No blocking finding**: no `open` finding at a severity in `review.block-on` (default
   `critical`). An accepted finding needs the person's reason.
3. **Every CRITICAL and HIGH finding** is listed in the panel, never only the top issues.

## Check

1. **Tests**: a `suite` row with exit 0 for the project's test command.
2. **Coverage**: a recorded value, at or above `check.coverage-threshold` (default 80). With no
   coverage tool, this row fails; nobody types a number in by hand.
3. **Scenarios**: every `Scenario:` of `intent.md` traced to a test that ran and passed.
4. **Criteria**: every `[required]` criterion has a passing row, or is `manual` and waits for
   the person's confirmation at the Check question.

## Commit

1. Every gate of the run is `PASS`, or the person overrode it with a reason.
2. Only the run's files and its spec folder are staged; never `git add -A`, `git add .` or
   `git add -f`.
3. No `--no-verify`. Temper never pushes and never merges.
