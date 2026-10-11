# Intent: Grouped Build with Haiku task agents (Temper 9.7.0)

**Author:** Claude <noreply@anthropic.com>
**Status:** completed
**Completed:** 2026-10-11
**Accepted-by:** galando <galando@gmail.com>
**Created:** 2026-10-10
**Reviewer:** galando <galando@gmail.com>
**Complexity:** complex

---

## Intent (IDD)

### Problem

Who: teams running `/temper` on medium and complex features, and the Temper
maintainers who pay for every Build launch.

Current: Build runs one task at a time, each launch on the session model with the
full build context (agents/build.md + reference/build.md + pack rules, about 64 KB
per launch as stated in the request), and a human gate after every task. A feature
with 12 tasks means 12 heavy launches and 12 human gates, run strictly in sequence.

Desired: Intent and Plan stay on Opus. Plan splits the Build into GROUPS (related
work in one area, the human review unit) and each group into many SMALL TASKS. Each
task is one launch of a small Haiku agent with a slim brief plus a group context
file Opus wrote once at plan time. The CLI decides which tasks are ready, which run
in parallel, and whether each task and group passes. Example: a 12-task feature in
3 groups of 4 becomes 12 Haiku launches of a few KB each, independent tasks and
groups running in parallel, and 3 human gates instead of 12.

Why it matters: lower cost and wall time per feature, fewer human interruptions,
and fewer seam bugs because every task in a group reads the same shared interfaces.

Facts (stated in the request): the ~64 KB per launch figure; the per-task human gate
today; `autonomy.max-blast-radius` defaults to 15 in `.claude/temper.config`;
current version is 9.6.7.
Assumptions (not yet measured): Haiku with a slim brief and a group context file
produces code that passes the same gates at an acceptable retry rate; the
cost/time saving outweighs retries, escalations and the integration step.

### Success Criteria

- [ ] AC-01 [required]: Grouped mode is opt-in through a key in `.claude/temper.config`; with the key absent or off, Build runs the existing per-task mode with no behavior change. (source: launch prompt req 9)
  Why: existing users and CI keep today's behavior; a new mode is adopted on purpose, not by upgrade.
  Validate: code — test-temper.sh case for absent/off/on config; full existing selftest passes unchanged.
- [ ] AC-02 [required]: In grouped mode Plan writes a three-level plan (feature -> groups -> tasks); every task declares its files and its dependencies, and Plan writes one group context per group (shared files, interfaces, conventions) as a `**Context:**` block under that group's heading in tasks.md, which `temper task show` hands to each task agent. (source: launch prompt req 1, 4; refined by Plan, D-06)
  Why: the CLI can only schedule and gate what the plan declares, and the group context file is what keeps Haiku tasks consistent at the seams.
  Validate: code — `temper gate plan` FAILs a grouped plan with a task missing declared files or a group missing its context file.
- [ ] AC-03 [required]: The CLI (`scripts/temper`), not a prompt, validates that declared file ownership does not overlap between tasks that can run at the same time, and returns the set of tasks ready to run now (dependencies met, files disjoint from running tasks). (source: launch prompt req 2, 3)
  Why: scheduling decided by a model is non-deterministic; overlapping writes from parallel agents corrupt each other's work.
  Validate: code — test-temper.sh cases for overlap rejection, dependency ordering, and the ready-task output.
- [ ] AC-04 [required]: Inside a group, dependent tasks run in order and independent tasks with disjoint declared files run in parallel; separate groups run in parallel, each in its own git worktree. (source: launch prompt req 2)
  Why: parallelism is where the wall-time saving comes from; worktrees keep parallel groups from editing one checkout.
  Validate: code — test-temper.sh case for worktree setup and ready-set per group; manual — one real grouped run.
- [ ] AC-05 [required]: Each task launches a new slim Haiku task agent (listed in `.claude-plugin/plugin.json`) whose brief stays within 6144 bytes, its group context within 4096 bytes and its task block within 1536 bytes (Decision D-06), instead of loading the full build brief, reference/build.md and pack rules. (source: launch prompt req 4; budget set by Plan, D-06)
  Why: per-launch context is the cost driver; a Haiku launch carrying 64 KB of context loses most of the saving.
  Validate: code — a selftest asserts the task brief size stays under its budget, and `temper gate plan` FAILs a group context or task block over its budget.
