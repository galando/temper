# Phase 4, second half: WP15 the cards, WP16 the hand back kinds, WP17 the fix run and TRIVIAL, WP18 two holes
Every `file:line` is of the head `10e965a`. Evidence paths are under `docs/plans/one-go/evidence/`.

The brief is `docs/plans/one-go/README.md`, and every shared name below is the one `docs/plans/one-go/contracts.md`
fixes. WP02 and WP03 land before these packages and move code: find each function by its name. "The flow modules"
are `scripts/flow.py` and the seven modules WP03 made of it (`scripts/flow_base.py` holds the tables and the
registries, `scripts/flow_view.py` the view). Each package ends as the brief's section 4 says:
`bash scripts/verify.sh quick` green, then the package commit, then the small progress commit, in one push.

The build order is that of the brief's section 5, not the order of this file: WP18 is built first, after WP10 and
before WP14 and WP11; WP15, WP16 and WP17 follow WP13, and `bash scripts/verify.sh full` after WP17 ends phase 4.
From WP18 on `temper evidence resolve` refuses every call, until WP24 records a repair commit. This is meant: until
then a blocking finding ends by the person's accept, or by the one counted loop back of WP11 and a second Review.
A test that needs a resolved finding uses the helper WP18 adds.

A check leaves `scripts/selftest/expected-fail.txt` in the package commit that makes it pass. A check that passed
earlier is simply not on the list (`docs/plans/one-go/done.md`, note 7). If one still fails for a reason that
belongs to a later package, do not weaken it: name that package on its line of the list and in
`docs/plans/one-go/PROGRESS.md`.

## WP15 The cards: approval, commit, stop

- **Goal:** Each question that decides (the approval, the commit, a stop) carries one card that the CLI computes
  from files and ledgers. The same card is a field of the view, text where no mod draws, and a drawing above the
  dialog where the mod does. A reader can say from the card alone what the click approves (rules 2 and 10).
- **Depends on:** WP03, WP04, WP05, WP10, WP11, WP12, WP13, WP14. The names those packages own are in
  `docs/plans/one-go/contracts.md`: the questions `plan.approve`, `rca.approve` and `commit.confirm`, the call
  `temper state set run_mode autonomous` that starts the unattended run, the arguments
  `--shown <file name>=<digest>`, and the record `.temper/rule-log.json` with the view field `rule_log`. Map them
  in one place.
  Extended later by WP17 (the two fix variants) and by WP19, WP20, WP22, WP24, WP25 and WP27, which each add rows
  through `scripts/card.py` and nowhere else.
- **Lane:** `flow core`.
- **Touches:** `scripts/card.py` (new), `scripts/panel.py`, `scripts/validate-panels.py`, `agents/plan.md` (the
  paragraph on its panel), the flow modules (the view in `scripts/flow_view.py`,
  `Builder.next`), `scripts/go.py`, `scripts/temper` (one word, `card`), `scripts/run_summary.py` (a reader of the
  kept summaries, for the time estimate), `hooks/temper-mod/core/runview.ts`, `hooks/temper-mod/core/view.ts`,
  `hooks/temper-mod/core/driver.ts`, `hooks/temper-mod/ui/question.tsx`, `hooks/temper-mod/register.tsx`,
  `commands/temper.md`, `scripts/selftest/make-view-fixtures.sh`, `scripts/selftest/view-fixtures.ts`,
  `scripts/selftest/view-fixtures-2.ts`, `scripts/selftest/cards/` (new, three text files),
  `scripts/selftest/temper-cases-56.sh` (new), `scripts/selftest/temper-cases-54.sh` (one case of WP13),
  `scripts/e2e/scenarios.ts`, `scripts/e2e/loop.ts`,
  `tests/mod/view.test.ts`, `tests/mod/drawings.test.tsx`, `tests/mod/driver.test.ts`, `docs/flow.md`, `docs/mod.md`,
  `scripts/selftest/expected-fail.txt`, `docs/plans/one-go/changed-tests.md`, `CHANGELOG.md`.
- **Tests first:**
  1. `scripts/selftest/temper-cases-56.sh` (new; `docs/plans/one-go/contracts.md` section 10 reserves the number),
     with the helpers `nx` and `vw` of `scripts/selftest/case-helpers.sh:16-17`:
     - `card: the approval question carries an approval card`: `nx "d['card']['kind']"` is `approval`, and the
       section ids come in the order of the table in Mechanism step 3. The same holds at the Design question of a
       run where the person asked for Design: that question is then the approval.
     - `card: one row per criterion, and a cut section names its count and its file`: an intent with 12 criteria
       gives 8 rows, `total` 12 and `file` the path of `intent.md`.
     - `card: the gate commands are word for word`: a Validate line with quotes and a pipe is byte equal in the
       `commands` section; that section is never cut.
     - `card: a sensitive path has its own row`: a plan file that matches `autonomy.park-on-touch` is marked
       `sensitive` and the `files` section ends with the row that names the path.
     - `card: every flagged Context Map line is whole`: an `ignore` line of 200 characters is in the card whole (the
       question text cuts it at 90, `scripts/flow.py:2293`).
     - `card: nothing is estimated from nothing`: with no kept run summary and no baseline record the card has no
       `baseline` section and its `foot` holds no minutes. With two finished runs in `.temper/runs.jsonl` the foot
       holds one row with their median in minutes, marked `about`.
     - `card: no card holds dollars`: at the three golden states, with a run summary kept, no title, tag, note, row
       or foot of a card holds a dollar sign, the word `dollar` or a price; every time is in minutes.
     - `card: no criterion is marked as the person's answer by guess`: the `criteria` rows carry only the mark their
       own line gives (`proposed`); the answers are rows of `answers` and the assumptions rows of `assumptions`,
       each a section of its own.
     - `card: the text form fits`: `temper card` on the sample project prints rows of at most 76 columns, at most 40
       rows apart from `commands` and the flagged `context` rows.
     - `card: three carriers, one card`: `temper go` prints in `card` the lines `temper card` prints, and
       `.temper/view.json` holds the object `temper next --json` holds.
     - `card: the commit question carries a commit card`: sections in the order of step 4; a skip shows with its
       reason; an open medium finding shows with its text; the `message` row equals the message in the option's
       `spec commit` call.
     - `card: a failed check asks with a stop card`: the failed rows, the count used of the budget of WP10, and no
       option text inside the card.
     - `card: a question that is none of the three has no card`: `card` is null at a passed Build question of a run
       that asks at every stage.
     - `card: golden texts`: `temper card` at the fixture states `plan-pass`, `commit-pass` and `check-fail`
       (`scripts/selftest/make-view-fixtures.sh:128, 156, 148`) equals `scripts/selftest/cards/approval.txt`,
       `commit.txt` and `stop.txt` byte for byte.
  2. `tests/mod/view.test.ts`: `parseRunView` reads `card` from the fixture `plan-pass`; a card of an unknown
     `kind` reads as null; a view with no `card` field still parses.
  3. `tests/mod/drawings.test.tsx`, new cases (no test draws the question line today; `tests/mod/modes.test.ts:6`
     only lists the element `questionHeader` per mode): `renderQuestion` with a card draws the title, each section
     title and each row above the engine's dialog; with no card it draws the one dim line it draws today.
  4. `tests/mod/driver.test.ts`: before it asks, the driver gives the card's lines to the port once; a question
     with no card gives none.
  5. `scripts/e2e/scenarios.ts`, `fullRun`: in `plain`, `mod` and `driver` mode the trace holds one entry
     `card approval` before the approval's answer and one `card commit` before the commit's answer; the traces stay
     equal between modes (`scripts/e2e/run.ts:28-31`).
  6. From `scripts/selftest/expected-fail.txt`: the scenario `flagged-map` of `scripts/e2e/accept.ts` (row `D02`),
     and `D02b`, `D22a` and `D22b` of `scripts/selftest/temper-cases-44.sh` (rows `D02` and `D22`), pass and leave
     the list here. The check of WP07 for rule 10, `D39c` of `scripts/selftest/temper-cases-45.sh` (the commit
     question lists everything a rule decided since the approval), holds here as far as the records of WP10 and
     WP11 go. It stays listed, with WP25 named on its line, until the repair of WP24 and the amendment of WP25 are
     on the card (row `D39`).
  7. Two checks of WP13 flip here, because the card shows a flagged line of any length whole. What holds at the
     end is row `D02b` of `docs/plans/one-go/done.md`: the answer is recorded at the approval only when the
     `context` section of the card holds every flagged line; a card whose section is cut records no answer and the
     Context check is asked; `plan.context-check: always` still asks. Rewrite the case
     `context: a map with a gap still asks under auto when a line cannot be shown whole` of
     `scripts/selftest/temper-cases-54.sh` to that rule (a flagged line of 95 characters is now folded; a card
     whose `context` section is cut still asks). Give the scenario `context-check` of `scripts/e2e/scenarios.ts`
     the config line `plan.context-check: always`, so that it keeps its own question. List both in
     `docs/plans/one-go/changed-tests.md`.
