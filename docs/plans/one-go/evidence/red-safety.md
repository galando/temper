# Red team review of plan-draft-v1: safety, trust and the product promise

Reviewer lens: what a rule now decides in place of a person, and whether a deterministic check still stands behind it.
Tree read: `/home/user/temper` at `10e965a` (read only; nothing run there). Line numbers are of that commit, read by me.
Read in full: the draft, `_crosscheck.md`, `adr-constraints.md`, `mod.md`, the five verifier reports named in the task,
`docs/trust.md`, `reference/autonomy.md`, ADR 0005, 0012, 0013, 0016, `hooks/temper-mod/core/rules.ts`; read in part:
`packs/guardrails/rules.md`, `scripts/flow.py`, `scripts/temper`, `scripts/risk.py`, `scripts/plan_patch.py`,
`agents/review.md`, `commands/temper.md`. `verify/v-pr115.md` appeared after my first pass; I read it in full and it
added to five points, each marked **[v-pr115]**.

Marks: **[code]** read by me at the cited line. **[verifier]** taken from a verifier report. **[inferred]** my reasoning.

## Verdict

**Not ready to approve as written. Sound in direction; four blockers, all in the plan's text, none in its mechanism.**
The two approval run reverses no enforced safety decision: the guard already treats only leaving Intent and Plan as the
person's advances (`rules.ts:491`). But the draft moves the person's look from eight questions to two and does not
write down what stands in for the six. Three things are missing: the approval is not bound to what was shown, a kept
verdict is not bound to a tree, and decision 2 lists less than the plan lets a rule do (it commits, it amends the plan,
it resolves findings, it goes on after a stop).

---

## 1. Blockers

### B1. Items 2d, 2e: the click "accepts the intent", but nothing binds the click to what was shown, and nothing freezes it afterwards

Facts **[code]**:

- `intent accept` writes a `Status` line and the fixed string "the person at the Intent gate"; it reads no verdict
  and records no digest (`scripts/temper:4474-4504`).
- `advance_ok` lets `state advance plan_complete build` through on a passed or skipped plan gate; it never reads the
  intent's Status (`scripts/flow.py:2510-2535`).
- `state advance plan_complete` freezes `approved_files` and a digest of tasks.md's File, Depends, Test, Validate,
  Interfaces, Context and Integration fields (`scripts/temper:1136-1161`, `_plan_fresh` `:2179-2196`). **There is no
  digest of intent.md anywhere** (grep of `scripts/` and the mod).
- The guard refuses tasks.md from Design on (`rules.ts:245-247`) but allows every other file of the spec folder,
  intent.md included, at Build, Review and Check (`rules.ts:293, 278, 286`). The Build gate reads the criteria from
  intent.md as it is at that moment (`scripts/acceptance.py:259-263`).

Scenario 1 (after the approval). An unattended run reaches Check with `acceptance evidence: AC-09 has no supported
passing evidence row` (a criterion only the person can confirm; the PR's policy loops to Build for it today,
`flow.py:1173-1180`). The fix agent rewrites AC-09 in intent.md to `Validate: test`, or drops it. No guard rule, no
gate row and no hash objects. Build and Check recompute PASS. The commit question shows "9 of 9 criteria". In the
stage by stage flow this hole exists too, but there a person stood at three later questions; in the default run of 2a
nobody does.

Scenario 2 (at the approval). The Plan agent may write intent.md at the Plan stage (`rules.ts:266`), and after 2d the
intent is still a draft there. The approval shows "the criteria one line each" from one state of the file; the
option's calls run later. The mod matches an answer on header, question text, label, run and step
(`docs/decisions/0013:58-66`), none of which changes when the file does. Without the mod nothing matches at all.

Is there a deterministic check today? No.

**Change to the plan text (2d), replace the first two sentences with:**

> **2d. The run leaves Intent by rule; the approval click accepts the intent.** When the Intent gate passes and nothing
> is open, the CLI moves to Plan as its own action and writes nothing but the spec folder. The approval's options carry
> the digests of what the approval shows: `intent accept --digest <H1>` (criteria, scenarios, out of scope,
> assumptions) and `state advance plan_complete build --plan-hash <H2>`. The CLI refuses either call when the file no
> longer has that digest, and refuses `plan_complete` while intent.md is a draft. It records `intent_hash` beside
> `plan_hash`. From then on the Build, Check and commit gates carry a row `intent unchanged since the approval`; the
> CLI's own writes (Status, Completed) are the only exempt lines. The mod refuses a write to intent.md from Build on,
> as it refuses tasks.md from Design on (`rules.ts:245-247`). `Accepted-by` reads "the person, at the plan approval".
> An override of a failed plan check never accepts the intent: with a draft intent and a failed plan gate, the Intent
> question is asked first.

Add to the list in decision 1 of when the separate Intent question stays: "when the plan gate failed or was skipped".
Today's failed Plan question offers `override_opt(self.leave_plan())` (`flow.py:700-701`); with the prototype's
`leave_plan` that one click would skip the plan check and accept the intent under a question that names neither.

### B2. Item 4f: repair in place, as one paragraph, lets a model's claim turn a failed gate to PASS, and its conditions are not written

What 4f changes in kind: today a High finding ends only when the ledger is wiped by a step back and a second whole
Review does not raise it again. After 4f, the CLI writes `resolved` because a reader's row says "fixed". Six gaps, each
a way a bad change gets through:

