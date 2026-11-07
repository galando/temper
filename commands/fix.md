---
description: "Root cause analysis and a structured fix: RCA → Fix → Review → Check, each gate a question you answer"
argument-hint: "<bug-description-or-JIRA-123>"
---

# Fix: RCA → Fix → Review → Check

**Goal:** find the root cause, make the smallest fix with a regression test, then Review and
Check. It is the pipeline of `/temper`, with RCA in place of Intent and Plan, and Fix in place
of Build.

**First output, once per conversation:** the same line `/temper:temper` gives: "Temper Markdown
edition: Claude walks each gate's checklist and asks you; no program enforces the gates here.
The full edition on GitHub (galando/temper) adds the CLI that computes every verdict, the
commit hook and the mod."

**Plugin folder:** `${CLAUDE_PLUGIN_ROOT}`.

## Usage

```
/temper:fix "users get 500 error on checkout"    # start a fix
/temper:fix "JIRA-123"                            # a fix from a ticket
/temper:fix                                       # take up the saved fix
```

## The rules

Every rule of `/temper:temper` holds: the person decides every gate in a dialog; this
conversation writes no project source; never push, merge, `--no-verify` or `git add -A`.
The questions, typed text, reasons, the review and check gates, the loop budget and the commit
steps are those of `commands/temper.md` in the plugin folder: read its sections "Every
question", "The gates" (Review, Check, Commit) and "The report" now, and follow them.

## 1. Start

- With no arguments and a run whose `run.json` says `"command": "fix"`: go on at its stage.
- A `/temper` run that is active is not this command's: say so in one line and ask its "Start
  over" question as `/temper:temper` does.
- Otherwise pick the bug's slug (a ticket key keeps its case: `JIRA-123-checkout-500`), write
  `run.json` with `"command": "fix"` and `state.json` at stage `rca` with `base_sha`.

## 2. RCA

Launch the Agent tool with `subagent_type` `temper:temper-rca` (or the general purpose agent with
`Follow {plugin folder}/agents/rca.md exactly.`), `run_in_background: false`, and the prompt:

```
Bug: $ARGUMENTS
RCA file: .temper/specs/{slug}/rca.md
Plugin folder: {plugin folder}
```

Print its panel. Then ask header `Temper gate`, question "Root cause: {CAUSE} at {AT},
confidence {CONFIDENCE}{, not reproduced}. Proceed to Fix?", options "Proceed to Fix",
"Walk through the RCA", "Run RCA again", "Save for later". A direction typed here ("look at the
auth module instead") launches RCA again with `Person's note: {text}`. On "Proceed to Fix", when
the current branch is `main` or `master`, ask the Branch question of `/temper:temper` with the
branch `fix/{slug}`. Stage `fix`.

## 3. Fix

Launch `temper:temper-fix` with `Spec path:` and `Plugin folder:` lines. Record the regression
test's path from its panel in `state.json` as `regression_test`. Handle DRIFT as `/temper`'s
Build does. Confirm its checklist against `evidence.md` (a red row before a green row for the
regression test). Then ask header `Temper gate`, options when PASS: "Continue to Review",
"Walk through the change", "Run Fix again", "Save for later"; when FAIL: "Run Fix again",
"Override and continue" *(reason)*, "Walk through the change", "Save for later".

## 4. Review and Check

As in `/temper:temper`, with one difference: a loop back launches `temper:temper-fix` (not
Build) with `Feedback re-entry: review.md` or `check.md`, and is named "Loop back to Fix".

## 5. Commit

As `/temper:temper`'s commit steps, with this message: `fix({scope}): {description}`, then the
lines `Root cause: {explanation}` and `Regression test: {test name}`, and `Closes JIRA-123` or
`Fixes #456` when there is one. Stage only the fix's files, the regression test,
`.temper/lessons.md` and the spec folder. After the commit say "Committed: {hash} / Branch:
{branch}. Temper does not push."
