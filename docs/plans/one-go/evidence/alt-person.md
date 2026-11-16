# Temper, from the person's side: an independent plan

Lens: the person in front of the run, and their trust. Tree read: `/home/user/temper` at `10e965a` (PR #115 head,
9.8.5). Paths are relative to it. Marks: **[code]** I read the line at `10e965a`; **[xc]** a figure from
`understand/_crosscheck.md` (which cites the evidence documents); **[reader]** a reader's measurement I did not repeat.
Nothing was run or written in the repository. I read no other planner's draft.

## 0. The plan in fifteen lines

1. **Two dialogs on a clean run, three on a vague one.** One approval before any code (intent and plan on one card),
   one at the end (the result, with its numbers, before the click). Rules the request left open are asked once, in one
   dialog, before the plan. Today the same run has 8 dialogs (6 + G) and a live mean of 13 [xc §3, §5 row 2].
2. **A passed check never asks.** It is a move of the CLI. The guard already treats only two forward moves as the
   person's (`hooks/temper-mod/core/rules.ts:491` [code]); the code path exists and is shipped off
   (`scripts/flow.py:296-298, 2441-2472` [code]).
3. **A failed check gets one repair by rule, then one card.** No recommendation is ever repeated after the same failure.
4. **The first run measures the project instead of asking the person to configure it.** The suite runs once in the
   background from second 0; its time and coverage set the limits and the coverage rule. Today a project at 55%
   coverage, or a Maven project, ends its first run red with correct code (`scripts/temper:3864, 3908-3912`,
   `scripts/check_run.py:140-144`, `scripts/flow.py:874-875` [code]).
5. **The surface shrinks to what a person uses:** 2 commands (11 today), 0 listed skills (5), a config of about 10
   lines written from what was measured (171 lines, 53 keys), about 12 words of vocabulary (115) [reader: ux §2].
6. **PR #115:** do not merge it as one thing. Its work-saving parts and its honesty fixes help a default user; four of
   its defaults hurt one (section 6).
7. **Target for a clear medium feature, with the mod:** 2 dialogs, 5 or 6 agent launches, the first decision within
   2 minutes, done within 8 to 10 minutes, about $1.00. Plain Claude Code on the same task: 0 dialogs, 88 to 99 s,
   $0.43 to $0.49 [xc §3]. Temper will not match that and should not claim to; the target is 2 times its dollars
   instead of 4 to 5, and two informed clicks instead of thirteen.
8. **A surface budget in CI** keeps it there: the counts above become numbers a pull request cannot raise without
   lowering another.

---

## 1. Targets, in run units

Reference run: a clear, medium feature, risk below H, 2 Build tasks, the mod's driver carrying the run [xc §3].

| Unit | Plain Claude Code | Temper today (default) | After steps 0 to 5 (rules, cards, first use) | After step 6 (Plan cost) |
|---|---|---|---|---|
| Dialogs, clear request | 0 | 8 (6 + G, G = 2); 6 with one group [xc §3] | **2** | 2 |
| Dialogs, vague request | 0 (it guesses: 73% of the rules met, against 98%) [xc row 2] | 9 to 10 (plus 1 or 2 Blocking dialogs) | **3** | 3 |
| Dialogs added by one failed check | n/a | 4 to 5 (reason, Build, Review, Check again) [xc §5 row 3] | **0** when the one repair works, **1** when it does not | same |
| Agent launches | 0 | 6 (4 + T) [xc §3] | 6; +1 per repair (today +2) | 5 or 6 |
| Seconds to the first decision | n/a | 175 to 295 s of machine time, behind two earlier dialogs (Intent gate, Context check) | 175 to 295 s, no earlier dialog | **120 s or less** |
| Whole run, wall time | 88 to 99 s | 597 to 865 s with a person who answers at once [xc §3]; a real person's time at 8 dialogs is on top and unmeasured [xc gap 11] | the same agent time, 2 dialogs | **8 min** (builders on Sonnet) or **10 min** (on Haiku) |
| Dollars | $0.43 to $0.49 | $1.02 to $1.70 for a clean run with no Design (Plan $0.75 to $1.13, Build $0.07, the rest $0.2 to $0.5); $1.93 to $2.50 measured with Design or a repair round [xc §3] | unchanged on a clean run; a repair costs about half of today's $0.40 to $0.50 | **$1.00 or less** ($1.25 with Sonnet builders) |
| Without the mod | n/a | +$0.28 to $0.97, 183 to 206 s outside the agents [xc row 18, §3] | same dialogs; fewer relay turns (section 8) | +$0.30 or less |

What steps 0 to 5 do not change is the dollars of a clean run: with the driver the main session already costs $0.00
[xc row 10]. The dollars are in Plan on Opus, which is step 6 and needs one paid measurement first.

---

## 2. Who decides what

### 2.1 Always the person's decision (a dialog, never a rule)

| # | Decision | Why it cannot be a rule | Where it is asked |
|---|---|---|---|
| 1 | Approve the intent and the plan, before any code | the promise (`README.md:3` [code]); it commits the spend and fixes the files | the approval card |
| 2 | The rules the request left open (Blocking questions) | only the person knows them; the one stage with a measured gain [xc row 2] | one dialog, before the plan |
| 3 | Anything that leaves the run's branch or the machine: push, pull request, merge | not reversible by Temper | the finish card |
| 4 | Skip a failed check; accept an open finding | it lowers the bar the person was promised | the failure card, the finish card |
| 5 | A file outside the approved plan; a protected path the plan did not name | scope is what was approved in 1 | Scope drift question (as today) |
| 6 | Change a locked acceptance test; confirm a criterion only a person can see | the test is the person's intent in code | the failure card; one confirm click |
| 7 | Plan again after Build started (it discards built work, `scripts/temper:1276-1279` [xc row 11]) | minutes and dollars, and the approved plan changes | the failure card |
| 8 | A second repair of the same failure | repeating the recommendation looped 131, 40, 52 and 72 times [xc §5 row 10] | the failure card |
| 9 | Any config line that loosens a check (coverage floor, skipping the baseline, `review.block-on`) | same as 4, for every later run | the person's editor |
| 10 | Keep commits the CLI did not make; start over; discard a run | destroys or adopts work | as today |