| # | Gap | Evidence | Scenario |
|---|---|---|---|
| a | `evidence resolve` passes a failed Review gate with any text, from any caller | reproduced **[verifier: v-repair X1]**; not person only (`rules.ts:489`) | The fixer, or any agent with Bash, resolves its own finding. Under 2a the run then advances with nobody asked. Stage 0 lists the hole but names no fix; 2a must not ship before it is closed |
| b | The recheck's rows are ledger rows any agent can add; the CLI cannot tell who wrote them | `agents/review.md:49-50` (a completion is `evidence add --exit 0`) | The fixer writes `recheck #3: fixed` before it returns |
| c | No verdict names a tree | `scripts/temper:1834-1851` **[verifier]** | Build's, Review's and Check's verdicts are kept across a code change. "What is committed is what was judged" is held today only by the write bans and the wipe, and 4f removes both |
| d | The window to reuse is the small change window, and it allows every path | `rules.ts:252` returns `ALLOW` before the Build rule at `:292-305` | The fixer edits a file outside the plan, the config's neighbours, CI files, a lockfile |
| e | The commit hook carve out is a state: while it holds, any `git commit` passes | the checkpoint carve out is keyed on `next_stage` (`scripts/temper:4072-4110`) | The agent commits itself, or two commits land under one window |
| f | "Was a test weakened or removed" is one of the reader's three questions and nothing else | **[verifier: v-repair section 4]** | The fix makes the red test pass by deleting an assertion. Suite green, coverage unchanged, the reader reads 40 changed lines and says fixed |

Also missing: a repair at Check changes code that Review never read; the draft treats Review and Check alike.

**Change to the plan text: replace 4f with the paragraph below, and move its first sentence into stage 0.**

> **Stage 0 (and before 2a ships).** `temper evidence resolve` is the CLI's alone: it refuses unless `--fixed-by` is a
> commit the CLI recorded as its own, reachable from HEAD and not from the reviewed HEAD, and a recheck row for that
> finding exists that was written after that commit. With the mod it is a person only call unless it is the CLI's own
> action.
>
> **4f. Repair in place at Review and Check.**
> *Who opens it.* Only the CLI, as its own action (`repair start`), and only when: the stage's gate failed on rows of
> the repairable list alone (open findings at or above `review.block-on`; a red suite, scenario or acceptance
> evidence row); Review recorded its completion; HEAD is the reviewed HEAD and the tree is clean; no stage of the run
> was skipped; the budget of 2h has room. With the mod, `repair start` typed by an agent is refused.
> *Which paths.* The Build write rule, not the small change window's: the approved files and test files. Never the
> spec folder, the config, the git hooks, a locked acceptance test, a dependency manifest or lockfile, a CI file, a
> file under a sensitive path (decision 7). A change outside is not committed; the repair stops and the Scope drift
> question is asked.
> *The commit.* The agent commits nothing. `repair commit` refuses when HEAD moved since the window opened (a
> foreign commit stops the run, as in Build). The carve out of the commit hook passes exactly one commit per window:
> its parent is the reviewed HEAD, the run is at Review or Check on its own branch, every staged file is approved or
> a test. It never applies to the final commit.
> *What reruns, all by the CLI on the new tree.* `integrate` (suite, every scenario test, interfaces), `gate build`,
> `check run` (coverage, the locked acceptance tests with their digest unchanged), the Review snapshot. A repair at
> Check that changes a file that is not a test gets the same recheck and Review's gate is computed again.
> *The recheck.* A reader that did not write the fix reads the whole diff from the reviewed HEAD to the repair
> commit, written by the CLI. Its rows count only when written after `repair commit` and inside the CLI's launch
> mark for the recheck; its completion row names the changed files and the CLI compares the count. A finding the
> reviewer marked as a behaviour defect is resolved only with a failing CLI run of its test before the fix and a
> passing one after, the test file's hash unchanged between them.
> *One deterministic test rule.* A repair diff that deletes a test file, or removes lines from a test file that
> existed at the reviewed HEAD, is never resolved by rule: the run stops and shows the removed lines.
> *When it reverts.* A CLI row that passed before the repair fails after it; the open blocking findings are not
> fewer; the recheck names a new blocking finding or did not complete; the diff is larger than the bound or touches
> files the findings do not name (then a full Review, not a revert). The CLI reverts with its own commit, checks that
> the tree hash equals the reviewed tree's, and asks.
> *Verdict and tree.* Every gate verdict records the tree it judged. The commit gate passes only when each verdict
> is of the committed tree, or of a tree that differs from it by CLI recorded repair commits whose reruns passed and
> whose recheck completed.
> *Never by rule.* A contested or accepted finding; a file outside the plan; an unfinished Review; `no code changed
> at Review`; SETUP; a missing measurement; a manual criterion; a locked acceptance test the triage does not blame
> on the code; a failure whose class is not code; a finding that needs the plan or the intent changed; anything
> under a sensitive path; the mutation score while it is unstable.
> *Budget.* One automatic repair per stage, counted in the one budget of 2h; one more on the person's click; then the
> loop back. The commit question lists each repair: the finding's text, the files and lines changed, the recheck's
> answer, a revert if there was one.

### B3. Item 4h: an amendment "by the CLI" includes a gate's own command, and is recorded as the person's

Facts **[code]**: `plan patch` is person only in the guard (`rules.ts:481`, "a plan patch changes the approved plan").
Its ledger row reads "plan patch by the person", label `PERSON`, whoever called (`scripts/plan_patch.py:134-136`). It
moves `plan_hash` and nothing else. The draft's 4h says the grown patch covers "a task's File and Depends lines and a
missing Validate" and "inside the approved files it is the CLI's".

