---
title: Testing the mod on your laptop
nav_order: 10
---

# Testing the mod on your laptop

Nothing is merged or released from the mods branch until you have run it in your own
terminal. Tick each box by hand. Every step has the exact command and the result you
should see. If a result differs, stop and write down what you saw.

The branch is loaded for one session with `--plugin-dir`. That does not install anything
and does not touch the Temper you already have. The one thing the test writes outside the
clone is the mode you pick with `/temper:temper mode`, which the last step clears.

In the commands below, `<clone>` is the path of your Temper clone. The short form `/temper` works only when no other plugin has the same command name. With the installed Temper and the branch both loaded it is an unknown command, so this checklist always types the full name `/temper:temper`.

## 1. Preparation

- [ ] **Claude Code 2.1.287 or later.**
  Run `claude --version`. Expect `2.1.287` or higher. If it is older, run `claude update`.
- [ ] **Get the branch.**
  Run `git fetch origin ccr-ea3cb3cc-wsa4sb && git checkout ccr-ea3cb3cc-wsa4sb` in your
  Temper clone (or a fresh clone). Expect `git status` to show that branch.
- [ ] **Turn off the installed Temper for the test**, so only one Temper runs.
  Run `claude plugin list` and find the id of Temper (it looks like `temper@<marketplace>`).
  Then run `claude plugin disable <that id>`. Turn it back on at the end with
  `claude plugin enable <that id>`. If Temper is not installed, skip this step.

## 2. Automated checks

Run these from `<clone>`. None of them needs you to be signed in.

- [ ] `claude plugin validate --strict .` prints `Validation passed`.
- [ ] `claude plugin test .` ends with `0 fail`.
- [ ] `npx -p typescript@5.6 tsc -p tsconfig.mod.json` prints nothing. It needs the
  generated types in `.claude-plugin/types/`. If they are missing, run
  `ANTHROPIC_API_KEY=sk-invalid claude -p hi --plugin-dir .` once, then run the command again.
- [ ] `bash scripts/check-mod-calls.sh` prints `OK` and a count of calls, with no process,
  http or env call.
- [ ] `bash scripts/tests/test-temper.sh` ends with `FAIL: 0`.
- [ ] `bash scripts/quality-check.sh` ends with `All checks passed.`

## 3. The demo session

- [ ] **Start the demo with one command.** From the root of your clone:

```bash
bash demo/run-demo.sh
```

  The script copies the demo project to `/tmp/pr-demo`, seeds a Temper run in the Intent
  phase, checks your Claude Code version, switches off your installed Temper for this one
  process only (so the branch is the only Temper, and your settings are untouched), and
  starts Claude Code with the branch loaded. When Claude Code asks, choose "Yes, I trust
  this folder". Always type the full command name `/temper:temper`.
  Expect the TEMPER bar above the prompt and no plugin load error. The folder is watched, so a
  `git pull` in `<clone>` reloads the mod without restarting.
- [ ] **Ask Claude whether the mod is active.** Type `/temper:temper status`. Expect an answer
  that starts with `No Temper run is active`. Then type
  `Does your system prompt contain a Temper enforcement line?` and expect Claude to quote
  `Temper enforcement: active`.
- [ ] **Start a run.** Type
  `/temper:temper Add password reset: one time token that expires after one hour`.
  Expect a phase bar above the prompt with Intent current, and a drafted intent.

## 4. Phase by phase

Work through one run. For each phase, check the refusal and the key.

- [ ] **Intent denial.** While Intent is current, type `Edit src/users.js and add a resetToken field now`.
  Expect a refusal that starts `Temper: Intent phase.` and ends with `Next:` and a step.
  The write to `.temper/specs/<name>/intent.md` must still be allowed.
- [ ] **Approve Intent with a key.** When the intent gate passes, press `1`. Expect the
  band to show Plan as current and a toast naming the new phase.
- [ ] **Plan denial and approval.** Repeat the denial for `src/users.js`. Expect
  `Temper: Plan phase.` Then press `1` to approve the plan.
- [ ] **Build.** Expect the first action to be a failing test. Ask Claude to edit a file
  that is not in the plan (for example `README.md` in the demo). Expect a question with
  three choices: Add to plan, Revert, Allow once. Choose Allow once and give a reason.
  Expect the edit to go through once.
- [ ] **The pane.** Type `/temper:temper pane`. Expect a pane with the criteria checklist, the
  phase and a short timeline. Type `/temper:temper pane` again to close it.
- [ ] **The game.** While Claude works, press `p`, or type `/temper:temper play`. Expect a game pane
  beside the Temper pane (terminal and desktop app only; on the VS Code extension you get a short
  text). Click the game once, press Space to start, and jump with Space. Let it end and expect
  "Game over" and your best score. While the game pane is open, ask Claude to edit `src/users.js` and
  expect the same refusal as without the game. Press Esc and expect the focus back in the prompt.
  Press `1` to approve and expect the banner "Temper: Intent is ready. Press Esc to go back." or the
  new phase in the banner. Set the plugin setting `game` to `off` and expect no `p Play` button.
  Run `/temper:temper play` again and expect the game to close.