### 2.2 Never automated, in any mode

Push, pull request, merge to a remote (`scripts/flow.py:887-892` [reader]); an override or an accepted finding
(`scripts/flow.py:1144-1148` [code]); a new plan without asking (PR #115 breaks this under its policy,
`scripts/flow.py:1963-1972` [xc row 12], section 6); editing the person's config or Claude Code settings; lowering a
threshold; changing a locked acceptance test; taking the same action twice on the same failure.

### 2.3 What a fixed rule may decide

| Rule | Today |
|---|---|
| Any passed check moves on: Intent (nothing open), Design (no open concern, tasks unchanged), each group, Build, Review (no open finding at high or above), Check | asked every time; constant recommended answers at `scripts/flow.py:635, 730, 749, 784, 817, 1943` [code] |
| The context check with no `ignore` and no `gap` line passes; with one, the lines go on the approval card | a dialog on every run [xc row 1] |
| One repair per failure: a failed group check launches the group fix agent once; a finding at high or above gets one fix and a recheck of the fix; a Check failure in the code gets one fix and a rerun of the failed rows | a loop through Build, Review and Check, 4 to 5 dialogs [xc §5 row 3] |
| An environment fault stops the run at once, with no retry | already so at a task (`scripts/flow.py:1857-1870` [reader]; the option at `:1867` [code]) |
| A task whose tests already pass is taken as done | an armed run does this (`scripts/flow.py:1837-1842` [reader]) |
| Time limits are 3 times the measured time, doubled once after a time-out, then asked | fixed 300 s, 600 s, 3600 s (`scripts/preflight.py:31`, `scripts/temper:2441, 3053, 3321` [code]); doubling is a question |
| Coverage: the total may not drop below what the project had before the run; no coverage tool means "not measured", shown on the finish card | an absolute 80% of the whole project (`scripts/temper:3864` [code]) |
| A medium or low finding is listed on the finish card; it is not repaired by rule | PR #115 recommends a loop back for medium (`scripts/flow.py:779-784` [reader]) |
| Model per stage, Design by risk, a second opinion on the plan at risk H (one round and one recheck) | CLI rules already, but the second opinion is an option on every plan question (`scripts/flow.py:678-679` [code]) |
| The spec commits and the record of the run on the run's own branch | the CLI makes them (`scripts/flow.py:557-571` [code]) |

### 2.4 The smallest set of approvals that keeps the promise

The promise has three parts: no code before the person approves the intent; verdicts computed by the CLI; tests first.

- **One approval is the minimum the promise needs:** the card before Build. No code can be written before it: with
  the mod, Plan and Design may write only spec files (`hooks/temper-mod/core/rules.ts:237-325` [reader]).
- **I recommend two by default:** that card, and the finish card. The second costs the person no waiting (the work is
  done and on the branch) and it is where they learn the result and choose the only thing that leaves the machine. It
  also keeps the written invariant that an unattended run never makes the final commit
  (`templates/temper.config.default:138-141` [code]).
- **The intent stays the person's click, literally.** Today leaving Intent runs four calls: branch, `intent accept`,
  the spec commit, `state advance intent_complete plan` (`scripts/flow.py:557-565` [code]). Split them: on a passed
  Intent check the CLI runs the branch and the advance by itself; `intent accept` and one spec commit (intent and plan
  together) move into the approval card's option. The ledger then still says the person accepted the intent, and
  the click that does it is the one before any code.
- The price of folding the intent click into the plan card: a wrong intent is found one Plan pass later (today 143 to
  246 s, $0.75 to $1.13 [xc §3]). It is paid only when the person rejects the intent after having answered its
  questions; nobody has measured how often [xc gap 10]. The criteria are shown as rows the moment Intent ends, so a
  person who is watching can stop the run there with Esc and type the correction (section 5). Owner decision D1.

---

## 3. The experience, step by step

Seconds are from the benchmark on small Python tasks [xc §3]; on the one real Java run each launch took 4 to 13 times
longer [xc §3]. "Today" is the shipped default with the recommended answer everywhere.

### 3.1 A clear request

They type `/temper:temper "lock an account after 5 failed logins in 15 minutes, for 15 minutes; 423 with the unlock time"`.

