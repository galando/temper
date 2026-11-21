# Red team review of plan-draft-v1: the owner's words, what is missing, can it be acted on

Reviewer lens: completeness. Read in full: the draft, `_crosscheck.md`, `ux-onboarding.md`, `changelog-older.md`,
`evidence-bench.md`, `mod.md`, `platform.md`. Read in part: the ten verifier reports (verdicts, corrections, effort,
"not determined"; `v-targets-scorecard.md` and `v-pr115.md` appeared while I reviewed), the three independent plans in `alt/` (after my first pass). Checked in `/home/user/temper` at
`10e965a`, read only: `README.md`, `commands/fix.md`, `scripts/flow.py` (fix questions, armed run, policy),
`scripts/check_run.py:76-146`, `templates/temper.config.default` at the head and on `origin/main`, this repository's
own `.claude/temper.config`, `scripts/temper:4540-4556`, `scripts/validate-directory.sh`, `CHANGELOG.md` (sizes of
entries), file sizes, `git log` (authors, the PR's commits). Nothing was run except `grep`, `sed -n`, `wc`, `git log`,
`git diff --shortstat`, `git show`.

Severity: **Blocker** = the owner cannot say yes to the plan as written, or a part of the request is not delivered
and the draft does not say so. **Major** = the plan delivers less than it says, or later than it could, or leaves a
group of users out. **Minor** = wording and consistency.

---

## 0. Verdict

The diagnosis is sound and the two approval mechanism is proven. The draft is not yet a plan the owner can approve.
It has no total cost, no end, and a cap anyone can raise. Its time targets are already overruled by its own verifier.
"Easy to use" starts after day 51 and first use is not in it. Existing projects keep the old defaults, because their
config files hold them. The bug flow, the run without the mod, other stacks and slow suites have no pass line. Five
blockers, fifteen majors, all fixable in the text.

---

## 1. The request, word by word

| The owner's words | Draft items that deliver it | How much | Not delivered, or not said |
|---|---|---|---|
| "look at the open pr" | Stage 0 | A list of 13 bullets (about 19 defects) to fix on the PR branch | No verdict on the PR in one sentence (the verifier has one: 16 must be fixed, 7 on a default user's path). No split between what the PR breaks for a default run, what is broken only behind a key that is off, and what was already broken on main. All three independent plans say **cut or switch off** the parts that add loops, the draft says **fix**; the owner is not shown the choice. The PR adds things the plan removes one or two stages later (`evidence.claimed-runs` in 1g, `autonomy.policy` in 2a, the preflight's pattern classes in 4b) |
| "as efficient as possible" | Section 2 targets; stages 2 to 4 | Dialogs 8 to 2 (certain, prototyped). Dollars 4.5 to about 2 times plain (a hypothesis) | "Possible" is never defined. The floor the design allows is visible in the product itself: the bug flow runs at 1.25 to 1.35 times the cost of plain Claude Code. The draft does not say why a clear feature should stop at 2 and not go on to 1.3, or what it would take |
| "easy to use" | 2e (the approval shows what is approved), stage 5 | Stage 5 is the last stage: it starts after 51 to 72 working days by the draft's own table | First use is not in the plan: prerequisites, Claude Code's own permission prompts (nobody has counted them), a first run that fails with correct code on an ordinary project (fixed in 4d, between day 31 and 72), the 172 line config written into the project, the stall after a background agent without the mod. No item on the 115 words a user meets. No pause |
| "no back and forth between phases" | Stage 2 (the questions between phases), stage 4 (the loops between phases) | Questions: all of it, early. Loops: stage 4, the largest and least certain stage, last but one | The phrase has two meanings and the draft measures one. The scorecard counts dialogs; it has no number for "a run went back to an earlier phase". The bug flow keeps 4 questions in a 90 second run and no stage touches it |
| "fast" | 3b, 3c, 3g, 4a, 4c to 4e, decision 5 | Unknown. The draft says "Seconds are unmeasured" for its largest lever | The time lines of section 2 are not reachable by the plan's own arithmetic (`verify/v-targets-scorecard.md`: clear feature 3 times "only in the best case", honest line 4.5; bug 2 times "not reachable", honest line 2.5). Section 0 says 4 times for the same thing section 2 calls 3. All of it is measured on small Python tasks; the two runs that went wrong were Maven, where a launch took 4 to 13 times longer. The time the person waits before the approval is not a target |
| "cost effective" | 3a to 3f, decision 3 | The contract cut is worth $0.07 to $0.14 a Plan pass (verifier). The rest, about $0.4 to $0.5 a run, rests on Plan on a cheaper model, which has never been run | "Effective" needs the value beside the cost. No pass line has a value floor (rules met on a vague request, tests left behind). A plan that hits every cost line by cutting the things that produce the value would pass. The two advantages Temper claims have not been measured on today's model |
| "Once and for all" | Section 5 (four bullets), 1e | A cap that the same commit may raise; a release rule that depends on a benchmark run by hand on the owner's machine; a rule in a file the building agents do not load | Stage 6 is "open". Nothing says when the plan is finished. Nothing says the owner can stop after a stage. Nothing stops new work from landing beside the plan while it runs |

---

## 2. Blockers

### B1. Page one promises time and cost the plan's own verifier calls unreachable or unproven

- **Draft items:** section 0 ("Where it goes", the stage 3 pass line "2.5 times vanilla's cost and 4 times its
  time"), section 2 (bug 1.5 and 2; clear feature 2 and 3; vague 3 and 5), item 3e.
- **Problem.** Section 0 and section 2 give two different lines for the clear feature (4 times and 3 times its
  time). The verifier report the draft defers to ("where this draft and they differ, they win") says: bug time at
  most 2 "not reachable as stated" (expected 2.2, honest 2.5); clear feature time at most 3 "not reachable as an
  expected value" (expected 4.1 with a Sonnet builder, 5.2 with Haiku; honest 4.5); "every target number rests on
  agent costs that were never measured alone and on a front agent that does not exist". The cost line depends on one
  test, Plan on Sonnet, that the draft schedules as 3e: after stages 0, 1, 2 and most of 3, so after about 30 working
  days. That test needs no code (`models.plan: sonnet` in the bench's config line; evidence-bench section 3).
- **Change to the plan text.**
  1. Replace the pass line table of section 2 with: Bug: cost at most 1.5, time at most 2.5, 2 dialogs, no clean run
     handed back. Clear feature: cost at most 2 and time at most 4.5 with Sonnet builders (or 1.5 and 5.5 with Haiku
     builders). Vague feature: cost at most 3, time at most 4.5, dialogs 2 plus one for each four open rules. Use the
     same numbers in the stage table of section 0.
  2. Add to section 0, under "Where it goes": "Certain: the two questions (prototyped; counted by script with no
     model). A target, not yet a fact: the dollars and the minutes. They rest on one test that has never been run,
     the planner on a cheaper model."
  3. Move the model test to stage 1, right after the "before" round, on today's contract (about $40 and 4 hours),
     and run the two anchor tasks again after 3b (about $12). Keep 3e as the confirmation.
  4. Give stage 3 a go or no go line: "If the cheaper model does not hold, stage 3 is 3a to 3d and 3g only, 3f is
     dropped, and the clear feature's cost line becomes 2.5."

### B2. The plan has no total, no end and no way to stop

- **Draft items:** section 0 table (stage 6: effort "open"), section 5, the whole of section 3 (no decision on the
  budget).
- **Problem.** The table sums to 56 to 80 working days for stages 0 to 5 and the draft never prints the sum. Stage 6
  is unpriced and unbounded (its item 6a alone is 8 to 12 days in `v-failure-budget.md`; a port like 6c was sized at
  4 to 6 weeks by an independent planner). Benchmark money is not totalled: the verifier's program is $143 to $236,
  plus about $30 for each later round. Who does the work is not said: 83 of this repository's 136 commits are by
  Claude sessions and 47 by the owner, so "days" are not the owner's days, and the owner's own time (decisions,
  reading each release's numbers, running the benchmark, which lives on the owner's machine) is not stated. There is
  no sentence that says when the plan is finished. The history is seven "lean" efforts and 33 releases in 84 days;
  a plan with an open last stage is the eighth.
- **Change to the plan text.**
  1. Add to section 0 a row "What it costs": "56 to 80 working days of build work in stages 0 to 5, done by agent
     sessions the owner directs; about $300 to $400 of benchmark runs; of the owner: the decisions of section 3 now,
     one reading of the numbers per release, about 15 to 22 hours of benchmark runs on the owner's machine."
  2. Add to section 0 "When it is done": "The plan ends with stage 5. It is done when two releases in a row hold the
     pass lines and no cap was raised. Stage 6 is not part of this plan: each of its items is a separate proposal
     with its own measured reason and its own yes."
  3. Add to section 4, before stage 0: "The owner can stop after any stage; each stage ends in a release that works
     by itself. A stage that reaches 1.5 times its upper estimate stops and reports. An item whose measured gain is
     smaller than the spread between two runs of the same task (about 20%) is dropped, not tuned."
  4. Add to section 0 a table "If you stop after stage N, you have": 0: the PR on main with no new loop; 1: CI in
     about 10 minutes, the numbers of today, the caps; 2: two questions on a clean run, one budget for repeats;
     3: a planner that writes half as much, no Design stage; 4: a failure repaired where it happened; 5: two commands
     and a ten line config.
  5. Ask for approval in two parts: stages 0 to 2 now (21 to 30 days, the part that is certain); stages 3, 4 and 5
     each on the numbers of the release before.

### B3. Existing projects keep the old defaults: their config file holds them as live lines

- **Draft items:** 5b ("defaults in code (an existing config is never overwritten)"), 3c, 4d, 5c, 2h, decision 3,
  and stage 0's "High blocks".
- **Evidence.** `temper config init` copies the template byte for byte (ux-onboarding 1.2). The template's live lines
  include `packs: [quality, tdd, security, git, performance]`, `review.block-on`, `check.coverage-threshold: 80`,
  `plan.context-check: auto`, `plan.fresh-review: ask`, `phases.design: true`, `loops.max-per-type: 2` and the two
  `autonomy.budget` keys (`templates/temper.config.default:16-153`). On `origin/main` the line is
  `block-on: [critical]`. This repository's own `.claude/temper.config` says `block-on: [critical]`,
  `coverage-threshold: 80`, `design: true`, five packs. So in every project that has run Temper once, the owner's
  included: PR #115's "High blocks by default" never applies, Design stays on after 3c, total coverage of 80% still
  fails Check after 4d, five packs stay after 5c, and `loops.max-per-type` is a line 2h no longer reads. The draft's
  one sentence on the subject makes the new defaults unreachable for them.
- **Change to the plan text.**
  1. New item **1h, the config rule**, in stage 1, and move the template cut of 5b into it: "`config init` writes
     only the ten lines; every default lives in code. From this release on no new project gets a frozen copy of the
     defaults."
  2. Same item: "An existing config: at the next run Temper asks once, 'Your config holds N lines that only repeat
     old defaults. Remove them so new defaults apply?' Yes rewrites the file to the lines the person changed and
     keeps a copy. A key that no longer exists is read by nothing, is never an error, and is named once."
  3. Add to 2h, 3c, 4d and 5c the words "reaches existing projects through 1h".
  4. Add a selftest to 1h: a project with the 9.8.4 config and one with the 9.8.5 config get the new defaults after
     a yes, and the old behaviour after a no.
  5. Add to section 3 the decision "Existing projects: offer the new defaults once (recommended), or leave every
     existing config as it is".

### B4. First use is not in the plan before day 31, and part of it is not in the plan at all

- **Draft items:** stage 5 as a whole (last), 4d (coverage), 2e; nothing on permission prompts, prerequisites, the
  stall, slow suites.
- **Evidence.** A first run on an ordinary existing project fails Check with correct code: total line coverage
  under 80% recommends a loop back to Build, and Maven, Gradle and Rust have no coverage command at all
  (`scripts/check_run.py:138-145`; ux-onboarding 1.4). The draft repairs this in 4d, inside the 20 to 28 day stage
  that starts after 31 to 44 days. No command declares `allowed-tools` and neither README nor Getting Started
  mentions Claude Code's permission prompts (grep: none); how many a first run raises is unknown (crosscheck gap 12).
  To the person a permission prompt is a dialog like any other, so "8 dialogs to 2" may be untrue on a first run.
  Fixed time limits (300 s, 600 s) meet a 15 minute suite on the first run (`alt-person.md` 3.4 walks it: at least
  four suite runs, ten or more dialogs, a red result on correct code). `python3`, `git` and `bash` are not named as
  needs. Without the mod a run can wait for a turn after a background agent ends, and the cure is a setting the
  person sets by hand.
- **Change to the plan text.**
  1. Move into stage 2 (they are gate rows and a brief, not structure): "a missing coverage tool is 'not measured',
     shown at the commit question, never a failed row"; "the mutation runs set `PYTHONDONTWRITEBYTECODE=1`" (one
     line; a reader got 50%, 75% and 80% on one tree without it and one score twelve times with it).
  2. Add to 1c: "count Claude Code's own permission prompts in a first run, with and without the mod, default
     permission mode". Add to stage 2: "bring that count to zero for the CLI's own calls (an `allowed-tools` line
     for the plugin's CLI in the two commands, if the host honours it; else say the number in the README)".
  3. New item **2j, the first run**: "The first lines of a first run say what was found (stack, test command,
     coverage tool, hook manager) and what was written. A needed tool that is missing is said before the first agent
     is paid for."
  4. Add to 4b: "The baseline's measured suite time sets the time limits (three times the measured time). A suite
     over 5 minutes runs once per group and once at the end; mutation then runs the changed tasks' tests, or is
     information only."
  5. Add a pass line to stages 2 and 4: "a first run with correct code ends green with no config edit on one
     scripted project per detected stack: Python, Node, Go, Maven, Gradle, Rust".
  6. Keep in stage 5 only what removes surface: commands, skills, packs, dead machinery.

