# Verification: one approval before Build (draft items 2b, 2c, 2d and decision 2)

Tree read: `/home/user/temper` at `10e965a` (branch `pr115`, clean, nothing written there). Paths are relative to it.
Marks: **[code]** read at the cited line; **[ran]** run in a scratch clone
(`.../scratchpad/work-v-one-approval/repo`, a temp project in `.../work-v-one-approval/proj`, patch in
`.../work-v-one-approval/prototype.diff`); **[doc]** a document of the repository; **[reader]** from a report.

## Verdict: feasible with changes

The mechanism works. A 31 line prototype in two files (`scripts/flow.py`, `scripts/plan_ops.py`) took a scratch run
from the Intent agent to the plan approval with **one** question where the head asks three **[ran]**. Three things in
the draft have to change: who accepts the intent (the person's click, not the rule), how the Context check is made
conditional (no file write is needed), and where the approval is shown (the draft names no display surface).

## 1. What assumes a separate Intent approval

| What | Where | Does the fold break it? |
|---|---|---|
| The Intent question | `scripts/flow.py:633-637`; asked whenever a stage has a verdict (`:2473-2474`); an armed run never covers Intent (`:2441`) | This is the thing removed |
| Its calls: `spec branch`, `intent accept`, `spec commit 'docs(intent): accept <slug>'`, `state advance intent_complete plan` | `scripts/flow.py:556-565` **[ran]** | They move: the advance to the rule, the accept to the plan approval |
| The Status header and `Accepted-by` | `intent accept` writes `**Status:** accepted` and `**Accepted-by:** the person at the Intent gate`, a fixed string; it checks no verdict (`scripts/temper:4474-4504`) | The string becomes false; 1 line |
| The draft rows of the Intent gate | 11 rows apply only while Status is `draft` (`scripts/intent_draft_rows.py:19-34`), so do `out of scope stated`, `open questions resolved` (`scripts/intent_closure_rows.py:35-50`), `blocking question open` and `rules checklist covered` (`scripts/gate_rows.py:34-36, 62-64`) | Only if the gate is computed again: see below |
| `no scenarios in draft` | `scripts/intent_draft_rows.py:169-173`. Plan writes the scenarios into intent.md after the acceptance | **Yes, on two paths.** A draft that holds scenarios fails this row when `gate intent` runs again **[ran]**: a door that walks Intent (`scripts/flow.py:2431-2433`) and a loop back to Intent |
| The intent verdict later | The commit gate and `state advance` read the stored verdict (`scripts/temper:3974-3979`; `scripts/flow.py:2510-2535`); nothing computes `gate intent` again in a straight run | No |
| `intent complete` at the end | only for an `accepted` intent (`scripts/flow.py:2139-2142`; `scripts/temper:4485-4490`) | No, if the approval accepts |
| The guard's person only move | `state advance intent_complete` and `plan_complete` (`hooks/temper-mod/core/rules.ts:491`). But a call of the CLI's own action is let through (`hooks/temper-mod/adapter.ts:231`; `docs/decisions/0013-...md:58-66`), and the calls `temper go` runs are subprocesses, not tool calls (`scripts/go.py:104-106`) | No rule change. The deny text names the question: "not allowed until the user approves the intent ... (Continue to Plan)" (`rules.ts:259-261`) |
| Code writes before approval | refused at stage `intent` and at `plan` and `design` until Build starts (`rules.ts:255-275`) | No: this is what enforces the promise, and it holds until `plan_complete`, which stays the person's |
| Design's trigger `intent_asked` | set when the gate fails on an open Blocking question (`scripts/temper:2096-2100`) | No |
| Plan's brief | "a human accepted it" (`agents/plan.md:19-22, 118`). Plan already takes a `Status: draft` intent as input (`reference/plan.md:51-56`) | Wording only |
| Intent's brief on a loop back | "the person ... accepts this revision at the Intent question" (`agents/intent.md:47-49`) | Stays true if a loop back keeps the question (guard, section 3) |
| The stage hooks for `/temper:intent` | `hooks/hooks.json:2` (description), `scripts/guards/stage-marker.sh:126`, `verify-stage-gate.sh`: they hold a `/temper:intent` session until an intent verdict exists. That command captures a draft, has its own "Commit intent.md" question and never accepts (`commands/intent.md:8-18, 96-99`); `commands/temper.md:208` | **No.** They do not assume an Intent approval inside a run |
| Documents that state it | `README.md:3, 30`; `docs/index.md:58`; `docs/getting-started.md:74-78`; `docs/ai-native-sdlc.md:52-54, 77-79`; `reference/autonomy.md:17-19` ("The Intent gate is always a question"); `docs/directory-submission.md:46, 50, 80`; `.claude-plugin/plugin.json:4`; `.claude-plugin/marketplace.json:3, 12`; `templates/intent.md:69`; `commands/intent.md:108-110` | Wording, section 2 |

## 2. The narrowest change, and the promise

**The run leaves Intent by rule; the person accepts the intent with the plan.** The draft's 2c says "accepted by rule".
That would write `Status: accepted` and an `Accepted-by` line before anyone approved anything, and an abandoned run
would leave an accepted intent nobody accepted. Keeping the acceptance in the person's click costs no more code and
keeps `README.md:3` true as written.

Prototype **[ran]** (`prototype.diff`, `flow.py` part):

1. `Builder.intent_by_rule()`: the conditions of section 3.
2. Before `q = self.ask(stage)` (`scripts/flow.py:2473`): at Intent, when the rule holds, return
   `{"action": "work", "calls": leave_intent(accept=False), "agents": []}`. `temper go` treats a `work` with calls and
   no agents as mechanical and goes on (`scripts/go.py:95-97`). `auto` is the wrong action: the mod draws any `auto`
   as an armed run (`hooks/temper-mod/core/view.ts:126`).
3. `leave_intent(accept=False)`: `spec branch`, `spec commit 'docs(intent): draft of <slug>'`, the advance; no
   `intent accept`.
4. `leave_plan()` (`scripts/flow.py:567-571`): when Status is `draft`, `intent accept` first, and the commit message
   names both.

Result: `temper next` at a passed Intent gave `work` with those three calls; `temper go` ran them and `temper brief`
and stopped at the Plan launch on Opus; intent.md stayed `Status: draft` on `feature/ci`. With a scripted plan
(clean map, `reviewed: pending`) and the patch of section 4, the next question was "Plan: the check passed. Approve
the plan and continue to Build?" whose first option carried `intent accept`, `spec commit 'docs(plan): accept the
intent and approve the plan of ci'`, `state advance plan_complete build`. Running them gave `Status: accepted` and
Build's first action. Not run: the mod's guard (read only), the selftest, the e2e.

Still needed beside the prototype:

- `scripts/temper:4474`: the string `the person at the Intent gate` (the prototype still wrote it). `scripts/temper`
  is 260,504 bytes against a 262,144 limit **[ran: `wc -c`]**, so 1,640 bytes are left; a shorter string frees some.
- `scripts/intent_draft_rows.py:169-173`: `no scenarios in draft` passes once `tasks.md` is beside the intent.
- `agents/plan.md:91-92`: drop the line that adds `- Blocking: Context check: ...` to intent.md. On a draft it would
  fail `blocking question open`, which reads that line too (`scripts/gate_rows.py:37`; the flow filters it,
  `scripts/flow.py:371-373`).
- A way back. The passed Plan question has no "Loop back to Intent"; only the failed one has
  (`scripts/flow.py:672-689` against `:700-701`). Without it the correction is not deferred but gone.
- `scripts/flow.py:1126`: the `Feature:` line for Plan too (section 6).
- The question's text and the option's description must say that it accepts the intent.
- TRIVIAL first (draft 2f). The Intent gate passes on an absent intent.md (`scripts/temper:2038-2039`); the rule must
  require the file (the prototype does), and the driver's wrong question for a trivial request stays until 2f.

**Wording of the promise.** With the acceptance in the click, "Claude cannot write code before you approve the
intent" stays true and needs no change in the manifest or the listing. What must change is every sentence that says
the intent is approved *first* or *at its own gate*: `README.md:30` ("You decide each gate by clicking an answer"),
`docs/getting-started.md:74-78`, `docs/ai-native-sdlc.md:52-54, 77-79`, `reference/autonomy.md:17-19`,
`docs/directory-submission.md:50` ("You approve the intent, then the plan"), `rules.ts:259-261`. Suggested: "You
approve the intent and the plan in one question before any code is written."

## 3. What is lost, and the guard

- **Lost:** the chance to correct the intent before Plan's spend. Today a correction at the Intent question costs an
  Intent pass (30 to 45 s, Sonnet). After the fold it costs that plus a second Plan pass: $0.75 to $1.13 and 143 to
  246 s (`docs/evidence/bench-2026-11.md:354-357` **[doc]**), and the approval again.
- **Also lost:** Grill Me and Teach Me on the intent alone, and "Save for later" at Intent (`scripts/flow.py:636-637`).
  The UX report proposes exactly that Save as the replacement for `/temper:intent` (ux-onboarding, lines 172 and 453
  **[reader]**); it conflicts with draft 6a.
- **What the person sees at that question today:** when Intent asked, their own answers and nothing new. The answers
  go to Decisions by a CLI call and no agent rewrites the criteria (`scripts/answer_ops.py:54-95`;
  `hooks/temper-mod/core/driver.ts:372-391`). The Intent agent's box shows the count of criteria, not the criteria
  (`agents/intent.md:174-187`).
- **How often a person changes the intent there: not determined, and no evidence exists.** The benchmark's person
  takes the recommended option at every gate (`bench/person.mjs:5-8, 31-32`; `docs/evidence/bench-2026-11.md:189`).
  The e2e person does the same (`scripts/e2e/scenarios.ts:119-123`). A run's records are deleted at its end
  (`scripts/temper:1448`). The one recorded revision of an intent came from a loop back from Plan, not from the Intent
  question (`docs/evidence/live-brief-checks.md:51-55`).

**Guard: keep the Intent question unless all of these hold** (each is a fact the CLI has at that point):

| Condition | Read from | Why |
|---|---|---|
| the gate passed and was not skipped | `r.verdict`, `r.skip` (`scripts/flow.py:275-294`) | a skip is the person's (`rules.ts:478`) |
| intent.md exists | `r.intent` | the trivial path passes with no file (`scripts/temper:2038-2039`) |
| no Blocking question is open | `r.blocking()` (`scripts/flow.py:371-373`) | they are asked first, as today |
| no branch clash | `branch_clash()` (`scripts/flow.py:535-545, 622-632`) | a true choice with no recommended answer |
| the run did not come back to Intent | `r.loop_into`, `r.loop_through` (`scripts/flow.py:323-343`) | the criteria changed after the person saw them |
| the person typed no note at Intent | `r.notes("intent", "input")` (`scripts/flow.py:184-189`) | they see what became of it |
| no door walked Intent | `walked()` (`scripts/flow.py:1110-1116`) | doors keep their checked questions (`:600-614`) |

"At tier complex" is weak at this point: the run's tier is recorded by Plan (`agents/plan.md:30-33`); at Intent there
is only the agent's first guess in the `**Complexity:**` line (`agents/intent.md:60-61`). If the owner wants it, read
that line, and say it is a model's guess. A better use of the same space: show the intent's assumptions and the
request text in the approval.

## 4. The Context check

**Confirmed: asked on every default run in which Plan writes plan.md as briefed.** Plan is told to write
`- reviewed: pending` (`agents/plan.md:89-94`; `templates/plan.md:8`). The row fails on `pending` unless the mode is
`off` (`scripts/plan_ops.py:92-94`), and is emitted whenever plan.md exists (`scripts/gate_rows.py:331-332`;
`scripts/temper:3593`). The flow builds the question when the line is neither `human` nor `auto` and asks it when it
is the only failed row (`scripts/flow.py:2338-2344`). The only writer of the line writes `human`
(`scripts/plan_ops.py:143`); nothing writes `auto` **[ran: grep]**. On the head, a clean map with `pending` under
`auto` fails the row **[ran]**. The config comment and `reference/plan.md:67-70` say "ask only when the map has an
`ignore` or a `gap`". The fixtures write `auto` themselves (`scripts/e2e/project.ts:4`, `pyjokes.ts:119`,
`replay.ts:132`).

