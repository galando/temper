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

3. **The approval runs to the commit by default (WP11).**
   - **What starts it.** Only the person's option at the approval: `approve-run` ("Approve and build", move `arm`) of
     `plan.approve`, or of `design.pass` when the person asked for Design. Its first call, `temper state set run_mode
     autonomous`, is refused unless the run is at Plan or Design with that check passed and not skipped, and under
     `run.default: never-unattended`; it records `unattended_from`, which `state set` refuses. `run.default` is
     `to-commit` (the default: `approve-run` first and recommended), `ask` (`ask-every-stage` first and recommended)
     or `never-unattended` (`ask-every-stage` alone); `autonomy.enabled: false` with no `run.default`, and an unknown
     value, read as `ask`. A saved autonomous run with no `unattended_from` (9.8.4, or the base) asks at every stage:
     it was approved for Build alone. A run saved at Review by an older Temper runs Review once more: its completion
     row names no file read. `state init` stamps `saved_by`; a state with none is taken up so, once. The key
     `autonomy.policy` and `Run.policy` go.
   - **What a rule may do.** Move on after a passed check (Design, Build, a group, Review, Check); take a task an
     earlier task built as done; give a failed check one counted repair: one loop back to Build for a Review finding at
     a level of `review.block-on` or a failed Check, or the recommended option of a failed group check when it has
     calls, needs nothing typed, does not save the run, is no step back and the group declares no sensitive path.
     Each is an entry of `.temper/rule-log.json`, with every stop and every answer.
   - **What a rule may never do.** Plan again, change a gate's command, the intent or the approved files, skip a
     check, accept a finding, answer a scope drift, write the config, push, open a pull request, make the final
     commit, or repair anything in a plan that declares a sensitive path (`autonomy.park-on-touch`, risk H).
   - **The stops.** Every other case is a stop: the park call, then the stage's own question. The rows of
     `scripts/stops.json` are the list; 20 to 22 join here: a failed check in a plan with a sensitive path, a Check
     whose only failed row is the mutation row (until WP19 makes the score information), and a run taken up again
     (`temper go --taken-up`). A stop keeps the mode; its question says the run goes on by itself after the answer,
     and each option ends the stop with `park --end --answer <id>`. Removing a stop needs a decision record.
   - **What ends it.** A skip, an accepted finding, a step back to Intent, Plan or Design (each writes
     `run_mode interactive` in the CLI) and "Ask me at every stage from here". A step back to Build keeps it.
   - **The commit.** It always asks: commit, commit and open a pull request, or a loop back to Build. A failed commit
     gate with a changed sensitive file outside the plan offers `confirm` (`temper override sensitive-path:<path>`).
     Temper pushes only after the person chose a pull request option there.
4. **The approval is bound to what was shown (WP12).**
   - **What it binds.** The intent and the plan as the approval showed them. `temper next` takes the digests of
     `intent.md` and `tasks.md` in the call that builds the question (`scripts/approval.py`): of `intent.md` without
     the lines the CLI writes itself (`Status`, `Accepted-by`, `Completed`), of `tasks.md` the plan digest (each task's
     files, Depends and Test, each group's Depends, Validate, Interfaces and Context, the Integration line). The
     approving advance carries them, `state advance plan_complete <next> --shown intent.md=<H1> --shown tasks.md=<H2>`,
     and so does `state advance design_complete` when the person asked for Design. Before it writes anything the CLI
     hashes each named file again and refuses the call when one changed: the person is asked again. `plan_complete` is
     refused too while `intent.md` is a draft. `intent accept --digest <H1>` refuses in the same way.
   - **What it records.** `state advance plan_complete` records `intent_hash` beside `plan_hash` and `approved_files`,
     from the files as they are at that call, whoever calls; `design_complete` records both again, since the answer at
     the Design question approves what Design changed. `state set` refuses the three keys.
   - **What holds it later.** The row `intent unchanged since the approval` of the Build, Check and commit gates fails
     when either file changed since (one row names both files; a run with no `intent_hash`, saved before 9.8.5, passes
     it). The way on is the stage's failed question: a step back to Plan and a new approval, restoring the file, or the
     person's skip. In a run that goes on by itself the failed row is a stop: a rule never changes the intent or the
     approved plan. With the mod a tool write of the run's `intent.md` is refused from Build on.
   - **What nothing checks.** The arguments are optional, so a call typed without them approves whatever the two files
     hold then, and the gates bind that. With the mod the option's calls are matched word for word, so the click is
     bound to the digests the question carried; with the mod off nothing checks the click. `plan.md` (the Context Map,
     the approach) is in no digest.
   - **Before the approval.** A run makes no branch and no commit before the approval: leaving Intent is `intent
     accept` and the advance; the approval switches to the run's branch, makes one commit of the spec folder there and
     advances. A branch an earlier run left is no question of its own: the approval names it and continues on it, and
     its More list offers a new branch. With the mod off the commit hook gates the branch the run stands on before the
     approval too (`from_branch`), and the classic hook `scripts/guards/hold_before_approval.py` refuses a project file
     write by the tools that write a file at Intent, Plan and Design of a feature run.
5. **The run leaves Intent by rule; the approval accepts the intent (WP13).**
   - **The rule.** A passed Intent check with an `intent.md` and nothing open is the CLI's own `work` action, the one
     call `state advance intent_complete plan`; the intent stays a draft. Nothing open means: a `/temper:temper` run,
     a check that passed and was not skipped, no Blocking question open, no step back into Intent, no note the person
     typed at Intent, and no door that walked it. Otherwise the Intent question is asked as before.
   - **One click.** The approval's first options accept a draft intent (`intent accept --digest <H1>`, recorded as
     `Accepted-by: the person, at the plan approval`) before the one commit and the advance; their text says so. The
     More list offers the step back to Intent. A skip of a failed plan gate never accepts the intent: with a draft it
     is the override alone, then the intent is accepted by its own question at Plan, and the plan question follows.
   - **The Context check.** Under `auto` the person is asked only about a map with an `ignore` or a `gap` line; a clean
     map stays `reviewed: pending`, Plan's own claim. A flagged map whose lines the approval shows whole is answered
     there: the approving option records `As planned (at the approval, N flagged lines shown)`. Any other flagged map
     keeps its own question, and `always` asks every map.

## Consequences

- Following the recommendation always ends: at the latest after six repeats, the run asks the person once.
- The limits that only move a recommendation (the text compare of a run again, the counters of a group, the mark of a
  task run again) stay: they choose the option, and the budget is the bound.
- The two limits are config keys, so with the mod off an edit of the config during a run raises them.
- A default run launches no Design agent at any tier or risk. A person who wants Design asks for it with one more
  dialog (More options) at the approval, or with the Design door.
- A plan of risk H always costs a fresh review round, two reviewers by default, before the run may go on by itself.
- A clean default run asks two dialogs, the approval (which accepts the intent) and the commit. A request that left
  rules open costs one more dialog for every four of them.
- A default run asks at the approval and at the commit; a failed check asks after its one repair. A person who wants
  every gate's question picks Ask me at every stage, or sets `run.default: ask`.
- The amended invariants: ADR-0011 (resolution 1: the unattended run is no longer Build alone), ADR-0012 (decision 4:
  a stop keeps the mode), ADR-0013 (decision 1: the CLI's own `auto` action carries the run from the approval to the
  commit).
