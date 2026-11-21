# Temper fault history, recent half: versions 9.7.0 to 9.8.5

Source: `/home/user/temper/CHANGELOG.md` lines 1 to 1158, read completely on local branch `pr115` (HEAD `9a01eff`).
Cross checks: `docs/decisions/0017-*.md`, `docs/decisions/0018-*.md`, the PR #115 description, `git log origin/main..HEAD`,
and code measurements at each version's release commit (listed in section 4). All line numbers without a file name are
`CHANGELOG.md` lines.

How to read the confidence words: **changelog** means the claim is only what the changelog says; **verified** means I
read the code or ran a read-only command; **measured** means I counted it with a script over `git show <commit>:<file>`;
**inferred** means my reasoning from the other three.

Two things a planner must know first:

- **The local tree is not the PR head.** PR #115 on GitHub has 16 commits and head `10e965a`; local `pr115` has 13
  commits and head `9a01eff` (verified: `git rev-list --count origin/main..HEAD` = 13; `git cat-file -t 10e965a` fails).
  The PR body cites `scripts/e2e/ab-replay.sh` and `docs/evidence/ab-replay-9.8.5.md`; neither is in the working tree
  (verified: `ls scripts/e2e`, `ls docs/evidence`). The PR body says the replay found three more bugs in this PR,
  including "Run Build again recommended forever when a failure text held a growing count"; that fix is not in the
  local tree.
- **Cadence.** 13 versions in 31 days (9.7.0 on 2026-10-15, 9.8.5 on 2026-11-15; verified from `git log` on
  `.claude-plugin/plugin.json`). I count 326 separate changes in those 13 entries; 206 of them (63%) repair a fault.

---

## 1. Every change, classified by root cause

### 1.1 The classes

Thirteen fault classes, then six classes that are not faults. Each change has exactly one class (its main cause).

| Class | Meaning |
|---|---|
| LOOP | A loop, retry, rerun or review round that did not converge, or that redid far more than the change needed |
| REC | A question whose recommended option, option set, wording or failure text did not follow the evidence |
| DEADEND | A dead end: no option fits, the run parks or stops with no way out, or a gate fails correct work |
| GUARDFP | The guard (the mod or a hook) refused a legitimate step |
| GUARDHOLE | A way around the guard, or a leak through it, closed |
| OFFSCRIPT | The main session or an agent left the script (edited what it must not, asked its own question, skipped a step) |
| ORCH | Orchestration mechanics: the driver's hand back, background agents, half done steps, a run left idle |
| ENV | An environment or toolchain fault (JDK, coverage tool, PYTHONPATH, git config, cloud session limits) |
| PLANDEF | A plan defect found only in Build or later |
| BRIEF | An agent brief ambiguity: the agent guessed, skipped or asked the wrong thing |
| HANDOFF | Information lost between stages: a loop back, an answer or a note that did not reach the next agent |
| EVID | Evidence that could be faked, was miscounted or was stale; a gate that passed what it should not |
| STATE | Run state, locking, and branch, worktree and commit bookkeeping |
| POLICY | A plugin directory rule or a host (Claude Code) change |
| COST | Cost, speed or fewer-questions work |
| FEATURE | A new capability (a gate, stage, agent, command) not driven by one fault |
| UI | The mod's drawing (bar, pane, panels) |
| TEST | Selftest, e2e and benchmark infrastructure, and measurements |
| DOC | Documentation, videos, migration notes, proposals |

### 1.2 Counts per class and per version (measured from my item list; the full list is the appendix)

| Class | 9.7.0 | 9.7.1 | 9.7.2 | 9.7.3 | 9.7.4 | 9.7.5 | 9.7.6 | 9.8.0 | 9.8.1 | 9.8.2 | 9.8.3 | 9.8.4 | 9.8.5 | Total |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| LOOP | 1 |  |  |  |  | 4 | 1 | 2 |  |  | 1 | 5 | 2 | **16** |
| REC | 6 |  |  |  |  | 1 | 2 | 6 |  |  |  |  | 3 | **18** |
| DEADEND | 4 |  |  |  |  | 3 |  | 4 |  | 1 |  | 1 | 3 | **16** |
| GUARDFP | 3 |  |  |  |  | 2 |  | 5 |  |  | 2 | 1 | 2 | **15** |
| GUARDHOLE | 5 |  | 1 |  |  |  |  |  |  |  | 3 |  |  | **9** |
| OFFSCRIPT | 3 |  |  |  |  | 1 |  | 3 |  |  |  |  |  | **7** |
| ORCH | 5 |  |  |  |  | 1 |  | 8 |  |  | 1 | 1 |  | **16** |
| ENV | 3 |  |  |  |  | 4 |  | 2 |  |  |  | 1 | 5 | **15** |
| PLANDEF |  |  |  |  |  |  |  | 2 |  |  |  | 3 | 1 | **6** |
| BRIEF |  |  |  |  |  | 1 |  | 5 |  |  |  | 1 |  | **7** |
| HANDOFF | 3 |  |  |  |  | 2 |  | 2 |  |  |  | 4 | 2 | **13** |
| EVID | 7 |  |  |  |  | 5 | 4 | 6 |  |  | 1 |  | 5 | **28** |
| STATE | 18 |  |  |  |  | 2 |  | 4 |  |  | 13 | 2 | 1 | **40** |
| POLICY |  | 2 | 3 | 9 | 3 |  |  | 2 | 4 |  |  | 2 |  | **25** |
| COST | 1 |  |  |  |  | 2 |  | 23 |  |  |  | 1 | 3 | **30** |
| FEATURE | 6 |  |  |  |  | 3 | 10 | 6 |  |  |  |  |  | **25** |
| UI | 5 |  |  |  |  | 2 | 1 | 3 |  |  | 1 |  |  | **12** |
| TEST |  |  |  |  |  | 4 | 3 | 7 |  |  |  | 3 | 1 | **18** |
| DOC | 2 |  | 1 | 1 |  | 1 | 2 | 2 |  |  |  | 1 |  | **10** |
| *Fault classes (first 13)* | 58 |  | 1 |  |  | 26 | 7 | 49 |  | 1 | 21 | 19 | 24 | **206** |
| **All items** | 72 | 2 | 5 | 10 | 3 | 38 | 23 | 92 | 4 | 1 | 22 | 26 | 28 | **326** |

Reading the matrix:

- **STATE (40) and EVID (28) are the two largest fault classes**, and both are spread over many versions. 9.8.3 is a
  whole release that says so itself: "Each piece of run state that several writers moved ... now has one table of
  allowed moves" (164-169). 9.8.5 ends the EVID series with the rule the spine was supposed to have from v7: a run
  counts only when the CLI ran it (53-57).
- **The flow-control classes together (LOOP 16 + REC 18 + DEADEND 16 + HANDOFF 13 = 63) are the largest group**,
  30% of all faults. They are one problem seen from four sides: what happens after a check fails.
- **The guard and the carrier together (GUARDFP 15 + GUARDHOLE 9 + OFFSCRIPT 7 + ORCH 16 = 47)** are 23% of faults.
- **POLICY (25) is 8% of all changes** and four whole releases (9.7.1, 9.7.2, 9.7.3, 9.7.4) plus 9.8.1. None of it
  made a run faster or cheaper.
- **COST (30) is concentrated in 9.8.0 (23)**: one release that followed one benchmark (220-223). No COST item
  before 9.8.0 removed a stage; they removed turns, tokens and questions inside the same pipeline.
- **PLANDEF is small in count (6) but it is the trigger of both failed runs** (section 3), and each of its fixes is
  a new plan gate row.

---

## 2. The ten most patched mechanisms

Each change carries zero or more mechanism tags; counts are changes tagged with the mechanism (measured from the
appendix). "Faults" is how many of those are in a fault class.

| # | Mechanism | Changes | Faults | Versions that touched it | Fault classes inside (count) |
|---|---|---:|---:|---|---|
| 1 | Grouped Build: task gate, group gate, the group question, retry / escalate / park, worktrees and merges | 53 | 42 | 9.7.0 (7), 9.7.5 (9), 9.8.0 (14), 9.8.3 (3), 9.8.4 (9), 9.8.5 (11) | LOOP 9, EVID 6, STATE 6, PLANDEF 5, ENV 5, DEADEND 4 |
| 2 | The guard's exact matching of questions, agent prompts and commands (the mod and the hooks) | 30 | 29 | 9.7.0 (9), 9.7.2 (1), 9.7.5 (3), 9.8.0 (8), 9.8.3 (6), 9.8.4 (1), 9.8.5 (2) | GUARDFP 15, GUARDHOLE 9 |
| 3 | Loop backs, step backs and "run the stage again" | 28 | 26 | 9.7.0 (6), 9.7.5 (2), 9.7.6 (1), 9.8.0 (7), 9.8.3 (3), 9.8.4 (6), 9.8.5 (3) | HANDOFF 10, LOOP 4, DEADEND 3, STATE 3 |
| 4 | The fresh review of the plan | 24 | 12 | 9.7.6 (19, its creation), 9.8.0 (1), 9.8.4 (4) | EVID 4, LOOP 3, REC 3 |
| 5 | The Check gate and its measurements (suite, coverage, mutation, "Run Check again") | 22 | 17 | 9.7.0 (4), 9.7.5 (2), 9.8.0 (10), 9.8.4 (1), 9.8.5 (5) | REC 6, EVID 6 |
| 6 | The mod's run driver and its hand back to the conversation | 22 | 12 | 9.8.0 (17, its creation), 9.8.1 (2), 9.8.3 (3) | ORCH 9, STATE 3 |
| 7 | Branch, worktree and commit bookkeeping | 18 | 16 | 9.7.0 (8), 9.7.5 (4), 9.8.0 (4), 9.8.4 (1), 9.8.5 (1) | STATE 11, GUARDFP 3 |
| 8 | Intent: the Blocking questions and the rules checklist | 17 | 14 | 9.7.5 (1), 9.8.0 (12), 9.8.3 (2), 9.8.4 (2) | BRIEF 5 |
| 9 | Plan gate lint rows and the approved plan's hash | 16 | 15 | 9.7.0 (2), 9.7.5 (4), 9.7.6 (1), 9.8.0 (3), 9.8.4 (2), 9.8.5 (4) | PLANDEF 5, EVID 3 |
| 10 | Usage, token and cost accounting, and the end report | 15 | 8 | 9.7.0 (9), 9.7.2 (1), 9.7.3 (1), 9.7.4 (1), 9.8.0 (2), 9.8.4 (1) | ORCH 4, POLICY 3 |

Next in line: acceptance tests and their lock (9: 8 in 9.8.0, 1 in 9.8.3), Review findings and what blocks (9), stage
doors (9, 8 of them in 9.7.0), Design (8), autonomy (7), the Context check (6), the state lock (3, in three
consecutive releases). The plugin directory is not a run mechanism but 23 changes carry its tag and 4 carry the
256 KiB file limit's (one change carries both).

### What each count says about the design

**1. Grouped Build (53 changes, patched in every feature release).** The mechanism itself is the problem. Created in
9.7.0 as "a failed task is retried, then escalated, then parks its group" (1007-1009), it has needed since:
a question for a foreign commit (1023), a question before re-merging (1047-1048), a rule for a task an earlier task
built (730-731, then 292, then 337-338: three patches of "Accept it as done"), a group timeout rule (727-728), a
max-groups key (727), one agent per chain because "in the measured runs every task ran alone" (287-289), leftover
branch and worktree recovery (549-558, 563-567), a scenario-ownership rule because "that task's gate could never
pass, and the group parked again and again" (604-607), a changed recommendation after "the same gate had failed six
times on every model" (608-609), then in 9.8.4 the whole of faults 1, 2, 3c and 5 (77-105) and `task blocked`
(129-133), then in 9.8.5 the Maven rows, ENV at a task gate, `plan patch`, the reuse of a passing check, and the
empty fix agent (19-20, 25, 47-48, 37-38). The pattern: every task passes its own gate and the group check fails
(74), so the per task gates do not predict the group result, and the ladder (retry, stronger model, park, rerun the
group) spends agent launches without new information. The project's own measurement says model strength is not the
variable: "the same quality ... its one run with retries was a plan defect no model could build" (124-126). The
changelog also records the decision not to remove worktrees for small plans (342-343).

