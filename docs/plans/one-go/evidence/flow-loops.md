# Flow loops: every backward edge and every repeat in a Temper run

Subject: Temper 9.8.5, the head of PR #115 (commit `9a01eff`, branch `pr115`). All paths are relative to
`/home/user/temper`. Line numbers are of the PR head.

How each claim is marked:

- **[code]** read in the code at the cited line.
- **[ran]** measured by running the PR head's CLI in a throwaway project (the experiments are in section 10; the
  scripts are in `/tmp/claude-0/-home-user-temper/1ba4743b-465f-5ae6-8b88-a04ebb2fe840/scratchpad/work-flow-loops/exp*.sh`).
- **[doc]** only a claim in a document.
- **[inferred]** follows from the code but was not run.
- **[bench]** a number from `docs/evidence/bench-2026-11.md` as summarized in my brief (not derived again): Plan about
  200 s on Opus, Design about 100 s on Opus, each Build task agent 122 to 193 s, Intent, the acceptance writer and
  Review 30 to 45 s each.

## 1. The findings that matter most

1. **The budgets do not bound a run.** Only `state loop` is counted, per pair of stages, per run (`scripts/loop_step.py:20-32`).
   `state redo` (Run Build again, Revise the plan, Run Check again, a typed change), `group reopen`, `group fix`, the gate
   with twice the time, the small change window and `state set next_stage <earlier>` have no limit: nothing refuses
   the next one (`scripts/temper:1455-1492`, `2593-2796`, `913-935`; `fix_tries` in `scripts/group_fix.py:69` only
   moves the recommendation) [code] [ran: E2, E3]. `autonomy.budget.max-total-loops: 4` and
   `max-stages: 12` are shipped in the config (`templates/temper.config.default:151-153`) and read by no code; a run took
   10 steps back with the key set to 4 [ran: E4].
2. **Every repair is a launch of a clean agent.** A loop back, a redo, a task retry, a group fix and a record pass each
   start a new agent that reads the spec again (`scripts/flow.py:1119-1136`). The main session may write no file
   (`commands/temper.md:157-158`), and a failed task gate deletes the task's worktree before the next attempt
   (`scripts/temper:3150-3153`). Nothing is repaired in the context that made the fault.
3. **The two costliest loops are both avoidable by checks that could run earlier.** Build to Plan throws away every
   passed task (`scripts/temper:1277-1279`, `1297-1329`) and relaunches Plan and Design on Opus; Check to Build runs
   Review a second time for measures (coverage, mutation score, acceptance tests) that are plain CLI runs and are
   already started while Review reads (`scripts/flow.py:1375-1378`).
4. **A loop back to Build empties Build's ledger, so the Build gate asks for a new failing test whatever the finding
   was** [ran: E12]: `RED then GREEN: need >=1 failing test run (RED) and >=1 passing run (GREEN); have red=0 green=0`.
5. **The plan gate misses three faults that can only end in a Build to Plan loop** [ran: E6]: a group with no Validate
   command, an Interfaces entry in a file no task declares, a task traced to a scenario the intent does not have. The
   plan gate passes all three.
6. **PR #115's run policy (`autonomy.policy: decide`) has three defects** [ran: E1a to E1g]: it never launches the group
   fix agent it says it takes (it goes straight to a replan, which resets Build); it replans unattended, which
   `reference/autonomy.md:28,35` and `templates/temper.config.default:138-141` say an armed run never does; and after
   that replan the answer "Stage by stage" leaves the run armed.
7. **A loop back from a blocked task carries nothing** [ran: E11]: the Plan agent on Opus gets `Loop back from Build:
   The plan cannot be built.` The fact the CLI holds (which task needs which file, and who declares it) is in the
   question text only. That loop is the run's one Build to Plan step.

## 2. The mechanics every edge shares

### 2.1 Three ways back, and what each one clears

| Call | Counted? | What it does | Where |
|---|---|---|---|
| `temper state loop FROM TO --reason R` | Yes, per (FROM, TO) pair, for the whole run | `loop_step.step` counts it and keeps what FROM left open; then `_go_back TO` | `scripts/temper:1222-1262`, `scripts/loop_step.py:56-123` |
| `temper state redo STAGE --reason R` | No | Removes the verdict and skips of STAGE and every later stage; records `redo {stage, reason, ts}`; the run stays at STAGE, whose agent runs again | `scripts/temper:1455-1492` |
| `temper state set next_stage EARLIER` | No | `_go_back EARLIER` with no loop record and no findings kept | `scripts/temper:913-935` [ran: E3] |

`_go_back TO` (`scripts/temper:1269-1295`) [code]:

- truncates the evidence ledger of TO and of every later stage, Commit and Pipeline included (`_clear_evidence_downstream`,
  `scripts/temper:1876-1896`);
- when TO is intent, plan or design and a grouped Build exists, **resets the grouped run**: `groups.json` goes to
  `.temper/archive/`, clean worktrees are removed, the branches are moved to `refs/temper/kept/` (`_groups_reset`,
  `scripts/temper:1297-1329`). Nothing reads those kept branches back into the next Build (the only readers of the kept
  refs are `keep` and `tidy`, `scripts/task_ops.py:306-365`);
- grants the fresh review one more round once plan.md or tasks.md changes (`_fresh_grant`, `scripts/temper:1264-1267`);
- removes the verdicts of TO and every later stage from `gates.json` and moves their skips to the archive (`_redo_from`,
  `scripts/temper:1041-1092`);
- moves `next_stage`, counts a step, clears `parked` and any small change window (`_state_next`, `scripts/temper:995-1039`).

### 2.2 The budgets that exist

| Budget | Default | What it bounds | Where it is enforced |
|---|---|---|---|
| `loops.max-per-type` | 2 | Each (FROM, TO) pair of `state loop`, separately, for the whole run | `scripts/loop_step.py:20-32`, `68-71`; offered by `scripts/flow.py:318-321` |
| Build to Plan | 1, fixed | The pair (build, plan) | `scripts/loop_step.py:24-25` |
| `fix.max-loops` | unset (then `loops.max-per-type`) | The pairs (check, build) and (check, fix) | `scripts/loop_step.py:27-28` |
| `feedback.enabled` | true | false: the flow offers no loop back at all | `scripts/flow.py:319-320` |
| Task attempts | 3 (2 on the task model, 1 on the escalation model) | Attempts of one task before its group parks. `group reopen` sets the count back to zero | `scripts/temper:3151-3168`, `scripts/tasks_md.py:209-210`, reset at `scripts/temper:2761-2766` |
| `plan.fresh-review-rounds` | 3 | Launches of the fresh review, **plus one for each loop back or replan after which plan.md or tasks.md changed** | `scripts/fresh_review.py:91-100`, `342-362` |
| `ACC_MAX_LAUNCHES` | 2, fixed | Launches of the acceptance writer before Build; then the CLI records a skip | `scripts/check_run.py:625`, `scripts/flow.py:1407-1410` |
| `ACC_MAX_CORRECTIONS` | 2, fixed | Launches of the writer for one reopen of the lock | `scripts/check_run.py:626`, `scripts/flow.py:1521-1522` |
| Pipeline rounds | `loops.max-per-type` (2) | CI fix rounds | `scripts/flow.py:991-1009`, `1024-1025` |
| Environment agent | 1 per run | `state env_agent: tried` is never cleared | `scripts/flow.py:1200-1205`, `1224` |
| `temper go` steps | 60 | Mechanical steps in one `temper go` call; the same calls twice in a row stop it | `scripts/go.py:28`, `98-103` |
| `autonomy.budget.max-total-loops`, `max-stages` | 4, 12 | **Nothing.** No script reads them | `templates/temper.config.default:151-153`; `grep` finds them only in the config, the selftest fixture and `reference/status.md:104` [ran: E4] |

