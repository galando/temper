---
description: "Root cause analysis + structured fix"
argument-hint: "<bug-description-or-JIRA-123>"
---

# Fix: RCA → Fix → Review → Check

**Goal:** Investigate root cause, implement minimal fix, then **review** and **check** —
the same full pipeline as `/temper`, with RCA replacing Plan and Fix replacing Build.

**Enforcement marker.** Look at your system prompt for a line that starts with
`Temper enforcement:`. With no such line, make the first sentence of your first reply in
this conversation exactly "Temper enforcement is off here (no mods support); continuing
with prompt based phases." With the line `Temper enforcement: off (UI only)`, the Temper
mod is loaded and the user turned enforcement off: make that first sentence exactly
"Temper enforcement is off (turned off by the user); continuing with prompt based
phases." instead. Then carry on as written below. Never treat either case as an error
and do not mention it again. With `Temper enforcement: active`, say nothing about it.
You state this once, in this conversation: a stage subprocess never has that line in
its system prompt, so its brief says nothing about enforcement.

## Usage

```
/temper:fix "users get 500 error on checkout"    # Start new fix
/temper:fix "JIRA-123"                            # Fix from Jira ticket
/temper:fix "#456"                                # Fix from GitHub issue
/temper:fix                                       # Resume saved fix
```

---

## Architecture

Each stage runs in an **isolated Agent subprocess** — genuine context clearing, not
theater. What each stage must do lives in exactly one place, its stage brief:

- RCA: `${CLAUDE_PLUGIN_ROOT}/agents/rca.md`
- Fix: `${CLAUDE_PLUGIN_ROOT}/agents/fix.md`
- Review: `${CLAUDE_PLUGIN_ROOT}/agents/review.md`
- Check: `${CLAUDE_PLUGIN_ROOT}/agents/check.md`

A brief's frontmatter declares its default model; its body carries methodology
pointers, the `temper` commands to run, and the summary box it returns. This file does
not repeat that contract per stage — read the brief once when you launch it, and print
the box the agent returns verbatim.

```
ORCHESTRATOR (this file)
  |
  +-- Agent(rca brief)    -> RCA gate    (human judgment — no CLI gate)
  +-- Agent(fix brief)    -> fix gate    -> CLI gate build
  +-- Agent(review brief) -> review gate -> CLI gate review
  +-- Agent(check brief)  -> check gate  -> CLI gate check
  |
  +-- CLI gate commit -> commit
```

Shared patterns: read `${CLAUDE_PLUGIN_ROOT}/reference/orchestrator-patterns.md` once,
now. Every `→ pattern` reference below points into it. Its section "The plugin folder"
says how plugin paths work: Claude Code wrote the plugin's absolute folder in place of
the CLAUDE_PLUGIN_ROOT variable when it loaded this file, and the Bash tool does not set
that variable, so run each command with the path exactly as this file shows it. The
temper CLI is `${CLAUDE_PLUGIN_ROOT}/scripts/temper`. Every other path below
(`.temper/`, the spec files, the files being fixed) is in the user's project, the
current directory. Nothing in a run writes into the plugin folder, unless the project is
the plugin folder itself (developing Temper on its own repository: a git checkout whose
top folder is the plugin folder; an installed copy is never a project, and the CLI
refuses it).

**Plugin folder line.** Every stage launch prompt below carries this line, word for word,
so the stage knows the folder that its brief and the reference pages mean:
`Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with /scripts/temper taken off); wherever the brief or a reference page writes the CLAUDE_PLUGIN_ROOT variable, use this folder.`

**Why this command gates at all:** the commit hook (installed by `/temper:init`) runs
`${CLAUDE_PLUGIN_ROOT}/scripts/temper gate commit` on **every** `git commit` in a project with a `.temper` folder,
regardless of which command produced it.
Fix maps onto the `build` gate (a regression test is exactly a RED-then-GREEN pair);
Review and Check are the literal same stages as `/temper`, sharing the review and check
briefs. Skipping evidence here would leave every `/temper:fix` commit wrongly blocked
(missing evidence fails closed, by design).

