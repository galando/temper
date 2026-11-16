# The mod (hooks/temper-mod): what it carries, what it refuses, what it costs

Reader: mod subsystem. Tree: `/home/user/temper` at PR #115 head (`pr115`, 9a01eff, 9.8.5). All paths are relative
to that folder. Every claim is marked **[code]** (read in code), **[ran]** (I ran it in a scratch clone at
`/tmp/claude-0/-home-user-temper/1ba4743b-465f-5ae6-8b88-a04ebb2fe840/scratchpad/work-mod/repo`), **[doc]** (a
claim in a doc or the CHANGELOG, not checked in code) or **[inferred]**.

## 0. The findings that matter for the goal

1. **With the mod loaded, a clean run already needs no model in the main session** ($0.00, 0 turns in 7 of 8
   measured runs: `docs/evidence/bench-2026-11.md:437` [doc]). The driver is 597 lines of pure code
   (`hooks/temper-mod/core/driver.ts`) over `temper go`.
2. **A hand back is one way.** Once the driver hands a run to the conversation, the Sonnet loop of
   `commands/temper.md` carries everything after it; nothing gives the run back to the driver unless the person types
   `/temper:temper` again (`commands/temper.md:24-28,43`; `hooks/temper-mod/register.tsx:753-765` [code]). Measured
   cost of one hand back: $0.02 to $0.43 of main session and, in one run, $3.06 and 917 s against $1.93 and 704 s
   (`bench-2026-11.md:389-391,441-445,479-481` [doc]). **A failed group check is a hand back** (`scripts/go.py:108-114`,
   `driver.ts:352`) [ran], and that is the kind of failure the 9.8.4 run met five times (`CHANGELOG.md:72-74`; whether that run was driven is not recorded).
