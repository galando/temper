# ADR-0025: One route

**Status:** Accepted
**Date:** 2026-11-21
**Amends:** ADR-0017 (the spec route it proposed is not built; its status is set to rejected)
**Relates to:** ADR-0019 (decision 2, Design only when asked), ADR-0022 (the acceptance tests keep their own writer)

## Context

ADR-0017 proposed a second route through the CLI for a request that already reads as a spec: the CLI would detect the
four parts of a spec in the request, the person would confirm the route, Intent would copy, Plan would group without
exploring, Design would be skipped and the fresh review would run one round of two lenses. It was written after one run
of a complex feature spent five Plan passes, six fresh reviewers and five Build attempts and put nothing on the branch.

By 9.8.5 the cost that route was meant to save is gone from the one route every request takes:

- Design runs only when the person asks for it (9.8.5, ADR-0019 decision 2). No tier and no risk adds it; a question
  Design would have asked is a Blocking question Plan writes, answered before the approval.
- Plan writes only what a script, a gate row or a later agent reads (9.8.5, the plan contract). At the simple tier a
  plan is `tasks.md` and the scenarios, with no `plan.md`; each scenario is one block of four lines; no tracing line,
  file table, diagram or risk section is written that nothing reads.
- Intent looks a fact up and never asks it, and leaves by rule when nothing is open: a request that states its rules
  reaches the approval with no question before it.
- A change to a plan that exists is made by a narrow revise agent, and every repeat is counted in one budget, so the
  review rounds that did not converge are bounded.

What is left of the spec route is a detector of four parts in free text, a second set of sections in two briefs, a
route mark that only the person may set, and a scenario that runs it in every mode: one more way for a run to differ,
for a saving the one route now makes for every request.

## Decision

1. **One route.** Every request, an idea or a spec, goes through Intent, Plan, Build, Review and Check, with one
   approval before code and one question at the commit. There is no route mark, no detector of a spec and no second
   section of a brief for one.
2. **Design on request.** Design is not a stage a route skips: it runs only when the person picks `Run Design first`
   at the approval, in every run.
3. **The plan contract.** What Plan writes is decided by what reads it (the plan gate rows, `tasks_md.py`, the Build
   task prompt, Review and Check), not by the shape of the request. A request that names its files and its tests
   gives the planner less to find; it does not get a different plan format.
4. **The spec route of ADR-0017 is not built.** ADR-0017 stays in the record with the status
   `Rejected: not built (9.8.5)`. A later proposal for a lighter front starts from a measured run of the one route,
   not from that draft.

## Alternatives Considered

### Build the spec route as ADR-0017 proposed
- **Pros:** a request that is already a spec could skip work in front of Build.
- **Cons:** a detector of free text decides a route, a second set of brief sections can drift from the first, and every
  test of the front runs twice.
- **Why not chosen:** Design on request and the plan contract already remove the work it would skip, for every request.

### One front launch for a request that leaves nothing open
- **Pros:** under 30 seconds less for such a request.
- **Cons:** it changes the guard table and the Intent gate's place in the run.
- **Why not chosen:** the saving is small and unmeasured; it stays on the list of later work.

## Consequences

### Positive
- One route to test, to document and to draw: the floor of `scripts/e2e/floor.json` counts it, and no scenario is
  needed for a second one.
- A request that states its rules still reaches the approval with nothing asked before it.

### Negative
- A request that is a full spec still runs the Intent and Plan agents; their cost is the cost of the one route.

### Neutral
- The fresh review of the plan stays a choice at the approval (`Fresh review first`), with its own config key.

## References

- ADR-0017 (the spec route, rejected), ADR-0019 (Design only when asked), ADR-0022 (the acceptance tests keep their own
  writer)
- `docs/flow.md` (what comes next), `reference/plan.md` (what Plan writes)