A pair's loop record stays in `active_loops` for the whole run, so a budget is never earned back (`scripts/loop_step.py:8-11`).
The CLI accepts any pair where TO comes before FROM (`scripts/temper:1226-1245`); the flow offers only the pairs of
`BACK_TO` (`scripts/flow.py:54-55`) and (commit, build) after a small change. `state loop commit intent` was accepted
[ran: E4]. With seven stages that is 21 pairs, each with its own budget of 2 (one of them 1): the CLI's own ceiling is 41
steps back, the flow's is 11.

### 2.3 What a step back carries

`loop_step.step` keeps at most 20 items in the loop record (`scripts/loop_step.py:114-120`) [code]:

- from Review: every finding not resolved or accepted, as `[severity] claim` cut at 300 characters (`:91-92`, `:115`);
- from Check: every run with a non zero exit, with the last 600 characters of its output, and a mutation score under
  the threshold (`:99-113`);
- from Plan: the open fresh review findings only (`:93-95`). The plan gate's failed deterministic rows live in
  `gates.json`, which the loop deletes, so they are **not** carried [inferred from `scripts/temper:1078-1080`];
- from Build: each group whose gate is FAIL (reason cut at 400, the count, five FAIL lines), then Build ledger rows with
  a non zero exit that are not RED or group runs (`:35-53`, `:96-99`). A parked group with no failed gate (a blocked
  task, three failed attempts) is not in it [ran: E11].

The reason is the person's answer to a second dialog whose ready answers are fixed texts: `The check found a real problem`
for a stage loop (`scripts/flow.py:586`, `593`), `The plan cannot be built` for Build to Plan (`:1853`, `:2005`, `:2107`,
`:2123`). So the reason usually says nothing, and the items above are all the next agent learns.

Who reads it: the stage the run goes back to gets `Loop back from X: reason` and `What X left open: ...`
(`scripts/flow.py:1349-1354`); each later stage the run passes again gets `Earlier loop back from X to Y: ...`
(`:1341-1348`); a Build fix pass gets `Feedback re-entry: reason`, each item cut at 200 characters, and the path of
`review-context.json` or `check-context.json` (`:1248-1277`).

### 2.4 What one more pass of each stage launches

| Stage pass | Agents launched | Model (default) | Time [bench] | Where |
|---|---|---|---|---|
| Intent | 1 Intent agent | sonnet (`agents/intent.md:4`) | 30 to 45 s | `scripts/flow.py:1374-1385` |
| Plan | 1 Plan agent; then, when the fresh review applies, 1 reviewer (2 at risk H) | opus (`agents/plan.md:4`); sonnet (`agents/plan-review.md:4`) | about 200 s for Plan | `scripts/flow.py:1374-1385`, `1279-1314`, `2424-2429`; `scripts/fresh_review.py:128-129` |
| Design | 1 Design agent | opus (`agents/design.md:4`) | about 100 s | `scripts/flow.py:1374-1385` |
| Build, first time | up to 2 acceptance writer launches; one agent per chain of tasks, up to 3 attempts a task | sonnet (`agents/acceptance.md:4`); haiku, or sonnet for a complex or risk H plan (`scripts/flow.py:1605-1610`) | 122 to 193 s per task agent | `scripts/flow.py:1394-1420`, `1698-1723` |
| Build, after a loop from Review or Check | 1 Build fix agent; possibly 1 record pass agent | sonnet (`agents/build.md:4`) | not in the summary I was given | `scripts/flow.py:1658-1672`, `2415-2423` |
| Review | 1 Review agent, on the whole change in a clean context (`agents/review.md:8`, `:60`) | sonnet | 30 to 45 s | `scripts/flow.py:1374-1385` |
| Check | none when the CLI finds a test command and no criterion is validated by code or metric; else 1 Check agent | sonnet | CLI run | `scripts/flow.py:1359-1373` |
| Pipeline | 1 Pipeline agent a round | sonnet | not measured | `scripts/flow.py:1328-1329` |

In an interactive run every stage pass also ends in its gate question, and every loop back option opens a second dialog
for the reason (`scripts/flow.py:475-480`, `commands/temper.md:150-153`).

## 3. Deliverable 1: every way a run goes backward or repeats work

"Person" means the person's choice in a `Temper gate` dialog. "Rule" means the CLI does it with no question. Costs are
the launches of section 2.4.

### 3.1 Stage loop backs (`state loop`, counted)

