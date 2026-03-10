---
description: "Root cause analysis + structured bug fix"
argument-hint: "<bug-description-or-JIRA-123>"
---

# Fix: RCA + Regression Test + Fix

**Goal:** Find root cause, write regression test, implement minimal fix, validate.

## Bug: $INPUT

## Execution

> **Full methodology:** See temper_fix tool documentation

### Quick Reference
1. Detect input (Jira/GitHub/description)
2. RCA via exploration (search code, trace execution, check git history)
3. Write regression test → must FAIL (confirms bug)
4. Implement minimal fix → test must PASS
5. Run validation pipeline → all tests pass
6. Report + commit

### Root Cause Analysis Steps

1. **Search Code**: Find relevant keywords from bug description
2. **Trace Execution**: Follow the code path that causes the issue
3. **Check Git History**: `git log --oneline -20 -- <file>` for recent changes
4. **Identify Root Cause**: The actual bug, not just the symptom

### Document Findings

```
## RCA: {bug-title}

**Symptom**: What the user experiences
**Root Cause**: The actual bug in code
**Impact**: How many users/systems affected
**Location**: File:line
**Fix Strategy**: What needs to change
```

### Regression Test

1. Create test that reproduces the bug
2. Run test → must FAIL (confirms bug exists)
3. Test covers exact scenario

### Minimal Fix

- Write smallest change that fixes the bug
- Do NOT refactor or add features
- Run regression test → must PASS
- Run all related tests

### Commit Message

```
fix: {brief description}

Root cause: {explanation}
Fix: {what was changed}

Closes #{issue}
```
