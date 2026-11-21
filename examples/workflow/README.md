# Example Workflows

This directory contains example workflows showing how to use Temper.

## Running temper from any automation (host-agnostic)

Temper ships **no CI-platform integration on purpose** — it works the same under
GitHub Actions, GitLab CI, Jenkins, plain cron, or any scheduler you already run,
because the integration surface is just commands and exit codes:

| What you wire | The command | Exit contract |
|---|---|---|
| Review as a merge/pipeline check | In a throwaway checkout: `scripts/temper state init <slug>`, then the Review brief headless (`claude -p "Follow <temper>/agents/review.md exactly. Spec path: ..."`), then `scripts/temper gate review` | gate exits 0 = no open findings at a severity **listed in** `review.block-on` (set membership, default `[critical]`: list every severity you want blocking); nonzero fails the check. The verdict is computed from the evidence ledger, never model narration. |

Two cautions that apply on every platform: run headless steps in a sandboxed runner
(a throwaway checkout, with `--dangerously-skip-permissions` only inside it), and guard
the review check against a *vacuous* pass: `temper gate review` fails when the ledger has no
`review completed` row (an empty findings ledger is not a review), so a review that never ran
cannot pass. A `/temper:temper` run is for an interactive session: headless, it stops at the
first gate question.

## Sprint Workflow Example

### Monday: Bug Fix

```
/temper:fix "BKNG-4530"
→ Fetches Jira → RCA → the RCA question: Proceed to Fix
→ Fix: regression test (RED), then the fix (GREEN)
→ Review → Check → all pass → Commit (with an entry in .temper/lessons.md)
```

### Tuesday-Wednesday: Feature

```
/temper:temper "BKNG-4521"
→ Intent: the problem and the criteria → the Intent question: Continue to Plan
→ Plan: blast radius, scenarios, tasks.md in groups → the Plan question: Continue to Build
→ Build: each ready task as a task agent (Sonnet by default) in its own worktree, RED then GREEN;
  one question per group
→ Review (confidence-scored findings) → the Review question
→ Check (all green, coverage 91%) → the Check question: Commit
```

### Thursday: Tech Debt Refactor

```
/temper:temper "BKNG-4535 refactor notification service"
→ Plan: 14 callers in the blast radius → 3 groups, 12 tasks
→ Build, Review, Check as above; the existing tests still pass
```

### Friday: Sprint Review

```
/temper:temper status
→ 3 tickets done, coverage 87%→91%, 4 issues caught, debt ratio improving
```

## Pack Management Workflow

```
/temper:temper pack
→ Shows all packs with enabled/disabled status
→ Toggle packs on/off, or quick-create a pack for a target
→ "Other", then "add new pack": the full builder scans the codebase, interviews you,
  writes .claude/packs/{name}/rules.md and adds it to the config
```
