---
description: "Root cause analysis + structured fix"
argument-hint: "<bug-description-or-JIRA-123>"
---

# Fix: RCA → Fix → Review → Check

**Goal:** Investigate root cause, implement minimal fix, then **review** and **check** —
the same full pipeline as `/temper`, with RCA replacing Plan and Fix replacing Build.

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
  +-- Agent(fix brief)    -> fix gate    -> temper gate build
  +-- Agent(review brief) -> review gate -> temper gate review
  +-- Agent(check brief)  -> check gate  -> temper gate check
  |
  +-- temper gate commit -> commit
```

Shared patterns: read `${CLAUDE_PLUGIN_ROOT}/reference/orchestrator-patterns.md` once,
now — every `→ pattern` reference below points into it. `$CLAUDE_PLUGIN_ROOT`
resolution is defined there. The temper CLI is `${CLAUDE_PLUGIN_ROOT}/scripts/temper`.
Every other path below (`.temper/`, the spec files, the files being fixed) is in the
user's project, the current directory; nothing in a run writes under
`$CLAUDE_PLUGIN_ROOT`.

**Why this command gates at all:** the commit hook (installed by `/temper:init`) runs
`temper gate commit` on **every** `git commit` in a project with a `.temper` folder,
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
"Follow ${CLAUDE_PLUGIN_ROOT}/agents/rca.md exactly. Bug: $ARGUMENTS."
```

Gate (human judgment — there is no `temper gate rca`): show the RCA box, then
"Proceed to Fix (Recommended)" / "Save for later" / Other (a change request, e.g.
"investigate the auth module instead" — re-launch the RCA agent with that direction,
re-show this gate).

**On Continue:**
1. Save the agent's returned findings to the project's `.temper/specs/{bug-slug}/rca.md`
   (create the directory if needed). The bug slug, which step 2 passes to `state init`,
   is lowercase letters, digits, '.', '_' or '-', starts with a letter or digit, and
   has no '..' (the CLI refuses anything else).
2. `${CLAUDE_PLUGIN_ROOT}/scripts/temper state init {bug-slug} --command fix` (first time only — also sets branch
   `fix/{bug-slug}`), else `${CLAUDE_PLUGIN_ROOT}/scripts/temper state advance rca_complete fix`.
3. If the git pack is enabled and `git branch --show-current` is main/master:
   `git checkout -b fix/{bug-slug}`.
4. Launch Stage 2.

---

## Stage 2: Fix

```
Use the Agent tool, model: {fix}, prompt:
"Follow ${CLAUDE_PLUGIN_ROOT}/agents/fix.md exactly. Spec: {spec_path from state}."
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
Fix mode: there is no intent.md, so scenario tracing doesn't apply — {spec_path}/rca.md
names the regression test that must be in the passing run."
```

Gate: run `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate check`, then `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate commit` (aggregates build/review/
check — a fix run has no plan gate, and `gate commit` only requires the gates the run
actually produced). After an "Other" change, re-launch the check agent to re-validate —
never commit directly.

- **On PASS:** "Commit (Recommended)" —
  ```
  git add -A && git commit -m "fix({scope}): {description}

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
