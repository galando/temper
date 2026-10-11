# Tasks: Grouped Build with Haiku task agents (Temper 9.7.0)

Build order: CLI spine first (every later layer calls it), then the mod, then the
briefs and orchestrator loop that drive the CLI, then docs, then the release stamps.
Every task leaves the repo green: `bash scripts/selftest/test-temper.sh` must end
`FAIL: 0` after each one. This feature itself is built in the ordinary per-task mode.

## Prerequisites

- [x] Read `scripts/temper` (gate_plan, gate_build, gate_commit, cmd_model, _json_append, _unsafe_temper_refuse, state clear/archive)
- [x] Read `scripts/selftest/test-temper.sh` (setup, assert_eq, assert_exit) and the end of `scripts/selftest/temper-cases-4.sh`
- [x] Read `hooks/temper-mod/core/rules.ts` (phaseWriteRule) and `hooks/temper-mod/core/bash.ts` (PROTECTED)
- [x] Read `agents/build.md` and `agents/plan.md` (brief shape: frontmatter, Plugin folder paragraph, Gotchas, panel)

## Tasks

### Task 1: Grouped-mode config keys and task model resolution [SEQUENTIAL]

**Action:** MODIFY / CREATE
**File:** `scripts/temper`, `scripts/selftest/temper-cases-5.sh`, `scripts/selftest/test-temper.sh`
**Traced to:** Scenario: "Grouped mode off keeps the per-task Build unchanged", "Task and escalation models resolve from config with defaults"
**Test:** `scripts/selftest/temper-cases-5.sh` (new fifth case file, sourced after cases-4)
**Validate:** `bash scripts/selftest/test-temper.sh 2>&1 | tail -1`
**Notes:** `_grouped_on` reads `build.mode` (`grouped` on; absent, `per-task` or anything else off). `temper model task` = `build.grouped.task-model` or `claude-haiku-5-5`; `temper model task-escalation` = `build.grouped.escalation-model` or `sonnet`. `model --all` appends `task=`/`task-escalation=` only when grouped is on, so the existing 8-line assertions in cases-1 stay untouched. Keep each case file under ~1200 lines like the other four.
- [x] done

### Task 2: Serialize CLI writes to shared run files [SEQUENTIAL: after Task 1]

**Action:** MODIFY
**File:** `scripts/temper`, `scripts/selftest/temper-cases-5.sh`
**Traced to:** Scenario: "Parallel evidence writes lose no rows"
**Test:** cases-5: 8 background `temper evidence add` calls, then count rows and `json.load` the ledger
**Validate:** `bash scripts/selftest/test-temper.sh 2>&1 | tail -1`
**Notes:** A `mkdir`-based lock (`.temper/.lock`, portable to macOS which has no flock) around `_json_append`, `_json_set_path` and every groups.json write; stale-lock break after 30 s; fail open (write anyway with a WARN) after the timeout so a crashed holder never wedges a run. The lock folder is added to the symlink refusal list.
- [x] done

### Task 3: Grouped tasks.md parser and the grouped plan-gate checks [SEQUENTIAL: after Task 2]

