# Build: TDD Against the Approved Plan

**Goal:** implement the approved `tasks.md` with real test first discipline, and leave a record
in `evidence.md` that the person can check.

Load `tasks.md`, `intent.md`, the Blast Radius and file tables of `plan.md`, the group's
Context, and the enabled packs' `rules.md` (rules whose `phases` is `all` or names `build`).
The run is on its feature branch already.

## For each task, in order

**a. Read context.** The files the task declares, adjacent patterns, the conventions. When a
cross-repo search tool is connected, use it for definitions and prior art.

**b. RED.** Write the failing test first: one test per bullet under `Cases:`, each asserting
the exact expected value the case names (never only "no error" or "not empty"). When the code
under test does not exist yet, write its signature first (a stub that raises or returns
nothing) so the test loads and its assertion fails. Run the task's `Test:` command. It must
fail on an assertion, for the reason the case names. A test that passes first proves nothing;
a test that cannot load (exit 126 or 127, a collection or import error, pytest exit 2) is not
a RED either. Append the row to `evidence.md` with the real exit code.

**c. GREEN.** Write the least code that passes. Run the same command; it must exit 0. Append
the row.

**d. REFACTOR** while green, then run the command once more.

**e. Tick the box** `- [x] done` in `tasks.md`.

Run scoped tests only (the task's command, a file, a class); the whole suite runs once at the
end of the group (`Validate:`) and once at Check. Wait for every test run in the foreground.

## Test the real code

Call what earlier tasks built. Mock only what a test cannot run for real: the network, the
clock, randomness, an error you cannot trigger. A test that mocks the code it checks proves
nothing, and Review reports it.

## A file outside the plan: the person decides first

The plan's files are those in `plan.md`'s tables and on `tasks.md`'s `File:` lines; test files
and the spec folder are always yours. Before you change any other file, stop. Finish what the
task can do without it, leave its box unticked, and list the file in the `DRIFT` section of
your return: the path, why the task needs it, and the change you would make. The orchestrator
asks the person and launches you again with one `Drift decision: {path}: {add|revert|allow-once}`
line per answer.

## Scenario tests

After the last task of the last group, run every scenario's `Test:` command from `intent.md`
and append one `scenario` row each. A failing one is a defect to fix (RED is already there;
make it GREEN). A "no tests ran" result (pytest exit 4 or 5) means the test has another name:
rename the test to the name the command gives, not the plan.

## Framework code

When a task calls a framework or library API, apply the `source-driven-development` skill:
detect the pinned version, check the call against the official docs for that version, cite the
source. A call to an API that does not exist is the cheapest defect to prevent.

## The fix pass

When Review or Check loops back, the launch prompt names `review.md` or `check.md`. Every task
is already done. Fix exactly what the feedback names: a test that fails because of the defect
(RED), then the fix (GREEN), with rows in `evidence.md`. Mark a fixed review finding `fixed`
in `review.md`. A finding you believe is wrong is not fixed and not accepted by you: mark it
`contested: {file:line} "{quoted text}"` with your reason, or say in your return that only the
person can settle it. It stays open; the person decides at the Review question.

## Quality gates

| Pattern | Rule | Level |
|---|---|---|
| SQL built by string concatenation | security: no SQL concat | BLOCK |
| A hardcoded secret or API key | security: no secrets | BLOCK |
| Database access from a controller | architecture: use the service layer | BLOCK |
| A public method with no test | tdd: test public methods | WARN |
| A method over 30 lines | quality: method length | WARN |
| 4 or more nesting levels | quality: at most 3 | WARN |
| An empty catch block | quality: no swallowed exceptions | WARN |
| Magic numbers | quality: named constants | SUGGEST |

## Error recovery

- Compile error: read the whole error, fix, retry (at most 3 times).
- A new test fails: the test or the code may be wrong; look before assuming either.
- An existing test fails: a regression; your change broke it, so fix the code.
- The plan cannot work (an API does not exist, an incompatible architecture): stop and say so
  in `BLOCKERS`; the person can loop back to Plan.

Build never commits, stages, pushes or merges. The one commit of the run comes after Check,
when the person chooses it.
