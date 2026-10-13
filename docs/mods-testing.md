---
title: Testing the mod on your laptop
nav_order: 10
---

# Testing the mod on your laptop

Nothing is merged or released until you have run it in your own terminal. Tick each box
by hand. Every step has the exact command and the result you should see. If a result
differs, stop and write down what you saw.

Your clone is loaded for one session with `--plugin-dir`. That does not install anything
and does not touch the Temper you already have. The one thing the test writes outside the
clone is the mode and enforcement you set with `/temper:temper mode` and
`/temper:temper enforcement`, which the last step sets back to the defaults.

In the commands below, `<clone>` is the path of your Temper clone. The short form `/temper` is an interactive shortcut that may not resolve in every surface (in `claude -p` it does not, and with the installed Temper and the clone both loaded it is an unknown command), so this checklist always types the full name `/temper:temper`.

## 1. Preparation

- [ ] **Claude Code 2.1.287 or later.**
  Run `claude --version`. Expect `2.1.287` or higher. If it is older, run `claude update`.
- [ ] **Pick what to test.**
  In your Temper clone, check out the commit you want to test. Expect `git status` to show
  it.
- [ ] **Turn off the installed Temper for the test**, so only one Temper runs.
  Run `claude plugin list` and find the id of Temper (it looks like `temper@<marketplace>`).
  Then run `claude plugin disable <that id>`. Turn it back on at the end with
  `claude plugin enable <that id>`. If Temper is not installed, skip this step.

## 2. Automated checks

Run these from `<clone>`. None of them sends a request.

- [ ] `claude plugin validate --strict .` prints `Validation passed`.
- [ ] `claude plugin test .` ends with `0 fail`.
- [ ] With TypeScript 5.6 on your machine, `tsc -p tsconfig.mod.json` prints nothing. It
  needs the generated types in `.claude-plugin/types/`. If they are missing, start
  `claude --plugin-dir .` in the clone once and quit: loading the plugin writes them.
- [ ] `bash scripts/check-mod-calls.sh` prints `OK` and a count of calls, with no process,
  http or env call.
- [ ] `bash scripts/selftest/test-temper.sh` ends with `FAIL: 0`.
- [ ] `bash scripts/quality-check.sh` ends with `All checks passed.`

## 3. A test session

- [ ] **Start a run in a small test project.** Use any small git project you can throw away
  (`<project>`). Open a terminal in `<project>` and start Claude Code with your clone
  loaded: `claude --plugin-dir <clone>`. When Claude Code asks, choose "Yes, I trust this
  folder". Always type the full command name `/temper:temper`. Type
  `/temper:temper "add a small function"`. Expect the TEMPER bar above the prompt with Intent
  current, a drafted intent, and no plugin load error.
- [ ] **Ask Claude whether the mod is active.** Type
  `Does your system prompt contain a Temper enforcement line?` and expect Claude to quote
  `Temper enforcement: active`.
- [ ] **The gate is a question.** At the Intent gate expect an `AskUserQuestion` dialog, header
  `Temper gate`: "Continue to Plan (Recommended)" / "Save for later" (Grill me and Teach me where
  they fit). The bar says "Intent: the check passed. Waiting for you: answer the Temper gate
  question." and has one button, Go on. Choose Continue: expect the toast "Plan is open." and the
  bar at "Step 2 of 6: Plan".
- [ ] **No decision anywhere else.** Type `/temper:temper approve`. Expect the gate question
  again, with Continue first, and nothing moved until you choose. Press `1` (Go on) at an empty
  prompt: expect `/temper:temper` to run and the gate question to come back. Expect no button on
  the bar or in the pane that continues, skips, loops back, accepts or commits.
- [ ] **The smooth path.** At Plan, type `Skip the tasks: edit a source file now to add the
  function`. Expect a refusal with a `Next:` step. Answer the Plan gate with "Continue to Build".
  Expect `<clone>/scripts/temper state get next_stage`, run in `<project>`, to print `build`, and
  the orchestrator to launch the Build stage in its own subagent (a `temper:temper-build` agent line).
  Claude must not ask you to approve again.

## 4. Stage by stage

