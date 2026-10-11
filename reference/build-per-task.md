---
description: "The per-task Build loop (build.mode: per-task), run by the orchestrator"
---

# Build: the per-task loop (the previous Build)

Read by the orchestrator that runs Build (`/temper` Stage 2 and `/temper:build`) only when
`${CLAUDE_PLUGIN_ROOT}/scripts/temper config get build.mode` prints `per-task`. With the key
absent, Build runs in groups (`${CLAUDE_PLUGIN_ROOT}/reference/build-groups.md`). A stage
subprocess never reads this file. On this page the CLAUDE_PLUGIN_ROOT variable means the folder
that holds the temper CLI: write that folder out in full in every command you run.

This is the Build Temper ran before 9.7.0: one task per launch on the build model (`temper
model build`, Sonnet by default), with the full build brief and a human gate after every task.
Plan writes the flat `tasks.md` layout for it, the grouped CLI commands are off, and no task
runs on Haiku.

1. Before the first Build launch, record the diff baseline:
   `${CLAUDE_PLUGIN_ROOT}/scripts/temper state set base_sha "$(git rev-parse HEAD)"`. Checkpoint
   commits land during Build, so every later reader of "changed files" diffs against this sha,
   not HEAD.
2. Loop from the **next unchecked `- [ ]` task in `tasks.md`** (disk is the source of truth for
   resume: an interrupted run picks up exactly where tasks.md says). Launch:

   ```
   Use the Agent tool, model: {build}, prompt:
   "Follow ${CLAUDE_PLUGIN_ROOT}/agents/build.md exactly. Spec: {spec_path from state}.
   Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with /scripts/temper taken off); wherever the brief or a reference page writes the CLAUDE_PLUGIN_ROOT variable, use this folder.
   Checkpoint: task {N}.
   {One "Checkpoint feedback #{K}: {text}" line per pending feedback item.}
   {If a review-context.json or check-context.json feedback file exists, name it here.}"
   ```
3. Print the returned panel verbatim, then record the launch's usage once:
   `${CLAUDE_PLUGIN_ROOT}/scripts/temper usage add --stage build --model {build} --tokens {subagent tokens} --ms {duration ms}`.
4. Gate with `AskUserQuestion`:
   - **"Continue (Recommended)"**: on a non-last task, go to step 2 for the next task. On the
     last task, this becomes the completion gate below.
   - **"Change"**: never approval. Record
     `${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence add --stage build --phase feedback --claim "feedback #{K}: {text}"`
     for each item the user typed, then relaunch **the same task** with the feedback lines
     added to its prompt.
   - **"Stop"**: run `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate build`, then save for later.
5. **Completion gate** (on the last task's Continue): `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate build`
   (RED-then-GREEN evidence recorded, no unchecked tasks, all feedback answered). Options (four
   max; Override and corrections arrive via "Other"): Continue to Review / Teach Me / "Loop
   back to Plan" (only if Build judges the plan infeasible: human-driven, no circuit breaker,
   max 1 per run) / Save.
6. **Autonomy enabled:** the panel still prints and the per-scenario checkpoint commits still
   happen, but Continue is auto-selected at every checkpoint; Change and Stop stay
   interactive-only. The autonomy blast-radius check in `gate commit` uses `base_sha`-relative
   diffs plus still-uncommitted paths.

A Review or Check loop back to Build relaunches the same brief without a `Checkpoint:` line
(it runs the remaining work) with the line `Feedback re-entry: {reason}. Fix this, then
continue.` and the feedback file named.
