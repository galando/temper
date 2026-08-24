# Example Workflows

This directory contains example workflows showing how to use Temper.

## Running temper from any automation (host-agnostic)

Temper ships **no CI-platform integration on purpose** — it works the same under
GitHub Actions, GitLab CI, Jenkins, plain cron, or any scheduler you already run,
because the integration surface is just commands and exit codes:

| What you wire | The command | Exit contract |
|---|---|---|
| Review as a merge/pipeline check | `claude -p "/temper:review" --plugin-dir <temper checkout>` then `scripts/temper gate review` | gate exits 0 = no open findings at a severity **listed in** `review.block-on` (set membership, default `[critical]` — list every severity you want blocking); nonzero fails the check. The verdict is computed from the evidence ledger, never model narration. |
| Closing-the-loop monitoring | `scripts/temper bands` on a schedule (no tokens until a breach) | exit 1 = 2sigma+ breach → have your automation invoke `claude -p` to draft the breach as a Stage-1 `intent.md` (per `reference/status.md` Step 3.7) and route it into whatever review flow your host uses |
| Feeding external metrics | `scripts/temper metrics append <series> <value>` from any pipeline step | any appended series becomes band-able by name |

Two cautions that apply on every platform: run headless steps in a sandboxed runner
(the same way this repo's own eval harness does, `evals/run-fixture.sh`), and guard
the review check against a *vacuous* pass — `temper gate review` reads an empty
evidence ledger as "0 findings", so have the review record a completion marker
(`temper evidence add --stage review --claim "review completed"`) and fail the job if
it's absent.

## Sprint Workflow Example

### Monday: Bug Fix

```
/temper:fix "BKNG-4530"
→ Fetches Jira → RCA via Explore subagent → regression test (RED)
→ Fix (GREEN) → /temper:check → all pass → commit
Total: ~10 minutes
```

### Tuesday-Wednesday: Feature

```
/temper:plan "BKNG-4521"
→ Fetches Jira → Explore scans codebase → risk assessment (HIGH: payment code)
→ Blast radius: 4 controllers, 2 services → generates plan with rollback notes
→ Asks: "Single provider or multiple?" → generates 8 tasks

/temper:build
→ Task 1-8: RED → GREEN → REFACTOR per task
→ Auto-chain: /temper:review (parallel subagents, confidence-scored findings)
→ Auto-chain: /temper:check (all green, coverage 91%)
→ "Ready to commit?"
Total: ~1-2 hours
```

### Thursday: Tech Debt Refactor

```
/temper:plan "BKNG-4535 refactor notification service"
→ Blast radius: 14 callers → plan: extract interface, 3 implementations
→ /temper:build → 12 tasks, all existing tests still pass
→ /temper:check → all green
```

### Friday: Sprint Review

```
/temper:status
→ 3 tickets done, coverage 87%→91%, 4 issues caught, debt ratio improving
```

## Pack Management Workflow

```
/temper:pack
→ Shows all packs with enabled/disabled status
→ Toggle packs on/off, or select "Add new pack"
→ Add new pack: scans codebase, interview, generates .claude/packs/{name}/rules.md
→ Validates against current codebase
→ Sets baseline for future tracking
```