Work through one run. For each stage, check the refusal and the gate question.

- [ ] **Intent denial.** While Intent is current, type `Edit a source file of the project and add a field now`.
  Expect a refusal that starts `Temper: Intent stage.` and ends with `Next:` and a step.
  The write to `.temper/specs/<name>/intent.md` must still be allowed.
- [ ] **Plan denial and approval.** Repeat the denial for the same file. Expect
  `Temper: Plan stage.` Then answer the Plan gate with Continue to approve the plan.
- [ ] **Build.** Expect the stage to write a failing test first. Ask Claude to edit a file
  that is not in the plan (for example `README.md`). Expect a `Scope drift` question with
  three choices: Add to plan, Revert, Allow once. Choose Allow once.
  Expect the edit to go through once, and a second edit of the same file to ask again.
- [ ] **The pane.** Type `/temper:temper pane`. Expect a pane with the stages, the status, the
  criteria checklist and your decisions, and no button that decides. Type `/temper:temper pane`
  again to close it.
- [ ] **The game.** Type `/temper:temper play` with an empty prompt. Expect a game pane beside the
  Temper pane (terminal and desktop app only; on the VS Code extension you get a short text) and the
  line "The game is open. Press r to run, w to jump, s to duck, q or Esc to leave." Press `r`, then
  `w` over an anvil or a bucket and `s` under a flying hammer, with no mouse. Expect Ember the dragon
  (orange, with horns, a wing and a flame at the tail), anvils, buckets of cold water and spinning
  hammers, a floor of bricks and embers, and the line "HI 00000  00032" at the top right. At every
  100 points expect a banner "Hot! 100" and a yellow flash. Let Ember hit something and expect
  "Game over. Your forge went cold." and "Press r to run again. q or Esc leaves.", and the button
  `r  Run again`. Press `q` and expect the pane to close. While the game is open, ask Claude to edit
  a source file: expect the same refusal as without the game. Press Esc and expect the pane to close
  and the prompt to work. Resize to 80 columns and open it again: the picture must fit.
- [ ] **The game feels right.** With the Buttons only (no click), expect a jump to start within a
  fraction of a second of the key (measured here: about 40 ms, see `docs/mods-plan.md` 3.8a). A jump pressed
  just before landing must fire on the landing. After one click on the game, Space and the Up arrow
  must jump at once and the Down arrow must duck.
- [ ] **The game offer.** Send a prompt that takes a while ("Write a 300 word essay about forges").
  While Claude works, expect `8 Play while you wait` on the bar (`8 Play` when the bar is
  narrow), "8  Play while you wait" in the pane, and "Press 8 to play while you
  wait." at the start of the hint line under the prompt (terminal). Press `8` at the empty prompt and
  expect the game pane with the keys, so `r` runs. When Claude stops, expect the offers
  to go away. Open it again and wait 4 seconds without a key: expect the dim line "No keys yet?
  Press Ctrl+X, then Tab, to give the game the keys." and expect it to go when you press a key.
  Set the plugin setting `game` to `command` and expect no offer anywhere, while
  `/temper:temper play` still works. Set it to `off` and expect "The game is off. Set game to on in
  /config."
- [ ] **A skip needs a reason.** At a failed check choose "Override and continue" with no reason.
  Expect the question `Override and continue. What is the reason?`; choose Cancel and expect the
  gate again and no stage change.
- [ ] **Commit gate.** Before Check passes, ask Claude to run `git commit -am wip`. Expect the native
  hook to block it with the gates that are not passed. Ask for `git commit --no-verify -am wip` and
  `git merge` of another branch: expect a `Temper:` refusal from the mod for each.
- [ ] **Review and Check.** Answer each gate. After Check passes, type `/temper:temper report`.
  Expect the report, listing the stages, any skip and every decision with its reason. It is kept
  in the mod's plugin store, so expect no `.temper/report.md` file.
- [ ] **Forgery.** Ask Claude to write `.temper/gates.json` or to run
  `scripts/temper override plan --reason ok`. Expect a refusal that says only the user decides.

## 4a. Grouped Build and the cases found in hands-on runs

