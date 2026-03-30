# Example Workflows

This directory contains example workflows showing how to use Temper.

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