| # | Edge | Trigger (gate row or verdict) | Who decides | Budget | Carried to the stage it returns to | Launched again |
|---|---|---|---|---|---|---|
| L1 | Plan to Intent | Plan gate FAIL: any row (`scripts/flow.py:700-701`), or fresh review blockers (`:1065`), or the preflight's environment fault (`:697-699`). It is the only repair among the options of a failed Plan gate that is not fresh review related: there is no "Run Plan again" option there | Person | 2 | The reason; Plan's open fresh review findings. Not the failed gate rows (2.3) | Intent agent, Intent question, Plan agent on Opus, a fresh review round (earned), Plan question. About 230 to 245 s of agents plus two questions |
| L2 | Design to Plan | Design gate FAIL: `concerns flagged`, or **`tasks agree with decisions`** (new in the PR: a `Design:` answer was given and tasks.md is byte for byte unchanged, `scripts/decisions.py:53-69`), where it is the recommended option (`scripts/flow.py:733-739`). Also offered at a passed Design under More options (`:731`) | Person (an armed run parks at Design, `:2443-2453`) | 2 | The reason; Design ledger rows with a non zero exit (normally none) | Plan agent on Opus, fresh review round, Plan question, **Design agent on Opus again**, the Design questions, Design question. About 300 s of Opus |
| L3 | Build to Plan | (a) tasks with no groups (`scripts/flow.py:1621-1633`); (b) a covered task (`:1851-1853`); (c) a group check FAIL: recommended after a fix did not help, or from the second failure with no fix possible (`:2000-2005`); (d) a parked group: recommended when a task is blocked (`:2094-2112`) or the group parked again after a rerun (`:2117-2128`); (e) the Build gate question, passed or failed (`:752`, `:763-765`) | Person. Under the policy, the CLI takes (c) by itself (5.2) | 1 for the run | Failed group checks with count and FAIL lines; failing Build runs. Not the blocked record [ran: E11] | Plan on Opus, fresh review round, Plan question, Design on Opus, Design question, then **every task again** (the grouped run is reset): T task agents at 122 to 193 s each. The acceptance tests stay locked (their lock file is not a ledger the loop clears, `scripts/flow.py:1387`, `scripts/temper:1892-1895`) |
| L4 | Review to Build | Review gate FAIL: `no blocking findings` (open critical or high, `scripts/temper:3823-3837`), recommended (`scripts/flow.py:795`); or `no code changed at Review` (`scripts/temper:3847-3856`). At a passed Review with an open finding at medium or above it is also the recommended option (new in the PR, `scripts/flow.py:779-784`) | Person; under the policy, a rule (`:1166-1172`) | 2 | The reason; each open finding; `review-context.json` | Build fix agent (sonnet), maybe a record pass agent, the Build question, a full Review agent, the Review question, Check again. Four dialogs: the option, its reason, the Build question, the Review question |
| L5 | Check to Build | Check gate FAIL on `tests pass`, `scenarios traced to tests`, `coverage >= threshold` (a real shortfall), `mutation score >= threshold`, `acceptance evidence`, or the locked acceptance tests when the triage says the code is wrong (`scripts/flow.py:864-875`). Offered, not recommended, at a passed Check (`:817`), a SETUP fault (`:851`) and a missing measurement (`:863`) | Person; under the policy, a rule (`:1173-1180`) | 2 (`fix.max-loops` when set) | The reason; failed runs with 600 characters of output; surviving mutants; `check-context.json`; the locked acceptance tests notice (`:1263-1269`) | Build fix agent, maybe a record pass, Build question, Review agent, Review question, Check run, Check question. Five dialogs |
| L6 | Check or Commit to Build after a small change | The Review of a small change made at Check or Commit failed (`scripts/flow.py:976-989`, `2372-2373`) | Person | (check, build) shares L5's count; (commit, build) has its own 2 [ran: E4] | As L4 | As L5 |
| L7 | Fix run: Review to Fix, Check to Fix, Commit to Fix | The same rows, in a `/temper:fix` run (`scripts/flow.py:55`, `2266-2268`) | Person | 2; (check, fix) takes `fix.max-loops` | As L4 and L5 | Fix agent, Review agent, Check |
| L8 | Any other pair | Not offered by the flow; the CLI accepts it (`scripts/temper:1226-1245`) [ran: E4]. `state set next_stage EARLIER` goes back uncounted [ran: E3] | Whoever runs the call (the mod's guard is another reader's subject) | 2 a pair; none for `state set` | For `state set`: nothing | Every stage from there |

### 3.2 The same stage again (`state redo`, never counted)

| # | Repeat | Trigger | Who decides | Budget | Carried | Launched again |
|---|---|---|---|---|---|---|
| R1 | Replan: `state redo plan` | "Revise the plan" at a failed fresh review (`scripts/flow.py:1055-1059`) or at a passed Plan with lesser findings (`:666-669`); the Context check answers "Include what is left out" and "Something else" (`:2317-2320`, `scripts/temper:4592-4596`); any typed change at Plan (`commands/temper.md:154-160`) | Person | None. Each replan that changes the plan also earns a fresh review round: 8 rounds ran with the limit at 3 [ran: E5] | The open fresh findings in the Plan prompt (`scripts/flow.py:1330-1334`); the person's note | Plan agent on Opus (about 200 s) and 1 or 2 reviewers, each time |
| R2 | "Run Build again", "Change something": `state redo build` | Build gate FAIL (`scripts/flow.py:755-765`); a passed Build the person wants changed (`:746-748`); a typed change at Build | Person. The recommendation moves to Save for later when the same failure returns (`:756-763`); it is still offered | None [ran: E2] | The failed rows (300 characters) as the reason; the integrate verdict and the gate's failed rows (`:1236-1246`) | Build fix agent. With nothing that names a fault, no agent: `integrate` and `gate build` run again (`:1660-1664`) |
| R3 | "Run Review again": `state redo review` | The Review gate fails only on `review completed` (`scripts/flow.py:794-798`) | Person | None | Nothing | Review agent |
| R4 | `state redo check` | "Run Check again" for a missing measurement (`scripts/flow.py:857-858`); "Repair the environment and run again" (`:841-843`); after the proposed setup block (`:848`); after the locked tests are restored (`:1500-1501`); after the writer corrected a test (`:1536`); after the environment agent (`:1220-1221`) | Person, except the two that follow an agent | None | The reason text | The Check run by the CLI; a Check agent only when section 2.4 says so |
| R5 | `state redo STAGE` of a walked stage | A door run entered at a later stage and an earlier stage's check fails (`scripts/flow.py:609-614`) | Person | None | The failed rows | That stage and every stage after it |
| R6 | `state redo pipeline` | A result that is not final (`scripts/flow.py:1020-1023`); after each CI fix round (`:1030-1032`) | Person | Fix rounds: 2. Reading again: none | The round number | Pipeline agent |
| R7 | A typed change at Intent or Design | `commands/temper.md:158-160`; a note newer than the verdict also relaunches the stage (`scripts/flow.py:2400-2410`) | Person | None | The note as `Person's note:` | That stage's agent (Design: Opus) |

### 3.3 The fresh review of the plan

| # | Repeat | Trigger | Who decides | Budget | Launched |
|---|---|---|---|---|---|
| F1 | First round | `plan.fresh-review` is `ask` by default: only when the person picks "Fresh review first" (`scripts/flow.py:1039-1042`, `scripts/fresh_review.py:117-125`); `auto` for medium and complex; `always` | Person (ask) or rule | Rounds | 1 reviewer; 2 at risk H unless `fresh-review-twice: false` |
| F2 | Next round, by itself | intent.md, plan.md or tasks.md changed after the launch (`scripts/fresh_review.py:218`, `277-279`; `scripts/flow.py:2424-2429`) | Rule | Rounds | The same; a recheck round reads only the earlier findings and the changed task blocks (`scripts/fresh_review.py:165-190`) |
| F3 | "Run the fresh review again" | A reviewer recorded no completion row or a short paraphrase (`scripts/flow.py:1051-1054`) | Person | Rounds (it takes one) | The same |
| F4 | One more round | Each loop back to Intent, Plan or Design, and each replan, once plan.md or tasks.md changed (`scripts/fresh_review.py:91-100`, `368-372`) | Rule | **No ceiling** [ran: E5] | The same |

### 3.4 Repeats inside Build

