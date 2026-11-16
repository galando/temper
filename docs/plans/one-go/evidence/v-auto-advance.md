# Verification: auto advance after the plan approval (draft items 2a, 2e, decision 1)

Tree read: `/home/user/temper` at `10e965a` (branch `pr115`, the head of PR #115). All line numbers are of that
commit, read by me. Paths are relative to `/home/user/temper`.

Marks: **[code]** read at the cited line. **[ran]** run by me in a clone
(`/tmp/claude-0/-home-user-temper/1ba4743b-465f-5ae6-8b88-a04ebb2fe840/scratchpad/work-v-auto-advance/repo`, `pr115` at
`10e965a`) with the selftest's own fixture helpers: scripted run states and `temper next --json`, no agents.
**[reader]** measured by a reader, not repeated.

Not run, as instructed: the selftest suite, the e2e suite, the bench. Also not run: `claude plugin test .` and `tsc`.
So what the prototype below breaks in those suites is **not determined**; the list in section 7 is from grep.

## Verdict

**Feasible with changes.** The mechanism exists in the code today (an armed run under `autonomy.policy: decide`), the
guard needs no table change, and a prototype of 18 changed lines in `scripts/flow.py` and one removed line in
`scripts/temper` gave the intended answers on eight scripted states [ran]. The draft undercounts what must ship with
the default flip: five behaviours that are tolerable while the mode is opt in become defects once it is the default.

## 1. Is it true that no guard change is needed?

**Yes, for every table of the guard, under two conditions.** What does change in the mod is text, one driver pattern
and tests.

Why no table changes [code]:

| Move of an auto advance run | Why the guard lets it through | Evidence |
|---|---|---|
| A passed Design, Build, Review, Check advances | `state advance` is person only for `intent_complete` and `plan_complete` alone | `hooks/temper-mod/core/rules.ts:491` |
| The CLI's own `auto` calls, including person only ones (`state loop`, `task accept`) | `temper go` runs them inside the CLI, so no tool call exists; when a session runs them itself, the calls of the CLI's action are on the allow list | `scripts/go.py:95-106`; `hooks/temper-mod/adapter.ts:231`; `rules.ts:459-461` |
| Arming (`state set run_mode autonomous`) | Person only, and allowed as a call of the option the person picked. It is that today for the second option | `rules.ts:493`; `scripts/flow.py:674-675` |
| "Ask me at every stage" writing `state set run_mode interactive` | Not person only | `rules.ts:493` (`d !== 'interactive'`) |
| `temper park` | Not in the person only list | `rules.ts:476-497` |
| With the driver | The driver runs calls by process spawn, not as tool calls, and takes the answer from the dialog | `hooks/temper-mod/core/driver.ts:283-328` |

The answer rule matches header, question and label from the view and holds no list of labels
(`core/answers.ts:70-76`); the allowed calls are the picked option's (`core/decisions.ts:37-41`). The move `arm` is
already in the CLI's list (`scripts/flow.py:58`).

The two conditions:

1. **The mode stays in `run_mode`.** A new state key for "advance by itself" would be settable by any session: only
   the keys of `GUARD_KEYS` and `run_mode` are held (`rules.ts:335, 448-457, 493`). A new key means a guard table
   change. Reuse `run_mode`.
2. **Arming stays a call of the option the person picked.** If the CLI armed a run by itself (a config default with
   no call), the plan approval would no longer carry the decision the guard checks.

What must change in the mod (none of it a guard table):

- Texts: `rules.ts:330-332` (the refusal text names "the last question before Build"); `core/commands.ts:29` ("You
  decide at every gate").
- For draft item 2g only: `core/driver.ts:261` reads a verdict with the pattern ` gate [a-z]+`, which does not match
  `group gate G1`.
- Tests that pin the two labels: `tests/mod/dialog.test.ts` (9 places), `guard.test.ts` (5), `hardening.test.ts` (3),
  `answers.test.ts` (1) [counted with grep]. They keep working with the new label of the stage by stage option.
- The generated view fixtures (section 7).

Prototype result [ran]: with the flow patched, the plan question reads
`Approve and run to the commit (Recommended) => state set run_mode autonomous, spec branch, spec commit, state advance plan_complete build`
and `Ask me at every stage => state set run_mode interactive, ...`. No file under `hooks/` was touched.

## 2. Every place an armed run stops, and whether it must stay

"Park" = the `auto` call `temper park`, after which `temper next` asks the gate's question
(`scripts/temper:4510-4537`). "Ask" = a question with no park.

| # | Where | Trigger | Code | Must stay? |
|---|---|---|---|---|
| 1 | Design | Design changed the plan's tasks | `flow.py:2443-2447` | Yes: the changed tasks need the approval |
| 2 | Design | open areas of concern | `flow.py:2448-2453` | Yes: a true decision |
| 3 | Design, Build | the stage's gate failed | `flow.py:2464-2466` | Yes: a failed check. The unarmed question recommends "Run Build again" (`flow.py:757`); taking it once is optional |
| 4 | Build | a manual task | `flow.py:1890-1893` | Yes: only the person can confirm |
| 5 | Build | commits the CLI did not make on a group's branch | `flow.py:1806-1809` | Yes: keeping them is person only (`rules.ts:487`) |
| 6 | Build | merging the groups again after such commits were settled | `flow.py:1795-1798` | Keep. Rare, and the comment gives the reason (an unasked rerun would go round) |
| 7 | Build | a parked group (a task out of attempts, a blocked task, an agent's commits) | `flow.py:2074-2077` | Yes |
| 8 | Build | a failed group check when the recommended option needs typing or is "Save for later" | `flow.py:1966-1977` | Yes |
| 9 | Build | a failed group check when the recommended option is "Loop back to Plan" | today **not a stop**: the policy takes it, `flow.py:1966-1972` | **Must become a stop** (decision 3). One condition: `rec.get("move") != "back"` |
| 10 | Build | a task that failed on the environment | ask, no park, `flow.py:1857-1870` | Yes. This is the model for a stop that does not disarm |
| 11 | Build | tasks.md has tasks and no groups | ask, `flow.py:1621-1633` | Yes |
| 12 | Build | a DRIFT row in a fix pass panel | the session asks, `commands/temper.md:180-187`; the driver hands back, `driver.ts:437` | Yes: never answered for the person |
| 13 | Review | a failed row with no open finding at medium or above (an unfinished review); a spent loop budget | `flow.py:1157-1159, 1172` | Yes |
| 14 | Check | a setup fault, a missing measurement, the locked acceptance tests, a spent loop budget | `flow.py:1157-1159, 1176-1179` | Yes |
| 15 | Check | a criterion only the person can confirm | today **not a stop**: a loop back to Build, `flow.py:1180` | **Must become a stop** (defect 3b) |
| 16 | Commit | always | `flow.py:2227-2231`, then the question at `:2242-2244` | Yes (decision 4). The park is machinery; the question could be asked directly |
| 17 | Commit | the commit gate failed | `flow.py:2228, 2247-2277` | Yes, and it needs an exit (section 3, item 7) |
| 18 | Plan, after any loop back to Plan | the plan question again | `flow.py:2441` excludes plan | Yes |

Not a stop: a covered task is taken as done (`flow.py:1837-1842`); a one group plan and an armed run continue a
passed group (`flow.py:1759-1765`).

**The fact the draft misses: one park disarms the run for good.** `temper park` writes `run_mode interactive`
(`scripts/temper:4520`) and nothing writes `autonomous` again except the arming option. So after the first stop every
later gate asks: the rest of Build, Review, Check. An unhappy run is then a stage by stage run. Row 10 shows the code
can ask without disarming.

## 3. Defects of `autonomy.policy` to fix first, each re-checked at `10e965a`

The three the task names, all confirmed in code and by run:

| # | Defect | Code at the head | Run at the head [ran] |
|---|---|---|---|
| a | The group fix agent is never launched in an armed run; the run plans again on Opus | the launch is guarded by `not r.armed()`, `flow.py:1754`; `group fix` only records the request and counts it, `scripts/group_fix.py:65-72`; the next pass recommends "Loop back to Plan" and the policy takes it, `flow.py:1966-1972, 2000-2005` | step 1 `auto: group fix G1`; step 2 `auto: state loop build plan --reason 'policy: ...'`; step 3 `work: temper:temper-plan`, "the Plan agent is working on opus" |
| b | A loop back to Build for a criterion only the person can confirm | `policy_move` for Check has no branch for it, `flow.py:1173-1180`; the unarmed question has, `:825-836` | `auto: state loop check build --reason 'policy: acceptance evidence: AC-09 has no supported passing evidence row'` |
| c | The run stays armed after a loop back to Plan, whatever the person answers | no write of `run_mode` on a step back, `scripts/temper:1269-1295`; "Stage by stage" carries no reset, `flow.py:673` | after the loop back and the answer "Stage by stage (Recommended)": `stage=build run_mode=autonomous` |

Four more that are small today and blocking once the mode is the default:

| # | Defect | Code | Why it blocks |
|---|---|---|---|
| 4 | A failed `integrate` after a fix pass relaunches the fix agent with no question and no count | `flow.py:1658-1672`; `scripts/temper:3316-3324` returns 1, so `gate build` never runs | In an unattended run this is a spend loop with nobody asked |
| 5 | One park disarms the run for good | `scripts/temper:4520` | Section 2 |
| 6 | The policy has its own severity list: any open finding at medium or above loops back, up to twice, with no question | `flow.py:1167-1169`; budget `scripts/loop_step.py:20-32` | Each loop is a fix pass and a whole Review. Draft decision 5 and WP0's "flip" name only the question (`flow.py:780`); this list is separate |
| 7 | A run that ran unattended gets two more commit gate rows, and the commit question has no option that checks again | rows: `scripts/temper:4191-4223`; question: `flow.py:2252, 2269-2277`; shipped patterns `templates/temper.config.default:150` (`park-on-touch: ["**/auth/**", "**/payment/**", "**/billing/**"]`) | Every default run becomes a run that "ran unattended" (`scripts/temper:911-912`). How often the row fires is **not determined** |
| 8 | An armed run cannot end in a pull request | `flow.py:891` (not offered to an armed run); the parked commit question has Commit and Save only, `:2243-2244` | The passed Check question, which holds the option, is no longer asked |

Older and outside the policy, but it decides whether the driver keeps the run (draft 2g): a failed `group gate` exits 1
and prints no `-> FAIL` (`scripts/temper:2510-2512`), so `temper go` reports `error` (`scripts/go.py:108-114`) and the
driver hands the run back, one way (`driver.ts:352`). With 2a and without 2g, "only a failed check asks" is true, and
that failed check also moves the rest of the run into the Sonnet session.

## 4. With the mod off

The model loop does not normally receive an `auto` action: `temper go` runs every `auto` action's calls itself and
stops only at agents, a question, steps, a wait or the end (`scripts/go.py:95-117`). The page tells the session what
to do if it meets one after an error (`commands/temper.md:73-75, 117-119`). So the same change works with the mod
and without it, and the question count is the same [reader: 3 questions in both modes under the policy].

Nothing is unsafe that today's armed policy run does not already do. What grows because it becomes the default:

1. **No guard, as today.** Without the mod nothing checks that the person picked the arming option. The CLI's own
   refusals stay: it leaves a stage only on a PASS or a skip (`flow.py:2510-2535`), and the policy never overrides or
   accepts (`flow.py:1144-1181`).
2. **Defect 4 above** is the one real hazard: a session follows `work` actions without end.
3. **Unattended spend has a bound but no question:** up to 2 loops Review to Build and 2 Check to Build
   (`loop_step.py:20-32`), each a fix pass and a Review.
4. **One long Bash call.** After the last task the session runs the task gate, the group gate, `integrate` and
   `gate build` in one call; after Review, `gate review`, `check run` (suite, coverage, mutants) and the commit gate.
   A one group run and an armed run do this today (`flow.py:1763-1768`). Whether the host cuts such a call at its
   default time limit is **not determined**; the page sets no limit.

## 5. What the person can no longer do between Plan and the commit

Options that exist only in questions the run no longer asks [code]:

| Question no longer asked | Options lost | Code |
|---|---|---|
| Each passed group (two or more groups) | Change (feedback, only those tasks run again), Stop | `flow.py:1942-1948` |
| Build passed | Change something, Teach Me, Loop back to Plan, Make a small change, Save for later | `flow.py:745-752` |
| Review passed | Continue with findings open, Accept a finding, Architecture Depth Review, Grill Me, Teach Me, Loop back to Build, small change, Save | `flow.py:772-791` |
| Check passed | Commit and open PR, stacked PRs, Loop back to Build, Review config suggestions, small change, Save | `flow.py:815-821, 887-897` |
| Design passed (if armed at Plan) | Walk through step by step, Grill Me, Teach Me, Loop back to Plan | `flow.py:726-732` |

Also lost: typing a change request at any of those questions (`commands/temper.md:154-162`).

What stays: an interrupt stops the driver with no model turn and the CLI holds the run (`driver.ts:336, 404, 444`).
But `/temper:temper` then resumes a run that goes on by itself, so an interrupt alone gives no question.

The smallest way to keep "let me look", in order of need:

1. **The option (needed, in the draft):** "Ask me at every stage" as the second option of the plan question. It must
   write `run_mode interactive` (defect c).
2. **The commit question carries what the Check question carried (needed, not in the draft):** the pull request
   options and "Loop back to Build". `state loop check build` is accepted from Commit (`scripts/temper:1222-1245`:
   the from stage only has to be reached). The record steps already read `pr` once the run is not armed
   (`flow.py:2210`).
3. **A pause (optional, about 10 lines):** a word of `/temper:temper` that runs the existing `temper park`. With
   the prototype, a park makes the stage the run is at ask its ordinary question with every option, and the run goes
   on by itself from the next stage [ran: after a park in Build, "Build: the check passed. Continue to Review?" is
   asked; after the advance, Review passes as `auto`]. No guard change: `park` is not person only.
4. **A note** needs nothing new: typed text at any stop is recorded for the next agent
   (`commands/temper.md:154-162`). It is not a way to stop.

## 6. The patch outline (smallest change that delivers 2a and decision 1)

Prototype in the clone: 6 edits, 18 lines of `scripts/flow.py`, 1 line of `scripts/temper`. Results in
`.../work-v-auto-advance/out-head.txt` (unpatched) and `out-patched.txt`.

In order:

| # | File and place | Change | Prototype result [ran] |
|---|---|---|---|
| 1 | `scripts/flow.py:296-298` `policy()` | default `decide`; `ask` stays as the way to get "Build only" | default config, armed: Build PASS gives `auto: state advance build_complete review`; Review PASS gives `auto: state advance review_complete check` |
| 2 | `scripts/flow.py:672-680` plan question, no Design | first option "Approve and run to the commit (Recommended)" (move `arm`, the arming call, then the plan's steps); second "Ask me at every stage" (the call `state set run_mode interactive`, then the steps) | labels and calls as in section 1 |
| 3 | `scripts/flow.py:681-689` plan question, Design follows | add the same two options. The armed path through Design exists (`:2441-2463`) but is reached today only through defect c. Whether a `Design:` Blocking question always leaves an open concern (so row 2 of section 2 stops the run) is **not determined** | not prototyped |
| 4 | `scripts/flow.py:1754` | drop `and not r.armed()` | after `group fix G1`: `work: temper:temper-build`, "one fix agent works on group G1's merged tree" |
| 5 | `scripts/flow.py:1968` | the policy never takes an option whose move is `back` | after a failed fix: `auto: park`, then the question "Loop back to Plan (Recommended), Fix..., Run..., More options" |
| 6 | `scripts/flow.py:1173-1180` | a required manual criterion parks (share the test of `:825-826`) | `auto: park`, then "Confirmed (Recommended), Loop back to Build, Make a small change, Save for later" |
| 7 | `scripts/flow.py:300-303` and `scripts/temper:4520` | a stop does not disarm: `park` no longer writes `run_mode`; `armed()` is false while `parked` is set. `parked` ends when the run changes stage (`scripts/temper:1018`) | after a stop in Build the Build question is asked once; Review then passes as `auto`. The commit still goes park, question, page, record |
| 8 | `scripts/flow.py:1167` | the policy's severity list follows `review.block-on`; a finding below it is carried to the commit question (decision 5) | not prototyped |
| 9 | `scripts/flow.py:1658-1672` | a failed `integrate` after a fix pass reaches `gate build`, so the Build question and its "failed the same way" rule (`:755-763`) apply | not prototyped |
| 10 | `scripts/flow.py:2242-2244, 2269-2277` | the commit question gains the pull request options, "Loop back to Build", and "Check again" for the commit gate's own rows | not prototyped |
| 11 | `scripts/go.py:108-109`, `core/driver.ts:261` (draft 2g) | a failed `group gate` is a verdict | not prototyped |

Item 7 leaves one extra question when the stop is inside Build with two or more groups (the stage stays interactive
until it is left). Ending the park at the person's answer (one call appended to the options of a parked question,
never at Commit) removes it; about 10 more lines.

Size limits: `scripts/temper` is 260,504 bytes, 1,640 under the 256 KiB cap; item 7 removes a line there.
`scripts/selftest/view-fixtures.ts` is 259,060 bytes, 3,084 under the cap, and the new option text is longer
(`flow.py:1138-1142`): new fixture views must go to `view-fixtures-2.ts`.

Draft item 2e ("the commit's three actions become one") is separate from this mechanism: the actions are
`flow.py:2232-2246`, gated by `end_report`. Not needed for auto advance.

## 7. Tests

Selftest (`scripts/selftest/`):

- `temper-cases-8.sh:73, 78, 94, 267`, `temper-cases-14.sh:47, 100, 105`, `temper-cases-15.sh:215, 221`: the two
  labels and their order.
- `temper-cases-28.sh`: the fixture appends `autonomy:\n  policy: decide` (`:5, 34`), which is the default after the
  change; the case "without autonomy.policy, an armed run still asks at Review" (`:30`) needs `policy: ask`. The
  group case asserts only the first call (`:40`).
- New cases, one per row of the prototype table: the fix agent is launched; no step back to Plan by the policy; a
  manual criterion parks and the question is "Confirmed"; "Ask me at every stage" writes interactive; a stop keeps
  `run_mode`; after the stop the next stage is `auto`; the commit sequence of an armed run.
- `make-view-fixtures.sh`: regenerate both fixture files.

End to end (`scripts/e2e/`): the scripted person takes the option marked "(Recommended)"
(`scenarios.ts:118-121`), so every scenario that reaches the plan question changes its trace. Scenarios that test a
later gate's question must pick "Ask me at every stage" by name: `smallChange`, `prAndPipeline` (it picks "Commit and
open PR" at the Check question, `:290`), `threeGroups`, `saveAndResume`, `coveredAndManual`, `designRun`, the fresh
review ones, `mavenRun`, the three pyjokes ones. `modGuards` pins the old label (`:153-154`). `armedRun` (`:443-462`)
asserts the 9.8.0 rule and is rewritten. New scenarios: a default run to the commit (3 questions with the fixture's
`reviewed: auto`); a failed group that the fix agent repairs; a failed fix that stops and asks; a manual criterion;
a stop and the stage after it. `replay.ts:309` no longer needs to append the policy.

Mod tests (`tests/mod/`): the label in `dialog.test.ts` (9), `guard.test.ts` (5), `hardening.test.ts` (3),
`answers.test.ts` (1); a driver test for the group gate verdict (item 11). No row is added to the answer audit's
table: no new person only call (`docs/decisions/0016-the-mod-answer-audit.md:28`).

## 8. Docs and decision records

- A new decision record: a passed gate is not a decision; the person approves the plan and the commit; the run stops
  at a failed check and at a true decision. It amends ADR 0012 decision 4 ("Every gate is an AskUserQuestion dialog",
  `docs/decisions/0012-...md:37-41`), ADR 0013 decision 1 (`auto` is "an armed run's own move", `:33-41`) and the
  invariant list of ADR 0011 (`docs/decisions/0011-grouped-build.md:89`).
- `reference/autonomy.md`: nearly the whole page ("The unattended part is Build alone", `:15`; "turns the run back
  to interactive", `:25`; "never plans again by itself", `:35`).
- `templates/temper.config.default`: the header of the autonomy block (`:133-141`), the `policy` comment (`:146`), the two
  unread budget keys (`:151-153`).
- `docs/flow.md:224-235` (the run policy), `docs/mod.md`, `docs/auto-mode.md`, `docs/grouped-build.md:124`.
- `.claude/CLAUDE.md`: "Autonomous Build (opt-in)" and "The person decides each gate".
- `README.md:30` ("You decide each gate by clicking an answer"), `docs/index.html`, `docs/mods-testing.md`.
- `commands/temper.md:104` (stale), `:117-119` (wording of `auto`).
- `CHANGELOG.md` (15,188 bytes under the cap).

## 9. Corrections to the draft

1. **2a names only the plan question with no Design** (`flow.py:672-680`). With Design the plan question has no
   arming option (`:681-689`) and arming is the second option of the Design question (`:726-730`). The draft must say
   which question arms.
2. **Decision 1's sentence on the guard is true and incomplete.** Leaving Intent and Plan are the only person only
   *advances* (`rules.ts:491`). Arming and every step back are person only too (`:492-493`); they pass because arming
   is the picked option's call and the policy's moves are the CLI's own action. State the two conditions of section 1.
3. **"A clean run goes from 8 dialogs to 2" is the effect of 2a, 2b and 2c together.** 2a alone takes the reference
   run from 8 to 4 (Intent, Context check, Plan, Commit): the two group questions, Build, Review and Check go, and
   the commit question takes Check's place.
4. **2a is not only a new first option.** It needs, in the same change: a stop that does not disarm, the commit
   question with the pull request options and a way back, the policy's own severity list, the bound on the fix pass
   after `integrate`, and the exit of the commit gate's own rows (section 3, items 4 to 8).
5. **WP0 lists three policy defects; under the default the list is eight.**
6. **Decision 3 and 2a meet in one line:** the policy takes "Loop back to Plan" by itself today (`flow.py:1966-1972`).
   Excluding moves of kind `back` settles it; the draft leaves it to "settle it there".
7. **Decision 5 and WP0's flip must name `flow.py:1167` as well as `:780`.** The policy does not read the question's
   recommendation at Review.
8. **2g must name `core/driver.ts:261` beside `go.py:108-114`**, or a failed group gate that is a call of an option
   ("twice the time", "Change the group's command") still hands the run back.
9. **Decision 1 leaves Design out.** A passed Design with no open concern and unchanged tasks advances in an armed
   run already (`flow.py:2454-2462`).
10. **WP2 has no docs item.** Four documents and the config template state the opposite of the new default.
11. **The draft says nothing about what the person loses** (section 5) or about a pause.