| t (target) | What they see | What they are asked | Today |
|---|---|---|---|
| 0 to 1 s | "Temper: run `login-lockout` on branch `feature/login-lockout`. Reading the request." | nothing | the same calls, under 1 s [xc §3 row 1] |
| 30 to 45 s | "Intent: 5 criteria, nothing left open." and the 5 criteria, one row each | nothing | the Intent agent's box with a **count** of criteria (`agents/intent.md:174-187` [code]), then dialog 1: "Accept the intent and continue to Plan?" (`scripts/flow.py:633-637` [code]) |
| to about 2 min (today's Plan: 3 to 5 min) | "Planning. Usually 2 to 4 minutes." A live row in the bar | nothing | Plan on Opus, 143 to 246 s [xc §3 row 8]; then dialog 2, the Context check, on every run [xc row 1] |
| about 2 min | **the approval card** (section 4.1) | **dialog 1: "Build this?"** One click, under a minute | dialog 3: a 12 line box with file **counts** (`scripts/panel.py:129-137` [code]); the recommended answer is "Stage by stage" (`scripts/flow.py:673` [code]) |
| +30 to 45 s | "Writing the 5 acceptance tests from your criteria; they are locked before any code." | nothing | the same launch [xc §3 row 15] |
| +2 to 4.5 min | one row per task: failing test first, then passing, files changed | nothing | the same, plus dialogs 4 and 5 (one per group, `scripts/flow.py:1763-1766` [code]); a group that depends on another waits for the click (`scripts/flow.py:1683-1686` [reader]); then dialog 6, "Continue to Review?" (`scripts/flow.py:749`) |
| +30 to 55 s | "Review: no finding at high or above. Check ran beside it." | nothing | dialog 7, "Continue to Check?" (`scripts/flow.py:784`) |
| about 8 to 10 min | **the finish card** (section 4.2), with the numbers | **dialog 2: "Keep this result?"** | dialog 8, "Check: the check passed. Commit?" with no number (`scripts/flow.py:821` [code]); the 88 line report prints after the click (`scripts/flow.py:2144-2146` [code]) |

Total attention: two reads of under a minute. Between them the person can leave.

### 3.2 A vague request

They type `/temper:temper "lock accounts after too many failed logins"`.

| t | What they see | What they are asked |
|---|---|---|
| 30 to 45 s | "Intent: your request leaves 3 rules open." | **dialog 1, one dialog, up to 4 questions**, each with up to 3 ready answers, the first marked as the suggestion, and "Decide later": How many attempts, in what window? How long is the lock? Per account or per IP? |
| after the answers | the criteria as rows, each answer marked "[your answer]", each guess marked "[assumed]" | nothing |
| +2 to 4 min | the approval card; the answers and assumptions are on it | **dialog 2: "Build this?"** |
| end | the finish card | **dialog 3: "Keep this result?"** |

Changes against today: at most 4 Blocking questions, so always one dialog (the brief allows six, which is two dialogs:
`agents/intent.md:134` [code]; a dialog holds four, [reader: platform §3]); a fifth open rule becomes a stated
assumption on the card. No separate Intent approval after the answers: the answers were the decision.

At risk H, Design's questions are true decisions too. They are asked before the card, in the same kind of dialog, and
the card comes once, after Design. Today the plan question comes first, Design second, and (new in PR #115) any Design
answer fails the Design check and recommends planning again (`scripts/flow.py:733-739` [reader], `scripts/decisions.py:53-69` [xc row 7]).

### 3.3 A run where a check fails

Example: after Build, the locked acceptance test for criterion 3 fails.

| Step | What they see | What they are asked |
|---|---|---|
| The failure | "Check: 1 of 5 acceptance tests fails (criterion 3). One repair now: a builder, about 2 minutes. You are asked only if it fails again." | nothing |
| The repair works | the failed rows run again and pass; the finish card says "Along the way: 1 repair" with what failed and what changed | the finish dialog only |
| The repair does not work | **the failure card** (section 4.3): what fails with the lines that say so, what was tried, what the triage thinks, what else is green | one dialog. The options: look (the run is saved), "The test is wrong: correct it", "Try another repair (about 2 min)", and under More: "Skip this check (your reason is recorded)", "Plan again (discards the build, about 4 min)" |

Rules that make this trustworthy:

- The recommended option is never the action that just failed. Today's own history: 131, 40, 52 and 72 repeats of a
  recommendation [xc §5 row 10].
- An environment fault is never repaired by a builder: "Your environment, not the code: `<line>`. Nothing was changed."
  The options are "Check again" and "Save for later", and a third, "This is the code's fault", because a wrong
  classification has no way out today [reader: pr-flow D8].
- A repair reruns what failed, not everything. Today one finding costs a fix agent, the Integration suite, a second
  Review of the whole diff and Check's whole run, and the step back empties Build's ledger so the gate wants a new
  failing test whatever the finding (`scripts/flow.py:588-593, 1655-1672`, `scripts/temper:1876-1896` [xc §5 row 3]).
- With the driver, a failed group check must not move the run into the conversation. Today `temper go` reads only
  `gate <stage>` as a verdict (`scripts/go.py:108-109` [code]), so `group gate` exiting 1 is an error and the driver
  hands the run back for good [xc row 10].

Today, for comparison: "Check: the check failed (...). Loop back to Build?" (`scripts/flow.py:874-875` [code]), a reason
dialog with one preset reason (`scripts/flow.py:586-593` [reader]), a fix pass, "Continue to Review?", a whole Review,
"Continue to Check?", Check again, "Commit?": 5 dialogs and 2 launches for one repair.

### 3.4 The very first use, on an existing Java or Node project (15 minute suite, 55% coverage)

**Today**, with correct code:

1. Install, type the command. Setup writes a 171 line config (123 lines of comments) and sets `core.hooksPath`; with
   husky or lefthook it refuses and prints a line to paste [reader: ux §1.2].
2. Intent, its dialog, then the Plan agent. Inside the Plan agent's own turn the preflight runs every Validate, Test
   and Integration command once on HEAD in a worktree under the temp folder, 300 s each
   (`scripts/preflight.py:31`, `agents/plan.md:59-61` [xc row 9]). The Integration line is normally the whole suite,
   15 minutes here: it times out, and over the limit "is an environment fault"
   (`templates/temper.config.default:109` [code]; `scripts/preflight.py:103-105` [code]; [reader: pr-env §1.3 row 3]).
   The person's first plan dialog is a failure: "Plan: the check failed ... add the proposed setup block ... and check
   again?" (`scripts/flow.py:697-699` [code]). No setup block cures a time limit; the keys that do
   (`plan.preflight-timeout`, `plan.preflight-skip`) are two comment lines (`templates/temper.config.default:109-110` [code]).
   On Node the temp worktree has no `node_modules`, so `npm test` fails there and passes silently as "needs new code"
   (`scripts/preflight.py:115` [code]; [reader: pr-env §0]).
3. Build. A group whose Validate is the suite hits the 600 s limit (`scripts/temper:2441` [code]) and asks "Run the
   gate again with twice the time (Recommended)". The suite runs again at integrate.
4. Check. The suite runs with coverage (15 minutes), then one mutant runs the whole suite again: the limit per mutant
   is 3 times the suite's time and the 300 s budget is tested only before each mutant
   (`scripts/check_run.py:374, 381` [code]); the result is "only 1 mutant(s) ran in the time budget" (`:395-397`).
5. The verdict. Node at 55%: "coverage >= threshold" fails against 80 (`scripts/temper:3864, 3912` [code]) and the
   dialog recommends "Loop back to Build" (`scripts/flow.py:874-875` [code]): a builder is sent to raise a whole
   project's coverage. Maven or Gradle: no coverage command at all (`scripts/check_run.py:140-144` [code]), the row
   reads "recorded coverage 'none'", the dialog recommends "Run Check again" (15 more minutes), then "Save for later"
   (`scripts/flow.py:857-863` [code]). The key that would help, `check.commands.coverage`, is not in the template [reader: ux §1.4].

At least four suite runs (an hour of tests), 10 or more dialogs, and a red result on correct code. The person concludes
that Temper does not work on their project.

**Target:**

| t | What they see | What they are asked |
|---|---|---|
| 0 to 5 s | "First run in this project. Found: Node, `npm test`, jest. Your git hooks are managed by husky: Temper's commit check is not installed; to add it, put this line in `.husky/pre-commit`: `<line>`. Measuring your test suite in the background now. Wrote `.claude/temper.config` (10 lines)." | nothing |
| 30 to 45 s and on | Intent, its one dialog if rules are open, then planning. On a large code base planning takes longer (12 minutes on the one Java run [xc §3]); the row says how long it has run | the Blocking dialog, if any |
| when the plan is ready | the approval card, with a first-run block: "Your suite: 14 min 52 s, 1,204 pass, 55% of lines covered. During Build only each task's own tests run. The full suite runs once at the end. Coverage may not drop below 55%. About 40 min from here, most of it your suite." If the suite is still running, the card says so and Build may start | "Build this?" |
| only if the suite is red on the current code | "3 tests fail on your code before any change: `<names>`." | one dialog, before the approval card: "Go on, and do not count these 3" or "Stop: I will fix them first" |
| Build | per task rows. Each task runs its own tests; a builder's worktree gets the dependency folder by link, as the mutation step already does for `node_modules` (`scripts/check_run.py:378-379` [code]) | nothing |
| the end | Review while the full suite runs once with coverage (15 minutes; Check already starts beside Review, `scripts/flow.py:1375-1378` [xc row 20]). The mutation check runs the changed tasks' tests, not the suite | nothing |
| about 40 to 50 min | the finish card: "Coverage 55.2% to 55.9% (not lower). Mutation: 10 of 12 caught." | "Keep this result?" |

Two or three dialogs. One full suite run in the foreground of the run, one in the background. The floor is the
suite itself: Temper cannot finish before the person's own tests do, and the card says so in advance.

What makes the defaults right without a config edit is one measurement, not ten keys: the baseline (suite time, pass
or fail on HEAD, coverage now). It replaces the PR's preflight as the environment check, earlier and outside any
agent's turn [xc §3 row 9 asks for exactly this].

---

## 4. What each approval shows

Rule for all three: the card is drawn by the CLI from files and the ledger (never by a model), fits one screen (30
rows of 76 columns at most), is shown before the question, and the question itself is one line. A dialog takes a
header of at most 12 characters and 2 to 4 options [reader: platform §3]; "Temper gate" stays the header, because the
mod matches header, text and label exactly (`hooks/temper-mod/core/answers.ts:33, 70-76` [reader: mod §2.3]).

### 4.1 The approval card (sample: login lockout, vague request, Node project)

```
APPROVE BEFORE ANY CODE IS WRITTEN                    login-lockout · risk M
You asked: "lock accounts after too many failed logins"

WHAT WILL BE TRUE (5 criteria; each gets a test written and locked first)
 1. 5 failed logins in 15 min lock the account for 15 min       [your answer]
 2. A locked account gets 423 and the unlock time, even with the right password
 3. A successful login resets the count
 4. The lock is per account, not per IP                         [your answer]
 5. Admins are locked like everyone else            [assumed: no rule given]
NOT IN SCOPE: unlock by email · CAPTCHA · limits per IP

WHAT WILL CHANGE (6 files; any other file asks you first)
 Group 1  the lockout rule    + src/auth/lockout.ts
                              + test/auth/lockout.test.ts
 Group 2  the login endpoint  ~ src/auth/login.ts   ~ src/auth/errors.ts
                              ~ test/auth/login.test.ts
                              + db/migrations/014_login_attempts.sql
 LEFT OUT ON PURPOSE: src/admin/login.ts (the admin login keeps its own flow)
 COULD NOT FIND: a written rate limit policy
 PROTECTED PATH IN THE PLAN: src/auth/ (you asked to be told)

HOW IT IS CHECKED
 5 acceptance tests from the criteria, locked before Build
 each task: a failing test first, then the code
 your suite: npm test (48 s, passes on the current code)
 coverage may not drop below 71% · planted-bug check on the changed lines

FROM HERE: about 7 min and $0.90 (3 builders, 1 review). You are asked
again only if a check still fails after one repair, and at the end.
Nothing is pushed.
```

Question: `Build this?`

| Option | Description shown |
|---|---|
| Approve and build (Recommended) | Accepts the intent and the plan, commits both on `feature/login-lockout`, and builds. Stops for you only if a check still fails after one repair. |
| Change something | Type what is wrong in one line. The plan is written again with it (about 3 min). |
| Step through | Approve, and ask me after every stage. |
| More options | Open as a page · Second opinion on the plan (about 40 s) · Save for later |

Where each row comes from: criteria and answers from `intent.md` (the CLI already parses criteria and Blocking lines,
`scripts/panel.py:130` [code], `scripts/intent_parse.py:26-43` [reader]); files by group from `tasks.md`
(`scripts/panel.py:108-112` [code], which today prints only two counts); left out and not found from the plan's
Context Map (`scripts/flow.py:2331-2338` [code]); protected paths from `autonomy.park-on-touch`
(`templates/temper.config.default:150` [code]); the suite line from the baseline; the estimate from this project's
earlier runs (step 1), or the shipped medians on a first run, always marked "about".

The one minute test for this card: a reader can say which files change, what is out of scope, which rows were their
own answers and which were guessed, what it costs, and when they will be asked again.

### 4.2 The finish card

```
DONE: login-lockout            branch feature/login-lockout · not pushed
 Criteria      5 of 5 met (5 acceptance tests pass, unchanged since locked)
 Tests first   9 new tests failed before the code and pass after
 Suite         212 pass, 0 fail (npm test, 51 s)
 Coverage      71.0% -> 72.4% (not lower)
 Planted bugs  11 of 12 caught (92%)
 Review        0 high · 1 medium, open:
               login.ts:88 the lock is checked after the password hash
 Files         6 changed, all in the plan
 Along the way 1 repair: group 2's check failed once (migration missing);
               a builder added it; the check passed
 This run      11 min 40 s · $1.12 · 3 dialogs
 Full record   .temper/specs/login-lockout/report.html
```

Question: `Keep this result?`

| Option | Description shown |
|---|---|
| Finish (Recommended) | Records the run on the branch. The code is already committed there. Nothing is pushed. |
| Finish and open a draft pull request | Pushes the branch and opens a draft. |
| Repair the medium finding | One builder, then Review reads the fix (about 2 min). |
| More options | Change something · Save for later |

Every number on it exists today and is not shown at the decision: the Check question is "Check: the check passed.
Commit?" (`scripts/flow.py:821` [code]) and the report prints after (`scripts/flow.py:2144-2146` [code]). The label
"Commit" also misstates the click: after a grouped Build this commit holds the record, not the code
(`scripts/flow.py:2195-2198` [code]).

### 4.3 The failure card

```
STOPPED: a check still fails after one repair              login-lockout
 What fails    acceptance test, criterion 3 "a successful login resets
               the count": expected 0 failed attempts, got 5
               test/acceptance/lockout.acc.test.ts:41
 Tried         1 repair: src/auth/login.ts (+6 -1). It fails the same way.
 Reading       the test and the code disagree about when the count resets;
               the test may be the wrong one
 Still green   211 tests · review: nothing at high · all files in the plan
 Spent so far  9 min · $1.05
```

Options: `Correct the test` (opens the locked test for change; recommended here because the triage says so) ·
`Try another repair` (about 2 min) · `Look first` (saves the run; `/temper:temper` takes it up) · More options:
`Skip this check` (asks for the reason) · `Plan again` (discards the build; about 4 min). The triage verdict and these
options exist (`scripts/flow.py:864-873, 1487-1511` [code, reader]); what is new is the card, the costs on the options,
and that nothing repeats by recommendation.

### 4.4 Two smaller texts

- **The Blocking dialog:** each question in the person's words, each ready answer with one line of consequence, the
  suggestion first, a house rule marked as one. Today the reason behind the suggestion is only in the file [reader: ux §6].
- **Without the mod,** once per conversation, in place of "Temper enforcement is off here (no mods support);
  continuing with prompt based phases." (`commands/temper.md:9-14` [code]): "Running without the Temper mod (it needs
  Claude Code 2.1.287 or later). Same checks, same two approvals. Claude relays each step, which is slower and costs
  about $0.30 to $1 more a run, and nothing but the instructions keeps it to the plan's files. The commit check still
  blocks a failed gate."

---

## 5. When the person disagrees or wants to look

| They want to | They do | What happens | Today |
|---|---|---|---|
| Look at the plan in full | open `.temper/specs/<slug>/plan.md`, `tasks.md`, `intent.md`; or More options, "Open as a page" | nothing moves | the same; the option sits in the first row of the plan question (`scripts/flow.py:675` [code]) |
| Change the plan | "Change something" on the card, one typed line | the driver records it and runs Plan again with the note; the option says what it costs | a typed line hands the run to the conversation for good (`hooks/temper-mod/core/driver.ts:288` [code]; [xc row 10]); the docs say "Claude makes it" and the page says the agent runs again [reader: ux §6] |
| Stop the intent early | Esc while Plan runs, then type the correction | the driver ends as stopped with no model turn (`hooks/temper-mod/core/driver.ts:336, 561-569` [reader]); `/temper:temper "<correction>"` restarts Intent with it | no row shows the criteria, so there is nothing to react to |
| Watch every stage | "Step through" on the card | today's default behaviour: a dialog after each stage | the default |
| See where a run is | `/temper:temper status` | one screen: stage, what passed, what it waits for | exists (`commands/temper.md:37` [reader]); a second command, `/temper:status`, draws a different dashboard |
| Stop and come back | Esc, or "Save for later" on any card; `/temper:temper` with no words resumes | as today | as today |
| Disagree with a finding or a check | on the finish or failure card: accept the finding, or skip the check, each with a reason that stays in the record | as today | both are lost at the commonest Review outcome on PR #115 [reader: pr-flow D1] |
| Disagree with a rule Temper applied (coverage, protected paths) | edit the 10 line config; it applies from the next run | the mod refuses a config change during a run (`hooks/temper-mod/core/rules.ts:521-524` [reader]), so no agent can do it for them | the keys are among 171 lines |
| Throw the result away | "Save for later", then delete the branch; nothing was pushed | | the same |

---

## 6. PR #115, from the person's side

A default user changes no config and takes the recommended answer. For that user the PR removes no dialog and adds
loop backs [reader: pr-flow §1, §3].

| Part of the PR | For a default user | Do |
|---|---|---|
| Failure text that leads with the cause; the four option cap; no fix agent with nothing to fix; "twice the time" recommended once only; no override offered where it cannot clear the row | helps: fewer wrong clicks, no dead dialogs | merge |
| Reuse of a check that passed on the same tree (`scripts/task_ops.py:464, 488` [xc row 8]) | helps: one suite run fewer | merge; extend to Check in step 5 |
| Only runs the CLI made count (`scripts/runs.py:30-33` [xc row 11]) | helps trust; but two briefs still tell the Check agent to claim its runs [reader: pr-flow feature 4] | merge with the briefs corrected |
| "SETUP: no verdict on the code" at Check; an environment verdict at a task (saves up to three wasted attempts) | helps; but neither has a way out when the classification is wrong, and the SETUP recommendation repeats without end [reader: pr-flow D8, D8b] | merge with a "this is the code" option and the repeat rule |
| The `setup:` block and the one runner; `temper doctor` as a read-only report | neutral until used; sound [reader: pr-env §0] | merge |
| **High blocks; an open medium finding recommends "Loop back to Build"** (`scripts/flow.py:779-784` [reader]) | **hurts:** each loop is 2 launches, 4 to 5 dialogs, $0.40 to $0.50 [xc §5 row 3]; and at that very question "More options" leads only to itself, so accept and save are unreachable (`scripts/flow.py:925-947` [reader: flow-questions finding 10]) | keep high blocking; take the medium recommendation out; repair the More options defect |
| **A Design answer fails the Design check until tasks.md changes, and "Loop back to Plan" is recommended** (`scripts/decisions.py:53-69` [xc row 7]) | **hurts:** about 300 s of Opus for an answer that often confirms the plan | do not fail on the first (suggested) choice; otherwise let Design change the tasks |
| **The preflight: inside the Plan agent's turn, 300 s a command, in a temp worktree with no dependencies** | **hurts first use** (section 3.4); outside Maven 24 of 33 sample failures pass it [xc row 9] | keep the code path off by default until step 5 replaces it with the baseline |
| **`autonomy.policy: decide`, shipped off, and reached only through the option that is not recommended** | the one part that removes dialogs is invisible; and as written it never launches the group fix agent (`scripts/flow.py:1754` [code]: the launch needs `not r.armed()`), so one failed group check ends in an unattended new plan [xc row 12]; it loops back to Build for a criterion only the person can confirm (`scripts/flow.py:1173-1180` [code]: no branch for it) | repair those three, then make it the default route in step 2 |
| Nine new config keys; a second top level `build:` key that cancels the first once uncommented; `.temper/preflight.json` in the person's `git status` [reader: ux §2.4, §1.2] | hurts | repair the two defects now; the keys go in step 7 |
| The run may plan again unattended, while the config says "NEVER re-plans unattended" (`templates/temper.config.default:141` [code]) | a broken promise in writing | planning again always asks (2.1 row 7) |

In short: land the work-saving parts and the defect repairs as 9.8.5; hold the three defaults that add loops; the
policy becomes the default route only after its defects are closed.

---

## 7. The steps, in order

Effort is one person's working days, with CI at 30 minutes a run [xc §5, last paragraph].

| # | Step | What changes | Effect for the person | Effort | How the owner knows it worked |
|---|---|---|---|---|---|
| 0 | **Settle PR #115** | The table in section 6. No new feature | No more loop backs than 9.8.4; the Review question whole again | 2 | e2e green; a selftest case: Review passed with one medium finding offers Accept and Save; the default-run trace still shows 5 + G gate questions (nothing regressed before step 2) |
| 1 | **A record that survives the run, and the budget file** | `state clear` deletes `usage.json` and `feedback-loops.json` (`scripts/temper:1448` [code]). Append one line per run to `.temper/runs.jsonl` first: dialogs, launches, repairs, loop backs, seconds in agents, seconds waiting for the person, dollars, by stage. Local only (no telemetry, [reader: adr P6]). `/temper:temper status` prints the last ten. Add `scripts/surface-budget.sh` with today's counts (section 9) | None yet. It is the meter for every later step, and the source of the card's "about 7 min" | 2 | After any run the owner reads one line with the run's dialogs, minutes and dollars |
| 2 | **Ask only where there is a decision** | `scripts/flow.py`: a passed Intent, Design (no open concern), group, Build, Review (nothing at high) and Check return `auto` (the armed policy path, `:2441-2472`, becomes the route of the first option). The plan question's first option becomes "Approve and build (Recommended)"; "Step through" is second (`:673-675`). The intent click moves into that option (2.4). The Context check dialog goes: its lines go on the card and the card's option carries the answer call (`:2331-2344`). Design's questions before the card. `autonomy.policy` leaves the template. One new ADR restates who decides what and replaces "never re-plans unattended" with "a new plan always asks" | 8 dialogs become 2; 3 on a vague request. No waiting between groups | 5 | e2e `full-run`: 2 questions, 6 launches, `driver done`. `design`: 2. Bench: mean dialogs 4 or fewer (13.1 today [xc row 14]). The fixture file shrinks (it is 3,084 bytes under the 256 KiB limit [reader: mod §2.4]) |
| 3 | **The three cards** | `temper card approve|finish|failure` in `scripts/panel.py` (the CLI draws; `:129-137` is the starting point). The driver shows a card whole (it compacts panels to a few rows today, `hooks/temper-mod/core/driver.ts:88-137` [reader]). The Intent agent stops drawing its own box (`agents/intent.md:162-187`); the CLI lists the criteria. Labels: "Finish", "Repair", "Skip this check", "Decide later". Blocking questions capped at 4 | One click is an informed decision. The numbers come before the commit click | 4 | The one minute test: the owner and two others read three sample cards, 60 s each, then answer five questions (which files, what is out, which rows were guessed, cost, when asked next): 13 of 15 right. View fixtures hold each card |
| 4 | **One repair, then one card** | A failed group check is a verdict, not an error (`scripts/go.py:108-109`); the group fix agent is launched in an unattended run too (`scripts/flow.py:1754`). A finding at high or above, and a Check failure in the code, get one fix agent and a rerun of the failed rows only. The same failure twice is never recommended again (generalise `same_failure`, `scripts/flow.py:856`). A run budget of 3 repairs that code reads (`autonomy.budget.*` is read by nothing, [xc row 11]). "Change something" and a typed line are carried by the driver; a hand back returns to the driver | A failure costs 0 or 1 dialog, not 4 to 5; the run never leaves the driver for a failure the CLI can describe | 6 | e2e `pyjokes` (the replay of the failed run) ends `driver done` with 3 questions or fewer. Bench with a seeded defect: one repair, half of today's $0.40 to $0.50. A selftest states: no option is recommended twice for one failure text |
| 5 | **The first run measures the project** | A baseline at second 0, in the background: the suite once on HEAD, its time, result and coverage, stored by tree and command (the reuse store exists, `scripts/run_env.py:121-180` [reader]). From it: time limits (3 times measured); the coverage rule (not lower than before; "not measured" when no tool, as the mutation row already passes with a note, `scripts/temper:3929-3930` [code]); the slow suite rule (over 5 minutes: task tests during Build, the suite once at the end, mutants run the task tests); a red baseline asks once, before the plan is paid for. The config is written from it, about 10 lines. `.claude/temper.config` goes into the run's first spec commit (it is dropped today, `scripts/flow.py:2947` [code]). Builders' worktrees get the dependency folder. Count Claude Code's own permission prompts in a first run and add `allowed-tools` for the CLI to the two commands (no command declares it, [reader: ux §1.1]) | A first run on an ordinary project ends green when the code is right, with 2 or 3 dialogs and one foreground suite run | 6 | Two new e2e projects, Maven and Node with jest, each with a suite slowed by a sleep and coverage near 55%: the first run ends green, 3 dialogs or fewer, the suite command runs at most twice in the foreground. The owner runs it once on a real repository and reads the finish card |
| 6 | **The first decision in 2 minutes, the run near $1** | Set `effort` on Plan and Design (neither has one, [xc gap 1]). Plan stops writing what nobody reads (19% of its output is Given/When/Then that no script and no builder reads, [xc §5 row 1]). One paid A/B: Plan on Sonnet against Opus for plans below risk H (about $50 and 4 hours, [xc gap 9]). At risk H the design concerns are part of the plan pass | The wait before the card halves; a clean run costs about 2 times plain Claude Code | 3, plus $50 | Bench: Plan 90 s or less and $0.50 or less with the same hidden-test and mutation results; if the A/B shows a loss, keep Opus and say so on the card |
| 7 | **Shrink what a person sees** | `.claude-plugin/plugin.json:25-37, 53-59`: commands 11 to 2 (`/temper:temper`, `/temper:fix`); the doors, `init`, `status`, `pack` and `intent` leave the listing (`status`, `report`, `help` stay as words; a word counts only when it is the whole argument, so "status badge on the order page" starts a feature, [reader: ux §2.1]). Skills 5 to 0 listed; Grill Me and Teach Me become pages read on demand under More options. Default packs 5 to 2 (security, tdd). Delete keys nothing reads (`autonomy.budget.*`, `autonomy.enabled` text, `tools.label-findings`, [reader: ux §2.4]). One model setting, not five places. README line 30 becomes "You approve once before any code is written and once at the end. In between Temper stops only when a check fails." Getting Started rewritten around the four experiences; the emoji examples no code prints go [reader: ux §7] | A new user learns 2 commands, 2 cards and about 12 words. Every session carries about 250 tokens of Temper, not 1,150 [reader: ux §3.1] | 4 | The budget script's counts; `scripts/validate-directory.sh` green; a new user (not the owner) completes a first run from the README alone |
| 8 | **Without the mod: the same run, said honestly** | The cards are printed from the CLI's text; passed checks are `auto` inside `temper go` (`scripts/go.py:95-117` [code]), so the session takes a turn only at a launch and at a dialog. The new first line (4.4). One line on the background agent stall with the setting that cures it [reader: ux §1.2] | Same 2 or 3 dialogs; fewer relay turns | 2 | e2e plain and driver traces equal (the suite already fails when they differ, `scripts/e2e/run.ts:27-31` [reader]); bench without the mod: $0.30 or less above the driver run |

Order and dependence: 0 before everything (the tree to build on). 1 before 2 (the meter). 2 before 3 (the cards
replace questions that must first be gone). 4 needs 2. 5 needs 3 (the card carries the first-run block). 6 is
independent after 1 and can run beside 4 and 5. 7 after 2 to 5, so nothing removed is still referenced. 8 last,
because every earlier step changes what the session must relay. About 34 working days and $50 to $100 of benchmark.

Two limits that every step meets: `scripts/temper` is 1,640 bytes under the 256 KiB file limit, so new logic goes
into Python modules [reader: adr §1.5]; a change of question text regenerates the view fixtures
(`scripts/selftest/make-view-fixtures.sh`).

---

## 8. A user without the mod

- **Same decisions, same cards, same two or three dialogs.** The flow is the CLI's; the e2e already asserts both paths
  ask the same [reader: flow-questions §2c].
- **What differs, and is said once in plain words** (4.4): a Sonnet session relays each step, so the run is slower
  (183 to 206 s outside the agents against 42 to 103 s) and dearer ($0.28 to $0.97 a run) [xc §3, row 18]; and the
  first promise is an instruction, not a refusal: nothing stops a write before the approval except the brief
  [reader: adr P1]. The commit check and the CLI's verdicts stay.
- **Step 2 helps this user most in turns:** a default run stops `temper go` 13 to 16 times today [reader:
  flow-questions §2b]; with passed checks as `auto` it stops at about 6 launches and 2 dialogs.
- **The stall:** without the driver a run can wait for a turn after a background agent ends; the cure is a setting the
  person sets by hand [reader: ux §1.2]. The first-run lines name it. Temper keeps not editing settings.
- The README stops saying the mod-off run "works the same" without the price; it says "same checks, slower, dearer".

---

## 9. What keeps the surface from growing back

1. **A budget file checked in CI** (`scripts/surface-budget.sh`, called by `scripts/quality-check.sh`). It counts and
   compares with numbers stored in the repository:

   | Count | Today | After step 7 |
   |---|---|---|
   | Dialogs in the clean e2e run (`full-run`) | 7 scripted, 8 real [xc row 2] | 2 |
   | Dialogs in the e2e run with one failed check | not scripted | 3 |
   | Listed commands / skills | 11 / 5 | 2 / 0 |
   | Live lines of the shipped config | 171 lines, 53 keys | 12 or fewer |
   | Distinct option labels in `scripts/flow.py` | 66 to 71 [xc row 9] | whatever step 7 leaves; from then it may only fall |
   | Options in the first row of the two cards | 4 | 4 |
   | Bytes the plugin adds to every session | about 4,570 [reader: ux §3.1] | 1,000 or fewer |

   A pull request that raises a count fails unless it changes the stored number in the same diff, with one line of
   reason in `docs/decisions/surface.md`. A new question, option, key or command therefore costs a visible line.
2. **Every config key has a reader:** a selftest walks the template and the config page and fails on a key no script
   reads. Two shipped keys have none today [xc row 11].
3. **Docs quote the product, not memory:** the questions and cards in README and Getting Started are generated from
   the view fixtures by a script; a doc that shows a question the CLI no longer asks fails the check (12 such
   disagreements today, [reader: ux §7]).
4. **One rule for a new question,** written in the new ADR: it must name the decision only the person can make
   (a row of 2.1). A passed check is never one.
5. **The meter in the changelog:** each release notes the median dialogs, minutes and dollars of the benchmark runs,
   from the run records of step 1.

---

## 10. Decisions the owner must make

| # | Decision | My answer | Why |
|---|---|---|---|
| D1 | One approval before code (intent and plan on one card), or a separate click for the intent? | One | The answers to the open rules are the intent decision; the click stays the person's and stays before any code (2.4). Cost: a wrong intent is found one Plan pass later |
| D2 | Keep the finish dialog on a fully green run? | Keep | It costs no waiting; it shows the result; it is where a pull request is chosen; it keeps the written invariant. The promise itself would allow dropping it |
| D3 | "Approve and build" as the recommended option, "Step through" second? | Yes | Today the recommended answer is the one that asks the most (`scripts/flow.py:673`) |
| D4 | May a run plan again without asking? | No, it always asks | It discards built work and changes what was approved; the config promises it (`templates/temper.config.default:141`); PR #115's policy does it |
| D5 | An open medium finding: repair by rule, or show at the finish card? | Show | No run shows a gain from the loop; each costs $0.40 to $0.50 and, today, 4 to 5 dialogs |
| D6 | Coverage: an absolute 80% of the project, or "not lower than before"? | Not lower, with the changed lines judged by the planted-bug check | 80% fails every ordinary existing project on its first run with correct code |
| D7 | Builders: seconds or cents? | Seconds (Sonnet): about 100 s a run for $0.25 [reader: adr R8] | The person is waiting; this is the cheapest minute and a half in the run |
| D8 | Spend about $50 on the Plan A/B (Sonnet against Opus, with effort set)? | Yes | Plan is most of the dollars and most of the wait before the first decision; nothing else moves them |
| D9 | Remove the doors, `init`, `status`, `pack`, `intent` from the listing? | Yes | 9 of 11 listed commands are not typed by a default user; the project's own rule calls the doors "doors into `/temper`" |
| D10 | Merge PR #115 only as section 6 says? | Yes | Its defaults add loops for the user who changes nothing |

## 11. What I did not verify

- That `intent accept` can move from leaving Intent to the plan approval without a second change in the Plan gate's
  rows; I read the call lists (`scripts/flow.py:557-571`), not every reader of the intent's status.
- How the card reaches the dialog in every surface: the mod adds descriptions and a preview through its own hook
  (`hooks/temper-mod/register.tsx:789-796` [reader]); a plain terminal preview is not documented [reader: platform §3].
  The plan relies only on rows shown before the question.
- The number of Claude Code permission prompts in a first run: nobody has counted [xc gap 12]. Step 5 counts them.
- Dollars and seconds of a fix agent alone, and every figure on a real project [xc gaps 6 to 8]. The targets in
  section 1 rest on small Python tasks.
- Whether a baseline in the project folder disturbs builders working in worktrees on the same machine (CPU, ports,
  a shared database). The first real run in step 5 answers it.