**Step 1, conditional (10 lines, [ran]).** No file write, so no gate that edits plan.md:

- `scripts/plan_ops.py`: `asks(m, mode)` = `always`, or not `off` and the map holds an `ignore` or `gap`; line 92
  becomes "not human or auto, and not (pending and not asks)"; `map_json` gains `flagged`.
- `scripts/flow.py:2338`: the same rule.

After it: clean pending map under `auto` passes ("2 source(s) listed, reviewed: pending"), `next` carries no
`context_check`, the plan question comes directly; a map with a `gap` still asks; `always` still asks.

**Step 2, fold the flagged case.** Step 1 alone may remove little: the template shows one `ignore` and one `gap`
line as its example (`templates/plan.md:5-7`), so real plans may often hold one. How often: not determined (no plan.md
with a Context Map is in the repository).

- The row passes for a pending map with flagged lines under `auto` (its detail counts them). A failing row would turn
  the approval into the failed Plan question (`scripts/flow.py:700-701`). `reviewed: auto` cannot serve: the row
  refuses it with flagged lines (`scripts/plan_ops.py:95-100`).
- The plan question's text gains the sentence `context_text` already builds, three `ignore` and two `gap` lines cut at
  90 characters (`scripts/flow.py:2289-2303`).
- The approving options run `plan review --answer 'As planned'` first, so plan.md records `reviewed: human` from a
  click that showed the lines. `plan review` stays the person's (`rules.ts:481`).