- [ ] AC-06 [required]: The task model defaults to `claude-haiku-5-5` and is configurable in `.claude/temper.config`, as is the escalation model. (source: launch prompt)
  Why: model ids change; teams pick their own cost/quality trade-off.
  Validate: code — test-temper.sh case reading the default and an override.
- [ ] AC-07 [required]: A per-task gate in the CLI passes only when that task has its own RED then GREEN evidence and only its declared files changed. (source: launch prompt req 5)
  Why: a cheap model gets a strict, deterministic check; an undeclared file change is the seam bug this mode exists to prevent.
  Validate: code — test-temper.sh cases for missing RED, GREEN before RED, and an undeclared file change.
- [ ] AC-08 [required]: On a task gate failure the task is retried once on Haiku, then escalated once to Sonnet; each attempt, its model and its outcome are recorded in run state. (source: launch prompt req 5)
  Why: bounded recovery without a human; the recorded attempts feed the cost comparison in AC-12.
  Validate: code — test-temper.sh case driving fail -> retry -> escalate -> state record.
- [ ] AC-09 [required]: A per-group gate passes only when every task gate in the group passes and the group's tests pass; then ONE human gate per group (Continue / Change / Stop) replaces the per-task human gate, or the run auto-continues in autonomy mode. (source: launch prompt req 6)
  Why: the group is the reviewable unit; per-task human gates are the interruption cost this mode removes.
  Validate: code — test-temper.sh case for the group gate verdict; manual — one interactive and one autonomy run.
- [ ] AC-10 [required]: After all groups pass, an integration step merges the worktrees, runs the full test suite and an interface check, then Review and Check run as today; a merge conflict or failure stops the run before Review with the cause recorded. (source: launch prompt req 7)
  Why: parallel groups only pay off if they land as one consistent change, verified before Review.
  Validate: code — test-temper.sh case for the integration gate verdict, including a conflict.
- [ ] AC-11 [required]: `autonomy.max-blast-radius` (default 15) has a defined, tested meaning in grouped mode that does not park every multi-group feature by default (rule in Decisions D-01). (source: launch prompt req 8)
  Why: grouped mode targets features larger than a single task; a limit that always parks them makes autonomy useless for this mode.
  Validate: code — test-temper.sh cases at, under and over the limit in grouped mode.
- [ ] AC-12 [required]: A documented, repeatable way to measure cost (tokens per model), wall time and Review findings for grouped mode against the per-task Build on the same feature, with the run state recording the numbers it needs. (source: launch prompt req 10)
  Why: the saving is an assumption today; the release needs evidence to decide whether grouped mode becomes recommended.
  Validate: code — the run state records tokens per model, wall time and Review findings, and a documented procedure exists; the real comparison run is a follow-up after 9.7.0 (Decision D-04).
- [ ] AC-13 [required]: Grouped mode works when subagents cannot launch subagents: the orchestrator launches every Haiku agent itself and the CLI decides the order. (source: launch prompt open question)
  Why: the design cannot rest on an unconfirmed platform capability.
  Validate: manual — one grouped run with orchestrator-launched task agents.
- [ ] AC-14 [required]: Per-stage logic for grouped mode lives in its brief under `agents/` and gate mechanics in `scripts/temper`; `commands/temper.md` gains no more than the launch loop. Refined during Review (L5): it also gains one `temper usage add` line per stage launch (D-07) and the narrowed autonomy invariant text (design Resolution 1); neither holds a gate rule. (source: .claude/CLAUDE.md)
  Why: the repo's known-mistakes list; logic in the orchestrator file leaks into clean-context stages.
  Validate: code — review of the diff to `commands/temper.md`; `bash scripts/quality-check.sh` passes.
- [ ] AC-15 [required]: The plugin version reads 9.7.0 everywhere it appears (plugin.json, README, CHANGELOG, docs, .claude/CLAUDE.md) and CHANGELOG.md has a 9.7.0 entry describing grouped mode. (source: launch prompt)
  Why: a release with mixed version strings breaks directory listing and confuses users.
  Validate: code — no 9.6.7 left outside CHANGELOG history; selftest, quality-check, validate-directory, `claude plugin test .` all pass.