## Models

Run `${CLAUDE_PLUGIN_ROOT}/scripts/temper model --all` **once**, at the same time as the first state call, and keep
its output for the run. The stage launches below say `model: {rca}`, `{fix}`, `{review}`,
`{check}` — substitute that stage's value from this output verbatim.

## State

`${CLAUDE_PLUGIN_ROOT}/scripts/temper state` owns `.temper/build-state.json` — never hand-write it. For
`/temper:fix`: stages `rca_complete | fix_complete | review_complete | check_complete`,
branch `fix/{slug}`, artifact `rca.md`. Resolve `spec_path` from
`${CLAUDE_PLUGIN_ROOT}/scripts/temper state get spec_path` before launching any post-RCA agent. Batch consecutive
state/evidence calls (never `gate`) into a single Bash call.

## Gates

Same shape as `/temper`: print the agent's returned box verbatim, run the stage's
`${CLAUDE_PLUGIN_ROOT}/scripts/temper gate`, then `AskUserQuestion` — Continue (Recommended) / "Save for later" /
built-in "Other" free-text. A change typed via "Other" is never approval: make the
edit, re-show the same gate (→ "Gate Options + Enforcement"). An agent returning a
failure/blocker → "Agent Failure Handling". On Save → the Save/Continue rule under
"Build State Schema".

---

## Stage 1: RCA

```
Use the Agent tool, model: {rca}, prompt:
"Follow ${CLAUDE_PLUGIN_ROOT}/agents/rca.md exactly. Bug: $ARGUMENTS.
Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with /scripts/temper taken off); wherever the brief or a reference page writes the CLAUDE_PLUGIN_ROOT variable, use this folder."
```

Gate (human judgment; the CLI has no RCA gate): show the RCA box, then
"Proceed to Fix (Recommended)" / "Save for later" / Other (a change request, e.g.
"investigate the auth module instead" — re-launch the RCA agent with that direction,
re-show this gate).

**On Continue:**
1. Save the agent's returned findings to the project's `.temper/specs/{bug-slug}/rca.md`
   (create the directory if needed). The bug slug, which step 2 passes to `state init`,
   is letters (either case), digits, '.', '_' or '-', starts with a letter or digit,
   and has no '..' or '/' (the CLI refuses anything else). A ticket key prefix keeps its
   case as typed (`{KEY}-{slug}`, for example `JIRA-123-checkout-500`).
2. `${CLAUDE_PLUGIN_ROOT}/scripts/temper state init {bug-slug} --command fix` (first time only — also sets branch
   `fix/{bug-slug}`), else `${CLAUDE_PLUGIN_ROOT}/scripts/temper state advance rca_complete fix`.
3. If the git pack is enabled and `git branch --show-current` is main/master:
   `git checkout -b fix/{bug-slug}`.
4. Launch Stage 2.

---

## Stage 2: Fix

```
Use the Agent tool, model: {fix}, prompt:
"Follow ${CLAUDE_PLUGIN_ROOT}/agents/fix.md exactly. Spec: {spec_path from state}.
Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with /scripts/temper taken off); wherever the brief or a reference page writes the CLAUDE_PLUGIN_ROOT variable, use this folder."
```