- "Include what is left out" (`scripts/flow.py:2312-2318`) becomes an option of the plan question. "Something else"
  and "Carry forward" go: a typed answer at a gate is already a note that sends the agent again
  (`scripts/flow.py:2399-2410, 1133`), and Carry forward runs nothing (`:2321`).
- `context_check` stays in `next` and the view as null (version 1 removes no field, `docs/flow.md:21-23`). The mod's
  typed answer case (`hooks/temper-mod/core/answers.ts:78-87`) is then reached only under `always`.

## 5. What the CLI can draw, and the limits

Already there:

- `temper panel plan` (`scripts/panel.py:91-137`): the first sentence of the Problem, the **count** of criteria and
  scenarios, the **count** of files to create and modify, the risk letter, the tier, the scenario names with
  `Covers`, the plan's decision headings, the diagram. It runs after the Plan agent (`scripts/flow.py:1379-1381`).
- The view: the plan's files by Build group (`scripts/flow.py:2747-2758`), tasks with title and files per group
  (`:2713-2733`), the criteria (`:2619-2627`), the Context Map rows and table (`:2337`), the request text
  (`run.feature`, `:2814`), the fresh review.
- The question: the fresh reader's paraphrase and open findings (`scripts/flow.py:651, 658-665`); an option
  `preview`, used for the Context Map table (`:2323-2324`).