### B5. Section 5 does not stop the growth it describes

- **Draft items:** section 5, all four bullets; 1e.
- **Problem.** In 31 days question sites went from 23 to 41. Those additions were made the way this plan will be
  built: an agent session meets a fault and adds a row, a key, a question. Against that:
  - "must remove one or raise the cap in the same commit": the session that adds the question raises the cap. It is
    a visible line, not a stop.
  - "A release ships only when the scorecard holds its pass line": the scorecard is a paid benchmark run by hand,
    with results outside the repository (evidence-bench 0.3). The project's last such net, the eval suite, "never
    gated a merge" and was deleted (ADR 0010). A rule that depends on a manual step lapses.
  - "A removal first rule in CONTRIBUTING.md": the building sessions load `.claude/CLAUDE.md`, not CONTRIBUTING.md.
  - The caps count sites. Cause A of the diagnosis is not a count, it is a pattern: a question after a passed check.
    A count lets one question go and the same pattern come back in its place.
  - The scripted floor already missed a real question once: its fixtures write `reviewed: auto`, which no real Plan
    agent is told to write, so every scripted count was one short (crosscheck row 2).
- **Change to the plan text.** Replace section 5 with:
  1. "**A rule the code checks, not a count:** every question names, in a field, the decision only the person can
     make there. A selftest fails on a question that is asked when its stage passed and nothing is open, other than
     the approval and the commit."
  2. "**Caps the builder cannot raise.** The cap file may only fall in an ordinary change. A raise is its own pull
     request that holds the cap file and a note of at most ten lines with the measured number; the owner merges it.
     `.claude/CLAUDE.md`, Known mistakes: never raise a cap; ask the owner."
  3. "**A release gate with no hand in it.** Each release commits its scorecard as a file (commit, version, the pass
     line numbers). `quality-check.sh` fails when the version in `plugin.json` has no scorecard file or a number in
     it is over its line. No model runs in CI and no secret is needed."
  4. "**The fault rule, where the builders read it** (`.claude/CLAUDE.md`): a fault met in a run is fixed by moving
     a check earlier or by deleting the path that allowed it. A new question, key, agent or row needs a line in
     `docs/evidence/` that shows its gain. Nothing new is on by default without one."
  5. "**Every thing written has a reader:** a selftest fails on a config key no code reads, and on a section a brief
     asks an agent to write that no script, later agent or panel reads."
  6. "**The floor's fixtures are made from the templates the agents are given,** so a scripted count is a real count."
  7. "**The numbers are in the changelog and the README:** each release prints dialogs, minutes and dollars beside
     the release before."
  8. "**A freeze:** while the plan runs, nothing lands that is not in it. For 60 days after stage 5 only defect
     fixes land and caps may only fall."