3. **The question count is the CLI's, not the mod's.** A run where every check passes first time asks 7 questions
   with two Build groups, 8 with Design or a third group; an armed run asks 4; an armed run with
   `autonomy.policy: decide` (new in PR #115) asks 3: Intent, Plan, Commit [ran]. The driver carried that 3 question
   run to the end with no hand back, no refusal and no change to the mod [ran]. So "one approval before Build, one
   at the commit" is one question away, and that question (the Intent gate) is a `scripts/flow.py` decision.
4. **The guard's coupling to exact text has a measured price**: 10 benchmark runs thrown away because the guard
   refused a step the CLI had given (`bench-2026-11.md:292-304` [doc]), 338 KB of generated view fixtures that must
   be regenerated on every flow change (`scripts/selftest/view-fixtures.ts`, 259,060 bytes, 3,084 bytes under the
   plugin directory's 256 KiB limit [ran: `ls -la`]), and three defects I found by running the mod's own code
   against the CLI's own output (section 2.4).
5. **Most of the guard exists to hold a model in the main session to the script.** `core/session.ts` (283 lines)
   says so in its header (`session.ts:1-12`). A driver that never hands the run back removes its reason.

## 1. The run driver

### 1.1 When the mod carries a run

| Typed by the person | Run state | Who carries it | Where |
|---|---|---|---|
| `/temper:temper <request>` | no run active | the driver | `register.tsx:611-617` [code] |
| `/temper:temper` (no words) | a `/temper` run active | the driver | `register.tsx:617` [code] |
| `/temper:fix <bug>` | no run active | the driver (`fixSteps`) | `register.tsx:727-739`, `driver.ts:480-504` [code] |
| `/temper:temper <request>` | another run active | the conversation (restart question) | `register.tsx:616-618` [code] |
| a run word (`approve`, `next`, `back`, `discuss`, `chose`, ...) | any | the conversation | `session.ts:232`, `register.tsx:614-618` [code] |
| a door (`/temper:plan`, `/temper:build`, `/temper:review`, ...) | any | the conversation, always | `register.tsx:723-741` handles only `temper`, `temper:temper`, `temper:fix` [code] |
| any of the above | mod inert (Claude Code below 2.1.287), enforcement off, or view.json of another version | the conversation | `register.tsx:613`, `adapter.ts:98` [code] |
| `/temper:fix` with no words and a fix run active | fix run | the conversation | `register.tsx:613` (`runCommand === 'fix'` returns null) [code] |

Note on doors: `commands/plan.md`, `build.md`, `design.md`, `review.md`, `check.md` carry no `model:` line (only
`commands/temper.md:4` and `commands/fix.md:4` say `model: sonnet`) [ran: grep of the front matter]. A run started
through a door therefore runs the whole loop on the session's own model, and is never driven.

### 1.2 What the driver does by itself

All in `hooks/temper-mod/core/driver.ts` [code], reaching the engine through `register.tsx:475-606`:

| Step | Code |
|---|---|
| Runs `temper go` each turn, up to 300 turns | `driver.ts:50,334-338` |
| Runs the `setup` calls (a failure is shown, the run goes on) | `driver.ts:339-342` |
| Starts the run: `state init <slug> --feature '<request, whole>'` | `driver.ts:343-349`, slug from `slugOf` `:193-199` |
| Shows the CLI's `say` line | `driver.ts:353` |
| `wait`: runs the after calls of tasks started in an earlier conversation, else sleeps 5 s, up to 120 looks | `driver.ts:354-369`, `register.tsx:513-516` |
| Blocking questions, four to a dialog; runs each `answer` or `carry` call, then the action's `gate` call | `driver.ts:372-391`, `register.tsx:552-574` |
| The gate question, word for word; More options; Accept a finding; the reason question; a manual task's name question; the option's calls and CLI steps; Save for later ends the drive | `driver.ts:283-328` |
| Agents: every `before` call, then every launch (type, model, prompt as the CLI wrote them), then waits, then the `after` calls with `{ms}` filled | `driver.ts:397-436`, `register.tsx:503-531` |
| Shows a Build task's `TASK N: stopped:` line and the CLI's panels, compacted to a few rows | `driver.ts:427-431`, `:88-137` |
| The end of run steps that are CLI calls, and the report as printed | `driver.ts:442-453`, `:212-218` |
| `/temper:fix`: setup, the root cause agent, `panel rca`, `state init --command fix`, `usage add`, then the same loop | `driver.ts:480-504` |
| An interrupt ends it as stopped, with no model turn | `driver.ts:336,404,444,561-569` |

`temper go` (`scripts/go.py`, 125 lines) does the rest inside the CLI before the driver sees anything: every `auto`
action (an armed run's moves) and every `work` action that has calls and no agents or steps (gates, group starts,
Check's run) (`scripts/go.py:95-117` [code]). So the driver only ever sees `work` with agents or steps, `ask`,
`wait`, `none`, `error`, `broken`.

The driver runs one program only: the plugin's own `scripts/temper`, by argument list, no shell
(`core/argv.ts:80-85`, `register.tsx:475-491` [code]). Anything else returns exit 126 without running
(`register.tsx:477`).

### 1.3 Every hand back cause

`handback(why, args)` at `driver.ts:279`. `args` is `next` unless noted. The command then goes on to the prompt
based page with one note (`register.tsx:583-586,763-764`).

| # | Cause | Line | Passed on as | Needs a model or the person? |
|---|---|---|---|---|
| 1 | The person typed an answer (Other) at a gate question | `driver.ts:288` | `discuss <text>` | Only to tell a question from a change request (`commands/temper.md:154-162`) |
| 2 | The chosen option has a `do` text (see 1.4) | `driver.ts:294-296` | `chose <label>` | Mixed: see 1.4 |
| 3 | A step of the chosen option is not a CLI call | `driver.ts:295` | `chose <label>` | e.g. Pipeline "Apply the fix and push" (`scripts/flow.py:1026-1032`) |
| 4 | An option call holds a placeholder the driver cannot fill (`{K}`, `{text}`) | `driver.ts:318` | `chose <label>` | e.g. "Which task changes?" options, `--feedback {K}` (`flow.py:1939`) |
| 5 | No name typed after three tries (manual task) | `driver.ts:316` | `chose <label>` | No. Seen in e2e `covered-and-manual` [ran] |
| 6 | A call of the answer failed (any non zero exit but a gate's `-> FAIL`) | `driver.ts:319`, `:261` | `next` | Includes every call that is not the CLI: `git checkout -b` (`flow.py:631`), `git -C <wt> rebase` (`flow.py:1818`) return 126 [ran: `cliArgv` returns null for both] |
| 7 | A CLI step of the option failed | `driver.ts:323` | `next` | To diagnose |
| 8 | Nobody answered: the gate question, the reason question, the name question, a Blocking question | `driver.ts:286,300,310,382` | `next` | A surface with no person (`claude -p`) |
| 9 | A Blocking answer call failed | `driver.ts:384` | `next` | To diagnose |
| 10 | `temper go` printed no action; `ask` with no question; an unknown action | `driver.ts:338,392,456` | `next` | Defect paths |
| 11 | `temper go` said `error` or `broken` (a call inside `go` failed, the same calls twice, a broken run state) | `driver.ts:352`, `scripts/go.py:99-114` | `next` | **A failed group check is one of these**: `temper group gate G1` exits 1, and `go.py:108-109` takes only a call that starts with `<cli> gate ` and prints `-> FAIL` for a verdict [ran: e2e `pyjokes`, driver mode, handed back at step 69 of 119 with "the call temper group gate G1 failed (exit 1)"; the model loop then asked the CLI's own question, "Fix the group's merged work (Recommended)"]. Also `temper integrate` failed (`bench-2026-11.md:389-391` [doc]) |
| 12 | `state init` failed | `driver.ts:346,499` | `next` | To diagnose |
| 13 | An agent's `before` call failed, or no agent could start | `driver.ts:409-421,435` | `next` | To diagnose |
| 14 | An agent's `after` call failed (not a gate FAIL, not a task verdict) | `driver.ts:432` | `next` | To diagnose |
| 15 | An agent's answer lists DRIFT rows | `driver.ts:221,437` | `next` | The Scope drift question is built from the agent's panel by a model (`commands/temper.md:180-188`) |
| 16 | A `steps` entry that is not a CLI call: the pull request steps, raw `git add` and `git commit`, a step with a `{placeholder}` | `driver.ts:214-217,440-441,452` | `next` | PR: `flow.py:2210-2217`; raw git: `flow.py:2207-2208` |
| 17 | A CLI step failed | `driver.ts:448` | `next` | To diagnose |
| 18 | Bounds: the question went round more than 6 times; more than 120 waits; the same after calls twice; 300 turns | `driver.ts:284,359,362,458` | `next` | No |
| 19 | Any throw that is not the interrupt | `driver.ts:142-145`, `register.tsx:731,755` | `next` | No |
| 20 | `/temper:fix`: a run is already active; the root cause agent could not start | `driver.ts:489,494` | `next` | No |

### 1.4 The options with a `do` (cause 2), one by one

| Option | Where the CLI writes it | Truly needs the conversation? |
|---|---|---|
| Grill Me, Teach Me | `flow.py:487-490` | Yes: a dialogue with the person |
| Open HTML review, Share HTML review | `flow.py:643-646` | Open: a script could do it. Share: publishes an artifact (a model tool) |
| Walk through step by step (Design) | `flow.py:704-705` | Yes: a dialogue |
| Architecture Depth Review | `flow.py:769-770` | An agent could do it |
| Review config suggestions | `flow.py:819-820` | The person picks per suggestion; the write is mechanical |
| Make a small change | `flow.py:907-913` | A model writes the change; an agent could |
| Group question "Change" | `flow.py:1944-1946` | Typed feedback; recording it is mechanical |
| Context check "Something else" | `flow.py:2319-2320` | Typed text; the call is mechanical |
| **"Cancel" in the Accept a finding question** | `flow.py:1088` (`do="Ask the %s question again."`) | **No.** The driver hands back `chose Cancel` instead of asking the gate question again [ran: stub drive, `handback args="chose Cancel"`] |
| More options, Accept a finding | `flow.py:498,513,778,801` | No: handled in the driver by matching the label `More options` and the text `Ask the accept question` (`driver.ts:290-291`) |

### 1.5 What model work is left in the main session

- **While the driver carries: none.** No model turn runs in the main session; the driver's output is `$.ui.log`
  rows (`register.tsx:596-601`) [code]. Measured: main session $0.00 and 0 turns (`bench-2026-11.md:352,389,437` [doc]).
- **After any hand back: all of it, for the rest of the run**, on Sonnet (`commands/temper.md:4`). The page says
  "carry that option out ... then go on with the loop" (`commands/temper.md:43`) [code]. There is no path back
  to the driver in the mod: the driver starts only inside `command.run` (`register.tsx:722-770`), and the mod has no
  call that runs a command (the reviewed list holds no `command.run`: `scripts/check-mod-calls.sh:26-45`) [code].
- Measured hand backs [doc]: a driver defect at the Intent gate, $0.06 and 58 turns (`bench-2026-11.md:351`);
  `temper integrate` failed, $0.02 (`:389-391`); a fix run with DRIFT, $0.43 of $1.27 (`:441-445`); `integrate`
  again, $3.06 and 917 s against $1.93 and 704 s for the sibling run (`:479-481`); login-lockout, three small change
  hand backs (`:505-506`); two runs on a defect now fixed, $0.36 and $0.91 of Sonnet (`:528-531`).
- Hand backs seen in my e2e runs in driver mode [ran: 17 of the repo's 23 scenarios and one of mine, scripted
  agents and a scripted person]: `small-change` (`chose Make a small change`), `pr-and-pipeline` (the pull request
  step), `covered-and-manual` (`chose Confirm: no name was typed`) and `pyjokes` (**a failed group check**, cause
  11). Twelve ended `driver done` with no hand back: full-run, design, context-check, armed-run, three-groups,
  save-and-resume, fresh-ask, fresh-review, fresh-contest, branch-clash-carry, pyjokes-full, pyjokes-blocked; so did
  my armed run under `autonomy.policy: decide`. `failing-scenario` ends at its own stop point. Not counted: `fix`
  fails here in every mode (pytest is not installed in this container), `maven` did not finish in 200 s in plain
  mode either (cause not determined, not a mod matter), and I did not run `mod-guards`, `hook-scope`,
  `branch-clash` and `fresh-not-run` in driver mode.
- The `pyjokes` hand back matters most for the goal: it is the replay of the 9.8.4 failed run (a group whose tasks
  pass and whose check fails, `CHANGELOG.md:70-74`). With the driver, the first failed group check moves the whole
  rest of the run into the Sonnet conversation. A failed **task** gate does not (it is read as the CLI's verdict:
  `driver.ts:77-82,432`); a failed **group** gate inside `temper go` is not.

## 2. The guard

### 2.1 What it refuses

Applied to **every loop, subagents too** (`register.tsx:784-788`), by `core/rules.ts` [code]:

| Refused | Line |
|---|---|
| `git commit --no-verify` / `-n` while a `/temper` or `/temper:fix` run is active | `rules.ts:396-398`, `shell.ts:547-564` |
| Any change of `core.hooksPath` (config, `-c`, `--config-env`, env variables, an alias, `HOME=` with git) | `rules.ts:399`, `shell.ts:539-668` |
| A brace list that expands past 1,024 words | `rules.ts:400`, `shell.ts:359` |
| A Bash write (a redirect, `rm`, `mv`, `cp`, `tee`, `sed -i`, `ln`, `rsync`, `dd` ...) onto the CLI's files: `.temper/gates.json`, `status.json`, `overrides.json`, `build-state.json`, `groups.json`, `usage.json`, `view.json`, `evidence/*.json`, `feedback-loops.json`, the `.temper` folders; and during a run `.claude/temper.config` and the git hooks and config | `rules.ts:103-116,404-428` |
| The same files by Write, Edit, MultiEdit, NotebookEdit; and the plugin data folder during a run | `rules.ts:513-524` |
| A write outside the stage's table (Intent: `intent.md`; Plan and Design: the spec files and `docs/decisions/*.md`; Build: the plan's files, tests, drift answers; Review, Check, Pipeline, Commit: the spec folder, plus `CLAUDE.md`/`AGENTS.md` from Check on); `tasks.md` from Design on | `rules.ts:237-325` |
| A person only CLI call that is not, word for word, a call of the option the person chose at this run and step, or a call of the CLI's own action: `override`, `plan review`, `plan patch` (PR #115), `task confirm`, `task accept`, `adhoc open`, `acceptance reopen`, `state set branch`, `group reopen --accept-foreign`, `evidence accept`, `evidence clear`, `state advance intent_complete|plan_complete`, `state loop|init|clear|archive`, `state set run_mode` (not interactive), `state set next_stage` backward | `rules.ts:459-468,476-497` |
| `state set` of the CLI's own keys; `complexity` outside Intent and Plan; `base_sha` in another form | `rules.ts:335,448-457` |
| An unquoted glob in a temper call that could spell a person word | `rules.ts:371-372,443` |
| `gh pr ready`; `gh pr create` without `--draft`; `guards uninstall` | `rules.ts:438-440` |
| Fix run: `state set regression_test ""` | `rules.ts:432-434` |
| Bash, when the guard itself throws during a run | `register.tsx:393-396,836-843` |

Applied to the **main session only** (a call with no agent id), during a `/temper` run, by `core/session.ts` [code]:

| Refused | Line |
|---|---|
| Every Write, Edit, MultiEdit, NotebookEdit (unless a small change window is open) | `session.ts:263` |
| Bash that is not the CLI or one of 49 reading programs and shell builtins, any redirect into a file, any git subcommand that is not a read (but a push to `temper-backup/`, PR #115), a program named through a variable | `session.ts:102-169,172-183,264-272` |
| An agent launch whose type, model family or prompt differs from the ones the CLI named | `session.ts:193-206,273-276` |
| A question whose header, text or option labels (count and order) differ from a question the CLI gives at this step, unless it is a Scope drift question or a chosen skill is running | `session.ts:208-215,277-281` |
| `state init --feature` whose text differs from what the person typed after `/temper:temper` | `session.ts:244-255`, `register.tsx:452-457` |

Not judged [code/doc]: a `/temper:fix` run's moves (`adapter.ts:206-208`), MCP and PowerShell file tools
(`docs/mod.md:249`), anything in a variable, a script, `sh -c`, `eval`, a here document, `git merge` and plumbing
(`docs/mod.md:236-243`, `shell.ts:11-13`). `docs/trust.md:62-72` and `docs/mod.md:171-173` say plainly that it is not
a sandbox.

### 2.2 Known cases where the guard refused a legitimate step of the CLI

| When | What was refused | Cause | Source |
|---|---|---|---|
| 9.6.x | `state advance build_complete review` after "Continue to Review" | only advances out of Intent and Plan counted as the person's | `CHANGELOG.md:1764-1766` [doc] |
| 9.6.x | Build checkpoint commits | the branch was never created | `CHANGELOG.md:1782` [doc] |
| 9.6.x | the orchestrator's `state advance` after a skip at Plan | skip not read as the go ahead | `CHANGELOG.md:1827-1829` [doc] |
| 9.7.0 | a copy into the spec folder | read as a replacement of the folder | `CHANGELOG.md:1021` [doc] |
| 9.7.5 | the command the CLI wrote to carry the spec files across a branch switch | a Bash write under `.temper` | `CHANGELOG.md:796-797` [doc]; fixed by `rules.ts:418-426` [code] |
| 9.8.0, round 5 | an agent launch after `task start` | the mod's memory of the named agents did not survive a module reload; the action had become `wait` | `bench-2026-11.md:295-297` [doc] |
| 9.8.0, round 5 | an agent launch | two view writers wrote the model differently ("Model: haiku." against the model id) | `bench-2026-11.md:298-299`, `CHANGELOG.md:399-400` [doc] |
| 9.8.0, round 5 | a fix agent launch | a raw traceback in the prompt, copied wrong by the session | `bench-2026-11.md:300-301`, `CHANGELOG.md:395-396` [doc] |
| 9.8.0, round 5 | the Intent agent launch, both runs | the CLI's prompt held two periods, the session tidied them to one | `bench-2026-11.md:286-288`, `CHANGELOG.md:370-371` [doc] |
| 9.8.0 | a manual task's confirm call | the name question could not be shown (one option), so no answer allowed the call; "the guard rightly refused" | `CHANGELOG.md:541-544` [doc] |
| 9.8.0, round 5 | (the cost) 10 runs in two passes thrown away: "each pass was stopped when the guard refused a step the CLI had given" | the cases above | `bench-2026-11.md:292-293` [doc] |
| **now (since 9.7.5)** | `plan review --answer '<typed text>' --redo`, the call the CLI gives for a typed Context check answer | the mod's parser reads the wrong shape, see 2.4 | [ran] |

Intended refusals that still cost a turn each [doc]: a session that passes a summary to `state init` is refused once
and passes the request whole (`bench-2026-11.md:283-285`); a session that added a line to an agent's prompt
(`:334-336`).

### 2.3 How tightly it is coupled to exact text

| Coupling | Mod side | CLI side |
|---|---|---|
| An answer counts only if header, question text and option label are equal | `answers.ts:33,70-76` | every question in `scripts/flow.py` |
| A question the session asks: header, text, label count and order equal | `session.ts:208-215` | the same |
| An agent launch: type, model family, prompt equal but for trailing spaces | `session.ts:186-206` | `flow.py:1120-1137` and every prompt builder |
| A person only call: word for word the option's call | `shell.ts:681-688`, `rules.ts:461` | every `calls` list |
| A whole command the CLI wrote: character for character | `session.ts:267`, `rules.ts:426` | `steps`, `setup` |
| The request: equal to what was typed, whitespace aside | `session.ts:221-255` | `state init --feature` |
| Step kinds by regex on English: `^Copy what temper report printed`, `^There is no record commit` | `driver.ts:215-216` | `flow.py:2145,2190` |
| Option kinds by label or `do` text: `More options`, `^Ask the accept question`, `Cancel`, `Carry forward` | `driver.ts:290-291,301,311,383` | `flow.py:468,480,498,513,778,801,2321` |
| Verdicts by output text: `-> FAIL`, `NEXT: `, `is parked`, ` task gate N `, ` panel x ` | `driver.ts:81,261,431-432` | the CLI's printed lines |
| An agent's free text: `DRIFT`, `TASK N: stopped:` | `driver.ts:221,427` | written by a model |
| The CLI's ASCII boxes parsed back into rows | `driver.ts:88-137` | `temper panel` |
| The fix run's prompt and steps, copied from the page | `driver.ts:470-502` | `commands/fix.md:44-68` |
| The view's shape: 90 lines of types, hand parsed | `core/runview.ts:32-90,142-291`; `types/index.d.ts:14-39` repeats the drawn shape "on purpose" (`:3-6`) | `flow.py:2797-2820`, `scripts/cli_ctx.py` |

The view's version is 1 and has never changed (`runview.ts:5`; one commit ever set it: a17c0e7, 9.7.0 [ran: `git log
-S`]), while fields were added in 9.7.5, 9.7.6 and 9.8.0 (`runview.ts:21,48-55,76`). So the version check
(`runview.ts:150`, `adapter.ts:193-204`) does not catch a change of shape.

### 2.4 What that coupling costs when the flow changes

- **Fixtures.** `scripts/selftest/view-fixtures.ts` (259,060 bytes, 12,335 lines, 34 views) and
  `view-fixtures-2.ts` (78,629 bytes, 3,534 lines, 9 views) are the CLI's `view.json` at 43 points of a run,
  generated by `scripts/selftest/make-view-fixtures.sh` and compared byte for byte by a self test case
  (`scripts/selftest/temper-cases-8.sh:455-458`) [ran: counts]. Any change to a question's text, an option, a
  prompt or a view field changes them: PR #115 changes 142 lines of the first file for 19 lines of mod code
  (`git diff --stat origin/main...HEAD`) [ran]. 8 commits have touched the first file, 5 the second, out of 133
  [ran]. The first file is at 98.8% of the plugin directory's 256 KiB limit (`scripts/quality-check.sh:21-27`);
  `scripts/temper` is at 260,504 bytes, 1,640 under it [ran].
- **Tests assert question text.** e.g. `scripts/e2e/scenarios.ts:351-356`; the answer audit walks every option of
  every fixture (`docs/decisions/0016-the-mod-answer-audit.md:19-22`, `tests/mod/audit.test.ts`).
- **Three defects found by running the mod's code on the CLI's own output** (none is caught by the 1,774 tests):
  1. **The Context check is never parsed.** The CLI writes `context_check.question` as an object holding header,
     question and options (`scripts/flow.py:2340-2341`; fixture `view-fixtures-2.ts:833-866`). The mod reads
     `context_check.question` as the question's text (`core/runview.ts:132-137`), so `question()` returns null
     (`runview.ts:105-108`) and `view.contextCheck` is always null [ran: `parseRunView` on the fixture gives null].
     A picked option still counts (the check is also `view.ask`). A **typed** answer never counts
     (`answers.ts:77-88` needs `contextCheck`), so the CLI's own call `plan review --answer '<text>' --redo` is
     refused as "Only the user decides this" [ran: `answersIn` counted 0, `evaluate` denied]. The test that covers
     the typed answer builds `contextCheck` by hand (`tests/mod/audit.test.ts:82-84`), which is why it passes. In
     place since 9.7.5 (f418c65).
  2. **The typed answer cap.** PR #115 raises the CLI's cap to 2,000 characters (`scripts/plan_ops.py:28`); the
     mod still counts 100 at most (`answers.ts:81`, asserted at `tests/mod/audit.test.ts:104-105`) [code]. Moot
     while defect 1 stands.
  3. **A fix run gets no branch under the real mod.** `driver.ts:502` runs a shell line (`if grep ... git checkout
     -q -b fix/<slug>`). The engine side runs only the plugin CLI by argument list and returns 126 for anything else
     (`argv.ts:80-85`, `register.tsx:476-477`), and `driver.ts:502` ignores the result [ran: `cliArgv` returns null
     for that line]. The e2e runs it through `bash -c` (`scripts/e2e/world.ts:54-55`), and the unit test only asserts that a fake port was handed the line (`tests/mod/driver.test.ts:321`;
     `tests/mod/driver.test.ts:303`), so they pass. Since 9.8.1, when `bash -c` was taken out
     (`CHANGELOG.md:205-209`). Consequence [inferred]: with the git pack on, a driven `/temper:fix` started on main
     stays on main (I found no CLI call that makes a `fix/` branch: a grep of `scripts/` for it is empty).
- **Docs that no longer match the code.** ADR 0016 decision 4, "The mod still runs nothing and sets nothing"
  (`docs/decisions/0016-the-mod-answer-audit.md:24`), against the driver, which runs the CLI and launches agents
  (`register.tsx:475-507`). ADR 0013 decision 5, "The mod's shell parser is deleted"
  (`docs/decisions/0013-...md:76-79`), against `core/shell.ts` at 688 lines with brace expansion, ANSI-C quotes,
  here documents and substitutions. `core/config.ts:3`, "The mod reads no `.claude/temper.config`", against
  `driver.ts:502`, which greps it (and never runs, defect 3). `tests/mod/driver.test.ts:165`'s title says an option
  with a `do` "runs its calls, then hands back"; the code hands back before any call (`driver.ts:292-296`).

## 3. Without the mod

| Question | Answer | Source |
|---|---|---|
| What runs the loop | The conversation follows `commands/temper.md` (215 lines) over `temper go` | `commands/temper.md:64-73` [code] |
| On which model | Sonnet (`model: sonnet`); a door has no model line, so the session's own | `commands/temper.md:4`, `commands/fix.md:4` [code] |
| Why not Haiku | Unguarded, the Haiku loop left the script in 2 of 8 runs (edited house rules and committed them; started a run from a one line summary, 17 of 26 hidden tests) | `bench-2026-11.md:410-415` [doc] |
| Cost of the loop itself | $0.28 to $0.97 a run, 22 to 59 turns; before round 5, $0.30 to $0.82, 47,000 to 71,000 tokens of context a turn | `bench-2026-11.md:446`, `:234` [doc] |
| Whole run, mod against no mod | cent-mismatch $0.45, 89 s against $0.84, 147 s; tenant-leak $0.89, 200 s against $0.81, 177 s (one hand back); vague-refunds $1.93, 661 s against $2.95, 812 s; partial-payments $2.28, 865 s against $2.95, 827 s | `bench-2026-11.md:427-430` [doc] |
| Time outside the agents | 42 to 103 s a feature run with the mod, 183 to 206 s without; 13 to 14 s a bug run with, 66 to 73 s without | `bench-2026-11.md:482-484` [doc] |
| Same flow | The e2e runs every scenario plain and with the mod's rules and fails when the traces differ | `scripts/e2e/run.ts:27-31` [code] |

Safety lost without the mod [code/doc]: every refusal of section 2.1 (nothing checks that the person answered
before a person only call; nothing holds a stage to its writes or Build to the plan's files; nothing refuses
`--no-verify`), the bar, the pane and the mod's report. What stays: the CLI computes every verdict and refuses to
leave a failed stage without an override, the native pre-commit hook, the evidence ledger, three classic hooks
(`docs/mod.md:117-128`, `docs/decisions/0013-...md:122-123`, `hooks/hooks.json:4-34`). The three classic hooks cost
23 ms per Bash call, 24 ms per prompt, 9 ms per stop [ran, outside a Temper project].

## 4. Dependence on Claude Code versions and private surfaces

| Dependence | Where | Fragility |
|---|---|---|
| Minimum version 2.1.287; below it, or with a version it cannot parse, the mod is inert | `core/config.ts:31-51`, `adapter.ts:187-188` | Fails safe (no driver, no guard, Sonnet loop) |
| "The mods API of Claude Code is early access and can change" | `docs/mod.md:147-150` [doc] | The owner's own words |
| 15 hook registrations: `session.start`, `classic.SessionStart`, `command.run`, `attribution.text`, `tool.call`, `prompt.compose`, 6 x `ui.render`, `ui.close`, `turn.complete`, `turn.step` | `register.tsx:705-944` [code] | Each is engine surface |
| 20 `$` calls on a reviewed list; CI fails on one more or one fewer | `scripts/check-mod-calls.sh:26-45,80-105` [code] | The check parses the `calls:` line `claude plugin validate` prints (`:60-77`) and fails if the validator cuts it (`:65-68`) |
| Fields the types do not give, reached by casts: `next.signal`, `e.agentId`, `e.questions`, `result.isError`, `result.deny` | `register.tsx:731,755,786,790,805-806` [code] | Untyped, so a change is silent |
| The driver lives inside one `command.run` hook for the whole run (600 to 870 s, waits of up to 90 minutes) and relies on `$` calls not being time bounded | `register.tsx:463-466,755` [code] | An undocumented budget rule |
| `$.ui.ask` takes labels only: the mod's own `tool.call` hook rewrites the dialog it just raised, through two module variables | `register.tsx:533-574,789-796`, `driver.ts:55-75,159-175` [code] | Private coupling between two hooks |
| The engine reloads the module mid session and every variable starts over | `register.tsx:30-35` [code] | Cost one benchmark pass (`bench-2026-11.md:295-297,302-303`); `agentEnds` and `asking` are still module state (`register.tsx:40,535,549`) |
| Types generated by loading the plugin (`claude -p "hi" --plugin-dir .`) before `tsc` | `.github/workflows/quality.yml:112-119` [code] | CI needs a real Claude Code |
| CI: the `Mod (Claude Code 2.1.287)` job pins the version; `Official Manifest Validation` installs the latest | `.github/workflows/quality.yml:76-79,99-111` [code] | 2.1.323 broke `validate --strict` "on main as well" (no MultiEdit in its types, a new band prop): `CHANGELOG.md:159-162` [doc] |
| Today | Claude Code 2.1.325 here: `claude plugin test .` gives 1,774 pass, 0 fail, 34 s [ran] | Works now |
| The plugin directory | 11 releases answer its holds on the mod: 9.6.1 to 9.6.7, 9.7.1 to 9.7.3, 9.8.1 (`CHANGELOG.md:200-216,843-846,905-908,958-961,1186,1285,1387,1584,1628,1636,1665`). "This plugin includes a mod" always goes to a reviewer (`:845,907`); hooks, mods and scripts are accepted only from Verified organizations (`:202-203`) [doc] | The holds shaped the code: no shell (`argv.ts`), no file written, no setting set, no file over 256 KiB, no folder named `tests` or `hooks` in a test's throwaway project |
| Organization policy can switch the mod off (`allowManagedModsOnly`, `disableAllHooks`) | `docs/mod.md:152-162` [doc] | Then the Sonnet loop |
| Surfaces: no drawing in the VS Code panel, `claude -p`, cloud sessions; in `claude -p` with enforcement on "a run stops at the first gate" | `docs/mod.md:135-145` [doc] | The driver needs a person for every question |

## 5. Size and complexity

### 5.1 Lines per file (4,984 lines of TypeScript, plus `hooks/hooks.json` 39 and `types/index.d.ts` 57) [ran: `wc -l`]

| Role | File | Lines |
|---|---|---|
| Driver | `core/driver.ts` | 597 |
| Driver | `core/argv.ts` | 86 |
| Guard | `core/shell.ts` | 688 |
| Guard | `core/rules.ts` | 531 |
| Guard (main session only) | `core/session.ts` | 283 |
| Guard (answers) | `core/answers.ts` | 123 |
| Guard (answers) | `core/decisions.ts` | 96 |
| Guard | `core/paths.ts` | 52 |
| Drawing | `core/view.ts` | 327 |
| Drawing | `ui/pane.tsx` 183, `ui/band.tsx` 106, `ui/palette.ts` 36, `ui/question.tsx` 19, `ui/hint.tsx` 17, `ui/spinner.tsx` 10, `ui/kit.ts` 4 | 375 |
| Drawing | `core/report.ts` 76, `core/section.ts` 43, `core/modes.ts` 28 | 147 |
| Shared | `register.tsx` (wiring: about 160 lines driver, 90 guard, 120 pane and root, the rest hooks) | 945 |
| Shared | `adapter.ts` | 297 |
| Shared | `core/runview.ts` (the view parser) | 291 |
| Shared | `core/config.ts` 63, `core/stages.ts` 33, `core/commands.ts` 31, `core/cli.ts` 19 | 146 |

Totals: driver 683, guard 1,773, drawing 849, shared 1,679.

### 5.2 Tests [ran]

- `tests/mod`: 40 test files and 3 helpers, 7,245 lines; 578 `test(` sites; **1,774 tests as run**, 0 fail, 34 s on
  Claude Code 2.1.325.
- Files whose subject is reading shell text against a model set on getting round the guard: `hardening` 591,
  `commit-hook` 355, `final-review` 245, `audit-round4` 243, `review-exploits-3` 154, `review-exploits-2` 139,
  `security-round3` 134, `known-limits` 120, `shell` 87, `security-round2` 86, `review-exploits` 70 = 2,224 lines,
  34% of the 6,498 lines of test files. ADR 0013 named this as the cost it meant to end
  (`docs/decisions/0013-...md:20-24`).
- Generated fixtures: 337,689 bytes, 15,869 lines, 43 views.
- e2e: `scripts/e2e`, 1,977 lines, 23 scenarios in 3 modes (plain, mod, driver). One scenario in one mode took 32
  to 48 s here, so about 45 minutes for all 69; the CI limit was raised from 45 to 60 minutes
  (`CHANGELOG.md:153-154`, `.github/workflows/quality.yml:89`). The `fix` scenario fails here in every mode because
  pytest is not installed in this container (not a mod fault).

### 5.3 What exists only to hold a model in the main session

| Part | Lines | Why it exists | Still needed if the main session never runs a model during a run? |
|---|---|---|---|
| `core/session.ts` | 283 | "a cheaper model for the session cannot leave the script" (`session.ts:1-6`) | Only for the hand back path and the runs the driver does not carry (doors, run words) |
| The request kept per project and conversation, and `featureWhy` | `register.tsx:410-418,429-431,452-457,742-746,828-834`, `session.ts:217-255` | A Haiku session summarized the request | No: the driver passes it whole (`driver.ts:345`) |
| The skill window | `register.tsx:405-427,820-824`, `session.ts:61-79` | Lets a skill's own questions through the question rule | Only because the question rule exists |
| `next.agents` in the view and `.temper/agents-named.json` | `runview.ts:48-50` | So the launch rule survives a module reload | Only for the launch rule |
| The hand back protocol (`next`, `discuss`, `chose`) | `register.tsx:580-586`, `commands/temper.md:24-28,42-43` | To pass a run to a model | No, if nothing is handed to a model as a run |
| `answers.ts`, `decisions.ts`, the decision book in `adapter.ts:136-181` | about 280 | To prove that the person, not the model that asked, chose | Under the driver the answer comes straight from `$.ui.ask` and the driver runs the calls by `$.process.spawn`, which is not a tool call, so the allow list is read only after a hand back and for the report's "Your decisions" [inferred from `register.tsx:475-491,576-578`] |
| `tests/mod/session.test.ts` and the session parts of `dialog`, `state-machines` | 240 and more | | |

What a driver does **not** remove: `rules.ts`, `shell.ts` and `paths.ts` (1,271 lines) also judge the stage agents
(Haiku and Sonnet Build task agents with Bash), which stay models.

## 6. One approval before Build, one at the commit

### 6.1 Where a clean run asks today [ran: e2e, scripted agents, every check passing first time, driver and plain modes alike]

| Setup | Questions | Which |
|---|---|---|
| Default, 2 groups | 7 | Intent, Plan, group G1, group G2, Build, Review, Check ("Commit?") |
| Default with Design, or 3 groups | 8 | the same plus Design, or G3 |
| `autonomy: enabled: true`, and the person picks "Autonomous Build" (not the recommended option) at the Plan question | 4 | Intent, Plan, Review, Check |
| The same plus `autonomy.policy: decide` (PR #115) | 3 | Intent, Plan, Commit ("the armed run parked here for you") |

Every one of the 7 or 8 default questions offers "(Recommended)" first on a check that passed. Blocking questions
(four to a dialog) and the Context check come on top when the intent or the plan leave something open.

In all four setups the driver carried the run to the end with 6 agent launches (7 with Design or a third group), no
hand back and no refusal [ran]. These are mock projects with scripted agents: they show which questions the flow
asks, not what a real run costs.

### 6.2 What the mod itself needs

**Nothing in the guard for the gates to go.** A gate becomes silent when `scripts/flow.py` returns it as an `auto`
action instead of `ask`. `temper go` runs `auto` calls inside the CLI (`scripts/go.py:95-106`), so no tool call
reaches the guard; and for a conversation the calls of the CLI's own action are on the allow list
(`adapter.ts:231`, `rules.ts:461`) [code]. The armed policy run above is the proof [ran]. The guard's list of person
only calls (`rules.ts:476-497`) needs no edit; what it means changes (leaving Intent would be the CLI's move, not the
person's), so ADR 0013 decision 5 and `docs/mod.md:11-12,177-179` would need to say so.

What does need work, in order of weight:

1. **The mod carries every way into a run.** Doors, run words and a request while another run is active go to the
   model loop today (`register.tsx:611-619,723-741`).
2. **A hand back returns.** Today it is one way (section 1.5). Either the conversation does the one handed step and
   stops (the person types `/temper:temper`, one keystroke more), or the step is done without the conversation: an
   agent the driver launches (`$.agent.spawn` is on the reviewed list, `check-mod-calls.sh:27`) or a CLI call.
3. **The hand backs that need no person and no model go**: a failed group check (`scripts/go.py:108-109`: read
   `group gate` as a verdict, as `driver.ts:77-82` already reads `task gate`); "Cancel" at the accept question
   (`flow.py:1088`); raw
   `git add`/`git commit`, `git checkout -b`, `git rebase` (`flow.py:631,1818,2207-2208`), which need a `temper`
   subcommand each because the mod runs only the CLI; the pull request steps (`flow.py:2210-2217`), likewise; the
   name question after three tries (`driver.ts:308-316`); a placeholder the driver cannot fill (`driver.ts:318`).
4. **The hand backs that need a model get an agent, not the session**: a small change (`flow.py:907-913`), DRIFT
   rows (the CLI would have to read them from a record the agent writes, not from its free text: `driver.ts:221`),
   a failed `integrate` or after call (causes 6, 11, 14).
5. **A typed answer is routed by the driver**: record the note and run `state redo <stage> --reason`, which is what
   the page tells the model to do at Intent, Plan, Design and Build (`commands/temper.md:154-162`). Telling a
   question from a change request is the one judgment in it.
6. **The two approval dialogs must carry what is approved.** `$.ui.ask` gives labels and four options
   (`register.tsx:540`); descriptions and a preview come only through the mod's own hook (`register.tsx:789-796`).
   The plan panel is shown as log rows before the question (`driver.ts:431`).
7. **A contract instead of text.** Section 2.3: step kinds, option kinds and verdicts as fields of `temper go`, and
   one schema file both sides are checked against, so a flow change does not need the mod and 338 KB of fixtures to
   follow.
8. **The three defects of section 2.4**, since a run with fewer questions leans harder on the ones left (the
   Context check is one of them).

What truly needs the person, and would stay as a question: Blocking questions, the Context check when the plan left
something out, Scope drift, a parked armed run (the policy does not decide: `flow.py:1139-1156`), a manual task's
confirmation, an override. A surface with no person (`claude -p`) has no answer for any of them today
(`docs/mod.md:141`).

## 7. Constraints any redesign must keep

- The person decides only in a question dialog; no button that decides in the mod (`.claude/CLAUDE.md`, Known
  mistakes; `docs/decisions/0012-...md:37-41`).
- The CLI is the only run state; the mod reads one file, `.temper/view.json`, and keeps nothing about the run
  (`docs/decisions/0013-...md:42-47,93-97`; `adapter.ts:4-6`).
- Gate logic lives in `scripts/temper` and `scripts/flow.py`, never in a prompt or the mod (`.claude/CLAUDE.md`).
- Hooks fail open except on their one detected violation (`.claude/CLAUDE.md`; `register.tsx:690-691`). One
  exception in code: Bash is refused when the guard throws during a run (`register.tsx:393-396`).
- The mod runs only the plugin's own CLI, by argument list, no shell; writes no file; sets no setting; makes no
  `http` or `env` call; its `$` calls are exactly the reviewed list (`scripts/check-mod-calls.sh:5-12,26-45`;
  `core/argv.ts:1-8`; `CHANGELOG.md:205-209`). The plugin directory holds a release otherwise.
- No tracked file over 256 KiB (`scripts/quality-check.sh:21-27`); `userConfig` declares no `options`
  (`core/config.ts:1-3`).
- With the mod off or inert, every phase works the same (`docs/mod.md:115`, `docs/trust.md:3`); the e2e fails when
  the flow with the mod differs from the flow without it (`scripts/e2e/run.ts:27-31`).
- After a mod, wiring or drawing change: `claude plugin test .`, `tsc -p tsconfig.mod.json` (TypeScript 5.6),
  `bash scripts/check-mod-calls.sh`; fixtures regenerated with `make-view-fixtures.sh` (`.claude/CLAUDE.md`).
- Never pushes or merges in an armed run; every pull request is a draft (`rules.ts:350-352,438`).

## 8. Could not determine

- Whether a hook other than `command.run` (for example `turn.complete`) may run for minutes, which decides whether
  the mod can take a run back after a hand back without the person typing.
- Whether `$.agent.spawn` passes through `tool.call` (so the launch rule judges the driver's own launches).
  `docs/mod.md:292` says the guard checks the driver's agents; I found no code path that shows it.
- The per call cost of the guard in a real session (two view reloads per Bash call: `register.tsx:436,829`). It
  cannot be timed without the engine.
- How often real runs hit the typed Context check answer (defect 1 of 2.4).
- Why the `maven` e2e scenario does not finish here (200 s in plain mode, about 17 minutes in driver mode before I
  stopped it, repeating `group reopen G1 --task 1`). It may be this container; I did not look further.
- Whether the real `temper group gate` prints a line `go.py` could read as a verdict; I saw only its exit code 1
  and its output's tail in the e2e trace.
