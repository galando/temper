# Verification: WP4, a lean front (draft items 4a to 4f)

Checked at the head of PR #115 (`10e965a`). Paths are relative to `/home/user/temper`; every line number is of the head,
read there. Nothing was written or run in that folder. Two experiments ran in a clone
(`.../scratchpad/work-v-lean-front/repo`, throwaway project `.../work-v-lean-front/exp`), and I read strings of the
installed host binary (`/opt/claude-code/bin/claude`, Claude Code 2.1.325) for the mod API.

Marks: **[code]** read at the line. **[ran]** run in the clone. **[host]** read from the installed host binary.
**[doc]** a figure from a repository document. **[est]** my estimate.

**Verdict: feasible with changes.** 4a, 4b and 4d are sound and mostly prose plus small script edits. 4c's effort part
does less than the draft says. 4e works at the state machine level today (measured) but is held by three checks and
buys little beyond auto accepting a clean intent. 4f is possible but costs the first builders their view of the
acceptance tests and collides with 5a.

---

## 1. Who reads each section, and the smallest contract

### 1.1 intent.md (written by Intent; the Scenarios by Plan)

| Section | Gate row | Read later by | Keep? |
|---|---|---|---|
| Status, Author, Created | `status header` `scripts/temper:2077-2083`; `header fields` `scripts/intent_draft_rows.py:156-167` | every status reader (`intent_parse.status`) | keep |
| Ticket | cross checked by `task context recorded` `intent_draft_rows.py:58-65` | none | keep (one line) |
| Complexity | `tier recorded` `scripts/temper:3569-3578` | the doors `scripts/temper:766, 957` | keep; the CLI writes it |
| Reviewer | none (optional since 9.8.0, `intent_draft_rows.py:158-160`) | none | drop from the template |
| Problem | `problem stated` `scripts/temper:2044-2059` | Plan panel, first sentence `scripts/panel.py:130` | keep |
| Success Criteria (`AC-NN`, priority, `Validate:`) | `success criteria`, `criteria ids`, `criteria priority`, `criteria validate` `intent_draft_rows.py:77-105`; plan gate `criteria -> validation` `scripts/temper:3515-3523` | Build gate, Check, the acceptance writer `agents/acceptance.md:15` | keep |
| `Why:` under each criterion | `criteria why` `intent_draft_rows.py:107-110` | none (`acceptance.py:388-389` skips it) | keep: about 20 tokens a criterion, and it shapes the criterion |
| Constraints | `no soft words` `intent_draft_rows.py:175-223` | the acceptance writer `agents/acceptance.md:15-16` | keep |
| Scope and Non-goals | `out of scope stated` `scripts/intent_closure_rows.py:27-40` | the acceptance writer | keep |
| Business Outcome | none | none | **cut** |
| Target Users | `target users action chain` `intent_draft_rows.py:112-118`; it already passes with no bullet | none | **cut**, with its row and the brief's "mandatory probe" `agents/intent.md:67-68, 89-91` |
| Open Questions | `open questions labeled`, `no duplicate question` `intent_draft_rows.py:120-154`; `blocking question open` `scripts/gate_rows.py:27-41` | the dialogs `scripts/flow.py:371-373, 2488-2505` | keep |
| Assumptions | none | the person, in Intent's panel `agents/intent.md:182-183` | keep; it must show in the one approval |
| Rules covered | `rules checklist covered` `gate_rows.py:53-90` | none after the gate | keep: seven short lines that force the one measured gain (the questions) |
| `**States:**` | the lock refuses tests that name no listed state `scripts/check_run.py:495-508` | the acceptance writer `agents/acceptance.md:27-30` | keep |
| Decisions | `no duplicate question`; plan gate `request routes kept` `gate_rows.py:309` | acceptance writer; Build task prompts for `Design:` rows `scripts/decisions.py:93-105`, `flow.py:1432-1434` | keep |
| Scenarios: `Scenario:`, `Covers:`, `Test:` | `criteria -> scenarios`, `criteria -> validation`, `scenarios in gherkin blocks` `scripts/temper:3507-3546`; `scenario test commands` `gate_rows.py:105-133`; preflight | `acceptance.scenario_blocks` reads only these three `scripts/acceptance.py:91-112`; task show `scripts/task_ops.py:385-389`; integrate `scripts/scenario_ops.py:133-155`; panel `panel.py:96-107` | keep |
| Scenarios: Given/When/Then, `Note:` | none | no script. Three briefs: Review step 3c judges tests against the Then clause `reference/review.md:149-153`; the Check agent `agents/check.md:42-44`, `reference/check.md:64`; Build's fix pass `reference/build.md:39-41` | **cut to one `Then` line** (see 1.5) |
| The line `- Blocking: Context check: ...` Plan adds | none | filtered out `flow.py:371-373`; its parser `context_choices` has no caller `flow.py:392-396` [ran: grep] | **cut** (`agents/plan.md:91-92`) |
| Scenario Coverage Checklist | none | no reader; one writer instruction `reference/build.md:91` | **cut** |
| Source Traceability | `task context recorded` `intent_draft_rows.py:52-74` | Plan fetches each source again `agents/plan.md:24-29` | keep |
| Intent's hand drawn 76 column panel | none | the person | **cut**: the CLI draws it, as for Plan and Design (`scripts/panel.py:8-10`) |

