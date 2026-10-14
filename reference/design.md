---
description: "System design exploration for complex features (optional stage)"
---

# Design: System Design Phase

**Goal:** Produce system design artifacts for complex/medium features — skipped for
simple/trivial. Active when `phases.design: true` AND complexity >= medium.

**Mode:** Design runs as a stage of `/temper` (also when `/temper:design` starts it: the
command is a door into `/temper`), in a clean subprocess with no `AskUserQuestion` gate:
return the summary, the orchestrator owns the gate. Load `intent.md`, `plan.md`, and the enabled packs' `rules.md`
(project `.claude/packs/` shadows global `~/.claude/packs/` shadows
the built-in files listed in `${CLAUDE_PLUGIN_ROOT}/reference/pack.md`, kept where `phases` is `all` or contains
`design`), plus the project's `.claude/packs/stacks/{detected-stack}.md` if present.

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
indistinguishable from a forgotten check, and `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate design` mechanically
requires the heading (its only requirement — silence is the one thing an unattended
design→build crossing must not let through).

## Step 3: Generate `design.md`

Write the project's `.temper/specs/{feature}/design.md` from `${CLAUDE_PLUGIN_ROOT}/templates/design.md`.

## Step 4: Summary + Gate

The panel format is owned by the design brief (`${CLAUDE_PLUGIN_ROOT}/agents/design.md`) — render exactly the panel it defines
(76 columns, fact rows then `AREAS OF CONCERN` and `DECISIONS` titled sections; the
concerns section is omitted entirely when design.md says "None flagged — {why}").
Never carry a second, different box here: whichever box a clean-context stage reads
first is the one that renders, and two shapes means two different reviews. Append
fact rows for what the design actually has: API contracts (`+ POST /api/x — shape →
response`), DB changes (`+ {table} — {columns}`), integration points.

Any flagged concern is presented **first** at the gate — it is the reason the human is
here. Write each concern as its own heading under Areas of Concern (or its own list item
at the margin), so the CLI can name it: the Design question lists the open ones (a
concern is resolved once a line of it starts with `resolved:`). "Continue to Build" with
open concerns means the human accepted them as written: leaving Design, the CLI adds
`resolved: accepted as written at the Design question ({date})` to each and the run
commits `design.md`. Another call, typed at the question, is written into the
concern's own `resolved: {what was decided}` line before the question is asked again.
An armed run parks at a Design with open concerns, so the person decides them.

The orchestrator asks the gate question exactly as `temper next --json` gives it (header
`Temper gate`; on a pass: "Continue to Build (Recommended)", "Walk through step by step"
(below), "Grill Me", and "More options" with Teach Me and Save for later). "Other" free text
edits `design.md` and asks the same question again: a change is never approval to proceed.

**Walkthrough:** read `design.md`, present only the sections it actually has — Architecture
Overview (always), API Contracts, Database Changes, Integration Points, Decision Log
(always) — one at a time via `AskUserQuestion` ("Next step" / "Ask a question", answer
then re-show the same section / "Other" edits then re-shows the same section). After the
last section, ask the gate question again.

## ADR Generation

After `design.md` is written, scan it for genuine architectural decisions — schema/
storage technology choice, framework/library selection for a new capability, API
contract design (REST vs GraphQL, versioning), infrastructure/deployment changes,
security architecture (auth flow, encryption), external-system integration. **Not**
styling/naming/code-organization/test-structure choices — those never get an ADR.

For each qualifying decision, write the project's `docs/decisions/NNNN-{slug}.md` (`NNNN`
sequential, check existing ADRs for the next number starting at 0001; `{slug}` kebab-case:
lowercase letters, digits and hyphens only, no `/`, no `..`) from
`${CLAUDE_PLUGIN_ROOT}/templates/adr.md` — Status (Proposed), Date, Context, Decision, Alternatives
Considered, Consequences. Never delete an ADR; supersede it with a new one referencing
`Supersedes: ADR-{NNNN}`. No qualifying decision → skip ADR generation entirely.

## Skip Conditions

The CLI decides whether a run has a Design stage: it has one when the complexity is Medium or
Complex and `phases.design` is not `false`, or when the spec folder already holds `design.md`.
Otherwise the run goes from Plan straight to Build.