---

## 3. Major findings

### M1. Stage 0 mixes three kinds of defect, and the owner is not shown the choice between fixing and switching off

- **Draft item:** stage 0, the list of merge blockers; "3 to 5 days".
- **Evidence.** `verify/v-pr115.md` (written while I reviewed) counts 16 defects that must be fixed, 4 defaults to
  flip and 29 to follow up. Of the 16, **seven are on a default user's path** and two more are holes in the mod's
  guard; four need `autonomy.policy: decide`, which is off by default and commented out in the template; some are
  older than the PR ("present on main too"; two of the three mod defects date from 9.7.5 and 9.8.1). So the first
  three bullets of the draft's list (all about the policy) cannot be met by a default run. The verifier recommends
  fixing all 16 on the branch, because the commits do not split by feature, and names a cheaper cut: "switch off,
  not split". `alt-smallest`, `alt-person` and `alt-clean-slate` each go further that way: remove or switch off what
  adds a loop, a question, an agent or a writer of the person's config ("cutting removes most of the defects without
  repairing them"), leave the policy code off, and repair it in the stage that makes it the default. The draft shows
  the owner one route. It also puts "CI in 10 minutes" (1a) after stage 0, on a branch whose 14 CI runs took 546
  minutes with 4 green.
- **Change.** (1) Open stage 0 with one sentence of verdict: "PR #115 is right in what it saves (one runner, reuse
  of a passed check, honest failure text, only runs the CLI saw count) and wrong in four defaults that add loops or
  waiting; a default user gets the same 8 questions as before and seven new ways to get stuck. Merge it after the
  list below." (2) Sort the list into three: **A, a default run meets it (7, plus 2 in the guard): before merge**;
  **B, only behind `autonomy.policy: decide` (4): the key stays off; repaired in 2a, where it becomes the default**;
  **C, older than the PR: 9.8.6, or the stage that touches it**. (3) Give list A a column "fix or switch off" and
  show both totals in days; recommend "switch off" for the environment agent's write path, the backup push
  allowance and the per command preflight as a failing row (4b replaces it). (4) Add: "This plan later removes
  these additions of the PR: `evidence.claimed-runs` (1g), `autonomy.policy` (2a), the preflight's pattern classes
  (4b). Do not document them for users." (5) Move the two workflow only parts of 1a (cancel superseded runs, shard
  the selftest) ahead of stage 0, on main. (6) Add "then nothing else lands on this PR". (7) Make "fix all, or
  switch off and fix the rest" a decision of section 3.