Each step below is a problem a real run hit once. Run them on a small project (a copy of a small
Python repository is enough), with a feature that splits into at least two tasks.

- [ ] **Blocking questions are buttons.** Start a run whose intent leaves a choice open (for
  example "list N jokes", without saying what happens when N is larger than the list). Expect
  an `AskUserQuestion` dialog with one question per Blocking question and its choices as
  options, never a list of questions to answer by typing. Expect the answers under
  `### Decisions` in `intent.md`.
- [ ] **Cases in the plan.** After Plan, open `tasks.md`. Expect `**Cases:**` under every task
  with at least 2 concrete cases (an input and its exact expected result).
- [ ] **Tasks in their own worktrees.** During Build, expect the folders
  `.claude/worktrees/temper-<name>-T<N>` while tasks run, tasks of one group running at the
  same time, and one gate per group (not one per task). The bar lists the groups and their tasks.
- [ ] **A pattern for the task agent.** Run `<clone>/scripts/temper task show <N>` while a
  task runs. Expect a `--- PATTERN TEST (...)` block with an existing test of the project
  (none when the project has no test of that kind).
- [ ] **Change at a group gate.** At a group gate (a `Build group` question) choose Change and type
  a small change. Expect only the named task to run again, and the group gate to come back.
- [ ] **A parked group.** Ask a task agent to commit its own work (or commit in its worktree by
  hand). Expect its task gate to fail, the group to park with the commit named, and two ways
  out printed. Follow one and expect `group reopen` to be accepted.
- [ ] **No false failures.** After Build, run `<clone>/scripts/temper group report`. Expect
  every task with its attempts in plain words. A failed attempt must name its model and its
  reason; an attempt with "no model given to task gate" means the orchestrator gated a task
  before its agent ran: stop and report it.
- [ ] **Tokens in the report.** Type `/temper:temper report`. Expect a Usage section with tokens
  and time per stage and per model, and a total.
- [ ] **A reused feature name.** Finish or clear a run, then start a new run with the same
  feature name. Expect the Intent gate's Continue to go through and Plan's `state set complexity`
  not to be refused.
- [ ] **Model choice.** Set `build.grouped.task-model: claude-sonnet-5-5` and run once. Expect
  the task agents and the report to name that model.

## 4b. Every wait point, with the mod and without it

The rule for every step below: you go on with an option of a dialog. You never type
`/temper:temper` or a CLI command to go on, Claude never tells you to press a key or a button
that decides, and an option you click is never refused. If any of that happens, stop and write
down the step, the setup and the text you saw.

Use a small Python project you can throw away (`<project>`), with pytest installed:

```
mkdir -p ~/temper-try/jokes && cd ~/temper-try/jokes && git init -q
printf 'JOKES = ["a", "b", "c"]\n\ndef first():\n    return JOKES[0]\n' > jokes.py
mkdir tests && printf 'from jokes import first\n\ndef test_first():\n    assert first() == "a"\n' > tests/test_jokes.py
git add . && git commit -qm base
```

Run the steps twice, once per setup. The mode changes only what is drawn, so one mode is enough;
section 5 checks the modes.

| Setup | How to start it | First check |
|---|---|---|
| No mod | `npx -y @anthropic-ai/claude-code@2.1.259 --plugin-dir <clone>` (the mod is inert before 2.1.287) | The first reply line is `Temper enforcement is off here (no mods support); ...` |
| Mod | `claude --plugin-dir <clone>` | The TEMPER bar above the prompt |

Then once more with the mod and `/temper:temper enforcement off`: every click below works the
same, nothing is refused, and the first reply line says enforcement is off. Turn it back on.

Start with `/temper:temper "list N jokes, and say what happens when N is larger than the list"`.
Every "dialog" below is an `AskUserQuestion` dialog, header `Temper gate` unless it says otherwise.

- [ ] **Blocking questions.** One dialog, one question per Blocking question, three choices at
  most plus "Carry forward". Never a list of questions to answer by typing.
- [ ] **Intent gate.** A dialog "Continue to Plan (Recommended)" / "Save for later" (Grill me,
  Teach me where they fit). Choose Continue: Plan starts.
