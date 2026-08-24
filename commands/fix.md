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
theater. What each stage must do lives in exactly one place: `agents/{stage}.md`
(frontmatter declares its default model; the body carries methodology pointers, the
`temper` commands to run, and the summary box it returns). This file does not repeat
that contract per stage — read the agent file once when you launch it, and print the
box the agent returns verbatim.

```
ORCHESTRATOR (this file)
  |
  +-- Agent(agents/rca.md)    -> RCA gate   (human judgment — no CLI gate)
  +-- Agent(agents/fix.md)    -> fix gate   -> temper gate build
  +-- Agent(agents/review.md) -> review gate -> temper gate review
  +-- Agent(agents/check.md)  -> check gate  -> temper gate check
  |
  +-- temper gate commit -> commit
```

Shared patterns: read `$CLAUDE_PLUGIN_ROOT/reference/orchestrator-patterns.md` once,
now — every `→ pattern` reference below points into it. `$CLAUDE_PLUGIN_ROOT`
resolution is defined there; `$TEMPER` below means `$CLAUDE_PLUGIN_ROOT/scripts/temper`.

**Why this command gates at all:** the commit hook (`scripts/hooks/install.sh`) runs
`temper gate commit` on **every** `git commit`, regardless of which command produced it.
Fix maps onto the `build` gate (a regression test is exactly a RED-then-GREEN pair);
Review and Check are the literal same stages as `/temper`, sharing `agents/review.md` /
`agents/check.md`. Skipping evidence here would leave every `/temper:fix` commit
wrongly blocked (missing evidence fails closed, by design).

## Models

Run `$TEMPER model --all` **once**, at the same time as the first state call, and keep
its output for the run. The stage launches below say `model: {rca}`, `{fix}`, `{review}`,
`{check}` — substitute that stage's value from this output verbatim.

## State

`$TEMPER state` owns `.temper/build-state.json` — never hand-write it. For
`/temper:fix`: stages `rca_complete | fix_complete | review_complete | check_complete`,
branch `fix/{slug}`, artifact `rca.md`. Resolve `spec_path` from
`$TEMPER state get spec_path` before launching any post-RCA agent. Batch consecutive
state/evidence calls (never `gate`) into a single Bash call.

## Gates

Same shape as `/temper`: print the agent's returned box verbatim, run the stage's
`$TEMPER gate`, then `AskUserQuestion` — Continue (Recommended) / "Save for later" /
built-in "Other" free-text. A change typed via "Other" is never approval: make the
edit, re-show the same gate (→ "Gate Options + Enforcement"). An agent returning a
failure/blocker → "Agent Failure Handling". On Save → "Save/Continue".

---

## Stage 1: RCA

```
Use the Agent tool, model: {rca}, prompt:
"Follow $CLAUDE_PLUGIN_ROOT/agents/rca.md exactly. Bug: $ARGUMENTS."
```

Gate (human judgment — there is no `temper gate rca`): show the RCA box, then
"Proceed to Fix (Recommended)" / "Save for later" / Other (a change request, e.g.
"investigate the auth module instead" — re-launch the RCA agent with that direction,
re-show this gate).

**On Continue:**
1. Save the agent's returned findings to `.temper/specs/{bug-slug}/rca.md` (create the
   directory if needed).
2. `$TEMPER state init {bug-slug} --command fix` (first time only — also sets branch
   `fix/{bug-slug}`), else `$TEMPER state advance rca_complete fix`.
3. If the git pack is enabled and `git branch --show-current` is main/master:
   `git checkout -b fix/{bug-slug}`.
4. Launch Stage 2.

---

## Stage 2: Fix

```
Use the Agent tool, model: {fix}, prompt:
"Follow $CLAUDE_PLUGIN_ROOT/agents/fix.md exactly. Spec: {spec_path from state}."
```

Gate: `$TEMPER gate build` (RED-then-GREEN regression-test evidence; the "no unchecked
tasks" requirement is skipped automatically — fixes have no `tasks.md`). On PASS:
"Continue to Review (Recommended)". On FAIL: fix and re-run, or "Override and continue"
(`$TEMPER override build --reason "..."`).

**On Continue:** `$TEMPER state advance fix_complete review`, launch Stage 3.

---

## Stage 3: Review

```
Use the Agent tool, model: {review}, prompt:
"Follow $CLAUDE_PLUGIN_ROOT/agents/review.md exactly. Spec: {spec_path from state}.
Fix mode: there is no intent.md — read {spec_path}/rca.md instead, and verify the fix
addresses its root cause, the regression test proves the fix (not a trivial assert),
and no same-pattern occurrence it flagged is left unfixed."
```

Gate: `$TEMPER gate review` (zero open findings at or above `review.block-on`). On
FAIL: "Fix all & continue to Check (Recommended)" — apply fixes for ALL open findings
directly (no subprocess), re-run the gate; still FAIL after one pass → offer "Override
and continue" instead of looping. After an "Other" change, re-launch the review agent
for an updated summary before re-showing the gate.

**On Continue:** `$TEMPER state advance review_complete check`, launch Stage 4.

---

## Stage 4: Check

```
Use the Agent tool, model: {check}, prompt:
"Follow $CLAUDE_PLUGIN_ROOT/agents/check.md exactly. Spec: {spec_path from state}.
Fix mode: there is no intent.md, so scenario tracing doesn't apply — {spec_path}/rca.md
names the regression test that must be in the passing run."
```

Gate: run `$TEMPER gate check`, then `$TEMPER gate commit` (aggregates build/review/
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
  then `$TEMPER state clear`, then report "Committed: {hash} / Branch: {branch} /
  Ready to push?".
- **On FAIL:** show `$TEMPER report`; "Override and commit" (`$TEMPER override {stage}
  --reason "..."`, re-run `$TEMPER gate commit`) or "Save for later".

---

## Resume

`/temper:fix` (no arguments) with saved state → validate per → "Resume Validation"
(valid stages: `rca_complete | fix_complete | review_complete | check_complete`), then
"Continue from {next_stage} (Recommended)" / "Start over (re-investigate)". Resuming at
`rca_complete`: re-display the RCA box (read `{spec_path}/rca.md`) before launching the
Fix agent, so the user can re-evaluate the root cause. `/temper:fix "new bug"` while
state exists for a **different** bug → "Nested Invocation Protection" (say "bug", not
"feature").