- **Mechanism:**
  1. **The card as data.** `scripts/card.py` gets `build(run, nxt)` (the card, or `None`) and `render(card, width)`
     (the text rows). The shape, the same in `temper next --json` and in the view:

     ```json
     {"kind": "approval",
      "run_id": "RUN", "step": 7,
      "title": "APPROVE BEFORE ANY CODE IS WRITTEN",
      "tag": "login-lockout · risk M",
      "sections": [
        {"id": "criteria", "title": "WHAT WILL BE TRUE",
         "note": "5 criteria; each gets a test written and locked first",
         "rows": [{"text": "AC-01 5 failed logins in 15 min lock the account", "mark": null},
                  {"text": "AC-05 Admins are locked like everyone else", "mark": "proposed"}],
         "total": 5, "file": ".temper/specs/login-lockout/intent.md"}],
      "foot": ["You are asked again only if a check still fails after one repair, and at the commit.",
               "Nothing is pushed."]}
     ```

     `kind` is `approval`, `commit` or `stop`. `run_id` and `step` are the pair the question carries
     (`scripts/flow.py:501`). A section is cut when `total` is larger than the count of `rows`; `file` says where
     the rest is. `mark` is one of a closed list: `proposed`, `create`, `modify`, `sensitive`, `left out`,
     `not found`, `not measured`, `open`, `skipped`, `by rule`, or null. No field holds a rendered line: the text
     form is made by `render`, so the fixtures hold each card once.
  2. **Which question gets which card.** `kind_of(run, nxt)` in `card.py`, the one place: the approval question and
     the commit question by the question id WP04 gave them (`plan.approve` and `rca.approve`; `commit.confirm`);
     when the person asked for Design, the Design question (`design.pass`) is the approval (WP11 step 4): it gets
     the approval card, built in the same call as the digests of WP12, exactly as `plan.approve` does;
     `stop` for any other `ask` whose stage has a FAIL verdict that is not skipped, or that WP11 recorded as a stop
     of an unattended run; else no card. In a run that asks at every stage the commit decision is still the passed
     Check question (`check.pass`, `scripts/flow.py:813-821`) unless WP11 moved it: it gets the commit card. A
     parked commit (`scripts/flow.py:2243-2244`) gets the commit card too.
  3. **The approval card, sections in this order** (the order of `red-safety.md`, M7). A section with no source is
     left out, never filled with a guess.

     | Section id | Shows | Source | Row cap |
     |---|---|---|---|
     | `request` | the request as typed | `state.feature` (`scripts/flow.py:2814`) | 2 |
     | `assumptions` | what Intent assumed for rules nobody was asked | the bullets under `### Assumptions` (`templates/intent.md:66`) | 4 |
     | `criteria` | one row per criterion: id and text; mark `proposed` when the line says so | `acceptance.parse_criteria`, as `scripts/panel.py:95` | 8 |
     | `out_of_scope` | the `Out of scope` bullet, one row | the reading of `scripts/intent_closure_rows.py:27-33`, moved into one function both use | 2 |
     | `answers` | each question the person answered with the answer; the tasks that changed for it where WP14 recorded them | rows of `### Decisions` that end `(the person, DATE)` (`scripts/answer_ops.py:74`); the store of `scripts/decisions.py` as WP14 left it | 4 |
     | `files` | per Build group: title and files, each marked `create` or `modify`, a sensitive one marked so; a last row `SENSITIVE PATH IN THE PLAN:` with the paths; the note `N files; any other file asks you first` | `plan_view` (`scripts/flow.py:2747-2758`); exists on disk as `scripts/panel.py:112`; `autonomy.park-on-touch` (`scripts/temper:4204`) | 8 |
     | `commands` | each group's Validate, the Integration command, each task's Test command, word for word; a manual task is named | `scripts/tasks_md.py:75, 83, 109` | none |
     | `context` | the count of sources; each `ignore` line as `left out`, each `gap` line as `not found`, whole | the Context Map rows (`scripts/flow.py:2337`) | none for flagged lines |
     | `launches` | how many agents of which kind, and the model of each kind | the plan's groups and tasks; `task_model` (`scripts/flow.py:1605-1610`); `ctx["models"]` (`:1121`) | 2 |
     | `risk` | the letter and its reasons the CLI can name: the count of files, a sensitive path, hot paths | `state.risk`; the security map as `scripts/panel.py:123-135` | 2 |
     | `baseline` | the suite command, its time and result on the current code, the coverage floor | `.temper/evidence/baseline.json`, which WP20 writes; absent before WP20 | 2 |

     The `foot` says in one or two rows what the run does by itself after the click, taken from the mode the first
     option sets (WP11): it asks again only when a check still fails after one repair and at the commit, or it asks
     after every stage. Its last row is `Nothing is pushed.` A time estimate is a row of the foot only when the kept
     run summaries of WP05 (`.temper/runs.jsonl`, read through `scripts/run_summary.py`) hold at least one finished
     run of this project; it is their median, in minutes, marked `about`. No card shows dollars, in any section or
     in the foot: the CLI holds none. A card shows minutes only, and an estimate only from those kept summaries.
     The person's answers and what Intent assumed are never marks on a criterion: each has a section of its own
     (`answers`, `assumptions`).
  4. **The commit card, sections in this order** (the plan, section 3, and M7):

     | Section id | Shows | Source |
     |---|---|---|
     | `criteria` | N of N met; each one not met with its text | `criteria(run)` (`scripts/flow.py:2619-2627`) |
     | `suite` | the test command, pass and fail counts, its time | `check_markers` (`scripts/flow.py:2597-2616`) |
     | `coverage` | the value against the floor, or `not measured` | the same; the third state is WP19's |
     | `planted_bugs` | the score, as information | the Check ledger's mutation row |
     | `review` | findings by level; each open finding with its text; `N of N files read` | `Run.findings` (`scripts/flow.py:398-417`); `finding_counts` (`:1423-1430`); the row `review completed` of WP18 |
     | `files` | N changed, all in the plan, or the ones outside; each sensitive file changed | the commit gate's scope row (`scripts/temper:4145-4190`); `park-on-touch` |
     | `rule_log` | everything a rule decided since the approval: each stop and the answer given, each carried finding, each check not measured, the budget used; later each repair (WP24) and each amendment (WP25) | `.temper/rule-log.json` (the view field `rule_log`, WP11); `.temper/budget.json`, read through `scripts/budget.py` (WP10) |
     | `skips` | each skipped check with its reason | `overrides` (`scripts/flow.py:2843`) |
     | `tree` | that every verdict is of the tree to be committed: the commit id and the count of uncommitted files; the tree id from WP22 on | `git`; the verdict records |
     | `run` | time in minutes, launches, dialogs; never dollars | `usage` (`scripts/flow.py:2761-2776`) |
     | `message` | the commit message the click will use, and the branch with `not pushed` | `feature_message` (`scripts/flow.py:2149-2151`), the record message (`:2198`) |

  5. **The stop card:** `what_fails` (the failed rows of the stage with the kept output lines, as `temper output`
     prints them, `scripts/output_ops.py:1-5`), `tried` (what ran for this failure and the count used of the budget
     of WP10, per failure and per run), `reading` (the triage verdict or the failure class, when one is recorded:
     `acc_triage`, `scripts/flow.py:1459`), `still_green` (the stages that passed), `spent` (time so far). The foot
     says whether the run goes on by itself after the answer.
  6. **The text form** (`render`, width 76, the width of `scripts/panel.py:27`): the title left and the tag right
     on one row; then per section its title with the note in brackets, its rows indented one space with the mark
     in square brackets at the right edge, and `and N more: FILE` when cut; a blank row between sections; the foot
     last. No box border. A row longer than the width wraps with two spaces of indent, as `scripts/panel.py:38-42`.
     In `files` the mark `create` is drawn as `+` and `modify` as `~` in front of the path; a short section
     (`out_of_scope`, `launches`, `risk`) is one row that starts with its title. The row caps of step 3 keep a
     card near one screen; the selftest holds the sample at 40 rows. The sample to hold the golden file against:

     ```
     APPROVE BEFORE ANY CODE IS WRITTEN                      login-lockout · risk M
     You asked: "lock accounts after too many failed logins"

     ASSUMED (1; nobody was asked)
      Admins are locked like everyone else (because no rule was given)

     WHAT WILL BE TRUE (5 criteria; each gets a test written and locked first)
      AC-01 5 failed logins in 15 min lock the account for 15 min
      AC-05 Admins are locked like everyone else                          [proposed]
     NOT IN SCOPE: unlock by email · CAPTCHA · limits per IP

     YOUR ANSWERS (1)
      How long does the lock last? -> 15 minutes

     WHAT WILL CHANGE (4 files; any other file asks you first)
      G1 the lockout rule    + src/auth/lockout.ts  + test/auth/lockout.test.ts
      G2 the login endpoint  ~ src/auth/login.ts    ~ test/auth/login.test.ts
      SENSITIVE PATH IN THE PLAN: src/auth/

     THE CHECKS RUN
      G1: npm test -- lockout
      all: npm test

     CONTEXT (6 sources)
      src/admin/login.ts (the admin login keeps its own flow)             [left out]

     LAUNCHES: 1 test writer, 2 builders (sonnet), 1 reviewer
     RISK M: 4 files, a sensitive path
     You are asked again only if a check still fails after one repair, and at
     the commit. Nothing is pushed.
     ```
  7. **Where the card is attached.** In `Builder.next` (`scripts/flow.py:2331-2346`), after `core_next`: when the
     action is `ask`, `out["card"] = card.build(r, out)`. In `view` (`scripts/flow.py:2809-2846`): one more key,
     `"card": nxt.get("card")`. The card is built in the same call as the question, from the same reads of
     `intent.md`, `tasks.md` and `plan.md`, so the digests WP12 puts on the approving calls are of the bytes shown.
  8. **Without the mod.** `scripts/go.py`, `compact`, the `ask` branch (`:68-74`): `out["card"]` is
     `card.render(n["card"], 76)`, a list of rows. `scripts/temper` gets the word `card` beside `panel`
     (`:5045-5050`): it prints the rows of the current question's card, and nothing with exit 0 when there is none.
     `commands/temper.md`, the `ask` bullet (`:108-114`): when `card` is there, print its rows as they are in one
     code block, then ask.
  9. **With the mod.** `core/runview.ts`: the types `Card`, `CardSection`, `CardRow`, and `card` on `RunView`
     (`:32-90`), parsed with the file's own helpers in `parseRunView` (`:142-291`); an unknown `kind` gives null.
     `core/view.ts` carries it to the `View` that `questionHeader` reads (`:294-297`). `ui/question.tsx:9-18`:
     `renderQuestion` takes the card and draws the title, the sections and the rows above the engine's dialog, the
     dim line first. `register.tsx:913-918` passes the card only for a dialog the driver itself raised (`asking`
     is set, `:535`). `core/driver.ts`: `GoOut` gets `card?: string[]` (`:22-33`), `Effect` and both ports get one
     effect `card`, yielded before `answer(cli, g.ask)` (`:393`). The engine's port draws nothing for it in `full`
     mode (the render hook draws from the view) and logs the rows with `logRows` (`driver.ts:150-157`) in any other
     mode. A dialog the conversation raised has the rows from the page (step 8), and the mod draws no card on it.
  10. **The Plan panel goes.** Remove the `panel plan` after call (`scripts/flow.py:1379-1381`; Design keeps its
      panel). The approval card shows what it showed, and the question follows at once in a default run.
      `scripts/validate-panels.py:31` (`CLI_PANEL`) wants every stage brief to show one closed panel or to name
      `temper panel plan|design|rca|task`. Make it accept one more form a brief may name, "the CLI draws the card
      (`temper card`)", and change the paragraph of `agents/plan.md:121-127` that names `temper panel plan` to
      that form. The new brief `agents/plan-revise.md` of WP27 uses the same form.
  11. Regenerate the fixtures (`bash scripts/selftest/make-view-fixtures.sh` and the same with `extra`), and write
      the three golden texts from `temper card` at the three states.
