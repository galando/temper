# ADR-0019: A run that asks twice

**Status:** Accepted
**Date:** 2026-11-17
**Amends:** ADR-0016 (one row of its table); the later decisions of this record amend ADR-0011, ADR-0012 and ADR-0013

## Context

A run that goes on by itself takes the recommended option, so a limit that only moves the recommendation is the real
bound of its repeats. At the base, eleven limits bounded a repeat, by five techniques, and only three of them refused a
call: the step back of one pair of stages, the attempts of a task and the writer of the acceptance tests
(`docs/plans/one-go/evidence/v-failure-budget.md`, section 1.3). A run again of a stage, the tasks of a group again, a
fix of a group and more time for its check were counted nowhere. Every other store of a failure is deleted or archived
by a step back, so a run that stepped back to Plan forgot what it had tried. The loop keys of the config
(`loops.max-per-type`, `fix.max-loops`, `feedback.enabled`, `autonomy.budget`) were read by some sites, by one site, or
by none.

## Decision

1. **One budget, in the CLI.** Every repeat that follows a failed check spends one entry of one record,
   `.temper/budget.json`, read only through `scripts/budget.py`.
   - **What it counts.** A failure is the check that failed, its key: `gate:<stage>`, `group:<G>`, `task:<N>`,
     `acceptance`, `pipeline`. A failed `integrate` spends under `gate:build`. One table, `SPENDS`, read by the CLI and
     by the flow, says which calls spend and when: a step back from a failed gate (from Build, also from a failed or
     parked group, under that group's key), a run again of a failed stage, a group fix, the group's tasks again, more
     time at a failed group check, a plan patch, a task retry, a task checked again after an environment fault, a
     reopened acceptance test, a CI fix round, and a merge again after a failed `integrate`. A task's attempts 1 to 3,
     `group continue`, `state advance` and every call at a passed gate spend nothing. The condition is read from the
     recorded verdicts and skips (the flow's `Run`), never from an argument: no flag and no variable exempts a call.
   - **The limits.** 2 for one failure (`budget.per-failure`) and 6 for one run (`budget.per-run`), defaults in code.
     The CLI's dispatcher checks a call of the table before it runs: past a limit it prints `BLOCKED: ...`, exits 1,
     writes nothing, and the call does not run. A call refused later for a reason of its own has spent its repeat. The
     record belongs to one run id: it survives a step back, and `state clear` and `state init` remove it.
   - **Who grants more.** `temper next` never offers a call the budget refuses. A question that would offer one
     becomes `run.budget`: the count, Save for later (recommended), Allow two more and the options that spend nothing.
     An armed run parks there. Only the person grants more, with `temper budget grant --key K --reason R`, the call of
     the option `grant-more`; the mod lets it through only on that answer (ADR-0016), and refuses a write of the record.
   - **What goes.** `loop_step.budget`, `Run.loop_budget`, the refusal per pair of stages, the rule "Build to Plan once
     per run" and the keys `fix.max-loops`, `feedback.enabled`, `loops.max-per-type`, `autonomy.budget.max-total-loops`
     and `autonomy.budget.max-stages`. A config that still holds one is not an error.

## Consequences

- Following the recommendation always ends: at the latest after six repeats, the run asks the person once.
- The limits that only move a recommendation (the text compare of a run again, the counters of a group, the mark of a
  task run again) stay: they choose the option, and the budget is the bound.
- The two limits are config keys, so with the mod off an edit of the config during a run raises them.
