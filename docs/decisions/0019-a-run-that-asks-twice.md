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
2. **Design runs only when asked; design concerns are questions in front of the approval (WP14).**
   - **When Design runs.** A run of `/temper:temper` has the Design stage when the person chose `Run Design first`
     (option id `run-design`, in the More list of the passed plan question), when the Design door started the run,
     when `design.md` exists, or when the run is at Design or has a Design verdict, so a run saved there keeps it. The
     option sets the state key `want_design` and then leaves Plan with `design` as the next stage. No tier, no risk
     and no setting adds the stage.
   - **What Design asked.** A policy conflict or a product call is one Blocking line Plan writes into intent.md, the
     answer the plan assumes as its first choice, and the tasks are written under it. `state advance plan_complete`
     is refused while one is open, so the person answers each in front of the approval, with the mod or without it.
   - **The hold moves to the plan gate.** The row `tasks agree with decisions` leaves the Design gate. An answer that
     is the first choice passes it with a note; another answer fails it until `tasks.md` changes. The first such
     failure is the CLI's own `state redo plan` (the budget counts it under `gate:plan`); the second asks, with
     `Revise the plan` recommended.
   - **Risk H.** A plan of risk H gets the fresh review with no request, and the option that starts the unattended
     run is offered at risk H only after a complete round on the plan as it is with no open finding at high.
   - **What goes.** The risk and tier trigger of Design, the state key `intent_asked` and the config key
     `phases.design`. At the plan question `Run Design first` takes the place of `Teach Me` in a run with no Design,
     so every option stays within two dialogs.

## Consequences

- Following the recommendation always ends: at the latest after six repeats, the run asks the person once.
- The limits that only move a recommendation (the text compare of a run again, the counters of a group, the mark of a
  task run again) stay: they choose the option, and the budget is the bound.
- The two limits are config keys, so with the mod off an edit of the config during a run raises them.
- A default run launches no Design agent at any tier or risk. A person who wants Design asks for it with one more
  dialog (More options) at the approval, or with the Design door.
- A plan of risk H always costs a fresh review round, two reviewers by default, before the run may go on by itself.
