---
description: "Root cause analysis + structured fix for a bug"
argument-hint: "<bug-description-or-JIRA-123>"
---

# Fix: Root Cause Analysis + Structured Fix

**Goal:** Investigate root cause, write a regression test that proves the bug, implement the minimal fix, verify blast radius, validate. Never guess — investigate first.

## Usage

```
/temper:fix "users get 500 error on checkout"
/temper:fix "JIRA-123"
/temper:fix "#456"
```

## Bug: $ARGUMENTS

## Execution

### Step 1: Detect Input Type

Same as /temper:plan Phase 0 — detect Jira, GitHub, or direct description.

**Extract from ticket/description:**
- Symptom (error message, wrong behavior, crash)
- Trigger (which user action, endpoint, data)
- Reproducibility (always, intermittent, specific conditions)
- When it started (recent deploy, specific date, always existed)

### Step 2: Root Cause Analysis (via Explore subagent)

Launch an Explore subagent:

```
Investigate a bug and find the root cause. Understand WHY it happens, not just WHERE.

BUG DESCRIPTION:
{ticket content or user description}

INVESTIGATION STEPS:

1. SEARCH for related code:
   - Grep for error messages, status codes, exception types from the bug
   - Grep for endpoint paths/URLs in the failing flow
   - Grep for class/function names from stack traces
   - Grep for domain keywords from the bug description
   - Find the entry point (controller/route) for the affected flow

2. TRACE the execution path (most important step):
   - Start at the entry point, follow EVERY call in the chain
   - Read each file fully
   - At each step check: input validation, null handling, error handling,
     business logic correctness, type safety
   - Continue until you find where behavior diverges from expected

3. CHECK common root causes:
   Off-by-one, null/undefined, wrong operator (= vs ==, && vs ||),
   race condition, type coercion, incorrect ordering, missing switch case,
   stale cache, config mismatch, dependency version conflict

4. CHECK git history:
   - git log --oneline -20 -- {affected files}
   - Look for recent refactors, dependency updates, merge conflicts
   - If suspicious commit: git show {hash}

5. CHECK for same vulnerability in related code (becomes blast radius)

6. IDENTIFY root cause: specific line, trigger data/state, when introduced

RETURN FORMAT (max 30 lines):

ROOT CAUSE ANALYSIS

Bug:          {one-line description}
Symptom:      {what user/system experiences}
Root cause:   {specific: which line, which condition, why}
Location:     {file:line}
Call chain:   {entry → ... → failing function}
Introduced:   {commit hash + date, or "unknown"}
Trigger:      {specific data/state causing failure}
Impact:       {scope: all users / specific flow / edge case}
Blast radius: {other code with same vulnerability}
Confidence:   {HIGH / MEDIUM / LOW}

Suggested fix: {1-2 sentence minimal fix}
Fix location:  {file:line}
Test scenario: {scenario the regression test should exercise}
Related files: {files to read before fixing}
```

### Step 2.5: Multiple Root Causes

```
If 2+ possible causes:
- HIGH confidence → proceed with that one
- Multiple HIGH → fix the deepest cause (cascading: A→B→C, fix A)
- Ambiguous → present both to user, recommend highest confidence first
- NEVER fix multiple causes simultaneously (can't verify which worked)
```

### Step 3: Write Regression Test (RED)

```
1. Find test file (existing for affected code, or create following project conventions)
2. Write test reproducing the EXACT failing scenario:
   - Set up specific trigger data/state
   - Assert EXPECTED (correct) behavior, not current broken behavior
3. Name descriptively: "shouldHandleExpiredTokenGracefully" not "testBugFix"
4. Run → MUST FAIL (confirms bug). If passes: wrong path? wrong data? already fixed?
5. Must fail with assertion error related to the bug, not NPE or compilation error
```

### Step 4: Implement Fix (GREEN)

```
1. Read full file identified in RCA (not just the affected line)
2. Understand: what does the function do? what do callers expect?
3. Implement MINIMAL fix:
   - Fewest lines possible
   - Do NOT refactor surrounding code
   - Do NOT add features or improve unrelated error handling
   - Diff should be small and obviously correct
4. Verify fix handles:
   - The specific trigger data from the bug
   - Related edge cases (if off-by-one → check empty, one, many, max)
   - Non-buggy inputs (don't break the happy path)
5. Run regression test → MUST PASS (GREEN)
6. Run ALL existing tests → MUST STILL PASS
```

### Step 4.5: Blast Radius Check

```
1. Find all consumers of changed code:
   - Grep for imports of affected module
   - Grep for calls to changed function
   - Check .temper/index/ if exists

2. For each consumer verify:
   - Signature changed? → check all callers
   - Return type changed? → check downstream handlers
   - New required parameters? → update all callers
   - Error handling changed? → verify error handlers

3. Check for SAME bug in related code (from RCA blast radius):
   - Same fix applies? → fix and add test cases
   - Unclear? → flag to user: "Same pattern in {file:line}, may need fix"

4. Run consumer tests → ensure no breakage

5. Report:
   BLAST RADIUS CHECK — {bug-name}
   Fix location: {file:line}
   Consumers: {count} | Tests: {passed}/{total}
   Same-pattern: {count fixed}/{count found}
   ✅ No breaking changes / ⚠️ {count} consumers need updates
```

If breaking changes: ask user before proceeding, list all required changes.

### Step 5: Validate (via /temper:check)

```
1. Run /temper:check (compile → test → lint → coverage)
2. If failure related to your fix → fix it
3. If pre-existing failure → note in report (verify with git stash → test → git stash pop)
```

### Step 6: Report + Commit

```
"Bug fixed. Regression test added.
  Root cause:  {1-line}
  Fix:         {1-line}
  Confidence:  {HIGH/MEDIUM}
  Test:        {test class}#{method}
  Files:       {list}
  Branch:      fix/{ticket}-{slug}
  Ready to commit?"

Commit: fix({scope}): {description}
  Root cause: {explanation}
  Regression test: {test name}
  {Closes JIRA-123 / Fixes #456}
  Co-Authored-By: Claude <noreply@anthropic.com>
```

### Step 7: Rollback Protocol

```
Tests fail after fix:
  → git checkout -- {file} → re-run tests → re-investigate

Review finds issues:
  → Apply better approach → regression test must still pass

Multiple fix attempts fail (3+):
  → Preserve regression test (proves bug exists)
  → Show user RCA + what you tried → ask for context

Bug is actually a design flaw:
  → Tell user: "This needs /temper:plan for a redesign, not a patch"
  → Offer temporary workaround with TODO if possible
```

### Step 8: Update Metrics

```json
{
  "fixes": {
    "total": "+1",
    "rca_used": "+1",
    "rca_confidence": "{HIGH/MEDIUM/LOW}",
    "blast_radius_fixes": "+{count}",
    "regression_test_added": true
  }
}
```