### 1.2 tasks.md

Everything is read except one field. `**Integration:**`, group `Depends`, `Validate`, `Interfaces`, `Context`, task
`File`, `Depends`, `Test`, `Cases`, the done box: parsed by `scripts/tasks_md.py:24`, checked by the 14 rows of
`scripts/plan_rows.py:21-195`, and the task block and group Context are all a builder gets
(`scripts/task_ops.py:382-394`).

`**Traced to:**` has one reader, `scenario_ops.traced` (`scripts/scenario_ops.py:30-36`). The agents-plan-side report
says the owner can be computed from the `Test:` file and the `**File:**` lines. **Not as the code stands:** the file
rule only adds owners for a scenario some task already traces (`if b["name"] in tracing`, `scenario_ops.py:85-90`). A
scenario with no `Traced to:` is owed by no task and no group and first runs at `integrate` (`:141`). Cutting the field
needs that loop to seed `tracing` from the files (about three lines). `Traced to: Infrastructure: ...` has no reader.

### 1.3 plan.md

| Section | Gate row | Read by | Keep? |
|---|---|---|---|
| Context Map | `context map reviewed` `scripts/plan_ops.py:81-101` (only when plan.md exists, `gate_rows.py:331-332`) | the Context check `flow.py:2289-2344` | keep only `ignore:` and `gap:` lines; the row must pass with no map (today it fails: `plan_ops.py:84-87`) |
| Architecture | none | Design, the fresh reviewer, the acceptance writer for names `agents/acceptance.md:16-17` | **cut**; names come from `**Interfaces:**` and `**File:**` |
| Approach Decisions | none | panel headings `panel.py:120-121` | keep, optional as today |
| Diagram, mermaid and ASCII | none | panel prints the `text` block `panel.py:144-158`; mermaid: none | **cut both** below complex; ASCII only at complex |
| Blast Radius | `blast radius documented`, a heading grep, medium and complex `scripts/temper:3560-3568` | `risk.py` looks for `[CROSS-REPO]` `scripts/risk.py:59-65`; Build's fix pass `reference/build.md:12-13` | keep only impact outside the declared files; **drop the row** |
| Files to Create, Files to Modify | none | `flow.plan_files` unions them with the `**File:**` lines `flow.py:2538-2559`; `drift.py:60`; the panel counts from tasks.md and the disk `panel.py:108-112` | **cut** |
| Cross-Repo Search | `cross-repo search recorded`, every tier `scripts/temper:3548-3559, 2126-2151` | panel SEARCH field, which already prints `local` when the section is absent `panel.py:118-119` | **cut, with its row**; a line only when a tool was used |
| Patterns to Follow, Dependencies, Risk Level | none | none (`temper risk` computes the risk) | **cut** |
| `## Deviations` (written at the commit) | none | `spec deviations` `flow.py:2143`, `scripts/spec_ops.py:75-100` | see below |

**At tier simple plan.md is already not needed by any gate.** [ran] In the clone, a spec folder with intent.md and
tasks.md only: `gate plan` printed PASS with 25 rows, and `next` asked "Approve the plan and continue to Build?" with no
Context check. The brief still tells Plan to write three files at simple (`reference/plan.md:38-39`,
`agents/plan.md:86`). Three things break without the file and must change with the cut:

1. `temper spec deviations` exits 1 with "no plan.md" when a deviation is recorded (`spec_ops.py:89-94`).
2. A later door finds the run's folder as "the folder that holds plan.md and tasks.md" (`commands/temper.md:199-203`).
3. Briefs name it: the acceptance writer (`agents/acceptance.md:16`), the fresh reviewer (`agents/plan-review.md:24`).

### 1.4 design.md

One section has a reader. Areas of Concern: the gate's heading grep (`scripts/temper:3729`), the Design question
(`flow.py:707-718`), the panel (`panel.py:176-198`), `resolved:` lines (`scripts/answer_ops.py:99-149`). Decision Log
and the counts of API Contracts and Database Changes go to the panel only. System Architecture, Integration Points,
Security and Performance Considerations: no reader. No brief or page of Build, Build task, Review, Check, the
acceptance writer, Fix or the fresh reviewer contains the word "design" [ran: grep, empty].

### 1.5 The smallest contract

- **Intent** writes: header (Status, Author, Created, Ticket, Complexity), Problem, Success Criteria with `Why:` and
  `Validate:`, Constraints, Scope, Open Questions, Assumptions, Rules covered, `**States:**`, Decisions, Context
  Sources. No panel.
- **Plan** writes: in intent.md, per scenario a fenced block of `Scenario:`, one `Then` line, `Covers:`, `Test:`;
  tasks.md as today without `Traced to:`; plan.md only at medium and complex, holding `ignore:` and `gap:` lines,
  real Approach Decisions, and blast radius outside the declared files.
- **Rows that go:** `cross-repo search recorded`, `blast radius documented` (plan); `target users action chain`
  (intent). **Row that is relaxed:** `context map reviewed` passes with no map. **Row worth a second look:**
  `criteria -> scenarios` (`scripts/temper:3507-3514`) demands one scenario per criterion whatever its Validate type,
  so three `manual` criteria force three scenarios; `criteria -> validation` already checks the real link
  (`acceptance.py:392-394`).