- [ ] **Plan gate.** A dialog of four options at most, the rest behind "More options". Choose
  Continue: Build (or Design, for a medium run with `phases.design: true`) starts.
- [ ] **Arming autonomy.** Add `autonomy:` and `  enabled: true` to `.claude/temper.config` and
  start a new run. At the plan gate: a dialog "Stage by stage (Recommended)" / "Autonomous: run
  the rest unattended" / "Save for later". Choose Autonomous: the run goes on without asking, and
  nothing is refused. Remove the lines afterwards.
- [ ] **Design gate** (a medium run with `phases.design: true`). On a failed design check: a dialog
  "Loop back to Plan" / "Override and continue" / "Save for later". Choose Override and continue
  and give a reason: Build starts, and `<clone>/scripts/temper report` lists the skip of design.
- [ ] **A group gate.** A dialog, header `Build group`: Continue / Change / Stop.
- [ ] **A parked group.** While a task runs, commit in its worktree by hand
  (`git -C .claude/worktrees/temper-<name>-T<N> commit -am x`). A dialog "Take the commits out
  and run the task again (Recommended)" / "Keep the agent's commits" / "Save for later". Choose
  Keep and pick a reason: the group reopens, nothing is refused.
- [ ] **Build completion gate on FAIL.** A dialog "Run Build again (Recommended)" / "Loop back to
  Plan" / "Override and continue" / "Save for later".
- [ ] **Review with open findings.** A dialog "Loop back to Build (Recommended)" / "Accept a
  finding" / "Override and continue" / "Save for later". Choose Accept a finding, pick the
  finding and a reason: the review check runs again. Choose Loop back to Build with a reason:
  Build runs again, its writes are not refused, and the bar shows Review and Check as to come.
- [ ] **The loop budget is spent.** Set `loops:` and `  max-per-type: 1` in
  `.claude/temper.config` and loop back from Review twice. The second time Claude says the
  budget is spent and asks again with "Override and continue" / "Save for later". Override with
  a reason: Check starts.
