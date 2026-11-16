# Temper: the measured evidence and the benchmark harness

Reader's subsystem: `docs/evidence/*`, `bench/*`, `scripts/e2e/cost_row.py`, `scripts/usage_ops.py`,
`docs/history/tokenomics.md`, `docs/history/pricing.md`. Read on the local working tree (`pr115`, commit `9a01eff`),
plus the three later commits on the GitHub PR head (see 0.2).

**Confidence tags.** `[code]` read in code or run by me. `[doc]` a figure in a doc; the raw runs are not in the
repository, so it cannot be re-derived. `[derived]` my arithmetic on doc figures. `[inferred]` my judgment.
`[measured]` a command I ran in my scratch clone, with its result.

**File short names.** B = `docs/evidence/bench-2026-11.md`. HS = `docs/evidence/haiku-sonnet-task-agents.md`.
FR = `docs/evidence/fresh-review.md`. AB = `docs/evidence/opus5-plan-prompt-ab.md`. LB = `docs/evidence/live-brief-checks.md`.
RP = `docs/evidence/ab-replay-9.8.5.md` (only on the GitHub PR head). CL = `CHANGELOG.md`.

---

## 0. Read this first: what the numbers belong to

### 0.1 No live benchmark number exists for 9.8.5 (the PR)

| Code | What was measured with live models | Source |
|---|---|---|
| 9.7.6 | Rounds 1 and 2 (90 runs) | B:6, B:88, B:140 `[doc]` |
| 9.8.0 | Rounds 3, 4, 5 and every later pass in B (the last: "three gaps", 7 runs) | B:138, B:194, B:220, B:513 `[doc]` |
| 9.8.4 | 18 runs, Build task agents Haiku against Sonnet; 6 forced-path runs | HS:9-17, LB:9-16 `[doc]` |
| 9.8.5 (PR #115) | Nothing live. Selftest cases only, plus a scripted replay with fake tools and estimated agent minutes | CL:6-11; RP:17-22, RP:53-55 `[doc]`, replay re-run by me `[measured]` |

`git diff --stat origin/main...HEAD -- docs/evidence bench` is empty on the local tree `[measured]`: the PR as checked out
changes no evidence file and no bench file. Every dollar and second below is for 9.8.0 or 9.8.4 code.

### 0.2 The local working tree is three commits behind the PR on GitHub

`git ls-remote origin refs/pull/115/head` gives `10e965a`; the local `pr115` is `9a01eff`, an ancestor of it `[measured]`.
The three missing commits add `docs/evidence/ab-replay-9.8.5.md` (66 lines), `scripts/e2e/replay.ts` (393 lines),
`scripts/e2e/ab-replay.sh`, and change `scripts/flow.py`, `scripts/gate_rows.py`, `scripts/e2e/scenarios.ts`.
On the local commit `9a01eff`, `bun scripts/e2e/run.ts plain fix` FAILS ("the regression test fails first"); it passes
on `origin/main` and on `10e965a` (the commit message: "the maven and fix scenarios follow the 9.8.5 rules") `[measured]`.
GitHub's check runs for the PR head are all green, the end to end job included (it took 30.6 minutes) `[measured, GitHub API]`.
The plan should be made against `10e965a`, not the local tree.

### 0.3 The raw runs are not in the repository

No `run.json`, `grade.json`, `person.jsonl` or session log is tracked (`git ls-files` has none) `[measured]`. Results live
in `~/temper-bench-results` on the author's machine (bench/run.mjs:36). Task reference solutions (B:27) are not in the
repository either. Every bench figure is therefore a `[doc]` claim; I checked the arithmetic of the summary lines
(B:385, B:392, B:451) against their tables and it holds `[derived]`.

### 0.4 Two pricing methods: rounds 1 to 4 are not comparable with round 5

Rounds 1 to 4 took the cost from the SDK's result messages and added the results up; a resumed session's result is
cumulative, so a resumed run was counted two or more times (bench/run.mjs:239-247; B:227-229; B:217-218) `[code][doc]`.
The Temper arm resumes up to 5 times and a vague-task baseline up to 3 (bench/run.mjs:198-201). Round 5 prices each
request from Claude Code's session logs (`bench/loop.py`). Visible effect: vanilla on vague tasks was $1.04 in round 2
(B:108) and $0.39 to $0.56 in round 5 (B:322, B:493-494) `[doc]`; the model also changed, so the size of the inflation
cannot be determined. **The headline "10 times dearer, now 4.5 times" (B:61, B:451) is not one clean series.** The only
like-for-like series is inside round 5 (its "before" arm was re-run and priced the new way, B:224-225) and 9.8.4.

---

## 1. The budget of a run

### 1.1 Feature run (`/temper:temper`), with the mod, the driver carrying the run

Tasks: vague-refunds and partial-payments (Ledger, Python, about 565 lines). "n.m." = not measured in any doc.

| Stage or agent | Model (brief frontmatter) | Launches per run | Seconds | Dollars | Source and tag |
|---|---|---|---|---|---|
| Intent | sonnet (agents/intent.md) | 1 `[inferred]`; n.m. | 30 to 45 | n.m. | B:457-459 `[doc]` |
| Plan | opus (agents/plan.md) | 1; more on a loop back; n.m. | about 200 (range 143 to 246) | $0.75 to $1.13 (one task, 5 runs) | B:356, B:457, B:477-478 `[doc]` |
| Fresh plan review | sonnet | 0 in the bench (the simulated person never asks: LB:4-5); default is `ask` (templates/temper.config.default:105) | 26 each | about $0.17 a plan | FR:70-76 `[doc]`, on 9.7.6 |
| Design | opus (agents/design.md) | 1 on medium and complex plans | about 100 (88 to 116) | $0.48 to $0.61 | B:357, B:458 `[doc]` |
| Acceptance writer | sonnet | 1 | 30 to 45 | n.m. | B:459 `[doc]` |
| Build task agents | haiku; sonnet when the plan is complex or risk H (scripts/temper:573-584) | 1 to 7 launches for 3 to 7 plan tasks (mean 2.3) | 122 per agent on 9.8.0 (was 193); per run on 9.8.4: 134 Sonnet, 259 Haiku | per run: $0.33 Sonnet, $0.07 Haiku | B:475; HS:28-47, HS:73-75 `[doc]`; mean launches `[derived]` |
| Build fix pass (after a step back) | sonnet (agents/build.md) | 0 to 6, mean 1.56; at least one in 16 of 18 runs | n.m. | n.m. | HS:28-47, HS:79 `[doc]`; mean and 16/18 `[derived]` |
| Review | sonnet, effort high (agents/review.md:5) | 1 to 3, mean 1.44; two or more in 7 of 18 runs | 27 to 54 each | n.m. | B:477; HS:28-47 `[doc]`; `[derived]` |
| Check | the CLI since 9.8.0 (`temper check run`); an agent only for a stack the CLI cannot read | 0 agents | n.m. alone; inside "time outside the agents" | $0 | CL:225-232 `[doc]`; e2e trace `[measured]` |
| Main session | none (the driver); Sonnet when the run is handed back | 0 | "time outside the agents": 42 to 103 | $0.00 in 7 of 8 runs; $0.02 to $0.91 on a hand back | B:437, B:389-391, B:482-484, B:528-531 `[doc]` |
| **Whole run, 9.8.0 final code** | | | **597 to 865** | **$1.93 to $2.50** | B:427-430, B:470-471 `[doc]` |
| **Whole run, 9.8.4, three large tasks** | | task + fix + review launches: mean 5.3 (2 to 13) | **466 to 1534, mean 840** | **$1.58 to $5.43, mean $2.70** | HS:28-47 `[doc]`; means `[derived]` |

Shares `[derived]` unless cited:
- **Dollars.** Opus (Plan and Design) is 64% to 83% of a run on a cheap loop (B:275-276 `[doc]`). Build task agents are 3% to
  12% (HS:87-88 `[doc]`). The main session is $0. The Sonnet agents (Intent, acceptance, Review, fix passes) are the
  remainder: on vague-refunds about $1.93 less Plan (about $0.88) less Design (about $0.50) less tasks ($0.07 to $0.33),
  so $0.2 to $0.5. No doc breaks the Sonnet agents down.
- **At the bench's own prices** (bench/loop.py:34-38: Opus $4 in, $20 out; Sonnet $2, $10; Haiku $0.10, $0.50 per million
  tokens), 25,000 Opus output tokens (B:457-458) are $0.50: half or more of the Plan agent's cost is the text it writes.
  A Plan agent alone ($0.75 to $1.13, 143 to 246 s) costs about twice a whole vanilla run of the same task
  ($0.43 to $0.49, 88 to 99 s: B:380-383).