### M2. `/temper:fix` is in no stage

- **Draft items:** section 2 (the bug row has ratios and no dialogs), 2a, 4b, 4f, 5a.
- **Evidence.** A fix run asks four questions (RCA, Fix, Review, Check: `scripts/flow.py:616-619, 743-752`;
  evidence-bench 1.3) in a run of about 90 seconds. It has no arming question, so 2a as written ("the plan question,
  or the Design question") does not reach it. The verifier: "No package of the draft touches the three agents of a
  bug run", and Check starts beside Review only in a `/temper:temper` run. One of four measured bug runs was handed
  back and cost 3.4 times plain. The README calls `/temper:fix` "the cheapest way to try Temper".
- **Change.** Add **2i**: "A fix run asks twice: the root cause with the fix it proposes (the approval), and the
  commit. A passed Fix, Review and Check advance as in 2a. Check starts beside Review in a fix run too." Add to the
  bug row of section 2: "Dialogs 2 (today 4); no clean run handed back". Add one line to each of 4b, 4f and 2h saying
  what it does in a fix run (the baseline starts beside the root cause agent; a finding in a fix run is repaired in
  place; the one budget replaces `fix.max-loops`).

### M3. No pass line protects what Temper is for

- **Draft items:** 1c (the scorecard's fields), every pass line, section 7.
- **Evidence.** The scorecard lists dialogs, loops, launches, seconds, dollars, hand backs. It has no outcome. The
  three things with a measured effect are the open rules asked first (73% to 98%), tests the builder did not choose
  (mutation 93% against 79%, last measured three rounds ago on old code) and the commit block. "Ask me before you
  build" as one sentence met 85% at 0.84 times plain cost and was never rerun on today's model (evidence-bench 5.1).
  The bench is at its ceiling on hidden tests, so it cannot show a lighter Temper is worse (evidence-bench 6.7).
- **Change.** In 1c add the columns "hidden tests, rules met on vague tasks, mutation score of the tests left,
  files outside the plan". In the "before" round add the `careful-ask` arm and `mutate.py` on current runs (about
  $10 to $15). Add to every pass line of stages 2 to 4: "and rules met at least 95% on the vague tasks, hidden tests
  equal, mutation score of the tests left not below the before round". Add to section 7: "If one added sentence to
  plain Claude Code meets as many rules as Temper on today's model, Temper's case on a vague request is the record
  and the commit block only. The owner is told before stage 3 starts."

### M4. "Fast" is judged on toy tasks only, and the wait the person sits through is not a target

- **Draft items:** 1c, the pass lines of stage 4, 6d ("add a compiled fixture to the bench first": stage 6).
- **Evidence.** All 11 tasks are the author's, ten Python, 22 to 583 lines; a suite takes under a second. Stage 4c
  to 4e exist to save suite runs and 6d's gain "is on compiled stacks and is unmeasured"; the verifier of the one
  tree change: "will not move the draft's pass lines on the current benchmark". On the one real Java run Plan took
  12 minutes and a Build task 25. Under two approvals the person waits attentively only from the request to the
  approval; that number is in no table.
- **Change.** In 1c add: (a) a scripted project with a slow suite in CI's free floor, which counts full suite runs
  (a cap: one on the base, one per group; today 4 to 5 on a two group run); (b) one real Maven or Gradle project
  measured once before and once after stage 4 (the verifier's round M5, $25 to $75 each); (c) the field "seconds
  from the request to the approval on screen". Add to section 2 a row "the approval is on screen within N seconds"
  with today's value from the before round. Add to stage 4's pass line: "the replay of the Java run ends with no
  loop to Plan and at most one full suite run per tree".

### M5. A run without the mod, and hosts other than the terminal, have a paragraph and no pass line

- **Draft items:** the paragraph "Without the mod" in section 2; 2a; 2e; section 6; section 7.
- **Evidence.** Whether a user has the mod is the host's decision: here the hooks modules of installed plugins wait
  on a rollout flag (`v-mod-driver.md` section 6), an organization can switch it off, and the share of users with it
  cannot be known. Without it a Sonnet session relays each step for $0.28 to $0.97 a run. After 2a one `temper go`
  call runs the task gate, the group gate, `integrate` and `gate build` in a row; "whether the host cuts such a call
  at its default time limit is not determined" (`v-auto-advance.md` section 4), and `commands/temper.md` sets no
  limit (grep: no "timeout"). 2e names only "the mod's drawing above the dialog"; the VS Code panel and cloud
  sessions draw nothing; in `claude -p` a run stops at the first gate (`docs/mod.md:134-145`).
- **Change.** Add a column "without the mod" to the pass line table of section 2 (same dialogs; cost at most the
  driven run plus $0.30). Run both arms once per release in 1c. Add to 2a: "No call the conversation makes runs
  longer than the host's limit for one command: longer work goes behind the existing `wait` action. Measured in
  stage 1 with a suite of 5 minutes." Add to 2e: "Where the mod draws nothing (no mod, the VS Code panel) the same
  panel is printed as text before the question." Add to section 6: "Hosts with no person (`claude -p`, cloud
  sessions, CI): unchanged; a run still needs a person twice." Reword the first line a user reads without the mod
  to say what is the same and what it costs (`alt-person.md` 4.4 has the text).

### M6. The order puts the owner's own phrase second to last, and holds back items that are days of work

- **Draft items:** the order of stages 3 and 4; items 4a, 4i; stage 2's size.
- **Evidence.** Stage 4 ("No back and forth") starts after 31 to 44 working days. Inside it sit small, independent
  items: 4a is "a brief change and one call"; 4i is 0.5 to 1 day and the `plan patch` repairs under a day
  (`v-failure-budget.md` 6.1). Stage 3 changes briefs and the plan contract; 4b to 4d change the runner. They touch
  different files. The first thing a user sees change arrives after 21 to 30 days, though the two prototypes are 18
  and 31 lines.
- **Change.** (1) Move 4a, 4i and the `plan patch` repairs into stage 2. (2) Split stage 4: **4A, faults found
  early** (4b, 4c, 4d, 4e) and **4B, repair where it happened** (4f, 4g, 4h). (3) State under the stage table:
  "Stage 3 and stage 4A may run side by side; 4B follows 4A." (4) Split stage 2 into "the questions" (2a to 2d, 2i:
  the release a user notices) and "what the questions show and what carries them" (2e to 2h). (5) Say in section 0
  when the first visible change ships.
- **And say what the phrase means.** Add to section 2: "'No back and forth between phases' is two numbers: the
  questions asked between phases (6 + G today, 0 after stage 2) and the times a run goes back to an earlier phase
  (7 of 18 benchmark runs had two or more Reviews; target 0 on a clean task, and at most the budget on a failing
  one)." Add the second number to 1c.

### M7. The six decisions are not the right six

- **Draft item:** section 3.
- **Not real decisions as written.** #5 (Build task model) says itself "decide after stage 1": it is not a decision
  for today, and the owner's own words ("fast") already point to Sonnet for $0.25. #6 follows from "easy to use".
  The first half of #2 restores what four documents already promise.
- **Real, but not decidable as written.** #1 holds three choices in one sentence: passed checks advance; the intent
  is accepted in the plan approval (a wrong intent then costs a second Plan pass, $0.75 to $1.13, and nobody knows
  how often people correct it); the commit stays a click. It also lists five exceptions the owner does not need.
  #4 is the only one with no recommendation and it leaves out the facts that decide it: the directory refused 9.8.0
  and accepts hooks, mods and scripts "only from Verified organizations" (`CHANGELOG.md:202-203`); every change to
  the mod goes to a reviewer again.
- **Missing.** (a) Clear requests: the README tells people to skip Temper for "a change whose rules are already
  written down". Is a clear feature at 2 times plain a goal worth stage 3f, or does the README keep sending them
  away? (b) The budget and the stop rule (B2). (c) Existing projects (B3). (d) PR #115: cut or fix (M1). (e) "A
  check that no measurement shows to pay becomes information, not a gate" (mutation, total coverage, the Design
  stage, three default packs): in this project's history rigor won every such contest without a number on either
  side (changelog-older 5.1). (f) The benchmark money. (g) A freeze on work outside the plan.
- **Change.** Replace section 3 with these, each in four lines (the question, what yes gives, what yes costs,
  recommended answer):
  1. A passed check never asks; you approve what will be built and you keep the result. Yes.
  2. The intent is approved in the same click as the plan. Yes; cost stated.
  3. An unattended run never plans again, never overrides, never pushes; it may repair a critical or high finding
     once. Yes.
  4. A check with no measured gain becomes information: Design as a stage, mutation, total coverage, three packs.
     Yes.
  5. PR #115: merge after the cut. Yes.
  6. Existing projects are offered the new defaults once; the stage commands go. Yes.
  7. Clear requests: aim for 2 times plain (stage 3f), or keep telling people to use plain Claude Code. The owner's
     call; the draft should say what each choice does to stage 3's size.
  8. The plugin directory: keep its rules as limits, stop making releases for it until the Verified question is
     answered. A recommendation, with the facts.
  9. The budget: stages 0 to 2 now; about $300 to $400 of benchmark in all; nothing outside the plan until stage 5.
  Move the Build task model to a list "decided later, on numbers".

### M8. What the person gives up, and how they stop a run, is not on the first page

- **Draft item:** the last paragraph of stage 2; 2a.
- **Evidence.** The draft names three lost options. `v-auto-advance.md` section 5 lists more: "Loop back to Plan"
  at Build, the depth review and "Continue with findings open" at Review, stacked pull requests, the config
  suggestions, "Save for later" between stages, and typing a change at any of those questions. And: "an interrupt
  alone gives no question", because `/temper:temper` resumes a run that goes on by itself.
- **Change.** Add to 2a: "Esc stops the run. `/temper:temper` then asks the question of the stage it stopped in,
  with every option (the existing `park`, about 10 lines)." Add to 2a: "The commit question carries 'Loop back to
  Build', 'Repair the medium findings first' and the pull request options." Add to section 0 a box "What you give
  up", five lines, and the sentence "'Ask me at every stage' keeps all of it".

### M9. The 256 KiB limit bites two more files, one of them within two releases

- **Draft item:** 1b.
- **Evidence (counted).** `CHANGELOG.md` is 246,956 bytes: 15,188 under the limit. The last releases' entries were
  5,433, 9,823 and 2,788 bytes; 9.8.0's was 37,629. Six stage releases do not fit. `scripts/flow.py` is 205,631
  bytes, and stages 2 and 4 put most of their logic there.
- **Change.** Add to stage 0: "Move the changelog entries older than 9.7.0 to `docs/history/`." Add to 1b: "`flow.py`:
  at least 40 KB free before stage 4 (the Build questions move to a module). `quality-check.sh` warns at 90% of the
  limit for every tracked file."

### M10. The plan cites evidence that will not exist when the owner reads it

- **Draft items:** the header (lines 3 to 7), "the full table is in `verify/v-pr115.md`", "the arithmetic is in
  `verify/v-targets-scorecard.md`", the Evidence column of section 1.
- **Evidence.** Both files appeared while I reviewed, and the draft was written before them: its section 2 still
  carries lines that `v-targets-scorecard.md` overrules (B1), and its stage 0 list is not the report's list (13
  bullets against 16, 4 and 29). The scratchpad is a temporary folder: the owner cannot open any of the 28 reports.