**2. The guard's exact matching (30 changes, 29 faults).** Half are false refusals (15), a third are holes (9). The
false refusals are all the same shape: a model transcribes text the CLI wrote and the guard compares characters. A
request "that ended with a period got two; a Haiku session tidied them, and the guard refused the launch as another
prompt" (370-371); "a raw traceback in a prompt was copied wrong by a cheaper session, and its launch was refused"
(395-396); a view written by another path named another model "and the guard refused the launch" (399-400); the mod
refused the command the CLI itself wrote (796-797). The holes were found by audits of shell syntax (1018-1021,
1028-1031, 1044-1047), and the changelog states the limit: "Temper is not a sandbox" (996). A design where the model
never retypes a prompt, a question or a command (the carrier passes an id) has neither kind of defect.

**3. Loop backs and reruns (28 changes, 10 of them HANDOFF).** Each loop back clears a ledger (1051-1052: "since the
loop clears that stage's ledger"), so every piece of information the next pass needs has had to be carried by a
separate patch: what Review left open (1051-1052), the person's reason (1061), the latest loop reason (762), the
failed run's output (295-298), Plan's open findings (92-94), the failed group check (96-97), the scenario rows
(116-120), the Design answers (28-29). Eight patches for one missing concept, a failure record that survives the
move. Same-stage reruns have no budget at all: `cmd_state_redo` (`scripts/temper:1455-1492`, verified) checks no
counter, and the only brake is the recommendation, which compares the first 300 characters of the failure text with
the last redo's reason (`scripts/flow.py:755-763`, verified). That is why following the recommendation looped 131,
40 and 52 times (90, 122, 123), and why the PR body reports the same loop again when the failure text holds a
growing count.

**4. The fresh review (24 changes).** Created in 9.7.6 with 19 changes of its own, including a round limit (637-638)
and a second reviewer at risk H (641). In the first real complex run it produced "6 fresh reviewers over 3 rounds"
(72-73) and did not converge; 9.8.4 then changed what a round is (a recheck of earlier findings only), which lens
runs, and what blocks (98-101), fixed the dead end at the round limit (95-96), and found a recheck round launched
with nothing to check (136-138). The severity rule flipped twice: high blocks (625), then medium is a recommended
revision (536-540), then "medium and low ones are no longer a recommended revision" (100-101). The design question
is not the reviewer, it is the unbounded review-revise cycle in front of Build. Its measured cost when nothing goes
wrong is small ("$0.17 ... about 17% of the Plan stage", 669-670); its cost when it finds things is Plan passes on
Opus, and Plan is about 200 s a pass (`docs/evidence/bench-2026-11.md:457`).

**5. Check (22 changes).** Before 9.8.0 a Sonnet agent ran the suite and typed results into the ledger, and "a row it
forgot ... failed the gate for no fault of the code" (226-228). Moving the run into the CLI was the structural fix;
the remaining patches are recommendations that did not fit the failure class: a missing tool recommended a loop back
to Build (739-746), then "Run Check again" was recommended 52 times (122-123), then an environment fault still
recommended a loop back until `SETUP` (39). Check got its failure classes one incident at a time: "a measurement
nobody took" in 9.7.5 (742-744), `SETUP` in 9.8.5 (39).

**6. The run driver (22 changes, all within 5 weeks of its creation).** It removes the main session's model cost
("$0.00 in the main session", 480-482), which is the largest single COST win in the period. Its faults are all at
the boundary where it hands back: eight hand back reasons are listed at creation (453-455), and seven patches
followed in the same release (457-460, 466-470, 471-476, 480-483, 559-562, 592-597, 518-520). 9.8.1 then had to
remove its shell (205-209) for the directory. The mechanism is sound; the hand back list is the defect surface.

**7. Git bookkeeping (18 changes, 11 STATE).** The commit message for a run whose code is already committed was
patched three times inside 9.7.0 alone (1042-1043, 1052-1053, 1067-1068). Task branches, group branches, kept refs,
worktree records and spec carry-over across branches each needed a recovery path (549-567, 765, 796-797). This cost
exists only because Build runs in worktrees per task.

**8. Intent (17 changes, 12 in 9.8.0).** This is the one stage the benchmark says earns its cost ("on vague
requests, asking before building mattered", 221-222). Its patches are brief ambiguities found by measured runs
(442-445, 579-583, 584-586), each closed with a gate row or checklist item rather than more prose. Low risk.

**9. Plan gate lint rows (16 changes).** One row per failed run: `scenario test commands` (708), `maven group
verify` (735-736), `tier recorded` (1108), `request routes kept` (378-381), `group validate order` (77-81), `shared
production files` (104-105), `maven filtered verify` (19-20), `tasks agree with decisions` (28). The 9.7.5 Maven row
missed `cd backend && mvn` (19; ADR 0018:11) and had to be patched after a 3.2 hour run. Rows that pattern-match a
plan can only know the defects already seen. The 9.8.5 preflight (14-18) is the first check of the right kind: it
runs the commands. The approved plan's hash was introduced as a freeze (1015-1016), relaxed for Design (307-310),
and relaxed again for one command line (47): a frozen artifact that three later features needed to edit.

**10. Usage and cost accounting (15 changes).** Built in 9.7.0 with six fixes in the same entry (1110-1137), then
its transcript read and cost were deleted for the directory (929-938), then tokens were deleted (823-831). What
remains is time per stage. It decides no gate.

---

## 3. The two failed real runs

### 3.1 Run A: the complex feature (9.8.4)

**What the record gives** (changelog 72-75; ADR 0017:9-12):

| Fact | Value | Source |
|---|---|---|
| Size | 8 criteria, about 30 files, risk H | 72 |
| Plan passes | 5 | 72 |
| Fresh reviewers | 6, over 3 rounds | 72-73 |
| Build attempts | 5, of one group of 12 tasks | 73 |
| Questions to the person | about 30 | 73 |
| Result | nothing on the branch | 73 |
| Signature | "Every task passed its own gate each time; the group check failed each time." | 74 |
| The request | "already stated the rules, the files to change, the tests to update and the done condition" | ADR 0017:10-11 |

No wall time, cost or per question breakdown is recorded anywhere I could find.

**Timeline, reconstructed (inferred from the counts and from each fix; the order inside Plan and Build is not
recorded):**

1. Intent, Plan pass 1 on Opus. Risk H gives two fresh reviewers a round (641, default
   `plan.fresh-review-twice: true`, `templates/temper.config.default`, verified).
2. Three review rounds, the default cap (`plan.fresh-review-rounds: 3`, 637, verified in the template): 2 reviewers
   x 3 rounds = 6 reviewers, matching the record. Each round was a full new review, so each found new things, and
   medium and low findings were recommended revisions (the state fault 4 fixed, 98-101). Each revision is a Plan
   pass ("Revise the plan", 639-640).
3. The round cap then dead ended after a loop back (fault 3b, 95-96).
4. Design (complex, risk H).
5. Build: G1 of 12 tasks on Haiku (the default before fault 5, 102-103). Every task passed its own gate. G1's
   Validate "ran selftest cases 8 and 9 while the task that updated them was in G2" (80-81), so the group check
   could not pass whatever the code. The question recommended running the group's tasks again (82, 87-88), with the
   reason "cut to 200 characters" (84). Five attempts.
6. At least one loop back toward Plan, which lost Plan's open findings and the failed group check (faults 3a and 3c,
   92-97). 5 Plan passes = the first, up to 3 revisions, and at least one more after a step back (inferred).
7. The run ended with no commit.

The mention of "selftest cases 8 and 9" means the feature was a change to Temper itself (inferred).

**Each fault, by kind:**

| # | Fault | Kind | Lines |
|---|---|---|---|
| 1 | G1's Validate ran test files a G2 task edits: the group could never pass | **Plan defect**, undetected by any plan row and by 6 reviewers | 77-81 |
| 2 | A failed group check recommended a blind rerun, every time; the failure reason cut to 200 characters | **Flow design** (LOOP, REC) | 82-91 |
| 3a | A step back dropped Plan's open findings; the reason reached only one stage | **Flow design** (HANDOFF) | 92-94 |
| 3b | The review round limit dead ended after a loop back | **Flow design** (DEADEND) | 95-96 |
| 3c | A step back from Build did not carry the failed group check | **Flow design** (HANDOFF) | 96-97 |
| 4 | Each review round was a new full review; medium and low findings sent the plan back | **Flow design** (LOOP) | 98-101 |
| 5 | Haiku task agents on a complex, risk H plan; more than two tasks sharing a production file | **Plan defect** (shared files) plus a model routing choice | 102-105 |
| 6a | The credential filter stripped `GIT_CONFIG_KEY_n`, so every git call under the CLI failed in cloud sessions | **Environment** (caused by the 9.7.4 directory change, 833-836) | 106-109 |
| 6b | Selftest case files shared a work folder | Environment (test infrastructure) | 109-110 |
| 7a | "Include what is left out" cut to 100 characters; Plan was told "already co" | Flow design (HANDOFF) | 111-112 |
| 7b-d | brief.md not excluded from git; no way to read a gate's output with the mod on; no agent time in the report | Frictions | 112-115 |
| 8 | The request was a spec; "Intent, Plan, Design and three review rounds mostly derived again what the request said" | **Flow design** (wrong route) | 142-144; ADR 0017:11-12 |

Fault 8 is the only one not fixed: ADR 0017 is "Proposed (a draft; nothing of it is built)" (ADR 0017:3).

A note on fault 5: the same release measured Haiku against Sonnet task agents over 18 runs and found "the same
quality" (124-126). The switch to Sonnet for complex or risk H plans is therefore not supported by the project's own
measurement; the shared-files row is.

### 3.2 Run B: the Java 24 Maven project (9.8.5)

**What the record gives:**

| Fact | Value | Source |
|---|---|---|
| Agent time | 3.2 hours, 12 tasks | 8 |
| Build alone | "most of 2.8 hours of Build went to faults that existed before any agent wrote code" | ADR 0018:9-10 |
| Findings | 22, coded S1 to S8, Q1 to Q9, U1 to U5 | 13, 27, 34, 44, 53, 58 |
| Second run | A Temper run on the 9.8.5 change itself: "a plan line that could never finish in its time limit, three fix agents that changed nothing" | 9-10 |

The changelog and ADR disagree only in scope (3.2 hours of agent time against 2.8 hours of Build); both can be true.
The run's own record is not in the repository (ADR 0018:67).

**Timeline, reconstructed (inferred; the record gives faults, not an order):**

1. Plan wrote group Validate lines of the form `cd backend && mvn verify -Dtest=...` under a JaCoCo BUNDLE rule: a
   filtered verify can never meet the coverage rule (19-20; ADR 0018:10).
2. The 9.7.5 plan row `maven group verify` did not see them, because the Maven check "skipped every `cd backend &&
   mvn ...` line" (ADR 0018:11).
3. Build started. The CLI's gates and the agents ran under JDK 21; the project needs `[24,)` (ADR 0018:10-11). "A
   gate call under the wrong JDK spent a task attempt and reset its work folder" (ADR 0018:12).
4. Failure texts "pointed at the wrong cause" (PR body): the text shown was a passing test's log line, not Maven's
   failed goal (35-36).
5. Fix passes were launched with no fault in their prompt, and fix agents changed nothing, after which the same
   check ran again on the same tree (37-38).
6. A wrong command line could only be corrected by Plan, Design and every passed task again (47; commit `69aad39`).
7. At Review and after: a Design answer given after the plan did not reach `tasks.md` (28-29); a High finding did
   not block, since `review.block-on` was `[critical]` (30; verified in `origin/main:templates/temper.config.default:31`);
   `integrate` was not rerun after HEAD moved (32).
8. At Check an environment fault recommended a loop back to Build (39), and "Override and commit" was offered where
   it could not clear the row (40).

**Each fault, by kind** (codes from the changelog's package headings and the PR's commit messages; S1 to S3 and U3
are package 1 and I could not map them one to one):

| Fault | Kind | Codes | Lines |
|---|---|---|---|
| A plan command that could never pass (filtered verify under a JaCoCo bundle rule) | **Plan defect** | package 1 | 19-20 |
| The Maven plan row missed `cd backend && mvn`, `./mvnw`, `mvnd` | Flow design (a lint row that pattern-matches) | package 1 | 19 |
| Wrong JDK in every shell; no declared environment for CLI commands or agents | **Environment** | package 1 | 21-24 |
| Nothing ran the plan's commands before Build | **Flow design** | package 1 | 14-18 |
| An environment failure at a task gate spent an attempt and reset the worktree | Flow design | package 1 | 25 |
| Failure text was a passing test's log line | Flow design (REC) | S4 | 35-36 |
| A passing check was rerun on the same tree | Flow design (COST) | S5 | 48 |
| One wrong command line needed Plan, Design and all tasks again | Flow design (LOOP) | S6 | 47 |
| A fix pass with no fault in its prompt | Flow design (LOOP) | S7 | 37 |
| A fix agent that changed nothing was followed by the same check | Flow design (LOOP) | S8 | 37-38 |
| A Design answer did not reach the tasks | Flow design (HANDOFF) | Q1 | 28-29 |
| A High review finding did not block | Gate too lenient (EVID) | Q2 | 30-31 |
| An agent's claimed run counted as proof | Evidence (EVID) | Q3 | 53-57 |
| A RED made on the final code counted | Evidence (EVID) | Q4 | 48-49, 58-59 |
| Interface signatures compared by text | Gate failing correct work | Q5 | 49 |
| Check recommended a loop back for an environment fault | Flow design (REC) | Q6 | 39 |
| `integrate` not rerun after new commits | Evidence (EVID) | Q7 | 32 |
| "Override and commit" offered where it does nothing | Flow design (REC) | Q8 | 40 |
| The state lock was written past | State | Q9 | 48 |
| Review and Check always ask, even in an armed run | Flow design (questions) | U1 | 45-46, 60 |
| The session could not add a word to a question | Guard too strict | U2 | 50 |
| The mod refused every push, also a backup | Guard too strict | U4 | 49-50 |
| A person's note was not marked as theirs | Handoff | U5 | 49 |

Tally of the 23 rows: 1 plan defect and 1 environment fault are the root causes; 12 rows are flow design; 4 are
evidence; 2 are the guard; 1 each is a gate failing correct work, state and handoff. The root causes were present
before the first agent launch; the flow design is what turned them into hours.

**What the PR's own replay claims** (PR #115 body; the script is not in the local tree, so this is unverified):
on a mock of the same faults, 9.8.4 against this PR: agent launches 10 against 7, estimated agent minutes 191
against 92, questions 8 against 8 (4 with `autonomy.policy: decide`), hand repairs of the shell 2 against 0, and the
High defect committed on 9.8.4 only.

**The 9.8.5 run on itself.** The branch holds two CLI-made task commits, `15fac9c` "Task 1 ... [G1]" and `230fc23`
"Task 2 ... [G1]", then eleven hand-written `feat:` commits; `7859742` says "on top of the Maven rows and the first
preflight (Tasks 1 and 2)" and "the full suite has not run yet" (verified in `git log origin/main..HEAD`). Inferred:
the gated run delivered two tasks and the rest of 9.8.5 was built outside the gated flow.

### 3.3 What the two runs have in common

| | Run A | Run B |
|---|---|---|
| Root cause | A plan defect in a Validate line | A plan defect in a Validate line, plus the JDK |
| When it was knowable | At the plan gate, by running the Validate line | At the plan gate, by running the Validate line |
| When it was found | After 5 Build attempts of 12 tasks | After most of 2.8 hours of Build |
| What the flow did with the failure | Recommended the same rerun | Launched fix agents with no fault, reran the same check |
| Information at the question | Reason cut to 200 characters | A passing test's log line |
| Pre-Build stages | 5 Plan passes, 6 reviewers, Design: none saw the defect | Not recorded |

Both are the same failure: a command in the plan that cannot pass, discovered only after the most expensive stage,
followed by a retry ladder that has no failure classes. 9.8.4 patched the ladder and added two lint rows; 9.8.5
added the preflight, which is the first change that would have stopped both runs at the plan gate.

---

## 4. Growth of questions, gate rows, agents and config keys

### 4.1 Measured at each release commit

Method: `git show <commit>:<file>` and `git ls-tree`, read only. Commits: 9.6.8 `c8fc548`, 9.7.0 `a17c0e7`, 9.7.4
`595aaae`, 9.7.5 `f418c65`, 9.7.6 `e659c31`, 9.8.0 `eceabad`, 9.8.3 `fb6af68`, 9.8.4 `3ecd452`, 9.8.5 `HEAD`.

| Version | Agent briefs in `agents/` | `self.question(` call sites in `scripts/flow.py` | Distinct option labels in `flow.py` (literal first argument of `opt(`) | Row names in `scripts/` (regex proxy, see note) | Keys in `templates/temper.config.default` | `temper ...` lines in the CLI help | `flow.py` lines | Python files in `scripts/` | Selftest case files |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 9.6.8 | 8 | no flow.py | no flow.py | 26 | 36 | 11 | none | 5 | 4 |
| 9.7.0 | 9 | 23 | 38 | 42 | 38 | 25 | 1,464 | 10 | 9 |
| 9.7.4 | 9 | 23 | 38 | 42 | 38 | 25 | 1,434 | 10 | 9 |
| 9.7.5 | 10 | 33 | 53 | 48 | 41 | 29 | 1,929 | 23 | 13 |
| 9.7.6 | 11 | 33 | 56 | 50 | 44 | 31 | 2,049 | 26 | 14 |
| 9.8.0 | 12 | 34 | 63 | 60 | 44 | 39 | 2,608 | 37 | 16 |
| 9.8.3 | 12 | 34 | 63 | 60 | 44 | 41 | 2,685 | 38 | 19 |
| 9.8.4 | 12 | 34 | 64 | 62 | 44 | 43 | 2,786 | 42 | 20 |
| 9.8.5 | 13 | 41 | 69 | 65 | 53 | 46 | 3,111 | 49 | 31 |
| **Growth 9.7.0 to 9.8.5** | **+4 (+5 from 9.6.8)** | **+18 (78%)** | **+31 (82%)** | **+23 (55%)** | **+15 (39%)** | **+21 (84%)** | **x2.1** | **x4.9** | **x3.4** |

Notes on the measures (so nobody over-reads them):

- **Row names** is a regex over `_req "name"` in `scripts/temper`, `row('name', ...)` in the Python files and
  `name = "..."` in three row files. It includes a few CLI evidence rows of Check (`coverage`, `mutation score`) and
  misses names with an apostrophe (`fresh reader's paraphrase`). It is a consistent proxy, not an exact count.
- **Config keys** counts leaf keys in the template, commented examples included, less one false match. Four keys the
  code reads are not in the template at HEAD: `check.mutation-threshold`, `check.commands.coverage`
  (`scripts/temper:3918`, `4938`), `models.plan-review` and `models.acceptance` (`scripts/flow.py:1284`, `1411`).
  With them the count at 9.8.5 is 57. At least 20 `TEMPER_*` environment variables are also read by the scripts
  (grep at HEAD), among them `TEMPER_MUTATION_BUDGET_S` (241) and `TEMPER_LOCK_MAX_S` (184).
- **Question sites** counts places in the flow that can ask, not questions in one run. Run A asked "about 30" (73).
- `scripts/temper` is 260,504 bytes at HEAD against the directory's limit of 262,144 (256 KiB): 1,640 bytes of room
  (measured). The limit already forced code out of the file in 9.7.1 (968-974), 9.8.0 twice (333-334, 568-570) and
  9.8.4 (155-158).
- Selftest: 1,761 passing checks at 9.7.4 and 1,988 at 9.7.5 (803), 2,074 at 9.7.6 (695), 2,879 at 9.8.5 (PR body).
  The serial CI run took about 26 minutes at 9.7.5 (804); the e2e job's limit went from 45 to 60 minutes in 9.8.4
  (153-154).

### 4.2 Agent launches a run can make (changelog and code)

Briefs undercount launches. Beyond one agent a stage, these launch types were added in the period:

| Added in | Launch | Source |
|---|---|---|
| 9.7.0 | One Haiku agent per task, a retry, then an escalation model | 1007-1008 |
| 9.7.5 | A record pass "once per round"; the Pipeline agent | 711; 760 |
| 9.7.6 | The fresh reviewer; a second one at risk H; up to 3 rounds; "Revise the plan" reruns Plan | 619-641 |
| 9.8.0 | The acceptance writer; its correction; the triage agent (`models.acceptance` at `flow.py:1411`, `1473`, `1523`) | 244-247, 299-303, 322-325 |
| 9.8.4 | The group fix agent; the recheck round | 85-86, 99-100 |
| 9.8.5 | The environment agent | 63-65 |

Removed in the period: the Check agent for stacks the CLI can read (226-232), Design for a fully specified request
below risk H (319-321), one agent per task where tasks chain (287-289), the main session's model when the mod
carries the run (448-452).

### 4.3 Every feature that added a question, a gate row, an agent, a config key or a CLI command

Q is a question or an option, R a gate row, A an agent brief, K a config key, C a CLI command. These are my
readings of the changelog text; the measured table above is the authority for totals. Net by this reading from
9.7.0 to 9.8.5: questions and options +24, gate rows +22, agent briefs +5, config keys +21, CLI commands +41.

| Version | CHANGELOG.md lines | Adds (Q question or option, R gate row, A agent brief, K config key, C CLI command) | Feature |
|---|---|---|---|
| 9.7.0 | 978-984 | C+1 | The CLI says what comes next (`temper next`, view.json); `commands/temper.md` 6,870 to 2,117 words |
| 9.7.0 | 1005-1011 | A+1 K+3 | Build runs in groups of Haiku task agents: retry, escalate, park |
| 9.7.0 | 1023 | Q+1 | A commit the CLI did not make on a group's branch is a question |
| 9.7.0 | 1024-1025 | Q+1 | A Review that did not finish offers to run again |
| 9.7.0 | 1025-1026 | Q-1 | The plan gate has no "Walk through step by step" option |
| 9.7.0 | 1047-1048 | Q+1 | After Keep the commits the person is asked before the groups merge again |
| 9.7.0 | 1060 | Q+1 | A passed Design offers Loop back to Plan |
| 9.7.0 | 1075-1076 | Q+1 | A passed Check offers Loop back to Build |
| 9.7.0 | 1077-1079 | R+1 | Review writes no code (a live Review fixed a critical finding itself) |
| 9.7.0 | 1083-1088 | Q+1 C+1 | `temper init --foreground-agents` asks to add an environment variable to settings |
| 9.7.0 | 1105-1108 | R+1 | `state set complexity` writes the tier into intent.md; row `tier recorded` |
| 9.7.0 | 1120-1122 | Q+1 | The report prints before the commit; a question offers the HTML page |
| 9.7.3 | 858-864 | Q-1 C-1 | `temper init --foreground-agents` removed |
| 9.7.3 | 890-892 | Q-1 | `mode` and `enforcement` no longer change settings; the first run mode question is gone |
| 9.7.5 | 705-711 | R+2 | A scenario criterion passed on a `Traced to:` line (F7 to F9): `Test:` commands, `criteria validated` |
| 9.7.5 | 712 | R+1 | The Intent gate passed over an open Blocking question (F10) |
| 9.7.5 | 713-716 | K+1 Q+1 C+1 | The Context Map and `plan.context-check` (F6) |
| 9.7.5 | 717 | C+1 | Risk was Plan's estimate (F11): `temper risk` computes it |
| 9.7.5 | 718-720 | Q+1 C+1 | tasks.md parsing; a manual task confirmed by the person; the all-tasks check passed with one of eight done (F12) |
| 9.7.5 | 723 | Q+1 | Change reopened every task (F13) |
| 9.7.5 | 724-725 | Q+1 C+2 | A small change needed a loop back (F14): `adhoc open` and `adhoc close` |
| 9.7.5 | 727 | K+1 | A plan with tasks and no groups reached a Build with nothing to run (F16); `max-groups` |
| 9.7.5 | 727-728 | Q+1 | A group gate records a timeout and offers a rerun at double the limit (F17) |
| 9.7.5 | 730-731 | Q+1 C+2 | A task an earlier task built was retried and parked (F19); the person decides |
| 9.7.5 | 735-736 | R+1 | Maven (F22): `maven_loop.py`; row `maven group verify` |
| 9.7.5 | 739-746 | Q+1 | A missing tool sent the run back to Build: "Run Check again" |
| 9.7.5 | 755-757 | R+1 | The Pipeline agent guessed a fix path and a round limit; row `fix paths` |
| 9.7.5 | 760-761 | A+1 K+1 Q+3 R+2 | The Pipeline stage, draft pull requests, stacked parts (F23, F24, F26) |
| 9.7.5 | 765 | Q+1 | Branch clash (F28) |
| 9.7.5 | 765 | C+1 | `temper guards uninstall` (F30) |
| 9.7.5 | 787-788 | Q-1 | The readiness skill (F25) is taken out |
| 9.7.6 | 619-625 | A+1 R+3 | The fresh review of the plan (`agents/plan-review.md`): three lenses, three plan gate rows |
| 9.7.6 | 626-628 | K+1 Q+1 C+1 | The person chooses it (`plan.fresh-review: ask`): "Fresh review first" |
| 9.7.6 | 631-634 | C+1 | The CLI marks each launch; an edit makes the review stale |
| 9.7.6 | 637-638 | K+1 | A round limit (`plan.fresh-review-rounds`, 3) |
| 9.7.6 | 639-640 | Q+1 | "Revise the plan" runs the Plan agent again with each open finding |
| 9.7.6 | 641 | K+1 | A risk H plan gets two independent reviewers (`plan.fresh-review-twice`) |
| 9.7.6 | 645-647 | C+1 | `evidence contest` with a checked citation |
| 9.7.6 | 648 | C+1 | `evidence escalate` |
| 9.7.6 | 656-658 | Q+1 C+1 | A reviewer that stopped is not a clean review; "Run the fresh review again" |
| 9.7.6 | 661-664 | C+1 | `temper drift` |
| 9.7.6 | 680-681 | K+1 | `reviewerModel` and `models.plan-review` |
| 9.8.0 | 226-232 | C+1 K+1 | The CLI runs Check itself (`check run`); the Check agent only for a stack it cannot read |
| 9.8.0 | 236-241 | R+1 K+1 | Mutation score gate (`check.mutation-threshold`) |
| 9.8.0 | 242-243 | R+1 | Regression proof for a fix |
| 9.8.0 | 244-247 | A+1 R+1 C+1 | Acceptance tests written before Build (`agents/acceptance.md`), locked |
| 9.8.0 | 250-251 | Q+1 | A criterion validated by hand is confirmed by the person at Check |
| 9.8.0 | 259-260 | C+1 | Carry forward works (`intent carry`); it left the Intent gate red with no way out |
| 9.8.0 | 261-264 | Q+2 | The Context check names what the plan leaves out; any other answer sends Plan back |
| 9.8.0 | 271-274 | K-1 | Unattended with no setting (`autonomy.enabled` no longer read) |
| 9.8.0 | 275 | Q-1 | A plan with one group goes on to the merge by itself |
| 9.8.0 | 276 | Q-1 | The report page is written without a question |
| 9.8.0 | 279-282 | C+1 | `temper go`: the CLI runs its own steps (59 of 88 tool calls) |
| 9.8.0 | 292 | Q-1 | "Accept it as done" records its reason itself |
| 9.8.0 | 299-303 | Q+1 C+1 | A wrong locked acceptance test has a way out ("Correct the acceptance test") |
| 9.8.0 | 304-306 | Q+1 C+1 | A lock is taken once; "Restore the locked tests" |
| 9.8.0 | 311-312 | Q+1 | Files outside the plan at the commit gate: "Add to plan" first |
| 9.8.0 | 315-318 | C+1 | Check runs while Review reads (`check ahead`) |
| 9.8.0 | 322-325 | C+1 | A failing locked test is triaged by an agent before a Build round |
| 9.8.0 | 326-328 | R+1 | The rules checklist is recorded; the Intent gate fails a missing item |
| 9.8.0 | 372 | C+1 | A typed change request goes to the stage's agent (`state redo --reason`) |
| 9.8.0 | 378-381 | R+1 | New row `request routes kept` (a Plan built the request's route as another path) |
| 9.8.0 | 384-387 | C+1 | `temper intent answer` (two to four turns a stage saved) |
| 9.8.0 | 388-391 | C+3 | `temper spec branch`, `spec commit`, `spec deviations` |
| 9.8.0 | 431-435 | C+1 | The CLI draws the Plan, Design and RCA panels (2,000 to 3,000 output tokens and 30 to 40 s a stage) |
| 9.8.0 | 436-441 | C+1 | The project brief (`temper brief`) |
| 9.8.0 | 495-500 | C+1 | The CLI draws each Build task's panel (about a minute of each Haiku agent's three) |
| 9.8.0 | 563-567 | K+1 | Earlier attempts' branches leave `git branch` (`build.grouped.keep-days`) |
| 9.8.0 | 571-576 | Q-1 | The words of a question match the run (More options, fix run wording, the page question gone) |
| 9.8.1 | 205-209 | C+2 | The mod runs one program with no shell; `temper config init`; `temper guards install` |
| 9.8.4 | 77-81 | R+1 | Fault 1: new row `group validate order` (G1's Validate ran tests a G2 task updated) |
| 9.8.4 | 82-91 | Q+1 C+1 | Fault 2: a failed group check stops recommending a blind retry; FAIL lines kept; `group fix`; rerun never recommended twice (131 loops on a mock) |
| 9.8.4 | 104-105 | R+1 | New row `shared production files` |
| 9.8.4 | 113-114 | C+1 | 7c: `temper output` (with the mod on, the session cannot run printenv or a test runner) |
| 9.8.4 | 129-133 | C+1 | `temper task blocked`: a task its plan cannot build is not retried |
| 9.8.5 | 14-18 | R+1 K+2 C+1 | Preflight: the plan gate runs every Validate, Test, Integration and scenario command once on HEAD; an environment or command fault fails the gate |
| 9.8.5 | 19-20 | R+1 | Maven is found after `cd backend &&`, `./mvnw`, `mvnd`; new row `maven filtered verify` |
| 9.8.5 | 21-24 | K+4 C+1 Q+1 | `setup:` block applied to every CLI command and put in every agent prompt; `temper doctor`; `doctor --propose` offered as one click |
| 9.8.5 | 25 | Q+1 | ENV at a task gate keeps the attempt and the worktree; "Check it again" |
| 9.8.5 | 28-29 | R+1 | A Design answer given after the plan holds Build until tasks.md changes; Build prompts carry the decisions |
| 9.8.5 | 45-46 | K+1 | `autonomy.policy: decide`: an armed run goes on through Review and Check by fixed rules |
| 9.8.5 | 47 | C+1 Q+1 | `temper plan patch`: change one command line of the approved plan, keep the passed tasks, spend no loop |
| 9.8.5 | 53-57 | K+1 C+2 | Only a run the CLI ran counts (`evidence run`); `evidence.claimed-runs`; `evidence void` |
| 9.8.5 | 58-59 | K+1 | `task start` records the code files so retries are judged; `build.red-before-code` |
| 9.8.5 | 63-66 | A+1 Q+1 | A setup for any project: rules, CI and devcontainer files, an environment agent (`agents/env.md`); one check |

### 4.4 What went the other way (removed or reversed)

| What | Added | Removed or reversed | Lines |
|---|---|---|---|
| Token counts and cost in the report | 9.7.0 | transcript read and cost removed 9.7.2; tokens removed 9.7.4 | 1110-1137; 929-938; 823-831 |
| `temper init --foreground-agents` and its question | 9.7.0 | 9.7.3 | 1085-1087; 858-864 |
| The bar's "Go on" button | 9.7.0 | 9.7.3 | 999; 888-889 |
| `ui.ask` in the mod | removed 9.7.3 | back in 9.8.0 for the driver | 893-894; 478 |
| The HTML report question | 9.7.0 | 9.8.0 | 1121-1122, 1129-1130; 276, 575-576 |
| Autonomy through Review and Check | 9.7.0 | Build alone in 9.8.0; back by `autonomy.policy: decide` in 9.8.5 | 1088, 1092; 513-515; 45-46 |
| `autonomy.enabled` | before 9.7.0 | "no longer read" 9.8.0 | 271-273 |
| Medium fresh review findings | pass silently 9.7.6 | recommended revision 9.8.0; not recommended 9.8.4 | 625; 536-540; 100-101 |
| The approved plan frozen from Design on | 9.7.0 | Design may change tasks 9.8.0; `plan patch` 9.8.5 | 1015-1016; 307-310; 47 |
| The lock fails open | 9.8.4 ("still written past ... (fail open)") | fails closed 9.8.5 | 148-149; 48 |
| "Include what is left out" | 9.8.0 | fixed 9.8.4, then "was always refused at 100" 9.8.5 | 261-264; 111-112; 41-42 |
| "Run again" recommended | 9.7.5 | not twice, 9.8.4 | 743; 120-123 |
| The readiness skill | before | taken out 9.7.5 | 787-788 |

Two of these are visible in the tree (verified). First, a doc and code disagreement: `.claude/CLAUDE.md:19-20` and
`templates/temper.config.default:135` still say that `enabled: false` keeps every gate interactive, while
`scripts/flow.py:302` says "autonomy.enabled is no longer read" and the view sets `"autonomy_enabled": True`
unconditionally (`scripts/flow.py:2822`). Second, the 9.8.4 fix of "Include what is left out" did not work: at
`origin/main` (9.8.4) `scripts/plan_ops.py:130-131` still raised "the answer is one line of at most 100 characters",
so passing the whole text made the option fail for any longer answer; HEAD allows 2000 (`scripts/plan_ops.py:28`,
`131-132`).

---

## 5. My reading: the few structural changes that would have prevented most of these patches

Counts are the fault changes in the classes or mechanisms each change addresses (appendix). They overlap, and a
class size is an upper bound on what a change prevents, not a promise.

### 5.1 One failure record and one budget for every "it failed, what now" (addresses LOOP 16, REC 18, HANDOFF 13, and about half of DEADEND 16: about 55 of 206)

Today a failed check can be followed by a task retry, an escalation, a group rerun, a group fix, a stage redo, a
loop back, a review round or a recheck. Each has its own counter or none (`state redo` has none,
`scripts/temper:1455-1492`), each carries its own subset of what failed, and the recommendation is recomputed by
each question with its own rule (text equality at `scripts/flow.py:755-756`). Replace them with:

- one typed failure record written by the CLI when any check fails: the command, its class (environment, command,
  plan, code, measurement missing), the build tool's summary, the tree hash; it survives every move;
- one attempt counter per (check, tree hash), so the same check is never run twice on the same tree and never
  recommended twice for the same class;
- one fixed ladder by class: environment goes to the setup repair; command goes to a plan line patch; plan goes to
  one Plan revision; code goes to one fix agent with the record in its prompt; a second failure of the same class
  stops and asks.

This is what 9.8.4 faults 2, 3 and 4 and 9.8.5 S4 to S8, Q6 and Q8 each built a piece of. It would have ended the
131, 40 and 52 step loops by construction rather than by wording.

### 5.2 Run before you plan on it: the environment and every plan command checked once, before any agent builds (addresses ENV 15, PLANDEF 6, and the trigger of both failed runs)

9.8.5 does this (preflight, `setup:`). The structural point for the plan is to make it the only plan check of its
kind, and stop adding one pattern row per incident (mechanism 9, 16 changes). A row such as `maven filtered verify`
or `group validate order` knows one defect; a dry run of each group's Validate against the files its tasks declare
knows them all. Related: a group's own check should only run tests its own tasks own, with one integration check on
the merged tree, so a cross group Validate cannot be written at all.

### 5.3 Shrink grouped Build to what the measurement supports (mechanism 1: 42 fault changes; with git bookkeeping 56; with loop backs 63, 31% of all faults)

Per task agents in worktrees with per task gates, a group gate, a merge and a person's Continue are the most patched
part of the product, and the benchmark does not show them paying: each task agent costs 122 to 193 s (507-508), in
the measured runs "every task ran alone" (289), Haiku and Sonnet gave the same quality (124-126), and plain Claude
Code built the same features at a quarter to a fifth of the cost (486). For simple and medium plans, one Build agent on the branch,
test first, with the CLI running the tests, removes the task gate ladder, the group question, worktree recovery,
kept refs, Interfaces checks, the scheduler and most of the Build to Plan loop. Keep groups only where a plan is
large enough to need parallel work. The changelog records this as considered and declined (342-343); the two failed
runs came after that decision.

### 5.4 The model never retypes what the CLI wrote (addresses GUARDFP 15, GUARDHOLE 9, OFFSCRIPT 7, ORCH 16: 47 of 206)

The driver already carries a run with no model in the main session (448-452). Make that the only carrier and close
its hand back list (453-455): each hand back reason is either a CLI call, or a feature to drop (a skill inside the
gate dialog, the HTML plan review, the small change window). With no model transcribing prompts, questions or
commands, character matching has nothing to match, and the shell parsing audits (1018-1047) guard a much smaller
surface. Without the mod, accept the measured Sonnet loop (422-427) and keep only the commit hook.

### 5.5 Proof only from commands the CLI ran, on the tree it judges (addresses EVID: about 15 of 28)

9.8.5 made this the rule for RED, GREEN and Check (53-57). Had it been the rule in 9.7.0, these would not have been
separate patches: scenario criteria passing on a `Traced to:` line (705-711), the Check agent typing results
(226-228), Check's tests row reading the wrong run (1074-1075, 587-591), a stale `integrate` (32), a RED on final
code (48-49), rows the Plan agent writes for its own review (631-634). The remaining EVID items are counting bugs.

### 5.6 Route by how complete the request is (addresses the cost that remains "when nothing goes wrong", ADR 0017:19-20)

The benchmark the project built 9.8.0 on says Temper wins only on vague requests (220-223). Run A's request was a
spec and still went through Intent, 5 Plan passes, 6 reviewers and Design. ADR 0017 proposes the lighter route and
none of it is built (142-144). This is not a patch-prevention change; it is the one that moves the cost and time
numbers, because Plan and Design on Opus are most of a run's cost and the fresh review (24 changes), the Context
check (6), acceptance locks (9) and Design (8) would simply not run for a clear request.

### 5.7 Fewer state writers, and no state that decides nothing (addresses STATE: 40)

9.8.3 put each piece of state behind one table after the fact (164-169). The cheaper version is less state: doors
(9 changes, 8 in 9.7.0), usage accounting (15), task and group branches with kept refs (18) and the small change
window (4) each added keys several writers moved. Sections 5.3 and 5.6 remove most of them.

### 5.8 Split the CLI before the size limit forces it again (POLICY: 25 changes, 4 for file size)

`scripts/temper` has 1,640 bytes of room. Every feature since 9.7.1 has been shaped by that limit. A dispatcher
plus modules, done once, ends that class; the other directory rules are already encoded in
`scripts/validate-directory.sh`.

### What I would not change

- **Intent's questions.** The one stage with measured value on vague requests (221-222, 598-599).
- **The CLI running Check** (226-232) and **the preflight** (14-18): both replaced a model's claim or a late
  discovery with a command the CLI runs.
- **The driver** (448-452): the largest measured saving in the period.

---

## Appendix: all 326 changes

Newest version first. "Adds" as in section 4.3.

| Version | CHANGELOG.md lines | Class | Mechanisms | Adds | Change |
|---|---|---|---|---|---|
| 9.8.5 | 14-18 | ENV | ENVSETUP, PLANROWS | R+1 K+2 C+1 | Preflight: the plan gate runs every Validate, Test, Integration and scenario command once on HEAD; an environment or command fault fails the gate |
| 9.8.5 | 19-20 | PLANDEF | PLANROWS, GROUP | R+1 | Maven is found after `cd backend &&`, `./mvnw`, `mvnd`; new row `maven filtered verify` |
| 9.8.5 | 21-24 | ENV | ENVSETUP | K+4 C+1 Q+1 | `setup:` block applied to every CLI command and put in every agent prompt; `temper doctor`; `doctor --propose` offered as one click |
| 9.8.5 | 25 | ENV | ENVSETUP, GROUP | Q+1 | ENV at a task gate keeps the attempt and the worktree; "Check it again" |
| 9.8.5 | 28-29 | HANDOFF | DESIGN, LOOPBACK, PLANROWS | R+1 | A Design answer given after the plan holds Build until tasks.md changes; Build prompts carry the decisions |
| 9.8.5 | 30-31 | EVID | REVIEWQ |  | `review.block-on` defaults to [critical, high]; medium and above recommend the repair |
| 9.8.5 | 32 | EVID | GROUP |  | `temper integrate` runs the Integration command again when HEAD moved |
| 9.8.5 | 35-36 | REC | GROUP, CHECK |  | The failure text is the build tool's summary, never a passing test's log line |
| 9.8.5 | 37-38 | LOOP | GROUP, LOOPBACK |  | No fix pass without a fault in its prompt; a fix agent that changed nothing keeps the check failed with no rerun |
| 9.8.5 | 39 | REC | CHECK, ENVSETUP |  | Check says SETUP for an environment fault and recommends repairing it, never a loop back |
| 9.8.5 | 40 | REC | CHECK |  | "Override and commit" is offered only where it can clear the row |
| 9.8.5 | 41 | DEADEND | QDIALOG |  | Every question has four options at most |
| 9.8.5 | 41-42 | DEADEND | CONTEXT |  | The Context answer takes 2000 characters ("Include what is left out" was always refused at 100) |
| 9.8.5 | 45-46 | COST | AUTO, REVIEWQ, CHECK | K+1 | `autonomy.policy: decide`: an armed run goes on through Review and Check by fixed rules |
| 9.8.5 | 47 | LOOP | PLANROWS, LOOPBACK, GROUP | C+1 Q+1 | `temper plan patch`: change one command line of the approved plan, keep the passed tasks, spend no loop |
| 9.8.5 | 48 | COST | GROUP |  | A passing check on the same clean tree is reused |
| 9.8.5 | 48 | STATE | LOCK |  | The lock never lets a write through without it |
| 9.8.5 | 48-49 | EVID | EVIDRUN, GROUP |  | A RED made on the final code does not count |
| 9.8.5 | 49 | DEADEND | GROUP |  | Interfaces match by shape |
| 9.8.5 | 49 | HANDOFF |  |  | A person's note is labelled PERSON |
| 9.8.5 | 49-50 | GUARDFP | GUARD, GITBOOK |  | The mod allows a push to a `temper-backup/` branch |
| 9.8.5 | 50 | GUARDFP | GUARD |  | The orchestrator can add a marked note to a question |
| 9.8.5 | 53-57 | EVID | EVIDRUN, CHECK | K+1 C+2 | Only a run the CLI ran counts (`evidence run`); `evidence.claimed-runs`; `evidence void` |
| 9.8.5 | 58-59 | EVID | EVIDRUN, GROUP | K+1 | `task start` records the code files so retries are judged; `build.red-before-code` |
| 9.8.5 | 60 | COST | AUTO, GROUP |  | The policy takes the recommended option at a failed group check |
| 9.8.5 | 61-62 | ENV | ENVSETUP |  | `doctor --propose` reads Gradle toolchains, .java-version, .tool-versions, Docker Compose, virtual environments |
| 9.8.5 | 63-66 | ENV | ENVSETUP | A+1 Q+1 | A setup for any project: rules, CI and devcontainer files, an environment agent (`agents/env.md`); one check |
| 9.8.5 | 67-68 | TEST |  |  | Selftest case file 6 runs on its own |
| 9.8.4 | 77-81 | PLANDEF | PLANROWS, GROUP | R+1 | Fault 1: new row `group validate order` (G1's Validate ran tests a G2 task updated) |
| 9.8.4 | 82-91 | LOOP | GROUP | Q+1 C+1 | Fault 2: a failed group check stops recommending a blind retry; FAIL lines kept; `group fix`; rerun never recommended twice (131 loops on a mock) |
| 9.8.4 | 92-94 | HANDOFF | LOOPBACK, FRESH, INTENT |  | Fault 3a: a step back keeps Plan's open findings; reason and findings reach every stage; Intent revises on a loop back |
| 9.8.4 | 95-96 | DEADEND | FRESH, LOOPBACK |  | Fault 3b: the fresh review round limit no longer dead ends after a loop back |
| 9.8.4 | 96-97 | HANDOFF | LOOPBACK, GROUP |  | Fault 3c: a step back from Build carries each failed group check |
| 9.8.4 | 98-101 | LOOP | FRESH |  | Fault 4: the fresh review converges: `tests` lens, later rounds are rechecks, only high blocks |
| 9.8.4 | 102-103 | COST | GROUP |  | Fault 5: Build model by risk (sonnet for complex or risk H) |
| 9.8.4 | 104-105 | PLANDEF | PLANROWS, GROUP | R+1 | New row `shared production files` |
| 9.8.4 | 106-109 | ENV |  |  | 6a: `run_env.py` keeps git's GIT_CONFIG_* family together (the credential filter broke every git call in cloud sessions) |
| 9.8.4 | 109-110 | TEST |  |  | 6b: each selftest case file starts from an emptied work folder |
| 9.8.4 | 111-112 | HANDOFF | CONTEXT |  | 7a: "Include what is left out" passes the whole text to Plan (was cut to 100 characters) |
| 9.8.4 | 112-113 | STATE | GITBOOK |  | 7b: `.temper/brief.md` listed in info/exclude |
| 9.8.4 | 113-114 | GUARDFP | GUARD | C+1 | 7c: `temper output` (with the mod on, the session cannot run printenv or a test runner) |
| 9.8.4 | 114-115 | ORCH | USAGE |  | 7d: `usage add --fill` puts a background agent's time into its row |
| 9.8.4 | 116-120 | HANDOFF | LOOPBACK, GROUP |  | After a step back to Build the fix pass ends with `temper integrate` (the step back had cleared the scenario rows) |
| 9.8.4 | 120-122 | LOOP | LOOPBACK, GROUP |  | Build failing the same way after "Run Build again" recommends Save for later (40 relaunches before) |
| 9.8.4 | 122-123 | LOOP | CHECK |  | The same at Check for a measurement the run cannot take (52 reruns before) |
| 9.8.4 | 124-128 | TEST | GROUP |  | Haiku against Sonnet task agents measured (18 runs): same quality |
| 9.8.4 | 129-133 | PLANDEF | GROUP | C+1 | `temper task blocked`: a task its plan cannot build is not retried |
| 9.8.4 | 134-138 | LOOP | FRESH, CONTEXT |  | The Context check answer made the fresh review stale and launched a recheck with nothing to check |
| 9.8.4 | 138-141 | BRIEF | INTENT, LOOPBACK |  | The Intent brief revises an accepted intent on a loop back by setting it to draft |
| 9.8.4 | 142-144 | DOC |  |  | Fault 8: ADR 0017 (a request that arrives as a spec), a proposal; nothing built |
| 9.8.4 | 145-149 | STATE | LOCK |  | The lock is never seen without its owner (#114) |
| 9.8.4 | 150-154 | TEST |  |  | pyjokes end to end scenarios in CI; e2e limit 45 to 60 minutes |
| 9.8.4 | 155-158 | POLICY | SIZE |  | Housekeeping: Python moved out of `scripts/temper` to stay under 256 KiB |
| 9.8.4 | 159-162 | POLICY |  |  | The mod's tests type check on Claude Code 2.1.323 |
| 9.8.3 | 171-172 | STATE | LOOPBACK |  | `state loop` takes only stages of the run, backward |
| 9.8.3 | 172-173 | STATE |  |  | `override` takes only a gate of the run; a skip covers the verdict it was given for |
| 9.8.3 | 173-174 | STATE | GROUP |  | Task status moves through one table; a group's status follows its gate; a reopen drops its Continue |
| 9.8.3 | 174-175 | STATE | SMALLCHANGE |  | The small change window opens only at the run's stage and closes on any move |
| 9.8.3 | 175-176 | STATE | LOOPBACK |  | `end_report`, `stage` and the evidence of Commit and Pipeline follow a step back |
| 9.8.3 | 176 | STATE | INTENT |  | `intent complete` refuses a draft |
| 9.8.3 | 176-177 | STATE |  |  | `state set` refuses the CLI's own keys |
| 9.8.3 | 177-178 | STATE | LOOPBACK |  | Build to Plan is once per run in the CLI as in the flow |
| 9.8.3 | 179-180 | EVID | GROUP, EVIDRUN |  | A RED that passed beside an undeclared change or a foreign commit stays FAIL |
| 9.8.3 | 180-181 | STATE | GROUP, INTENT |  | Task readiness, task done, intent status, Blocking questions and finding state each have one definition |
| 9.8.3 | 181 | LOOP | ACCEPT |  | The acceptance writer's launches and corrections are bounded |
| 9.8.3 | 181-182 | UI |  |  | An earlier stage with no verdict shows todo, not passed |
| 9.8.3 | 182 | STATE | GUARD |  | The agents a stage named are kept in `.temper/agents-named.json` |
| 9.8.3 | 183-186 | STATE | LOCK |  | Lock: no row lost under load; freed in one rename; a waiter waits for a live holder |
| 9.8.3 | 187-188 | GUARDFP | GUARD |  | The stop marker names its session; another session's or an old marker no longer blocks |
| 9.8.3 | 188 | GUARDFP | GUARD |  | The fallback commit guard accepts `commit_complete` |
| 9.8.3 | 189 | STATE | DRIVER |  | The run is held when view.json is lost at any stage |
| 9.8.3 | 189-190 | ORCH | DRIVER |  | An interrupt ends the driver as stopped |
| 9.8.3 | 190 | STATE | DRIVER |  | An answer is recorded once |
| 9.8.3 | 190 | GUARDHOLE | GUARD |  | An Allow once is spent after the call ran |
| 9.8.3 | 190-191 | GUARDHOLE | GUARD |  | The skill window and the kept request end with their step and run |
| 9.8.3 | 191 | GUARDHOLE | GUARD |  | `regression_test` is lifted only by the person during a fix run |
| 9.8.2 | 195-198 | DEADEND | CONTEXT, AUTO |  | `plan.context-check: off` passes a pending review (unattended runs parked at the Plan gate) |
| 9.8.1 | 205-209 | POLICY | DRIVER, DIRPOL | C+2 | The mod runs one program with no shell; `temper config init`; `temper guards install` |
| 9.8.1 | 210-212 | POLICY | DRIVER, DIRPOL |  | `/temper:temper` and `/temper:fix` pass on unchanged |
| 9.8.1 | 213-214 | POLICY | DIRPOL |  | The PreToolUse hook only denies |
| 9.8.1 | 215-216 | POLICY | DIRPOL |  | An icon; the README says what the hooks and the mod run |
| 9.8.0 | 226-232 | EVID | CHECK | C+1 K+1 | The CLI runs Check itself (`check run`); the Check agent only for a stack it cannot read |
| 9.8.0 | 233 | ENV | CHECK |  | With no coverage tool the row says what to install |
| 9.8.0 | 236-241 | FEATURE | CHECK | R+1 K+1 | Mutation score gate (`check.mutation-threshold`) |
| 9.8.0 | 242-243 | FEATURE | CHECK | R+1 | Regression proof for a fix |
| 9.8.0 | 244-247 | FEATURE | ACCEPT | A+1 R+1 C+1 | Acceptance tests written before Build (`agents/acceptance.md`), locked |
| 9.8.0 | 248-249 | EVID |  |  | The commit gate's declared files row applies to every run |
| 9.8.0 | 250-251 | EVID | CHECK | Q+1 | A criterion validated by hand is confirmed by the person at Check |
| 9.8.0 | 254-258 | FEATURE | INTENT |  | Intent drafts each open rule as a Blocking question with ready answers; runs on Sonnet |
| 9.8.0 | 259-260 | DEADEND | INTENT | C+1 | Carry forward works (`intent carry`); it left the Intent gate red with no way out |
| 9.8.0 | 261-264 | HANDOFF | CONTEXT, LOOPBACK | Q+2 | The Context check names what the plan leaves out; any other answer sends Plan back |
| 9.8.0 | 265-268 | COST | DESIGN |  | Design runs on risk; `risk` kept by the CLI; a Design concern becomes a Blocking question |
| 9.8.0 | 271-274 | COST | AUTO | K-1 | Unattended with no setting (`autonomy.enabled` no longer read) |
| 9.8.0 | 275 | COST | GROUP | Q-1 | A plan with one group goes on to the merge by itself |
| 9.8.0 | 276 | COST | USAGE | Q-1 | The report page is written without a question |
| 9.8.0 | 279-282 | COST | DRIVER | C+1 | `temper go`: the CLI runs its own steps (59 of 88 tool calls) |
| 9.8.0 | 283-286 | COST |  |  | The loop runs on Sonnet |
| 9.8.0 | 287-289 | COST | GROUP |  | One build agent per chain |
| 9.8.0 | 290-291 | COST | GITBOOK |  | The commit message is drafted by the CLI |
| 9.8.0 | 292 | COST | GROUP | Q-1 | "Accept it as done" records its reason itself |
| 9.8.0 | 295-298 | HANDOFF | LOOPBACK, CHECK |  | A step back from Check carries what failed (two runs at $26.91 and $38.24) |
| 9.8.0 | 299-303 | DEADEND | ACCEPT, CHECK | Q+1 C+1 | A wrong locked acceptance test has a way out ("Correct the acceptance test") |
| 9.8.0 | 304-306 | EVID | ACCEPT | Q+1 C+1 | A lock is taken once; "Restore the locked tests" |
| 9.8.0 | 307-310 | DEADEND | PLANROWS, DESIGN |  | Design may change the tasks (Build refused to start: "the approved plan changed") |
| 9.8.0 | 311-312 | REC |  | Q+1 | Files outside the plan at the commit gate: "Add to plan" first |
| 9.8.0 | 315-318 | COST | CHECK | C+1 | Check runs while Review reads (`check ahead`) |
| 9.8.0 | 319-321 | COST | DESIGN |  | Design on a fully specified request is skipped |
| 9.8.0 | 322-325 | REC | ACCEPT, CHECK, LOOPBACK | C+1 | A failing locked test is triaged by an agent before a Build round |
| 9.8.0 | 326-328 | BRIEF | INTENT | R+1 | The rules checklist is recorded; the Intent gate fails a missing item |
| 9.8.0 | 329-330 | REC | INTENT |  | House rules first |
| 9.8.0 | 331-332 | EVID | ACCEPT |  | Every state is tested; `acceptance lock` refuses tests that never name a listed state |
| 9.8.0 | 333-334 | POLICY | SIZE |  | `scripts/temper` under 256 KiB again |
| 9.8.0 | 337-338 | LOOP | GROUP |  | "Accept it as done" looped |
| 9.8.0 | 339-340 | STATE |  |  | The CLI called from a subfolder started a second `.temper` |
| 9.8.0 | 342-343 | DOC | GROUP |  | Not done on purpose: small plans still build in worktrees |
| 9.8.0 | 345-346 | TEST |  |  | The benchmark moved to `bench/` |
| 9.8.0 | 357-364 | OFFSCRIPT | GUARD |  | The main session relays, and the mod holds it to that (a Haiku session edited spec files and locked tests) |
| 9.8.0 | 365-366 | GUARDFP | GUARD |  | The CLI set in a variable in the same command is read as the CLI |
| 9.8.0 | 367-369 | OFFSCRIPT | GUARD, INTENT |  | A run starts from the person's request word for word |
| 9.8.0 | 370-371 | GUARDFP | GUARD, INTENT |  | The Intent prompt carries the request with one period (the guard refused the launch as another prompt) |
| 9.8.0 | 372 | OFFSCRIPT | LOOPBACK | C+1 | A typed change request goes to the stage's agent (`state redo --reason`) |
| 9.8.0 | 373-375 | GUARDFP | GUARD |  | The view carries what the guard needs (`next.agents`, `blocking_asks`, an option's `skill`) |
| 9.8.0 | 378-381 | PLANDEF | PLANROWS | R+1 | New row `request routes kept` (a Plan built the request's route as another path) |
| 9.8.0 | 384-387 | COST | INTENT | C+1 | `temper intent answer` (two to four turns a stage saved) |
| 9.8.0 | 388-391 | COST | GITBOOK | C+3 | `temper spec branch`, `spec commit`, `spec deviations` |
| 9.8.0 | 392-393 | COST |  |  | An agent's gate call prints its failed rows only (`gate --brief`) |
| 9.8.0 | 394 | COST | DRIVER |  | `temper go`'s question is slimmer |
| 9.8.0 | 395-396 | GUARDFP | GUARD, LOOPBACK |  | A fix pass's findings are short in the prompt (a traceback was copied wrong, the launch refused) |
| 9.8.0 | 397-398 | COST |  |  | The fix run's lesson is written by the Fix agent |
| 9.8.0 | 399-400 | GUARDFP | GUARD, GROUP |  | Every view is written by one path (`group start` named another model; the guard refused the launch) |
| 9.8.0 | 403-404 | BRIEF |  |  | Plan and Design are told never to read the plugin's scripts |
| 9.8.0 | 407-413 | TEST | USAGE |  | Benchmark: a resumed run was counted twice; prices from session logs |
| 9.8.0 | 415-428 | TEST |  |  | Round 5 measured; the loop stays on Sonnet |
| 9.8.0 | 431-435 | COST | PANEL | C+1 | The CLI draws the Plan, Design and RCA panels (2,000 to 3,000 output tokens and 30 to 40 s a stage) |
| 9.8.0 | 436-441 | COST |  | C+1 | The project brief (`temper brief`) |
| 9.8.0 | 442-445 | BRIEF | INTENT |  | Intent asks Who, When and How much first |
| 9.8.0 | 448-452 | COST | DRIVER |  | The mod carries the run (the run driver), no model in the main session |
| 9.8.0 | 453-456 | ORCH | DRIVER |  | The driver hands the run to the conversation for what needs a model |
| 9.8.0 | 457-460 | ORCH | DRIVER |  | An option the conversation must carry out is handed over before any call; steps are handed over whole |
| 9.8.0 | 461-462 | COST | DRIVER |  | `/temper:fix` is carried too |
| 9.8.0 | 463-465 | TEST | DRIVER |  | The e2e driver gains a third mode, `driver` |
| 9.8.0 | 466-470 | ORCH | DRIVER |  | The driver's dialog shows descriptions and previews; an interrupt stops it; a CLI call streams |
| 9.8.0 | 471-475 | ORCH | DRIVER, PANEL |  | Terminal check: a panel logged in one call was drawn as one row and cut at 2000 characters |
| 9.8.0 | 475-476 | ORCH | DRIVER |  | Terminal check: at Esc the read threw, taken for a failure and handed to the conversation |
| 9.8.0 | 478-479 | FEATURE | DRIVER |  | The mod's reviewed calls gain `agent.spawn`, `ui.ask`, `ui.log`, `clock.now`, `process.spawn` |
| 9.8.0 | 480-483 | ORCH | DRIVER, INTENT |  | A driver defect handed the run back at the Intent gate |
| 9.8.0 | 484-492 | TEST |  |  | The final pass and the shipped code measured |
| 9.8.0 | 495-500 | COST | PANEL, GROUP | C+1 | The CLI draws each Build task's panel (about a minute of each Haiku agent's three) |
| 9.8.0 | 501-506 | COST |  |  | A command that would wait for input until the Bash timeout is refused (480 s in 3 runs) |
| 9.8.0 | 507-510 | TEST |  |  | Measured (10 runs): a Build task agent 122 s against 193 s |
| 9.8.0 | 513-517 | FEATURE | AUTO, LOOPBACK |  | Autonomous is Build alone; an armed Review or Check no longer loops back by itself |
| 9.8.0 | 518-520 | STATE | DRIVER |  | One answer is one decision (the pane listed it twice) |
| 9.8.0 | 521-524 | UI |  |  | A stage that waits for the person is not red (`waits`) |
| 9.8.0 | 525-528 | UI | PANEL, DRIVER |  | Panels in the mod's output are a few rows |
| 9.8.0 | 529-531 | UI |  |  | A Temper agent's message is drawn in full (not yet seen live) |
| 9.8.0 | 532-535 | COST | DRIVER, INTENT |  | The Blocking questions come in one dialog (the driver asked six in six dialogs) |
| 9.8.0 | 536-540 | REC | FRESH |  | Fresh review findings below high are the person's call; "Revise the plan" recommended for a medium one |
| 9.8.0 | 541-545 | DEADEND | GROUP, GUARD, QDIALOG |  | A manual task's name question can be shown (it held one option; the run stopped there) |
| 9.8.0 | 546-548 | REC | SMALLCHANGE |  | "Make a small change" says who makes it |
| 9.8.0 | 549-558 | STATE | GITBOOK, GROUP |  | An earlier attempt of the same run name no longer blocks Build (leftover branches and worktrees) |
| 9.8.0 | 559-562 | ORCH | DRIVER, GROUP |  | The driver starts every task before it launches any agent |
| 9.8.0 | 563-567 | STATE | GITBOOK, GROUP | K+1 | Earlier attempts' branches leave `git branch` (`build.grouped.keep-days`) |
| 9.8.0 | 568-570 | POLICY | SIZE |  | Room in the CLI: 886 bytes were left under 256 KiB |
| 9.8.0 | 571-576 | REC |  | Q-1 | The words of a question match the run (More options, fix run wording, the page question gone) |
| 9.8.0 | 579-583 | BRIEF | INTENT |  | Exempt is an item of the rules checklist |
| 9.8.0 | 584-586 | BRIEF | INTENT |  | A rule the request states decides its edges |
| 9.8.0 | 587-591 | EVID | ACCEPT, CHECK, LOOPBACK |  | A corrected acceptance test that fails again keeps the acceptance path (two Build rounds, then an override) |
| 9.8.0 | 592-597 | ORCH | DRIVER, GROUP |  | A Build task agent that stops before its gate no longer hands the run back |
| 9.8.0 | 598-599 | TEST |  |  | Measured (7 runs) |
| 9.8.0 | 600-601 | DOC | ACCEPT |  | Not done, measured: the acceptance writer beside Design |
| 9.8.0 | 604-607 | PLANDEF | GROUP, PLANROWS |  | A scenario is owed by the task that writes its test file (the gate could never pass) |
| 9.8.0 | 608-609 | LOOP | GROUP |  | A group parked again after a rerun recommends Loop back to Plan (six failures on every model) |
| 9.8.0 | 610-611 | ENV | ACCEPT |  | `acceptance lock` runs the command once and refuses one that cannot run here |
| 9.7.6 | 619-625 | FEATURE | FRESH, PLANROWS | A+1 R+3 | The fresh review of the plan (`agents/plan-review.md`): three lenses, three plan gate rows |
| 9.7.6 | 626-628 | FEATURE | FRESH | K+1 Q+1 C+1 | The person chooses it (`plan.fresh-review: ask`): "Fresh review first" |
| 9.7.6 | 629-630 | FEATURE | FRESH |  | The paraphrase is in the plan question |
| 9.7.6 | 631-634 | EVID | FRESH | C+1 | The CLI marks each launch; an edit makes the review stale |
| 9.7.6 | 635-636 | EVID | FRESH |  | A lazy review does not pass |
| 9.7.6 | 637-638 | LOOP | FRESH | K+1 | A round limit (`plan.fresh-review-rounds`, 3) |
| 9.7.6 | 639-640 | FEATURE | FRESH, LOOPBACK | Q+1 | "Revise the plan" runs the Plan agent again with each open finding |
| 9.7.6 | 641 | FEATURE | FRESH | K+1 | A risk H plan gets two independent reviewers (`plan.fresh-review-twice`) |
| 9.7.6 | 642 | FEATURE | FRESH, DOORS |  | A plan entered through a stage command gets the fresh review |
| 9.7.6 | 645-647 | EVID | REVIEWQ, FRESH | C+1 | `evidence contest` with a checked citation |
| 9.7.6 | 648 | FEATURE | REVIEWQ, FRESH | C+1 | `evidence escalate` |
| 9.7.6 | 649-650 | FEATURE | FRESH |  | A comprehension finding is never contested |
| 9.7.6 | 651-653 | REC | REVIEWQ, FRESH |  | Contested and escalated findings come first at the accept question |
| 9.7.6 | 656-658 | EVID | FRESH | Q+1 C+1 | A reviewer that stopped is not a clean review; "Run the fresh review again" |
| 9.7.6 | 661-664 | FEATURE |  | C+1 | `temper drift` |
| 9.7.6 | 666-673 | TEST | FRESH |  | Evidence: A/B plan gate, cost ($0.17 and 37 s a plan), a live run |
| 9.7.6 | 676-679 | UI | FRESH |  | The pane shows the fresh review |
| 9.7.6 | 680-681 | FEATURE | FRESH | K+1 | `reviewerModel` and `models.plan-review` |
| 9.7.6 | 684-687 | TEST | FRESH |  | A live smoke check of the fresh review |
| 9.7.6 | 688 | REC | FRESH |  | A plan question that failed on another row did not carry the paraphrase |
| 9.7.6 | 691 | DOC |  |  | The README is short |
| 9.7.6 | 692-693 | DOC |  |  | The website videos |
| 9.7.6 | 694-697 | TEST |  |  | Tests: case file 14; suite counts |
| 9.7.5 | 705-711 | EVID | PLANROWS, GROUP | R+2 | A scenario criterion passed on a `Traced to:` line (F7 to F9): `Test:` commands, `criteria validated` |
| 9.7.5 | 712 | EVID | INTENT | R+1 | The Intent gate passed over an open Blocking question (F10) |
| 9.7.5 | 713-716 | FEATURE | CONTEXT | K+1 Q+1 C+1 | The Context Map and `plan.context-check` (F6) |
| 9.7.5 | 717 | EVID |  | C+1 | Risk was Plan's estimate (F11): `temper risk` computes it |
| 9.7.5 | 718-720 | EVID | PLANROWS, GROUP | Q+1 C+1 | tasks.md parsing; a manual task confirmed by the person; the all-tasks check passed with one of eight done (F12) |
| 9.7.5 | 723 | LOOP | GROUP | Q+1 | Change reopened every task (F13) |
| 9.7.5 | 724-725 | LOOP | SMALLCHANGE, LOOPBACK | Q+1 C+2 | A small change needed a loop back (F14): `adhoc open` and `adhoc close` |
| 9.7.5 | 726 | DEADEND | GROUP |  | Build stopped when the mod was off (F15) |
| 9.7.5 | 727 | DEADEND | GROUP, PLANROWS | K+1 | A plan with tasks and no groups reached a Build with nothing to run (F16); `max-groups` |
| 9.7.5 | 727-728 | ENV | GROUP | Q+1 | A group gate records a timeout and offers a rerun at double the limit (F17) |
| 9.7.5 | 729 | ENV | GROUP |  | Tests imported the wrong copy (F18): the folder first on PYTHONPATH |
| 9.7.5 | 730-731 | LOOP | GROUP | Q+1 C+2 | A task an earlier task built was retried and parked (F19); the person decides |
| 9.7.5 | 732-733 | COST | CHECK |  | Scoped tests, one suite run (F20) |
| 9.7.5 | 734 | EVID |  |  | Blast radius counted Temper's own files (F21) |
| 9.7.5 | 735-736 | ENV | GROUP, PLANROWS | R+1 | Maven (F22): `maven_loop.py`; row `maven group verify` |
| 9.7.5 | 739-746 | REC | CHECK | Q+1 | A missing tool sent the run back to Build: "Run Check again" |
| 9.7.5 | 747-749 | ENV | PIPELINE |  | Pipeline could not read the checks in a cloud session (GraphQL 403) |
| 9.7.5 | 750-754 | LOOP | PIPELINE, SMALLCHANGE |  | A CI fix sent Review, Check and the commit gate again |
| 9.7.5 | 755-757 | BRIEF | PIPELINE | R+1 | The Pipeline agent guessed a fix path and a round limit; row `fix paths` |
| 9.7.5 | 760-761 | FEATURE | PIPELINE | A+1 K+1 Q+3 R+2 | The Pipeline stage, draft pull requests, stacked parts (F23, F24, F26) |
| 9.7.5 | 762 | DEADEND | GITBOOK |  | No record commit when there is nothing to stage (F27; the hook refused the empty commit) |
| 9.7.5 | 762 | HANDOFF | LOOPBACK |  | A fix pass reads the latest loop reason (F27) |
| 9.7.5 | 765 | STATE | GITBOOK | Q+1 | Branch clash (F28) |
| 9.7.5 | 765 | GUARDFP | GUARD, GITBOOK |  | The commit hook gates the run's branch only (F29) |
| 9.7.5 | 765 | STATE | GUARD | C+1 | `temper guards uninstall` (F30) |
| 9.7.5 | 766 | UI |  |  | The band shows no failed rows while an answer is carried out (F31) |
| 9.7.5 | 767 | HANDOFF |  |  | Notes and typed answers reach the next agent (F1) |
| 9.7.5 | 767 | OFFSCRIPT |  |  | The wait text and every `say` are sentences for the person (F3) |
| 9.7.5 | 767-768 | ORCH |  |  | A failed call stops its action (F4) |
| 9.7.5 | 768 | COST |  |  | `temper next` starts one Python process (F5; 2.2 s before) |
| 9.7.5 | 768 | UI |  |  | The models and their sources are shown (F2) |
| 9.7.5 | 787-788 | FEATURE |  | Q-1 | The readiness skill (F25) is taken out |
| 9.7.5 | 790 | TEST |  |  | The selftest refuses a CLI call outside its own folder |
| 9.7.5 | 791-792 | TEST |  |  | A parallel selftest runner with tiers |
| 9.7.5 | 792-795 | TEST |  |  | The e2e driver (16 scenarios) and the mod answer audit |
| 9.7.5 | 796-797 | GUARDFP | GUARD, GITBOOK |  | The mod refused the command the CLI wrote to carry the spec files across a branch switch |
| 9.7.5 | 799-801 | DOC |  |  | Migration |
| 9.7.5 | 803-808 | TEST |  |  | Suite counts |
| 9.7.4 | 818-821 | POLICY | DIRPOL |  | No key in CI |
| 9.7.4 | 823-831 | POLICY | DIRPOL, USAGE |  | No token count; usage is time only |
| 9.7.4 | 833-836 | POLICY | DIRPOL |  | No credential handed to a test (credential-named variables stripped) |
| 9.7.3 | 848-856 | POLICY | DIRPOL |  | Test helpers no longer write a hook through a split name; rule 13 |
| 9.7.3 | 858-864 | POLICY | DIRPOL | Q-1 C-1 | `temper init --foreground-agents` removed |
| 9.7.3 | 868-874 | POLICY | DIRPOL |  | `guard-entries.py` removed; `enable guardrails` prints the entries |
| 9.7.3 | 875-880 | POLICY | DIRPOL |  | No `git config user.name` or `user.email`, no `$USER` |
| 9.7.3 | 881-882 | POLICY | DIRPOL, USAGE |  | `--tokens` renamed `--token-count` |
| 9.7.3 | 883-884 | POLICY | DIRPOL |  | The tests write no stand-in settings file |
| 9.7.3 | 888-889 | POLICY | DIRPOL |  | The bar's Go on button is gone |
| 9.7.3 | 890-892 | POLICY | DIRPOL | Q-1 | `mode` and `enforcement` no longer change settings; the first run mode question is gone |
| 9.7.3 | 893-895 | POLICY | DIRPOL |  | The mod's reviewed calls go from 18 to 13 |
| 9.7.3 | 897-898 | DOC | DIRPOL |  | The docs say the same |
| 9.7.2 | 910-922 | POLICY | DIRPOL |  | No script names a folder like one of the mod's (`tests` to `unit`); rules 10 and 12 |
| 9.7.2 | 923-927 | POLICY | DIRPOL |  | Other names a reader could take for the mod's |
| 9.7.2 | 929-938 | POLICY | DIRPOL, USAGE |  | The CLI reads no Claude Code file (`usage_cost.py` deleted, no cost) |
| 9.7.2 | 940-941 | GUARDHOLE | GUARD |  | The secret guard no longer repeats a secret |
| 9.7.2 | 943-950 | DOC | DIRPOL |  | The README says what the mod sets, runs and hooks |
| 9.7.1 | 963-966 | POLICY | DIRPOL |  | `.gitattributes` with `eol=lf` |
| 9.7.1 | 968-974 | POLICY | SIZE, DIRPOL |  | No file over 256 KiB (`task_ops.py` split out) |
| 9.7.0 | 978-984 | FEATURE |  | C+1 | The CLI says what comes next (`temper next`, view.json); `commands/temper.md` 6,870 to 2,117 words |
| 9.7.0 | 986-989 | FEATURE | DOORS |  | One flow; the stage commands are doors into `/temper` |
| 9.7.0 | 991-996 | FEATURE | GUARD |  | The guard claims only what it can enforce; the mod's shell parser is deleted |
| 9.7.0 | 998-1003 | UI |  |  | The mod draws the run from view.json; the game is removed |
| 9.7.0 | 1005-1011 | FEATURE | GROUP | A+1 K+3 | Build runs in groups of Haiku task agents: retry, escalate, park |
| 9.7.0 | 1013-1015 | EVID |  |  | A verdict of the active run is computed from its own spec folder; TEMPER_CONFIG not followed |
| 9.7.0 | 1015-1016 | EVID | PLANROWS |  | The plan gate records the digest of the approved tasks.md; no agent writes it from Design on |
| 9.7.0 | 1016-1018 | ENV | GROUP |  | A project below the top of its repository builds in its own folder |
| 9.7.0 | 1018-1021 | GUARDHOLE | GUARD |  | The guard reads `$'..'` quotes, brace lists and globs; refuses a git config that switches the hook off |
| 9.7.0 | 1021 | GUARDFP | GUARD |  | A copy into the spec folder is no longer refused |
| 9.7.0 | 1021 | GUARDHOLE | GUARD |  | At Commit only the spec folder is written |
| 9.7.0 | 1022 | STATE |  |  | `base_sha` is recorded once |
| 9.7.0 | 1022-1023 | REC | DOORS |  | A door's walked stage whose check fails offers to run it |
| 9.7.0 | 1023 | OFFSCRIPT | GROUP | Q+1 | A commit the CLI did not make on a group's branch is a question |
| 9.7.0 | 1024 | STATE | GITBOOK |  | The commit step skips a file deleted in a commit |
| 9.7.0 | 1024 | EVID | EVIDRUN |  | `gate build` wants the passing run after the failing one |
| 9.7.0 | 1024-1025 | DEADEND | REVIEWQ | Q+1 | A Review that did not finish offers to run again |
| 9.7.0 | 1025 | STATE |  |  | `config get fix.max-loops` prints the limit the loop keeps |
| 9.7.0 | 1025-1026 | REC |  | Q-1 | The plan gate has no "Walk through step by step" option |
| 9.7.0 | 1028-1031 | GUARDHOLE | GUARD |  | Second audit: copy targets, brace lists, glob classes, HOME and XDG_CONFIG_HOME |
| 9.7.0 | 1031-1032 | GUARDFP | GUARD |  | A config suggestion may go into `.claude/AGENTS.md` |
| 9.7.0 | 1032-1033 | GUARDHOLE | GUARD, GITBOOK |  | The hook and the commit gate read a rename by both its names |
| 9.7.0 | 1033-1034 | STATE | GITBOOK |  | A project folder with a glob character keeps its run files out of git status |
| 9.7.0 | 1034-1035 | STATE | GROUP |  | After Keep the commits the next step merges the groups again |
| 9.7.0 | 1037-1039 | STATE | GITBOOK |  | The accepted intent was committed on the person's branch (often main) |
| 9.7.0 | 1039 | STATE | GROUP |  | A group that builds on another starts only after the person's Continue |
| 9.7.0 | 1040 | REC | REVIEWQ |  | A passed Review with open findings below the blocking severity offers Loop back to Build |
| 9.7.0 | 1041-1042 | STATE | USAGE |  | The report prints before the run state is cleared |
| 9.7.0 | 1042 | EVID | CHECK |  | The Check marker of the tests reads no scenario row |
| 9.7.0 | 1042-1043 | STATE | GITBOOK |  | The last commit's message when Build committed the code |
| 9.7.0 | 1043-1044 | ORCH | USAGE |  | A background agent's tokens and time come from its completion notice |
| 9.7.0 | 1044-1046 | GUARDHOLE | GUARD |  | A second narrow review closed more ways around the guard |
| 9.7.0 | 1046-1047 | GUARDFP | GUARD |  | A glob in a call is refused only when it could spell a word the person decides (`--model sonnet[1m]`) |
| 9.7.0 | 1047-1048 | LOOP | GROUP | Q+1 | After Keep the commits the person is asked before the groups merge again |
| 9.7.0 | 1050-1051 | STATE |  |  | A `/temper:fix` run in a fresh project runs the setup calls |
| 9.7.0 | 1051-1052 | HANDOFF | LOOPBACK |  | A loop back to Build keeps what Review or Check left open |
| 9.7.0 | 1052-1053 | STATE | GITBOOK |  | The last commit's message when the code is already committed (second patch) |
| 9.7.0 | 1053-1054 | STATE |  |  | `state clear` keeps the ledger `state archive` wrote |
| 9.7.0 | 1054-1055 | STATE | GITBOOK, CHECK |  | `.temper/coverage/` kept out of git status |
| 9.7.0 | 1056-1059 | UI |  |  | `temper next` names the model before each launch |
| 9.7.0 | 1060 | DEADEND | DESIGN, LOOPBACK | Q+1 | A passed Design offers Loop back to Plan |
| 9.7.0 | 1061 | HANDOFF | LOOPBACK |  | A loop back to Intent, Plan or Design gives the agent the person's reason |
| 9.7.0 | 1063-1065 | EVID | DOORS, REVIEWQ |  | A door into Review or Check reads the run's diff from where the feature started (it read an empty diff) |
| 9.7.0 | 1065-1067 | STATE | DOORS, DESIGN |  | `state init --enter` takes the tier from plan.md |
| 9.7.0 | 1067-1068 | STATE | GITBOOK |  | The last commit of a run whose code is all committed (third patch) |
| 9.7.0 | 1068-1072 | DEADEND | DOORS |  | A door's walked Build passes on the newest Build PASS (before, it always failed) |
| 9.7.0 | 1072-1074 | DEADEND | DOORS, LOOPBACK |  | A loop back from a door's run runs the stage it goes back to |
| 9.7.0 | 1074 | EVID | DOORS |  | `enter` and `built_before` are the CLI's keys |
| 9.7.0 | 1074-1075 | EVID | CHECK |  | Check's tests row reads the latest run of each test command |
| 9.7.0 | 1075-1076 | REC | CHECK, LOOPBACK | Q+1 | A passed Check offers Loop back to Build |
| 9.7.0 | 1077-1079 | OFFSCRIPT | REVIEWQ | R+1 | Review writes no code (a live Review fixed a critical finding itself) |
| 9.7.0 | 1079-1080 | HANDOFF | LOOPBACK |  | A loop names only the feedback file of the stage it came back from |
| 9.7.0 | 1081-1083 | ORCH |  |  | Stage agents launch in the foreground; a completion notice is the agent's return (a run sat idle) |
| 9.7.0 | 1083-1088 | ORCH |  | Q+1 C+1 | `temper init --foreground-agents` asks to add an environment variable to settings |
| 9.7.0 | 1088 | REC | AUTO |  | A parked commit question says the armed run parked there |
| 9.7.0 | 1090-1092 | REC | DESIGN, AUTO |  | The Design question names each open concern; an armed run parks at a Design with open concerns |
| 9.7.0 | 1093-1095 | STATE |  |  | `temper next` no longer lists `temper init` after every finished run |
| 9.7.0 | 1096-1097 | UI | PANEL |  | A task agent's box gives exit codes; the RCA box wraps |
| 9.7.0 | 1097-1099 | ENV |  |  | Inline Python runs isolated (`python3 -I`): a project's `json.py` ran on every call |
| 9.7.0 | 1101-1103 | UI | DESIGN |  | The `resolved:` line is a paragraph of its own |
| 9.7.0 | 1103-1105 | COST | GROUP |  | A passing group Validate prints only its last 12 lines |
| 9.7.0 | 1105-1108 | STATE | DOORS, PLANROWS | R+1 | `state set complexity` writes the tier into intent.md; row `tier recorded` |
| 9.7.0 | 1110-1117 | ORCH | USAGE |  | The report showed zero tokens and time; the CLI reads the agent's transcript |
| 9.7.0 | 1117-1120 | FEATURE | USAGE |  | An estimated cost at API list prices |
| 9.7.0 | 1120-1122 | FEATURE | USAGE | Q+1 | The report prints before the commit; a question offers the HTML page |
| 9.7.0 | 1123-1125 | ORCH | USAGE |  | The orchestrator records an agent at the first of its report and its notice (a run waited) |
| 9.7.0 | 1126-1128 | ENV | USAGE |  | No cost shown: a gateway prefix in the model names |
| 9.7.0 | 1128-1130 | OFFSCRIPT | USAGE |  | A run skipped the HTML question and the report: both were instructions in a list |
| 9.7.0 | 1131-1137 | STATE | USAGE |  | A run priced only its Sonnet stages; a partial cost is marked `+` |
| 9.7.0 | 1139-1145 | UI |  |  | The pane opens for a run started in the session |
| 9.7.0 | 1147-1154 | DOC |  |  | Two videos |
| 9.7.0 | 1156-1157 | DOC |  |  | Migration |