### Constraints

- Gate mechanics (scheduling, ownership overlap, task/group/integration gates) live in `scripts/temper`, each with a `test-temper.sh` case, never in a prompt. (source: .claude/CLAUDE.md, launch prompt)
- Hooks fail open except their one detected-violation path. (source: .claude/CLAUDE.md)
- Per-stage logic belongs in that stage's brief in `agents/`; `commands/temper.md` carries only the launch loop. (source: .claude/CLAUDE.md, launch prompt)
- New agents are listed in `.claude-plugin/plugin.json`. (source: .claude/CLAUDE.md)
- Intent and Plan stay on Opus. (source: launch prompt)
- Autonomy invariants stay hardcoded: never commits, pushes, merges to a remote branch, or re-plans unattended. (source: .claude/temper.config autonomy comment)
- README and manifest changes pass `bash scripts/validate-directory.sh`. (source: .claude/CLAUDE.md)

### Scope and Non-goals

- In scope: grouped Plan output and validation; CLI scheduling, ownership check, task/group/integration gates; slim Haiku task agent and group context file; retry/escalation; worktree per group and integration merge; config keys; max-blast-radius semantics for this mode; measurement procedure; version 9.7.0 and CHANGELOG.
- Out of scope: changing the per-task Build mode; moving Intent, Plan, Design, Review or Check to other models; making grouped mode the default; remote push or merge of worktree branches.
- Must keep working: per-task Build as the default; existing gates and their selftest cases; autonomy mode with grouped mode off; the commit gate hooks.

### Target Users

- Feature developer running `/temper`: approves the grouped plan, then reviews each group at its gate (Continue / Change / Stop) → the next group runs or the change is re-planned for that group.
- Developer running autonomy mode: arms autonomy at the plan gate → groups auto-continue and the run parks before commit for one final review.
- Temper maintainer: runs the AC-12 comparison on a real feature → decides whether grouped mode is recommended, tuned, or kept experimental in the next release.

### Open Questions

### Decisions

- D-01 (max-blast-radius in grouped mode): Plan rejects any single group whose declared files exceed `autonomy.max-blast-radius` (Plan splits it), and the commit gate parks when files changed outside the union of declared files, instead of comparing the feature total to the limit. (source: user at intent gate, 2026-10-10)
- D-02 (Change at a group gate): feedback is recorded and only the tasks it concerns re-run on the task model, with the usual retry and escalation; re-planning stays a separate, explicit "Loop back to Plan" choice. (source: user at intent gate, 2026-10-10)
- D-03 (end of the retry chain): when a task fails on Haiku, its Haiku retry and the Sonnet escalation, its group stops and the run parks for a human, with every attempt recorded; independent groups may finish first. (source: user at intent gate, 2026-10-10)
- D-04 (AC-12): the comparison run is a follow-up, not a 9.7.0 release blocker; 9.7.0 ships grouped mode opt-in and experimental, with the measurement recording and procedure built in. (source: user at intent gate, 2026-10-10)
- D-05 (nested subagents, was a Deferred question): current Claude Code docs say a subagent can spawn subagents up to three layers below the main conversation by default, and `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` turns nesting off. The design still has the orchestrator launch every task agent, with the CLI choosing the order: nesting can be switched off by the user, a group agent would hold a growing context, and the built-in `isolation: worktree` branches from the default branch and blocks Bash in the main checkout, where the task agent must run the temper CLI. (source: Plan stage, code.claude.com/docs/en/sub-agents read 2026-10-10)
- D-06 (size budgets, was a Deferred question): task brief <= 6144 bytes, group context <= 4096 bytes, task block <= 1536 bytes, so one launch carries at most about 11.5 KB instead of about 64 KB. The group context lives in tasks.md under its group heading (not a separate file), because the spec folder holds exactly intent.md, tasks.md and plan.md and `temper gate plan` reads only those. The budgets are constants in `scripts/temper`, tuned after the AC-12 comparison. (source: Plan stage, 2026-10-10)
- D-07 (whole-flow usage, added during Build): 9.7.0 also records usage for every agent launch in every stage and in both Build modes, through a general `temper usage add --stage S --model M --tokens T --ms D`; `temper report` shows tokens and time per stage, per model and in total, and `state archive` keeps them in gate-ledger.json. This gives AC-12 a per-task Build baseline. Numbers are the per-agent totals Claude Code returns (not split into input/output/cache); the orchestrator session's own usage is not visible and is not recorded. (source: user during Build, 2026-10-10)
- D-08 (agent-made commits, decided after eight review rounds of automatic undo kept finding invariant breaks): when a task's range holds a commit the CLI did not record, the CLI does not repair it. The task FAILs, its group parks at once (no retry, a deliberate exception to D-03: it is a rule violation, not a test failure), the branch and working tree are left untouched, and the message names the commit(s) and files. A human resolves it; `group reopen` is accepted only when the parked commits are no longer ancestors of the group branch HEAD, or when the human acknowledges them with an explicit flag that is recorded like an override and shown in the report. While a group is parked, its running siblings' task gates are refused without a verdict or restore, so their work stays. The group gate also verifies every passed task's recorded commit is an ancestor of the group HEAD. Stopping rule adopted for this release: fix what can give a wrong result in a normal run or weaken a gate; detect and stop agent misbehaviour rather than repair it; document rare or contrived cases as known limits. (source: user, 2026-10-11)