| # | Repeat | Trigger | Who decides | Budget | Carried | Launched again |
|---|---|---|---|---|---|---|
| B1 | Task retry | Task gate FAIL on attempt 1: no green run, a RED that did not fail on an assertion, a RED on the final code, a final run that is not green, a scenario test the task owes fails, an undeclared change (`scripts/task_ops.py:669-775`) | Rule | Attempt 2 of 3 | `PREVIOUS ATTEMPT` in `task show`; **the worktree is deleted** (`scripts/temper:3150-3153`) | A new task agent on the task model |
| B2 | Task escalation | Task gate FAIL on attempt 2 (`scripts/temper:3181-3182`) | Rule | Attempt 3 of 3 | The same | A new task agent on the escalation model (sonnet) |
| B3 | Group park, then "Run the task again" | Attempt 3 fails; a commit the CLI did not make (parks at once); a blocked task (parks at once, `scripts/temper:3147-3149`); a task that cannot be merged (`:3225-3243`) | Person (`scripts/flow.py:2067-2129`) | None: `group reopen` sets attempts back to zero (`scripts/temper:2761-2766`) | The attempts move to `attempts_prior` | Up to 3 more agents for each parked task |
| B4 | Covered task: "Run it again" | The RED run passed before any change (`scripts/temper:3122-3127`) | Person (`scripts/flow.py:1848-1855`); an armed run accepts it as done (`:1837-1842`) | None | Nothing | One task agent |
| B5 | Environment fault at a task gate: "Check it again" | The last run is a failing GREEN whose output names an environment fault (`scripts/task_ops.py:758-767`, new in the PR) | Person, in every mode (`scripts/flow.py:1857-1870`) | None; no attempt is spent | The work and the attempt are kept | No agent: `task test N --phase green` and `task gate` |
| B6 | Group check: "Run the gate again with twice the time" | Exit 124 of the Validate run (`scripts/flow.py:1990-1995`) | Person; recommended at the first time-out only | None (the limit doubles each time) | Nothing | No agent |
| B7 | Group check: "Fix the group's merged work" | Group gate FAIL after every task passed and the check ran (`scripts/flow.py:1983`, `1996-1999`) | Person; recommended once (`fix_tries`, `scripts/group_fix.py:69`) | None in code | The gate's reason and eight FAIL lines (`scripts/flow.py:2048-2065`) | One Build fix agent (sonnet) on the merged tree; then the group gate. A fix that changed nothing keeps the gate failed (`scripts/group_fix.py:79-86`) |
| B8 | Group check: "Run the group's tasks again" | Group gate FAIL; recommended only at the first failure when no fix is possible (`scripts/flow.py:2001-2002`) | Person | None | Nothing; every task's files are reverted | Every task of the group, up to 3 attempts each |
| B9 | Group check: "Change the group's command" (plan patch, new in the PR) | Recommended after a second time-out or an empty fix (`scripts/flow.py:2021-2034`) | Person, who types the command | None; spends no loop (`scripts/plan_patch.py:8-11`) | The passed tasks keep their work | No agent: the group gate runs again |
| B10 | Passed group: "Change" | The person's feedback at the group question (`scripts/flow.py:1928-1949`) | Person | None | `feedback #K` rows | The named task and each task that depends on it and shares a file (`:1901-1926`) |
| B11 | Fix pass after a loop back or a redo | L4, L5, R2 | Rule | By the edge that caused it | Section 2.3 | One Build fix agent |
| B12 | Record pass | The Build gate fails only on `criteria validated` rows with no CLI row (`scripts/flow.py:197-214`, `2415-2423`) | Rule | Once a round (`record_pass`) | The rows to record | One Build agent that writes no code |
| B13 | Integrate again | "Merge the groups" after foreign commits are kept or taken out (`scripts/flow.py:1799-1802`); HEAD moved since the last pass (`scripts/temper:3316-3327`) | Person; rule | None | Nothing | No agent |
| B14 | Acceptance writer again | The writer locked nothing (`scripts/flow.py:1404-1410`) | Rule | 2 launches, then a recorded skip | Nothing | The writer (sonnet) |

### 3.5 Repeats inside Plan and Check

| # | Repeat | Trigger | Who decides | Budget | Launched |
|---|---|---|---|---|---|
| P1 | Preflight again with a setup block | The `preflight` row fails on the environment and the config has no `setup:` block (`scripts/flow.py:693-699`, `1183-1205`) | Person, one click | Rule based block: until it was tried and failed. Agent: once a run | No agent for the proposed block; one environment agent (sonnet) when no rule fits (`:1207-1227`) |
| P2 | Context check | The map's `reviewed:` line is pending (`scripts/flow.py:2305-2346`) | Person | None | "As planned": the gate only. Any other answer is R1 |
| C1 | Acceptance triage | Check fails only on the locked acceptance tests (`scripts/flow.py:1465-1485`) | Rule; not in an armed run (`:1471`) | Once for each distinct failure | One agent (sonnet) that changes nothing |
| C2 | "Correct the acceptance test" | The same row; recommended when the triage says the test is wrong, or after one loop to Build (`scripts/flow.py:1504-1511`) | Person | 2 writer launches for each reopen; reopens are not counted | The writer, then R4 |
| C3 | "Restore the locked tests" | A builder changed a locked test (`scripts/flow.py:1499-1501`) | Person | None | No agent; R4 |
| C4 | "Confirmed" | A criterion validated by hand has no row (`scripts/flow.py:826-836`) | Person | None | No agent; the gate |

### 3.6 Other repeats

| # | Repeat | Trigger | Who decides | Budget | Launched |
|---|---|---|---|---|---|
| A1 | "Make a small change" | Offered at the Build, Review, Check and Commit questions (`scripts/flow.py:905-952`) | Person | None | The main session edits. After a change at Review: a Review agent on the changed files. At Check or Commit: that Review agent, a Check agent and the commit gate. At Build or docs only: the stage's gate (`scripts/adhoc_ops.py:100-111`, `scripts/flow.py:954-974`) |
| PL1 | CI fix round | The Pipeline result is red (`scripts/flow.py:1026-1037`) | Person | 2 rounds | The main session applies the fix list and pushes; the Pipeline agent reads the checks again |
| K1 | Park of an armed run | Section 5 | Rule | Each park ends the unattended run | No agent. `temper park` sets the run interactive (`scripts/temper:4520`); the gate's own question follows |

## 4. Deliverable 2: is the cause knowable before Build by a deterministic check?

### 4.1 The checks that exist before Build

All are rows of `temper gate plan` (`scripts/temper:3494-3605`), so the Plan agent, which runs the gate itself before it
returns (`agents/plan.md:60`), repairs them in its own context. That is the one working case of repair inside a stage.

| Row | What it catches | Where |
|---|---|---|
| `grouped plan`, `declared files`, `exact file paths`, `dependencies` | A plan with no groups, a task with no file, a glob, a cycle, a task that depends on a task of a group its group does not depend on | `scripts/plan_rows.py:14-26`, `53-98` |
| `task test command` | A task with no Test command, or one whose test path the task does not declare and the project lacks | `scripts/plan_rows.py:27-43` |
| `task test cases` | Fewer than two cases | `scripts/plan_rows.py:44-46` |
| `file ownership` | Two tasks that can run together declare the same file | `scripts/plan_rows.py:99-123` |
| `group validate order` (9.8.4) | A group's Validate runs an existing file that a task of a group not yet on its worktree edits | `scripts/plan_rows.py:130-175` |
| `shared production files` (9.8.4) | More than two tasks of one group declare one production file | `scripts/plan_rows.py:176-194` |
| `integration command` | No Integration line | `scripts/plan_rows.py:195` |
| `scenario test commands` | A scenario with no `Test:` line, or a test file no task declares and the project lacks | `scripts/gate_rows.py:105-133` |
| `maven group verify`, `maven filtered verify` (the second new in the PR) | A Maven group that does not validate with `verify` and JaCoCo; a filtered `verify` under a JaCoCo bundle rule | `scripts/gate_rows.py:136-191` |
| `request routes kept` | A route the request names that the plan does not | `scripts/gate_rows.py:263-296` |
| `preflight` (new in the PR) | Every Validate, Test, Integration and scenario command run once on HEAD: an environment fault (setup line failed, time limit, JDK out of range, class file version, connection refused, program not found, offline dependency) or a command fault (five patterns, and tests pass with `BUILD FAILURE`) | `scripts/preflight.py:34-37`, `73-115` |
| `tasks agree with decisions` (Design gate, new in the PR) | A Design answer given while tasks.md has not changed. A proxy: it compares a hash and cannot read whether a task holds the old rule | `scripts/decisions.py:53-69` |