- **Seconds.** Plan about 200 s and Design about 100 s are roughly 300 of 600 to 870 s: 35% to 50%. Intent, acceptance and
  Review are about 100 to 135 s together. Build task agents were 17% of wall time in the 9.8.4 Sonnet arm and 29% in the
  Haiku arm. Time outside the agents is 7% to 12%.
- **Per plan task** (9.8.4): 26 s on Sonnet, 47 s on Haiku; per launch 64 s and 106 s (HS:28-47).

Without the mod, add a Sonnet main session: $0.28 to $0.97 a run in 22 to 59 turns (B:446), and time outside the agents
of 183 to 206 s on a feature against 42 to 103 s (B:482-484) `[doc]`.

**On a real project the per-launch times are 4 to 13 times larger.** The Java 24 run's own averages per launch: Plan 12
minutes, a Build task 25, a Build fix pass 40, Review 3, Intent 1, Acceptance 8 (RP:21-22; `scripts/e2e/replay.ts:192-196`
on `10e965a`) `[doc]`. The bench: Plan 3.3 minutes, a Build task 2. The bench's seconds are a floor, not a forecast.

### 1.2 Bug run (`/temper:fix`), with the mod, the driver carrying the run

Sequence: RCA, Fix, Review, Check, Commit (scripts/flow.py:47-48) `[code]`.

| Stage or agent | Model | Launches | Seconds | Dollars | Source and tag |
|---|---|---|---|---|---|
| RCA | opus, effort high (agents/rca.md:5) | 1 | 33 to 61 (final pass; before the CLI drew its panel: 77 to 103) | $0.23 to $0.34 (before: $0.44 to $0.62) | B:386-388 `[doc]` |
| Fix | sonnet | 1; 3 passes in the one hand back run | n.m. | n.m. | B:441-444 `[doc]` |
| Review | sonnet | 1 `[code: sequence]`; n.m. | n.m. | n.m. | |
| Check | the CLI | 0 agents | n.m. | $0 | CL:225-232 |
| Main session | none | 0 | 13 to 14 outside the agents | $0.00 | B:482-484, B:437-438 `[doc]` |
| **Whole run, clean** | | 3 agents `[measured, scripted]` | **88 to 133** | **$0.41 to $0.50** | B:427-428, B:438, B:472-473 `[doc]` |
| **Whole run, handed back** (1 of 4 with-mod runs) | | | 290 | $1.27 ($0.43 in the main session) | B:441-444 `[doc]` |

Fix, Review and Check together are the remainder: about $0.11 to $0.27 and 28 to 100 s `[derived]`, across two passes
that are not the same code (the RCA figures are from the final pass, the totals from the shipped pass).

