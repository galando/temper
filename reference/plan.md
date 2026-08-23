---
description: "Transform a feature request into a structured implementation plan with impact analysis"
argument-hint: "<feature-name-or-JIRA-123>"
---

# Plan: Feature Planning with Impact Analysis

**Goal:** Turn a feature request into `intent.md` + `tasks.md` + `plan.md` — grounded in
a real blast radius, not an estimated one. This doc states the outcome and the handful of
rules a strong model would not derive on its own; it does not choreograph your steps.

## Usage

```
/temper:plan "feature description" | "JIRA-123" | "#123"
/temper:plan --full "feature"    # force full artifact set even for a small change
/temper:plan --quick "feature"   # force a lightweight, inline plan
```

**Modes:** Standalone (`/temper:plan`) runs in the current context and shows its own
gate. Agent subprocess (from `/temper`) runs in a clean context and returns a summary —
`agents/plan.md` step 5 already tells you not to show an `AskUserQuestion` gate in that
mode; the orchestrator owns it. The methodology below is identical either way.

## What You Produce

**Hard rule — write exactly these three files under `.temper/specs/{feature-slug}/` for
Medium/Complex features, never a fourth: no `spec.md`, `quickstart.md`,
`evals/evalset.json`, README, or anything else in the spec directory.** `temper gate
plan` reads only these three.

- **`intent.md`** — Problem, Success Criteria (each with a `Validate:` type — see below),
  Constraints, Target Users, then Gherkin **Scenarios**.
- **`tasks.md`** — ordered implementation steps, each with a validation command and a
  `Traced to:` field (see File-to-Scenario Traceability).
- **`plan.md`** — Architecture, **Blast Radius** (required for Medium/Complex), Approach
  Decisions (only when a real alternative was rejected), a diagram.

**Trivial** (<3 files): no artifacts — say so and implement directly. **Simple** (3-5
files): an inline plan in the conversation, no files. **Medium** (5-10) / **Complex**
(10+): the three files above. `--full`/`--quick` force Complex/Simple.

**A draft intent.md already exists** (captured via `/temper:intent`, or drafted from a
`temper bands` breach): it is your input, not something to overwrite. Keep the
originator's Problem and Constraints (correct only with a stated reason), tighten the
Success Criteria with `Validate:` types, resolve or explicitly re-carry each Open
Question (they count toward the 2-3 clarifying questions below), then derive Scenarios
as usual. The `Status: draft` header stays until a human accepts the plan gate.

**Risk multipliers** (each pushes complexity up one tier): touches auth/payment/security
code; modifies a library with 5+ consumers; changes a DB schema; a module with a
historically high defect rate (`.temper/metrics.json` if present); a CRITICAL/HIGH
security hot path (below).

## What `temper gate plan` Checks

Quoted from `gate_plan()` in `scripts/temper` so this doc cannot drift from the gate:

1. **Artifacts exist** — `intent.md` and `tasks.md` present under the spec path.
2. **Criteria → Scenarios** — scenario count >= Success Criteria count. Record
   `temper state set complexity <tier>` as soon as you classify it — the gate reads it.
3. **Blast Radius documented** — for `medium`/`complex` only, `plan.md` has a heading
   matching `blast radius` (any level, e.g. `## Blast Radius`).

Fix any FAIL before returning: usually a missing scenario, an empty Success Criteria
section, or a missing Blast Radius heading.

## Explore: Your Own Tools, By Default

Explore the repo with your own tools, in your own context — stack, structure, patterns,
similar code, test coverage. A nested Explore subagent is an escape hatch for a repo
large enough that reading it directly would blow your context, not a mandatory first
step; that judgment call is yours, not a fixed procedure. Read `.claude/temper.config`
and enabled packs' `rules.md` (project shadows global shadows built-in; keep rules whose
`phases` is `all` or contains `plan`) before you plan.

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

Medium: 3-8 scenarios. Complex: 5-15. Tag each with a `Note:` — `unit` (default, pure
logic), `mock` (external dependency), `integration` (DB/multi-service), or `manual`
(non-automatable: UX, email delivery). After deriving scenarios, reconcile against your
preliminary file list: add files scenarios now require, and drop or justify-as-
infrastructure any file no scenario touches.

**Success-criteria validation types** — prefer the first two, mechanically checkable:

| Type | Example |
|---|---|
| `scenario` | `Validate: scenario — covered by "User resets password"` |
| `code` | `Validate: code — endpoint exists at POST /api/reset` |
| `metric` | `Validate: metric — measure support ticket volume post-deploy` |
| `manual` | `Validate: manual — UX review needed` |