### 4.2 Each trigger against those checks

| Trigger | Knowable before Build by a deterministic check? | Check that exists | What is missing |
|---|---|---|---|
| A command that cannot pass (L3 by way of B6, B7, B9) | Yes | `preflight` command fault; the two Maven rows | **The default class is `needs new code`** (`scripts/preflight.py:111-115`): any failure on HEAD that matches no pattern passes the row. A suite already red on HEAD, or a Validate that fails for a reason no pattern names, is found only at the group gate. Missing: compare what failed on HEAD with the files the plan declares (a failing test in a file no task touches is a fault of the base) |
| An environment fault (B5, P1, R4) | Yes | `preflight` environment fault; the `setup:` block; the `ENV` task verdict; SETUP at Check | Nothing found. One note: the preflight runs inside whichever call first runs `gate plan`, which is the Opus Plan agent's own gate run (`agents/plan.md:60`), up to 300 s a command [inferred] |
| A plan that splits a file over tasks (B7, B8, then L3) | Yes | `shared production files`, `file ownership` | Two tasks on one file are allowed. The same file in two ordered groups is not counted (the row counts within one group, `scripts/plan_rows.py:185-193`) |
| A group that cannot pass its own Validate (the 9.8.4 run) | Yes | `group validate order` | Only files that exist now count (`scripts/plan_rows.py:171`); a new test file written by a later group is not seen |
| **A group with no Validate command** | Yes | **None.** The plan gate passes it [ran: E6] | A row. At Build the group gate fails with `declares no **Validate:** command` (`scripts/temper:2481-2482`), the recommended answer is "Run the group's tasks again" [ran: E6b], and "Change the group's command" cannot help: `plan patch` needs an existing Validate line (`scripts/plan_patch.py:70-77`) |
| **An interface no task builds** | Yes | **None before Build.** `ifcheck` runs inside `temper integrate`, after every group is built (`scripts/temper:3424-3429`, `scripts/task_ops.py:516-522`) | A plan gate row: each Interfaces path is a file some task of that group declares, or exists. The plan gate passed an entry in a file no task declares [ran: E6] |
| **A scenario owned by the wrong task** | Mostly | Not a check, a rule: `owners()` moves the scenario to the task that writes its test file, or to the group gate (`scripts/scenario_ops.py:74-98`) | A row for a `Traced to:` name the intent does not have, and for a scenario no task is traced to. The plan gate passed a task traced to a name the intent lacks [ran: E6]; such a scenario is owed by nobody, runs first at integrate, and a failure there fails the Build gate (`scripts/temper:3419-3423`) |
| A task whose test needs a file it does not declare (blocked, then L3) | Partly | `task test command` checks the test path only | What the test imports is not read. Today the agent finds it and runs `task blocked` (`scripts/task_blocked.py:47-65`), and the only repair offered is L3 |
| A covered task (B4, L3) | No, not without running code | None | Not determinable from the plan alone |
| A wrong acceptance test (C1, C2, L5) | Not whether it is wrong. That it fails: yes, at the end of Build | The locked tests run **only at Check** (`scripts/check_run.py:656-674`; `acc_run` has no other caller) | Run the locked command at `temper integrate`. Today the first failure is seen after Review, and its repair can take Review a second time |
| Coverage or mutation score under the threshold (L5) | Not before Build. At the end of Build: yes | Measured only at Check (`scripts/temper:3904-3931`); `check ahead` starts the same run when Review starts (`scripts/flow.py:1375-1378`) | The same measures at the Build gate, so the fix pass repairs them before Review |
| A Design answer the tasks do not follow (L2) | Yes, as a proxy | `tasks agree with decisions` | The row only detects. The repair it recommends is the loop to Plan; nothing applies the answer to tasks.md in place |
| Review findings (L4) | No | None can exist: the finding is a model's reading of code not yet written | A Build task agent gets the plan review's medium and low notes (`scripts/flow.py:1590-1603`), nothing else |
| Three failed attempts of a task (B3) | No | None | Section 6.1 |

## 5. Deliverable 3: the armed run, and `autonomy.policy: decide`

### 5.1 The armed run with no policy (as on `origin/main`)

Only the person arms a run, at the last question before Build: the Plan question when no Design follows, else the
Design question (`scripts/flow.py:670-675`, `726-728`). What the CLI then does by itself [code]:

| Situation | Armed run | Where |
|---|---|---|
| A group passed | Continues (the group question is skipped) | `scripts/flow.py:1759-1760` |
| A covered task | Accepts it as done | `scripts/flow.py:1837-1842` |
| Build gate PASS | Advances to Review and turns interactive | `scripts/flow.py:2454-2462` |
| Group check FAIL | Park | `scripts/flow.py:1973-1977` |
| A parked group (three failed attempts, a blocked task, a foreign commit) | Park | `scripts/flow.py:2074-2077` |
| Foreign commits found at integrate | Park | `scripts/flow.py:1795-1798`, `1806-1809` |
| A manual task | Park | `scripts/flow.py:1890-1893` |
| Build gate FAIL (integration, criteria) | Park; no fix pass by itself | `scripts/flow.py:2464-2467` [ran: E10] |
| A task's environment fault | **A question, not a park**: no report is written, the run just waits | `scripts/flow.py:1857-1870` [ran: E9] |
| Tasks with no groups | A question | `scripts/flow.py:1621-1633` |
| Review, Check | The ordinary questions (the run is interactive again) | `scripts/flow.py:2441` |
| Commit | Always a park, also on a PASS | `scripts/flow.py:2227-2231` |

A park runs `temper park`, which sets `run_mode interactive` (`scripts/temper:4520`). Nothing arms a run again but the
Plan and Design questions (`scripts/flow.py:675`, `728` are the only calls that set `autonomous`). So **the first park
ends the unattended run for good**: after it, each passed group of a plan with two or more groups asks "Continue?"
again (`scripts/flow.py:1758-1766`) [inferred].

### 5.2 What the policy changes (new in PR #115)

`autonomy.policy: decide` in the config (`scripts/flow.py:296-298`). The run stays armed after Build
(`scripts/flow.py:2457-2461`), and Review and Check give an `auto` action in place of the question (`:2468-2472`).