---

## Scenarios (BDD)

#### Happy Path

```gherkin
Scenario: Grouped mode off keeps the per-task Build unchanged
  Given .claude/temper.config has no build.mode key, and a second project sets build.mode: per-task
  When temper model --all, temper gate plan and temper schedule run in each project
  Then model --all prints exactly the 8 existing stage lines, gate plan applies no grouped check
  And temper schedule exits 1 with "grouped mode is off (build.mode)" and writes nothing
  And bash scripts/selftest/test-temper.sh passes every pre-existing case unchanged
  Note: unit
  Covers: AC-01
```

```gherkin
Scenario: Task and escalation models resolve from config with defaults
  Given build.mode: grouped and no build.grouped model keys
  When temper model task and temper model task-escalation run
  Then they print claude-haiku-5-5 and sonnet
  And with build.grouped.task-model: haiku and build.grouped.escalation-model: opus they print haiku and opus
  And temper model --all adds task= and task-escalation= lines only in grouped mode
  Note: unit
  Covers: AC-06, AC-01
```

```gherkin
Scenario: A three-level grouped plan passes the plan gate
  Given build.mode: grouped and a tasks.md with "## Group G1: cli" and "## Group G2: docs"
  And each group has a non-empty **Context:** block under 4096 bytes
  And every "### Task N:" has a **File:** line with at least one path and a **Depends:** line
  When temper gate plan runs
  Then it prints PASS with a "grouped plan" requirement naming 2 groups and their task counts
  Note: unit
  Covers: AC-02
```

```gherkin
Scenario: The ready set holds only tasks with met dependencies and disjoint files
  Given group G1 with Task 1 (scripts/a.sh), Task 2 (scripts/b.sh, Depends: Task 1), Task 3 (docs/c.md)
  And group G2 with Task 4 (README.md), and build.grouped.max-parallel: 4
  When temper schedule runs before any task started
  Then it prints JSON lines for Task 1, Task 3 and Task 4 with group, worktree, model claude-haiku-5-5 and attempt 1
  And after temper task start 1 and a PASS of temper task gate 1, temper schedule prints Task 2
  Note: unit
  Covers: AC-03, AC-04
```

```gherkin
Scenario: Each group gets its own worktree off the feature branch
  Given an approved grouped plan on branch feature/demo with groups G1 and G2
  When temper group start G1 and temper group start G2 run
  Then git worktree list shows .claude/worktrees/temper-demo-G1 and temper-demo-G2 on branches temper/demo/G1 and temper/demo/G2
  And both branch from the feature branch HEAD, and .git/info/exclude lists .claude/worktrees/
  And git status in the main checkout shows no new untracked path
  Note: integration
  Covers: AC-04
```