- **Not a row but must change:** `scenario_ops.owners`, `spec deviations`, the door's folder rule, Review step 3c
  (judge against the `Then` line and the task's Cases).

### 1.6 Output tokens saved

The only real Plan output in git is `eaba313:.temper/specs/mods-support/` (v9.6.0, complex: 16 criteria, 32 scenarios,
23 tasks). I measured it again [ran]: plan.md 22,634 B, scenarios 14,538 B of which step lines 10,423 B, tasks.md
16,407 B of which `Traced to:` 3,635 B. Plan's files: 53,579 B.

| Cut | Bytes | Share of Plan's file bytes |
|---|---|---|
| plan.md: Architecture 4,499; Diagram 1,260; Cross-Repo 406; the file tables 8,285; Patterns 587; Dependencies 426; Risk Level 437 | 15,900 | 30% |
| Step lines, keeping one `Then` line (about 90 B each) | about 7,500 (10,423 with none kept) | 14% (19%) |
| `Traced to:` | 3,635 | 7% |
| **Total** | **27,000 to 30,000** | **50% to 56%** |

That is about 6,800 to 7,500 tokens (bytes divided by 4). A Plan launch emits about 25,000 output tokens
(`docs/evidence/bench-2026-11.md:457-458`; median 24,617, `docs/evidence/opus5-plan-prompt-ab.md:18`), so the cut is
**about a quarter to 30% of the launch's output, about $0.14 to $0.15 a pass** at $20 per million
(`bench/loop.py:34-38`), against $0.75 to $1.13 a pass. Seconds: not determined; if the whole 143 to 246 s were output
it would be at most 40 to 70 s, and the prompt A/B found wall time "dominated by the model exploring the repo"
(`opus5-plan-prompt-ab.md:42-45`).

What the estimate rests on, and where it is weak: one spec, one tier, a format that predates Cases, group Context, the
Context Map and the second diagram (the first two are kept and grow tasks.md's share; the last two are cut). The 25,000
figure and the sample are different runs. Thinking tokens bill as output and are untouched by a contract cut. At
simple tier the whole of plan.md goes (42% on the sample). The scorecard of WP1 has to split output tokens by file
before this number is used as a pass line.

---

## 2. Folding Design into Plan

**When it runs today:** `phases.design` on and (risk H at medium or complex, or complex when Intent asked something),
or a design.md exists, or the run is at Design (`flow.py:251-266`). Not in the reference medium run.

**What the gate checks:** two rows (`scripts/temper:3718-3739`): `concerns flagged` (the heading exists) and `tasks
agree with decisions` (`scripts/decisions.py:60-69`: tasks.md must change after any `Design:` answer).

**What already exists for the fold.** Plan may write Blocking questions (`reference/plan.md:265-268`), and the flow
asks every open Blocking question before any gate question (`flow.py:2478-2481`). On an accepted intent the row
`blocking question open` passes (`gate_rows.py:35-36`), so a Plan question fails no gate. The gap: only an answer
whose question starts with `Design:` is recorded against tasks.md (`decisions.py:42`), and only `Design:` rows reach a
builder's prompt (`decisions.py:94`). A Plan question answered against the plan's assumption is written to Decisions
and nothing else happens.

**What moves into Plan's contract:** the concern rule (`reference/design.md:29-42`): a policy conflict or product call
becomes `- Blocking: {question} choices: {the answer the plan assumes} | ...`, and the plan is written under the first
choice; the trigger list of `agents/plan.md:129` (data model, money, permissions, external system) says when to look.
ADR writing for projects that keep ADRs (`reference/design.md:83-99`); the mod already lets Plan write
`docs/decisions/*.md` (`hooks/temper-mod/core/rules.ts:268`).

**The smallest change:** `has_design()` returns true only for an existing design.md, a run at Design, or an explicit
ask (`flow.py:266`); `decisions.record` keeps any Blocking answer given after tasks.md exists and whether it was the
first choice; the row `tasks agree with decisions` moves to the plan gate and fails only for an answer that was not the
first choice; its way on is a revise pass (section 4), not a full Plan.

**Lost at risk H:** a second Opus reading of intent, plan, packs and stack pack; the API contract and schema text
(nobody reads it, but writing it may surface a concern); the pack `architecture-depth`, whose rules are read at
`[design, review]` only (`packs/architecture-depth/rules.md:2`; not a default pack, `templates/temper.config.default:16`)
and would have no reader before Build unless `plan` is added; the Design panel and walkthrough. Evidence that Design
changed an outcome: none; the code's own comment says "concerns the person only approved" (`flow.py:258-262`).

**Saved:** nothing on the reference run. When Design runs: 88 to 116 s, $0.48 to $0.61, one dialog (`bench-2026-11.md:354-357`), and the PR's Design to Plan loop cannot occur.

---

## 3. Models and effort

**Where a launch gets its model.** `models.<stage>` in the config, else the `model:` line of the brief
(`scripts/cli_ctx.py:57-68`), for the nine names of `AGENT_STAGES` (`:21`). The fresh reviewer and the acceptance
writer read `models.plan-review` and `models.acceptance` the same way (`flow.py:1284-1287, 1411-1414`). The env agent
is `sonnet` and cannot be set (`flow.py:1222`). Build tasks: `build.grouped.task-model`, else `sonnet` for a complex or
risk H plan, else the brief (`cli_ctx.py:69-76`). The action carries the model (`flow.py:1135`); the driver passes it to
`$.agent.spawn` (`hooks/temper-mod/register.tsx:505`); a session launch is checked by model family
(`hooks/temper-mod/core/session.ts:185-201`).

**Effort.** No launch carries one: no `effort` in `flow.py`, `cli_ctx.py`, `go.py` or `core/driver.ts` [ran: grep].
Three briefs set it in frontmatter: review high, rca high, pipeline medium (`agents/review.md:5`, `agents/rca.md:5`,
`agents/pipeline.md:5`). Plan and Design have none.

- **By frontmatter:** works with and without the driver, today. One level per agent type.
- **By the CLI per launch:** the CLI can add a field to the agent it names (`flow.py:1135`), but neither consumer uses
  it. A session's Agent tool takes `effort` from host 2.1.292 [doc: platform.md:8]; the mod loads from 2.1.287
  (`scripts/check-mod-calls.sh:34`), and its launch check ignores the field (`session.ts:193-205`).
- **By the driver per launch:** not through spawn. [host] In 2.1.325 `$.agent.spawn` forwards prompt, description,
  model, subagent type, name and cwd to the Agent tool, nothing else. The mod's `turn.step` hook can set model and
  effort on a subagent's steps (`register.tsx:941-944`); today it sets a model for the two reviewers only (`:678-680`).
- **`phaseModels` does not reach a stage agent.** It applies when the step has no agent id, the main loop
  (`register.tsx:677-687`). The cross check's gap 1 reads as if it could set an effort per stage agent; it cannot.
- **What pinning buys.** A subagent on another model than the session runs at that model's own default, and both
  host documents give Opus 5.5 `medium` [doc: platform.md:10, 98]. So `effort: medium` on the two Opus briefs changes
  nothing unless the person's session is on Opus at a higher level. A saving needs `low`, which nothing has measured.

**Prices** [doc: platform.md:83-90; `bench/loop.py:34-38`]: Opus 5.5 $4 in, $20 out; Sonnet 5.5 $2, $10; Haiku 5.5
$0.10, $0.50. Plan on Sonnet at equal tokens is half: at most $0.37 to $0.56 saved a pass.

**What the A/B must measure before a default changes.** Needs no code (`models.plan: sonnet`).

1. Run it on the cut contract (after 4a and 4b), or its answer is about a contract that no longer exists.
2. Plan quality where it shows: plan gate rows failed at first return; preflight classes; Build task retries,
   escalations and `task blocked`; group check failures; loops from Build to Plan; hidden tests; Review findings at
   high and medium. One fresh reviewer on every plan as a measuring device (count of high readiness findings).
3. Per Plan launch: dollars, seconds, output tokens with thinking apart if the logs give it.
4. At least one complex or risk H task and one vague task, since the default is to be set by tier and risk.
5. A rule fixed before the run. Three runs a cell show only large effects: the Haiku against Sonnet test could not
   separate $0.25 from a spread of $1.99 to $3.19 (`docs/evidence/haiku-sonnet-task-agents.md:88-89`).
6. Effort is a second factor: Opus at `low` is one more arm (about $25 more).

---

## 4. A revise mode

**Where a revision is launched today.** Every one ends in `stage_work("plan")` (`flow.py:1316-1385`): the same agent
type, the same model, the whole brief, `reference/plan.md` (27,927 B) and the project brief again.

| Trigger | Call | What the prompt adds |
|---|---|---|
| "Revise the plan" after a fresh review | `state redo plan` `flow.py:666-669, 1056-1059` | `Fresh review findings to answer`, each cut at 200 characters `:1331-1334` |
| Context check: "Include what is left out", "Something else" | `plan review --answer ... --redo` `flow.py:2317-2327`; `scripts/temper:4560-4592` | `Person's note:` `flow.py:1133` |
| A change typed at the Plan question | a note, then `state redo plan` `commands/temper.md:156-160`; `flow.py:2400-2410` | `Person's note:` |
| Loop back from Design or Build | `state loop <stage> plan` (`BACK_TO`, `flow.py:54`; recommended at `:733-739`) | `Loop back from`, `What ... left open` `:1349-1354` |
| Loop back to Intent, passing Plan again | | `Earlier loop back from` `:1340-1348` |

`state redo` clears the verdict and stores the reason (`scripts/temper:1455-1492`). A precedent for changing the plan
with no agent exists: `plan patch G --cmd` (`flow.py:2027`).

**What a revise prompt would carry:** each finding or the note in full; the numbers of the affected tasks (a fresh
finding names `Task N`, `agents/plan-review.md:77`; the recheck already computes the changed blocks,
`flow.py:1294-1302`); the order to change only those blocks and the scenarios they own, then run `gate plan`. A short
brief of its own (the grouped format, the budgets, the row names) in place of the two plan pages; no `temper brief`
call. Model: `sonnet` by its own key, read as `models.plan-review` is. A full Plan stays for a loop back to Intent
(the criteria changed) and when the person asks for it.

**Continuing the same agent.**

- The host can: SendMessage resumes a finished subagent with its history [doc: platform.md:21]. It is a tool of a
  model's session.
- The driver cannot through spawn: [host] no resume field (above). The mod's reviewed call list has no other agent
  call (`scripts/check-mod-calls.sh:25-45`).
- [host] The mod API has `$.tool.call({ tool, ...args })`, and `$.agent.spawn` is itself built as an Agent tool call.
  Whether `$.tool.call` with SendMessage resumes a subagent with no model turn: **not determined**. Hooks modules are
  switched off in this container (the load printed "hooks modules are turned off for installed plugins in this
  process"), so I could not try it.
- What the verifier would need: a rule for SendMessage in `evaluateSession`, which today judges only `Agent` and
  `Task` and lets any other tool pass (`session.ts:83, 273-282`); the agent's id kept across a reload of the module
  (the driver holds ids in memory only, `register.tsx:40, 503-507`); the CLI naming a "continue" action with its exact
  message in view.json; `tool.call` added to the reviewed list.
- **It may not be cheaper.** A resumed agent reads its cache only within the subagent's 5 minute lifetime
  [doc: platform.md:12, 22]. After a person's answer that is usually gone, and the whole history is paid again at
  full input price: 100,000 tokens on Opus is $0.40 before a word is written. A fresh revise agent with a narrow
  prompt has no such cost. Continuation pays only when the answer comes within the lifetime, or the brief sets a one
  hour lifetime.

Recommendation: build the fresh revise agent; treat continuation as a later test, not as the design.

---

## 5. One front launch

**Tier simple today:** the same path as medium. Intent (Sonnet), the Intent question, Plan on Opus told to write three
files (`reference/plan.md:38-39`), the Context check because plan.md exists, the plan question, the acceptance writer.
The tier changes only Design, the blast radius row, the fresh review under `auto`, and the task model.

**[ran] What the state machine already allows.** In the clone, with the run at stage intent:

1. A draft intent that holds scenarios fails the intent gate on exactly one row, `no scenarios in draft`
   (`intent_draft_rows.py:169-173`).
2. `gate plan` runs at stage intent and records PASS (25 rows, no plan.md): a gate has no stage rule.
3. `intent accept` has no precondition: it accepted the draft while its gate was FAIL, and wrote
   `Accepted-by: the person at the Intent gate`. After it the draft rows skip and the intent gate passes.
4. After `state advance intent_complete plan`, `next` asked "Plan: the check passed. Approve the plan and continue to
   Build?" at once. No Plan agent, no Context check. The plan verdict recorded at Intent survives the advance, and
   the branch switch waits for `leave_plan` (`flow.py:567-571`).

**What holds one launch back:**

1. The row `no scenarios in draft`. Its stated reason is placeholders (`agents/intent.md:72-76`); it can pass when
   every scenario has a `Test:` line.
2. The mod's write rule: at stage intent only intent.md and `intent-context.json` may be written
   (`hooks/temper-mod/core/rules.ts:255-262`). It applies to an agent's writes too (`register.tsx:433-445`).
3. A passed intent gate always asks (`flow.py:633-637`); an armed run never covers Intent (`:2441`). An `auto` move
   is possible: `temper go` runs an auto action's calls inside the CLI (`scripts/go.py:7, 95-97`), so the mod's
   person only rule on `state advance intent_complete` (`rules.ts:491`) is not met. It changes ADR 0013 and
   `docs/trust.md`.
4. The launch: the type is `temper:temper-intent` on Sonnet with no project brief (`flow.py:1123-1135, 1384`). A front
   agent that plans runs on Plan's model, so on Opus the intent part costs Opus; or the Sonnet Intent agent goes on
   to plan, which is Plan on Sonnet. **4e therefore depends on the A/B of 4c.**
5. The wording `intent accept` writes, and the branch clash question, which is asked only at the Intent question
   (`flow.py:622-632`).

**How questions return.** As today: the agent writes `- Blocking:` lines and returns; the gate fails on
`blocking question open`; `next` gives `blocking_asks`, four to a dialog (`flow.py:2478-2505`); answers go to
Decisions by `temper intent answer`. A subagent cannot ask [doc: platform.md:31]. So with questions the run still has
two front launches: the intent, then the plan (a new agent, or the same one continued if section 4 allows).

**What it buys.** Over "auto accept a clean intent" (draft 2c) one launch saves an agent start, a second reading of
intent.md and a second fetch of the sources (`agents/plan.md:24-29`): not measured, by my estimate under 30 s and a
few cents. The two cheaper steps give most of it: the auto accept, and one line that gives Plan the `Feature:` text
(`flow.py:1126`; the mod checks the CLI's own prompt, so no mod change).

---

## 6. The acceptance writer

**What it needs:** stage build (the mod denies `{spec}/acceptance/` at Plan, `rules.ts:263-269`, and allows the spec
folder at Build, `:293`); an intent that no longer changes; names of entry points (plan.md today, tasks.md after the
cut); the project's tests. The flow launches it alone, before any group (`flow.py:1394-1420, 1641-1643`), at most twice
(`check_run.py:625`). The lock itself has no rule about Build (`check_run.py:486-538`); the order is the flow's.
The changelog records why it is not earlier: beside Design it "would miss what Design decided" (`CHANGELOG.md:600-601`).
With Design folded and its questions asked before the approval, that reason is gone from the approval on.

**Beside the first builder: possible.** Attach it to the first batch of task agents (`flow.py:1698-1723`) and lift
"no group started" (`:1402`). What changes:

1. The first builders lose the prompt line that points at the locked tests (`acceptance_line`, `flow.py:1436-1441`,
   printed only once a lock exists). Today every builder is told to read them; then they first meet that code at
   Check (or at integrate under 3d). How much the line prevents: not determined.
2. It collides with 5a's "on the run's branch for a one chain plan": the writer runs its tests once in the project
   folder and expects them to fail (`agents/acceptance.md:35-36`); with a builder writing in that folder the tests are
   no longer written before the code.
3. `integrate` must wait for the lock or the skip.
4. The row and ledger name "acceptance tests written before Build" (`scripts/temper:3932-3942`,
   `check_run.py:662-673`, `flow.py:1178, 1263, 1450`) stops being true to the letter.
5. The brief needs one line: never read `.claude/worktrees/`.

**Later than that** (after a group merges, or after Build) breaks its purpose: it reads "the code the tests call", so
tests could follow the code, and its own first run would pass.

**Saved:** 30 to 45 s of serial time on the bench (`bench-2026-11.md:457-459`), 8 minutes on the one Java run; no dollars.

---

## 7. Mechanism, in order

1. **4a, prose:** `agents/plan.md`, `reference/plan.md`, `templates/plan.md`, `templates/intent.md`,
   `templates/tasks.md`, `agents/intent.md` to the contract of 1.5; `reference/review.md:149-153`,
   `reference/build.md:39-41, 91`, `agents/check.md:42-44`, `agents/acceptance.md:16-17`,
   `agents/plan-review.md:24`, `commands/temper.md:199-203`.
2. **4a, scripts:** delete the two rows in `gate_plan` (`scripts/temper:3548-3568`) and `_cross_repo_recorded`
   (`:2126-2151`); `plan_ops.gate_row` passes with no map (`:84-87`); `scenario_ops.owners` seeds from the `Test:`
   file (`:85-90`); `spec_ops.py:89-94` writes Deviations without a plan.md; delete `target users action chain`
   (`intent_draft_rows.py:28, 112-118`) and `context_choices` (`flow.py:392-396`); a `panel intent` in `panel.py`.
3. **4b:** `flow.py:266`; `decisions.py:42, 53-69, 94`; `answer_ops.py:147`; the row into `gate_plan`; the plan
   question's option for a failed row; `packs/architecture-depth/rules.md:2`; `templates/temper.config.default:112`.
4. **4d:** new `agents/plan-revise.md`; `.claude-plugin/plugin.json:38-52`; `stage_work` picks it (`flow.py:1316-1385`).
5. **4c:** the A/B on the result of 1 to 4; then one `model:` or `effort:` line per brief. Per tier only if the A/B
   says so: a field at `flow.py:1135`, `phasePick` (`register.tsx:677-687`), `agentWhy` (`session.ts:193-205`).
6. **4e, first half:** `Feature:` for Plan (`flow.py:1126`); the auto accept (`flow.py:633-637, 2441`); the wording
   in `cmd_intent` (`scripts/temper:4431-4433, 4496`).
7. **4e, second half, only if 5 puts Plan and Intent on one model:** `intent_draft_rows.py:169-173`;
   `rules.ts:255-262`; the Intent brief's last step; `after` calls `panel plan`, `gate plan`.
8. **4f, last and only if 5a keeps worktrees:** `flow.py:1394-1420, 1641-1643, 1698-1723`.

## 8. Tests

- Selftest: `temper-cases-2.sh` (cross-repo row, `no scenarios in draft`), `-14.sh` (blast radius row,
  `state redo plan`), `-11.sh` (context map), `-1.sh` (`criteria -> scenarios`), `-25.sh` (`tasks agree with
  decisions`), `-16.sh` and `case-helpers.sh` (`Traced to`), `-8.sh` (flow: Design, the new auto move, the revise
  agent), `-15.sh` and `-18.sh` (acceptance), `-20.sh` (redo); `make-view-fixtures.sh` and `view-fixtures.ts`.
- e2e: `scripts/e2e/project.ts` (fixture plan with no file tables, no `Traced to`), `scenarios.ts` (Design scenarios,
  a clean front run with one launch, a revise round, the writer beside a builder), `pyjokes.ts`, `replay.ts`.
- Mod: the write rule at Intent and the launch check in `tests/mod` (`session.test.ts`, `run-files.ts`); a test that
  an effort the CLI names cannot be dropped.
- A new case each: an untraced scenario is owed by the task that writes its test file; a run with no plan.md records
  a deviation and reaches the commit; a door finds a folder with tasks.md only.

## 9. Docs and decisions

ADR 0013 and `docs/trust.md` (a clean intent accepted with the plan approval); a new ADR for the folded Design and
the plan contract; ADR 0017 where it leans on the tests lens and plan.md; `reference/plan.md`, `reference/design.md`
(both already wrong on when Design runs: `reference/plan.md:40-41`, `reference/design.md:7-8, 103-105`),
`reference/review.md`, `reference/build.md`, `reference/check.md`; `templates/temper.config.default:104, 112`;
`docs/commands.md`, `commands/design.md`, `commands/temper.md`; `.claude/CLAUDE.md`; `CHANGELOG.md`; a new evidence
page for the A/B.

## 10. Corrections to the draft

1. **Row B and 4a, "19% Given/When/Then lines nothing reads".** No script reads them. Review step 3c, the Check
   agent and Build's fix pass are told to (`reference/review.md:149-153`, `agents/check.md:42-44`,
   `reference/build.md:39-41`). Keep one `Then` line or change those three pages.
2. **4a, "40% to 60% fewer output bytes".** True of the bytes Plan writes into files on one old sample (50% to 56%).
   It is about a quarter to 30% of the launch's output tokens and about $0.14 a pass. Say which.
3. **4a, "drop the format rows that check unread sections".** Two plan rows qualify, and one intent row; one more is
   relaxed. The larger part of the work is four readers that are not rows (1.5).
4. **4a leans on "Traced to can be computed".** Not without a change to `scenario_ops.owners`.
5. **4b** should say the plan is written under each question's first choice, and that the hold moves to the plan gate
   for any other answer. Without that, a Plan question answered against the plan changes nothing.
6. **4b, what is lost** is missing: the `architecture-depth` pack's only reader before Build, and ADR writing.
7. **4c, "effort set on the two Opus agents".** Frontmatter is the only route under the driver; pinning `medium`
   changes nothing in most sessions. Word it as "an effort line after the A/B shows a lower level holds".
8. **1f and 4c.** The A/B is scheduled in WP1, before 4a and 4b change what Plan writes and remove Design. Run it
   after them, or run it twice.
9. **4d, "continues the same agent if the host allows it".** Add the cache lifetime: a resume after five minutes
   pays the whole context again. The fresh revise agent is the design; continuation is a test.
10. **4e** is placed before the model decision it depends on, and its first half is worth less than the draft
    implies next to 2c. Reorder: `Feature:` to Plan and the auto accept first; one launch after 4c.
11. **4f** omits its two costs: the first builders lose the acceptance line, and it cannot be combined with 5a's
    build on the run's branch.
12. **Open point 1** can be narrowed: not through `$.agent.spawn`; perhaps through `$.tool.call`, untested; and it
    does not decide 4d.
13. **2b** ("the CLI writes `reviewed: auto` for a clean map") must also cover a plan with no map and no plan.md.

## 11. Not determined

- Whether `$.tool.call` can send SendMessage to a finished subagent with no model turn.
- Seconds saved by the contract cut; how today's format splits Plan's output.
- Whether Plan holds on Sonnet or on Opus at `low`.
- What the builders' view of the locked acceptance tests prevents.
- Output tokens and dollars of Intent and of its panel.
