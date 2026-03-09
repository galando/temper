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

## Standards Building Workflow

```
/temper:standards
→ Scans codebase (patterns, consistency, inconsistencies)
→ Interview: 5-10 questions about conventions
→ Generates: .claude/packs/{company}/rules.md
→ Generates: .claude/presets/{company}-{stack}.yaml
→ Validates against current codebase
→ Sets baseline for future tracking
```