| Edge | With the policy | Still parks for the person |
|---|---|---|
| L4 Review to Build | By rule when a finding at medium or above is open, the findings as the reason (`scripts/flow.py:1166-1169`) | When the (review, build) budget is spent (`:1158-1159`); when Review fails with no such finding (`:1172`) |
| L5 Check to Build | By rule on any other failed Check (`scripts/flow.py:1180`) | A SETUP fault (`:1176-1177`); a missing measurement or a failed acceptance test (`:1178-1179`); a spent budget |
| Review PASS, Check PASS | Advance by rule (`scripts/flow.py:1164-1165`, `1170-1171`, `1174-1175`) | The commit, always (`:2227-2231`) |
| B6 twice the time | By rule, at the first time-out (`scripts/flow.py:1963-1972`) | |
| B7 group fix | The CLI runs `group fix G` by itself, **but the agent is never launched** (5.3, defect 1) | |
| B8 run the group's tasks again | By rule, at the first failure when no fix is possible | |
| L3 Build to Plan | **By rule** (`scripts/flow.py:1966-1972`, the recommended option's call) [ran: E1b, E1c]. Plan then runs on Opus unasked, and the run stops at the Plan question with no park and no report [ran: E1c, E1f] | Only when the budget is spent (then Save for later is recommended, which parks) |
| B9 change the group's command | No: it needs a typed answer (`scripts/flow.py:1968`) | Park |
| B3 a parked group, B5, a manual task, foreign commits | As without the policy | Park (B5: a question) |
| Build gate FAIL | As without the policy [ran: E10] | Park |
| R1, R2, R4 (`state redo`) | Never taken by the policy | |
| Overrides, accepted findings | Never (`scripts/flow.py:1146-1147`; `scripts/selftest/temper-cases-28.sh:26`) | |

The policy removes at most these dialogs from a run that goes well: the Build question, the Review question, the Check
question, and for each loop back the option and its reason. It adds no new repair: every repair is still a loop back
that relaunches a clean agent.

### 5.3 Defects in the policy, each seen by running the PR head

1. **The group fix agent is never launched in an armed policy run.** The policy runs `group fix G1`, which records the
   request and sets `fix_tries` to 1 (`scripts/group_fix.py:68-69`). The next action launches the agent only when the
   run is not armed: `if gate == "FAIL" and ginfo.get("fix") and not r.armed()` (`scripts/flow.py:1754`). So the flow
   falls to `group_failed`, which now sees a fix already tried and recommends the loop back to Plan, and the policy
   takes it. Seen: `the policy takes "Fix the group's merged work"`, then, with no agent between, `the policy takes
   "Loop back to Plan"`, then `OK: grouped run reset for the re-plan` [ran: E1a to E1c]. The selftest asserts the first
   call only (`scripts/selftest/temper-cases-28.sh:40-41`). Effect: one failed group check in an unattended policy run
   discards the whole Build and spends the run's one Build to Plan step, with no attempt at a fix.
2. **The policy replans unattended.** After that loop the next action is `work`: the Plan agent on Opus, mode
   `autonomous`, no park, no `autonomy-report.md` [ran: E1c]. `reference/autonomy.md:28` says "Build never loops back to
   Plan by itself", `:35` says it "never plans again by itself", and `templates/temper.config.default:141` says "NEVER
   re-plans unattended". `docs/flow.md:232-233` says the policy does take a loop back to Plan. The documents disagree
   with each other; the code follows `docs/flow.md`.
3. **"Stage by stage" does not disarm.** At the Plan question that follows, the run is still armed, and the calls of
   "Stage by stage (Recommended)" are the spec branch, the spec commit and `state advance plan_complete build`: none
   sets `run_mode interactive` [ran: E1g]. The person who answers "every later stage keeps its own gate" gets an armed
   Build.

## 6. Deliverable 4: where a repair could happen inside the stage, and what forces a transition today

### 6.1 A failed task attempt (B1, B2)

- Today: the task agent runs its own gate (`agents/build-task.md:13-15`) and must stop when it fails. The gate has
  already recorded the failed attempt and deleted the worktree (`scripts/temper:3150-3160`). The next attempt is a new
  agent in a new worktree, told what failed in a `PREVIOUS ATTEMPT` block.
- What forces it: the gate is the only call that tells the agent the verdict, and it spends the attempt in the same
  call. The verdict itself is a pure read: `task_ops.py verdict` prints JSON and changes nothing (`scripts/task_ops.py:669-775`).
- Inside the stage: a check call that returns the verdict without spending the attempt (the same `verdict` mode), so
  the agent that knows the code mends what the verdict names (an undeclared change, a scenario test under the wrong
  name, a final run that is not green) and gates once. The attempt counter stays as the bound.

### 6.2 Review findings (L4)

- Today: the stage transition clears the Build, Review and Check ledgers (`scripts/temper:1275`). The Build gate then
  needs a new RED and GREEN run by the CLI and the scenario rows again [ran: E12]. Then the Build question, a full
  Review in a clean context, the Review question.
- What forces it: Review writes no code (`scripts/temper:3847-3856`); `BACK_TO` is the only repair the flow recommends
  (`scripts/flow.py:54-55`); the loop clears every later ledger.
- Inside the stage: the flow already has the shape, in the small change window: a change made at Review is followed by
  a Review agent on the changed files only (`scripts/flow.py:960-965`, `scripts/adhoc_ops.py:109-110`). A repair action
  at Review could launch the Build fix agent with the findings, keep Build's ledger and verdict, and review only the
  fix. Today the window is offered under More options [ran: E8], is carried out by the main session and records no
  test first.

### 6.3 Check failures (L5)

- Today: the suite, coverage, the scenario tests, the locked acceptance tests and the mutation score are first measured
  at Check (`scripts/check_run.py:678-749`), after Review. A shortfall goes Check, Build, Review, Check.
- What forces it: the rows are in `gate_check` (`scripts/temper:3862-3972`); `gate_build` reads none of them (`:3613-3716`).
- Inside the stage: they are CLI runs with no model. Run them at the end of Build (with `temper integrate`), so the
  Build fix pass repairs a shortfall before Review is spent. A pass on the same clean tree is already reused
  (`scripts/run_env.py:123`, `150-165`), so Check on an unchanged tree would cost little.

### 6.4 A plan the build proves wrong (L3)

- Today: any change to tasks.md's File, Depends or Test lines, or to a group's Validate, Interfaces or Context, makes
  `group gate`, `group reopen`, `integrate` and `task start` refuse: "the approved plan changed ... loop back to Plan"
  (`_plan_fresh`, `scripts/temper:2176-2196`). The loop resets the grouped run (2.1).
- What forces it: one digest for the whole plan (`scripts/temper:2163-2174`) and a reset that keeps no task.
- Inside the stage: `temper plan patch` already changes one command line, moves the approved hash, keeps the passed
  tasks and spends no loop (`scripts/plan_patch.py:109-127`). The same for a task's files (a blocked task that needs
  one more file, a test that belongs to another task) would keep every task whose block did not change; a digest per
  task block exists already (`scripts/fresh_review.py:146-162`) and so does the set of tasks that must rerun with one
  (`scripts/flow.py:1901-1926`).

### 6.5 Fresh review findings and typed changes at Plan (R1)

