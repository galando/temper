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

MULTI-HYPOTHESIS INVESTIGATION:

1. LIST ALL PLAUSIBLE CAUSES (max 5):
   Based on symptom, generate hypotheses with confidence + evidence:

   | # | Hypothesis | Confidence | Evidence |
   |---|------------|------------|----------|
   | 1 | {cause}    | HIGH/MED/LOW | {why you think this} |
   | 2 | {cause}    | HIGH/MED/LOW | {why you think this} |
   ...

SKIP CONDITION: If only ONE plausible cause exists OR you have an exact stack trace pointing to a specific line, proceed directly to Step 2 investigation. Otherwise, continue with multi-hypothesis approach.

2. INVESTIGATE TOP HYPOTHESIS:
   - Start with highest confidence hypothesis
   - SEARCH for related code (error messages, stack traces, domain keywords)
   - TRACE the execution path (entry point → ... → failure point)
   - Write a quick regression test to CONFIRM/DENY the hypothesis

3. IF HYPOTHESIS DENIED:
   - Fall back to next highest confidence hypothesis
   - Repeat investigation
   - Max 3 hypothesis attempts before asking user for more context

4. CHECK common root causes:
   Off-by-one, null/undefined, wrong operator (= vs ==, && vs ||),
   race condition, type coercion, incorrect ordering, missing switch case,
   stale cache, config mismatch, dependency version conflict

5. CHECK git history:
   - git log --oneline -20 -- {affected files}
   - Look for recent refactors, dependency updates, merge conflicts
   - If suspicious commit: git show {hash}

6. CHECK for same vulnerability in related code (becomes blast radius)

7. IDENTIFY root cause: specific line, trigger data/state, when introduced

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
Hypotheses tested: {N}/{M} (only if multi-hypothesis used)

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

### Step 4.75: Intent Cross-Reference

```
If an active intent.md exists in .temper/specs/:
  1. Check if the bug relates to an existing scenario:
     - Grep scenario names for keywords from the bug description
     - If match found: note "Related to scenario: {name}" in report
  2. Check if the fix affects a success criterion with a Validate: type:
     - If fix touches code referenced by a `Validate: code` criterion → verify it still passes
     - If fix changes behavior covered by a `Validate: scenario` criterion → verify linked test still passes
  3. Check if the fix reveals a missing scenario:
     - The regression test covers a behavior not in any scenario
     - If so: suggest adding a scenario to intent.md
       "Bug fix reveals missing scenario. Consider adding:
        Scenario: {derived from regression test}
          Given {trigger condition}
          When {action}
          Then {expected behavior}"
  4. If no active intent.md: skip (most fixes are standalone)
```

### Step 5: Validate (via /temper:check)

```
1. Run /temper:check (compile → test → lint → coverage)
2. If failure related to your fix → fix it
3. If pre-existing failure → note in report (verify with git stash → test → git stash pop)
```

### Step 6: Report + Commit

Show a report and ask what to do next:

```
┌─────────────────────────────────────────────────────────────┐
│ 🔧 FIX — {Bug Title}                                        │
├─────────────────────────────────────────────────────────────┤
│ ✅ ROOT CAUSE                                                │
│    {1-line root cause}                                      │
│                                                             │
│ 🔨 FIX APPLIED                                              │
│    Fix:         {1-line description}                        │
│    Confidence:  {HIGH/MEDIUM}                               │
│    Test:        {test class}#{method}                       │
│    Files:       {list}                                      │
│                                                             │
│ What next?                                                  │
│   ▸ Commit (Recommended)                                   │
│     Change something first                                 │
│     Save for later                                         │
└─────────────────────────────────────────────────────────────┘
```

#### Stage Gate

Use AskUserQuestion with these options:

```
AskUserQuestion:
  question: "What next?"
  options:
    - label: "Commit (Recommended)"
      description: "Commit with conventional message, regression test included."
    - label: "Change something first"
      description: "Type what you want to change. Claude edits, then re-asks."
    - label: "Save for later"
      description: "Keep changes uncommitted, save state."
  multiSelect: false
```

**On Commit (first option):**

```
Commit: fix({scope}): {description}
  Root cause: {explanation}
  Regression test: {test name}
  {Closes JIRA-123 / Fixes #456}
  Co-Authored-By: Claude <noreply@anthropic.com>
```

**On Change something first (second option):**
1. Ask: "What would you like to change?"
2. User types their change request
3. Claude makes the change
4. Re-show AskUserQuestion with same options

**On Save for later (third option):**
1. Save state to .temper/build-state.json
2. Report: "✅ Saved. Run /temper when ready to continue."

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
