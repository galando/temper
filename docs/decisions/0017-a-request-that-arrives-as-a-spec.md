# ADR-0017: A request that arrives as a spec (draft)

**Status:** Proposed (a draft; nothing of it is built)
**Date:** 2026-11-12
**Relates to:** ADR-0011 (grouped Build), ADR-0013 (the CLI says what next)

## Context

A `/temper:temper` run of a complex feature (8 criteria, about 30 files, risk H) took 5 Plan passes, 6 fresh reviewers over
3 rounds and 5 Build attempts of one group, asked the person about 30 questions, and put nothing on the branch. The request
itself already stated the rules, the files to change, the tests to update and the done condition. Intent, Plan, Design and
three review rounds mostly derived again what the request said, and each derivation was a new place to drift from it.

The full pipeline is built for a request that is an idea: Intent finds the problem and the criteria, Plan finds the files
and the blast radius, Design weighs the architecture, the fresh review finds what the plan left open. When the request is a
spec, those stages have little to find, and their cost (agent runs, rounds, questions) buys little.

9.8.4 fixed the faults that made that run diverge (a group that could not pass its own Validate, blind retries, loop backs
that forgot what they learned, review rounds that did not converge). This ADR is about the cost that remains when nothing
goes wrong.

## Proposal

A **spec path**: a lighter route through the same CLI, for a request that is already a spec. Same gates, same evidence
ledger, same commit hook; fewer agent stages in front of Build.

1. **Detection is the CLI's, and the person confirms it.** `temper next` at Intent reads the request (the run's `feature`
   text) for the four parts of a spec: rules or criteria (a numbered or bulleted list of behaviors), the files to change
   (paths), the tests (test paths or commands), and a done condition (a command, or a stated check). With all four, the
   Intent question offers `Use the request as the spec (Recommended)` next to the full route. Without one of them, the
   question names the part that is missing and the full route stays the one recommended. No model decides the route.
2. **Intent copies, it does not derive.** On the spec path, the Intent agent writes `intent.md` from the request, keeping
   each rule as a criterion in the request's own words (an `AC-NN` id, a `Why:` taken from the request or marked
   `(proposed)`, a `Validate:` naming the request's test). It adds no criterion and drops none. The Intent gate is unchanged.
3. **Plan groups, it does not explore.** Plan reads the files the request names and the tests that cover them, writes
   `tasks.md` in groups (the 9.8.4 plan gate rows hold: a group can pass its own Validate, no production file split over
   more than two tasks), and writes a short `plan.md` (the blast radius of the named files, the cross-repo search line).
   The brief's codebase exploration is skipped; the project brief (`temper brief`) still runs.
4. **No Design.** The spec path skips Design whatever the tier, as a door run does (`temper state init --enter build`
   already shows the CLI can start past a stage). A risk H plan on the spec path still builds its tasks on sonnet.
5. **One fresh review round, two lenses.** `readiness` and `tests` only, on round 1; a high finding sends the plan back
   once (a recheck round, as 9.8.4 runs it), and then the person decides. No `zoom-out` (the request chose the scope) and
   no `comprehension` paraphrase (the request is the paraphrase).
6. **The done condition is the Integration command.** The request's done condition becomes `**Integration:**` in
   `tasks.md` and a scenario's `Test:` line, so Check runs exactly what the request said done means.
7. **Build, Review, Check and the commit are unchanged.** The savings are all in front of Build; nothing after it trusts the
   request more than the code.

## What it would cost

- A detector in `scripts/flow.py` (the four parts) and a case per part in `temper-cases-8.sh`, plus the Intent question's
  extra option in the view fixtures (`make-view-fixtures.sh`).
- A `route: spec` mark in the run state, set only by the person's answer (a person-only call in the mod's table, ADR-0016).
- Spec path sections in `agents/intent.md` and `agents/plan.md` (stage logic stays in the stage briefs), and
  `fresh_review.py` lenses chosen by the route.
- An e2e scenario that runs a spec request end to end with the mod and without it.

## Risks

- **A request that looks like a spec and is not one.** Four parts present does not mean four parts right. The person
  confirms the route at the Intent question, and every gate still runs; a wrong spec fails where a wrong plan would.
- **Copying a mistake faithfully.** Intent no longer questions the request. The Intent question still shows the criteria,
  and Review still checks the change against them.
- **Two routes to keep in step.** Every later change to Intent, Plan or the fresh review has to say what it does on the spec
  path. Keeping the path a subset of the full route (stages skipped, never different stages) limits that.

## Alternatives considered

- **Use a door (`/temper:build`).** A door starts at Build only when an approved plan exists; a spec request has none, and
  writing `tasks.md` by hand is the work the spec path would do for the person.
- **Turn the fresh review off (`plan.fresh-review: off`).** Saves the rounds but keeps Intent, Plan exploration and Design,
  and loses the `tests` lens, the one that would have caught the failed run's G1 and G2 split.
- **Lower the tier to simple.** The tier says how big the change is, not how well it is specified; a large, well specified
  change would lose the blast radius it needs.

## Decision

None yet. This draft is for the person to accept, change or reject. If accepted, it is built in its own change, with a
failing test first for each point above.