```gherkin
Scenario: A task with its own RED then GREEN and only declared files passes its gate
  Given Task 1 declares scripts/a.sh and tests/a_test.sh and was started with temper task start 1
  When temper task test 1 --phase red -- bash tests/a_test.sh exits 1, the agent edits scripts/a.sh
  And temper task test 1 --phase green -- bash tests/a_test.sh exits 0
  Then temper task gate 1 prints PASS, ticks Task 1's box in tasks.md
  And commits only the declared paths on the group branch
  Note: unit
  Covers: AC-07
```

```gherkin
Scenario: The task launch payload stays within its byte budget
  Given agents/build-task.md and a grouped tasks.md whose group context is 4000 bytes
  When the selftest measures agents/build-task.md and temper task show 1 runs
  Then agents/build-task.md is at most 6144 bytes
  And task show prints the task block, the group context, the worktree path and the project path in under 6000 bytes
  Note: unit
  Covers: AC-05
```

```gherkin
Scenario: A group gate passes when every task passed and the group tests pass
  Given every task of G1 has a PASS task gate and G1 declares **Validate:** `bash tests/run.sh`
  When temper group gate G1 runs
  Then the CLI runs bash tests/run.sh inside the G1 worktree, records exit 0, and prints PASS
  And the orchestrator shows one Continue / Change / Stop question for G1, or auto-continues with run_mode autonomous
  Note: unit
  Covers: AC-09
```

```gherkin
Scenario: Integration merges every passed group and verifies the result
  Given groups G1 and G2 both have PASS group gates and disjoint files
  When temper integrate runs on feature/demo
  Then both group branches are merged with --no-ff, the full test command exits 0
  And every **Interfaces:** line of each group context is still found in its file
  And temper gate build adds an "integration" requirement that PASSes and the worktrees are removed
  Note: integration
  Covers: AC-10
```

```gherkin
Scenario: Run state records the numbers the cost comparison needs
  Given Task 1 ran twice on claude-haiku-5-5 (2100 and 1900 tokens) and once on sonnet (5200 tokens)
  When temper task gate records each attempt with --model, --tokens and --ms, and temper group report --json runs
  Then the report gives tokens per model {claude-haiku-5-5: 4000, sonnet: 5200}, attempts per task, wall time per group
  And the count of open Review findings, and temper state archive copies the same block into gate-ledger.json
  Note: unit
  Covers: AC-12
```

```gherkin
Scenario: The orchestrator launches every task agent in a real grouped run
  Given a scratch project with build.mode: grouped and a two-group plan
  When /temper runs through Build with nesting switched off (CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1)
  Then every task agent is launched by the main conversation on the model temper schedule printed
  And independent tasks run in the same turn, the run shows one gate per group, and Review starts after integration
  Note: manual
  Covers: AC-13, AC-04, AC-09
```

```gherkin
Scenario: The release reads 9.7.0 everywhere
  Given the version bump has run
  When grep searches the repo for 9.6.7 outside CHANGELOG.md and docs history lines
  Then nothing is found, plugin.json, README badge, docs/index.html and .claude/CLAUDE.md read 9.7.0
  And CHANGELOG.md starts with a "## v9.7.0" entry that names grouped mode, and quality-check reports the version match
  Note: unit
  Covers: AC-15
```

```gherkin
Scenario: Grouped logic stays in the briefs and the CLI
  Given the finished diff
  When git diff of commands/temper.md is read and bash scripts/quality-check.sh runs
  Then commands/temper.md gains only a grouped launch loop that calls temper schedule, task gate, group gate and integrate
  And no gate rule appears in a prompt, and quality-check passes with agents/build-task.md listed in plugin.json
  Note: manual
  Covers: AC-14, AC-05
```

#### Error Paths

```gherkin
Scenario: The plan gate rejects a task with no declared files and a group with no context
  Given build.mode: grouped, Task 2 has no **File:** line and group G2 has no **Context:** block
  When temper gate plan runs
  Then it prints FAIL naming "Task 2: no declared files" and "G2: no group context"
  Note: unit
  Covers: AC-02
```

```gherkin
Scenario: Overlapping files between tasks that can run together are rejected
  Given Task 1 and Task 3 both declare scripts/a.sh and neither depends on the other
  When temper gate plan runs
  Then it prints FAIL "file ownership overlap: scripts/a.sh in Task 1 and Task 3"
  And when the plan adds Depends: Task 1 to Task 3, the gate passes
  Note: unit
  Covers: AC-03
```