- **Removed:** the `plan` box of `scripts/panel.py:91-137` and its call (the helpers `section`, `plain`,
  `first_sentence` stay, `card.py` imports them); the `plan` word of `temper panel` (`scripts/temper:5046`); the
  diagram line of `compactPanel` (`hooks/temper-mod/core/driver.ts:135`); the sentence of `commands/temper.md:87-89`
  about an agent whose after calls hold `temper panel`, for Plan.
- **Documents in the same change:** `docs/flow.md` (the field `card` in the `next` section and in the view table,
  `:264-290`; the word `temper card`); `docs/mod.md` (what is drawn above the dialog); `CHANGELOG.md`;
  `docs/plans/one-go/changed-tests.md` (each case that stated the old Plan panel on purpose). The three golden
  texts are the samples the README of WP31 quotes.
- **Done when:** `bash scripts/verify.sh quick` is green; `scripts/selftest/temper-cases-56.sh` ends `FAIL: 0`;
  `claude plugin test .`, `tsc -p tsconfig.mod.json` and `bash scripts/check-mod-calls.sh` pass with the list of
  calls unchanged; `bun scripts/e2e/run.ts all full-run flagged-map` passes with equal traces, and `flagged-map`,
  `D02b`, `D22a` and `D22b` are off the list; `temper card` at the three states prints the golden files; no
  tracked file is over 256 KiB.
- **Traps:**
  - The plan's sample marks criteria `[your answer]` and prints dollars. No field links a criterion to an answer
    (`scripts/answer_ops.py:54-95` writes only the Decisions row) and the CLI holds no dollars
    (`scripts/flow.py:2761-2762`: time only). Show answers and assumptions in their own sections, no dollars on any
    card, and minutes only: an estimate only from the kept run summaries, never from a table of prices.
  - Never put card text into the question text. The mod counts an answer only on equal header and question text
    (`hooks/temper-mod/core/answers.ts:33, 70-76`), and `add_note` already appends to it (`scripts/flow.py:2348-2358`).
  - The fixtures: `view-fixtures.ts` is 259,060 bytes at the head against a limit of 262,144
    (`scripts/quality-check.sh:21-27`). Each card adds about 2 KB to a view that asks. Rely on the room WP01 made,
    and move views to the second module (`make-view-fixtures.sh extra`) before the first passes the limit.
  - The sensitive path matcher was a bash function at the head (`_glob_touch_match`, `scripts/temper:4008`). WP11
    moved it to `scripts/sensitive.py` (`match`, `declared`). Do not write a second matcher in `card.py`: call
    that module, with one selftest that the card and the commit gate give the same answer.
  - `$.ui.log` draws one row per call and cuts a row at 2,000 characters (`register.tsx:596-600`); a dialog preview
    cannot hold a card (`driver.ts:84-87`). No new host call is needed; `ui.resolve` is on the reviewed list.
  - A flagged Context Map line must be whole on the card: WP13's approving option records the Context answer only
    when every flagged line was shown (`red-safety.md`, M4). Its test reads `total` against the rows of `context`.
    WP13 left the widening of "shown whole" to this package: its fold now holds whenever the card shows every
    flagged line, no longer only under the cuts of the question text, and `flagged-map` (row `D02`) asserts it.
  - The card follows the mode rule of the dim line: drawn in `full` mode only (`register.tsx:916`;
    `tests/mod/modes.test.ts:6` lists `questionHeader` among the elements of a mode). Tests that state the old
    output on purpose: every case that greps `| PLAN:` or calls `panel plan`, and the e2e check of the RCA panel
    (`scripts/e2e/scenarios.ts:642`, which WP17 changes).
  - `scripts/card.py` is a new script: run `bash scripts/validate-directory.sh` before the commit.
- **Size:** L.

## WP16 Hand back kinds: a closed list, the three defects, a failure stays in the driver

- **Goal:** With the mod, a run leaves the driver only for a step on a closed list of seven kinds, each one step
  the person asked for by an option, and it returns at the person's next command. A failed check, a failed call, a
  typed answer, a scope drift and an unanswered dialog never hand a run to the main session: each becomes the CLI's
  next question or a saved stop. The pass line: a scripted run with one failed group check and one failed
  `integrate` reaches its question with no hand back.
- **Depends on:** WP04 (ids, so the driver selects by id and kind), WP09 (a recorded verdict is no error), WP10
  (a repeat is counted), WP11, WP15.
  Extended later by WP17, which uses `temper spec branch --if-protected` and the driving of an active fix run.
- **Lane:** `flow core` (it edits the flow, `scripts/go.py`, `scripts/spec_ops.py` and the fixtures), with the mod.
- **Touches:** the flow modules (`NEEDS` goes into `scripts/flow_base.py`), `scripts/go.py`, `scripts/spec_ops.py`,
  `scripts/temper` (the `spec`, `group` and `drift` words), `scripts/plan_ops.py`, `hooks/temper-mod/core/driver.ts`,
  `hooks/temper-mod/core/runview.ts`, `hooks/temper-mod/core/answers.ts`, `hooks/temper-mod/core/rules.ts`,
  `hooks/temper-mod/register.tsx`, `commands/temper.md`, `commands/fix.md`, `agents/build.md`, `agents/fix.md`,
  `scripts/selftest/temper-cases-8.sh`, `scripts/selftest/temper-cases-57.sh` (new), the fixtures,
  `scripts/e2e/scenarios.ts`, `scripts/e2e/loop.ts`, `tests/mod/driver.test.ts`, `tests/mod/driver-wiring.test.ts`,
  `tests/mod/answers.test.ts`, `tests/mod/view.test.ts`, `tests/mod/audit.test.ts`, `docs/mod.md`, `docs/flow.md`,
  `scripts/caps.json`, `scripts/selftest/expected-fail.txt`, `docs/plans/one-go/changed-tests.md`, `CHANGELOG.md`.