- [ ] **Check FAIL.** A dialog "Loop back to Build" / "Override and continue" / "Save for later".
- [ ] **Check PASS.** One dialog "Commit (Recommended)" / "Save for later" (and "Review config
  suggestions" when Check wrote them), never two dialogs in a row.
- [ ] **Commit gate FAIL.** Before you choose Commit, run `touch .temper/specs/<name>/design.md`
  in another terminal (the commit gate then wants a design check). A dialog "Override and commit"
  / "Save for later". Choose it and give a reason: the commit is made. Delete the empty
  `design.md` afterwards.
- [ ] **An autonomous park.** In an armed run, make Review fail twice (the loop budget). Expect
  the park report, then the dialog of the gate it parked at. Override with a reason: the run goes
  on, nothing is refused.
- [ ] **Save for later, then go on.** At any gate choose Save for later. With the mod, the bar says
  the stage is saved for later, and a write outside the stage is still refused. Start a new session
  and run `/temper:temper` (or press Go on): the gate dialog comes back, and Continue goes through.
  Pick "More options", then "Start over": a `Temper resume` dialog asks "Start over" / "Cancel".
- [ ] **Start over.** With a run saved, `/temper:temper "a different feature"`. A `Temper resume`
  dialog with "Start over". Choose it: the new run starts at Intent.
- [ ] **Scope drift.** Ask Claude in Build to edit `README.md`. A dialog, header `Scope drift`,
  with Add to plan / Revert / Allow once.
- [ ] **A fix run.** `/temper:fix "first() fails on an empty list"`. With the mod, in every mode:
  no bar for the fix run, `/temper:temper status` says the mod stands aside, nothing is refused,
  and every gate is a dialog (Proceed to Fix, Continue to Review, the review FAIL options,
  Commit). Without the mod: the same dialogs.
- [ ] **A stage command.** After a commit cleared the run, run `/temper:build` on a spec with an
  approved plan. Expect it to start `/temper` at Build: the same gates as above, and with the
  mod nothing else is refused.

## 5. Modes

- [ ] `/temper:temper mode minimal`. Expect the reply `Temper mode: minimal`, the stage chips
  only, no toasts and no pane. Denials still apply, and the gate is the same dialog.
- [ ] `/temper:temper mode off`. Expect the bar to disappear. Ask for a write in Plan and expect
  the refusal to still appear, and the gate to be the same dialog.
- [ ] `/temper:temper mode full`. Expect the full bar back, with no restart.
- [ ] `/temper:temper enforcement off`, then try a write in Plan. Expect the write to go through
  and a toast `Temper enforcement: off`. Run `/temper:temper enforcement on` to restore it.
- [ ] If you can, set `pluginConfigs` for Temper in a managed settings file so that
  `uiMode` is locked, then run `/temper:temper mode full`. Expect
  `Your organization set Temper's mode to <value>. Ask your admin to change it.`
  If you cannot set managed settings, mark this step as skipped.

## 6. Compaction and layouts

- [ ] **`/compact` keeps the marker.** Type `/compact`. After it finishes, ask
  `Does your system prompt contain a Temper enforcement line?` Expect `Temper enforcement: active`
  and the same stage.
- [ ] **`/clear` keeps the run.** Type `/clear`, then `/temper:temper status`. Expect the same
  stage as before, read from the CLI's files in `.temper/`.
- [ ] **A narrow terminal.** Resize to 80 columns. Expect the bar to wrap or truncate
  without breaking the prompt, and the pane to wait instead of squeezing in.
- [ ] **A wide terminal.** Resize to 160 columns in fullscreen. Expect the pane to dock beside
  the transcript.
- [ ] **Light and dark themes.** Switch the terminal theme and expect the bar to stay readable.

## 7. Old versions and other surfaces

The plugin must still load on old Claude Code versions and fall back to the prompt based
phases. For each version below, use a copy of Claude Code at that version, set up apart
from your own so it stays untouched, and ask it for `/temper:status` from `<clone>` with
the clone loaded (`-p --plugin-dir .`).

| Version | Expect |
|---|---|
| 2.1.259 | No load error. The answer comes through the prompt based path. |
| 2.1.200 | The same. |
| 2.1.286 | The same, or the mod stays inert. |

- [ ] The three rows above behave as described. On each, the answer must not mention a
  plugin load error. The message `Temper enforcement is off here (no mods support)` is
  correct and expected when a skill runs.
- [ ] **Enforcement turned off.** On a version that loads the mod, run
  `/temper:temper enforcement off`, then `/temper:status`. Expect the answer to open once with
  `Temper enforcement is off (turned off by the user)`, not the "no mods support" sentence.
  Turn it back on with `/temper:temper enforcement on`.
- [ ] **`claude -p` on your version.** Run `claude -p --plugin-dir . "/temper:status"`.
  Expect an answer and no question asked of you.

## 8. The desktop app

This part was not verified by the author. How to load a local plugin folder into the
desktop app depends on your installation, so treat the first step as an experiment.

- [ ] Open the Code tab of the desktop app on `<project>`. Load the clone as a plugin
  (for example by adding `<clone>` as a local marketplace through the plugin settings, with
  the installed Temper disabled as in step 1). If your build has no way to do this, mark
  the step skipped and note it.
- [ ] Start a run and expect the same stage bar and the same Plan denial as in the terminal.
  Open the pane and expect it to draw. Elements that only the terminal has are not used by
  the mod, so nothing should be missing.
- [ ] Switch to a WSL session if you use one. Plugins are unavailable there, so expect no
  Temper at all, and expect prompt based phases when you load the plugin in another way.

## 9. Clean up

- [ ] **Clear the saved mode.** In a session started with `claude --plugin-dir <clone>`, so
  the setting of the loaded clone is the one that changes, run `/temper:temper mode full` and
  `/temper:temper enforcement on` to put the defaults back. Expect the replies
  `Temper mode: full` and `Temper enforcement: on`.
- [ ] Enable the installed Temper again with `claude plugin enable <that id>`.
- [ ] Delete `<project>` if you made it only for this test.

When every box is ticked (or marked skipped with a reason), the change is ready to merge
and release with the existing release process.
