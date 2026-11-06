---
description: "Autonomous Continuation: what an armed run does, and what it never does"
---

# Autonomous Continuation

No setting (9.8.0): the person chooses it at the last question before Build, and every other gate is the ordinary
question to the person. `autonomy.enabled` is no longer read. The temper CLI computes every move
of an armed run (`temper next --json`, ADR 0013); this page says what those moves are. The temper
CLI is `${CLAUDE_PLUGIN_ROOT}/scripts/temper`.

**Arming.** Only the person arms a run, at the last question before Build, and only after its check passed: the Plan
question when no Design follows, the Design question when it does (9.8.0), so every decision is made first. The
question offers "Autonomous Build: run Build unattended" next to its ordinary way on, asked like every gate with the
header `Temper gate`. Either answer approves the stage. The unattended part is Build alone (9.8.0): Review, Check and the
commit ask the person as in every run.
"Autonomous" runs `temper state set run_mode autonomous` while the run is still at Plan, then the
plan's own steps. The Intent gate is always a question: no unattended run starts without a person
having accepted the intent.

**What an armed run does by itself** (each is an `auto` action of `temper next`):

- In Build, each passed group's question is answered Continue; "Change" and "Stop" stay the
  person's. A task whose tests already pass because an earlier task built it is taken as done (9.8.0). Each group's gate still runs, and its panel still prints.
- After a passed Build, it goes on to Review and turns the run back to interactive (`temper state set run_mode
  interactive`). From there every gate is the person's question, a failed Review or Check included.
- It parks when Build fails, when a group fails its check, and when a group parks (a task failed on Haiku, its retry
  and the Sonnet escalation, or made a commit the CLI did not). Build never loops back to Plan by itself.

**A park** runs `temper park`: the run turns interactive again, `.temper/autonomy-report.md` gets
the verdict (`SHIP-PENDING-COMMIT` or `PARKED-NEEDS-DECISION`), where it parked, why, the branch
and the report, ending with "The run waits for you at the gate it parked at." The next `temper
next` asks that gate's question; the person never has to type to go on.

**What it never does.** It never pushes, never merges to a remote, never plans again by itself, and
never makes the final feature commit: the commit is the person's question, as in every run. The only commits
an armed run makes are the CLI's own local ones in Build: a task's declared files on its task
branch, their merge into the group branch (`temper task gate`), and the merge of the groups into
the feature branch (`temper integrate`). The commit gate also checks, for a run whose Build ran unattended (the CLI
records `ran_unattended` when the person arms it), that
every changed file is one the plan declared (`autonomy.max-blast-radius` bounds each group's
declared files at the plan gate) and that no changed file matches `autonomy.park-on-touch`. Changed
means what changed since `base_sha` (Build's merges included) and what is still uncommitted.

**The person is not watching.** Claude does not ask "Shall I...?" in an armed run: the only stop
is a park.