- **Tests first:**
  1. `tests/mod/driver.test.ts`, one case per former cause:
     - `a typed answer at a gate runs the typed calls`: the driver fills `{text}`, runs them, and goes on; the end
       is never `handback`.
     - `Cancel at the accept question asks the gate question again` (today the end is `chose Cancel`).
     - `nobody answered ends as saved`: a null answer at the gate, the reason, the name and a Blocking question
       each give `done`.
     - `a failed before call ends as saved with the CLI's FAIL line`; the same for `state init`, a step and a
       Blocking answer call.
     - `a bound ends as saved with its reason`: question depth, 120 waits, the same after calls, 300 turns.
     - `an option whose needs kind is on the list hands back that kind and the option id`, one case per kind.
     - `a needs kind that is not on the list ends as saved`, never a hand back.
     - `the Scope drift question is the CLI's`: the driver asks it as any question and runs the option's call.
     - `broken asks the restart question`.
  2. `tests/mod/view.test.ts`: `parseRunView` on the fixture that holds a Context check gives a `contextCheck` that
     is not null (defect 1). `tests/mod/answers.test.ts`: a typed Context check answer of 1,500 characters counts,
     one of 2,001 does not (defect 2).
  3. `tests/mod/driver-wiring.test.ts`: `/temper:fix` with no words and a fix run active is driven; a hand back
     note carries `step`, the kind and the option id.
  4. Selftest, in `temper-cases-8.sh` beside the fixture cases (`:455-458`):
     - `no call of the flow is a foreign program`: in every fixture view, every string of every `calls` list (the
       action's, each option's, `more`, `accept`) starts with the CLI's path.
     - `every needs kind is on the closed list`, and no option carries a `do` text without a `needs`.
     - `a gate question carries typed calls`, with the `state redo` call only at Intent, Plan, Design, Build and Fix.
  5. Selftest, `scripts/selftest/temper-cases-57.sh` (new): `spec branch --carry` does what the shell line of
     `carry_switch` did (the spec files cross the switch; a refused switch puts them back and fails);
     `group take-out` removes only the newest commits it is given; `drift ask` refuses a path of the plan; a pending
     drift gives the Scope drift question with its three options and their calls; all answered gives the agent again
     with one `Drift decision:` line per file; an unattended run with a pending drift asks and never moves by rule.
  6. `scripts/e2e/scenarios.ts`: a new scenario `failed-checks` (one group check fails once, then `integrate`
     fails once): in `driver` mode the trace has no hand back and ends `driver done`; in `plain` and `mod` mode the
     same questions are asked. `prAndPipeline` (the scenario `pr-and-pipeline`) in `driver` mode hands back exactly
     the kinds `pull-request` and `pipeline-fix`. That `fixRun` (the scenario `fix`) in `driver` mode started on
     `main` ends on `fix/bug` (defect 3) is left to WP17, whose approving option makes the branch call.
  7. `scripts/caps.json` gets the key `handback_kinds`, exactly 7, which `scripts/check_caps.py` counts from
     `NEEDS` in `scripts/flow_base.py`: the checker names no file of the mod.
  8. From `scripts/selftest/expected-fail.txt`: the scenarios `group-fail` and `group-fail-twice` of
     `scripts/e2e/accept.ts` (row `D06`) pass and leave the list here.