### 1.3 The floor of questions and launches, measured free on the PR head

I traced the scripted end to end scenarios (real CLI, scripted agents, the person takes the recommended option) on
`10e965a` in plain mode `[measured]`:

| Scenario | Gate questions on a faultless run | Agent launches | CLI calls |
|---|---|---|---|
| `/temper:fix` (`fix`) | 4 (RCA, Fix, Review, Check) | 3 (rca, fix, review) | 16 |
| `/temper:temper`, two Build groups, no Design (`full-run`) | 7 (Intent, Plan, G1, G2, Build, Review, Check) | 6 (intent, plan, acceptance, 2 tasks, review) | 46 |
| the same with Design (`design`) | 8 | 7 | 52 |
| three groups (`three-groups`) | 8 | n.m. | 53 |
| Autonomous Build armed (`armed-run`) | 4, and 3 automatic steps | n.m. | 48 |
| risk H: two fresh reviewers, a recheck, Design, one Review finding sent back, then a fix run (`pyjokes-full`) | 15 | n.m. | 92 |

So a faultless feature run asks 5 stage questions, plus one per Build group, plus one for Design, before any Intent
Blocking question, Context check or Scope drift question. With live models on 9.8.4 the three large tasks drew
**13 dialogs a run on average (8 to 26)** (HS:28-47; `questions` counts AskUserQuestion calls: bench/run.mjs:162) `[doc][derived]`.
A bug run's floor is 4 dialogs, in a run that takes about 90 s; the live count for bug runs is not published in any doc.

The scripted replay of the Java run (RP:26-35; re-run by me in 48 s, same table) `[measured]`: 9.8.4 asked 8 questions,
launched 10 agents, recommended 1 loop back and needed 2 repairs of the shell by hand; 9.8.5 asked 8, launched 7,
needed none; 9.8.5 with `autonomy.policy: decide` asked 4. Agent minutes (191 against 92) are an estimate from fixed
weights per launch, not a measurement (RP:55).

---

## 2. The trend, and what each change bought

### 2.1 Three anchor tasks (means; see 0.4 for why the first rows are not comparable with the rest)

| Code state | Priced by | cent-mismatch (bug) | vague-refunds | partial-payments | Source |
|---|---|---|---|---|---|
| R1/R2, 9.7.6 | SDK sum | $1.58 | vague tasks: $7.69, 981 s | $4.85; hard tasks 878 s | B:36, B:45-47, B:110 |
| R3, 9.8.0 | SDK sum | all 33 runs: median $2.56, mean $5.43, 856 s | | | B:149 |
| R4, Sonnet loop | SDK | $0.96, 269 s | $3.18, 884 s | $3.54, 1022 s (1 run) | B:201-205 |
| R4, Haiku loop, unguarded | SDK | $1.35, 249 s | $4.97, 1171 s (9/11 once) | $3.40, 1256 s (23/26) | B:202-206 |
| R5 "before": 9.8.0 as pushed, Sonnet loop | session logs | $1.01, 232 s | $2.79, 937 s | $3.48, 1187 s | B:380-383 |
| R5 relay session, Sonnet loop | logs | $0.93, 249 s | $3.28, 1137 s | $2.97, 988 s | B:247, B:253, B:256 |
| R5 guarded Haiku loop | logs | $0.68, 229 s | $2.16, 904 s | $2.55, 950 s | B:248, B:254, B:258 |
| R5 final pass: Haiku loop, driver, CLI panels, brief | logs | $0.47, 197 s | $2.00, 641 s | $2.06, 738 s | B:380-383 |
| Shipped: Sonnet loop, driver carries fix runs too, with the mod | logs | $0.45, 89 s | $1.93, 661 s | $2.28, 865 s | B:427-430 |
| Shipped, without the mod | logs | $0.84, 147 s | $2.95, 812 s | $2.95, 827 s | B:427-430 |
| Faster Build, with the mod | logs | $0.41, 113 s (1 run) | $1.93, 597 s | $2.50, 811 s | B:470-472 |
| 9.8.4, Sonnet task agents (the default for these plans) | SDK, fixed | | | $2.65, 716 s | HS:60 |
| 9.8.4, Haiku task agents | SDK, fixed | | | $2.63, 890 s | HS:59 |
| Vanilla, same day as the final pass | logs | $0.36, 48 s | $0.43, 99 s | $0.49, 88 s | B:380-383 |

Rows are `[doc]`; the two-run means in rows 4, 6 and 7 are `[derived]`.

### 2.2 What each change bought

