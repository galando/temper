# Every question a person can be asked (Temper, PR #115 head, 9.8.5)

Reader: `flow-questions`. Tree read: `/home/user/temper` at `9a01eff` (branch `pr115`). Files read whole:
`scripts/flow.py` (3,111 lines by `wc -l`, not 3,165), `scripts/go.py`, `scripts/answer_ops.py`,
`scripts/gate_rows.py`, `docs/flow.md`, `commands/temper.md`, `templates/temper.config.default`,
`hooks/temper-mod/core/driver.ts`, `scripts/fresh_review.py`, `scripts/plan_ops.py`, `scripts/decisions.py`,
`scripts/loop_step.py`, `scripts/risk.py`, `scripts/cli_ctx.py`, `scripts/intent_parse.py`, `agents/intent.md`,
`agents/plan.md`, `agents/design.md`.

How each claim is marked:

- **[code]** verified by reading the code at the cited line.
- **[measured]** I ran it. All runs were in a scratch clone
  (`.../scratchpad/work-flow-questions/repo`, `git checkout pr115`) with the project's own end to end driver
  (`scripts/e2e/`: the real CLI, scripted agents, a scripted person who takes the recommended option, and for
  `driver` mode the mod's real `core/driver.ts`). My throwaway wrappers are in
  `.../scratchpad/work-flow-questions/drv/` (`trace.ts`, `policy.ts`, `pending.ts`, `carry.ts`, `blocking.ts`,
  `trivial.ts`, `manual.ts`, `designq.ts`, `onegroup.ts`). Nothing was run in `/home/user/temper`.
- **[doc]** only a doc says so.
- **[inferred]** follows from code I read, not run.

---

## 0. The findings that matter most

1. **A default run asks 5 + G questions on a clean pass (G = number of Build groups when there are two or
   more), plus the Context check, plus Intent's own questions.** Measured: 7 questions for a 2 group plan, 5 for
   a 1 group plan, 8 with Design. Six of the gate questions have a *constant* recommended answer whenever the
   gate passed (Intent, Design, each group, Build, Review, Check): the label `(Recommended)` is written into the
   code, not computed (`scripts/flow.py:635, 730, 1943, 749, 784, 817`). [code + measured]
2. **The fewest questions possible today is 3 gate clicks** (Intent, Plan, Commit), reached only by choosing
   the option that is *not* recommended at the Plan question and by writing two config keys by hand
   (`autonomy.policy: decide`, `plan.context-check: off`). Measured. No config key removes the Intent question,
   the Plan question or the commit question. [code + measured]
3. **The recommended answer at the Plan question is the one that asks the most**: `Stage by stage
   (Recommended)` (`scripts/flow.py:673`). The one click that removes the Build questions, `Autonomous Build`,
   is the second option and never recommended. [code]
4. **The Context check is asked on every run under the default config**, also for a clean map, because the
   Plan brief tells Plan to write `- reviewed: pending` (`agents/plan.md:91`, `templates/plan.md:8`,
   `reference/plan.md:70`) and no code turns `pending` into `auto`; the gate row fails on `pending` unless the
   mode is `off` (`scripts/plan_ops.py:92-94`). The config comment promises `auto: ask when the Context Map has
   an ignore or a gap` (`templates/temper.config.default:104`). Measured: clean map + `pending` + default config
   asks "Is this the right context for the plan?". Its `Carry forward` option runs nothing and the same question
   comes again, without end (`scripts/flow.py:2321`; measured 4 times in a row). [code + measured; doc disagrees]
5. **PR #115 adds a built in loop back from Design to Plan.** Any answered `Design:` question makes the Design
   gate fail (`tasks agree with decisions`) until `tasks.md` changes, and the question then recommends `Loop
   back to Plan` (`scripts/decisions.py:60-69`, `scripts/flow.py:733-739`, `scripts/answer_ops.py:146-148`).
   Measured: `gate design` passed (exit 0), the person answered one Design question, `gate design` failed
   (exit 1), question `Loop back to Plan (Recommended) | Override and continue | Save for later`. Following the
   recommendation costs another Plan on Opus and another Design on Opus. [code + measured]
6. **PR #115's policy (`autonomy.policy: decide`) loops back to Build for a criterion only the person can
   confirm.** `policy_move` has no branch for a `Validate: manual` criterion (`scripts/flow.py:1173-1180`),
   while the ordinary Check question has one (`scripts/flow.py:824-836`). Measured: an armed policy run with a
   required manual criterion ran `state loop check build --reason 'policy: acceptance evidence: AC-02 has
   n...'` and launched a Build fix pass, where the unarmed run asks one click (`Confirmed (Recommended)`).
   [code + measured]
7. **With the mod's run driver, a TRIVIAL request is not handled.** The Intent agent writes no file, the
   Intent gate passes on an absent `intent.md` (`scripts/temper:2038-2039`), the driver does not read the
   agent's `TRIVIAL` word (`hooks/temper-mod/core/driver.ts:422-434`), and the person is asked `Intent: the
   check passed. Accept the intent and continue to Plan?` with `Continue to Plan (Recommended)`. Measured. The
   model loop handles TRIVIAL in prose (`commands/temper.md:176-179`). [code + measured]
8. **The questions and the agent launches are the same with the mod and without it** (measured, and asserted
   by `scripts/e2e/run.ts:28-31`). What differs is who does the mechanical steps: with the mod off, the Sonnet
   session (`commands/temper.md:4`) takes one turn at every stop of `temper go`: 13 stops for a 1 group run and
   16 for a 2 group run (measured from the driver trace); with the driver those stops cost no model turn.
9. **The last question guards a record commit, not the code.** A grouped Build commits each task, each group
   and the merge itself; the commit step's message is then `docs(<slug>): record the run: spec, gate ledger and
   report (the code is in the commits before it)` (`scripts/flow.py:2184-2198`; measured in every run). [code +
   measured]
10. **PR #115 breaks the Review question it changed.** At a passed Review with an open medium finding (the
    new "repair by default" question), `More options` holds only `More options | Make a small change`:
    `Accept a finding`, `Grill Me`, `Teach Me` and `Save for later` cannot be reached, and the inner `More
    options` leads to itself. Cause: `add_adhoc` makes room by dropping `Teach Me` only when the first option
    starts with `Continue` (`scripts/flow.py:925-930`); the first option is now `Loop back to Build
    (Recommended)`, so the full More question falls into the last branch, which slices the `More options`
    option itself and replaces the More question (`scripts/flow.py:943-947`). Measured on pr115:
    `more: More options | Make a small change`; on origin/main (9.8.4) the same state gives `more: Accept a
    finding | Grill Me | Make a small change | Save for later`. [code + measured on both]

---

## 1. Inventory of every question

Headers are constants: `Temper gate`, `Build group`, `Temper resume`, `Scope drift`
(`scripts/flow.py:40-45`); `Question N` (`flow.py:2502`); `Manual task` (`flow.py:1897-1898`); `Group command`
(`flow.py:2028`).

Every question goes through `Builder.question` (`flow.py:492-507`), which holds four options at most: a fifth
and later option is moved under a generated `More options` question (`flow.py:493-498`; also `with_more`,
`flow.py:509-515`, and `add_adhoc`, `flow.py:943-947`). `flow.py` has 41 `self.question(` sites, 12
`self.with_more(` sites and 14 `"action": "ask"` returns (counted with grep).

"Happy" column: **yes** = appears in a default run where every gate passes; **cond** = appears in a clean run
only under the named condition; **no** = appears only after a failure, a non default choice or a non default
config.

### 1a. Stage gate questions: `Builder.ask(stage)`, `scripts/flow.py:574-877`

| # | Question (text as built) | Built at | When | Options (in order; `>` = under More options) | Recommended, and the rule | Happy |
|---|---|---|---|---|---|---|
| G1 | `Intent: the check passed. Accept the intent and continue to Plan?` | `flow.py:633-637` | Intent gate PASS (or skipped) | Continue to Plan · Grill Me · Teach Me · Save for later | Continue to Plan: constant | **yes**, every run |
| G2 | `Intent: ... The branch X already exists from an earlier run ... Accept the intent and continue to Plan?` | `flow.py:622-632` | Intent PASS and `feature/{slug}` exists with commits HEAD lacks | Continue on X · Continue on a new branch X-2 · Grill Me · Save for later | none | no |
| G3 | `Intent: the check failed (rows). Correct intent.md, or skip the check?` | `flow.py:638-640` | Intent gate FAIL. With open Blocking questions it is built too, but the Blocking questions are asked first and the gate runs again (`driver.ts:387-391`) | Override and continue · Grill Me · Save for later | none | no |
| G4 | `Plan: the check passed.[ A reader with no context took it as: ...] Approve the plan and continue to Build?` | `flow.py:672-680` | Plan PASS, no Design stage | Stage by stage · Autonomous Build: run Build unattended · Fresh review first (default `plan.fresh-review: ask`) or Open HTML review (review off or already asked) · > Open/Share HTML review, Grill Me, Teach Me, Save for later | **Stage by stage**: constant (`flow.py:673`) | **yes**, runs with no Design |
| G5 | same text, `... continue to Design?` | `flow.py:681-689` | Plan PASS, Design follows | Continue to Design · Fresh review first (or Open HTML review) · Open HTML review (or Share) · > Share HTML review, Grill Me, Teach Me, Save for later | Continue to Design: constant | **yes**, runs with Design |
| G6 | G4 or G5 with `The fresh review left N finding(s) open: ... They go to the builder as notes.` | `flow.py:658-669, 676-677, 681-683` | Plan PASS with open fresh review findings below high | as G4/G5 with `Revise the plan` third | Stage by stage / Continue to Design; Revise never recommended (`flow.py:662-663`) | no (needs the fresh review) |
| G7 | `Plan: the check failed (rows). [limit text] Revise the plan / Run the fresh review again / Accept a finding, or skip the check?` | `fresh_question`, `flow.py:1044-1069` | Plan FAIL on a fresh review row | Run the fresh review again (a reviewer did not finish, rounds left) · Revise the plan (open blocker, rounds left) · Accept a finding (open blocker) · > Loop back to Intent, Override and continue, Grill Me, Save for later | first of: Run the fresh review again, else Revise the plan (`flow.py:1052-1059`) | no |
| G8 | `Plan: the check failed (rows). The project's own files say what it needs: add the proposed setup block (...) and check again?` | `flow.py:693-699`, option from `setup_offer`, `flow.py:1183-1205` | Plan FAIL, `preflight` row says environment fault, config has no `setup:` block (new in PR #115) | Add the proposed setup block **or** Let an agent find the setup · Loop back to Intent · Override and continue · Save for later | the setup option: whenever one is offered | no |
| G9 | `Plan: the check failed (rows). Fix the plan, or skip the check?` | `flow.py:700-701` | any other Plan FAIL | Loop back to Intent · Override and continue · Grill Me · Save for later | none | no |
| G10 | `Design: the check passed[, with N open area(s) of concern: ...][. Design changed the plan's tasks ...]. Continue to Build?` | `flow.py:708-732` | Design PASS | Continue to Build · Autonomous Build: run Build unattended · Walk through step by step · > Grill Me, Loop back to Plan, Teach Me, Save for later | Continue to Build: constant, also with open concerns (it records them as accepted, `flow.py:718`) | **yes**, runs with Design |
| G11 | `Design: the check failed (tasks agree with decisions ...). Loop back to Plan so the tasks follow your answers?` | `flow.py:733-739` | Design FAIL after a `Design:` answer (new in PR #115) | Loop back to Plan · Override and continue (reasons: The tasks already agree / I accept the risk / It is not a real issue) · Save for later | Loop back to Plan: constant (`back_opt(rec=True)`) | **cond**: every run where Design asks at least one question |
| G12 | `Design: the check failed (rows). Fix the design, or skip the check?` | `flow.py:740-741` | other Design FAIL | Loop back to Plan · Override and continue · Save for later | none | no |
| G13 | `Build: the check passed. Continue to Review?` (Fix run: `Fix: ...`) | `flow.py:743-752` | Build gate PASS, run not armed | Continue to Review · Change something · Teach Me · > Loop back to Plan, Make a small change, Save for later | Continue to Review: constant | **yes** unless armed |
| G14 | `Build: the check failed (rows). Run Build again?` | `flow.py:753-765` | Build gate FAIL | Run Build again · Loop back to Plan · Override and continue · > Make a small change, Save for later | Run Build again; after the same failure twice: Save for later (`flow.py:755-763`) | no |
| G15 | `Review: the check passed[, open findings: n low]. Continue to Check?` | `flow.py:772-791` | Review PASS, no open finding at medium or above | No finding (measured): Continue to Check · Architecture Depth Review · Grill Me · > Teach Me, Make a small change, Save for later. A low finding open (measured): Continue to Check · Loop back to Build · Architecture Depth Review · > Accept a finding, Grill Me, Make a small change, Save for later | Continue to Check | **yes** unless policy |
| G16 | `Review: the check passed, open findings: n medium. Loop back to Build to repair them?` | `flow.py:779-788` | Review PASS with an open finding at medium (new in PR #115: repair is the default) | Measured: Loop back to Build · Continue to Check · Architecture Depth Review · > **More options, Make a small change** (a defect: Accept a finding, Grill Me, Teach Me and Save for later are lost, finding 10) | Loop back to Build: any open finding in critical, high, medium (`flow.py:780`) | no |
| G17 | `Review: the check failed (rows)[, open findings ...]. Loop back to Build?` | `flow.py:792-808` | Review FAIL (a finding at `review.block-on`, default critical and high, `flow.py:420`; or the review did not finish) | (Run Review again) · Loop back to Build · Accept a finding · Override and continue · > Architecture Depth Review, Save for later | Run Review again when no completion row; else Loop back to Build (`flow.py:794-798`) | no |
| G18 | `Check: the check passed. Commit?` | `flow.py:813-821`, PR options `flow.py:887-897` | Check PASS, not under the policy | Commit · Loop back to Build · Commit and open PR · > (Commit and open stacked PRs, with 2+ groups), (Review config suggestions), Make a small change, Save for later | Commit: constant | **yes** unless policy |
| G19 | `Check: AC-n needs your confirmation: ... Confirm?` | `flow.py:824-836` | Check FAIL only because a required `Validate: manual` criterion has no row | Confirmed · Loop back to Build · Make a small change · Save for later | Confirmed: constant | **cond**: every run whose intent has a required manual criterion (measured) |
| G20 | `Check: SETUP: the environment was not ready (...), so the result is no verdict on the code. ... run Check again?` | `flow.py:837-851` | Check hit the environment (new in PR #115) | (Add the proposed setup block / Let an agent find the setup) · Repair the environment and run again · Save for later · > Loop back to Build, Override and continue | the setup offer when there is one, else Repair | no |
| G21 | `Check: the check failed (rows). It failed the same way after it ran again: install what it names, or save the run for later?` | `flow.py:855-863` | the same missing measurement after `Run Check again` | Save for later · Run Check again · Loop back to Build · Override and continue | Save for later | no |
| G22 | `Check: the check failed (rows).[ The triage says ...] <lead option>?` | `flow.py:864-873`, options `acceptance_options`, `flow.py:1487-1511` | only the locked acceptance tests failed | Restore the locked tests **or** Correct the acceptance test / Loop back to Build · Override and continue · Save for later | by the triage agent's verdict (`test` -> Correct the test), else by whether a loop back already ran (`flow.py:1504-1508`) | no |
| G23 | `Check: the check failed (rows). Run Check again / Loop back to Build?` | `flow.py:874-875` | other Check FAIL | (Run Check again) · Loop back to Build · Override and continue · Save for later | Run Check again when every failed row is a missing measurement (`flow.py:879-885`), else Loop back to Build | no |
| G24 | `<Stage>: ... (this stage ran before; it is checked, not run again). Go on to X?` | `flow.py:600-614` | a stage before the door of `/temper:build` and the like | PASS: Continue to X · Save for later. FAIL: Run <stage> · Override and continue · Save for later | Continue / Run <stage> | no (doors only) |
| G25 | `RCA: the root cause is in .../rca.md. Proceed to Fix?` | `flow.py:616-619` | `/temper:fix`, after RCA | Proceed to Fix · Save for later | Proceed to Fix | yes for a fix run |
| G26 | `Pipeline: every job passed. End the run?` / `... Run Pipeline again?` / `... the fix limit is reached ...` / `... Apply the fix and push?` | `pipeline_question`, `flow.py:1011-1037` | after `Commit and open PR`, while `phases.pipeline` is not false | End the run · Save for later / Run Pipeline again · Save / Apply the fix and push · End the run · Save | End the run (green, or limit reached); Run Pipeline again (no final result); Apply the fix and push (red, rounds left) | no (only after the PR option) |

### 1b. Build loop questions (inside the Build stage)

| # | Question | Built at | When | Options | Recommended, and the rule | Happy |
|---|---|---|---|---|---|---|
| B1 | header `Build group`: `Group G (title) passed its check. Continue?` | `group_question`, `flow.py:1928-1949`; asked from `flow.py:1758-1766` | a group's gate PASS, not armed, **and the plan has 2 or more groups** (one group goes on by itself, `flow.py:1763-1765`) | Continue · Change · Stop | Continue: constant | **yes**, once per group for G >= 2 |
| B1a | `Which task changes?` (`change`) | `flow.py:1931-1941` | after `Change` | one option per task (More tasks beyond 4) | none | no |
| B2 | `Group G failed its check [N times] (reason). What failed: ... <lead>?` | `group_failed`, `flow.py:1957-2046` | a group's gate FAIL, not armed | up to six, the recommended first: Run the gate again with twice the time · Fix the group's merged work · Run the group's tasks again · Loop back to Plan · Change the group's command (typed, PR #115) · Save for later | computed (`flow.py:1991-2035`): first time out -> twice the time; every task passed and the check ran -> Fix (once); first failure otherwise -> rerun; then Loop back to Plan; then Save; second time out or an empty fix -> Change the command | no |
| B3 | `Group G is parked ...` (three texts) | `parked`, `flow.py:2067-2129` | a group parked: agent commits the CLI did not make / a task blocked on an undeclared file / tasks out of attempts | Take the commits out and run the task again · Keep the agent's commits · Save; or Loop back to Plan · Run the task again · Save; or Run the task again · Loop back to Plan · Save | per variant; after a rerun parked again -> Loop back to Plan (`flow.py:2117-2128`) | no |
| B4 | `Task N (title): its tests already pass before any change ... Accept it as done?` | `covered_task`, `flow.py:1832-1855` | a task's RED run passed | Accept it as done · Run it again · Loop back to Plan · Save for later | Accept it as done (an armed run takes it by itself, `flow.py:1837-1842`) | no |
| B5 | `Task N (title) failed on the environment, not on its code: ... then check it again?` | `env_task`, `flow.py:1857-1870` (PR #115) | a task's GREEN failed on the environment | Check it again · Save for later | Check it again; asked in every mode, armed too | no |
| B6 | header `Manual task`: `Task N (title) is a manual task. Confirm by hand that each Case holds: ...` | `manual_task`, `flow.py:1872-1899` | a `**Test:** manual` task whose files are made | Confirm (then the name question) · Stop | none | cond (plans with manual tasks) |
| B7 | `Group G's branch holds commits the CLI did not make (...). Take them out, or keep them?` / `... Merge the groups again?` | `foreign_branch`, `flow.py:1772-1830` | `temper integrate` found foreign commits | Take the commits out · Keep the commits · Save / Merge the groups · Save | Take the commits out / Merge the groups | no |
| B8 | `Build stopped: tasks.md has tasks but no groups ...` | `no_groups`, `flow.py:1621-1633` | a plan with no groups | Run Plan again · Save for later | Run Plan again while the one Build to Plan loop is unspent | no |
| B9 | `<Stage>: Review of your small change failed (...). Loop back to Build?` | `side_review_failed`, `flow.py:976-989` | after `Make a small change` at Check or Commit | Loop back to Build · Override and continue · Save for later | Loop back to Build | no |

### 1c. Commit questions

| # | Question | Built at | When | Options | Recommended | Happy |
|---|---|---|---|---|---|---|
| C1 | `Commit: every gate passed, and the armed run parked here for you (its report: .temper/autonomy-report.md). Commit?` | `flow.py:2242-2244`; the park at `flow.py:2227-2231` | an armed run reached Commit with every gate passed | Commit · Make a small change · Save for later | Commit | only in an armed policy run (measured) |
| C2 | `Commit: the commit gate failed (rows). Override and commit? / Add the files to the plan? / An override does not clear this row ...` | `flow.py:2247-2277` | commit gate FAIL | Add to plan · (Loop back to Fix) · Override and commit (not offered for the commit gate's own rows, PR #115) · Make a small change · Save for later | Add to plan when files are outside the plan; Loop back to Fix in a fix run | no |

In an unarmed run there is **no question at the Commit stage**: the Check question's `Commit (Recommended)` is
the commit decision, and the report page is written without a question since 9.8.0 (`flow.py:2237-2241`).
`commands/temper.md:104` still says `next` "asks whether to write the report as an HTML page too"; the code
and `docs/flow.md:303` say it does not. [code; one doc disagrees]

### 1d. Questions that come before or inside a gate question

| # | Question | Built at | When | Options | Recommended, and the rule | Happy |
|---|---|---|---|---|---|---|
| Q1 | header `Question N`: each `- Blocking:` line of `intent.md`'s Open Questions | `blocking_asks`, `flow.py:2488-2505`; attached to any `ask` at any stage, `flow.py:2478-2482`; source lines read by `intent_parse.blocking`, `intent_parse.py:26-43` | Intent wrote Blocking questions (six at most, `agents/intent.md:134`); Design wrote `Blocking: Design:` lines (`reference/design.md:37-42`); Plan added one (`agents/plan.md:27-28`) | the line's choices (three at most) · Carry forward; with no choices: Type the answer · Carry forward | the first choice (its description is `Recommended`); a choice marked `(house rule)` is moved first (`flow.py:375-386`) | **cond**: whenever Intent or Design asks. Up to four in one dialog (`commands/temper.md:163-165`, `driver.ts:375-378`) |
| Q2 | the Context check: `The plan leaves out: ...; It could not find: ... Is that right?` or `Is this the right context for the plan?` | `context_question`, `flow.py:2305-2329`; swapped in as the `ask` at `flow.py:2338-2344` | Plan stage, the map's `reviewed:` is neither `human` nor `auto`, and `plan.context-check` is not `off` | As planned · (Include what is left out, when the map has `ignore` lines) · Something else · Carry forward | As planned: constant | **yes** under the default config when Plan follows its brief (measured; finding 4) |
| Q3 | `<label>. What is the reason?` (`reason_question`) | `opt`, `flow.py:475-480` | after any option built with `reason=`: every Loop back (`flow.py:588-593`), Override (`595-598`), Change something (`746-748`), Make a small change (`907-913`), Accept finding (`1084-1086`), Correct the acceptance test (`1509-1511`), Keep the commits (`1819-1821`, `2089-2091`), Override and commit (`2270-2272`) | the preset reasons · Cancel. For a Loop back the only preset is `The check found a real problem` (`flow.py:586`) | none | no (but it follows every recommended Loop back) |
| Q4 | name or command question (`answer_question`): `Task N: what name should the confirmation carry?` / `Group G: what Validate command should it run? ...` | `opt`, `flow.py:463-468`; used at `flow.py:1895-1897` and `2024-2028` | after Confirm of a manual task; after Change the group's command | Type it below · Cancel | none (typed) | no |
| Q5 | `More options` second question | `flow.py:493-498, 509-515, 943-947` | the person picks `More options` | the rest of the options | none | no |
| Q6 | `Review: which finding do you accept?` / `Plan: which finding do you accept?` | `accept_question`, `flow.py:1071-1088` | after `Accept a finding` | Accept finding N (three at most) · Cancel; then the reason question | none | no |
| Q7 | header `Temper resume`: `A run of <slug> is open at <Stage>. Start over?` | `restart`, `flow.py:2279-2285`; carried in every `next` (`flow.py:2364`) | the action is `broken` (`commands/temper.md:120`), or the arguments name another feature (`commands/temper.md:61-62`) | Start over · Cancel | none | no |
| Q8 | header `Scope drift`: `Outside the plan: <path>` / `Why:` / `Change:` | constants `flow.py:43-45`, `drift_info` `flow.py:2843-2844`; the question itself is assembled by the session, `commands/temper.md:180-187` | a Build fix pass panel with a `DRIFT` section; one dialog per file; the driver hands the run back for it (`driver.ts:220-221, 437`) | Add to plan · Revert · Allow once | none | no |
| Q9 | a note added to any question: `Note from Claude (not from Temper): ...` | `add_note`, `flow.py:2348-2358` (PR #115) | the session ran `temper state set ask_note '<step>: ...'` | none of its own | n/a | no |

### 1e. Questions the CLI does not build (an option's `do` hands them to the session or a skill)

| Option | Where | What then asks |
|---|---|---|
| Grill Me, Teach Me | `skill`, `flow.py:487-490`; offered at Intent, Plan, Design, Build, Review | the skill's own questions (`skills/grill-me/SKILL.md`, `skills/teach-me/SKILL.md`) |
| Open HTML review, Share HTML review | `flow.py:643-646` | `reference/plan-review.md` |
| Walk through step by step | `flow.py:704-705` | the session, section by section |
| Architecture Depth Review | `flow.py:769-770` | no question; an analysis, then the Review question again |
| Review config suggestions | `flow.py:818-820` | Accept, Reject or Defer for each suggestion |
| Make a small change | `adhoc_option`, `flow.py:905-913` | "ask them in one line what to change" |
| Something else (Context check), Change (group) | `flow.py:2319-2320`, `1944-1946` | typed text |
| a later door with several planned spec folders | `commands/temper.md:199-200` | "or else ask the person" |

There is **no "report" question** any more (see 1c).

---

## 2. The happy path, per tier

### 2a. How the tier is set and what it changes

- The Plan agent records it: `temper state set complexity <trivial|simple|medium|complex>`
  (`agents/plan.md:30-33`); Intent's `**Complexity:**` line is only a first guess (`agents/intent.md:60-61`). A
  door run reads it from `plan.md`, else `intent.md` (`scripts/temper:765-774`). [code]
- The risk letter is computed, not judged: up to 3 production files L, up to 10 M, more H; a CRITICAL entry
  of the security map makes H; a HIGH entry or a `[CROSS-REPO]` row moves it up one; Plan may raise it
  (`scripts/risk.py:72-108`, `agents/plan.md:129`). [code]
- `intent_asked` is set when the Intent gate ever failed on an open Blocking question (`scripts/temper:2099-2100`). [code]

What the tier (with the risk) changes, and nothing else in the flow reads it:

| What | Rule | Where |
|---|---|---|
| Design stage runs | `phases.design` on **and** (risk H and tier medium or complex, **or** tier complex and Intent asked something); also when `design.md` exists | `flow.py:251-266` |
| Model of a Build task | sonnet for tier complex or risk H; else the brief's `claude-haiku-5-5`; `build.grouped.task-model` overrides | `cli_ctx.py:57-79`, `flow.py:1605-1610`, `scripts/temper:573-583` |
| Blast Radius section required in `plan.md` | tier medium or complex | `scripts/temper:3560-3566` |
| Fresh review by itself | only with `plan.fresh-review: auto` (medium, complex) or `always`; the default `ask` only offers it | `fresh_review.py:117-125`, `templates/temper.config.default:105` |
| Two fresh reviewers | risk H, unless `plan.fresh-review-twice: false` | `fresh_review.py:128-129` |
| Where arming is offered | at the Plan question with no Design; at the Design question with Design | `flow.py:670-675, 726-728` |
| `trivial` | the Intent agent returns `TRIVIAL` and writes nothing; the session clears the run and makes the change itself | `agents/intent.md:17-20`, `commands/temper.md:176-179` |

Three docs state the Design rule three other ways: "complexity >= medium" (`reference/design.md:7-8`),
"medium/complex features" (`templates/temper.config.default:112`), "a complex plan, and a medium one only at
risk H" (`agents/plan.md:129`). The code is `flow.py:266`: a complex plan whose Intent asked nothing and whose
risk is not H gets **no** Design. [code; docs disagree]

Models per agent (the brief's `model:` line unless `models.<stage>` is set, `cli_ctx.py:57-68`): intent sonnet,
plan opus, design opus, plan-review sonnet, acceptance sonnet, build-task `claude-haiku-5-5`, build (fix pass)
sonnet, review sonnet, check sonnet, env sonnet, rca opus, fix sonnet, pipeline sonnet (read from each file's
frontmatter). The session that runs the loop with the mod off is `model: sonnet` (`commands/temper.md:4`).

### 2b. The ordered happy path (default config `templates/temper.config.default`, every gate passes)

Symbols: **B** = Blocking questions Intent wrote (0 to 6). **C** = 1 when the Context check is asked (default
config and Plan writes `reviewed: pending` as briefed: 1), else 0. **G** = Build groups. **T** = task agents
(one per chain of dependent tasks, `flow.py:1558-1588, 1699-1723`; independent tasks run at once, 4 at most,
groups 2 at most, `flow.py:1677-1696`).

**Tier simple, and tier medium below risk H, and tier complex with nothing asked and risk below H** (no Design)

| Step | Who | Agent launch (model) | Question |
|---|---|---|---|
| 1 | agent | Intent (sonnet) | |
| 2 | person | | Q1 Blocking questions, in ceil(B/4) dialogs (only when B > 0) |
| 3 | person | | G1 `Accept the intent and continue to Plan?` |
| 4 | CLI + agent | `temper brief`, Plan (opus), `panel plan`, `gate plan` | |
| 5 | person | | Q2 Context check (when C = 1) |
| 6 | person | | G4 `Approve the plan and continue to Build?` -> `Stage by stage (Recommended)` |
| 7 | agent | Acceptance writer (sonnet), alone, before any group starts (`flow.py:1394-1420, 1641-1643`) | |
| 8 | agents | T Build task agents (haiku; sonnet for tier complex) | |
| 9 | person | | B1 `Group G passed its check. Continue?` once per group, **only when G >= 2**; a group that depends on another does not start until the person's Continue of it (`flow.py:1683-1686`) |
| 10 | CLI | `integrate`, `gate build` | |
| 11 | person | | G13 `Build: the check passed. Continue to Review?` |
| 12 | CLI + agent | `check ahead` (the suite runs while Review reads, `flow.py:1375-1378`), Review (sonnet) | |
| 13 | person | | G15 `Review: the check passed. Continue to Check?` |
| 14 | CLI | `check run`, `gate check`, with no agent when the CLI finds the test command (`flow.py:1359-1364`, `check_run.py:76-136`). A Check agent (sonnet) is launched when the stack is unknown, or to record `Validate: code` or `metric` criteria (`flow.py:1365-1373`) | |
| 15 | person | | G19 manual confirmation (only with a required manual criterion), then G18 `Check: the check passed. Commit?` |
| 16 | CLI / session | `gate commit`; report steps; `report --html`; `state archive`, `spec commit`, `state clear` (`flow.py:2222-2246, 2135-2147, 2176-2220`) | none |

Counts: agent launches **4 + T** (+1 Check agent in the cases named). Questions: **5 + C + (G if G >= 2) +
dialogs for B** (+1 with a manual criterion).

Measured (fixture writes `reviewed: auto`, so C = 0; B = 0):

| Run | Questions | Agent launches | `temper go` stops |
|---|---|---|---|
| 2 groups, 1 task each (`full-run`), mod off | 7: Intent, Plan, G1, G2, Build, Review, Check | 6: intent, plan, acceptance, task 1, task 2, review | (same go.py; not traced) |
| the same, mod's driver | the same 7, same order | the same 6 | 16, no hand back, no model turn in the main session |
| 1 group, 2 independent tasks (`onegroup.ts`), driver | 5: Intent, Plan, Build, Review, Check | 6 | 13 |
| clean map but `reviewed: pending` (`pending.ts`) | +1: `Is this the right context for the plan?` | | |
| 2 Blocking questions at Intent (`blocking.ts`), driver | `Question 1`, `Question 2`, then the Intent question; the failed Intent question is not shown | | |

**Tier medium at risk H, tier complex at risk H, tier complex when Intent asked** (Design runs)

Steps 1 to 5 as above, then:

| Step | Who | Agent launch (model) | Question |
|---|---|---|---|
| 6 | person | | G5 `Approve the plan and continue to Design?` -> `Continue to Design (Recommended)` |
| 6a | CLI + agent | `temper brief`, Design (opus), `panel design`, `gate design` | |
| 6b | person | | Q1 `Design:` Blocking questions, when Design wrote any; then **G11** (the gate now fails, `Loop back to Plan (Recommended)`), see finding 5 |
| 6c | person | | G10 `Design: the check passed. Continue to Build?` |
| 7 to 16 | | as above; task agents on **sonnet** (`cli_ctx.py:72-73`) | as above |

Counts: launches **5 + T**; questions **6 + C + (G if G >= 2) + dialogs for B**, when Design asks nothing.
Measured (`design` scenario, medium raised to H, 2 groups, C = 0): 8 questions (Intent, Plan, Design, G1, G2,
Build, Review, Check); 7 launches (intent, plan opus, design opus, acceptance, 2 tasks on sonnet, review); 18
stops of `temper go` in driver mode.

**Trivial.** One launch (Intent, sonnet), which returns `TRIVIAL`. Mod off: no question; the session runs
`state clear` and makes the change itself (`commands/temper.md:176-179`). [doc of the model loop; not run]
Mod's driver: one wrong question, G1 (finding 7). [measured]

### 2c. "Mod on, the driver carries the run" against "mod off"

| | Mod off | Mod on, driver |
|---|---|---|
| Questions and their order | the same | the same (measured; `scripts/e2e/run.ts:28-31` asserts plain = mod) |
| Agent launches | the same | the same (measured) |
| Who runs the mechanical steps | the Sonnet session: one model turn at each stop of `temper go` (13 for 1 group, 16 for 2 groups, measured from the driver trace), each rereading the conversation (`go.py:3-5`) | the mod: no model turn (`driver.ts:1-6`, `330-459`) |
| Who words the question | the session copies it; nothing enforces it | the driver asks it as given; the mod counts an answer only on an exact match (`docs/flow.md:94-96`) |
| Hand back to the session | n/a | on a typed answer (`driver.ts:288`), any option with `do` (skills, HTML review, small change, group Change; `driver.ts:292-296`), a step that is not a CLI call such as the pull request steps (`driver.ts:440-441`, `stepPlan` `212-218`), a DRIFT row (`driver.ts:437`), a failed call |
| TRIVIAL | handled in prose | not handled (finding 7) |

---

## 3. Could a fixed rule answer each happy path question?

| Question | Is there anything to decide when the gate passed? | Config that removes it today | A fixed rule that could answer it |
|---|---|---|---|
| Q1 Blocking questions (Intent) | **Yes: a true decision.** These are the product rules only the person knows; the benchmark's one win for Temper is here. | none (`Carry forward` defers one at a time) | none that keeps the value; the first choice is only a guess. They can be asked in one dialog (already done). |
| G1 Intent gate | Only if the person reads `intent.md`. When B > 0 the person has just answered the questions; when B = 0 the request was specific. The recommended answer is constant. | none. An armed run never covers Intent (`flow.py:2441`), and arming happens later. | "gate PASS -> accept" (always, or when B = 0), with the intent shown in the Plan question so one approval covers both. |
| Q2 Context check | With no `ignore` or `gap` line: nothing. With one: a scope decision, but it is the same decision as approving the plan. | `plan.context-check: off` (`flow.py:2338`, `plan_ops.py:92`) | the documented `auto`: the CLI writes `reviewed: auto` for a clean map; otherwise put the left out lines into the Plan question. |
| G4 / G5 Plan gate | **Yes: the true decision of the run** (it commits the Build spend), and the place the run mode is chosen. | none | could be automatic for a low risk, simple plan under a policy key that does not exist today. |
| G10 Design gate | With open concerns that need a call: yes (they should be `Design:` questions). With "None flagged": nothing. | `phases.design: false` removes the whole stage (`flow.py:266`). No key passes the gate: an armed run parks on open concerns or changed tasks (`flow.py:2443-2453`) and otherwise goes on, but arming is offered only *at* this question. | "gate PASS, no open concern, tasks unchanged -> go on". |
| G11 Design gate after a Design answer | The CLI cannot tell whether the answer changed a rule (`decisions.py:8-12`), so it always fails. | none | "the answer is the first (recommended) choice -> the tasks already agree"; or ask such questions before Plan. |
| B1 group question | Nothing when the group's check passed (the Build question follows with `Change something`). | armed run (`flow.py:1759-1760`); a plan with one group (`flow.py:1763-1765`). No key of its own. | "group gate PASS -> continue" (the code already does it for one group and for armed runs). |
| G13 Build gate | Nothing when it passed. | armed run (`flow.py:2441-2463`) | "PASS -> Review". |
| G15 Review gate, no finding | Nothing. | armed + `autonomy.policy: decide` (`flow.py:2468-2472`, `1166-1172`) | "PASS and no finding at medium or above -> Check"; "finding at medium or above -> repair" (the policy's rule). |
| G18 Check gate | Whether to commit, and whether to open a pull request. With a grouped Build the code is already committed on the run's branch; what is left is the record commit (finding 9). | under the policy the Check gate passes by itself, then the run **always** parks at Commit (`flow.py:2227-2231`) and asks C1. | "PASS -> write the record commit on the run's branch"; the pull request choice could be a config key. This is the one the config calls a safety invariant (`templates/temper.config.default:138-141`), so it is the owner's call. |
| G19 manual confirmation | **Yes: only the person can look.** | none | none (and the policy handles it wrongly, finding 6). |

True decisions that only the person can make: **the Blocking questions, the plan approval, a manual
confirmation, open design concerns, and (by the project's own invariant) the final commit.** Everything else on
the happy path is a passed check with one recommended answer.

Config keys that change which questions appear (all the keys `flow.py` reads are: `autonomy.policy` :298,
`plan.context-check` :2338, `plan.fresh-review` / `-twice` / `-rounds` :248-249, `phases.design` :266,
`phases.pipeline` :233 and :2215, `feedback.enabled` :319, `review.block-on` :420, `loops.max-per-type` :994,
`build.grouped.max-groups` :1678, `build.grouped.max-parallel` :1692, `check.commands.test` / `.coverage` :1554,
`models.acceptance`, `models.plan-review`):

- `autonomy.enabled` is **not read** (`flow.py:300-303`), yet the config's header still says "With this block
  absent or enabled: false, the plan gate offers only the ordinary stage-by-stage continuation"
  (`templates/temper.config.default:133-136`) and the project's `CLAUDE.md` says the same. [code; docs disagree]
- `autonomy.budget.max-total-loops` and `max-stages` (`templates/temper.config.default:151-153`) have **no
  reader** in `scripts/` or `hooks/` (grep); `docs/flow.md:231` says a policy loop back happens "while
  `loops.max-per-type` and the autonomy budget last". Only `loops.max-per-type` (and `fix.max-loops`) is
  enforced (`loop_step.py:20-32`). [code; doc disagrees]
- `scripts/temper:3594` comments the fresh review as "medium and complex tiers by default"; the default is
  `ask` (`fresh_review.py:23`, config line 105). [code comment disagrees]

---

## 4. The minimum number of questions today, `/temper:temper "<feature>"` to the commit

Set every knob to ask least:

```yaml
plan:
  context-check: off      # removes Q2
  fresh-review: off       # removes the offer (it added no question, only an option)
phases:
  design: false           # removes G10 (and G11); otherwise the run is armed one question later, at Design
autonomy:
  policy: decide          # Review and Check decide by rule once the run is armed
```

and choose `Autonomous Build: run Build unattended` at the Plan question (the option that is not recommended).

Measured (`policy.ts`, plain and driver, 2 groups): **3 questions**, 6 agent launches, in this order:

1. `Intent: the check passed. Accept the intent and continue to Plan?` -> Continue to Plan.
2. `Plan: the check passed. Approve the plan and continue to Build?` -> Autonomous Build: run Build unattended.
3. `Commit: every gate passed, and the armed run parked here for you (its report: .temper/autonomy-report.md).
   Commit?` -> Commit.

Between 2 and 3 the trace shows `auto:build` (each group continued, Build advanced), `auto:review`,
`auto:check`, then `park --verdict SHIP-PENDING-COMMIT`.

Plus, not removable by any config: Intent's Blocking questions (0 for a fully specified request; up to 6 in
1 or 2 dialogs otherwise; the Intent gate forces a question for Who, When, How much or Exempt that the request
does not state, `gate_rows.py:78-84`). So the floor is **3 clicks, or 4 to 5 dialogs for a vague request.**

What still interrupts such a run (each parks it or asks, by design): a manual task (`flow.py:1890-1893`), an
environment fault at a task (`flow.py:1857-1870`), a failed group check that the policy cannot settle
(`flow.py:1963-1977`), a foreign commit (`flow.py:1795-1809`), a DRIFT row (`commands/temper.md:186-187`), open
design concerns or tasks Design changed (`flow.py:2443-2453`), a spent loop budget, a SETUP fault, a missing
measurement or a failed acceptance test at Check (`flow.py:1176-1179`), a required manual criterion (wrongly: a
loop back, finding 6), a commit gate row of an armed run (`autonomy.max-blast-radius` when there is no
`tasks.md`, `autonomy.park-on-touch` for a changed file outside the plan, `scripts/temper:4191-4222`).

For comparison, the same run with the default config and the recommended answers: 7 questions (2 groups) plus
the Context check.

---

## 5. Waste, judged against the goal

| # | What | Where | Cost | Size (basis) |
|---|---|---|---|---|
| W1 | A question after every passed gate, with a constant recommended answer | `flow.py:635, 730, 1943, 749, 784, 817` | questions; idle wall time while the run waits | 4 + G of the 5 + G gate questions (all but Plan); measured 7 -> 3 when rules answer them |
| W2 | The recommended Plan answer is the one with the most later questions | `flow.py:673` | questions | G + 3 later questions that `Autonomous Build` + policy would not ask (measured 7 against 3) |
| W3 | A dependent group waits for the person's Continue of the group before it | `flow.py:1683-1686, 1766` | time | human latency at each group boundary of an unarmed run; not measured |
| W4 | Context check on every run; `Carry forward` loops | `plan_ops.py:92-94`, `agents/plan.md:91`, `flow.py:2321` | questions, reliability | +1 question per default run (measured); an endless repeat on one option (measured 4 of 4) |
| W5 | The reason dialog after a recommended Loop back offers one preset reason | `flow.py:586-593` | questions | +1 dialog per loop back; the policy already fills the reason itself (`flow.py:1161`) |
| W6 | A Design answer forces `Loop back to Plan (Recommended)` | `decisions.py:60-69`, `flow.py:733-739` | loops, time, dollars | per run with a Design answer: Plan again (about 200 s on Opus, per the bench) and Design again (about 100 s), plus the Plan and Design questions again; or an override in 2 dialogs |
| W7 | A medium Review finding goes round through Build: fix pass, Build question, Review again, Review question | `flow.py:779-782`, fix pass `flow.py:1655-1672` | loops, questions | per repair round: 2 launches (fix pass, Review) and 3 dialogs (reason, Build, Review) |
| W8 | The policy loops back to Build for a manual criterion | `flow.py:1173-1180` against `824-836` | loops, dollars | 1 wasted fix pass on sonnet per such run, then a park (measured) |
| W9 | The driver cannot take the TRIVIAL exit | `driver.ts:422-434`, `scripts/temper:2038-2039` | reliability, dollars | a typo request is offered `Continue to Plan (Recommended)`, i.e. a Plan on Opus (measured) |
| W10 | With the mod off, one Sonnet turn per `temper go` stop | `commands/temper.md:4, 66-75`, `go.py:84-121` | tokens, time | 13 to 16 turns per clean run (measured stops), each rereading the conversation |
| W11 | The acceptance writer runs alone before any task starts | `flow.py:1641-1643, 1394-1420` | time | one serial launch per run (30 to 45 s per the bench); it needs only the accepted intent |
| W12 | The commit is three actions (report, page, record) and, with the mod off, two session turns | `flow.py:2232-2246` | time, tokens | 3 stops of `temper go` per run (measured) |
| W13 | Side features on every gate question: Grill Me, Teach Me, Architecture Depth Review, Open and Share HTML review, Walk through, Make a small change, Change something | `flow.py:632-637, 643-648, 704-705, 746-750, 769-770, 905-913` | concepts | 8 optional features a user meets in the happy path dialogs |
| W14 | Dead and misdescribed knobs: `autonomy.enabled`, `autonomy.budget.*`; three statements of the Design rule; `auto` for the Context check | `templates/temper.config.default:104, 112, 133-153`, `flow.py:300-303, 266` | concepts | 3 keys with no effect, 2 keys whose comment is wrong |
| W15 | The last question guards a docs only commit | `flow.py:2184-2198, 2227-2231` | questions | 1 question per run, armed runs included |
| W16 | Stale prose: the HTML report question; `blocking` then `ask.question` | `commands/temper.md:104, 108-110` against `163-169` | reliability (mod off) | the bench records the driver once asking the stale failed question for the same reason (`docs/evidence/bench-2026-11.md:361-362`) |
| W17 | The Review question with a medium finding loses four options (PR #115 regression) | `flow.py:925-930, 943-947` | reliability | the person cannot accept a finding or save the run from that question (measured on pr115; fine on origin/main) |

---

## 6. What I would change here (most valuable first)

1. **One approval, then run to the end.** Make the Plan question's first, recommended option "Approve and
   run" (today's arm + policy), and make "ask me at every stage" the other option. After it the run asks only
   when a check fails or a true decision appears. Removes G + 3 questions per clean run (7 -> 3 measured) and
   the idle time between groups. Code: `flow.py:672-680, 1144-1181, 2441-2472`.
2. **Fold the Intent acceptance and the Context check into the two real dialogs.** Accept the intent by rule
   when its gate passes (the person has just answered the Blocking questions, or there were none) and show the
   intent's summary and the map's `ignore` / `gap` lines inside the Plan question. With 1, a clean run is: Intent's
   questions (if any), one plan approval, the commit. Code: `flow.py:633-637, 2331-2346`, `plan_ops.py:81-101`.
3. **Stop the Design -> Plan loop.** Do not fail the Design gate on an answer that is the recommended (first)
   choice; send every decision to the builders (already done, `flow.py:1432-1434`); loop back only when the
   person picks another choice, and then patch the tasks instead of a full replan where one line changes.
4. **Repair the policy before making it the default.** A manual criterion asks its one click instead of
   looping (`flow.py:1173-1180`); a Review repair goes fix pass -> Review of the changed files without the Build
   question in between; the recommended Loop back fills its own reason (`flow.py:586-593`); the Review question
   with a medium finding gets its More options back (`flow.py:925-947`, finding 10).
5. **Give TRIVIAL to the CLI.** The Intent agent records the verdict with a CLI call, and `temper next`
   answers with an action that ends the run, so the driver and the model loop behave the same.
6. **Make the record commit by rule** (on the run's branch, never a push), or state plainly why it stays a
   question. This touches the invariant in `templates/temper.config.default:138-141`: the owner decides.
7. **Delete what does nothing**: `autonomy.enabled`, `autonomy.budget.*`, the `Carry forward` option of the
   Context check, the stale lines of `commands/temper.md`; write the Design rule once.

---

## 7. Invariants a redesign must keep (with source)

- The person decides only by choosing an option of a question; a typed message is never a move; no button in
  the mod decides (`docs/flow.md:94-96`, `commands/temper.md:143-144`, project `CLAUDE.md` "Known mistakes").
- What comes next, a gate's options and the Build loop live in `scripts/flow.py` with a case in
  `temper-cases-8.sh`; gate verdicts are computed by `scripts/temper`, never asserted by a prompt; view changes
  need `make-view-fixtures.sh` (project `CLAUDE.md`).
- `next` and `view.json` are version 1: a field may be added, never renamed or removed without a new version
  (`docs/flow.md:21-23`, `flow.py:37`).
- A question holds four options at most (`flow.py:493-498`, `docs/flow.md:92`).
- The mod counts an answer only when header, question and label match what the CLI wrote for that run and step
  (`docs/flow.md:94-96`), so any new wording or auto answer must come from the CLI.
- Every option's `move` is in `MOVES` (`flow.py:56-59, 459-461`).
- `temper go` never runs an option's calls (`go.py:17-19`).
- An unattended run never pushes, never merges to a remote, never replans, never overrides or accepts for the
  person (`templates/temper.config.default:138-141`, `flow.py:1144-1148`, `docs/flow.md:231`); only the person
  writes `autonomy.policy` (`docs/flow.md:226`).
- Answers to Blocking questions are written by the CLI (`temper intent answer`), never by editing `intent.md`
  (`commands/temper.md:168-169`, `answer_ops.py:9-12`).
- A stage command is a door into `/temper`, with no flow of its own; no stage logic in `commands/temper.md`
  (project `CLAUDE.md`).
- `flow.py` uses the standard library only (`flow.py:12`); `scripts/temper` stays under 256 KiB
  (`gate_rows.py:9`).

## 8. What I could not determine

- How often a real Plan agent writes `reviewed: pending` (as briefed) and how often `reviewed: auto`; the e2e
  fixture writes `auto` (`scripts/e2e/project.ts:4`). That decides whether the Context check is in every real
  run. I measured only the briefed case.
- How many Blocking questions real runs carry on average (the cap is six), and how the "about 30 questions" of
  the bad complex run split by kind.
- Whether the owner counts the final commit question as a decision to keep (it is written as an invariant).
- Claude Code's own permission prompts, which are outside `flow.py`.
- Wall time lost to waiting at group questions (W3): no measurement exists.
