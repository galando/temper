---
description: "System design exploration for complex features (optional stage)"
---

# Design: System Design Phase

**Goal:** Produce system design artifacts, when the person asked for Design at the plan approval (WP14).

**Mode:** Design runs as a stage of `/temper`, in a clean subprocess with no `AskUserQuestion` gate:
return the summary, the orchestrator owns the gate. Load `intent.md`, `plan.md`, and the pack files your prompt lists
on its `Packs:` line (the CLI chose those of Design), plus the project's `.claude/packs/stacks/{detected-stack}.md` if
present.

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

**A concern the person must decide becomes a question with ready answers (9.8.0).** For a product or policy call
(a cap, a role, an edge case) also add one line to intent.md's `### Open Questions`: `- Blocking: Design:
{the concern as a concrete question} choices: {the answer the tasks assume} | {other}`. The CLI asks it before the
Design question; the answer goes into Decisions and that concern's `resolved:` line. A concern that is only a note
for the builders stays a concern.

The section is **always present** — when nothing was flagged, write
`None flagged — {one line on why}` rather than omitting it: an absent section is
indistinguishable from a forgotten check, and `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate design` mechanically
requires the heading (its only requirement — silence is the one thing an unattended
design→build crossing must not let through).

## Step 3: Generate `design.md`

Write the project's `.temper/specs/{feature}/design.md` from `${CLAUDE_PLUGIN_ROOT}/templates/design.md`.

## Step 4: Summary + Gate

The CLI draws the Design panel (`temper panel design`, 9.8.0) from design.md: the counts of the API Contracts and
Database Changes headings and of the open concerns, then the `AREAS OF CONCERN` (each heading, with its `resolved:`
line or `(open)`) and `DECISIONS` (the Decision Log table's rows) sections; a "None flagged" Areas of Concern gives no
concerns section. This stage draws no box: it returns `DESIGN DONE {path to design.md}`.

Any flagged concern is presented **first** at the gate — it is the reason the human is
here. Write each concern as its own heading under Areas of Concern (or its own list item
at the margin), so the CLI can name it: the Design question lists the open ones (a
concern is resolved once a line of it starts with `resolved:`). "Continue to Build" with
open concerns means the human accepted them as written: leaving Design, the CLI adds
`resolved: accepted as written at the Design question ({date})` to each, as a paragraph
of its own (indented to the item's text under a list item concern), and the run
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

**Only in a project that keeps ADRs (9.8.0):** a `docs/decisions/` folder with at least one ADR in it. Otherwise
write none: an ADR nobody asked for is a file outside the plan, and the commit gate's scope row names it.

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

A run has a Design stage only when the person chose `Run Design first` at the plan approval, or the spec folder
already holds `design.md`. No tier and no risk adds it; otherwise the run goes from Plan to Build.
