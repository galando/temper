---
description: "The grouped Build loop, run by the orchestrator (/temper Stage 2 and /temper:build)"
---

# Build: the grouped loop

Read by the orchestrator that runs Build: `/temper` (Stage 2) and the standalone
`/temper:build`. A stage subprocess never reads this file. The temper CLI is
`${CLAUDE_PLUGIN_ROOT}/scripts/temper`; every other path here is in the user's project.
On this page the CLAUDE_PLUGIN_ROOT variable means the folder that holds the temper CLI:
write that folder out in full in every command you run.

Grouped Build is the default (see `build.mode` for the way back). Plan wrote `tasks.md` as groups of small tasks; each task is
one launch of a slim task agent (`claude-haiku-5-5` by default) in its own git worktree, each
group's branch takes the merges of its passed tasks, and the human gate is once per group. The loop holds no rules of its own:
every decision is a CLI output, so relay it. It needs the run state (`temper state init`,
which `/temper` does at its start).

1. **Baseline.** Before the first launch:
   `${CLAUDE_PLUGIN_ROOT}/scripts/temper state set base_sha "$(git rev-parse HEAD)"`.
   Commits land during Build, so every later reader of "changed files" diffs against this sha.
2. **Start groups.** For each group in `tasks.md` whose `Depends` groups have passed:
   `${CLAUDE_PLUGIN_ROOT}/scripts/temper group start G<n>` (it makes the group's worktree).
3. **Schedule.** `${CLAUDE_PLUGIN_ROOT}/scripts/temper schedule` prints one JSON line per ready
   task (task, group, title, worktree, model, attempt). Before each launch run
   `${CLAUDE_PLUGIN_ROOT}/scripts/temper task start N`: it gives the task its own worktree (from the
   group branch), which `task show` names to the agent. Launch **every ready task in ONE turn**,
   so they run in parallel, each on the `agent_model` its line prints (the alias the Agent tool
   takes; `model` is the full id). The `temper:temper-build-task` agent type carries only the
   tools a task needs (Read, Edit, Write, Bash, Glob, Grep), which keeps each launch's fixed cost
   down; when that type is not offered, launch the general-purpose agent with the same prompt:

   ```
   Use the Agent tool, subagent_type: temper:temper-build-task, model: {agent_model}, prompt:
   "Follow ${CLAUDE_PLUGIN_ROOT}/agents/build-task.md exactly.
   Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with /scripts/temper taken off); wherever the brief or a reference page writes the CLAUDE_PLUGIN_ROOT variable, use this folder.
   Task: {N}."
   ```
4. **Task gate.** After each task's own agent has returned, and never before (the gate judges that
   agent's work: a gate run while the agent still works finds no green run and spends one of the
   task's attempts):
   `${CLAUDE_PLUGIN_ROOT}/scripts/temper task gate N --model {model} --tokens {subagent tokens} --ms {duration ms}`.
   The CLI refuses a task gate with no `--model`. Task agents are **not** recorded with `usage add`; `task gate --tokens --ms` records them, so
   each launch is counted once. Act on the single `NEXT:` line it prints: `NEXT: schedule` goes
   back to step 3; `NEXT: retry Task N on {model}` and `NEXT: escalate Task N on {model}` go back
   to step 3 (the schedule prints the model); `NEXT: park group G` leaves that group parked
   (other groups go on).
5. **Group gate.** When the schedule prints `{"waiting"...}`, start any group whose dependencies
   have now passed (step 2) and ask the schedule again once another agent has returned. A task it
   lists as `running` still has its agent at work: wait for that agent and gate the task with its
   result (step 4). Only after a resume in a new conversation, where no agent of the earlier one is
   left, gate a task still listed as running with the model its waiting line names, so the gate judges
   the work it left. When every task of group G has passed:
   `${CLAUDE_PLUGIN_ROOT}/scripts/temper group gate G<n>`. A parked group, or a FAIL, goes to the
   user with the CLI's reason; nothing else is decided here.
6. **One human gate per group** (`AskUserQuestion`, with the group's gate output, also with the
   Temper bar: the bar has no group-gate buttons): **"Continue (Recommended)"** (next group) / **"Change"** (never approval:
   record each item the user typed with
   `${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence add --stage build --phase feedback --claim "feedback #{K}: {text}"`,
   then `${CLAUDE_PLUGIN_ROOT}/scripts/temper group reopen G<n> --task N --feedback {K}` for each
   task it concerns, and go back to step 3; only those tasks re-run, `task show` hands them the
   feedback, and their passing gate answers it) / **"Stop"**
   (`${CLAUDE_PLUGIN_ROOT}/scripts/temper gate build`, then save for later).
7. **Integrate.** When the schedule prints `{"done": true, ...}`:
   `${CLAUDE_PLUGIN_ROOT}/scripts/temper integrate`, then `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate build`.
   Show the group-level panel from the CLI output (`temper group report`), not a per-task one.
8. **Completion gate** (`gate build`: RED-then-GREEN evidence, no unchecked tasks, every
   feedback answered, integration PASS). Options (four max; Override and corrections arrive via
   "Other"): Continue to Review / Teach Me / "Loop back to Plan" (only if Build judges the plan
   infeasible: human-driven, no circuit breaker, max 1 per run; `state loop build plan` resets the
   grouped run for the new plan) / Save.
9. **Autonomy enabled:** every group's Continue and the completion gate's Continue are
   auto-selected on PASS; Change and Stop stay interactive-only; a parked group (once no other
   group is ready), or an integrate FAIL, parks the run (see
   `${CLAUDE_PLUGIN_ROOT}/reference/autonomy.md`).

## Fix pass (Review or Check loops back to Build)

A Review or Check FAIL that loops back to Build does not re-run the groups: they are
integrated already. Launch the Build brief once, on the feature branch, as a fix pass:

```
Use the Agent tool, model: {build}, prompt:
"Follow ${CLAUDE_PLUGIN_ROOT}/agents/build.md exactly. Spec: {spec_path from state}.
Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with /scripts/temper taken off); wherever the brief or a reference page writes the CLAUDE_PLUGIN_ROOT variable, use this folder.
Feedback re-entry: {reason}. Fix this, then continue.
{Name the review-context.json or check-context.json feedback file.}"
```

A `DRIFT` section in its panel goes to the person first, as the orchestrator's **Scope drift**
paragraph in Stage 2 says. Record its usage once (`temper usage add --stage build --model {build} ...`), then run
`${CLAUDE_PLUGIN_ROOT}/scripts/temper gate build` and the downstream gate that triggered the loop.