Missing for the approval the draft describes:

- The criteria one line each, the files by group marked create or modify, the tests (each group's Validate, the
  Integration command, the tasks' Test commands), what is left out (the intent's `Out of scope` bullet, parsed today
  only in `scripts/intent_closure_rows.py:27-33`; the map's `ignore` and `gap`; Deferred questions), the assumptions,
  the reasons for the risk, the launches and models (computed only inside Build, `scripts/flow.py:1558-1610`).
- **A place to show it with the mod.** The driver turns a panel into one row per section, items joined
  (`hooks/temper-mod/core/driver.ts:84-88`), and a log line is cut at 2,000 characters
  (`hooks/temper-mod/register.tsx:597-599`). A list of criteria would be one long row. The existing surface that fits
  is the mod's own drawing above the dialog (`register.tsx:913-918`; `hooks/temper-mod/ui/question.tsx:9-18`, today
  one dim line), fed by a new field of view.json. The pane has the files by group but opens by itself only from 144
  columns (`docs/mod.md:55-56, 66-68`). Without the mod the session copies the panel into its reply, as today.

Limits (platform report, section 3 **[reader]**): 1 to 4 questions a call, 2 to 4 options a question, a header of
at most 12 characters (`Temper gate` is 11), an "Other" text row, not available in a subagent. `flow.py` already
holds four options and nests the rest (`scripts/flow.py:492-498, 509-515`). Previews: the docs name them for the
TypeScript SDK only; the mod sets `preview` through its tool call hook (`driver.ts:59-75`) and a comment says a
preview "cannot hold a panel of forty rows" (`driver.ts:85`). Whether and how large a preview shows in the terminal:
not determined. So the approval cannot lean on it. The mod counts an answer only on an exact match of the question
text (`docs/flow.md:94-96`), so the text stays short and the body goes in the panel.

Options: the passed Plan question already fills four with a More question of four (`scripts/flow.py:673-680`).
Adding "Include what is left out" and "Loop back to Intent" makes a More question of six, so a second level; that
path broke once in this PR (`scripts/flow.py:925-947`, flow-questions finding 10 **[reader]**). Move Share HTML
review and Teach Me off this question, or accept the second level with a test.

## 6. Does the Plan agent get the request text? No

Only Intent's prompt gets `Feature:` (`scripts/flow.py:1126-1130`). Plan gets the brief path, the spec path and the
person's notes (`:1123-1125, 1131-1134`). The brief holds the request's *words that can name code*, not the request
(`scripts/brief.py:186-189`; the scratch run's brief read "nouns: report" **[ran]**). The run keeps the text
(`state.feature`), and one gate row compares its routes with the plan (`scripts/gate_rows.py:284-317`). Once nobody
reads the intent before Plan, give Plan the line: one condition at `scripts/flow.py:1126`.

## Order of the work

1. Step 1 of section 4 (S).
2. The rule move and the acceptance at the approval, with the way back and the wording (M). After 2f.
3. Step 2 of section 4 (S to M).
4. The approval panel and the mod's drawing of it (M).

## Not determined

- How often a person changes the intent at the Intent question (no data anywhere).
- How often a real plan's Context Map holds an `ignore` or a `gap`.
- Whether an option preview renders in the terminal, and its size limit.
- The mod's guard with the rule move: read, not run.
- The longest question text the dialog shows whole.
