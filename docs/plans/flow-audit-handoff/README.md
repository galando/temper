# Flow audit handoff (PR #97): no place where the person cannot go on by a click

Temporary working file for the session that verifies every Temper flow before PR #97 merges.
Delete this folder in the last commit before the merge.

## Goal

The person must never have to type a command to go on. Hold that across every point where a run waits for
them, in every setup:
- no Temper mod;
- the mod in uiMode full, minimal or off;
- enforcement on or off.

At every such point:
- They can continue, loop back, skip with a reason, save, start over or accept a finding with a click: a bar
  button, or an `AskUserQuestion` option.
- The mod's guard (`hooks/temper-mod/core/rules.ts`) accepts that choice, so the orchestrator's next CLI call is
  not refused.
- No text points at a button that does not exist in that mode.
- No text is jargon the person cannot act on.

## What the hands-on runs already found and fixed (do not redo)

| Problem | Fixed in |
|---|---|
| Blocking questions shown as text | `a157257` (Gates step 2 in `commands/temper.md`) |
| The bar folded an earlier run of the same feature name: "Record my choice" loop, refused `state set complexity` | `75884c3` |
| The label "Record my choice" | `75884c3` |
| No Loop back to Build at Review | `75884c3` |
| No usage in the bar's report | `75884c3` |
| Weak Haiku tests | `154de57` (`**Cases:**` per task, a pattern test in `task show`) |
| `mode off` and `mode minimal` had no click at a gate | `fc5d9da` (the `Temper gate` question, `core/gateanswer.ts`) |
| No Start over at all | `fc5d9da` (`Temper resume` question, More menu, `/temper:temper restart`) |
| The raw group report | `fc5d9da` |

Still open from the hands-on runs:
- **"None FAIL" in the group report.** Two task attempts were gated with no `--model` before their agent ran
  ("false failures from the cleanup"), and that cost each task one of its two Haiku attempts. The cause is not
  known. Find what in the orchestrator flow (`reference/build-groups.md`, `commands/temper.md`) can gate a
  task before its agent returns, and stop it.

## Audit findings at `fc5d9da` (read only, NOT yet verified by a second reader)

Verify each one before fixing it. Some may be wrong, and some may be older than this PR; record which.

**Blockers.** The person cannot go on without typing, or the guard refuses a move they chose.

1. **`/temper:fix` with the mod, enforcement on.** The guard has no `rca` or `fix` stages.
   - The cause: `cliPhase` maps rca and fix to the mod phase fix (`gates.ts:78,108`); `PHASE_INDEX` fix=5 is
     above review=4 (`rules.ts:362,476-477`); `nextStage()` has no rca or fix case (`rules.ts:273-290`).
   - `state advance fix_complete review` gets BACK_DENY.
   - `state advance rca_complete fix` gets ONLY_USER.
   - `temper override build` at the Fix gate gets ONLY_USER: the override is stored as stage check
     (`adapter.ts:232`, `cli.ts:66`).
   - `state loop review fix` gets STATE_RESTART.
   - Review "Fix all & continue to Check" edits code in Review and is refused (`rules.ts:196-202`).
   - Every source write of the Fix agent is refused as scope drift, since a fix run has no plan files.
   - The bar shows the Fix-after-Check buttons during RCA and Fix.
   - `commands/fix.md` never mentions the bar, the `Temper gate` header or the `Temper buttons: none` line.
2. **The loop budget is spent (`state loop` prints BLOCKED).**
   - The back event has already moved the mod's raw phase upstream (`machine.ts:140-147`). It stays a pending
     move (`adapter.ts:386-391`).
   - Key 1 re-runs the loop, which gets BLOCKED again and then STATE_RESTART.
   - A later Skip is dropped by reduce, because the raw phase is no longer the stage being skipped
     (`machine.ts:149-150`). The following `state advance` then gets ONLY_USER.
   - Minimal and off: `recordGateAnswer` returns early while a move is pending (`register.tsx:822`).
3. **A run saved with "Save for later", then resumed with `/temper`.**
   - A bare `/temper:temper` never records resume (`register.tsx:1155-1163`). `decide` then refuses every move
     with "The run is paused" (`machine.ts:274`).
   - Minimal and off: that error is dropped silently (`register.tsx:825-827`).
   - Full: Resume exists only in the More menu.
4. **Autonomy arming at the plan gate.**
   - "Stage by stage" and "Autonomous" are not recognized by `gateAnswer` (`gateanswer.ts:33,60-80`), so no
     approve is recorded.
   - Full mode: `state set run_mode autonomous` gets AUTONOMY_DENY until the person also presses key 1.
5. **An autonomous run that FAILs or parks.**
   - `autonomy.md:23-25` says "FAIL, loop automatically", but the guard refuses an unattended `state loop`.
   - Writing `.temper/autonomy-report.md` is refused in Build, Review and Check (`rules.ts:196-226`).
6. **The Design gate, every mod mode.**
   - The mod has no design verdict (`gates.ts:8`). Key 1 says "Continue to Build" even when the design check
     FAILed.
   - Loop back to Plan cannot be chosen: `backTo(plan, plan)` returns null, and `decide` refuses it.
   - An override is recorded for plan, not design. The advance then gets ONLY_USER.
   - The commit gate FAILs on design later.
7. **A parked group (agent commits), and a group gate FAIL.**
   - `reference/build-groups.md:46-49` gives the person no option to click. The CLI text tells them to type git
     and `temper group reopen` commands (`scripts/temper:2352-2356,3706`).
   - `group reopen --accept-foreign` is always ONLY_USER for the orchestrator (`bash.ts:1367-1372`,
     `rules.ts:503-511`).
