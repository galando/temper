---
description: "System design exploration for complex features (optional stage)"
---

# Design: System Design Phase

**Goal:** Produce system design artifacts for complex/medium features — skipped for
simple/trivial. Active when `phases.design: true` AND complexity >= medium.

**Modes:** Standalone (`/temper:design`) runs in the current context, own gate. Agent
subprocess (from `/temper`) starts clean, no `AskUserQuestion` gate — return the summary,
the orchestrator owns it. Load `intent.md`, `plan.md`, and the enabled packs' `rules.md`
(project `.claude/packs/` shadows global `~/.claude/packs/` shadows built-in
`$CLAUDE_PLUGIN_ROOT/packs/`, kept where `phases` is `all` or contains `design`), plus
`.claude/packs/stacks/{detected-stack}.md` if present.

## Step 1: Analyze the Plan

Read `intent.md` + `plan.md`: feature scope, success criteria, planned file changes,
risk level and complexity.

## Step 2: System Design Exploration

**Medium:** primary system components, data flow between them, key interfaces.
**Complex:** full architecture diagram, API contract definitions (request/response
shapes), DB schema changes (if any), integration points with external systems, error
handling strategy.

**Flag areas of concern while designing, not after.** Anywhere two applicable rules
pull in opposite directions (a pack rule vs. a stack pattern, a constraint in
`intent.md` vs. a security requirement), or a constraint cannot be fully satisfied:
record it in `design.md` → **Areas of Concern** with the conflict, the options, and
who owns the call. These are the points an analyst would have escalated — a human
resolves each one at the design gate, before Build spends anything on the wrong
answer. Design flags; it never silently picks a side on a policy conflict.

The section is **always present** — when nothing was flagged, write
`None flagged — {one line on why}` rather than omitting it: an absent section is
indistinguishable from a forgotten check, and `temper gate design` mechanically
requires the heading (its only requirement — silence is the one thing an unattended
design→build crossing must not let through).

## Step 3: Generate `design.md`

Write `.temper/specs/{feature}/design.md` from `$CLAUDE_PLUGIN_ROOT/templates/design.md`.

## Step 4: Summary + Gate

```
+--------------------------------------------------------------+
| DESIGN -- {Feature Name}                                     |
+--------------------------------------------------------------+
| Components: {N} new, {N} modified, {N} existing               |
| API contracts (if any): + POST /api/x -- shape -> response    |
| DB changes (if any): + {table} -- {columns}                   |
| Integration points: {external system} -- how it connects      |
| Decision log: 1. {decision} -- {rationale}                    |
| Areas of concern: {N} flagged (or "none")                     |
+--------------------------------------------------------------+
```

Any flagged concern is presented **first** at the gate — it is the reason the human is
here. "Continue to Build" with open concerns means the human accepted them; record
their call in the concern's line (`resolved: {what was decided}`).

`AskUserQuestion`: "Continue to Build (Recommended)" (save `design.md`, proceed) / "Walk
through design step by step" (below) / "Save for later". "Other" free-text → edit
`design.md`, re-show this gate — a change is never approval to proceed.

**Walkthrough:** read `design.md`, present only the sections it actually has — Architecture
Overview (always), API Contracts, Database Changes, Integration Points, Decision Log
(always) — one at a time via `AskUserQuestion` ("Next step" / "Ask a question", answer
then re-show the same section / "Other" edits then re-shows the same section). After the
last section: "Continue to Build (Recommended)" / "Save for later".

## ADR Generation

After `design.md` is written, scan it for genuine architectural decisions — schema/
storage technology choice, framework/library selection for a new capability, API
contract design (REST vs GraphQL, versioning), infrastructure/deployment changes,
security architecture (auth flow, encryption), external-system integration. **Not**
styling/naming/code-organization/test-structure choices — those never get an ADR.

For each qualifying decision, write `docs/decisions/NNNN-{slug}.md` (`NNNN` sequential,
check existing ADRs for the next number starting at 0001; `{slug}` kebab-case) from
`templates/adr.md` — Status (Proposed), Date, Context, Decision, Alternatives
Considered, Consequences. Never delete an ADR; supersede it with a new one referencing
`Supersedes: ADR-{NNNN}`. No qualifying decision → skip ADR generation entirely.

## Skip Conditions

Auto-skipped (orchestrator goes straight to Build): Trivial/Simple complexity,
`phases.design: false`, or a config-only/single-file plan.