- **Mechanism:**
  1. **The closed list.** A set `NEEDS` beside `MOVES` (`scripts/flow.py:58-59`; both are in `scripts/flow_base.py`
     since WP03); `opt()` (`:459-481`) takes `needs=` and refuses a kind that is not in it, as it refuses a move
     (`:460-461`). The `do` sentence stays as the words for a person or a model; the driver never reads it. Three
     kinds are navigation and stay inside the driver: `more` (`:498, 513, 946`), `accept` (`:778, 801, 1061`),
     `cancel` (`:1088`). Seven are the hand back kinds. Each is one step the conversation does, then it stops:

     | Kind | The option or step today | Who does the one step |
     |---|---|---|
     | `talk` | Grill Me and Teach Me (`scripts/flow.py:487-490`), the Design walk through (`:704-705`) | the conversation, with the person |
     | `html-review` | Open and Share HTML review (`scripts/flow.py:643-646`) | the conversation: it renders or publishes the page and applies the comments |
     | `depth-review` | Architecture Depth Review (`scripts/flow.py:769-770`) | the conversation |
     | `config-suggestions` | Review config suggestions (`scripts/flow.py:819-820`) | the conversation, one question per suggestion |
     | `small-change` | Make a small change (`scripts/flow.py:905-913`) | the conversation, inside the window `adhoc open` opened; WP24 gives a finding's repair to an agent |
     | `pull-request` | the pull request steps after the commit (`scripts/flow.py:2209-2217`) | the conversation |
     | `pipeline-fix` | the steps of Apply the fix and push (`scripts/flow.py:1026-1033`) | the conversation |

     No kind gets a new agent (the cap of 13 briefs holds). In two former causes an agent the flow already launches
     does the work: a typed change request goes to the stage's agent, and a drift answer goes back to the Build or
     Fix agent that asked.
  2. **What disappears**, by the causes of `v-mod-driver.md`, section 2 (31 sites of `handback(` in
     `hooks/temper-mod/core/driver.ts`):

     | Cause today | Sites in `driver.ts` | After |
     |---|---|---|
     | a recorded verdict read as an error: `temper go` says `error`, an after call, a call of the answer | `:352`, `:432`, `:319` with the rule at `:261` | gone with the marker of WP09; the driver reads the marker in one helper, and the text patterns of `:80-82` and `:261` go |
     | a call that is not the CLI's (exit 126, `register.tsx:476-477`) | the calls of `scripts/flow.py:629, 631, 1818`; `driver.ts:502` | the CLI does it: step 3 |
     | a step that is no call: raw `git add` and `git commit` | `:214-217`, `:295`, `:440-441`, `:452`; `scripts/flow.py:2206-2208` | the CLI does it: step 4 |
     | the person typed an answer at a gate | `:288` | the CLI does it: step 5 |
     | Group "Change" and Context check "Something else" | `scripts/flow.py:1944-1946, 2319-2320` | the CLI does it: a typed answer fills the call, step 6 |
     | Cancel in the accept question | `:291-296`; `scripts/flow.py:1088` | the driver asks the gate question again |
     | a placeholder the driver cannot fill; no name after three tries | `:318`, `:316` | no call of the flow holds `{K}` or `{text}` outside a typed question (step 6); the name question is asked until Cancel |
     | an agent's answer lists DRIFT rows | `:221`, `:425`, `:437` | the CLI asks: step 7 |
     | nobody answered | `:286`, `:300`, `:310`, `:382` | a saved stop (`done`) |
     | a call failed: before call, no agent started, `state init`, a step, a Blocking answer | `:346`, `:384`, `:421`, `:435`, `:323`, `:448`, `:494`, `:499` | a saved stop that shows the CLI's own FAIL line |
     | bounds and defects | `:284`, `:359`, `:362`, `:458`, `:338`, `:392`, `:456`, `:484`, the throw at `:142-145` | a saved stop with the reason; `broken` asks the `restart` question (id `run.restart`) that `go.py` already passes (`scripts/go.py:77-78`) |
     | `/temper:fix` while a run is active | `:489` | an active fix run is taken up; another request asks the `restart` question |
     | an option with a `do` text | `:294-296` | only the seven kinds |

  3. **Foreign calls become CLI words** (in `scripts/spec_ops.py:25-39` and its dispatch, `scripts/temper:5037-5042`):
     `temper spec branch --carry NAME` (the steps of `carry_switch`, `scripts/flow.py:547-555`, in Python: copy the
     spec folder to a temp folder, restore it, switch, copy back; on a refused switch copy back, fail and name the
     folder), `temper spec branch --if-protected` (for a fix run: on `main`, `master` or the default branch switch
     to the run's branch, on any other branch record that branch as the run's and switch nothing), and
     `temper group take-out G SHA...` (the rebase of `scripts/flow.py:1818`, with its two conditions checked again
     inside the call). The branch clash options moved with WP12 to the approval (`plan.approve`). There the
     approving options carry `spec branch --carry NAME` in the place of the raw switch. No option that is not an
     approving one may make or switch a branch before the approval (rule 1 of `docs/plans/one-go/README.md`
     section 6): WP12 left `Build on a new branch` with the one call `state set branch <new>`, and it keeps that
     call. It records the name, and the approving option makes the branch through `spec branch`. So the raw
     checkout of `scripts/flow.py:631` went with the branch clash question, and no CLI word takes its place: a
     word that makes a new branch would have no caller once no branch is made before the approval.
  4. `record_steps`, the branch with no file list (`scripts/flow.py:2206-2208`): the same `spec commit` call with
     the lesson file, or the no record note of `:2190`. Steps become typed where WP04 left them as text: the
     report step (`scripts/flow.py:2145-2146`) and the note are kinds, so `stepPlan` stops matching English
     (`driver.ts:212-218`).
  5. **Typed text at a gate.** Every gate question gets `typed`: `{"calls": [...], "again": true}`. The calls are
     the page's rule (`commands/temper.md:154-162`) as CLI calls with `'{text}'`: the note
     (`evidence add --stage S --phase note --kind input --claim '{text}'`), and at Intent, Plan, Design, Build and
     Fix also `state redo S --reason '{text}'`, only while the budget of WP10 has room. `again` is true where the
     same question is asked again after the calls (Review, Check, Commit, and any stage at the budget's limit) and
     false where the redo sends the stage's agent. `scripts/go.py`, `slim` (`:44-55`), passes `typed` and `needs`.
     The driver, where it hands back today (`driver.ts:288`): fill with `fill()` (`:205-207`), run, go on. A typed
     text is a change request by rule; a person who wants to talk interrupts and types.
  6. **Typed fills.** Group "Change" becomes an option with a typed question (the `answer=` form of `opt()`,
     `scripts/flow.py:463-468`) and one call, `temper group feedback G --text '{answer}'`, which records the
     feedback row and its number; the next action asks "Which task changes?" with the number already in the calls.
     Context check "Something else" becomes the same form with the question's own `answer` call
     (`scripts/flow.py:2327`). The driver already asks a typed question (`driver.ts:307-317`).
  7. **Scope drift is the CLI's question.** The agent records what it needs with
     `temper drift ask --path P --why W --change C` (a row in the stage's ledger) and returns. In `core_next`, for
     Build and Fix, before the gate question and before any launch: a drift row with no answer gives an `ask`
     (question id `scope.drift`) with header `DRIFT_HEADER`, a first line `DRIFT_PREFIX` and the path, the `Why:` and
     `Change:` lines, and the three `DRIFT_OPTIONS` (`scripts/flow.py:43-45`), each with move `drift` and the record
     call the page writes today (`commands/temper.md:183-185`). With all answered, the same agent is launched again
     with one `Drift decision:` line per file. It is never an `auto` action. Briefs: `agents/build.md:82, 109, 136`
     and `agents/fix.md:44-49, 90` name the call in place of the `DRIFT` section. `hasDrift` goes.
  8. **The driver's ends.** `DriveEnd` (`driver.ts:48`) keeps two kinds. `handback` carries `{kind, option}` and is
     returned at one site, for an option or a step whose `needs` kind is one of the seven. Everything else of the
     table in step 2 returns `done` with a text that says what stopped and that `/temper:temper` takes the run up.
  9. **The return.** `register.tsx:583-586`: the note says `step KIND OPTION`. `commands/temper.md:24-28, 43` and
     `commands/fix.md:40-43`: after that one step, end the turn with the line `Type /temper:temper to go on.` (or
     `/temper:fix`). The driver takes up an active run on the bare command (`register.tsx:617`). A fix run is
     refused in two places today: `drives` returns null for it (`register.tsx:613`), and the fix path drives only
     with no run active (`:730`). With no words and a fix run active, both now call `driveSteps(cli, null)`.
  10. **The three live defects.**
      - A typed Context check answer is refused: the CLI writes `context_check.question` as an object
        (`scripts/flow.py:2340-2341`; `temper-cases-15.sh:202` reads it so), and `contextCheck` reads it as the text
        (`hooks/temper-mod/core/runview.ts:132-137`), so `view.contextCheck` is always null. Read the text and the
        options from the object.
      - The typed answer limit is 100 characters (`hooks/temper-mod/core/answers.ts:81`) against the CLI's 2,000
        (`MAX_ANSWER`, `scripts/plan_ops.py:28, 131`). Make it 2,000.
      - A driven fix run gets no branch: `driver.ts:502` is a shell line, `hostRun` answers it with exit 126
        (`register.tsx:476-477`) and the driver ignores the result. The line goes here, and this package builds
        `temper spec branch --if-protected`; putting that call on the approving option of the fix run is left to
        WP17.
- **Removed:** `hasDrift` and its two uses; `taskVerdict` and the `-> FAIL` matches once WP09's marker is read;
  `carry_switch`; the `git` strings of `scripts/flow.py:631, 1818, 2207-2208`; the hand back words `next` and
  `discuss` (`commands/temper.md:25-28, 42`; `register.tsx:580-586`); the DRIFT bullet of `commands/temper.md:180-187`
  and the branch lines of `commands/fix.md:67-68`; `{K}` and `{text}` in option calls.
- **Documents in the same change:** `docs/mod.md` (what the driver carries, the seven kinds, the return);
  `docs/flow.md` (`needs`, `typed`, the drift ask, the new CLI words); `commands/temper.md` and `commands/fix.md`;
  `scripts/caps.json`; `CHANGELOG.md`; `docs/plans/one-go/changed-tests.md` (each test of the base that changed).
- **Done when:** `bash scripts/verify.sh quick` is green; `claude plugin test .`, `tsc -p tsconfig.mod.json` and
  `bash scripts/check-mod-calls.sh` pass with no new call; `grep -c "handback(" hooks/temper-mod/core/driver.ts`
  prints at most 3 (the helper and the one site for options and steps); `bun scripts/e2e/run.ts all` passes
  `failed-checks` with no hand back, `pr-and-pipeline`, `fix`, `group-fail` and `group-fail-twice`, and the last
  two are off the list; `python3 scripts/check_caps.py` exits 0 with `handback_kinds` at 7; the fixtures are
  regenerated and under the limit.
- **Traps:**
  - A question with the header `Scope drift` matches twice in `answersIn`: as a gate option
    (`hooks/temper-mod/core/answers.ts:70-76`) and as a drift answer (`:111-119`). Keep the drift branch as the one
    reader (the write rule of `rules.ts` reads its choice) and let the gate branch skip that header.
  - `state set branch` is a person only call (`hooks/temper-mod/core/rules.ts:486`), and
    `tests/mod/audit.test.ts:76` wants a question that offers each such call: the option `Build on a new branch`
    of the approval (WP12) is that question. Add no `spec branch` word that makes a new branch: the branch clash
    question that held the raw checkout at the head went with WP12, and before the approval no option may make a
    branch (step 3).
  - The driver's calls run by `$.process.spawn`, which is no tool call, so no guard rule sees them. What keeps
    them the person's is that the driver runs an option's calls only after the answer; keep that order.
  - Way back to the driver rests on the model stopping after one step. The session guard holds it meanwhile; do
    not add `command.run` or any other host call for the return (`v-mod-driver.md`, section 3, way C).
  - The e2e loop and many mod tests select options by label (`scripts/e2e/loop.ts`, `tests/mod/dialog.test.ts`);
    move a test to ids only where its question changes.
  - `state redo` from a typed text counts in the budget whoever typed (`red-safety.md`, M8). At the limit the
    `typed` calls hold the note only, and the question shows the count.
  - A saved stop must not read as success: its text starts with what stopped. An interrupt keeps its own text
    (`STOPPED`, `driver.ts:52-53`).
- **Size:** L.

## WP17 `/temper:fix` asks twice; the checks run beside Review; TRIVIAL is a recorded verdict

- **Goal:** A clean bug run asks twice: the root cause with the fix it proposes, then the commit. Its checks start
  beside Review, as a feature run's do. A trivial request is a verdict the CLI records, with a size bound the commit
  hook holds with the mod off.
- **Depends on:** WP05 (the kept run summary), WP09, WP10 (the one budget replaces `fix.max-loops`,
  `scripts/loop_step.py:20-32`), WP11 (the run goes on by itself; the commit question), WP12 (the binding to what
  was shown), WP15 (the cards), WP16 (the fix branch call, an active fix run is driven, typed text).
- **Lane:** `flow core`.
- **Touches:** the flow modules, `scripts/card.py`, `scripts/panel.py`, `scripts/trivial.py` (new),
  `scripts/approval.py` (the row and the check take `rca.md` in a fix run), `scripts/run_summary.py` (the line of kind
  `trivial`), `scripts/temper` (`cmd_intent`, the no run branch of `gate_commit`, `state init`), `agents/intent.md`,
  `agents/rca.md`, `commands/temper.md`, `commands/fix.md`, `hooks/temper-mod/core/driver.ts`,
  `hooks/temper-mod/core/rules.ts`, `hooks/temper-mod/register.tsx`, the fixtures (`fix-rca` and new fix states),
  `scripts/selftest/temper-cases-58.sh` (new), `scripts/e2e/scenarios.ts`, `tests/mod/guard.test.ts`,
  `tests/mod/commit-hook.test.ts`, `tests/mod/driver.test.ts`, `docs/flow.md`, `docs/mod.md`, `reference/fix.md`,
  `scripts/e2e/floor.json`, `scripts/selftest/expected-fail.txt`, `docs/plans/one-go/changed-tests.md`,
  `CHANGELOG.md`.
- **Tests first:**
  1. Selftest, `scripts/selftest/temper-cases-58.sh` (new), names start with `fix:` or `trivial:`:
     - `fix: the root cause question is the approval`: the question id is `rca.approve`, and its first option,
       `approve-run`, carries in this order `spec branch --if-protected`, `state set run_mode autonomous` (the
       call of WP11 that starts the unattended run) and `state advance rca_complete fix` with
       `--shown rca.md=<digest>`; its card is of kind `approval` with the sections of step 2.
     - `fix: the approval is of what was shown`: `rca.md` edited after `next` printed the question makes the
       advance fail.
     - `fix: no branch and no commit before the approval`: after `state init --command fix` and the root cause
       agent, `git branch --show-current` and `git rev-parse HEAD` are what they were.
     - `fix: a passed Fix, Review and Check move on by rule`, and `next` stops at the commit question with a commit
       card whose `message` row is the text of `fix_message`.
     - `fix: Review starts Check's run`: the Review agent's `before` holds `check ahead` in a fix run.
     - `fix: the run asks at every stage when the person picked that`: the four questions of today, in order.
     - `fix: no pull request option at the commit`.
     - `trivial: the verdict is recorded`: `temper intent trivial --why TEXT` at Intent, step 0, no spec file,
       writes the record with the request and HEAD; it is refused at any other stage and once `intent.md` exists.
     - `trivial: the flow closes the run`: the next action is the CLI's own `intent trivial --close`; after it no
       run is active, the kept run summary has one line of kind `trivial`, and `next` says so in one line.
     - `trivial: the commit hook holds the bound`: with the record and HEAD unchanged, a staged change of one
       production file and 10 lines passes `gate commit`; 11 lines fail; two production files fail; a test file
       beside the one file passes; the FAIL row names `/temper:temper`.
     - `trivial: the record is spent`: after one commit, or after `state init`, a large commit passes as any
       commit with no run does.
     - `trivial: work that was there before is not counted`: a file that was dirty at the verdict does not count.
  2. `scripts/e2e/scenarios.ts`: `fixRun` (the scenario `fix`) asks 2 dialogs in all three modes and ends with its
     commit on `fix/bug`, in driver mode too (defect 3 of WP16); a new scenario `trivial` (the Intent agent calls the
     verdict, changes one line, returns) asks 0 dialogs and ends with no run and an uncommitted one line change, the
     same in all three modes.
  3. `tests/mod/guard.test.ts`: while the trivial window is open the Intent agent may write a project file; with
     it closed the write is refused as today; `state clear` at Intent is no longer let through for an agent or the
     session. `tests/mod/driver.test.ts`: `fixSteps` runs no shell line and passes `--feature`.
  4. `scripts/e2e/floor.json`, the entry `fix`: `dialogs` of a clean scripted bug run is 2 (today 4) and
     `launch_total` is 3 (row `D03`).
  5. From `scripts/selftest/expected-fail.txt`: the scenario `fix-two` of `scripts/e2e/accept.ts` (row `D03`) and
     `D25` of `scripts/selftest/temper-cases-46.sh` pass and leave the list here.
- **Mechanism:**
  1. **Question one, the approval.** `ask`, the branch for `rca` (`scripts/flow.py:616-619`), with the question id
     `rca.approve`. Its text:
     `RCA: the root cause and the proposed fix are on the card. Approve the fix?` Options, four at most:

     | Option | Move and calls |
     |---|---|
     | `Approve and fix (Recommended)`, id `approve-run` | the move `arm`, which WP11 gives the first option of the plan question; calls: `spec branch --if-protected`, `state set run_mode autonomous` (WP11), `state advance rca_complete fix --shown rca.md=<digest>` (the argument of WP12) |
     | `Change something` | typed (WP16): the note at stage `rca`, then the root cause agent runs again with it |
     | `Ask me at every stage`, id `ask-every-stage` | `approve`; the branch call and the advance, no arming: the four questions of today |
     | `Save for later`, id `save` | `pause` |

     Under `run.default: ask` the first and third trade places, and under `never-unattended` the arming option is
     not offered, exactly as WP11 does for the plan question. `rca.md` is bound by the mechanism WP12 built for the
     plan: the digest on the advance call, and its one row with `rca.md` in the place of `intent.md` in a fix run.
     No second mechanism.
  2. **Its card** (kind `approval`, built in `scripts/card.py` when `run.command` is `fix`), sections in order:
     `request` (the bug as typed: pass `--feature` at `state init`, which a fix run does not do today,
     `driver.ts:499`, `commands/fix.md:61`), `cause` (CAUSE, AT, CONFIDENCE, SINCE, CHAIN), `fix` (FIX), `test`
     (TEST, with the note that it is written first and must fail before the fix), `files` (the file of AT, the
     Blast radius and Read first items, and the note that the fix may change these and its test and that any other
     file asks first, `agents/fix.md:44-49`), `commands` (the test command the CLI found, `cli_check`,
     `scripts/flow.py:1551-1556`, word for word), `risk` (a sensitive path among the files; a LOW confidence). The
     fields are read by the one reader of `rca.md` (`RCA_FIELDS`, `scripts/panel.py:201-224`), which `card.py`
     imports. The foot names the branch the click makes and ends `Nothing is pushed.`
  3. **In between.** Apply WP11's rule to the fix sequence (`SEQ`, `scripts/flow.py:47-48`): a passed Fix, Review
     and Check move on as the CLI's own action; today the armed path leaves out `rca`, `review` and `check`
     (`scripts/flow.py:2441`) and the policy covers only a feature run's Review and Check (`:2468`). A failed check
     follows WP11 and WP10 as in a feature run, with `BACK_TO["fix"]` (`:54-55`) as the one counted loop.
  4. **Question two, the commit.** The commit question of WP11, in a fix run with the options
     `Commit (Recommended)`, `Loop back to Fix` (as `scripts/flow.py:2266-2268`) and `Save for later`; never a pull
     request (`pr_options`, `:891`). Its card (kind `commit`): `regression` (the RED and the GREEN run of the
     regression test, both made by the CLI, `agents/fix.md:24-28`, and the regression proof row,
     `scripts/check_run.py:741-745`), then `suite`, `coverage`, `planted_bugs`, `review`, `files`, `rule_log`,
     `skips`, `tree`, `run`, `message` (`fix_message`, `scripts/flow.py:2153-2174`) as in WP15.
  5. **The checks beside Review.** `stage_work`, `scripts/flow.py:1375`: drop `r.command == "temper"` from the
     condition, keep `self.cli_check()`. Nothing else is needed: `check ahead` already passes the run's command
     (`scripts/temper:4951-4955`), `check_run.ahead` runs the regression proof for a fix
     (`scripts/check_run.py:780-801` and `:741-745`), the planted bugs run in a copy (`:372-379`), the proof in a
     temp worktree (`:416-421`), and `adopt` compares a digest that includes uncommitted content
     (`:757-772, 805-829`), which a fix run's tree is.
  6. **Before the run exists.** `fixSteps` (`hooks/temper-mod/core/driver.ts:480-504`) and `commands/fix.md:33-68`
     keep launching the root cause agent first. Changes: `state init S --command fix --feature BUG`; no
     `panel rca` print (`driver.ts:497-498`, `commands/fix.md:56-60`; the card shows the fields); no branch line
     (`driver.ts:502`, `commands/fix.md:67-68`). `Change something` at the root cause question is the flow's: with
     a note at stage `rca` that no launch has taken yet, `core_next` (`scripts/flow.py:2390-2392`) gives a `work`
     action with the root cause agent, the prompt of `rcaPrompt` (`driver.ts:470-476`) with the bug from
     `state.feature` and the note, and the after call `usage add`. The count of notes taken is kept in the run
     state, as `record_pass` keeps its round (`scripts/flow.py:2416-2418`). This replaces the page's own rule
     (`commands/fix.md:79-81`).
  7. **TRIVIAL, the verdict.** `temper intent trivial --why TEXT`, dispatched in `cmd_intent` before its check that
     `intent.md` exists (`scripts/temper:4437-4441`), logic in `scripts/trivial.py`. It is refused unless the run is
     a `/temper:temper` run at Intent, at step 0, with no `intent.md`, `plan.md`, `tasks.md` or `design.md` (the
     facts of `scripts/flow.py:2833-2834`). It writes into the run state `trivial: {why, head, at, dirty_before}`
     (`dirty_before` is the list of paths with uncommitted changes at that moment) and prints one line. The Intent
     gate already passes with no `intent.md` (`scripts/temper:2038-2039`).
  8. **Who makes the change.** The Intent agent, in the same turn, after the call returned OK: at most one
     production file and 10 changed lines, then the project's tests, then it returns one line. It is the only
     model both carriers have at that point (with the mod no model runs in the main session), and no launch is
     added. `agents/intent.md:17-20, 169-170`: the call in place of the word, then the change. With the mod, the
     write is allowed only while the window is open: `guard.trivial_exit` (`scripts/flow.py:2833-2834`) keeps its
     name and now means that the state holds `trivial`; `rules.ts`, the `intent` case (`:255-262`), allows a write
     outside the spec folder while it is true.
  9. **The flow closes it.** In `core_next`, first for a run whose state holds `trivial` and whose Intent verdict
     is recorded: `{"action": "auto", "calls": ["temper intent trivial --close"]}`. The call writes
     `.temper/trivial.json` (`{request, why, head, at, dirty_before, bound: {files: 1, lines: 10}}`), appends one
     line of kind `trivial` to the kept run summary of WP05 (`.temper/runs.jsonl`, through
     `scripts/run_summary.py`), and clears the run as `state clear` does
     (`scripts/temper:1435-1453`), keeping that one file. With no run active and a record whose `head` is HEAD,
     `next` says that no run is active, that the last request was trivial with its reason, that the change is not
     committed, that the commit is the person's, and that the commit hook holds it to one file and 10 lines.
  10. **The bound, in the commit hook.** `gate_commit`, the branch for no active run (`scripts/temper:4055-4064`):
      when `.temper/trivial.json` exists and its `head` is HEAD, count the staged change outside `.temper/`,
      leaving out the paths of `dirty_before`: files that are not tests by the gate's own pattern
      (`scripts/temper:4174`), and added plus removed lines over all counted files (`git diff --cached --numstat`).
      At most 1 file and 10 lines: the row `trivial exit` passes and names the file and the lines. More: it fails
      with a detail that gives the counted files and lines, the bound, and the two ways on: commit the trivial
      change alone, or start `/temper:temper` with the request for it. A record whose `head` is not HEAD is spent:
      the gate ignores it, and `state init` and the view writer remove it.
- **Removed:** the TRIVIAL bullet of `commands/temper.md:176-179` (the page does nothing for it; `temper go` ends
  with `none` and its `say`); the `TRIVIAL` return word of `agents/intent.md:169-170`; the mod's `state clear`
  allowance (`rules.ts:48-50, 463-464`; `register.tsx:440-441, 459, 798-803`); `temper panel rca` in the page and the
  driver (the word stays in the CLI); the key `fix.max-loops` with WP10.
- **Documents in the same change:** `commands/fix.md` (two questions, no panel, no branch step); `reference/fix.md`;
  `docs/flow.md` (the fix questions; `guard.trivial_exit`, `:279`; the word `intent trivial`); `docs/mod.md:259-261`
  (the TRIVIAL paragraph: the verdict is a CLI record, the change is bounded by the commit hook); `agents/rca.md:29-31`
  (the person approves the fix on the card); `CHANGELOG.md`; `docs/plans/one-go/changed-tests.md` (the two
  assertions of the first trap). The README sentence that names the exception is left to WP31.
- **Done when:** `bash scripts/verify.sh quick` is green; `scripts/selftest/temper-cases-58.sh` ends `FAIL: 0`;
  `bun scripts/e2e/run.ts all` passes `fix` and `fix-two` with 2 dialogs and `trivial` with none, traces equal
  between modes; `scripts/e2e/floor.json` says 2 dialogs for `fix`; `fix-two` and `D25` are off the list; the
  mod's three checks pass. Then `bash scripts/verify.sh full` is green: this package ends phase 4
  (`docs/plans/one-go/README.md` section 5).
- **Traps:**
  - `scripts/e2e/scenarios.ts:645` asserts the old question text (`RCA: the root cause is in`) on purpose, and
    `:642` asserts the RCA panel; both change here. The fixture `fix-rca` (`make-view-fixtures.sh:218`) changes.
  - The mod stands aside in a fix run (`hooks/temper-mod/adapter.ts:208`; `commands/fix.md:16-17`): no guard rule
    checks the answer there. The CLI's digest check of step 1 is what binds the approval, with the mod and without.
  - `to_branch()` (`scripts/flow.py:527-533`) would move a person who started the fix on their own feature branch
    onto a new `fix/` branch. Use `spec branch --if-protected`, which keeps today's rule (off `main` and `master`
    only, `commands/fix.md:67-68`) and drops its condition on the git pack, so WP30 can decide that pack freely.
  - The Fix agent does not commit, so the tree is dirty through Review and Check, and the reuse store has no key
    for it (`result_key`, `scripts/run_env.py:131-139`). `check ahead` is the one reuse a fix run gets; do not
    route it through the store here. WP22 owns the digest.
  - The Review agent may run tests while the background suite runs in the same folder (a known hazard of feature
    runs too, `review-check-commit.md`, section 3.4). Do not solve it here; WP22 does.
  - The bound is a constant in `scripts/trivial.py`, with no config key: a key would let a project raise it.
    `scripts/caps.json` has no key for it (`docs/plans/one-go/contracts.md` section 12).
  - If WP12 kept its classic hook (`scripts/guards/hold_before_approval.py`), that hook refuses a project file
    write before the approval with the mod off. The one write of a trivial request is such a write: let the hook
    pass it while the run state holds `trivial`, as step 8 lets the mod pass it, and add that case beside the
    hook's case in `scripts/selftest/temper-cases-53.sh`. A fix run is outside that hook (WP12 step 9), so the
    fix path needs nothing for it.
  - `.temper/trivial.json` is a new run file that can turn a gate row. The three duties of
    `docs/plans/one-go/contracts.md` section 3 come with it: its name in `_RUN_FILES`, what `state clear` does
    with it (step 9 keeps it), and the mod's guarded list with a test in `tests/mod/guard.test.ts`.
  - After the verdict the run is still active until the flow closes it. Do not clear it inside
    `intent trivial`: the Intent agent's after calls (`usage add`, `gate intent`) would fail, and a failed after
    call ends the drive.
  - The trivial change is never committed by the CLI or by a rule (rule 4). The page and the driver only say it.
- **Size:** L (M for the fix run, M for TRIVIAL).

## WP18 Two holes: `evidence resolve` checks its commit; Review's completion row names the files read

- **Goal:** A finding is marked resolved only for a commit the CLI made after Review read the code, and a Review
  that did not read every changed file does not pass. Both hold in the CLI with the mod off, and both land before
  the default run stops asking at Review.
- **Depends on:** WP02 (room in `scripts/temper`), WP03 (the flow modules), WP04 (the ids), WP07 (the checks `D34d`
  and `D37a` and the expected to fail list), WP10 (the budget that counts a second Review).
  Extended later by WP11 (it changes the default, so this package is built before it), by WP15 (the commit card
  shows `N of N files read`) and by WP24 (the recheck condition and the repair commit).
- **Lane:** `flow core` (it edits `scripts/temper` and the fixtures).
- **Touches:** `scripts/temper` (`cmd_evidence_resolve`, `cmd_evidence_add`, `gate_review`, one word
  `review files`), `scripts/findings.py`, the flow modules (the Review question and its launch),
  `agents/review.md`, `hooks/temper-mod/core/rules.ts`, `scripts/selftest/temper-cases-59.sh` (new),
  `scripts/selftest/case-helpers.sh`,
  `scripts/selftest/case-helpers-5.sh`, `scripts/selftest/temper-cases-1.sh`, `temper-cases-2.sh`,
  `temper-cases-5.sh` and the other case files that write the completion row, `scripts/selftest/make-view-fixtures.sh`
  and the fixtures, `scripts/e2e/scenarios.ts`, `scripts/e2e/replay.ts`, `scripts/e2e/pyjokes.ts`,
  `tests/mod/review-exploits-3.test.ts`, `tests/mod/security-round2.test.ts`, `tests/mod/run-files.ts`,
  `docs/flow.md`, `docs/trust.md`, `reference/review.md`, `scripts/selftest/expected-fail.txt`,
  `docs/plans/one-go/changed-tests.md`, `CHANGELOG.md`.
- **Tests first:**
  1. Selftest, in the new file `scripts/selftest/temper-cases-59.sh` (the resolve cases of the base are at
     `temper-cases-1.sh:72-77`; see test 5 for what goes where):
     - `evidence resolve refuses a text that is no commit`: `--fixed-by 'no such commit'` exits 1 and the Review
       gate stays FAIL (the run of `v-repair-in-place.md`, X1).
     - `evidence resolve refuses a commit Review already read`: the reviewed HEAD itself, and any ancestor of it.
     - `evidence resolve refuses a commit the CLI did not make`: a commit made by hand after Review started.
     - `evidence resolve refuses a commit that is not on this branch`.
     - `evidence resolve refuses when the run has no Review snapshot`.
     - `evidence resolve takes a commit the CLI recorded after the reviewed HEAD`, and stores the full id.
     - the cases that only need a resolved finding (`temper-cases-2.sh:734-735`, `temper-cases-5.sh:1074, 1397, 1405`,
       `case-helpers-5.sh:461, 784, 792`) use one new helper of `case-helpers.sh` that makes such a commit.
  2. Selftest, a second block of the same new file, for the Review gate:
     - `review completed fails when a changed file was not read`: 14 changed files, a completion row that names 2:
       the row fails with `read 2 of 14 changed files; not read:` and the first names.
     - `review completed passes when every changed file is named`, with the detail `read 14 of 14 changed files`.
     - `review completed fails on a row with no read list` when files changed.
     - `a deleted file and the run's own state are not asked for`.
     - `the narrow Review after a small change is held to the window's files`.
     - `temper review files prints the set the gate compares`.
     - `the question after a short Review recommends Run Review again`, and the launch names the unread files.
  3. `tests/mod/review-exploits-3.test.ts` and `tests/mod/security-round2.test.ts`: `evidence resolve` typed by an
     agent or the session is refused; it moves out of their lists of calls any agent may make (`:106` and `:26`).
  4. `scripts/e2e/scenarios.ts`: the scripted reviewer records its completion with the files that
     `temper review files` prints; one new step in `fullRun` where it names one file fewer and the Review gate
     fails. `scripts/e2e/replay.ts` stops calling `evidence resolve` in its Build agent (`:263`).
  5. From `scripts/selftest/expected-fail.txt`: `D34d` of `scripts/selftest/temper-cases-44.sh` and `D37a` of
     `scripts/selftest/temper-cases-45.sh` pass and leave the list here. `D34d` asserts the row `review completed`;
     no row is added. `D37b`, `D37c` and the scenarios `repair-finding` and
     `repair-worse` (`D37d`, `D37e`) stay listed until WP24. New cases go into
     `scripts/selftest/temper-cases-59.sh`, with state builders of their own. Files 1, 2 and 5 are edited only
     where an assertion of the base changes, each listed in `docs/plans/one-go/changed-tests.md`. After an edit of
     file 5: `bash scripts/selftest/make-helpers-5.sh > scripts/selftest/case-helpers-5.sh`, then
     `TEMPER_CASES_ONLY="6 31"`, and run `quick` as a background command: file 5 alone takes 13 minutes.
- **Mechanism:**
  1. **The check `evidence resolve` makes.** In `cmd_evidence_resolve` (`scripts/temper:1617-1663`), before the
     lock, one call of a new function in `scripts/findings.py` that returns the full commit id or the reason. All
     four must hold:
     1. `--fixed-by` names a commit (`git rev-parse --verify --quiet X^{commit}`);
     2. it is an ancestor of HEAD (`git merge-base --is-ancestor`, as `scripts/task_ops.py:538`);
     3. it is not an ancestor of the reviewed HEAD, the `head` of `review_snapshot` in the run state, which the CLI
        writes when the run enters Review (`scripts/temper:3794`, called at `:1037, 1469, 4619`); with no snapshot
        the call is refused;
     4. the CLI recorded it as its own: it is in `cli_commits` of `.temper/groups.json` (written at
        `scripts/group_fix.py:91` and `scripts/temper:2756, 3238, 3259`; read the same way by `known_shas`,
        `scripts/task_ops.py:279-282`).
     Each refusal is one `FAIL:` line that names which of the four failed and both short ids. The stored mark is
     `resolved: {fixed_by: FULL_ID, ts}`. At the head no commit can meet 3 and 4 together (the commit hook refuses
     a commit at Review), so until WP24 records its repair commit in `cli_commits` the call always refuses. That
     is the point: a finding then ends by the person's accept or by a loop back and a second Review, as the plan's
     release 2 has it. WP24 adds the fifth condition (a recheck row written after the commit).
  2. **With the mod**, `evidence resolve` is never a tool call: a rule of its own in `rules.ts`, beside the line
     for `accept` and `clear` (`:489`), denies it for the session and for every agent. Do not add it to
     `personOnly`: `tests/mod/audit.test.ts:76` wants a question for every person only call, and no question
     offers this one. WP24 calls the function inside the CLI, which no guard sees.
  3. **The completion row names the files read.** `cmd_evidence_add` (`scripts/temper:1513-1577`) takes
     `--read FILE`, any number of times, only with `--stage review` and the claim `review completed`; the row
     stores `read: [paths]`, relative to the project, with a leading `./` taken off.
  4. **The set the gate compares.** One function gives the changed files of the run: the commit gate's own set
     (`_changed_since_base`, `scripts/temper:4150-4155`: since `base_sha`, plus uncommitted and untracked files),
     lifted out of `gate_commit` so both gates call it, minus `.temper/` and `.claude/`, minus files that no longer
     exist. After a small change (`adhoc_done` with a `review` step) it is that window's files.
     `temper review files` prints it, one path a line.
  5. **The gate.** `gate_review`, the completion block (`scripts/temper:3838-3846`): the row `review completed`
     passes only when the latest completion row has exit 0 and its `read` list holds every file of the set. Detail
     on a pass: `read N of N changed files`. On a fail: `read K of N changed files; not read:` and the first
     names, with the count of the rest. No new row: the name `review completed` stays, so the flow's reading of an
     unfinished Review (`scripts/flow.py:793-798`) recommends `Run Review again` for a short reading too, and the
     cap on gate rows does not move. The second launch gets one extra prompt line with the unread files
     (`stage_work`, `scripts/flow.py:1316-1385`), and the repeat counts in the budget of WP10.
  6. **The brief.** `agents/review.md:15-18`: the changed files are what `temper review files` prints, in place of
     the two `git` commands. `:47-52`: the completion command carries one `--read` per file read whole. `:26-28`:
     the gate checks three things, and the stale default of `review.block-on` there (`critical`) becomes the real
     one (`critical,high`, `scripts/temper:3814`).
- **Removed:** the free text form of `--fixed-by` (its usage line says `<commit or note>`,
  `scripts/temper:1617, 1630`); the `evidence resolve` call of the scripted Build agent
  (`scripts/e2e/replay.ts:263`); `evidence resolve` from the two mod test lists of harmless calls.
- **Documents in the same change:** `docs/trust.md` (what resolves a finding; what the completion row proves and
  does not: the reviewer names what it read, the CLI compares the names); `docs/flow.md:166-182` (findings);
  `reference/review.md` (the completion command); the CLI help text of `evidence resolve`; `CHANGELOG.md`;
  `docs/plans/one-go/changed-tests.md` (the resolve cases and the completion rows of the base that changed).
- **Done when:** `bash scripts/verify.sh quick` is green; the command of `v-repair-in-place.md`, X1, run at a
  failed Review, exits 1 and `temper gate review` still prints FAIL:

  ```
  temper evidence resolve --stage review --id 1 --fixed-by 'no such commit'
  ```

  A scripted reviewer that names 2 of 14 files fails the gate; the mod's three checks pass;
  `bun scripts/e2e/run.ts all` passes with the new step; `D34d` and `D37a` are off the list.
- **Traps:**
  - About 38 places in the tests write the completion row by hand (`grep -c "review completed"` over
    `scripts/selftest`, `scripts/e2e` and `tests/mod`). Add one helper to `case-helpers.sh` that records the row
    with the output of `temper review files`, and use it wherever the project has changed files; a project with
    none passes as `read 0 of 0 changed files`.
  - `Run.findings` leaves the completion row out by its exact claim (`scripts/flow.py:402`). Keep the claim text
    `review completed`; put the file list in the `read` field, never in the claim.
  - A run saved by 9.8.5 after its Review has a completion row with no `read` list. Do not pass it for that: a
    model that leaves `--read` out would get the same pass. It fails once and Review runs again. Say so in the
    `CHANGELOG.md` line of this package; the migration note itself is left to WP32.
  - The reviewer's list is still its own claim. The row raises the price of skipping a file from silence to a
    false statement in the ledger; `docs/trust.md` must not say more than that.
  - `scripts/temper` has 1,640 bytes free at the head. Put the two checks in `scripts/findings.py` and call them
    in one line each; WP02 must have landed.
  - The lock test `L2` (`temper-cases-5.sh:1393-1405`) runs six resolves at once to prove the write is atomic: its
    setup needs six findings and one CLI commit that all six may name.
  - The test helper needs a commit after the reviewed HEAD while the run is at Review, where the commit hook
    refuses a code commit. Let it commit one file under the spec folder (the artifact only carve out,
    `scripts/temper:4037-4053`, lets that through, and `no code changed at Review` does not count the spec folder)
    and append the id to `cli_commits`.
  - `cli_commits` exists only for a grouped Build. In a fix run and in a run with no groups the call refuses
    until WP24, which is the intended state; the refusal text must say why, so nobody reads it as a broken run.
  - `scripts/e2e/replay.ts` also drives the CLI of `10e965a` (`bash scripts/e2e/ab-replay.sh 10e965a`), which
    still takes a note for `--fixed-by`, and every `full` holds the base column of that replay equal to the
    entry `replay_base` of `scripts/e2e/floor.json` (WP05). After the edit of `:263` run the replay once. If the
    base column moved, the scripted Build agent keeps the call when it drives another plugin folder
    (`TEMPER_E2E_ROOT` is set, `scripts/e2e/world.ts:17`) and drops it for this tree only.
- **Size:** M (S for `evidence resolve` alone; the completion row and the tests it moves make it M).