Gate: `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate build` (RED-then-GREEN regression-test evidence; the "no unchecked
tasks" requirement is skipped automatically — fixes have no `tasks.md`). On PASS:
"Continue to Review (Recommended)". On FAIL: fix and re-run, or "Override and continue"
(`${CLAUDE_PLUGIN_ROOT}/scripts/temper override build --reason "..."`).

**On Continue:** `${CLAUDE_PLUGIN_ROOT}/scripts/temper state advance fix_complete review`, launch Stage 3.

---

## Stage 3: Review

```
Use the Agent tool, model: {review}, prompt:
"Follow ${CLAUDE_PLUGIN_ROOT}/agents/review.md exactly. Spec: {spec_path from state}.
Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with /scripts/temper taken off); wherever the brief or a reference page writes the CLAUDE_PLUGIN_ROOT variable, use this folder.
Fix mode: there is no intent.md — read {spec_path}/rca.md instead, and verify the fix
addresses its root cause, the regression test proves the fix (not a trivial assert),
and no same-pattern occurrence it flagged is left unfixed."
```

Gate: `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate review` (zero open findings at or above `review.block-on`; a
finding marked with `${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence resolve` no longer counts). On FAIL:
"Fix all & continue to Check (Recommended)" — apply fixes for ALL open findings
directly (no subprocess), re-run the regression test, then mark each fixed finding
`${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence resolve --stage review --id {n} --fixed-by "{commit or note}"`
(ids from `${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence list --stage review`) and re-run the gate. The row stays in
the ledger as the record of what was found; only the gate stops counting it. Still
FAIL after that pass → **loop back** per → "Feedback Loops": `${CLAUDE_PLUGIN_ROOT}/scripts/temper state loop
review fix --reason "{why}"` (this clears the build, review and check evidence for a
fix run), re-launch the Fix agent with the re-entry line, re-run Review, re-gate. Only
a spent loop budget (`BLOCKED`) falls through to "Override and continue" / "Save for
later". After an "Other" change, re-launch the review agent for an updated summary
before re-showing the gate.

**On Continue:** `${CLAUDE_PLUGIN_ROOT}/scripts/temper state advance review_complete check`, launch Stage 4.

---

## Stage 4: Check

```
Use the Agent tool, model: {check}, prompt:
"Follow ${CLAUDE_PLUGIN_ROOT}/agents/check.md exactly. Spec: {spec_path from state}.
Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with /scripts/temper taken off); wherever the brief or a reference page writes the CLAUDE_PLUGIN_ROOT variable, use this folder.
Fix mode: there is no intent.md, so scenario tracing doesn't apply — {spec_path}/rca.md
names the regression test that must be in the passing run."
```

Gate: run `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate check`, then `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate commit` (aggregates build/review/
check — a fix run has no plan gate, and `gate commit` only requires the gates the run
actually produced). After an "Other" change, re-launch the check agent to re-validate —
never commit directly.

- **On PASS:** "Commit (Recommended)". Commit in two separate Bash calls, staging first,
  so the in-agent commit-gate hook sees the staged set. First stage the named paths
  only: every file the fix changed (the Fix panel's CHANGED section, plus any file a
  Review fix touched), the regression test, and the spec folder
  `.temper/specs/{bug-slug}/`. Never `git add -A` or `git add .`, which would also
  stage unrelated files such as a personal `.claude/settings.local.json`, and never
  `git add -f` over a gitignored spec folder. Then, in the next call:
  ```
  git commit -m "fix({scope}): {description}

  Root cause: {explanation}
  Regression test: {test name}
  {Closes JIRA-123 / Fixes #456}"
  ```
  then `${CLAUDE_PLUGIN_ROOT}/scripts/temper state clear`, then report "Committed: {hash} / Branch: {branch} /
  Ready to push?".
- **On FAIL:** show `${CLAUDE_PLUGIN_ROOT}/scripts/temper report`; "Override and commit" (`${CLAUDE_PLUGIN_ROOT}/scripts/temper override {stage}
  --reason "..."`, re-run `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate commit`) or "Save for later".

---

## Resume

`/temper:fix` (no arguments) with saved state → validate per → "Resume Validation"
(valid stages: `rca_complete | fix_complete | review_complete | check_complete`), then
"Continue from {next_stage} (Recommended)" / "Start over (re-investigate)". Resuming at
`rca_complete`: re-display the RCA box (read `{spec_path}/rca.md`) before launching the
Fix agent, so the user can re-evaluate the root cause. `/temper:fix "new bug"` while
state exists for a **different** bug → "Nested Invocation Protection" (say "bug", not
"feature").
