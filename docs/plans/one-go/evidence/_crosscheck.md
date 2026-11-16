# Cross check of the 17 reader reports (Temper, PR #115)

Reader: the planners. I read all 16 reports in this folder in full, wrote the seventeenth (`platform.md`) unchanged,
and then went to the code for every point below. Paths are relative to `/home/user/temper`. Nothing was written or run
in that folder; my two helper scripts are in `.../scratchpad/work-crosscheck/`.

Marks: **[code]** I read it at the cited line. **[counted]** I counted it with a command. **[doc]** a figure from a
document of the repository that I opened. **[reader]** a result a reader measured and I did not repeat.

## 0. Which revision

- The working tree is `9a01eff`. The head of PR #115 on GitHub is `10e965a`, three commits later [counted:
  `git ls-remote origin refs/pull/115/head`]. One reader (cli-core) names `c417166`: that was the head while it read.
- The three later commits change 10 files. In `scripts/flow.py` they add one 7 line helper (`same_failure`) and use it
  at lines 756 and 856; nothing else in the flow moves. Line numbers in `flow.py` from 2570 on are 7 higher at the head.
  `scripts/temper` is the same file [counted: diff in a reader's clone of the head].
- Every line number below is of `9a01eff`, as in the reports. No finding below depends on the three commits, except
  that the end to end suite is red at `9a01eff` and green at `10e965a`.
- Plan against `10e965a`.

---

## 1. Contradictions between reports, settled in the code

| # | Topic | Who says what | Settled answer | Evidence |
|---|---|---|---|---|
| 1 | How often the Context check is asked | flow-questions, cli-core, agents-plan-side: on every default run. pr-flow (section 3) and ux-onboarding (1.3, row d): only when the map has an `ignore` or a `gap` | **On every default run in which Plan follows its brief and writes a plan.md.** The brief and the template tell Plan to write `- reviewed: pending`; the gate row fails on `pending` unless the mode is `off`; the flow then asks. The only code that rewrites the line writes `reviewed: human`, from the person's answer. Nothing writes `auto`. The conditional rule exists only in the config comment. Exception: a spec folder with no plan.md has no such row | `agents/plan.md:89-94`; `templates/plan.md:8`; `scripts/plan_ops.py:92-94`, `:123-146`; `scripts/flow.py:2338-2344`; `scripts/gate_rows.py:310-311`; `templates/temper.config.default:104` [code] |
| 2 | Why the scripted counts (7, 8) leave the Context check out | not stated by the readers who quote 7 and 8 | The end to end fixtures write `reviewed: auto` themselves, which no real Plan agent is told to do. A real default run has one more question than every scripted count | `scripts/e2e/project.ts:4`; `scripts/e2e/pyjokes.ts:119` [code] |
| 3 | Questions on a clean default run | pr-flow: 5. flow-questions, cli-core, mod, ux: 7 with two groups, 8 with Design | One formula: **5 + 1 (Context check) + G when the plan has two or more groups + 1 when Design runs + the Blocking dialogs.** pr-flow's 5 is the one group case without the Context check | `scripts/flow.py:635, 673, 749, 784, 817` (the five), `:1763-1766` (groups), `:2338` [code] |
| 4 | Does an armed run need `autonomy: enabled: true`? | mod (6.1 table): yes. flow-questions, pr-flow, adr-constraints: the key is not read | **Not read.** A run is armed only by the option "Autonomous Build" at the Plan or Design question | `scripts/flow.py:300-303`, `:674-675`, `:726-728` [code] |
| 5 | When Design runs | evidence-bench (table 1.1), ux-onboarding (1.3, rows e' and f) and three docs: medium and complex plans. flow-questions, agents-plan-side, adr-constraints: by risk | `phases.design` on **and** (risk H at tier medium or complex, **or** tier complex when Intent had to ask something); also when a design.md exists. A medium plan below risk H has no Design | `scripts/flow.py:251-266` [code] |
| 6 | Python written inside `scripts/temper` | cli-core: about 990 lines. dev-efficiency: about 2,100 (41%) | **About 2,100.** My count: 2,124 lines inside 51 multi line `python3 -c` blocks and 14 heredocs, of 5,121 lines | [counted: `work-crosscheck/embedded.py`] |
| 7 | Python files under `scripts/` | cli-core: 48. adr-constraints, dev-efficiency, changelog-recent, ux: 49 | **49 files, 12,335 lines** | [counted] |
| 8 | Lines of the config template | cli-core, changelog-older, dev-efficiency: 171. ux-onboarding: 172 | **171** | [counted] |
| 9 | Question sites in `flow.py` | flow-questions, changelog-recent: 41. dev-efficiency (summary): 53 | Both: 41 `self.question(` sites plus 12 `self.with_more(` sites; 14 places return `"action": "ask"`. Distinct option labels were counted as 66, 69 and 71 by three readers with three methods; there are 89 `self.opt(` sites | [counted] |
| 10 | `TEMPER_*` environment variables | cli-core: 7. changelog-recent: at least 20 | 22 distinct names appear in the scripts; 15 are read from the environment; **7 are meant for a person to set** (two lock limits, three time limits, the mutation budget, the config path). The rest pass values between the CLI's own processes | [counted] |
| 11 | Why the e2e `fix` scenario fails at `9a01eff` | cli-core, pr-flow, evidence-bench: the scenario claims its runs with `evidence add --exit`, which 9.8.5 no longer counts. mod, ux-onboarding: pytest is not installed in the container | **The first.** The scenario runs `python3 -m unittest`, not pytest. At `9a01eff` it records RED and GREEN as claims; `runs.py` drops a row with no `executed_by`. `10e965a` changes those two lines to `evidence run` | `scripts/runs.py:30-33`; `git diff 9a01eff 10e965a -- scripts/e2e/scenarios.ts` [code] |
| 12 | Selftest total: 2,879 or 2,575 | PR body and dev-efficiency (1.1): 2,879. pr-tests-ci: CI prints 2,575 and 220 of the gap is unexplained | **2,575 is the serial count CI prints. 2,879 is the parallel runner's sum:** +84 because each of its 29 processes repeats 3 safety assertions, +220 because `case-helpers-5.sh` holds 214 `assert_` lines of case file 5's test code, which case file 6 runs again when it runs alone. In series the helpers are already defined and the file is not sourced. dev-efficiency's "0.51 s per assertion in CI" divides by the wrong count | `scripts/selftest/temper-cases-6.sh:11`; `scripts/selftest/run-selftest.sh:66-75`; `grep -c assert_ scripts/selftest/case-helpers-5.sh` = 214 [code, counted] |
| 13 | Did 16 of 18 measured runs step back to Build? | evidence-bench: yes ("at least one in 16 of 18"). review-check-commit: most fix passes were not followed by another Review | **Not shown.** The column counts every launch of the `temper-build` agent (28 in 18 runs). A stage loop back to Build always runs Review again, and there were only 8 extra Review rounds (26 in 18 runs). So at most 8 of the 28 launches were stage loop backs; the other 20 or more were record passes, "Run Build again" passes or group fix agents, and the logs to tell them apart are not in the repository. What is shown: 7 of 18 runs had two or more Reviews | `bench/compare_models.py:136, 139`; `docs/evidence/haiku-sonnet-task-agents.md:30-47`; `scripts/temper:1269-1295` [code, doc] |
| 14 | What the `questions` column of that table counts | adr-constraints: not known. evidence-bench: dialogs | **AskUserQuestion calls**, so dialogs. A dialog can hold up to four Blocking questions. Mean 13.1, range 8 to 26 | `bench/run.mjs:161-163` [code]; table sum 235 over 18 [counted] |
| 15 | Share of a run's cost that is Plan and Design on Opus | "45% to 83%" in five reports; "64% to 83%" in evidence-bench | Two arms. 45% to 60% when a Sonnet session ran the loop; **64% to 83% when the main session costs nothing**, which is the case with the mod's driver | `docs/evidence/bench-2026-11.md:239-240, 275-277` [doc] |
| 16 | Cost of Design | most: $0.48 to $0.61, 88 to 116 s. adr-constraints: $0.48 to $0.51 | Both, for different code. Before the CLI drew the panels: $0.49 to $0.61, 91 to 116 s (3 runs). On the shipped code: **$0.48 and $0.51, 88 and 90 s (2 runs).** Plan on the shipped code: $0.75 and $1.01, 143 and 185 s | `docs/evidence/bench-2026-11.md:354-357` [doc] |
| 17 | Is the endless fix pass after a failed `integrate` new in the PR? | pr-flow (D5): a new loop. build-side: main has the same branch | **The relaunch is older; the PR adds a second way into it.** On main a first `integrate` that fails on its suite already relaunches the fix pass with no question (the branch tests only that an integration verdict exists). The PR makes `integrate` run the suite again after new commits, so a fix pass can now land there too, and on that path the prompt carries the old loop reason and not the integration failure | `git show origin/main:scripts/flow.py` lines 1468-1482; `scripts/flow.py:1655-1672`; `scripts/temper:3316-3324` [code] |
| 18 | Session turns the mod removes | flow-questions (summary): 13 to 18 a run. mod, evidence-bench: 22 to 59 turns, $0.28 to $0.97 | flow-questions counted the stops of `temper go` in a scripted run (a floor). The benchmark measured real sessions. **Use 22 to 59 turns and $0.28 to $0.97 a run** | `docs/evidence/bench-2026-11.md:446` [doc] |
| 19 | CLI calls in a clean scripted run | cli-core: 84. evidence-bench: 46. dev-efficiency: 70 steps | Three counters, not one fact: every CLI process a run starts (84), the calls the loop itself makes (46), and loop steps (70). The time (31 to 32 s, 737 Python starts) agrees between cli-core and dev-efficiency | [reader] |
| 20 | Does the driver start Check in the background as the conversation does? | review-check-commit: not determined | **Yes.** `check ahead` is a `before` call of the Review agent, and the driver runs every `before` call before it starts an agent | `scripts/flow.py:1375-1378`; `hooks/temper-mod/core/driver.ts:401-412` [code] |

Not contradictions, but the same thing measured on different fixtures: Python starts per `gate plan` (45 with 26 rows,
42 with 24 rows); preflight failures that pass silently (24 of 33 in pr-env's set, 11 of 14 in pr-tests-ci's set).

---

## 2. Twelve claims the plan will lean on, checked in the code

| # | Claim | Verdict | What the code says |
|---|---|---|---|
| 1 | A clean default run asks 5 gate questions, plus one per Build group when there are two or more, each with a recommended answer written as a constant | **Confirmed** | "Continue to Plan (Recommended)" `scripts/flow.py:635`; "Stage by stage (Recommended)" `:673`; "Continue to Review (Recommended)" `:749`; "Continue to Check (Recommended)" `:784`; "Commit (Recommended)" `:817`; the group question only when the plan has more than one group `:1763-1766`. The flow asks whenever a stage has a verdict and the run is not armed `:2473-2474`. The Design question adds "Continue to Build (Recommended)" `:730` |
| 2 | A clean default run launches 4 + T agents: Intent, Plan, the acceptance writer, T Build task agents, Review. Check needs no agent | **Confirmed** | One agent a stage `scripts/flow.py:1119-1136`; the acceptance writer before any group `:1394-1420`; Check is `check run` and `gate check` with no agent when the CLI finds a test command and no criterion is validated by code or metric `:1359-1364`. Two conditional launches the count leaves out: a Build "record pass" when the Build gate fails only on a criterion nobody recorded `:197-214, 2415-2423`, and the Check agent for `code` and `metric` criteria `:1361-1373` |
| 3 | The Context check is asked on every default run | **Confirmed**, with the condition that Plan writes plan.md as briefed | Row 1 of section 1 |
| 4 | `autonomy.policy` is off by default; with it and an armed run the floor is 3 questions (Intent, Plan, Commit) | **Confirmed** | Default `ask` `scripts/flow.py:296-298`; commented out in the template `templates/temper.config.default:146`; an armed policy run stays armed after Build `:2457-2461` and Review and Check return `auto` `:2468-2472`; an armed run always parks at Commit `:2227-2231` and is then asked "Commit?" `:2242-2244`. An armed run never covers Intent or Plan `:2441`. The 3 was measured by two readers [reader] |
| 5 | The fresh review is not part of a default run | **Confirmed** | Default `ask` `templates/temper.config.default:105`, `scripts/flow.py:248`; under `ask` it applies only once the person asked `scripts/fresh_review.py:117-125`; two reviewers at risk H `:128-129`; 3 rounds, more after each replan |
| 6 | PR default: a High finding fails Review, and an open Medium finding makes "Loop back to Build" the recommended answer | **Confirmed** | `review.block-on` default `critical,high` at both read sites `scripts/temper:3814`, `scripts/flow.py:420`; template `:31`; the Medium rule `scripts/flow.py:779-784`, with no config key |
| 7 | PR default: any answered `Design:` question fails the Design gate until tasks.md changes, and "Loop back to Plan" is recommended | **Confirmed** | The row compares only the hash of tasks.md `scripts/decisions.py:53-69`; the question `scripts/flow.py:733-739` |
| 8 | The same tests run several times on one tree; the PR's reuse covers two call sites | **Confirmed** | `run_cached` is called for a group's Validate and for the Integration suite only `scripts/task_ops.py:464, 488`. Scenario tests run uncached at the task gate `scripts/task_ops.py:706-708`, at the group gate `scripts/temper:2504-2505`, at integrate `scripts/temper:3421-3423` and at Check `scripts/check_run.py:720`. Check's suite `:693`, the acceptance tests `:671` and each mutant `:386` are plain runs |
| 9 | The preflight: 300 s a command, runs in a worktree under the temp folder, and any failure no pattern names passes as "needs new code" | **Confirmed** | `DEFAULT_TIMEOUT = 300` `scripts/preflight.py:31`; `tempfile.mkdtemp` `:189-193`; the last line of `classify` `:115`; only the two fault classes fail the row `:224`. It runs inside whichever call runs `gate plan`, and the Plan brief tells the agent to run that gate itself `agents/plan.md:59-61` |
| 10 | The driver carries a clean run with no model in the main session; a hand back is one way; a failed group check is a hand back | **Confirmed** in code; the $0.00 is a doc figure | The driver returns `handback` and the command goes on to the prompt based page `hooks/temper-mod/register.tsx:753-765`; nothing starts the driver again but a typed command. `temper go` treats only `<cli> gate <stage>` with `-> FAIL` as a verdict, so `group gate` exiting 1 is an `error` `scripts/go.py:108-114`, which the driver hands back `hooks/temper-mod/core/driver.ts:352`. 7 of 8 runs at $0.00: `docs/evidence/bench-2026-11.md:437` |
| 11 | Loop budgets do not bound a run: only `state loop` is counted; `autonomy.budget.*` is read by nothing; a step back to Plan resets Build | **Confirmed** | The budget function `scripts/loop_step.py:20-32`; `state redo` holds no counter `scripts/temper:1455-1492`; `max-total-loops` and `max-stages` appear only in the template, this repository's own config, one status page and an old plan [counted]; `_go_back` to intent, plan or design calls `_groups_reset` `scripts/temper:1276-1279`; a step back empties the ledgers of the stage and every later one `:1876-1896` |
| 12 | Policy defect: in an armed policy run the group fix agent is never launched, so one failed group check ends in an unattended replan | **Confirmed** by reading; reproduced by three readers | The launch is guarded by `not r.armed()` `scripts/flow.py:1754`; the policy takes the recommended option's call `:1963-1972`; `group fix` only records the request, so the next pass recommends "Loop back to Plan" and the policy takes that too. No call sets the run back to interactive on that loop [reader: flow-loops E1, pr-flow D2 and D4, adr-constraints T2] |

Three more that are not in the twelve but that a plan would use, all confirmed [code]:

- Models: Plan and Design `opus`; Intent, acceptance, Build fix, Review, Check, env `sonnet`; Build task
  `claude-haiku-5-5`, or `sonnet` when the tier is complex or the risk is H (`agents/*.md` line 4;
  `scripts/cli_ctx.py:46-73`).
- The guard treats only two forward moves as the person's: leaving Intent and leaving Plan
  (`hooks/temper-mod/core/rules.ts:491`).
- The locked acceptance tests first meet the built code at Check: `acc_run` has one caller
  (`scripts/check_run.py:656, 725`).

Nothing I checked came out wrong in the code. The wrong statements are the ones in section 1 (rows 1, 4, 5, 6, 11, 12, 13).

---

## 3. One run budget: a default medium feature run, with the mod

**The run.** Shipped config, the recommended answer at every question, the mod's driver carrying the run, tier medium,
risk below H. So: no Design, no fresh review, Build tasks on Haiku. B = Blocking questions Intent writes. G = Build
groups. T = Build task agents (one per chain of tasks). Reference shape for the totals: G = 2, T = 2.

**Where the numbers come from.** Agent seconds and dollars: `docs/evidence/bench-2026-11.md` (9.8.0) and
`docs/evidence/haiku-sonnet-task-agents.md` (9.8.4): small Python tasks, a simulated person who answers at once. CLI
seconds: readers' timings on a toy project. Nothing was measured live on this PR. "Not measured" means no document
gives the figure. On the one real Java run the per launch times were 4 to 13 times larger (Plan 12 minutes, a Build
task 25, the acceptance writer 8).

**The last three columns** are my reading of the evidence, not a measurement: is the step needed for (a) a clear, well
specified request, (b) a vague request, (c) a risky large change.

| # | Step | Kind | Model | Seconds | Dollars | (a) clear | (b) vague | (c) risky large |
|---|---|---|---|---|---|---|---|---|
| 1 | Setup calls on a first run (`config init`, `init`, `guards install`), `state init` | CLI | none | under 1 | 0 | yes | yes | yes |
| 2 | Intent agent | launch | Sonnet | 30 to 45 | not measured | no: it has nothing to ask; the planning agent can write the criteria | **yes**: the one stage with a measured gain (facts met 73% to 98%) | yes |
| 3 | `usage add`, `gate intent` | CLI | none | about 0.8 | 0 | goes with 2 | yes | yes |
| 4 | Blocking questions: B questions, four to a dialog | question | none | the person's time, not measured | 0 | none arise | **yes**: true decisions, 1 or 2 dialogs | yes |
| 5 | Intent gate: "Accept the intent and continue to Plan?" | question | none | not measured | 0 | no | no as a dialog of its own: the person has just answered; show the intent in the plan approval | owner's call (the guard and ADR 0013 name it as the person's) |
| 6 | `spec branch`, `intent accept`, `spec commit`, `state advance` | CLI | none | about 1 | 0 | yes | yes | yes |
| 7 | `temper brief` | CLI | none | 0.04 to 0.28 | 0 | yes | yes | yes |
| 8 | Plan agent: scenarios, tasks.md, plan.md, about 25,000 output tokens | launch | Opus, no effort set | 143 to 246 (shipped code: 143 and 185) | $0.75 to $1.13 (shipped code: $0.75 and $1.01) | only the task list and its tests; not three files on Opus | yes | yes |
| 9 | Preflight, inside the Plan agent's own `gate plan`: every Validate, Test, Integration and scenario command once on HEAD | CLI, inside the agent's turn | none | 0.4 on the toy project; not measured on a real one; up to 300 a command | 0, but it holds an Opus turn open | a check of the environment is needed in all three, earlier and smaller than this one | same | same |
| 10 | `usage add`, `panel plan`, `gate plan` | CLI | none | 1.2 to 1.6 | 0 | yes | yes | yes |
| 11 | Context check: "Is this the right context for the plan?" | question | none | not measured | 0 | no | no as a dialog: put the `ignore` and `gap` lines in the plan approval | same |
| 12 | `plan review --answer`, `gate plan` again | CLI | none | about 1.4 | 0 | goes with 11 | goes with 11 | goes with 11 |
| 13 | Plan gate: "Approve the plan and continue to Build?" | question | none | not measured | 0 | **yes** | **yes** | **yes** |
| 14 | `spec branch`, `spec commit`, `state advance plan_complete build` | CLI | none | about 0.7 | 0 | yes | yes | yes |
| | Fresh review: not launched in a default run (it is an option of question 13) | | Sonnet, 1 or 2 reviewers | 26 each, 37 of wall time | $0.17 a plan | no | no | one round and one recheck |
| | Design: not in this run (risk below H) | | Opus | 88 to 116, plus a question | $0.48 to $0.61 | no | no | its concerns are needed; a separate Opus stage after Plan is not shown to be |
| 15 | `acceptance start`, the acceptance writer, alone before any group | launch | Sonnet | 30 to 45 | not measured | open: no run isolates its value | yes | yes |
| 16 | `state set base_sha`, `group start` per group, `task start` per chain | CLI | none | 0.4 and 0.8 each, plus a checkout each | 0 | not as worktrees: one agent in place | only where tasks really run at once | yes |
| 17 | T Build task agents, up to 4 at once | launch × T | Haiku 5.5 | 122 an agent on 9.8.0; 259 a run on 9.8.4 | $0.07 a run | one builder | yes | yes (on Sonnet by the risk rule) |
| 18 | Per task, by the agent: `task show`, `task test` red, green twice, `task gate` (owed scenario tests, commit, merge) | CLI | none | 4.4 a task plus the tests | 0 | red, green and one check | yes | yes |
| 19 | `group gate` per group: Validate, then the group's scenario tests again | CLI | none | 0.7 plus the suite | 0 | once per tree | once per tree | once per tree |
| 20 | Group question, once per group when G is 2 or more | question × G | none | not measured; a dependent group waits for it | 0 | no | no | no |
| 21 | `integrate` (merge, the Integration suite unless reused, every scenario test again), `gate build` | CLI | none | 1.0 and 0.7 plus the suite | 0 | yes, once | yes, once | yes, once |
| | Record pass: only when the Build gate fails on a criterion nobody recorded | launch | Sonnet | not measured | not measured | no | no | no: the CLI should record it |
| 22 | Build gate: "Continue to Review?" | question | none | not measured | 0 | no | no | no |
| 23 | `check ahead` in the background, then the Review agent | launch | Sonnet, effort high | 27 to 54 | not measured | yes | yes | yes |
| 24 | `usage add`, `gate review` | CLI | none | about 0.5 | 0 | yes | yes | yes |
| 25 | Review gate: "Continue to Check?" | question | none | not measured | 0 | no; ask only for an open finding | same | same |
| 26 | `check run` (adopts the background run), `gate check`: suite with coverage, scenario tests a third time, acceptance tests for the first time, up to 40 mutant runs | CLI | none | 1 to 2 on the toy project; not measured on a real one; mutation budget 300 | 0 | yes | yes | yes |
| 27 | Check gate: "Commit?" (the commit decision; it shows no numbers) | question | none | not measured | 0 | yes while the owner keeps the commit a click | yes | yes |
| 28 | `gate commit`, report, report page, `state archive`, `spec commit`, `state clear` | CLI | none | about 3 | 0 | yes | yes | yes |

### Totals for this run

| | Count | Notes |
|---|---|---|
| Agent launches | **4 + T = 6** | Intent (Sonnet), Plan (Opus), acceptance writer (Sonnet), 2 Build task agents (Haiku), Review (Sonnet). 7 with Design. One more for each record pass or Check agent |
| Questions | **6 + G = 8 dialogs**, plus 0 to 2 Blocking dialogs | Intent gate, Context check, Plan gate, 2 group questions, Build gate, Review gate, Check gate. One group: 6. Scripted runs show 7 because their fixture skips the Context check |
| Questions that decide something on a clean run | 2: the plan approval and the commit; plus the Blocking questions | The other 6 have one recommended answer after a passed check |
| Agent seconds | about 500 to 650 | 30-45 + 143-246 + 30-45 + 259 (two Haiku agents in sequence would be 244) + 27-54 |
| Seconds outside the agents | 42 to 103 with the mod; 183 to 206 without it | `docs/evidence/bench-2026-11.md:482-484`; the simulated person answers at once, so a real person's time is on top and unmeasured |
| Whole run, measured | 597 to 865 s, $1.93 to $2.50 | 9.8.0 code with the mod, two tasks; the vague-refunds runs include a Design launch (about $0.5 and 90 s). Three larger tasks on 9.8.4: mean 840 s, $2.70, 13 dialogs |
| Dollars by step | Plan $0.75 to $1.13; Build tasks $0.07 a run; main session $0.00 | Intent, acceptance writer, Review and fix passes together: $0.2 to $0.5 by subtraction, never split |
| Same task in plain Claude Code | 88 to 99 s, $0.43 to $0.49 | `docs/evidence/bench-2026-11.md:380-383` |

What the same run needs by case, from the last three columns:

- **(a) clear request:** 2 or 3 launches (one planner and builder, one Review, the acceptance writer if it is kept) and
  2 questions (approve, commit).
- **(b) vague request:** Intent, Plan, acceptance writer, builders, Review: 4 + T launches as today, and 3 or 4 dialogs
  (the Blocking questions, the plan approval, the commit).
- **(c) risky large change:** the same plus one fresh review round and the design concerns asked before the plan is
  approved; questions as (b), plus a stop for every failure.

---

## 4. Gaps: what no reader covered, and what I could answer from the code

Answered now:

1. **Effort is set on 3 of 13 agents, and not on the two Opus ones.** Only `agents/review.md` (high), `agents/rca.md`
   (high) and `agents/pipeline.md` (medium) have an `effort:` line. A launch carries a model and no effort
   (`scripts/flow.py:1135`; `hooks/temper-mod/register.tsx:505`). So Plan and Design run at whatever the host gives
   Opus by default. The plugin option `phaseModels` can set an effort per stage (`register.tsx:675-687`). No reader
   looked at effort as a cost lever, and no evidence document measures it.
2. **Two launches hide behind the criterion type.** An intent with a `Validate: code` criterion gets a Build "record
   pass" (a Sonnet agent that writes no code) each Build round and a Check agent (`scripts/flow.py:197-214, 1361-1373,
   2415-2423`). They are the likely bulk of the 20 or more unexplained `temper-build` launches of the 18 run table
   (section 1, row 13). How often intents hold such criteria is not recorded.
3. **Every launch is a fresh agent; nothing in the driver continues one.** The driver's only call is `$.agent.spawn`
   with type, prompt and model (`register.tsx:505`). The platform report says a finished subagent can be continued with
   its history by SendMessage, which is a tool of a model's session. Whether the mod API can do the same without a
   model turn is not in any report. This decides whether "repair in the context that made the fault" is possible under
   the driver or only inside an agent's own turn (as when an agent runs its gate before it returns).
4. **The Plan agent never gets the request text.** Only Intent's prompt has the `Feature:` line
   (`scripts/flow.py:1126-1130`); Plan gets intent.md and a brief ranked from the request. One reader notes it; it
   matters for any plan to merge the front agents.
5. **Run records are deleted at the end of every run.** `state clear` removes `feedback-loops.json` and `usage.json`
   (`scripts/temper:1448`); the committed ledger keeps time per stage and no questions, loop backs or dollars. So no
   installed copy of Temper can say how often any loop fires. Every "how often" in the reports is unanswerable from the
   product as built.

Still open (listed so the plan does not assume an answer):

6. Dollars for Intent, the acceptance writer, Review, a Build fix pass and a group fix agent, each alone. The bench
   logs hold them; no table does.
7. Seconds per step on a real project. The only figures are one Java run's averages, not broken down (how much of a
   25 minute Build task is a cold worktree, a JVM start, or the model).
8. How long Check and the preflight take on a real suite; the mutation step alone can be 40 suite runs.
9. Whether Plan or Design on Sonnet, or on Opus at lower effort, holds plan quality. Never run. About $50 and 4 hours.
10. How many Blocking questions a real run carries, how often a person picks "Change" at a group, and how the "about
    30 questions" of the failed run split.
11. The time a real person spends at each dialog. The benchmark's person answers at once; at 13 dialogs this may be
    the largest part of a real run's wall time.
12. Claude Code's own permission prompts in a first run. Not counted by anyone.
13. Whether a plugin workflow (platform report, section 5) could carry the part from plan approval to the commit. It
    takes no input in the middle of a run, so it could not hold a gate; nobody compared it with the mod's driver, and
    it is not known whether the mod's guard sees a workflow's agents.
14. Prompt cache behaviour. Each stage is a different agent type with its own prefix and a 5 minute lifetime; nobody
    measured what share of a run's input is read from cache.
15. Who uses Temper today and what a restructuring may break for them (configs, runs in flight, the `view.json`
    version, the commit hook path). No report has a number, and the product keeps none by design.
16. Whether the plugin directory is still a goal. It sets the 256 KiB limit, the no shell rule for the mod and the path
    rules, and `scripts/temper` is 1,640 bytes under the limit.
17. Owner decisions the reports raise and cannot settle: keep the commit a click; keep the Intent approval a separate
    click; may an unattended run plan again by itself (the PR's code does, four documents say never); should a Medium
    finding send a run back by default; seconds or cents for Build tasks; one route or two.
18. Whether a typed agent reads its own brief twice (the brief is its system prompt and its prompt says "Follow ...
    exactly"): 1,500 to 3,700 tokens a launch if it does.

---

## 5. The ten largest sources of time, cost, questions and loop backs

Ranked by what a typical run pays, then by what a bad run pays.

| # | Source | Kind | Size | Evidence |
|---|---|---|---|---|
| 1 | **The Plan agent on Opus, writing about 25,000 tokens into three files; every revision is a new clean pass** | dollars, seconds | $0.75 to $1.13 and 143 to 246 s a pass: more than a whole plain Claude Code run of the same task ($0.43 to $0.49, 88 to 99 s). With Design, 64% to 83% of a run's dollars and about 300 of its 600 to 870 s. The failed complex run had 5 passes. In the one real Plan output in git history, 42% of the file bytes are plan.md and 19% are Given/When/Then lines that no script and no builder reads | `docs/evidence/bench-2026-11.md:275-277, 354-357, 457-458`; `scripts/flow.py:1056-1059`; `CHANGELOG.md:72-74`; agents-plan-side section 4 [doc, reader] |
| 2 | **A question after every passed check** | questions, waiting | 6 of the 8 dialogs of the reference run offer one recommended answer after a check that already passed; only the plan approval and the commit decide something. Floor by construction: 6, plus G when there are two or more groups. Live mean 13 dialogs a run (8 to 26). Across 18 runs cost and time rise with dialogs (r 0.93 and 0.89; task size is mixed in). A dependent group does not start until its question is answered | `scripts/flow.py:635, 730, 749, 784, 817, 1683-1686, 1763-1766, 2338, 2473-2474`; `docs/evidence/haiku-sonnet-task-agents.md:30-47` [code, doc] |
| 3 | **Repairing a Review or Check finding by a loop through Build** | loop backs, dollars, questions | One round: 2 launches (fix pass, a full second Review of the whole diff), 4 dialogs, a second Check run, $0.40 to $0.50. 7 of 18 runs had two or more Reviews; those runs cost 39% more. The step back empties Build's ledger, so the gate asks for a new failing test whatever the finding. The PR raises the rate: High now blocks and Medium recommends the loop | `docs/evidence/bench-2026-11.md:271-273`; `scripts/flow.py:779-784, 588-593, 1655-1672`; `scripts/temper:1876-1896` [code, doc] |
| 4 | **Plan and environment faults found only after Build, then a step back that rebuilds everything** | loop backs, hours | Both failed real runs: a Validate command that could never pass. 5 Build attempts of a 12 task group and nothing on the branch; most of 2.8 hours of Build. A step back to Plan archives the grouped run and launches Plan (and Design) on Opus again. The PR's preflight runs after Plan is paid for, and outside Maven 24 of 33 sample failures pass it | `CHANGELOG.md:72-74`; `docs/decisions/0018` lines 9-12; `scripts/temper:1276-1279, 1297-1329`; `scripts/preflight.py:115, 224` [code, doc, reader] |
| 5 | **Build's structure: a worktree, a gate, a commit and a merge per task; a failed attempt is thrown away and a new agent starts** | seconds, launches | A task agent is 122 to 193 s; task agents are 17% to 29% of wall time. In 11 of 18 runs one agent built the whole plan as a chain, so the per task worktrees gave no parallel work. In 18 runs no retry was caused by the model: all 11 extra task runs came from one plan defect. Nothing shares build output between worktrees (25 minutes a Build task on the Java run, not broken down). 53 of 326 changelog items patch this mechanism | `docs/evidence/haiku-sonnet-task-agents.md:30-47, 76-78`; `scripts/temper:2955-2972, 3150-3153`; changelog-recent section 2 [code, doc, reader] |
| 6 | **The same tests run again and again on the same code** | seconds | A scenario test runs at the task gate, the group gate, integrate and Check. The suite runs at each group gate, at integrate, at Check, in the preflight, and once per mutant (up to 40). One measured run "ran the same 11,600 tests about eight times". Seconds on the benchmark, the largest CLI side cost on a real suite | `scripts/task_ops.py:464, 488, 706-708`; `scripts/temper:2504-2505, 3421-3423`; `scripts/check_run.py:386, 693, 720`; `scripts/run_env.py:121-123` [code] |
| 7 | **Design as a second Opus stage after Plan, and (new in the PR) a loop to Plan after any Design answer** | dollars, seconds, loop backs | When it runs: 88 to 116 s, $0.48 to $0.61, one more question. No later agent reads design.md and no run shows it changing an outcome. With the PR, answering one Design question recommends Plan again and Design again: about 300 s of Opus | `docs/evidence/bench-2026-11.md:357`; `scripts/decisions.py:53-69`; `scripts/flow.py:251-266, 733-739` [code, doc] |
| 8 | **A model in the main session: every run without the mod, and the rest of any run the driver hands back** | dollars, seconds | Without the mod: $0.28 to $0.97 and 22 to 59 turns a run; 183 to 206 s outside the agents against 42 to 103 s. A hand back is one way; measured ones cost $0.02 to $0.91, and one bug run went from $0.45 to $1.27. A failed group check, the failure both bad runs met, is a hand back | `docs/evidence/bench-2026-11.md:441-446, 482-484`; `scripts/go.py:108-114`; `hooks/temper-mod/core/driver.ts:352`; `hooks/temper-mod/register.tsx:753-765` [code, doc] |
| 9 | **Checks that run late or fail correct work** | loop backs | The locked acceptance tests first run at Check, after Review: three runs looped to $23 to $38 before a fix, and it still happens. Check wants 80% line coverage of the whole project and has no coverage command for Maven, Gradle or Rust, so a first run on an ordinary project fails with correct code and recommends a loop. The mutation score moved between 50%, 75% and 80% on one unchanged tree against a threshold of 70 | `scripts/check_run.py:656, 725, 138-144`; `scripts/temper:3864, 3918`; `docs/evidence/bench-2026-11.md:158-170`; review-check-commit 3.6 [code, doc, reader] |
| 10 | **Repeats with no bound** | loop backs, launches | `state redo`, `group reopen` and `group fix` are never counted; the shipped `max-total-loops: 4` is read by nothing; a failed `integrate` relaunches the Sonnet fix pass with no question. Following the recommendation looped 131, 40, 52 and 72 times in four separate incidents, each fixed by comparing failure texts. Counted loops alone allow 53 + 6 × T launches | `scripts/temper:1455-1492`; `scripts/loop_step.py:20-32`; `scripts/flow.py:1655-1672`; `CHANGELOG.md:90, 120-123`; `scripts/flow.py:2573-2575` at `10e965a` (the 72); flow-loops section 7 [code, doc, reader] |

Below the ten, and worth one line each: the acceptance writer runs alone before any group (30 to 45 s in series,
though it needs only the accepted intent); four Sonnet agents still draw their own 76 column box (a Build task agent
spent about a minute of three on it before the CLI took it over); CLI process starts cost about 31 s a small run (737
Python starts), 4% to 6% of a run.

One cost that is not a run cost but decides whether a restructuring is affordable: a change to Temper itself waits 30
minutes for CI when green and 60 when an end to end scenario hangs; PR #115 used about 546 CI minutes in 14 runs, 4 of
them green; one new question option touched 10 files.
