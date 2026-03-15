---
description: "Root cause analysis + structured bug fix"
argument-hint: "<bug-description-or-JIRA-123>"
---

# Fix: RCA + Regression Test + Fix

**Goal:** Find root cause, write regression test, implement minimal fix, validate.

## Bug: $ARGUMENTS

## Execution

> **Full methodology:** Read `$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/fix.md`

### Quick Reference

1. Detect input (Jira/GitHub/description)
2. RCA via Explore subagent (search code, trace execution, check git history)
3. Write regression test → must FAIL (confirms bug)
4. Implement minimal fix → test must PASS
5. Intent cross-reference: link fix to active scenario, suggest missing scenarios
6. Run /temper:check → all tests pass
7. Report + commit

**Multi-hypothesis RCA: investigates top causes ranked by confidence**