- [ ] **Override needs a reason.** Press `9`. Dismiss the reason question without an
  answer. Expect a toast that an override needs a reason and no phase change.
- [ ] **Commit gate.** Before Check passes, ask Claude to run `git commit -am wip`. Expect
  `Temper: commit blocked. Check has not passed.` After Check passes, the same command
  must be allowed.
- [ ] **Review and Check.** Press `1` at each band. Expect `.temper/report.md` after Check
  passes, listing the phases, any override and every scope decision with its reason.
- [ ] **Forgery.** Ask Claude to write `.temper/gates.json` or to run
  `scripts/temper override plan --reason ok`. Expect a refusal that says only the user can
  approve.

## 5. Modes

- [ ] `/temper:temper mode minimal`. Expect the reply `Temper mode: minimal`, the bar with no
  action buttons, no toasts and no pane. Denials still apply.
- [ ] `/temper:temper mode off`. Expect the bar to disappear. Ask for a write in Plan and expect
  the refusal to still appear.
- [ ] `/temper:temper mode full`. Expect the bar and the buttons back, with no restart.
- [ ] `/temper:temper enforcement off`, then try a write in Plan. Expect the write to go through
  and a toast `Temper enforcement: off`. Run `/temper:temper enforcement on` to restore it.
- [ ] If you can, set `pluginConfigs` for Temper in a managed settings file so that
  `uiMode` is locked, then run `/temper:temper mode full`. Expect
  `Your organization set Temper's mode to ...; ask your admin to change it.`
  If you cannot set managed settings, mark this step as skipped.

## 6. Compaction and layouts

- [ ] **`/compact` keeps the marker.** Type `/compact`. After it finishes, ask
  `Does your system prompt contain a Temper enforcement line?` Expect `Temper enforcement: active`
  and the same phase.
- [ ] **`/clear` rebuilds the state.** Type `/clear`, then `/temper:temper status`. Expect the same
  phase as before, rebuilt from the files in `.temper/specs/<name>/events/`.
- [ ] **A narrow terminal.** Resize to 80 columns. Expect the bar to wrap or truncate
  without breaking the prompt, and the pane to wait instead of squeezing in.
- [ ] **A wide terminal.** Resize to 160 columns in fullscreen. Expect the pane to dock beside
  the transcript.
- [ ] **Light and dark themes.** Switch the terminal theme and expect the bar to stay readable.

## 7. Old versions and other surfaces

The plugin must still load on old Claude Code versions and fall back to the prompt based
phases. Run each of these from `<clone>`, which does not touch your installed Claude Code.

| Version | Command | Expect |
|---|---|---|
| 2.1.259 | `npx @anthropic-ai/claude-code@2.1.259 -p --plugin-dir . "/temper:status"` | No load error. The answer comes through the prompt based path. |
| 2.1.200 | `npx @anthropic-ai/claude-code@2.1.200 -p --plugin-dir . "/temper:status"` | The same. |
| 2.1.286 | `npx @anthropic-ai/claude-code@2.1.286 -p --plugin-dir . "/temper:status"` | The same, or the mod stays inert. |

- [ ] The three rows above behave as described. On each, the answer must not mention a
  plugin load error. The message `Temper enforcement is off here (no mods support)` is
  correct and expected when a skill runs.
- [ ] **`claude -p` on your version.** Run `claude -p --plugin-dir . "/temper:status"`.
  Expect an answer and no question asked of you.

## 8. The desktop app

This part was not verified by the author. How to load a local plugin folder into the
desktop app depends on your installation, so treat the first step as an experiment.

- [ ] Open the Code tab of the desktop app on the demo project. Load the clone as a plugin
  (for example by adding `<clone>` as a local marketplace through the plugin settings, with
  the installed Temper disabled as in step 1). If your build has no way to do this, mark
  the step skipped and note it.
- [ ] Start a run and expect the same phase bar and the same Plan denial as in the terminal.
  Open the pane and expect it to draw. Elements that only the terminal has are not used by
  the mod, so nothing should be missing.
- [ ] Switch to a WSL session if you use one. Plugins are unavailable there, so expect no
  Temper at all, and expect prompt based phases when you load the plugin in another way.

## 9. Clean up

- [ ] Enable the installed Temper again with `claude plugin enable <that id>`.
- [ ] **Clear the saved mode.** `/temper:temper mode` stores your choice as a `pluginConfigs`
  entry in your user settings. Make a backup, then remove the entry:

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq 'del(.pluginConfigs["temper@inline"], .pluginConfigs.temper)' ~/.claude/settings.json.bak > ~/.claude/settings.json
```

  Expect `jq '.pluginConfigs' ~/.claude/settings.json` to show no Temper entry. If your
  settings file already had a `pluginConfigs` entry for a Temper you installed, keep that
  one: only remove the entry that the test added.
- [ ] Delete the demo copy: `rm -rf /tmp/password-reset-demo`.

When every box is ticked (or marked skipped with a reason), the branch is ready to merge
and release with the existing release process.
