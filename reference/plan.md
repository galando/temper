---
description: "Transform a feature request into a structured implementation plan with impact analysis"
argument-hint: "<feature-name-or-JIRA-123>"
---

# Plan: Feature Planning with Impact Analysis

**Goal:** Turn a feature request into `intent.md` + `tasks.md` + `plan.md` — grounded in
a real blast radius, not an estimated one. This doc states the outcome and the handful of
rules a strong model would not derive on its own; it does not choreograph your steps.

## Usage

Plan runs as a stage of `/temper`, in a clean subprocess from the plan brief
(`${CLAUDE_PLUGIN_ROOT}/agents/plan.md`), also when `/temper:plan` starts the run (it is a door
into `/temper`). It returns a summary and never shows an `AskUserQuestion` gate: the
orchestrator owns the gate.

## What You Produce

**Hard rule — write exactly these three files under `.temper/specs/{feature-slug}/` for
Medium/Complex features, never a fourth: no `spec.md`, `quickstart.md`,
`evals/evalset.json`, README, or anything else in the spec directory.** `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate
plan` reads only these three.

- **`intent.md`** — Problem, Success Criteria (each with a `Validate:` type — see below),
  Constraints, Target Users, then Gherkin **Scenarios**.
- **`tasks.md`** — ordered implementation steps, each with a validation command and a
  `Traced to:` field (see File-to-Scenario Traceability).
- **`plan.md`** — Architecture, **Blast Radius** (required for Medium/Complex), Approach
  Decisions (only when a real alternative was rejected), a diagram.

**Count production files only.** The tier counts the files that hold the product's code: test
files, docs (README, CHANGELOG, guides) and a one-line export or registration edit follow from the
code and add no design question, so they do not count.

**Trivial** (one file, no product problem): no artifacts — say so and implement directly (in
`/temper` the Intent stage decides this). **Simple** (up to 3 production files, with new functions,
options or fields in existing modules only): an inline plan in the conversation, no files; in
`/temper` the three files below, and Design is skipped. **Medium** (4-10 production files, or a new
module, data model or external interface) / **Complex** (10+): the three files above, and Design
runs. `--full`/`--quick` force Complex/Simple. The risk multipliers below still push a tier up.

**intent.md usually already exists when you start.** In the orchestrated `/temper`
flow, the Intent stage wrote it and a human accepted it at the intent gate
(`Status: accepted`) before you launched — it is your input: derive Scenarios and
architecture from it, refine its wording only with a stated reason, never re-derive
the Problem from scratch. **Re-read every `- consulted:` source its `### Context
Sources` records** — the intent summarizes them, but you plan against them; treat
every `- unavailable:` line as an explicit gap (name it in `plan.md`, and add an
Open Question back into `intent.md` if it hides a decision). Do not re-derive
context Intent already gathered. A `Status: draft` intent (captured via
`/temper:intent` or a control-band breach) is the same
input, plus: resolve or explicitly re-carry each Open Question (a refine pass may
ask only a question the draft marks `Blocking`, or one a gate FAIL forces —
anything else thin becomes a new Open Question); the draft→accepted flip happens at
whichever human gate reviews it first.
**Risk multipliers** (each pushes complexity up one tier): touches auth/payment/security
code; changes what the consumers of a library with 5+ consumers already use (a signature,
a behaviour, a default; adding a new function or option they never call does not count); changes a DB schema; a module with a
historically high defect rate (`.temper/metrics.json` if present); a CRITICAL/HIGH
security hot path (below).

## What `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate plan` Checks

Quoted from the plan gate in the temper CLI (`${CLAUDE_PLUGIN_ROOT}/scripts/temper`) so this doc cannot drift from the gate.
These run **at every tier**: the artifacts exist (`intent.md` + `tasks.md`); scenario
count >= Success Criteria count; every criterion has explicit validation links
(`acceptance.py plan` — stable `AC-NN` ids, `Why:` and `Validate:` on each, every
`Covers:` id names a real criterion); every `Scenario:` sits inside a ```gherkin
fence; `plan.md` records `## Cross-Repo Search`. **Only for `medium`/`complex`**:
`plan.md` also needs a heading matching `blast radius` (any level, e.g.
`## Blast Radius`). Record `${CLAUDE_PLUGIN_ROOT}/scripts/temper state set complexity <tier>` as soon as you
classify it — the gate reads it to decide whether the Blast Radius section applies.