- Today: the reviewer is launched after the Plan agent returned and its gate ran (`scripts/flow.py:2424-2429`). Each
  finding the person sends back, and each typed change, relaunches Plan on Opus in a clean context (`:1330-1334`,
  `commands/temper.md:158-160`), and each changed plan is reviewed again.
- What forces it: the main session may write no spec file; the stage's agent is the only writer.
- Inside the stage: the CLI already tells a note the next agent must read (`kind: input`) from a change already made,
  which only runs the gate again (`kind: edit`, `scripts/flow.py:2411-2414`). A small edit of plan.md or tasks.md by a
  cheap agent, recorded as `edit`, would rerun the gate and a recheck round without the Opus pass.

### 6.6 A Design answer (L2)

- Today: the person answers a `Design:` question after the Design agent returned; the new row then fails until tasks.md
  changes, and the recommended answer is the loop to Plan: Plan and Design both run again on Opus.
- What forces it: `scripts/decisions.py:60-69`, `scripts/flow.py:733-739`.
- Inside the stage: Design may already change tasks.md, and Continue approves the changed tasks (`scripts/flow.py:719-725`,
  `scripts/temper:1181-1211`). Applying the answer to the tasks at Design (the Design agent again with the answer, or a
  task patch as in 6.4) needs no Plan pass.

### 6.7 What is already repaired inside its stage

The plan gate's deterministic rows (the stage agent runs its own gate first: `agents/plan.md:60`, `agents/design.md:24`,
`agents/intent.md:141`, `agents/build.md:89`, `agents/check.md:54`); the group fix on the merged tree (B7); the plan
patch (B9); the environment fault at a task (B5); SETUP at Check (R4); the acceptance correction (C2). All but the first
are new in 9.8.4 or in this PR, and each replaced a loop back.

## 7. Deliverable 5: the worst case the default budgets allow

### 7.1 There is no finite worst case in an interactive run

R1 to R7, B3, B7, B8, B10 and A1 have no counter (section 3). Each is the person's choice, one dialog at a time, and
the flow stops recommending most of them after the first repeat, but nothing refuses the tenth. Measured: six "Run
Build again" in a row, each accepted [ran: E2]; eight fresh review rounds with the limit at 3 [ran: E5].

### 7.2 Using only the counted loops, each to its limit

Defaults: `loops.max-per-type` 2, Build to Plan 1, three attempts a task, fresh review requested, risk H (two
reviewers), a plan with a Design stage and T tasks, no uncounted repeat.

A stage is passed once, plus once for each loop that starts at or after it and ends at or before it [inferred from the
stage sequence, `scripts/flow.py:47`]:

| Stage | Passes | From |
|---|---|---|
| Intent | 3 | 1 + Plan to Intent 2 |
| Plan | 6 | 1 + Plan to Intent 2 + Design to Plan 2 + Build to Plan 1 |
| Design | 4 | 1 + Design to Plan 2 + Build to Plan 1 |
| Build, every task | 2 | 1 + Build to Plan 1 |
| Build, fix pass | 4 | Review to Build 2 + Check to Build 2 |
| Review | 5 | 1 + 2 + 2 |
| Check | 3 | 1 + Check to Build 2 |

Launches:

| Agent | Count | Model |
|---|---|---|
| Intent | 3 | sonnet |
| Plan | 6 | opus |
| Fresh reviewers | 12 (6 rounds: 3, plus one earned by each of the last three plan passes; two reviewers each) | sonnet |
| Environment agent | 1 | sonnet |
| Design | 4 | opus |
| Acceptance writer | 2 | sonnet |
| Build task agents | 6 × T (3 attempts a task, two full Builds) | haiku or sonnet, then sonnet |
| Record pass | 5 (one for each round of Build: the first and four loops) | sonnet |
| Build fix pass | 4 | sonnet |
| Review | 5 | sonnet |
| Check agent (only when section 2.4 says one runs) | 3 | sonnet |
| Acceptance triage | 3 (one for each Check pass, at most) | sonnet |
| Acceptance correction | 2 (one reopen) | sonnet |
| Pipeline | 3 (the first reading and two fix rounds) | sonnet |
| **Total** | **53 + 6 × T** | |

For T = 8 that is 101 launches; for T = 12 (the group size of the 9.8.4 run, `CHANGELOG.md:72-73`) it is 125. Ten of
them are on Opus: at the bench's 200 s and 100 s that is about 1,600 s of Opus agent time, against about 300 s in a
run with no loop [inferred from the bench numbers]. Without the fresh review (the default is `ask`) the total is
41 + 6 × T. The (commit, build) pair after a small change adds 2 fix passes, 2 Reviews and 2 Check passes.

Steps back in that run: 9 (11 with the commit pair). The config's `max-total-loops: 4` does not stop the fifth [ran: E4].

### 7.3 An armed run under the policy, from arming to the commit park

No question is asked. Acceptance writer 2, task agents 3 × T, record pass 5, fix pass 4, Review 5, Check agent 3:
**19 + 3 × T** launches at most before the park at Commit, if no group check fails. With a failed group check the run
goes to a replan instead (5.3).

## 8. Where the documents and the code disagree

| Document | Says | Code |
|---|---|---|
| `reference/autonomy.md:15-16`, `:25-26` (not changed by the PR) | The unattended part is Build alone; after Build every gate is the person's | With `autonomy.policy: decide` the run stays armed through Review and Check (`scripts/flow.py:2457-2472`). The page does not mention the policy |
| `reference/autonomy.md:28`, `:35`; `templates/temper.config.default:138-141` | Build never loops back to Plan by itself; an armed run never plans again by itself | The policy does both [ran: E1c] |
| `docs/flow.md:230-231` | "A loop back happens only while `loops.max-per-type` and the autonomy budget last" | No autonomy budget is read anywhere; only `loops.max-per-type` (`scripts/flow.py:1158`) |
| `docs/flow.md:231-233` | Under the policy a failed group check takes "a fix agent" by itself | The agent is never launched (`scripts/flow.py:1754`) [ran: E1b] |
| `templates/temper.config.default:107` | `fresh-review-rounds: 3  # launches of the fresh review in one run, at most` | Plus one for each loop back or replan that changed the plan, with no ceiling (`scripts/fresh_review.py:91-100`) [ran: E5]; `docs/flow.md:107-113` does say so |
| `templates/temper.config.default:133-136` | "With this block absent or enabled: false, the plan gate offers only the ordinary stage-by-stage continuation" | `autonomy.enabled` is not read (`scripts/flow.py:300-303`); line 144 of the same file says so |
| `templates/temper.config.default:151-153` | `budget: max-total-loops: 4, max-stages: 12` | Dead keys |
| `reference/orchestrator-patterns.md:152-154` | Build to Plan is "Human-driven only" | The policy takes it by rule |
| `docs/flow.md:124-126` | "following the recommendation always ends" | True for a group check. But the recommended chain can end in a replan that resets Build, which is the costliest end |

## 9. Proposals, most valuable first

1. **Complete the plan gate, so no plan fault reaches Build.** Rows for: a group with no Validate; an Interfaces path
   no task of the group declares and the project lacks; a `Traced to:` name the intent lacks and a scenario no task is
   traced to; a failure on HEAD in a test file no task declares (a red base) instead of `needs new code`. The Plan
   agent repairs each in its own context. Removes causes of L3. Effort S to M.