Ask clarifying questions (max 2-3, `AskUserQuestion`, concrete options — "integrate with
existing PaymentService or create a new one?", never "what should the architecture be?")
only when scenarios reveal a genuine ambiguity. Skip entirely when requirements are clear.

## File-to-Scenario Traceability

Every planned file justifies its existence — a scenario-traced file
(`src/services/PasswordResetService.ts → Scenario: "User resets password"`) or an
infrastructure file that states its dependency (`db/migrations/001_x.sql → required by
PasswordResetService`). A file that is neither: question whether it's needed: if it is,
a scenario is missing — add one. In `tasks.md`, fill `Traced to:` for every task the same
way (`Traced to: Scenario: "name"` or `Traced to: Infrastructure: required by {module}`).

Order tasks by layer (infra → core → integration → tests). Mark independent tasks
`[PARALLEL: with Task N]` only when they touch disjoint files and neither depends on the
other's output or config changes — default to `[SEQUENTIAL: after Task N]` when unsure.

## Approach Decisions

Populate `## Approach Decisions` in `plan.md` **only** when a real alternative was
genuinely considered and rejected — an empty/absent section is valid and means exactly
that: no load-bearing choice was made. One genuine decision beats three padded ones.
Structure: Alternative / Pros / Cons / **Why not chosen** (`templates/adr.md`'s shape).

**`Why not chosen` is the load-bearing field — banned, verbatim:**
- "less optimal", "not as good", "suboptimal", "less suitable"
- "for simplicity" without naming what was simplified and at whose cost
- "best practice" without naming the practice and the alternative it beat

Every rejection must name a concrete constraint, risk, or cost — a reviewer should be
able to challenge it from the text alone. Mirror each as one line in the summary box's
🧭 DECISIONS (`{chosen} (not {rejected})`, capped at 3, `+{N} more` beyond that).

## Diagram

Generate a mermaid diagram in `plan.md`'s `## Diagram` section (flowchart for component/
data flow, `stateDiagram-v2` for lifecycles, `sequenceDiagram` for cross-boundary calls,
`classDiagram` for type hierarchies) — under 30 nodes, `classDef` color-coding new vs.
existing vs. modified when it helps. Render the diagram as ASCII box-drawing art in the
terminal summary box too (the terminal can't render mermaid); keep the mermaid block in
plan.md for GitHub/tool rendering. Skip the diagram only for a single-file or config-only
change in standalone `/temper:plan`.

## Evidence + State (batch these into one Bash call)

```
$CLAUDE_PLUGIN_ROOT/scripts/temper state set complexity <trivial|simple|medium|complex>
$CLAUDE_PLUGIN_ROOT/scripts/temper gate plan
```

If a security-hot-path scan ran, also persist `.temper/security-map.json` (one entry per
CRITICAL/HIGH file: `file`, `function`, `sensitivity`, `entry_points[]` with `route`,
`exposure`, `has_auth_middleware`, `has_authorization_check`) for Review/Check to read.

## Summary Box

```
+-----------------------------------------------------------+
| PLAN — {Feature Name}                                     |
+-----------------------------------------------------------+
| INTENT: {one-line problem} -> {success criteria}           |
| SCENARIOS: {N} ({unit}/{mock}/{integration}/{manual})      |
| ARCHITECTURE: create {N} files, modify {N} files            |
| DECISIONS: {chosen} (not {rejected}) [+{N} more] | none     |
| COMPLEXITY: {trivial|simple|medium|complex}  RISK: {L/M/H}  |
| SECURITY: {N} CRITICAL, {N} HIGH hot paths (if any)          |
+-----------------------------------------------------------+
{ASCII art diagram, or N/A for a standalone single-file/config-only change}
```

Trivial: a one-line box, no gate. Simple: `Files: {N} create, {N} modify` / `Risk: {L/M}`.

## Approval (standalone `/temper:plan` only)

Subprocess mode never shows this — return the summary and stop (see above). Standalone:
`AskUserQuestion` — "Continue to Build (Recommended)" / "Walk through step by step"
(present Intent, Diagram, Scenarios, Architecture, Blast Radius, Tasks one section at a
time, `AskUserQuestion` "Next step"/"Ask a question" between each) / "Save for later". A
change typed via "Other" is never approval — make the edit, then re-show this same gate.

On Continue: write `.temper/build-state.json` (`stage: plan_complete`, `next_stage:
build`, `artifacts: ["intent.md","tasks.md"]`); if intent.md's header says `Status:
draft`, flip it to `Status: accepted` and add `**Accepted-by:** {git config user.name}
<{user.email}>` — the human Continue *is* the acceptance, and the artifact records who
gave it. Commit the accepted artifacts in two steps — `git add .temper/specs/{slug}/`
first, then `git commit -m "docs(plan): accept {slug} — plan approved"` as a separate
call (not `add && commit`: the in-agent commit-gate hook checks `temper gate commit`
when the commit is submitted, and the artifact-only carve-out that passes it mid-run
reads the already-staged set). Skip with a note if the project gitignores
`.temper/specs/`. Standalone mode loads only `tasks.md` + `intent.md` for Build.
Subprocess mode: the orchestrator handles the transition.

## Edge Cases

- Vague description ("improve performance") → ask which part before exploring.
- No tests in the project → flag lower coverage expectations, add a Task 0 "set up test
  infrastructure", scope new tests to the new code only.
- Monorepo → ask which package; still check blast radius across shared libraries.
- DB migration needed → Task 1, before code depending on the new schema; +1 risk tier;
  note the rollback path.
- Feature partially exists → build on the similar code found, don't duplicate; say so.