8. **Review, the pane's per-finding Fix button.**
   - Writes are refused: `ctx.fixFiles` is never set (`register.tsx:830-832`).
   - The deny text names a "Fix all" button that does not exist (`rules.ts:201`).
9. **Standalone `/temper:build` with the mod.** `commands/build.md:32-34` runs `state init {slug}` with no
   `--command`, so the mod sits at Intent and refuses every Build write.

**Confusing.** Text the person cannot act on.

10. **Denies and the "Next:" line in minimal and off still say "press 1" or name typed commands.** The texts:
    - ONLY_USER (`machine.ts:55`), which is also used where "approve" is the wrong move;
    - `nextStep()` (`actions.ts:394-421`), and `section.ts` never passes `buttons` to it;
    - `COMMIT_NEXT` (`rules.ts:137-143`);
    - the phase write denies (`rules.ts:181,193,208`);
    - `AUTONOMY_DENY` (`rules.ts:254`);
    - `stateSetDeny` (`rules.ts:316`);
    - `OPAQUE_DENY` (`rules.ts:320`);
    - BACK_DENY names a "Go back" button that does not exist (`rules.ts:353`).
11. **A pending move in minimal and off.** The line "Press 1 to finish it" has no key 1 there.
    `commands/temper.md:239-240` promises the bar shows the problem, which it does not draw in those modes.
12. **Review FAIL in minimal and off.** There is no click to accept one finding: `gateanswer.ts` has no accept
    mapping, and the pane is full mode only.
13. **Full mode, the reason dialog of every button** (`register.tsx:436-442,685-687`). It always offers "I
    accept the risk" and "It is not a real issue", even for Loop back or Start over, and its question reads
    "What is the reason for start over?".
14. **The Build completion gate on FAIL.**
    - Its options rely on "Other". "Continue to Review" stays listed even on FAIL.
    - Full mode key 1 is "Loop back to Plan" (`actions.ts:113,146`).
    - An integrate FAIL has no options at all (`build-groups.md:58-59`).
15. **The group gate in full mode.**
    - `build-groups.md:51` says the bar has no group gate buttons, but it draws Continue, Change and Stop.
    - The bar's Stop records a pause, and then every move is refused (see 3).
    - The bar's Change says "this task", not "this group".
16. **Check PASS with `config-suggestions.json`.** "Review config suggestions" can never show, because the phase
    becomes Done at once (`adapter.ts:623-628`).
17. **The Plan gate when Design follows.** It says "Continue to Build" and "Build opens".
18. **Resuming a saved `/temper:fix` run.**
    - `fix.md:233` "Start over (re-investigate)" has no `Temper resume` header, so the answer is not recorded.
    - `orchestrator-patterns.md` hardcodes `--command temper`, which is wrong for a fix run.

**Minor.**

19. Check FAIL in full mode has no "Loop back to Build" in the Fix menu.
20. Check PASS in minimal and off asks two dialogs in a row: Continue to Commit, then Commit.
21. Texts still invite typing:
    - the full-mode wait line (`temper.md:265`);
    - the drift deny;
    - "Saved. Run {command} when ready";
    - the CLI's NEXT lines.
22. The Plan gate offers 7 options without a mod, but `AskUserQuestion` takes at most 4.
23. Intent FAIL in full mode: key 1 says "Start Intent" for an intent that already exists.
24. Toasts carry jargon or typed commands (`machine.ts:244-249,274,296`).
25. Standalone `/temper:plan` and `/temper:check` tell Claude to write `.temper/build-state.json` by hand,
    which the guard refuses (`reference/plan.md:354`, `check.md:188`).

**Unverified.**
- The Commit gate FAIL in full mode.
- Blocking questions with 4 choices plus "Carry forward" would exceed the 4 options a question can hold.

**Found fine (as traced).**
- Intent and Plan Continue in every mode.
- Design PASS Continue.
- Plan FAIL loop to Intent.
- Override at each phase.
- Review FAIL loop to Build.
- Accepting a finding through the pane.
- Check FAIL loop to Build in minimal and off.
- The Fix loop limit choices.
- Commit at Done.
- Resume Validation and nested Start over in `/temper`.
- Start over from the More menu.
- The Scope drift dialog.
- Blocking questions.
- Group gate Continue, Change and Stop through the dialog.
- The per-task checkpoint.
- `state set base_sha`.
- Enforcement off (only the text findings apply).
- No mod: plain dialogs (findings 7, 14, 21 and 22 still apply).

## Rules for the work

From `.claude/CLAUDE.md`:
- A gate-mechanics change is a `scripts/temper` edit plus a `test-temper.sh` case.
- Hooks fail open except their one detected-violation path.
- Per-stage logic lives in the stage's brief in `agents/`, never in `commands/temper.md` or `commands/fix.md`.

Every fix gets a test that fails on the old code. Run all of these after each batch:
- `bash scripts/selftest/test-temper.sh` (it must end `FAIL: 0`);
- `claude plugin test .`;
- `bash scripts/check-mod-calls.sh` and `bash scripts/check-original-options.sh`;
- `bash scripts/quality-check.sh`, `bash scripts/validate-docs.sh` and `bash scripts/validate-directory.sh`;
- `claude plugin validate --strict .`.

`tsc` runs only in CI. Push to both `ccr-897459d6-inv6ia` and `ccr-9154161b-pdiqc8` (the head of PR #97), never
with force. Then check the release checklist, `docs/mods-testing.md`, and extend it for every flow fixed.