Scenarios:

1. *A command by rule.* A group's Validate is the group gate. If the CLI inserts or changes one as its own action,
   the text comes from an agent (the verifier's own table says "an agent has to diagnose" for three of five cases,
   **[verifier: v-failure-budget 4.3]**). A model's line becomes what the gate runs: `pytest -k "not slow"`, a
   narrower path, `true`. That makes a gate easier to pass and is recorded as the person's.
2. *A passed task's tests.* Task 4 reports it is blocked on `tests/test_a.py`, which Task 2 (passed) wrote. The file
   is "inside the approved files", so the CLI adds it to Task 4 by rule. Task 4 may now rewrite Task 2's tests; Task 2
   stays passed because its own fields did not change.
3. *The record.* `approved-tasks.json` and `approved_files` are overwritten (the verifier's "four values move"). After
   the amendment the only record of what the person approved is gone.

The merge list confirms the first scenario on today's code: "a Validate patched to `true` passes the group check; the
patch is a ledger note, not shown as an override; without the mod any caller may run it" **[v-pr115 U2]**. 4h widens
that call before closing it.

Where the line is, and whether the CLI can hold it without the mod: yes, if the by rule form is a separate call
whose whole effect is harmless whoever calls it. The CLI cannot know who calls; it can compare the amended tasks.md
with `approved-tasks.json` field by field (`tasks_change_summary`, `flow.py:155-181`) and refuse.

**Change to the plan text: replace 4h with:**

> **4h. A plan amendment before a replan.** Two calls. `plan amend` (by rule, the CLI's own action in any run): it
> may add to a task a file that another task of the same group already declares and that is in `approved_files`,
> with the Depends line the file ownership row forces, and nothing else. The CLI refuses it when any other field
> differs from the approved plan, when the file is a test another task wrote, a locked acceptance test or under a
> sensitive path, when a group or its Depends changes, or when a task that passed loses a file. The static rows run
> on the result. Its ledger row says "amended by rule" and never "the person". `plan patch` (the person's, as today,
> `rules.ts:481`): every command line (Validate, Test, Integration, a missing Validate), every file outside the
> approved set, every Traced to line. The command is shown word for word in the question. The approved plan's record
> is never overwritten: an amendment is appended to it and the commit question lists each one. A replan stays for a
> fault in the intent, a change of group structure, and an amendment the static rows refuse; an unattended run asks
> for each.

### B4. Decision 2 and item 2a: the owner would sign a narrower sentence than the plan carries out

Decision 2 says: never moves back to Plan by itself; may repair a critical or high finding once per stage; a medium
is carried; never overrides, accepts, pushes or merges. Against the plan and the standing texts:

| What the plan does | Where | Standing text it changes |
|---|---|---|
| The CLI commits a repair on the run's branch at Review or Check, and may revert it | 4f | "the only commits it allows are grouped Build's local task commits and the local `temper integrate` merge ... Hardcoded, not configurable (safety invariants, not preferences)" (`templates/temper.config.default:138-141`); `reference/autonomy.md:36-39`; ADR 0011 resolution 1 |
| The CLI changes the approved plan | 4h | "NEVER re-plans unattended" (same lines); `rules.ts:481` |
| The CLI resolves a finding | 4f | Today only a wipe and a second Review, or the person's accept |
| Review and Check advance by rule | 2a | "The unattended part is Build alone" (`reference/autonomy.md:15-16`) |
| A stop no longer disarms | 2a | "A park ... the run turns interactive again" (`reference/autonomy.md:30`) |
| The CLI leaves Intent, makes a branch and commits a draft intent with no click | 2d (the prototype's `spec branch`, `spec commit`) **[verifier: v-one-approval section 2]** | "The Intent gate is always a question" (`reference/autonomy.md:18`) |

And two things decision 2 does not say that the run needs said:

- *After an override.* Build fails, the run stops, the person picks "Override and continue". With "a stop no
  longer disarms" the run goes on unattended through Review and Check, and 4f may repair by rule on top of a stage
  the checks no longer vouch for. A person who skipped one check did not approve an unattended rest.
- *Taking the wheel.* An interrupt stops the driver, but `/temper:temper` then resumes a run that goes on by itself
  **[verifier: v-auto-advance section 5]**. The person who sees Build go wrong has no question to answer.

**Change to the plan text: replace decision 2 with:**

> 2. **What an unattended run may do, and the list is closed.** By rule it may: advance on a passed, unskipped gate;
> launch the group fix agent once; repair in place once per stage (4f) and commit or revert that repair locally;
> amend the plan inside the narrow form of 4h; carry a finding below `review.block-on` to the commit question. It
> never: moves back to Plan or Intent; changes a command a gate runs, the intent, or the approved file set; resolves
> a finding without the CLI's reruns and a recheck; overrides; accepts; answers a Scope drift row; reopens a locked
> test; writes the config; pushes; opens a pull request; makes the final commit. Arming is a call of the option the
> person picked, offered only on a passed, unskipped gate. It ends at every step back to Plan or Intent, at every
> override and at every accepted finding; after any other stop the question says in its text that the run goes on by
> itself, and offers "Ask me at every stage from here". An interrupted run that is taken up again asks its stage's
> question once. Recommended: yes. This replaces the "hardcoded" lines of the config template,
> `reference/autonomy.md` and ADR 0011 resolution 1, in one new decision record.

**Add to 2a:** "The stops an unattended run keeps are a tested table (the 18 rows of `verify/v-auto-advance.md`
section 2). A selftest fails when an armed run passes one of them by `auto`."

---

## 2. Major findings

### M1. Item 2a: Review's PASS rests on the reviewer's own claim, and its question was the only later look

**[code]** The Review gate has three rows: no open blocking findings (the reviewer's rows), `review completed` (the
reviewer's own `evidence add --claim "review completed" --exit 0`, `agents/review.md:49-50`; `scripts/temper:3838-3846`)
and `no code changed at Review`. Scenario: the reviewer reads 2 of 14 changed files, records nothing, writes its
completion row. PASS, `auto`, commit question: "0 findings". No deterministic row says the diff was read.

Change (2a): "Review's completion row names the files it read. The gate compares them with the files changed since
`base_sha` and fails `review covered the diff` when one is missing. The commit question shows 'Review: N of N files
read, findings by level'."

### M2. Items 2a, 1e, section 5: caps stop growth; nothing stops a later lean change from removing a stop

Section 5 makes every new question pay (remove one or raise the cap). The pressure then runs one way. Change (1e):
"A floor beside the caps: the stops of 2a's table and the person only calls of `rules.ts:476-497` are listed in a
file; CI fails when one is no longer reachable from a question; removing one needs a decision record." ADR 0016
decision 2 tests the reverse (a person only call must have a question); this is its other half.

### M3. Items 2a, 1g: an explicit opt out in an existing config is ignored when the default flips

`autonomy.enabled` has not been read since 9.8.0 (`flow.py:300-303`). That was harmless while arming was the second,
unrecommended option. After 2a the first, recommended option arms. A project whose config says `enabled: false`, and
an organization that wants no unattended runs (`docs/enterprise.md`), get the opposite of what their file says.
Change (1g and 2a): "One key stays, `run.default: to-commit | ask | never-unattended`. An existing `autonomy.enabled:
false` is read as `ask`: 'Ask me at every stage' is first and recommended. `never-unattended` does not offer the
arming option. The key is the person's during a run, as the mod's config rule already holds." Owner decision 8.

### M4. Item 2b: the approval records `reviewed: human` for lines it may not have shown, and a clean map is the Plan agent's own claim

- The folded answer runs `plan review --answer 'As planned'` and writes `reviewed: human`
  **[verifier: v-one-approval section 4]**. The question shows at most three `ignore` and two `gap` lines, cut at 90
  characters (`flow.py:2289-2303`). A map with seven flagged lines is recorded as reviewed by a person who saw five
  halves.
- A map is "clean" when Plan wrote no `ignore` and no `gap`. Today the person sees the sources on every run.
  Scenario: Plan read the legacy billing module, lists it as a source, flags nothing. Nothing is asked and nothing
  is shown.

Change (2b): "The approving option records the answer only when every flagged line was shown whole; otherwise the
Context check stays its own question. The record says where it was given and how many lines were shown. The approval
always shows the map's sources, flagged or not. A clean map is recorded as `reviewed: not needed`, never `human`."

### M5. Item 2c: TRIVIAL ends every gate on a model's word, and "a CLI verdict" hides that

**[code]** Today the Intent agent returns the word `TRIVIAL`, the session runs `state clear` and "then make[s] the
change, run[s] the project's tests, and commit[s] normally" (`commands/temper.md:176-179`; `agents/intent.md:17-20`).
After the clear no run is active, so the guard judges nothing. This is a standing exception to the headline promise,
decided by a model. 2c makes it a CLI call but the CLI has no fact about the request to compute it from.

Change (2c): "TRIVIAL is a call (`intent trivial --why`) the CLI records with the request and HEAD in the kept run
summary (1d), and says in one line. The exit has a bound the commit hook checks without the mod: the next commit
after a trivial exit may change at most one production file and N lines, else the hook refuses and names
`/temper:temper`. README's promise names the exception." Whether the exit needs a click is owner decision 9.

### M6. Item 2d: by rule git writes before any click; and with the mod off the promise is a prompt

- The prototype's `leave_intent(accept=False)` runs `spec branch` (`git checkout -b`, `scripts/spec_ops.py:34`) and
  `spec commit 'docs(intent): draft ...'` as the CLI's own action. A request the person rejects at the approval
  leaves a branch and a commit they never agreed to. Change (2d): "Before the approval the run makes no branch and no
  commit. The approving option's calls make the branch and one spec commit; a branch clash is asked there."
- With the mod off: no rule refuses a code write at Intent or Plan; nothing checks that a person clicked
  (`docs/decisions/0013:122-123`; `docs/ai-native-sdlc.md:83-87`). What holds is the CLI's order, the commit hook and
  the record. That is today's state, but today a session that leaves the script has two questions to skip before
  Build and six more before the commit; after stage 2 it has one and one. The share of users with the mod is unknown
  and the host gates it by a rollout flag **[verifier: v-mod-driver section 6]**.
  Change (2d, new item): "A classic PreToolUse hook of the plugin (Write, Edit, MultiEdit, NotebookEdit) holds the
  stage write rule until `plan_complete` when the mod is not loaded: it reads view.json's guard field, refuses a
  write outside the spec folder at Intent, Plan and Design, and fails open on anything else (one detected violation
  path, ADR 0005's contract). README and `docs/trust.md` say: with the mod, the person's click is checked; without
  it, the write rule is held and the click is not."

### M7. Item 2e: what the approval and the commit question must show is the safety case, and the draft's list is short

The approval replaces three questions. Missing from 2e's list: the request as typed; the assumptions Intent or the
front agent made (the only place a wrong reading of a vague request shows, 3f); what is out of scope; each question
asked with the answer given and the tasks that changed for it (3c: the hold compares only a hash of tasks.md,
`decisions.py:53-69`, so "it changed" is all the gate knows); the commands the gates will run, word for word; files
under a sensitive path, on their own line; the context sources (M4); what the run may do by rule after the click.
The commit question's list lacks everything decided by rule since the approval.

Change (2e), add: "The approval shows, in this order: the request as typed; assumptions; criteria; out of scope;
your answers and what each changed; files by group, sensitive paths marked; the gate commands word for word; context
sources and flagged lines; launches and models; risk and its reasons; one line on what the run does by itself. What
does not fit is named with its count and its file, and the question says so. The commit question shows, beside the
numbers: each repair (finding, files, recheck), each amendment, each carried finding with its text, each check that
was not measured, each sensitive file changed, each stop and the answer given, the budget used, and that every
verdict is of the tree to be committed. Both are CLI fields of view.json, drawn the same with the mod and without."

### M8. Item 2h: the counter must have no exemption a caller can set

"Every repeat that is not the person's own change" needs someone to say which is which. The guard treats `state
redo`, `group fix` and a plain `group reopen` as nobody's (`rules.ts:476-497`); without the mod the CLI cannot tell a
person's call from a model's. A flag that marks a repeat as the person's would be the way round the budget.
Change (2h): "Every repeat counts; no argument exempts a call. At the limit the call is refused and the flow asks
before it offers it, so a refusal is never read as an error or a verdict. The one way on is a person only call that
grants more, recorded with a reason and shown at the commit question (a new row in ADR 0016's table and its
question in the fixtures)."

### M9. Items 3a, 3c, 3f, section 2: the "facts the CLI holds" are partly a model's lines

Section 2 says the CLI decides the route from facts it holds: did Intent ask, the tier, the risk. **[code]** The tier
is `state set complexity`, written by the Intent or Plan agent (`rules.ts:452`). "Nothing to ask" is the front
agent's judgment. Risk is the count of declared production files plus a security map the Plan agent may write and a
`[CROSS-REPO]` row in plan.md (`scripts/risk.py:9-11, 76-93`); 3b removes that row and at the simple tier plan.md.
Scenario: a change to token checking in two files is tier simple, risk L: one front launch, no questions, no fresh
round, Haiku builders, run to the commit.

Changes: (section 2) "Each skip names its fact and who wrote it. The tier that drops an artifact is bounded by the
CLI: more than N declared production files, more than one group, or risk H is never simple." (3b) "The CLI's risk
reads the sensitive path patterns: a declared file that matches is risk H by rule; the cross repo fact is kept as a
line of tasks.md." (3c) "At risk H the arming option is offered only after the fresh round ran and left no open high
finding; a skipped round never arms. 'The person asks for Design' is an option of the approval." (3f) "The Intent
write rule widens to tasks.md and plan.md of the run's spec folder and nothing else; the Intent gate still records
its own verdict; the approval shows the assumptions (M7)."

### M10. Item 3g: folding the acceptance tests into the builder ends "tests come first" as an independent check

The measured case for the locked tests is that a builder passes its own tests and fails the acceptance check
(`docs/evidence/fresh-review.md:51-61` **[verifier: adr-constraints R5]**). "Fold its tests into the builder's first
step" removes the writer that did not write the code, on the evidence of one bench arm over small Python tasks whose
person approves everything. Change (3g): "Whatever the arm shows, the row `acceptance tests written before Build`
stays: the tests are written from the accepted intent by an agent that does not see the builder's work, and locked
by digest before the first task gate. 'Run it beside the first builder' is allowed under that rule; 'fold it into
the builder' needs the owner's decision (10) and a decision record."

### M11. Item 4b: "go on with the suite as information" is a skip, and must be recorded as one

A red base and the answer "go on" removes `tests pass` from every later gate for the whole run. Scenario: 3 tests red
on main; the run breaks 5 more; nothing fails. Changes (4b): "The answer is recorded as the person's skip with a
reason, shown in the report and at the commit question. Where the runner gives test names, the tests that failed on
the base are tolerated and any new failure still fails. A base result of unknown is never read as green. The
baseline runs the project's test command before any approval; `docs/trust.md` says so."

### M12. Items 4d, 4e, 4g: measurements turned into "information" pass a gate silently, and a class must never be a verdict

- 4d: no coverage data means "information"; a missing tool means "information". 4e: mutation may become
  "information only". Mutation is Temper's one measured gain on clear tasks (93% against 79%, `bench:146-149`
  **[verifier]**). In an unattended run nobody sees that a gate stopped gating. This is a threshold change with no
  owner decision.
- 4g: classes are told partly by text patterns. If "environment" or "measurement" can be reached by what a test
  prints ("command not found", "Connection refused"), a class that downgrades a row is a way to pass.

Changes: (4d, 4e) "A check that was not measured is a third state, shown in the gate, the report and the commit
question as 'not measured: <why>', never as PASS. 'The tool is missing' is decided by the CLI's own probe (exit 127,
the program not on PATH), never by output text. `check.require` lists the measurements that stay hard gates; the
default is owner decision 11." (4g) "A class chooses the next step. It never changes a verdict: a FAIL ends only when
the same check passes in a CLI run on a new tree or the person skips it with a reason."

### M13. Item 4c: the digest's exclusions and the reuse store are where a stale PASS comes from

"`git write-tree` on a copy of the index with recorded byproducts left out." If the list of byproducts can hold a
tracked file or a path an agent names, a change to it does not end a cached PASS. Change (4c): "A byproduct is a
path git ignores that the CLI's own run created; the list is written by the runner, never by an agent or the plan;
no tracked file, approved file or test is ever left out. A reused PASS is recorded as reused with its key; only a run
the CLI made is reused. The store of reusable passes is one of the CLI's files in the guard's list, has its own
selftest, and its key holds the setup block's digest and the tool versions."

The last sentence is not a refinement. **[v-pr115 M14, U4]** The reuse store (`<git dir>/temper-results.json`) is
in no guarded list of the mod today: "a kept pass makes a group check and the Integration suite pass without running",
no test names it, and its key has no tool versions. 4c makes that store the base of every later gate's speed. The
draft's stage 0 list names `preflight.json` and `decisions.json` only as missing from the run file list; it does not
name the three files as unguarded. Add v-pr115 M14 to stage 0 by name.

### M14. Sensitive paths (question 6): right that the rows apply; wrong default behind them

See section 4.6 below. Change: a new owner decision 7 and three rules (named in the approval; no carry and no repair
by rule; a confirm exit at the commit gate).

### M15. Item 6e and stage 2's docs: two commitments about what the code and the docs claim

- 6e removes "what exists only for a model in the main session". 2g keeps a closed list of hand backs (Grill Me,
  Teach Me, Share, a pull request body), each a model turn in the main session, and a continued agent wakes that
  model too **[verifier: v-mod-driver 1.3]**. Change (6e): "Only parts with no caller left go. `core/session.ts`
  stays while any hand back kind or door exists. The condition is a safety one, not a measured one."
- Stage 2 has no docs item, while `reference/autonomy.md` (nearly whole), the config template's header, ADR 0011,
  0012 decision 4, 0013 decision 1, `README.md:30`, `.claude/CLAUDE.md` and `docs/trust.md:80-81` state the opposite
  of the new default. P5 says the docs may not claim more than the code enforces. Change (stage 2 pass line): "One
  new decision record and the reworded pages ship in the same release as 2a and 2d; `check-known-limits.sh` holds
  the new sentences."

---

## 3. Minor findings

| # | Item | Point | Change |
|---|---|---|---|
| m1 | 1f | Ids must never become what makes an answer count | "The guard's match stays the exact header, question, label, run and step (ADR 0016 decision 1); an id is a lookup, not a proof" |
| m2 | 2g | The verdict marker must only tell an error from a verdict | "The next step always comes from `temper next`, which reads the recorded verdict; the marker is read only from a call the carrier ran itself" |
| m3 | 4a | A read only verdict call is a free probe of the gate | "At most three verdict calls per attempt, each recorded; failing first still holds per task (`task_ops.py:176-192`)" |
| m4 | 4d | "Correct the acceptance test" moves to Build | "Reopening a locked test stays the person's (`rules.ts:485`); an unattended run stops for it" |
| m5 | 2a | The pull request options move to the commit question | Reword `docs/trust.md:80-81`: "pushes only after the person chose a pull request option at the commit question" |
| m6 | 5b | Ten config lines | "The keys that set a gate (block-on, thresholds, sensitive paths, run default, budget) stay settable and stay the person's during a run" |
| m7 | 4f, ladder | The environment class's first step is "the setup repair" | "A setup block reaches the config only by the person's answer, with the block shown word for word" (stage 0 has the defect; state the rule) |
| m8 | Stage 0 | The flip of Medium names `flow.py:780` and `:1167` | Also the text at `:1141`, which tells the person "findings at medium or above are repaired" |
| m9 | Stage 0 | The PR loosens the Interfaces check on purpose: `client.send(msg)` now matches any `send(msg)` **[v-pr115 U23]**. A gate made easier to pass, in no list of the draft | Name it in stage 0 as kept or reverted, by the owner |
| m10 | Stage 0 | A time-out at the preflight is to pass "with the note not checked" **[v-pr115 M15]** | Fine, and it is the same third state as M12: write one rule for both |

---

## 4. Answers to the seven questions

### 4.1 Each item that removes a question or lets a rule decide

| Item | What a person could have caught at the removed question | Deterministic check that still stands | Gap |
|---|---|---|---|
| Decision 1, 2a (group, Build, Review, Check questions) | A group built the wrong way ("Change"); a diff that looks wrong; a finding to accept or dig into | Task, group and Build gates (CLI runs); Check (CLI runs); the commit gate's scope row (`scripts/temper:4145-4190`) | Review's PASS is the reviewer's claim (M1). No way to take the wheel (B4). Options lost are named in the draft; a pause is not |
| 2b (Context check) | Plan read the wrong sources or left something out | `request routes kept` and the plan rows | A clean map is Plan's claim; the folded record overstates (M4) |
| 2d (Intent question) | A wrong reading of the request, before $0.75 to $1.13 of Plan | The Intent gate's rows; the write rule at Intent and Plan (mod only) | No binding of the click, no freeze (B1); git writes before a click, nothing without the mod (M6) |
| 2h (one counter) | Nothing removed; a bound added | The call refuses at the limit | An exemption a caller can set (M8) |
| 3c (Design question) | Open areas of concern, resolved by the person; a second Opus reading | The plan gate's `tasks agree with decisions`; the fresh round at risk H | The row knows only that tasks.md changed; risk is partly Plan's claim (M9) |
| 3f (Intent launch folded) | Blocking questions on a request the agent wrongly took as clear | `rules checklist covered` | "Nothing to ask" is the agent's; assumptions not shown (M7, M9) |
| 4b (baseline) | Adds a question | The base run | "As information" is an unrecorded skip (M11) |
| 4d (checks at Build's end) | Nothing removed; checks move earlier | The same CLI runs | Coverage and tools as information (M12) |
| 4f (repair) | Whether to fix, accept or go back; what the fix changed | The CLI's reruns on the new tree | Six gaps (B2) |
| 4h (amendment) | Every change to the approved plan | The static rows | Commands by rule; a passed task's tests; the record (B3) |
| Decision 2 | See B4 | | |

### 4.2 Against the hard commitments

- *Makes a gate easier to pass:* 4d and 4e (measurements as information, M12); 4h as drafted (a command by rule, B3);
  4b's "as information" (M11); 3a through the tier (M9); 4c if the exclusions are loose (M13); 3g's fold (M10).
- *Lets an agent or a rule write what only the person may write:* 4h (`plan patch`, `rules.ts:481`); 2b's folded
  `plan review` answer (person only, same line; acceptable only when every line was shown, M4); the environment
  rung and the config (m7); intent.md after the approval, which no rule guards today (B1).
- *Lets unreviewed code reach a commit:* 4f's repair commit is read only by a narrow recheck, and a Check repair by
  nobody unless the plan says so (B2). The final commit stays the person's, and nothing is pushed before it.
- *Lets a model's claim count as evidence:* `evidence resolve` (B2a); the recheck's rows (B2b); `review completed`
  (M1); TRIVIAL (M5); the tier and the clean map (M9, M4). 1g's removal of `evidence.claimed-runs: count` is the one
  change in the draft that hardens this, and should be kept.
- *The person decides only in a dialog:* kept, if every stop of an unattended run is a `Temper gate` question and
  the budget grant, the sensitive path confirm and the pause are options of one (B4, M8, 4.6).

### 4.3 Item 2d: is the promise kept?

Yes with the mod, if B1 and M6 are taken: the guard refuses code writes at Intent and at Plan until `plan_complete`
(`rules.ts:255-275`), and `plan_complete` stays the person's (`:491`). The verifier's correction (the click accepts,
the rule only moves) is right and the draft took it.

- *What the approval must show:* M7's list. The minimum for the promise: the request as typed, the criteria, the
  assumptions, what is out of scope, and a sentence that this click accepts the intent, approves the plan and lets
  the run go to the commit by itself.
- *What the guard must still refuse between Intent and the approval:* every write by the editing tools outside
  intent.md at Intent and outside the spec files and `docs/decisions/*.md` at Plan and Design; `state advance
  plan_complete`, `state set run_mode autonomous`, `intent accept` (new: make it person only), `plan review`,
  `override`, unless it is the picked option's call. After the approval: tasks.md (today) and intent.md (new).
- *With the mod off:* the CLI's stage order, the digests of B1 (the CLI refuses a stale approval call whoever makes
  it), the commit hook, the record. Nothing checks the click. M6's classic hook would hold the write rule. Say so in
  README; do not let "works the same with the mod off" cover the promise.

### 4.4 Item 4f: every way a bad change gets through, and the conditions

B2's table (a to f), plus: a repair at Check that Review never read; a second repair that undoes the first (the
"same finding open" rule covers it); a repair that passes by changing the intent (B1); a fixer that edits outside
the plan through the open window (B2d). The conditions are B2's replacement paragraph: who opens, which paths, the
one commit, what reruns, the recheck's order and count, the deterministic test rule, when it reverts, verdict and
tree, never by rule, the budget, what the commit question shows.

### 4.5 Item 4h and decision 2: amendment against replan

The line: an amendment changes no criterion, no command, no group, no approved file set and no test another task
wrote; it only lets a task of a group write a file the same group already owns. Everything else is the person's
patch or a replan. The CLI can enforce the by rule form without the mod because the call's whole effect is bounded
whoever makes it (a field by field comparison with `approved-tasks.json`). It cannot enforce "the person asked"
for the wider form without the mod; that is today's state for `plan patch`, and the ledger must stop writing
"by the person" for a call it cannot attribute (B3).

### 4.6 Item 2a makes every default run "unattended": the commit gate's rows and the sensitive paths

**[code]** `state set run_mode autonomous` records `ran_unattended` (`scripts/temper:910-912`); the commit gate then
adds two rows (`:4191-4223`). What they really add today is small: the scope row (every changed file is declared, a
test, or allowed at a Scope drift question) already runs in every run with a plan (`:4145-4190`). The count row
applies only with no tasks.md. `park-on-touch` fails only for a changed file under a pattern that the plan does not
declare (`:4202-4217`, since 9.8.0): in practice an undeclared test file, or a file the person allowed at a Scope
drift question, under `auth/`, `payment/` or `billing/`. A planned change to auth code parks nowhere.

- *Is it right that the rows apply to every default run?* Yes, and they should apply in every mode: they describe
  the change, not who watched. But the failed row has no exit today: "An override does not clear this row: change
  what it names (the config's autonomy limits, or the change)" (`flow.py:2274-2276`). A person who answered "Allow
  once" for `src/auth/x.py` is then stopped at the commit with the config as the only way on. 2a's "the commit
  gate's own rows get an exit" must say what the exit is. The merge list's fix, an option "Check again"
  **[v-pr115 M11]**, runs the gate again and the row fails again: it ends the dead end for a person who reverted the
  file, not for one who meant the change.
- *The default for auth, payment and billing.* With unattended as the default, a planned change there runs from
  the approval to the commit, with High findings repaired by rule and Medium ones carried. Proposed default
  (owner decision 7): the three patterns stay, as `sensitive-paths` at the top level, read in every mode; a
  declared file that matches makes risk H by rule (M9); the approval names those files on their own line; when the
  run's changed files include one, an open finding at medium or above stops the run at Review (not carried), no
  repair and no amendment is by rule in those files, and the commit question lists them; an undeclared change there
  fails the commit gate, and the exit is a person only "Confirm the change to <path>" with a reason, recorded in the
  ledger. The run still goes unattended through Build.

### 4.7 Invariants the final plan must state

1. Before the approval the run writes only its spec folder and `.temper`: no project file, no branch, no commit.
2. The approval is of what was shown: its calls carry the digests of the intent and the plan, and a later change to
   either fails the Build, Check and commit gates until the person approves again.
3. Only an option the person picked arms a run, only on a passed and unskipped gate; a step back to Plan or Intent,
   an override or an accepted finding ends it.
4. An unattended run never plans again, changes a gate's command, the intent or the approved file set, overrides,
   accepts, answers Scope drift, writes the config, pushes, opens a pull request or makes the final commit.
5. Every verdict is computed by the CLI from runs the CLI made or the person confirmed, and names the tree it
   judged; the commit gate passes only when every verdict is of the committed tree.
6. A failure's class chooses the next step and never a verdict; a FAIL ends only by the same check passing in a CLI
   run on a new tree, or by the person's skip with a reason.
7. A check that was not measured is shown as not measured, never as passed.
8. During a run only the CLI commits, and every such commit is recorded; any other commit stops the run.
9. A finding is resolved only by the CLI, for a commit the CLI made, after its reruns passed on that tree and a
   reader that did not write the fix confirmed it.
10. Tests come first: a behaviour change has a failing CLI run before the code, and the tests that gate the code are
    written and locked by an agent that did not write it.
11. Every repeat is counted in the CLI against one budget with no exemption; only the person grants more.
12. The person decides only in a `Temper gate` dialog; every stop is one; the commit question lists everything a
    rule decided since the approval.
13. The stops an unattended run keeps are a tested table; removing one needs a decision record.
14. Every rule above is enforced by the CLI or the commit hook with the mod off; where only the mod holds
    something (that a person clicked), the docs say so.

### 4.8 Owner decisions that are not in section 3

| # | Decision | Why it is the owner's | My recommendation |
|---|---|---|---|
| 7 | The default for sensitive paths (auth, payment, billing) in an unattended run | It decides whether a planned auth change may be repaired and carried by rule | The rules of 4.6 |
| 8 | Is there a setting that makes "Ask me at every stage" the default, or forbids arming; and is an existing `autonomy.enabled: false` honoured | The default flips for people who wrote the opposite into their config | Yes to both (M3) |
| 9 | May TRIVIAL skip the approval on the Intent agent's word | A standing exception to the README's first sentence | Yes, bounded by the commit hook and recorded (M5) |
| 10 | May the acceptance tests be written by the builder | "Tests come first" as an independent check | No; beside the builder is fine (M10) |
| 11 | May coverage and the mutation score become information where they cannot be measured soundly | A gate threshold change | Yes for a missing tool, shown as not measured; mutation stays a gate where it is stable (M12) |
| 12 | The repair commit and its hook carve out; may a critical finding be repaired by rule at all | The config template calls the current commit list "hardcoded, not configurable" | Yes with B2's conditions; critical only with a test that proves it |
| 13 | The by rule amendment of the approved plan | "NEVER re-plans unattended" and `rules.ts:481` | Only the narrow form of B3 |
| 14 | The promise's wording, and a classic hook that holds the write rule without the mod | The headline sentence, and what it rests on when the mod is not loaded | "You approve the intent and the plan in one question before any code is written"; add the hook (M6) |
| 15 | After a stop, does the run go on by itself | `reference/autonomy.md:30` says a park turns the run interactive | Yes, except after an override or an accept (B4) |
| 16 | A red base and "go on" | It is a skip of `tests pass` for the whole run | Recorded as the person's skip; new failures still fail (M11) |

Decisions 12, 13 and 15 can be folded into decision 2 if its text is replaced as in B4.

---

## 5. Not determined

- Whether the mod's guard sees the driver's own `$.agent.spawn` launches, and whether it can tell the reviewer from
  the fixer by agent id for B2b **[verifier: v-mod-driver section 9]**. B2's ordering rule does not depend on it.
- How the in-agent commit hook of the guardrails pack treats a commit the CLI makes at Review
  **[verifier: v-repair section 10]**.
- How often a real plan touches a sensitive path, so how often 4.6's stop would fire. No installed copy keeps this.
- Whether a classic PreToolUse hook on the editing tools is acceptable to the plugin directory (M6). Hooks are
  accepted only from verified organizations either way **[verifier: adr-constraints 1.5]**.
- I read `verify/v-pr115.md` in full but checked only my own findings against it. I did not compare the draft's
  stage 0 list with its 16 defects one by one; the one gap I saw is its M14 (finding M13 above).
