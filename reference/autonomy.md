---
description: "The run to the commit: what a rule may do after the approval, and what it never does"
---

# The run to the commit

The CLI computes every move (`temper next --json`, ADR 0013; decision 3 of ADR 0019). The temper CLI is
`${CLAUDE_PLUGIN_ROOT}/scripts/temper`.

**The start.** Only the person starts it, at the approval: the Plan question, or the Design question when the person
asked for Design, after its check passed; it also accepts the intent. "Approve and build" runs
`temper state set run_mode autonomous`, then the stage's own steps; "Ask me at every stage" runs
`temper state set run_mode interactive`. `run.default` orders the two (`to-commit`, `ask`, `never-unattended`);
`autonomy.enabled: false` with no `run.default` reads as `ask`. The CLI refuses the call anywhere else, and records
the stage it was made at (`unattended_from`).

**What a rule does** (each an `auto` action, recorded in `.temper/rule-log.json`):

- A passed check moves on: Design, Build, Review, Check; a passed group's question is answered Continue.
- A failed check gets one counted repair: one loop back to Build for a Review finding at a level of
  `review.block-on`, or for a failed Check; the recommended option of a failed group check when it needs nothing
  typed, is no step back and the group declares no sensitive path. A finding below the level goes on and is named at
  the commit question.
- A task an earlier task built is taken as done.
- At a failed Build gate (the checks run when Build ends, 9.8.5, WP23) the failure record's class picks the step: a
  fault of the environment (`environment`) is a stop with the setup question, and no fix pass; a locked acceptance test
  that fails alone gets the triage agent, in every mode; a test the triage blames on the code gets one fix pass as the
  CLI's own action (one repeat of `gate:build`), and then the run asks; a test the triage calls wrong is a stop with
  the question, whose `Correct the acceptance test` is the person's. A failed suite or a measured coverage drop
  (`code`, the only failed rows) gets one fix pass by rule, then a stop; any other failed Build gate is a stop. No rule
  changes code for a test the triage does not blame on the code, and a class never changes a verdict.

**A stop** is everything else: the park call (`temper park`), then the stage's own question, whose text says the run
goes on by itself after the answer. The run keeps its mode; the answer's last call, `temper park --end --answer <id>`,
ends the stop. `.temper/autonomy-report.md` holds the verdict and the reason, and ends with
"The run waits for you at the gate it parked at." A plan that declares a file under `autonomy.park-on-touch` gets no
repair by rule. A run taken up with no words asks its stage once (`temper go --taken-up`). The stops are listed in
`scripts/stops.json`.

**A red base after the approval** (9.8.5, WP20) is a stop: the baseline, still running at the approval, ended red.
No new task agent is launched, the agents in flight finish and their calls run, the stop is recorded with its notice,
and the run asks the red base question. "Go on anyway" there is a skip, so the run then asks at every stage.

**What ends it.** A skip, an accepted finding, a step back to Plan or Intent, and "Ask me at every stage from here".

**What it never does.** It never plans again or changes a gate's command, the intent or the approved files; it never
skips a check, accepts a finding, answers a scope drift or writes the config; it never pushes, opens a pull request or
makes the final feature commit: the commit question always asks, and a pull request is opened only after the person
chose that option there. The commit gate holds a run that went on by itself (`ran_unattended`) to the plan's files
(`autonomy.max-blast-radius` bounds each group at the plan gate) and to `autonomy.park-on-touch`; the person confirms
a changed sensitive file at the failed commit question.

**The person is not watching.** Claude never asks "Shall I...?" in such a run: every stop is a question of the CLI.
