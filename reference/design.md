# Design: System Design for Medium and Complex Runs

**Goal:** write `design.md` for a run of tier `complex`, or `medium` at risk H, when
`phases.design` is not `false`. Simple and trivial runs go from Plan straight to Build.

Read `intent.md`, `plan.md` and the enabled packs' `rules.md` (rules whose `phases` is `all` or
names `design`), and the project's `.claude/packs/stacks/{stack}.md` when it exists.

## What to design

**Medium:** the main components, the data flow between them, the key interfaces.
**Complex:** also the API contracts (request and response shapes), schema changes, the
integration points with external systems and the error handling strategy.

## Areas of Concern: flag while designing, not after

Anywhere two applicable rules pull in opposite directions (a pack rule and a stack pattern, a
constraint in `intent.md` and a security requirement), or a constraint cannot be fully met,
record it under **Areas of Concern**: the conflict, the options and who owns the call. These
are the points an analyst would escalate; the person resolves each at the Design question,
before Build spends anything on the wrong answer. Design flags a policy conflict; it never
silently picks a side.

**A concern the person must decide becomes a question with ready answers.** For each concern
that needs a product or policy call (a cap, a role, an edge case), also add one line to
`intent.md`'s Open Questions:
`- Blocking: Design: {the concern as a concrete question} choices: {recommended} | {other} | {other}`.
The orchestrator asks it before the Design question, and writes the answer into `intent.md`'s
Decisions and into the concern's `resolved:` line. A concern that is only a note for the
builders stays a concern.

The section is always present. With nothing to flag, write `None flagged: {why}`: an absent
section looks exactly like a forgotten check.

## Writing design.md

Use `templates/design.md`. Give each concern its own `###` heading with an owner, and each
decision its row in the Decision Log table.

## ADRs

Only in a project that already keeps ADRs (a `docs/decisions/` or `docs/adr/` folder with at
least one record): for each real architectural decision (storage technology, a framework for
a new capability, an API contract style, deployment, security architecture, an external
integration), write `NNNN-{slug}.md` with Status, Date, Context, Decision, Alternatives
Considered and Consequences, and list it in your return so the plan's file list covers it.
Never for naming, styling or code organization. Never delete an ADR; supersede it.