```gherkin
Scenario: A task gate fails without its own RED before GREEN
  Given Task 1 recorded only a green run, and Task 2 recorded green before red
  And Task 3's red row belongs to Task 1
  When temper task gate runs for each
  Then each prints FAIL "need a failing run before a passing run for this task and attempt"
  Note: unit
  Covers: AC-07
```

```gherkin
Scenario: An undeclared file change fails the task gate
  Given Task 1 declares scripts/a.sh and the worktree also changed scripts/z.sh, which no running task declares
  When temper task gate 1 runs
  Then it prints FAIL "undeclared change: scripts/z.sh" and leaves the task box unticked
  Note: unit
  Covers: AC-07
```

```gherkin
Scenario: A failing task is retried on Haiku, escalated once, then parks its group
  Given Task 1 fails its gate on attempt 1 (claude-haiku-5-5)
  When temper task gate 1 runs after attempts 1, 2 and 3
  Then it prints NEXT: retry on claude-haiku-5-5, then NEXT: escalate on sonnet, then NEXT: park group G1
  And temper schedule stops offering G1 tasks while G2 tasks are still offered
  And groups.json records three attempts with model, outcome and reason
  Note: unit
  Covers: AC-08
```

```gherkin
Scenario: A merge conflict stops the run before Review
  Given G1 and G2 both changed line 1 of README.md after a hand edit outside the plan
  When temper integrate runs
  Then the merge of G2 is aborted, the feature branch is left at the G1 merge
  And temper integrate exits 1 with "merge conflict: G2 in README.md", gate build FAILs on "integration"
  Note: unit
  Covers: AC-10
```

```gherkin
Scenario: A group larger than max-blast-radius is rejected at plan time
  Given autonomy.max-blast-radius: 3 and group G1 declares 4 distinct files
  When temper gate plan runs in grouped mode
  Then it prints FAIL "G1 declares 4 files > autonomy.max-blast-radius=3: split the group"
  And a group declaring exactly 3 files passes
  Note: unit
  Covers: AC-11
```

#### Edge Cases

```gherkin
Scenario: Autonomy commit gate in grouped mode compares changes to the declared union
  Given run_mode autonomous, build.mode: grouped, max-blast-radius 15 and 3 groups declaring 40 files
  When 40 declared files changed and temper gate commit runs
  Then the "blast radius" requirement PASSes "40 changed, all declared"
  And after one more change to an undeclared src/extra.ts it FAILs "changed outside declared files: src/extra.ts"
  Note: unit
  Covers: AC-11
```

```gherkin
Scenario: Parallel evidence writes lose no rows
  Given 8 temper task test calls for 4 tasks started in the background at the same moment
  When they all finish
  Then .temper/evidence/build.json holds exactly 8 new rows and is valid JSON
  Note: unit
  Covers: AC-04
```

```gherkin
Scenario: Change at a group gate reruns only the named tasks
  Given G1's tasks 1, 2 and 3 passed and the person types feedback for Task 2
  When the orchestrator records feedback #1 and runs temper group reopen G1 --task 2
  Then temper schedule offers only Task 2, at attempt 1 on the task model
  And Task 1 and Task 3 keep their ticked boxes and passed gates
  Note: unit
  Covers: AC-09
```

```gherkin
Scenario: The mod allows a planned write in a group worktree and refuses an unplanned one
  Given enforcement active, phase build, plan files scripts/a.sh, and run slug demo
  When a Write targets .claude/worktrees/temper-demo-G1/scripts/a.sh and another targets .claude/worktrees/temper-demo-G1/src/x.ts
  Then the first is allowed and the second is denied as scope drift naming src/x.ts
  And a Write to .temper/groups.json is denied as a CLI-owned file
  Note: unit
  Covers: AC-04
```

## Scenario Coverage Checklist

## Source Traceability

### Context Sources

- none: description only — nothing linked (launch prompt carries the full requirement list, req 1-10)
- consulted: /home/user/temper/.claude/CLAUDE.md — repo constraints, current version 9.6.7 (2026-10-10)
- consulted: /home/user/temper/.claude/temper.config — `autonomy.max-blast-radius: 15` default and autonomy invariants (2026-10-10)