- **Change.** The final plan is one file in the repository (`docs/plans/`), with an appendix that holds each number
  it uses, its source in the repository's own documents, and how strong it is (runs, tasks). No scratchpad path in
  the text. The merge list of stage 0 is printed in full in an appendix.

### M11. The documents, the README's numbers and the two videos change in stage 2, not in stage 5

- **Draft items:** 2d (three documents named), 5e.
- **Evidence.** The verifier lists what states the opposite of the new default: `README.md:30` ("You decide each
  gate by clicking an answer"), `docs/getting-started.md:74-78`, `docs/directory-submission.md:50`,
  `reference/autonomy.md` (nearly the whole page), the template's autonomy block, `docs/flow.md:224-235`,
  `.claude/CLAUDE.md`, ADR 0011, 0012 and 0013. The README's price paragraph ("3 to 13 times as much", "5 to 18
  times as long") and "When to use it" change with stages 2 and 3. Both videos on the README show a run that asks at
  every gate. `validate-directory.sh` rules 2 and 3 fix two headings and a line that names the phases.
- **Change.** Add to every stage a line "Documents in the same release", with the list. Reduce 5e to "what is
  left". Add to section 5: "The README's price lines are written from the release's scorecard." Add to stage 2:
  "the two videos are recorded again, or taken off the README until they are".

### M12. Runs in flight, the installed commit hook, and the version number are not mentioned

- **Draft items:** every stage ("each a release"); 2a; 4c; 4f; 4g; 5a.
- **Evidence.** A run saved under one release is taken up under the next: 2a changes what `run_mode` means, 4g moves
  the failure record out of `groups.json`, 4c changes the key of stored runs. The commit hook is a file installed in
  the project; the setup check asks for a reinstall only when fixed marker strings are missing
  (`scripts/temper:4551-4555`), so 4f's exception does not reach an existing project unless the check learns a new
  marker. An existing user's first run after stage 2 behaves differently with no config change and nothing tells
  them.
- **Change.** Add to section 4, before stage 0: "Each release takes up a run saved by the release before it, or
  says in one line that it cannot and offers to start the stage again. One selftest per release replays a saved
  state of the release before. A change to the commit hook adds its marker to the setup check. The first run after
  stage 2 prints once: 'Temper now asks twice. Pick Ask me at every stage for the old flow.'" Add a column "version"
  to the stage table and say whether stage 2 is 9.9 or 10.0.

### M13. No item on the words a person meets, and no picture of what they will see

- **Draft items:** 2e, stage 5.
- **Evidence.** A user meets 115 terms and needs about 12 (ux-onboarding 2.9, 4.2). "Stage" and "phase" name the
  same thing (the owner's request says "phases"; the config says `phases:`; the docs say stages). The commit
  question's label "Commit" names something already done: the code is committed during Build. The draft describes
  the approval in one sentence; `alt-person.md` 4.1 to 4.3 draws the three screens, and they would let the owner say
  yes or no to the thing itself.
- **Change.** Add **5f**: "The words a person meets: at most 12, listed. One word for stage. 'Armed' and 'parked'
  leave every question and panel ('runs by itself', 'stopped for you'). A selftest fails on a question or panel
  that uses a word outside the list." Add to 2e its acceptance: "three people read a sample approval for 60 seconds
  and can say which files change, what is left out, which rules were their own answers and which were assumed, and
  when they are asked next." Put one sample approval, one sample result and one sample stop in the final document.

### M14. An unattended run has no bound in time, and nothing tells the person it is waiting

- **Draft items:** 2h, 2e, decision 2.
- **Evidence.** After the approval the person leaves. The budget of 2h counts repeats; its default is "by
  construction" with no data (`v-failure-budget.md` section 9). The bad real run took 3.2 hours.
- **Change.** Add to 2h: "and a bound in time: a run that has taken N times the approval's estimate stops and
  asks". Add to 2e: "the approval shows an estimate (launches and minutes, from the kept summaries of 1d; the
  shipped medians on a first run), marked 'about'". Add to decision 2 the number of repairs, as the owner's to set.
  Add to section 6 or to stage 2: how a waiting run reaches the person (the host's notification), or that it does
  not.

### M15. Other stacks and monorepos are covered by a clause, not by a check

- **Draft items:** 4b, 4d, section 7 (last bullet).
- **Evidence.** The CLI finds a stack at the repository root only and knows six (`scripts/check_run.py:76-146`);
  anything else (.NET, Ruby, PHP, a monorepo with the project in a folder) returns nothing and a Sonnet Check agent
  runs instead. Outside Maven 24 of 33 sample environment failures pass the preflight as "needs new code". The
  benchmark is ten Python tasks and one TypeScript.
- **Change.** Covered by B4 item 5 (a scripted first run per detected stack). Add to 4b: "A project the CLI cannot
  read (no test command found) is told so in the first lines, with the one config line that names the command; it
  is not sent to an agent silently." Add to section 6: "Stacks the CLI does not detect and monorepos get the same
  flow with a test command the person names; no detection work is planned."

---

## 4. What the draft does not cover, area by area

| Area | In the draft | Must it be | Where I ask for it |
|---|---|---|---|
| Users without the mod | one paragraph in section 2 | yes: the host decides who has the mod | M5 |
| Hosts other than the terminal | nothing | one table and one line in "not in the plan" | M5 |
| Stacks beyond Python and Maven; monorepos | clauses in 4b, 4d | yes, as a pass line: first run green per stack | B4, M15 |
| Long suites | 4e ("bounded, or information only") | yes: a rule from the measured suite time, and one command limit without the mod | B4, M4, M5 |
| Existing users: configs | "never overwritten" | yes: it decides whether four stages reach them | B3 |
| Existing users: runs in flight, the view version, the hook | 1f says "additive in version 1" | yes, one rule and one selftest per release | M12 |
| The bug flow | ratios only | yes: it is the cheapest way in and it keeps 4 questions | M2 |
| README and the promise | 2d names three documents | yes, per stage | M11 |
| The plugin directory's rules | decision 4, 1b | the facts and a recommendation; two more files near the limit | M7, M9 |
| The cost of the plan | effort per stage | yes: the sum, the dollars, whose time, the end | B2 |

Does any stage make the bug flow worse? 4b adds a full suite run on the base beside a 90 second run: no dollars, but
on a slow suite the baseline outlives the fix. The draft should say the fix run does not wait for it. Nothing else
does. 2g and 2h make it better (the hand back tail, one budget in place of `fix.max-loops`).

---

## 5. "Once and for all"

**What in the draft stops the next 31 days from adding 18 question sites again?** One thing: the cap on question
sites in `quality-check.sh` (1e), which the same commit may raise. Is it enough? No: see B5. The scripted floor is
the strongest part of section 5 and should stay; it needs fixtures made from the real templates.

**Is there a point where the plan says "stop: it is good enough"?** No. Stage 6 is open, no stage has a line for
giving an item up, and the plan does not say it ends. See B2 for the text: the plan ends with stage 5; an item under
the noise is dropped; a stage over 1.5 times its estimate stops; the owner may stop after any stage.

**What I would add or make stricter**, in order of weight: the question rule as a check (a question must name its
decision; no question after a passed check); caps only the owner can raise; the release gate as a committed file
that CI reads; the fault rule in `.claude/CLAUDE.md`; a reader for everything written; a freeze during and 60 days
after. One more, from `alt-smallest`: "nothing new is on by default without a line in `docs/evidence/`". PR #115
turned on three defaults with no measurement behind any.

---

## 6. Can the owner say yes or no in ten minutes?

Not from sections 0 and 3 as written. What stops them:

1. No total and no end (B2).
2. Page one does not separate what is certain from what is hoped (B1).
3. What they give up is at the bottom of stage 2 (M8).
4. Decision 4 has no recommendation; decision 5 is not for today; decision 1 is three decisions (M7).
5. The stage table's pass lines are in builder's terms ("CI under 12 minutes", "bench mean at most 4"); a row "what
   you see change" is missing.
6. They are not shown the thing: no sample of the approval or of the commit question (M13).

**Noise the owner does not need in the body** (move to an appendix for the builder): the header's note on line
numbers and revisions; the Evidence column of section 1 with its file and line lists; every `flow.py:NNN` in
section 4; the prototypes' line counts; the 13 bullets of stage 0; 6a to 6e. Section 1's ten causes are worth
keeping, one plain line each with its size.

---

## 7. Wording

### 7.1 Words that need a plain sentence at first use

| Word in the draft | Say instead, or add |
|---|---|
| armed, arms | "runs by itself after your approval" |
| park, parked | "stops and waits for you" |
| carve out (of the commit hook) | "one exception to the commit block: the CLI's own repair commit" |
| digest | "a fingerprint of the files; the same fingerprint means the same code, so a test that passed need not run again" |
| hand back | "the mod gives the run to the chat model, which then runs every later step, slower and for money" |
| structural floor | "the questions and agent starts a run has when nothing goes wrong, counted by a script with no model" |
| carrier ("both carriers") | "whatever runs the loop: the mod's code, or the chat model" |
| driver | "the mod's code that runs a run with no model in the chat" |
| the policy | "the fixed rules an unattended run follows at Review and Check" |
| door | "a stage command, such as /temper:plan, that only enters /temper" |
| Blocking dialog | "the product questions your request left open" |
| tier, risk H | "how large the change is (simple, medium, complex); how risky (low, medium, high)" |
| gate, gate row | "a stage's check; one line of it" |
| static rows | "checks of the plan's text that run no command" |
| reopen closure | "the tasks that depend on a changed task" |
| baseline | "your own tests run once on the code as it is, before anything changes" |
| mutant, mutation | "a planted bug; the share of planted bugs your tests catch" |
| integrate | "the step that joins the groups' work and runs the whole suite" |
| the brief (3h) | two meanings in the draft: an agent's instruction page, and the project summary in `.temper/brief.md`. 3h means the second; say "the project summary" |
| caps (1b) and caps (1e) | two meanings: the directory's file size limit, and the growth limits. Call the first "the size limit" |
| "words of /temper:temper" | "a first word after the command, such as status" |
| TRIVIAL "ends the run" (2c) | say what the person sees: for a one line change Temper says so and steps aside |
| G, T | "the number of Build groups", "the number of builder agents" |
| scripted run, replay | "a run with the real CLI and scripted agents, no model, free" |

### 7.2 Numbers given without saying where they come from

| Where | Number | Add |
|---|---|---|
| Section 0 | "$1.9 to $2.5 and 600 to 870 s" | two tasks, 2 runs each, small Python, a simulated person who answers at once, on 9.8.0 code; nothing is measured on 9.8.5 |
| Section 0 | "Real runs averaged 13 dialogs" | they are 18 benchmark runs with live models and a simulated person, not users' runs. The two "bad real runs" in the next sentence are real. Write "18 benchmark runs" |
| Section 0 table | every effort range | "one person's working days, CI waits included, from the verifier reports"; and the sum |
| Stage 1 | "CI in 10 minutes" (title), "about 10" (1a), "under 12" (pass line) | one number |
| Stage 2 pass line | "bench mean at most 4" | mean of what: dialogs per run on the 18 run set, 13.1 today |
| Stage 3 pass line against section 2 | 2.5 and 4 against 2 and 3 | one line (B1) |
| Row B | "Half of the bytes Plan writes ... read by no script and no later agent" | one plan, from 9.6.0; three pages do tell later agents to read the scenario lines (`v-lean-front.md` correction 1) |
| Row D | "7 of 18 runs had two or more Reviews" | the same 18 benchmark runs |
| Section 2, bug "today" | "1.9 to 2.4 times" | 1.85 to 2.9 with the two later single runs (verifier 3.1) |
| Decision 4 | "16 of 33 releases" | 17 with 9.8.1 (changelog-older section 3) |
| Decision 5 | "$0.07", "100 s for about $0.25" | 18 runs, three tasks, 9.8.4 |
| 3b | "about $0.14 a pass" | on Opus; $0.07 on Sonnet; an estimate from one plan |
| 3e | "About 4 hours and $75" | three arms at about $25 an arm; the two arm round cost $48.68 |
| 4c | "4 to 5 down to 3", "5 down to 1 or 2" | counted on a toy project by a verifier; only with one owner of the suite command |
| 4e | "up to 40 suite runs", "50% and 80%" | the code's limit; one reader, one tree |
| 6c | "about 31 s" | 737 process starts on a toy project |
| Section 7 | fine | |

---

## 8. What the three independent plans have that the draft lacks

| From | What | Take it? |
|---|---|---|
| alt-person | The three screens drawn (approval, result, stop) and a one minute reading test as their acceptance | yes (M13) |
| alt-person | "Seconds to the first decision" as a unit | yes (M4) |
| alt-person | The first run on a real project walked step by step (15 minute suite, 55% coverage, husky), and a baseline that measures the project and writes the config from it | yes (B4) |
| alt-person | Permission prompts counted; `allowed-tools` | yes (B4) |
| alt-person | A table "always the person's decision" and the rule "a question must name the decision" | yes (B5) |
| alt-person | Without the mod as a step of its own, with an honest first line | yes (M5) |
| alt-person | Documents that quote questions are generated from the view fixtures | yes, in section 5 |
| alt-person | Blocking questions capped at four, so always one dialog | measure first: asking is the one measured gain |
| alt-person, alt-clean-slate, alt-smallest | PR #115: cut what adds loops, keep what saves work, leave the policy off, then merge | yes, as the owner's choice (M1) |
| alt-smallest | A column "Proof" for every change: what the owner can look at to know it worked | yes: one per stage item |
| alt-smallest | "What this plan does not do": it does not make the run short, and says so | yes: the draft needs that paragraph (B1) |
| alt-smallest | "Any of 4, 6, 7 and 8 can be dropped and the rest still stands"; 17 to 20 days and $60 for the questions, the output cut, checks once, one cap | yes: it is the proof that stages 0 to 2 can be approved alone (B2) |
| alt-smallest | The decision on clear requests: accept about 4 times plain, or order the front agent merge | yes (M7) |
| alt-smallest | "Nothing new is on by default without a line in `docs/evidence/`" | yes (B5) |
| alt-clean-slate | A target table with a row for a bug (dialogs 4 to 2), for a large risky change (launch and Opus pass limits) and a value floor (rules met at least 95%) | yes (M2, M3) |
| alt-clean-slate | A column "what is deleted" for every step | yes: add it to the stage table |
| alt-clean-slate | "What the owner can stop after: any step" and version numbers per step | yes (B2, M12) |
| alt-clean-slate | The model test and the two missing controls in the first step | yes (B1, M3) |
| alt-clean-slate | A risks table with what limits each risk | yes, in place of section 7's list |
| alt-clean-slate | "With the mod off, the same gates, not the same speed" as a decision | yes (M5) |

The draft is ahead of all three in one respect: it has verifier reports behind its mechanisms. It is behind all
three in telling the owner what they will see, what they decide, what it costs and when it ends.

---

## 9. Proposed structure of the final document

**Headings**

1. The plan on one page
2. What you decide (nine decisions, four lines each)
3. What you will see (a clear request; a vague one; a failed check; your first run on an existing project; a bug
   fix; without the mod; with the three sample screens)
4. Where Temper is today (the ten causes, one plain line and one size each)
5. The targets and what they rest on (certain, target, unknown; the arithmetic; the measurement rounds with dollars)
6. The releases (for each: what you see change, what is removed, the pass line, days, what it needs first,
   documents in the same release, what an existing project must do, how you know it worked)
7. PR #115 (the verdict; keep, cut, fix)
8. What keeps it from growing back, and when the plan ends
9. Who is affected (existing projects, runs in flight, without the mod, other hosts, other stacks, slow suites,
   the plugin directory)
10. Not in the plan, each with its reason
11. Risks, and what limits each
- Appendix A: the mechanisms, with file and line (for the builder)
- Appendix B: every number, its source, how strong it is
- Appendix C: the twelve words a user meets; the plan's own terms

**The first page holds**

- The three opening sentences.
- One table, today against after, for a clear feature, a vague feature, a bug: questions, minutes, dollars, times
  the run goes back; each cell marked certain or target.
- "What you give up", five lines.
- The releases in one table: what you see change, days, version, "if you stop here you have".
- "What it costs": days, dollars, your own time.
- "What you decide now": nine lines, each with the recommended answer.
- "When it is done, and what keeps it done": three lines.

**The three sentences that should open it**

1. Today a Temper feature run costs 4 to 5 times what plain Claude Code costs, takes 7 to 10 times as long and stops
   to ask you 8 to 13 times, though only two of those questions decide anything; that is measured on small Python
   tasks, and the one real Java run was far worse.
2. This plan makes a run ask twice (approve what will be built, keep the result), repairs a failure in the phase
   where it happened instead of going back, and aims at about 2 times the cost and 4.5 times the time of plain
   Claude Code: the two questions are certain, the dollars and minutes are a target that one test of about $40
   confirms or lowers in the first weeks.
3. It is six releases, 56 to 80 working days and about $300 to $400 of benchmark runs; you can stop after any
   release, it is finished after the sixth, and from the second release on a check stops questions, agents, options
   and config lines from growing back unless you raise the limit yourself.

(The six releases are stages 0 to 5; stage 6 is not part of the plan.)
