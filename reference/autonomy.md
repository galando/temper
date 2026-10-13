---
description: "Autonomous Continuation: what an armed run does, and what it never does"
---

# Autonomous Continuation

Opt in: `autonomy.enabled: true` in `.claude/temper.config`. With the block absent or `false` (the
default), every gate is the ordinary question to the person. The temper CLI computes every move
of an armed run (`temper next --json`, ADR 0013); this page says what those moves are. The temper
CLI is `${CLAUDE_PLUGIN_ROOT}/scripts/temper`.

**Arming.** Only the person arms a run, only at the plan gate, and only after the plan check
passed: the Plan question then offers "Stage by stage (Recommended)" and "Autonomous: run the rest
unattended", asked like every gate with the header `Temper gate`. Either answer approves the plan.
"Autonomous" runs `temper state set run_mode autonomous` while the run is still at Plan, then the
plan's own steps. The Intent gate is always a question: no unattended run starts without a person
having accepted the intent.

**What an armed run does by itself** (each is an `auto` action of `temper next`):

- After a passed Design, Build, Review or Check, it goes on to the next stage.
- In Build, each passed group's question is answered Continue; "Change" and "Stop" stay the
  person's. Each group's gate still runs, and its panel still prints.
- After a failed Review or Check, it loops back to Build, within the same loop budget as an
  interactive run (`loops.max-per-type`). Build never loops back to Plan by itself.
- It parks when the budget is spent, when Build fails, when a group fails its check, when a group
  parks (a task failed on Haiku, its retry and the Sonnet escalation, or made a commit the CLI did
  not), and at the commit.

**A park** runs `temper park`: the run turns interactive again, `.temper/autonomy-report.md` gets
the verdict (`SHIP-PENDING-COMMIT` or `PARKED-NEEDS-DECISION`), where it parked, why, the branch
and the report, ending with "The run waits for you at the gate it parked at." The next `temper
next` asks that gate's question; the person never has to type to go on.

**What it never does.** It never pushes, never merges to a remote, never plans again by itself, and
never makes the final feature commit: at the commit it always parks, PASS or FAIL. The only commits
an armed run makes are the CLI's own local ones in Build: a task's declared files on its task
branch, their merge into the group branch (`temper task gate`), and the merge of the groups into
the feature branch (`temper integrate`). The commit gate also checks, for an armed run only, that
every changed file is one the plan declared (`autonomy.max-blast-radius` bounds each group's
declared files at the plan gate) and that no changed file matches `autonomy.park-on-touch`.

**The person is not watching.** Claude does not ask "Shall I...?" in an armed run: the only stop
is a park.
