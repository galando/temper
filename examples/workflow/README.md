# Example Workflows

This directory contains example workflows showing how to use Temper.

## CI Templates (copy into your project's `.github/workflows/`)

| Template | Loop it closes |
|---|---|
| [`temper-review.yml`](temper-review.yml) | AI in the PR review loop: headless `/temper:review` on every PR, merge check = `temper gate review` (deterministic verdict from the evidence ledger, never model narration). Humans still approve via branch protection. |
| [`temper-bands.yml`](temper-bands.yml) | Closing the loop: scheduled `temper bands` (pure arithmetic, no tokens) → on a 2sigma+ breach, Claude drafts the breach as a Stage-1 `intent.md` and opens a triage PR. The loop begins and ends with no one starting it — and lands in the review gate, never around it. |

Both templates pin a temper tag — review what you pin; the headless step runs with
`--dangerously-skip-permissions` inside the runner sandbox, same as this repo's own
eval harness (`evals/run-fixture.sh`).

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