Fix any FAIL before returning: usually a missing scenario, an empty Success Criteria
section, a missing Cross-Repo Search record, or a missing Blast Radius heading.

## Cross-Repo Search

When any cross-repo code search tool is connected (for example a Sourcegraph MCP),
use it — for blast radius (callers of the changed code outside this repo), prior art
(has another repo solved this already), and definitions that live in a dependency.
When none is connected, or `tools.mode: heuristic-only`, say so and proceed with
local tools: the tool's absence never fails a gate, but a missing record does.
Record under `## Cross-Repo Search` in `plan.md`, one line per query:

```
- used: {tool} — {query} → {finding}
- not available: {reason}
```

Blast-radius rows found this way carry a `[CROSS-REPO]` label and name the repo.

## Explore: Your Own Tools, By Default

Explore the repo with your own tools, in your own context — stack, structure, patterns,
similar code, test coverage. A nested Explore subagent is an escape hatch for a repo
large enough that reading it directly would blow your context, not a mandatory first
step; that judgment call is yours, not a fixed procedure. Read `.claude/temper.config`
and enabled packs' `rules.md` (project shadows global shadows the built-in files listed in `${CLAUDE_PLUGIN_ROOT}/reference/pack.md`;
keep rules whose `phases` is `all` or contains `plan`) before you plan.

## Blast Radius: Measured, Not Estimated

Every file in the Blast Radius section must come from something you actually opened or
grepped — an importer list you read, a call site you found — not a plausible guess. If a
`code-review-graph` MCP server is available, prefer `get_impact_radius_tool` (label
findings `[PROVEN]`); otherwise grep for importers/consumers and label `[HEURISTIC]`.
For each changed file: who imports it, does the importer have test coverage for the
affected path, does it change a contract (API shape, event payload, DB schema), does it
bypass an established pattern. Output shape:

```
BLAST RADIUS — {feature}
  Direct impact:    {file} ({action}) → used by {N} consumers
  Transitive impact: {module} → calls {changed-function}()
  Risk areas:        {module} has {X}% coverage for {path}
  Architectural compliance: [ok]/[warn] {pattern} ...
```

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
way — this is what keeps the file list from over-engineering (no file exists without a
scenario or an infrastructure reason). Skip this section for Trivial/Simple.

- Every blast-radius **risk area** → at least one scenario.
- Every **acceptance criterion** → at least one scenario.
- Every **affected consumer** → a regression-guard scenario ("existing X still works").
- Every scenario is concrete (specific inputs/outputs) and testable — never "system works
  correctly".

Medium: 3-8 scenarios. Complex: 5-15. **Every scenario is one fenced ```gherkin
block** — never a bare `Scenario:` line with indented steps (markdown reads the
steps as a lazy continuation and renders the whole scenario as one run-on paragraph
in every preview and review surface). The fence holds the `Scenario:` line, the
Given/When/Then steps, and the two annotations: `Note:` — the testing approach
(`unit` the default for pure logic, `mock` for an external dependency,
`integration` for DB/multi-service, `manual` for the non-automatable: UX, email
delivery) and `Covers:` — the comma-separated AC ids this scenario verifies (a
regression-only scenario may omit it). Group the blocks under `#### Happy Path`,
`#### Error Paths`, `#### Edge Cases`; omit an empty group. Example:

    ```gherkin
    Scenario: Rate-limited caller gets 429, not a hang
      Given the API has received 100 requests in the last minute
      When one more request arrives
      Then it is rejected with 429 within 50ms
      Note: unit
      Covers: AC-01
    ```

After deriving scenarios, reconcile against your
preliminary file list: add files scenarios now require, and drop or justify-as-
infrastructure any file no scenario touches.

**Success-criteria validation types** — prefer the first two, mechanically checkable:

| Type | Example |
|---|---|
| `scenario` | `Validate: scenario — covered by "User resets password"` |
| `code` | `Validate: code — endpoint exists at POST /api/reset` |
| `metric` | `Validate: metric — measure support ticket volume post-deploy` |
| `manual` | `Validate: manual — UX review needed` |