| Change | Dollars | Seconds | Other | Strength | Source |
|---|---|---|---|---|---|
| 9.8.0 over 9.7.6 (Intent's rules checklist, clicked answers, scope row, Check run by the CLI, acceptance tests) | median -31% ($3.69 to $2.56); mean up ($4.66 to $5.43) from 3 looping runs | none (847 to 856) | brief facts met 83% to 98%; files out of scope 13/30 to 1/33 | 30 and 33 runs, old pricing | B:148-161 |
| The loop at Check fixed (failing output carried, "Correct the acceptance test") | late-fees mean $18.00 to $3.30; subscriptions $15.17 to $5.02 | n.m. | no run looped | 6 reruns | B:172-179 |
| Loop on Haiku, unguarded (R4) | loop -$0.2 to -$0.5; run total higher on features | longer (80 to 93 turns against 50) | left the script; lost hidden tests | 10 runs | B:199-215 |
| Relay session, Sonnet loop (R5) | bugs -$0.05 to -$0.10; partial-payments -$0.50; vague-refunds +$0.40 to +$0.50 | within noise | | 2 runs a cell | B:271-274 |
| Guarded Haiku loop | -$0.30 a bug (30%), -$0.63 vague-refunds (23%), -$0.93 partial-payments (27%) | about the same | not shipped: unsafe without the mod (2 of 8 runs left the script) | 2 to 3 runs a cell | B:269-270, B:410-416 |
| The driver (no model in the main session): with the mod against without, same code | -46% bug, -35% vague-refunds, -23% partial-payments | -39% bug, -19% vague-refunds, +5% partial-payments; time outside agents 42 to 103 s against 183 to 206 s | 7 of 8 runs carried whole; tenant-leak's mean was 9% dearer with the mod, from the one hand back | 2 runs a cell | B:427-430, B:448-450, B:482-484 |
| The driver carries `/temper:fix` | none ($0.47 to $0.45) | cent-mismatch 197 s to 89 s | | 2 runs | B:380, B:427, B:437-439 |
| CLI-drawn panels and the project brief | Plan -14%; RCA $0.44-0.62 to $0.23-0.34; whole run -11% | Plan -25%, Design -13%, RCA 77-103 s to 33-61 s; whole run -17% | | 2 runs against 3 | B:354-371, B:386-388 |
| Intent asks Who, When, How much first; then Exempt | none | none | the 60 day window asked in 4 of 4 runs (was 1 of 3); late-fees 12/13 to 13/13 | 4 and 2 runs | B:434-436, B:520-527 |
| Faster Build (the CLI draws the task panel; a hook refuses a command that waits for input) | none | a Build task agent 193 s to 122 s (-37%); 480 s of hung commands gone; **a whole run moved less than its noise** (6% to 10%) | | 10 agents | B:457-464, B:475-481 |
| 9.8.4: Sonnet task agents on complex or risk H plans | +$0.25 a run | task agents 259 s to 134 s; run -100 s (13%) | no quality difference (9/9 each) | 9 runs an arm | HS:66-99 |
| Fresh plan review, when it runs | +$0.17 a plan (17% of the Plan stage) | +26 s reviewer, +37 s wall | finds planted plan defects 5 of 5 | 3 runs a mode, 9.7.6 | FR:36-39, FR:70-76 |
| v8 prompt diet (Plan prompt 1,086 to 224 lines) | -41% to -48% a Plan run | **none** (384 s against 388 s) | quality equal | 3 runs an arm for cost | AB:13-20, AB:35, AB:42-49 |

### 2.3 Ranking `[inferred from the table]`

Gave the most:
1. **Removing loops that never end.** The largest swing in the record ($15 to $18 a run down to $3 to $5). 9.8.4 found the
   same class three more times: 131 recommended fixes in a row, 40 relaunched fix passes, 52 Check reruns (CL:86,
   CL:121-124) `[doc]`.
2. **Taking the model out of the main session** (the driver): 23% to 46% of cost, and the time between agents from about
   3 minutes to about 1.
3. **Letting the CLI do what an agent typed** (panels, the brief, plain fields): halved the RCA agent, 14% to 25% off Plan.
4. **The Intent checklist**: the only change that moved an outcome (facts met 83% to 98%), at no cost.

Gave nothing measurable: the Sonnet relay session; Faster Build on a whole run; the prompt diet on wall time; Haiku
instead of Sonnet for task agents on cost ($0.25, inside the spread of $1.99 to $3.19 for one task: HS:88-89). The
unguarded Haiku loop was negative.

What is left: nothing above touched the two Opus agents' output or the number of stages. Since round 5 "the next cut
has to come from the Opus agents, and from work an agent does that the CLI can do" (B:275-277) `[doc]`.

---

## 3. What the evidence says about model choice

| Question | Tested? | Result | Source |
|---|---|---|---|
| Plan and Design on Opus against anything else | **Never.** "The agents' models never changed" | none | B:225, HS:12 |
| Plan prompt length, both arms on Opus 5 | Yes, 6 runs an arm (3 for cost), a fixture that no longer exists (`evals/` was removed in 9.5.0: CL:1948) | cost -41% to -48%, time unchanged, gate verdicts equal | AB:1-55 |
| Build task agents: Haiku against Sonnet | Yes, 18 runs, 9.8.4 | same hidden tests (9/9 each); Haiku $0.25 cheaper a run (9%) and 100 s slower (13%); task agents take twice as long on Haiku | HS:66-99 |
| The loop on Haiku against Sonnet | Yes, rounds 4 and 5 | guarded: $0.03 to $0.09 against $0.27 to $0.85, same outcomes; unguarded: left the script in 2 of 8 runs; shipped loop stays Sonnet | B:265-268, B:410-416 |
| RCA on Opus against Sonnet | No. One accidental launch on Sonnet in about 280, outcome not reported | none | B:212-213 |
| Effort levels (review and rca are `high`) | No | none | agents/review.md:5, agents/rca.md:5; no mention in docs/evidence `[measured: grep]` |
| The whole run on one model, as vanilla is (Opus, one session) | Only as the vanilla arm | equal correctness on clear tasks at $0.36 to $0.56 | B:499-501 |

What the model evidence supports `[inferred]`:
- A cheaper model is not a faster one: Haiku task agents were twice as slow as Sonnet (HS:90-91).
- A cheaper model for a small share buys little: task agents are 3% to 12% of cost, the loop is $0 with the driver.
- The only large share nobody has tested is Opus Plan and Design. At equal tokens Sonnet is half Opus's price
  (bench/loop.py:34-38), so the ceiling of that lever is about $0.6 to $0.85 a run (about a third of a run); its effect on time and
  on later loop backs is unknown.
- That test needs no code: `models.plan: sonnet` overrides the brief (scripts/temper:567-571), and
  `bench/run.mjs --config-yaml` appends config lines (bench/run.mjs:119-131). I confirmed in a throwaway project that
  appending `models:\n  plan: sonnet\n  design: sonnet` makes `temper model --all` print `plan=sonnet`, `design=sonnet` `[measured]`.

Never tested, in any doc `[measured: grep of docs/evidence and CHANGELOG]`:
- Plan on Sonnet; Design on Sonnet; no Design at all.
- One front agent in place of Intent, Plan, Design and the acceptance writer.
- Review and Check in parallel (Check is the CLI now; nothing measures running it while Review reads).
- The spec route of ADR 0017 ("Nothing of it is built": CL:139-141).
- Autonomous Build and `autonomy.policy: decide` with live models (no mention in docs/evidence).
- The `careful-ask` arm on the current model. It ran in round 2 only (B:103-110); round 3 reused those numbers.
- Whether the acceptance writer or Design changes a hidden-test result. The one isolated test of a stage is the fresh
  review on a seeded fixture (FR:46-61).
- History worth knowing: an adaptive depth lever (a reduced pipeline for small changes) existed through v6 and was retired
  in v7 because "it traded a small saving for a weaker plan gate" (docs/history/tokenomics.md:25) `[doc]`, with no
  measurement cited.

---

## 4. What the bench measures, what it lacks, what a round costs

### 4.1 What it measures today `[code]`

| Thing | Where | Reported by |
|---|---|---|
| Hidden tests, original suite, files outside `expected_paths`, lines changed | bench/grade.py:107-148 | report.py:41-59 |
| Brief facts met and facts asked for (vague tasks) | grade.py:78-90; run.mjs:259-260 | report.py:62-81 |
| Mutation score, regression caught | bench/mutate.py:122-165 | report.py:49-56 |
| Cost (SDK, cumulative fix), wall time, API time, turns, sessions | run.mjs:238-264 | report.py:57 (means only) |
| `questions`: AskUserQuestion calls in the run | run.mjs:162, run.mjs:258 | **not in report.py**; compare_models.py:133 only |
| Every question with its time, stage, options and answer | `person.jsonl`: run.mjs:167, run.mjs:187 | nobody |
| Main session: turns, context, cost split, growth by source, refusals | bench/loop.py:127-239 | `loop.py --summary` |
| Build task launches, task runs, escalations, fix passes, Review rounds, Build task seconds and dollars | bench/compare_models.py:111-140 | compare_models.py only |
| Claude Code's own logs of the session and each agent | run.mjs:90-106, run.mjs:268 | read by loop.py and compare_models.py |

### 4.2 What it lacks for the owner's goal, and how hard each is

The logs it already copies hold everything except human time. I wrote a 46 line prototype that reads only
`session/subagents/*.meta.json` and `*.jsonl` and `person.jsonl`, and prints launches, seconds, dollars and output tokens
per agent type, questions per stage, stage regressions and the longest stretch without a question. It runs on synthetic
logs shaped as loop.py and compare_models.py read them; I had no real logs to try it on `[measured, synthetic]`.

| Metric | Today | To add | Effort |
|---|---|---|---|
| Questions per run | counted in `run.json`, never printed | a column in report.py; split by `header` (gate, group, drift, Intent rule) from `person.jsonl` | S |
| Loop backs per run | not recorded. `feedback-loops.json` is deleted at `state clear` and is not in the archived ledger (scripts/temper:1378-1403, scripts/temper:1448) | log the option's `move` beside the answer (run.mjs:164-167 holds it already), or snapshot `view.json`'s `loops` at each question (scripts/flow.py:2772-2781) | S |
| Agent launches per run, by type | only build-task, fix pass and review, only in compare_models.py. `loop.py`'s agent list is empty under the driver (loop.py:181-184; compare_models.py:59-60) | count `agentType` in the subagent meta files | S |
| Wall time per agent and stage | only build-task (`subagent_secs`, compare_models.py:88-108) | call it for every type. It sums first to last timestamp per log, so agents that ran in parallel add up | S |
| Cost per agent and stage | only build-task (`kind_cost`, compare_models.py:29-48) | call it for every type | S |
| Time between agents | once, by hand (B:482-484) | wall less the agents' seconds | S |
| Time the person spends | **cannot be measured**: the simulated person answers at once (bench/person.mjs:22-34) | report dialogs, the gaps between them, and a stated reading time per dialog | M, and it stays a model |
| Spread | means only (report.py:48-58) | min, max, median | S |
| Which code ran | `run.json` has no plugin commit, version, Claude Code version or mod on/off (run.mjs:248-264) | four fields | S |
| An arm for "no mod", "Haiku loop" and the like | none: those arms were run from separate worktrees (B:225), and report.py knows five arm names (report.py:14) | a flag and free arm names | S to M |
| A reproducible table | round 5's tables were put together by hand from `loop.py --summary` | one script from results folder to table; keep `run.json` and `grade.json` per published table | S |

The product also records part of this for every real run: `.temper/usage.json` has one row per launch with stage, model
and milliseconds (scripts/temper:4763-4779), summed into the committed `gate-ledger.json` (scripts/temper:1377,
scripts/temper:1401-1402; scripts/usage_ops.py:16-38). It holds no tokens and no dollars by decision
(scripts/temper:4766; docs/history/pricing.md:8-16), no questions and no loop backs `[code]`.

Free structural counters exist already: the end to end traces (section 1.3) and, on `10e965a`, `scripts/e2e/replay.ts`,
which counts questions, launches, recommended loops and repairs by hand (replay.ts:197-198, 339, 347, 379-381) `[code]`.

### 4.3 Other harness facts a planner should know `[code]`

- The person: takes "(Recommended)", else the first option that does not stop, skip, override or defer; never types a
  change (bench/person.mjs:11-34). On vague tasks a Sonnet "product owner" answers product questions from a private brief
  (bench/person_llm.mjs:9-22; run.mjs:170-185); gate questions keep the fixed policy.
- Caps: 60 questions, then the person "has left" (run.mjs:163); 6 sessions for Temper, 1 for vanilla, 4 for a vague
  baseline (run.mjs:201); 60 minutes (run.mjs:51), 90 from run-all.sh (run-all.sh:15). The two real bad runs (about 30
  questions; 3.2 hours) would be cut off or nearly.
- Runs go one at a time (run-all.sh:3); the 9.8.4 comparison ran three tasks in parallel (HS:17).
- `bench/README.md:42` says cost comes from the SDK's results; round 5 is priced from session logs with a price table
  written into bench/loop.py:34-38 (dated 2026-10, loop.py:24). Two sources, one stale-able table.
- `mutate.py` reads a task only from `bench/tasks` (mutate.py:126), so it cannot score a `--task-dir` task; grade.py
  can (grade.py:100).
- `scripts/e2e/cost_row.py` and `live-smoke.sh cost` are a second, cheaper live harness: one headless session from the
  Plan agent to the plan question, cost and time per mode (cost_row.py:1-5, 29-32; FR:65-73).

### 4.4 What one round costs

| Round | Runs | Dollars | Hours, one run at a time | Source |
|---|---|---|---|---|
| Four anchor tasks, 2 runs, Temper only | 8 | $10.10 | 1.0 | B:373-383 `[doc]`; hours `[derived]` |
| The same with vanilla | 16 | $16.40 | 1.7 | B:311-325 |
| A model A/B: 3 large tasks, 3 runs, 2 arms | 18 | $48.68 | 4.2 (ran three in parallel) | HS:28-47 `[derived]` |
| All 11 tasks, 3 runs, Temper and vanilla, at the latest per-task figures | 66 | about $71 | about 6.1 | B:427-430, B:489-497 `[derived]` |
| Round 1 as run | 63 | $83.85 | n.m. | B:6 |
| Round 3 as run | 33 + 6 | $181.29 + $19.78 | n.m. | B:141 |
| Everything recorded in B, plus the 9.8.4 runs | 258 + 18 (round 4's 16 runs are not priced) | $605.10 + $48.68 | n.m. | sums of B:6, 136, 141, 229, 311, 344, 373, 399, 419, 455, 513 `[derived]` |

Scripted alternatives cost nothing: the A/B replay took 48 s on my machine; one end to end scenario about 20 s `[measured]`.
The full end to end CI job takes about 31 minutes `[measured, GitHub API]`.

---

## 5. The gap to vanilla, and a defensible target

### 5.1 The gap today (latest figures, with the mod; vanilla run the same day or hour)

| Task type | Task | Temper | Vanilla | Cost ratio | Time ratio | What Temper added in that pass | Source |
|---|---|---|---|---|---|---|---|
| Bug | cent-mismatch | $0.45, 89 s | $0.36, 48 s | 1.25 | 1.9 | nothing on hidden tests (4/4 both) | B:427 |
| Bug | tenant-leak (clean run) | $0.50, 110 s | $0.37, 46 s | 1.35 | 2.4 | nothing (6/6 both) | B:428 |
| Bug | tenant-leak (handed back) | $1.27, 290 s | $0.37, 46 s | 3.4 | 6.3 | nothing | B:441-444 |
| Vague feature | vague-refunds | $1.93, 661 s | $0.43, 99 s | 4.5 | 6.7 | 11/11 against 8/11; 5 of 5 facts against 3 | B:429, B:432-433 |
| Vague feature | vague-discounts (1 run) | $2.88, 778 s | $0.49, 112 s | 5.9 | 6.9 | **nothing** (9/9, 5/5 facts both) | B:493 |
| Vague feature | vague-late-fees (1 run; after the fix: $1.87 to $4.01) | $1.97, 656 s | $0.56, 134 s | 3.5 | 4.9 | **less** (12/13 against 13/13), equal after the fix | B:494, B:520 |
| Clear feature | partial-payments | $2.28, 865 s | $0.49, 88 s | 4.7 | 9.8 | nothing (26/26 both) | B:430 |
| Clear feature | subscriptions (1 run) | $3.39, 1463 s | $0.53, 98 s | 6.4 | 14.9 | nothing | B:491 |
| Clear feature | ts-seat-holds (1 run) | $1.66, 595 s | $0.54, 57 s | 3.1 | 10.4 | nothing | B:492 |
| Clear feature | login-lockout (1 run) | $2.39, 720 s | $0.18, 40 s | 13.3 | 18.0 | nothing | B:495 |
| Clear feature | orders-pagination (1 run) | $1.08, 369 s | $0.22, 47 s | 4.9 | 7.9 | less (8/9 against 9/9), equal after the fix | B:496, B:521 |
| Clear feature | slugify (1 run) | $0.74, 245 s | $0.12, 18 s | 6.2 | 13.6 | nothing | B:497 |

Ratios `[derived]`. In dollars the gap is $0.1 on a bug and $1.5 to $2.9 on a feature. In time it is 40 to 60 s on a bug
and 6 to 23 minutes on a feature, during which the person answers 8 to 26 dialogs.

What Temper adds that these columns do not count `[doc]`: the person's decisions in intent.md, gates computed by the CLI,
acceptance tests locked before Build, a report, a commit block (B:508-511); stronger tests left behind (mutation score
93% against 79%, last measured in round 3, on old code and the old baseline: B:149). On a clear task a one-paragraph
"careful" prompt reached the same hidden tests and 88% against 94% mutation score for 1.16 times vanilla's cost
(B:34-36) `[doc]`. On vague tasks one added sentence ("ask me before you build") met 85% of the facts against Temper's
83% in round 2, at 0.84 times vanilla's cost (B:108-110, B:120-122); 9.8.0 then reached 98% (B:149), against the
round 2 numbers of that arm.

### 5.2 A target that can be defended `[inferred]`

The rule: Temper may cost what the thing it adds would cost to get another way.

| Task type | What it adds | Target ratio to vanilla | On the Ledger tasks | Person | Why this number |
|---|---|---|---|---|---|
| Bug | a root cause on record; a regression test the CLI proved fails on the old code | cost at most 1.5, time at most 2 | at most $0.55, 95 s | at most 2 dialogs (today 4) | It is already there on a clean run (1.25 to 1.35, 1.9 to 2.4). The work is the tail: 1 run in 4 handed back at 3.4 and 6.3 times. |
| Clear feature | no correctness; stronger tests; the record; the commit gate | cost at most 2, time at most 3 | at most $1.00, 4.5 minutes | at most 3 dialogs (today 8 to 26) | The record and the gate are CLI work, seconds not dollars. An independent test writer and one review are two Sonnet agents of 30 to 45 s. The bug flow proves a flow of one thinking agent, one builder, one review and CLI checks runs at 1.3 and 2. The careful prompt gets most of the tests for 1.16. |
| Vague feature | the person's unstated rules: 98% against 73% in round 3, 5 of 5 against 3 of 5 on one task in round 5 | cost at most 3, time at most 4 | at most about $1.50, 7.5 minutes | the open rules (5 or 6) plus at most 3 dialogs | A missed rule costs vanilla at least one more round (about $0.45, 100 s) and the person's time to notice. Two to three vanilla runs is a fair price for not missing 1 or 2 rules of 5. It only holds while Temper stays clearly above `careful-ask`, which has not been re-run on the current model. |

Counts to hold beside the ratios: step backs to Build 0 in the median run (today at least one in 16 of 18 large runs);
agent launches at most 5 on a clear feature (today about 9: four single stages and 5.3 task, fix and review launches).

Distance to the target `[derived]`:
- Bug: met on clean runs.
- Vague: needs 14% to 49% less cost (from 3.5, 4.5 and 5.9 times) and 18% to 42% less time (from 4.9, 6.7 and 6.9 times).
- Clear feature: needs less than half the cost and a third of the time. It **cannot be met with the current stages**:
  Plan alone (143 to 246 s) is longer than twice a vanilla run, and Plan plus Design cost $1.23 to $1.74 against a
  $1.00 ceiling. Shorter prompts will not do it (AB:42-45). Fewer stages, or one front agent that writes far less than
  25,000 tokens, will have to.

Two measured signs of where the rest goes `[derived from HS:28-47, 18 runs, three tasks, so task size confounds it]`:
- Cost and time follow the number of dialogs: r = 0.93 and 0.89; about $0.21 and 63 s per extra dialog overall
  ($0.09 to $0.18 and 42 to 62 s within a task).
- Runs with one Review and at most one fix pass (11 of 18) averaged $2.35, 729 s and 11 dialogs; the other 7 averaged
  $3.26, 1014 s and 16 dialogs: 39% more of each.

---

## 6. Limits the plan must not over read

1. **Sample sizes.** Most round 5 cells are 2 runs; the seven "other tasks" are 1 run each (B:486-497); per-agent costs
   of Plan and Design come from one task, 2 to 3 runs (B:354-357). The doc says of its own two-run results "a first
   measure, not a result" (B:370-371).
2. **Spread is as large as most effects.** tenant-leak cost $1.66, $5.35 and $1.72 in three runs (B:76); one 9.8.4 task
   ranged $1.99 to $3.19 (HS:88-89); Review 27 to 54 s, Plan 153 to 234 s (B:477-478). Any claimed gain under about 20%
   on two runs is noise.
3. **Pricing changed mid-series** (0.4). Do not quote "10 times to 4.5 times" as one trend.
4. **The tasks.** All 11 written by the author (B:80-81; bench/README.md:73-74). Ten Python, one TypeScript. Code under
   test is 22 to 583 lines; 7 of the 11 tasks share one Ledger code base of about 565 lines `[measured: line counts of
   bench/tasks/*/repo]`. Plans had 3 to 7 tasks; the run that went badly had 12 tasks and about 30 files (HS:103-105).
   No task has an environment fault, a build tool slower than seconds, or a second service.
5. **Real per-launch times are 4 to 13 times the bench's** (RP:21-22 against B:457-459, B:475). A stage that is 30 s on
   the bench (acceptance) was 8 minutes on the Java project. Time shares from the bench do not carry over.
6. **The simulated person** approves everything, takes the recommended option, never types a change, never asks for the
   fresh review, answers at once (bench/person.mjs:1-34; LB:4-5). So the bench (a) leaves out human time entirely,
   (b) never takes the paths behind the two bad real runs, (c) measures the CLI's recommendations, not people.
7. **A ceiling on correctness.** Every arm passes nearly every hidden test (B:55-57, B:499-501), so the bench can show
   neither that Temper builds more correct code nor that a lighter Temper builds less correct code. A redesign that
   keeps 100% here has not been shown safe.
8. **The vague-request advantage is thin in the last pass**: 5 of 5 facts against 3 of 5 on vague-refunds, equal on
   vague-discounts, behind then equal on vague-late-fees (one vanilla run each). The baseline moved: "the model under
   vanilla has caught up" (B:499-501).
9. **The tests-left-behind advantage** (mutation score) was last measured in round 3 (B:149) and not at all on
   round 5 code or today's baseline.
10. **Nothing live on 9.8.5.** Preflight, the setup block, `review.block-on: [critical, high]` (more repairs before
    commit), `autonomy.policy: decide`, `plan patch`: unmeasured with models. The replay's 191 to 92 agent minutes is
    an estimate with scripted agents (RP:53-55).
11. **Raw data is not kept with the docs** (0.3), and `run.json` does not say which code ran (4.2).
12. **Older evidence is not usable for this goal.** `benchmark.md` measures review detection on a 300 line playground
    and concludes parity (benchmark.md:79-85, 108-110). `case-study.md` is anecdote; its metrics table ("Average test
    coverage 85%+", case-study.md:84-91) has no source. `comparison.md` states the cost honestly ("3 to 13 times",
    comparison.md:36-38) and that every other tool has a lighter path for a small change (comparison.md:27).

---

## 7. What follows for the plan

Sources of waste seen in the evidence:

| What | Size, with basis | Where |
|---|---|---|
| The Plan agent writes about 25,000 tokens on Opus | about 200 s and $0.75 to $1.13 a run; more than a whole vanilla run | B:356, B:457-458 |
| Design on Opus, never shown to change an outcome | about 100 s and $0.5 a run | B:357, B:458 |
| A fixed floor of dialogs | 7 to 8 a faultless feature run, 4 a bug run; 13 measured on large tasks | section 1.3; HS:28-47 |
| Step backs to Build | at least one in 16 of 18 runs; rough runs cost 39% more | HS:28-47 `[derived]` |
| A model in the main session when the mod is absent | $0.28 to $0.97 and about 100 to 140 s a feature run | B:446, B:482-484 |
| Wrong locked acceptance tests | three runs at $23 to $38 before the fix; still two loops back in one late run | B:158-170, B:505-507 |
| Hand backs | $0.36 to $0.91 of Sonnet each; one bug run 3.4 times vanilla | B:441-444, B:528-531 |
| Bench tables made by hand, raw runs not kept, two price sources, no code stamp | every figure is a doc claim; a round's write-up is manual | sections 0.3, 4.2, 4.3 |

Changes I would make on the evidence side, most valuable first:

1. **A scorecard in the owner's units**, from logs the bench already copies: dialogs (by stage and kind), loop backs,
   launches, seconds and dollars per agent type, time between agents, longest stretch without a dialog; plus the code
   stamp in `run.json`. Small. Without it every later change is judged by hand-made prose.
2. **Run the model A/B nobody has run**: Plan and Design on Sonnet, by config line, 3 tasks, 3 runs, 2 arms: about $50
   and 4 hours. It decides the largest untested cost lever before any redesign.
3. **Set the three target ratios as the bench's pass line**, and measure a lighter route for clear requests against
   them on the six clear tasks (the route itself is another reader's subject; ADR 0017 is unbuilt).
4. **Track the structural floor for free in CI**: dialogs and launches of the scripted `full-run`, `design` and `fix`
   scenarios, and the replay's table; fail when a change raises them.
5. **A second simulated person and two tasks shaped like the bad runs** (10 or more plan tasks; an environment fault;
   a person who sometimes chooses Change and asks for the fresh review), with a stated reading time per dialog.
6. **Re-run the two missing controls on the current model**: `careful-ask` on all tasks and `mutate.py` on current
   runs, about $10 to $15. They test whether Temper's two claimed advantages still exist.
7. **Keep `run.json` and `grade.json` beside each published table**, and generate the table by script.

---

## Appendix: the harness in one table `[code]`

| File | What it does | Lines |
|---|---|---|
| bench/run.mjs | one run: seeds a git repo from the task, runs an arm through the Agent SDK with no settings, answers every AskUserQuestion, resumes a Temper run up to 5 times, writes `run.json`, `person.jsonl`, `transcript.jsonl`, copies the session logs | 63-73, 150-191, 198-231, 238-268 |
| bench/person.mjs | the fixed-policy person | 11-34 |
| bench/person_llm.mjs | the Sonnet product owner of a vague task | 9-60 |
| bench/grade.py | hidden tests, the original suite, the diff against expected paths | 97-152 |
| bench/mutate.py | mutation score of the arm's own tests; regression caught for a bug | 122-165 |
| bench/report.py | means per arm and task | 41-105 |
| bench/tokens.py | tokens per model from the SDK results | 20-40 |
| bench/loop.py | the main session turn by turn, priced from session logs; `--summary`, `--check` | 34-38, 127-256 |
| bench/compare_models.py | the Haiku against Sonnet table; holds the per-agent-type cost and time functions | 29-48, 88-108, 111-140 |
| bench/combine.py | merges two results folders, renaming the older Temper arm | 17-45 |
| bench/run-all.sh | every task, arm and repetition, one at a time, then the report | 9-20 |
| scripts/e2e/cost_row.py | one row of `live-smoke.sh cost` (Plan stage with and without the fresh review) | 9-32 |
| scripts/usage_ops.py | the summary of `.temper/usage.json` (rows and ms by stage and model) and `--fill` | 16-58 |
| docs/history/tokenomics.md, pricing.md | v7 retired the runtime token levers, model routing tables and cost estimates; v8 gave back `models.{stage}` | tokenomics.md:8-42; pricing.md:8-16 |
| scripts/e2e/replay.ts, ab-replay.sh (GitHub PR head only) | scripted replay of the Java run on two versions; counts dialogs, launches, loops, repairs | replay.ts:192-198, 339-386; ab-replay.sh:13-39 |

Scratch work (clone, worktrees of `origin/main` and `10e965a`, prototypes):
`/tmp/claude-0/-home-user-temper/1ba4743b-465f-5ae6-8b88-a04ebb2fe840/scratchpad/work-evidence-bench`
(`proto/stages.py` is the 46 line per-agent prototype; `proto/trace.ts` counts dialogs and steps of an end to end scenario).