**Action:** MODIFY
**File:** `scripts/temper`, `scripts/selftest/temper-cases-5.sh`
**Traced to:** Scenario: "A three-level grouped plan passes the plan gate", "The plan gate rejects a task with no declared files and a group with no context", "Overlapping files between tasks that can run together are rejected", "A group larger than max-blast-radius is rejected at plan time"
**Test:** cases-5 fixtures: valid two-group plan; missing **File:**; missing **Context:**; overlap with and without Depends; group at and over max-blast-radius; context over 4096 bytes; task block over 1536 bytes; Depends cycle; Depends naming an unknown task
**Validate:** `bash scripts/selftest/test-temper.sh 2>&1 | tail -1`
**Notes:** One embedded python parser (`_grouped_parse`, JSON out) shared by every grouped subcommand: `## Group G<n>: title` headings; group-level `**Depends:**`, `**Validate:**`, `**Interfaces:**` and the `**Context:**` block (until the first `### Task`); `### Task N:` blocks with `**File:**` backticked paths (the same tokens the mod's planfiles.ts reads) and `**Depends:** none | Task N, Task M`. Constants `TASK_BRIEF_MAX_BYTES=6144`, `GROUP_CONTEXT_MAX_BYTES=4096`, `TASK_BLOCK_MAX_BYTES=1536` at the top of the script. The new requirement rows run only when `_grouped_on`; with grouped off gate_plan output is byte-identical.
- [x] done

### Task 4: Grouped run state and the ready set (`temper schedule`) [SEQUENTIAL: after Task 3]

**Action:** MODIFY
**File:** `scripts/temper`, `scripts/selftest/temper-cases-5.sh`
**Traced to:** Scenario: "The ready set holds only tasks with met dependencies and disjoint files", "Grouped mode off keeps the per-task Build unchanged"
**Test:** cases-5: ready set before start, after start (running task's files excluded), after PASS (dependent task appears), max-parallel cap, grouped off exits 1
**Validate:** `bash scripts/selftest/test-temper.sh 2>&1 | tail -1`
**Notes:** `.temper/groups.json` (CLI-owned; added to `_unsafe_temper_refuse`, removed by `state clear`). `temper schedule` prints one JSON line per launchable task: task, group, worktree, project, model, attempt. A task is ready when its Depends tasks passed, its group's Depends groups passed their group gate, its group is not parked, and its files are disjoint from every running task; at most `build.grouped.max-parallel` (default 4) running at once.
- [x] done

### Task 5: Group worktrees (`temper group start`) [SEQUENTIAL: after Task 4]

**Action:** MODIFY
**File:** `scripts/temper`, `scripts/selftest/temper-cases-5.sh`
**Traced to:** Scenario: "Each group gets its own worktree off the feature branch"
**Test:** cases-5 in a throwaway git repo: two worktrees, their branches, base commit = feature HEAD, `.git/info/exclude` line, clean main `git status`; a group depending on G1 starts from G1's branch merged in; a commit the CLI makes in a worktree passes the native pre-commit hook (no run state there, degrade-open)
**Validate:** `bash scripts/selftest/test-temper.sh 2>&1 | tail -1`
**Notes:** Path `.claude/worktrees/temper-{slug}-{G}` (Claude Code's own worktree folder), branch `temper/{slug}/{G}`. Exclude written to the common git dir's `info/exclude` only, never `.gitignore`. Idempotent: a second start of the same group reuses the worktree.
- [x] done

### Task 6: Task lifecycle: start, show, test, gate [SEQUENTIAL: after Task 5]

**Action:** MODIFY
**File:** `scripts/temper`, `scripts/selftest/temper-cases-5.sh`
**Traced to:** Scenario: "A task with its own RED then GREEN and only declared files passes its gate", "A task gate fails without its own RED before GREEN", "An undeclared file change fails the task gate", "The task launch payload stays within its byte budget"
**Test:** cases-5: pass path; green-only; green-before-red; red row of another task; undeclared file; task show size
**Validate:** `bash scripts/selftest/test-temper.sh 2>&1 | tail -1`
**Notes:** `task start N` marks running and snapshots sha256 of every dirty/untracked file in the worktree. `task show N` prints task block + group context + worktree + project paths. `task test N --phase red|green -- <cmd>` runs the command with cwd = worktree and appends a `build` ledger row tagged `task`, `attempt`, `executed_by: cli`. `task gate N` PASSes on RED (nonzero) then GREEN (0) rows for this task and attempt, and changed files (hash differs from snapshot, minus files other running tasks declare) within the declared files; on PASS it ticks the task's `- [ ]` in tasks.md and makes a pathspec commit of the declared paths on the group branch. The verdict goes to groups.json, not gates.json.
- [x] done

### Task 7: Retry, escalation, park and usage recording [SEQUENTIAL: after Task 6]

**Action:** MODIFY
**File:** `scripts/temper`, `scripts/selftest/temper-cases-5.sh`
**Traced to:** Scenario: "A failing task is retried on Haiku, escalated once, then parks its group", "Run state records the numbers the cost comparison needs"
**Test:** cases-5: fail x3 drives retry -> escalate -> park; schedule skips the parked group, still offers G2; attempts carry model, outcome, reason, tokens, ms
**Validate:** `bash scripts/selftest/test-temper.sh 2>&1 | tail -1`
**Notes:** `task gate N --model M --tokens T --ms D` records the attempt. On FAIL the CLI restores the task's declared files to the start snapshot and prints exactly one `NEXT:` line (`retry on {task model}` / `escalate on {escalation model}` / `park group G`). Attempt 3 failing parks the group (D-03); no fourth attempt exists.
- [x] done

### Task 8: Group gate and Change at the group gate [SEQUENTIAL: after Task 7]

**Action:** MODIFY
**File:** `scripts/temper`, `scripts/selftest/temper-cases-5.sh`
**Traced to:** Scenario: "A group gate passes when every task gate passed and the group tests pass", "Change at a group gate reruns only the named tasks"
**Test:** cases-5: PASS path; one task not passed -> FAIL; group Validate exits 1 -> FAIL; `group reopen G1 --task 2` unticks only Task 2, resets its attempts, schedule offers only Task 2
**Validate:** `bash scripts/selftest/test-temper.sh 2>&1 | tail -1`
**Notes:** `temper group gate G` runs the group's **Validate:** command in its worktree through the CLI (recorded as a build row tagged with the group). `temper group reopen G --task N [--task M]` reverts only those tasks' commits' files to the group base for those paths, unticks them, and clears their attempts.
- [x] done

### Task 9: Integration (`temper integrate`) and the build gate's integration requirement [SEQUENTIAL: after Task 8]

**Action:** MODIFY
**File:** `scripts/temper`, `scripts/selftest/temper-cases-5.sh`
**Traced to:** Scenario: "Integration merges every passed group and verifies the result", "A merge conflict stops the run before Review"
**Test:** cases-5: two clean groups merge, suite command runs, Interfaces found, worktrees removed; a conflicting pair aborts with the cause, gate build FAILs on "integration"
**Validate:** `bash scripts/selftest/test-temper.sh 2>&1 | tail -1`
**Notes:** Merges in group dependency order with `git merge --no-ff`; on conflict `git merge --abort`, record `{group, files}` in groups.json, exit 1. Full suite command = tasks.md `**Integration:**` line. Interface check: each `**Interfaces:**` entry is `` `path` — `literal` ``, verified with a fixed-string search. gate_build gains an "integration" row only when grouped is on.
- [x] done

### Task 10: Grouped meaning of max-blast-radius at the commit gate [SEQUENTIAL: after Task 9]

**Action:** MODIFY
**File:** `scripts/temper`, `scripts/selftest/temper-cases-5.sh`
**Traced to:** Scenario: "Autonomy commit gate in grouped mode compares changes to the declared union"
**Test:** cases-5: autonomous + grouped, 40 declared changes PASS; one undeclared FAIL names it; autonomous + per-task keeps the count rule (existing cases)
**Validate:** `bash scripts/selftest/test-temper.sh 2>&1 | tail -1`
**Notes:** Only the "blast radius" row changes, and only when `_grouped_on`; spec-folder paths count as declared. park-on-touch is unchanged.
- [x] done

### Task 11: Measurement report and ledger archive [SEQUENTIAL: after Task 10]

**Action:** MODIFY
**File:** `scripts/temper`, `scripts/selftest/temper-cases-5.sh`
**Traced to:** Scenario: "Run state records the numbers the cost comparison needs"
**Test:** cases-5: `group report --json` totals, open review findings count, `state archive` writes a `grouped` block into gate-ledger.json
**Validate:** `bash scripts/selftest/test-temper.sh 2>&1 | tail -1`
**Notes:** Report fields: tokens per model, attempts per task, escalations, parked groups, wall time per group (first start to group gate PASS), total Build wall time, open Review findings (review ledger). Update the CLI header comment and `--help` usage for schedule, task, group, integrate.
- [x] done

### Task 12: Mod: guard groups.json and map group-worktree writes [SEQUENTIAL: after Task 4]

**Action:** MODIFY / CREATE
**File:** `hooks/temper-mod/core/bash.ts`, `hooks/temper-mod/core/rules.ts`, `tests/mod/worktree.test.ts`
**Traced to:** Scenario: "The mod allows a planned write in a group worktree and refuses an unplanned one"
**Test:** `tests/mod/worktree.test.ts`
**Validate:** `claude plugin test . && npx -p typescript@5.6 tsc -p tsconfig.mod.json && bash scripts/check-mod-calls.sh`
**Notes:** PROTECTED gains `['state', /(^|\/)\.temper\/groups\.json$/i]`. In phaseWriteRule (build/fix), a path under `.claude/worktrees/temper-{run slug}-G{n}/` is judged by its worktree-relative path with the same rule (spec, test file, plan files, added paths); any other worktree prefix gets no special treatment. Pure rule change: no new `$` call, so check-mod-calls.sh stays as is unless it reports one.
**Feedback (orchestrator, after task 6 feedback #1):** since `task test` now runs the declared `**Test:**` command from tasks.md, a task agent that edits the run's tasks.md could swap its own Test command. While a grouped Build run is active (groups.json present), the mod refuses agent writes to the run's `.temper/specs/{slug}/tasks.md` (the CLI ticks boxes itself); add a worktree.test.ts case for it. Per-task mode keeps today's allowance.
**Feedback (orchestrator, after task 11 feedback #2):** PROTECTED also gains `.temper/usage.json` (CLI-only, like groups.json), with a worktree.test.ts case.
- [x] done

### Task 13: The slim task brief [SEQUENTIAL: after Task 11]

**Action:** CREATE / MODIFY
**File:** `agents/build-task.md`, `.claude-plugin/plugin.json`, `scripts/temper`, `scripts/selftest/temper-cases-5.sh`
**Traced to:** Scenario: "The task launch payload stays within its byte budget", "Grouped logic stays in the briefs and the CLI"
**Test:** cases-5 asserts `wc -c < agents/build-task.md` <= the CLI's TASK_BRIEF_MAX_BYTES (read from the script, one source)
**Validate:** `bash scripts/selftest/test-temper.sh 2>&1 | tail -1 && bash scripts/validate-plugin.sh && python3 scripts/validate-panels.py`
**Notes:** Frontmatter `name: temper-build-task`, `model: claude-haiku-5-5`. Body: the Plugin folder paragraph; steps (run `temper task show N` from the project folder; edit only declared files under the worktree path; `temper task test N --phase red` then green; never commit, never edit tasks.md, never run `task gate`); **Gotchas**; the one closed panel (TASK, CHANGED, BLOCKERS). No pack rules: Plan distils the relevant ones into the group context. `temper model task` reads this frontmatter as the default.
- [x] done

### Task 14: Plan brief, plan reference and templates for grouped output [SEQUENTIAL: after Task 3]

**Action:** MODIFY
**File:** `agents/plan.md`, `reference/plan.md`, `templates/tasks.md`, `templates/temper.config.default`
**Traced to:** Scenario: "A three-level grouped plan passes the plan gate", "Task and escalation models resolve from config with defaults"
**Test:** a cases-5 case runs `temper gate plan` on the grouped example from templates/tasks.md copied into a fixture (the template must pass the gate)
**Validate:** `bash scripts/selftest/test-temper.sh 2>&1 | tail -1 && bash scripts/quality-check.sh`
**Notes:** agents/plan.md gains one step: when `temper config get build.mode` prints `grouped`, write tasks.md in the grouped format of reference/plan.md, "Grouped tasks". reference/plan.md documents the format, the budgets, distilling pack rules into Context, splitting a group over max-blast-radius, and Interfaces/Integration lines. temper.config.default gains a commented `build:` block (mode, grouped.task-model, escalation-model, max-parallel).
- [x] done

### Task 15: Orchestrator launch loop, autonomy and state schema [SEQUENTIAL: after Task 13]

**Action:** MODIFY
**File:** `commands/temper.md`, `reference/autonomy.md`, `reference/orchestrator-patterns.md`
**Traced to:** Scenario: "Grouped logic stays in the briefs and the CLI", "The orchestrator launches every task agent in a real grouped run"
**Test:** manual diff review: commands/temper.md Stage 2 gains only a "Grouped mode" loop (group start, schedule, parallel Agent launches with the printed model, task gate with usage, NEXT handling, group gate + AskUserQuestion Continue / Change / Stop, integrate)
**Validate:** `bash scripts/quality-check.sh && bash scripts/validate-docs.sh`
**Notes:** Every rule the loop needs is a CLI output (`NEXT:` lines, ready JSON), so the prose only relays it. autonomy.md: groups auto-continue, Change and Stop stay interactive, a parked group parks the run, D-01 meaning of max-blast-radius. orchestrator-patterns.md: groups.json in the state schema.
**Feedback (orchestrator, intent D-07):** every stage launch in commands/temper.md (Intent, Plan, Design, per-task Build checkpoint, Review, Check) and in commands/fix.md's RCA/Fix launches is followed by one `temper usage add --stage {stage} --model {model} --tokens {subagent tokens} --ms {duration}` call with the numbers the Agent result reports; grouped task launches pass them through `task gate --tokens --ms` as already designed (counted once). Add the usage file to orchestrator-patterns.md's state schema. Also add `**File:**` entry `commands/fix.md` for this.
- [x] done

### Task 16: User docs, measurement procedure and decision record [SEQUENTIAL: after Task 15]

**Action:** CREATE / MODIFY
**File:** `docs/grouped-build.md`, `docs/decisions/0011-grouped-build.md`, `docs/getting-started.md`
**Traced to:** Scenario: "Run state records the numbers the cost comparison needs"
**Test:** `bash scripts/validate-docs.sh`
**Validate:** `bash scripts/validate-docs.sh && bash scripts/validate-directory.sh`
**Notes:** docs/grouped-build.md: how to switch it on, what a run looks like, and the AC-12 procedure (same feature, two branches, per-task then grouped, collect `temper group report --json`, `temper report --json` and the review findings, compare tokens per model x price, wall time, findings). ADR 0011 records D-01..D-06 and the Approach Decisions of plan.md.
**Feedback (orchestrator):** the user docs list the new run state files (`.temper/groups.json`, `.temper/usage.json`, `.temper/.lock/`) wherever they list the other `.temper/` runtime files a project should not commit; this repo's .gitignore already has them (8e4a41a).
- [x] done

### Task 17: Version bump to 9.7.0 [SEQUENTIAL: after Task 16]

**Action:** MODIFY
**File:** `.claude-plugin/plugin.json`, `README.md`, `docs/index.html`, `.claude/CLAUDE.md`, `CHANGELOG.md`
**Traced to:** Scenario: "The release reads 9.7.0 everywhere"
**Test:** grep for the old version
**Validate:** `bash scripts/version-bump.sh 9.7.0 && ! grep -rn --exclude-dir=.git --exclude-dir=.temper --exclude=CHANGELOG.md --exclude=directory-submission.md '9\.6\.7' . && bash scripts/validate-directory.sh`
**Notes:** version-bump.sh rewrites plugin.json, .claude/CLAUDE.md, README badge, docs/index.html and inserts the CHANGELOG skeleton. docs/directory-submission.md names 9.6.6/9.6.7 as release history (which version removed the icon); those lines stay.
- [x] done

### Task 18: CHANGELOG 9.7.0 entry [SEQUENTIAL: after Task 17]

**Action:** MODIFY
**File:** `CHANGELOG.md`
**Traced to:** Scenario: "The release reads 9.7.0 everywhere"
**Test:** quality-check "Version match" row
**Validate:** `head -12 CHANGELOG.md && bash scripts/quality-check.sh`
**Notes:** Replace the skeleton with `## v9.7.0: grouped Build with small Haiku task agents (opt-in, experimental)` and a body: what grouped mode is, the config keys, the new CLI subcommands, the mod change, the budgets, D-01 meaning of max-blast-radius, and that the cost comparison is a follow-up (D-04).
- [x] done

### Task 19: Full validation sweep [SEQUENTIAL: after Task 18]

**Action:** VERIFY
**File:** none (runs every suite)
**Traced to:** Infrastructure: required by the release (AC-14, AC-15)
**Test:** all suites
**Validate:** `bash scripts/selftest/test-temper.sh && bash scripts/quality-check.sh && bash scripts/validate-directory.sh && claude plugin test . && npx -p typescript@5.6 tsc -p tsconfig.mod.json && bash scripts/check-mod-calls.sh`
**Notes:** Any failure goes back to the task that owns the file.
- [x] done

### Task 20: One real grouped run (manual) [SEQUENTIAL: after Task 19]

**Action:** VERIFY
**File:** none (a scratch project outside this repo)
**Traced to:** Scenario: "The orchestrator launches every task agent in a real grouped run"
**Test:** manual, recorded with `temper evidence add --stage build --claim "manual grouped run" --label HEURISTIC`
**Validate:** `scripts/temper group report --json` in the scratch project shows every task's attempts and models
**Notes:** Run once interactive (one gate per group seen) and once with autonomy armed (groups auto-continue, run parks before commit), with `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` to prove AC-13.
- [x] done