Ask clarifying questions (`AskUserQuestion`, concrete options — "integrate with
existing PaymentService or create a new one?", never "what should the architecture
be?") only where the uncertainty changes the outcome — no fixed round count, one
question at a time. Skip entirely when requirements are clear.

## File-to-Scenario Traceability

Every planned file justifies its existence — a scenario-traced file
(`src/services/PasswordResetService.ts → Scenario: "User resets password"`) or an
infrastructure file that states its dependency (`db/migrations/001_x.sql → required by
PasswordResetService`). A file that is neither: question whether it's needed: if it is,
a scenario is missing — add one. In `tasks.md`, fill `Traced to:` for every task the same
way (`Traced to: Scenario: "name"` or `Traced to: Infrastructure: required by {module}`).

Order tasks by layer (infra → core → integration → tests). Tasks with disjoint files and
no `**Depends:**` between them run in parallel; give a task `**Depends:**` on another when it
needs that task's output or config change (see "Grouped tasks" below).

## Approach Decisions

Populate `## Approach Decisions` in `plan.md` **only** when a real alternative was
genuinely considered and rejected — an empty/absent section is valid and means exactly
that: no load-bearing choice was made. One genuine decision beats three padded ones.
Structure: Alternative / Pros / Cons / **Why not chosen** (`${CLAUDE_PLUGIN_ROOT}/templates/adr.md`'s shape).

**`Why not chosen` is the load-bearing field.** Every rejection names a concrete
constraint, risk, or cost that a reviewer could challenge from the text alone: not
"simpler" but what was simplified and at whose cost, not "best practice" but which
practice and which alternative it beat. Mirror each as one line in the summary box's
🧭 DECISIONS (`{chosen} (not {rejected})`, capped at 3, `+{N} more` beyond that).

## Diagram

Generate a mermaid diagram in `plan.md`'s `## Diagram` section (flowchart for component/
data flow, `stateDiagram-v2` for lifecycles, `sequenceDiagram` for cross-boundary calls,
`classDiagram` for type hierarchies) — under 30 nodes, `classDef` color-coding new vs.
existing vs. modified when it helps. Render the diagram as ASCII box-drawing art right
after the terminal summary panel too, as the one drawing allowed beside that panel (the
terminal can't render mermaid); keep the mermaid block in
plan.md for GitHub/tool rendering.

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
  `**Test:**`, `**Cases:**`, `**Traced to:**` and a closing `- [ ] done` box. The parser takes a task's group from the `## Group` heading it sits under (a `[group: G<n>]` tag in the
  title is not read).
  Task numbers are unique across the whole file.

**Declared files.** `**File:**` lists backticked paths, one per file the task will write, including its test file.
Give exact file paths, one per file. In grouped mode the plan gate refuses any glob
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
heading through its last field, the cases included) is at most 2048 bytes. Put long background in `plan.md`, not in tasks.md.

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

If a security-hot-path scan ran, also persist `.temper/security-map.json` (one entry per
CRITICAL/HIGH file: `file`, `function`, `sensitivity`, `entry_points[]` with `route`,
`exposure`, `has_auth_middleware`, `has_authorization_check`) for Review/Check to read.

## Summary Panel

The panel format is owned by the plan brief (`${CLAUDE_PLUGIN_ROOT}/agents/plan.md`) — render exactly the panel it defines
(76 columns, fact rows then titled sections, one row per item, empty sections
omitted), appending a `SECURITY: {N} CRITICAL, {N} HIGH hot paths` fact row when the
security scan found any. Never carry a second, different box here: whichever box a
clean-context stage reads first is the one that renders, and two shapes means two
different reviews.

Trivial: a one-line box, no gate. Simple: `Files: {N} create, {N} modify` / `Risk: {L/M}`.

## Approval

The orchestrator owns the plan gate (`${CLAUDE_PLUGIN_ROOT}/commands/temper.md`, Stage 1); this stage
never shows it: return the summary and stop. The gate's "Walk through step by step" option
presents Intent, Diagram, Scenarios, Architecture, Blast Radius and Tasks one section at a time,
with `AskUserQuestion` "Next step" / "Ask a question" between each, then asks the gate again. A
change typed via "Other" is never approval: make the edit, then ask the same gate again.

## Edge Cases

- Vague description ("improve performance") → ask which part before exploring.
- No tests in the project → flag lower coverage expectations, add a Task 0 "set up test
  infrastructure", scope new tests to the new code only.
- Monorepo → ask which package; still check blast radius across shared libraries.
- DB migration needed → Task 1, before code depending on the new schema; +1 risk tier;
  note the rollback path.
- Feature partially exists → build on the similar code found, don't duplicate; say so.