2. **Replace the Build to Plan reset with a plan amendment that keeps the passed tasks.** Extend `plan patch` from one
   command line to a task's files and tests, one question, rebuild only the tasks whose blocks changed and those that
   depend on them. Apply a Design answer the same way in place of L2. Carry the blocked record into it. Removes the
   costliest loop: two Opus passes and every task. Effort M to L.
3. **Measure Check's numbers at the end of Build.** Suite, coverage, mutation score and the locked acceptance tests at
   `temper integrate`; the fix pass repairs a shortfall before Review. Check reuses the pass on the same tree. Removes
   L5's second Review and most of L5 itself. Effort M.
4. **Repair Review's findings without leaving for Build.** A repair action at Review: the fix agent with the findings,
   Build's ledger kept, a Review of the fix only (the small change path already does the last part). One dialog in
   place of four; no demand for a new RED when the finding has no behavior to test. Effort M.
5. **Let a task agent see its verdict before it spends the attempt.** Expose the read only `verdict` as a check call;
   the gate still counts attempts. Fewer relaunches of the 122 to 193 s agents. Effort S.
6. **Mend the policy before the PR is merged.** Launch the group fix agent in an armed run (`scripts/flow.py:1754`);
   park instead of replanning, or change the three documents; disarm on "Stage by stage"; assert the second step in
   `temper-cases-28.sh`. Effort S.
7. **One budget that is real, and no dead knob.** Count `state redo`, `group reopen` and `group fix` against one run
   limit (the shipped `max-total-loops` could be that key), cap the fresh review's earned rounds, and remove
   `autonomy.enabled`, `max-stages` and any key no code reads. Effort S.
8. **One dialog a loop, with the reason written by the CLI.** The ready reasons are fixed texts; the policy already
   builds the reason from the failed rows (`scripts/flow.py:1161`, `1169`, `1969-1970`). Do the same for the person's
   click, and put the question's own facts (the blocked record) in the loop record. Effort S.

## 10. The experiments

Each ran the PR head's CLI from a clone, in a throwaway project built with the selftest's own `setup` and helpers
(`scripts/selftest/test-temper.sh:53-165`, `scripts/selftest/case-helpers.sh`). Nothing ran in `/home/user/temper`.

| Id | What was done | Result |
|---|---|---|
| E1a | Armed, policy, group G1's check failed once, every task passed; `temper next --json` | `auto`: `the policy takes "Fix the group's merged work"`, call `group fix G1` |
| E1b | Ran that call; `next` again | `fix={'requested': ...} fix_tries=1`; then `auto`: `the policy takes "Loop back to Plan"`, call `state loop build plan --reason 'policy: group G1 failed its check (...)'`. No agent |
| E1c | Ran that call; `next` again | `OK: loop build->plan iteration 1/1`, `OK: grouped run reset for the re-plan`; then `work`: `temper:temper-plan` on `opus`, mode `autonomous`; state `run_mode=autonomous parked=None`; no `autonomy-report.md` |
| E1d | The same failure, armed, no policy | `auto`: `temper park --verdict PARKED-NEEDS-DECISION` |
| E1e | The same failure, interactive | A question: Fix the group's merged work (Recommended), Run the group's tasks again, Loop back to Plan, More options (Change the group's command, Save for later) |
| E1f | After the policy's loop, the Plan gate passes | `ask`, mode `autonomous`: "Plan: the check passed. Approve the plan and continue to Build?" with Stage by stage (Recommended) and Autonomous Build |
| E1g | The calls of "Stage by stage" there | `spec branch`, `spec commit`, `state advance plan_complete build`; none disarms; `run_mode=autonomous` |
| E2 | `state redo build` six times, a failed Build gate before each | Six times `OK: build runs again`; `active_loops: []` |
| E3 | `state set next_stage plan` from Review | `OK: next_stage = plan`; no loop counted; `groups.json` gone |
| E4 | Each pair until refused, config with `max-total-loops: 4` | plan to intent 2 of 2, build to plan 1 of 1, review to build 2 of 2, check to build 2 of 2, commit to build 2 of 2, each then `BLOCKED`; `state loop commit intent` accepted; 10 steps back in all |
| E5 | `plan fresh start`, then `state redo plan` and a change to tasks.md, eight times | Rounds 1 to 8 all launched (`fresh review round 8 of 3 launched`); `rounds: 8, extra: 5`. With no change between rounds: refused from round 4 |
| E6 | A plan with a group that has no Validate, an Interfaces entry in a file no task declares, a task traced to a scenario the intent lacks; `temper gate plan` | `plan verdict: PASS`, every row ok |
| E6b | The same plan at Build, its task passed; `group gate G1`, then `next` | `FAIL: group G1 declares no **Validate:** command`; question: Run the group's tasks again (Recommended), Loop back to Plan, Change the group's command, Save for later |
| E8 | Review FAIL on one high finding; the loop; `next`; then a Build gate that fails only on criteria rows | Review question: Loop back to Build (Recommended), Override and continue, Architecture Depth Review, More options (Make a small change, Save for later). After the loop: `temper:temper-build` on sonnet with `Feedback re-entry: The check found a real problem.` and the finding. Then: `Build: the record pass is working on sonnet` |
| E9 | Armed, no policy, a task marked `env_fault` | `ask`, mode `autonomous`: "Task 1 ... failed on the environment ... check it again?" |
| E10 | Armed, Build gate FAIL on integration, without and with the policy | Both: `temper park ... 'Build failed: integration: ...'` |
| E11 | A blocked task (`needs src/other.py`, declared by Task 2), group parked; the loop to Plan; the Plan agent's prompt | The question names the file, the owner and the reason. The prompt holds `Loop back from Build: The plan cannot be built.` and nothing else of it; the loop record has no `findings` |
| E12 | A passed Build with four ledger rows; Review to Build; `temper gate build` | Rows 4, then 0. `RED then GREEN — need >=1 failing test run (RED) and >=1 passing run (GREEN); have red=0 green=0`; `criteria validated — AC-01 FAIL: scenario 'first' (true) has no row run by the CLI ...` |

## 11. What I could not determine

- How long a Build fix pass, a group fix agent and a record pass take: the bench summary I was given has no number for
  them, so L4 and L5 are priced in launches only.
- How often each edge fires in real runs. A run keeps `feedback-loops.json` and `usage.json`, and `state clear` removes
  both (`scripts/temper:1448`); I found no record across runs.
- Whether the mod's run driver (`hooks/temper-mod/core/driver.ts`) and its guard treat the `auto` calls, `state set
  next_stage` and the off menu loop pairs as `temper go` does. I did not read the mod.
- Whether the policy's unattended replan is meant (as `docs/flow.md` says) or a slip (as `reference/autonomy.md` and
  the config template say).
- Whether the separate budget of the (commit, build) pair is meant.
- Whether the preflight's commands really run inside the Plan agent's turn in practice (it follows from
  `agents/plan.md:60` and `scripts/temper:3600`; I did not run a Plan agent).
