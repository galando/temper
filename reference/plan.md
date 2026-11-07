# Plan: Feature Planning with a Measured Blast Radius

**Goal:** turn an accepted intent into `intent.md` scenarios, `tasks.md` and `plan.md`,
grounded in a blast radius you measured, not one you guessed. This page states the outcome
and the rules a strong model would not derive on its own; it does not choreograph each step.

## What you produce

Exactly three files under `.temper/specs/{slug}/` (besides the run's own `state.json` and
`evidence.md`), never a fourth spec document:

- **`intent.md`**: the accepted Problem, Success Criteria and Constraints, plus the Gherkin
  **Scenarios** you derive.
- **`tasks.md`**: grouped tasks, each with its files, its scoped test command, its cases and a
  `Traced to:` field (`templates/tasks.md`).
- **`plan.md`**: Context Map, Architecture, Blast Radius (medium and complex), Cross-Repo
  Search, Approach Decisions (only real ones), Diagram, files to create and modify
  (`templates/plan.md`).

**The intent is your input.** The Intent stage wrote it and the person accepted it. Derive
scenarios and architecture from it; refine its wording only with a stated reason; never
re-derive the Problem. Re-read every `consulted:` source it records. Treat each
`unavailable:` line as a gap: name it in `plan.md`, and when it hides a decision, add a
Blocking Open Question back into `intent.md`.

## Complexity

Count production files only (not tests, not docs, not a one-line registration edit).

- **Trivial**: one file, no product problem. No artifacts.
- **Simple**: up to 3 production files, new functions, options or fields in existing modules.
  Design is skipped.
- **Medium**: 4 to 10 production files, or a new module, data model or external interface.
- **Complex**: more than 10.

**Risk multipliers**, each one tier up: auth, payment or security code; a change to what the
consumers of a library with 5 or more consumers already use; a database schema change; a
module with a high defect rate; a CRITICAL or HIGH security hot path.

**Risk letter**: up to 3 production files is L, up to 10 is M, more is H. A CRITICAL hot path
is H; a HIGH hot path or a cross-repo consumer moves it up one letter. Raise it to H with a
stated reason when the change adds or changes a stored schema, moves money, changes who may do
what, or calls an external system. Design runs for `complex`, and for `medium` at risk H.

Write the tier into the `**Complexity:**` line of `intent.md` and of `plan.md`, and the risk
letter into `plan.md`'s `**Risk:**` line. The orchestrator copies both into `state.json`.

## Context Map

`plan.md` opens with `## Context Map`: what you used (`use:`), what you left out on purpose
(`ignore:`) and what you could not find (`gap:`), one line per source and never per code file,
at most 12 lines of at most 100 characters. Write each `ignore` and `gap` as the decision it
is ("refunds in the CSV export are out of scope"): the orchestrator shows them to the person
at the Plan question.

## Explore with your own tools

Read the repository yourself: stack, structure, patterns, similar code, tests. A nested
Explore agent is an escape hatch for a repository too large to read directly. Read
`.claude/temper.config` and the enabled packs' `rules.md` (project `.claude/packs/` first,
then the plugin's `packs/` folder), keeping rules whose `phases` is
`all` or names `plan` or `build`.

## Cross-Repo Search

When a cross-repo code search tool is connected (a Sourcegraph MCP server, for example), use
it for callers outside this repository, prior art and definitions in dependencies. When none
is connected, say so. Record under `## Cross-Repo Search`, one line per query:
`- used: {tool}: {query} → {finding}` or `- not available: {reason}`. Blast radius rows found
this way carry a `[CROSS-REPO]` label and name the repository.

## Blast Radius: measured, not estimated

Every file in the Blast Radius section comes from something you opened or grepped. With a
`code-review-graph` MCP server, prefer its impact tool and label rows `[PROVEN]`; otherwise
grep for importers and label them `[HEURISTIC]`. For each changed file: who imports it, does
the importer have tests for the affected path, does it change a contract (API shape, event
payload, schema), does it bypass an established pattern.

**Security hot paths.** Classify each file:

| Level | Signal | Example |
|---|---|---|
| CRITICAL | auth, crypto, payment, secret, token | AuthService, PaymentService |
| HIGH | session, permission, role, rate limit, validate | SessionManager, RateLimiter |
| MEDIUM | logging, error handling, route, middleware | ErrorHandler, ApiMiddleware |
| LOW | config, constants, types, helpers | AppConfig, Types |

For CRITICAL and HIGH files, find each importer, classify it as an entry point (HTTP handler,
CLI command, worker, event subscriber) and its exposure (PUBLIC, AUTHENTICATED, ADMIN,
INTERNAL). A CRITICAL file reachable from a PUBLIC endpoint gets its own scenario.

## Scenarios: from the blast radius, before architecture

Scenarios say what behavior is required; the architecture follows from them, which keeps the
file list honest (no file without a scenario or an infrastructure reason).

- Every risk area gets at least one scenario.
- Every acceptance criterion gets at least one scenario.
- Every affected consumer gets a regression guard ("existing X still works").
- Every scenario is concrete (specific inputs and outputs), never "the system works".

Medium: 3 to 8 scenarios. Complex: 5 to 15. **Each scenario is one fenced `gherkin` block**
holding the `Scenario:` line, the Given/When/Then steps, and three annotations: `Note:` (the
test approach: `unit`, `mock`, `integration` or `manual`), `Covers:` (the AC ids it verifies)
and `Test:` (a scoped command that proves it and names the test a task writes). Group the
blocks under `#### Happy Path`, `#### Error Paths` and `#### Edge Cases`; leave out an empty
group.

    ```gherkin
    Scenario: Rate limited caller gets 429, not a hang
      Given the API has received 100 requests in the last minute
      When one more request arrives
      Then it is rejected with 429 within 50ms
      Note: unit
      Covers: AC-01
      Test: pytest tests/test_rate_limit.py::test_429_when_over_limit -q
    ```

**Validation types**, mechanical first: `scenario`, `code` (a grep for a pattern), `metric`
(measured after release), `manual` (a person confirms).

You run headless and ask nobody. Where an uncertainty changes the outcome, write it into
`intent.md`'s Open Questions as `Blocking:` with ready choices; the orchestrator asks it
before the Plan question.

## File to scenario traceability

Every planned file justifies itself: `src/reset.py → Scenario: "User resets password"`, or
`db/migrations/001_x.sql → Infrastructure: required by reset.py`. A file that is neither
either goes, or reveals a missing scenario.

## Grouped tasks

Write `tasks.md` as `templates/tasks.md` shows:

- A top-level `**Integration:**` line with the full suite command.
- `## Group G<n>: title`, then `**Depends:**`, `**Validate:**` (a group test command) and
  `**Context:**` (at most 4096 bytes: the enabled packs' rules that apply to this group in
  your own words, security rules always, the conventions and interfaces to keep).
- `### Task N: description` with `**File:**` (exact paths, no glob, the test file included),
  `**Depends:**`, `**Test:**` (the task's own scoped command, never the whole suite),
  `**Cases:**` (at least two, each a concrete input and its exact expected result: normal
  first, then edges, then errors), `**Traced to:**` and a `- [ ] done` box. A task block is at
  most 2048 bytes.
- Few groups: a new group only for a separate review unit. Inside a group, independent tasks
  get disjoint files; a task that needs another's code says `**Depends:** Task N`.

## Approach Decisions

Only when a real alternative was considered and rejected. The `Why not chosen` line names a
concrete constraint, risk or cost a reviewer could challenge from the text alone; never
"simpler" or "best practice" without saying what and at whose cost.

## Diagram

A mermaid diagram in `## Diagram` (under 30 nodes), then the same diagram as ASCII box art in
a fenced `text` block under 80 columns, for the terminal.

## Edge cases

- A vague request ("improve performance"): a Blocking question on which part, before exploring.
- No tests in the project: add a Task 0 that sets up the test tooling; scope new tests to new code.
- A monorepo: a Blocking question on which package; still check shared libraries.
- A migration: Task 1, before the code that needs it; one risk tier up; note the rollback.
- The feature partly exists: build on what is there and say so.
