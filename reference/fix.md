---
description: "Root cause analysis + structured fix for a bug"
argument-hint: "<bug-description-or-JIRA-123>"
---

# Fix: Root Cause Analysis + Structured Fix

**Goal:** Investigate root cause, write a regression test that proves the bug, implement the minimal fix, review the fix, validate. Never guess — investigate first.

## Usage

```
/temper:fix "users get 500 error on checkout"
/temper:fix "JIRA-123"
/temper:fix "#456"
```

## Bug: $ARGUMENTS

## Execution

### Context Loading

This stage may run in two modes:
- **Standalone** (`/temper:fix`) — the command file (`commands/fix.md`) acts as the orchestrator, running this methodology across 4 Agent subprocess stages (RCA -> Fix -> Review -> Check)
- **Agent subprocess** (from `/temper`) — starts with CLEAN context, only loads what's listed below

**This reference file describes the methodology** for each stage. The **command file** handles the orchestrator routing, stage gates, and state management. When running as a subprocess, only the steps relevant to the current stage are executed.

**Subprocess mode override:** When running as an Agent subprocess, do NOT show AskUserQuestion gates or clear context. Return the summary to the orchestrator. The orchestrator handles all gate decisions and context transitions.

In both modes, the fix methodology is identical.

**Context loading strategy:** Apply the context-engineering skill for hierarchical loading (rules -> arch -> source -> errors, under 2K lines/task). The file list below specifies WHAT to load; the skill specifies HOW and WHEN.

### Step 1: Detect Input Type

Same as /temper:plan Phase 0 — detect Jira, GitHub, or direct description.

**Extract from ticket/description:**

- Symptom (error message, wrong behavior, crash)
- Trigger (which user action, endpoint, data)
- Reproducibility (always, intermittent, specific conditions)
- When it started (recent deploy, specific date, always existed)

### Step 1.5: Load Enabled Packs

Read `.claude/temper.config` to get the list of enabled packs. For each enabled pack, load `.claude/packs/{pack}/rules.md`.

If stack detected, also load `.claude/packs/stacks/{detected-stack}.md` for stack-specific patterns.

These rules are applied during:
- **RCA** — check if the bug violates any pack rules (e.g., security pack: was input validation skipped?)
- **Fix approach validation** — validate the proposed fix doesn't introduce new pack violations (Step 3.5)
- **Fix implementation** — ensure the fix doesn't introduce new pack violations
- **Validation** — `/temper:check` validates against all enabled pack rules

```
Loading enabled packs: quality, tdd, security, git
Loading stack-specific rules: {detected-stack}
  quality: {N} BLOCK, {N} WARN rules
  tdd: {N} BLOCK, {N} WARN rules
  security: {N} BLOCK, {N} WARN rules
  git: {N} WARN, {N} SUGGEST rules
  {stack}: {N} patterns to follow
```

### Step 2: Root Cause Analysis (via Explore subagent)

**Check depth budget from agents config:**
- If `depth_remaining > 1`: spawn Explore subagent
- If `depth_remaining <= 1`: run RCA inline (no subagent)

If spawning is allowed, launch an Explore subagent:

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

   MCP CALL CHAIN (during execution path tracing):
   If code-review-graph MCP server is available and tools.mode is not heuristic-only:
   1. Call query_graph_tool with the suspected function name:
      - Request both callers (who calls this function) and callees (what this function calls)
      - Returns full call chain: entry point → intermediates → failing function
   2. Call get_affected_flows_tool for user-facing flows through the suspected function:
      - Returns which API endpoints / user actions reach the failing code
      - Identifies blast radius in terms of user-facing behavior
   3. Evidence: [PROVEN] call chain (AST-level, mechanically verified)
   If MCP unavailable:
      Use grep-based call chain tracing → [HEURISTIC]

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

### Step 2.1: Mandatory Debugging Procedure

After identifying the root cause area, follow this structured debugging procedure. **No shortcuts** — each step must be completed before proceeding to the next.

**Procedure (in order):**

1. **REPRODUCE** — Create a minimal, reliable reproduction of the bug.
   - Isolate the trigger: specific input, state, timing, or condition
   - Write it as a test or script that demonstrates the failure
   - If you cannot reproduce: stop and gather more evidence (logs, traces, user steps)
   - Gate: "Without a repro, stop and gather more evidence"

2. **LOCALIZE** — Narrow down to the specific component, function, or line.
   - Binary search through the execution path
   - Add strategic logging/assertions to isolate the failing boundary
   - Confirm: "The bug manifests between point A and point B"

3. **REDUCE** — Strip away everything unrelated to the failure.
   - Remove unrelated code paths, data, configuration
   - The reproduction should be the simplest possible case
   - If the reduced case no longer fails, you removed too much — add back carefully

4. **BISECT** — Use `git bisect` to find the commit that introduced the bug.
   - `git bisect start && git bisect bad HEAD && git bisect good {last-known-good}`
   - If bisect is impractical (long-running bug, complex setup): use `git log --oneline -20 -- {affected files}` to identify suspicious commits
   - `git show {hash}` to inspect each candidate

5. **ROOT CAUSE** — Identify the specific line, condition, and why it fails.
   - Not "the function has a bug" but "line 47 returns early when `items.length === 0` because the guard clause should check `items === null`"
   - Trace: what data/state triggers the failure? Why does it happen now?

6. **REGRESSION TEST** — Write a test that proves the bug exists and will catch it if it returns.
   - Test must fail before the fix and pass after
   - Test name should describe the bug: `shouldHandleEmptyItemListNotAsNull`
   - This test is written BEFORE the fix (see Step 3)

**Anti-rationalizations:**

| Rationalization | Response |
|-----------------|----------|
| "I can see the bug right there" | Then reproduction takes 30 seconds. Do it. Eyes lie, tests don't. |
| "The stack trace tells us everything" | Stack traces show WHERE, not WHY. Reproduce to confirm the why. |
| "Bisect will take too long" | Bisect is logarithmic. Even 1000 commits = 10 steps. Use `git bisect run` for automation. |
| "It's obvious — let me just fix it" | Obvious bugs get obvious wrong fixes. Reproduce first, then fix with confidence. |
| "The test would be trivial" | Trivial tests catch trivial regressions. Write it. |
| "This only happens in production" | Then you need production-like data/state. Create a staging reproduction with anonymized prod data. |

**Gate:** Without a reproduction, stop and gather more evidence. Do not proceed to Step 2.5.

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

### Step 3.5: Validate Fix Approach Against Pack Rules

Before implementing the fix, validate that the proposed approach doesn't violate pack rules:

```
1. SECURITY PACK: Check if the fix approach would:
   - Introduce SQL concatenation → must use parameterized queries
   - Expose secrets → must use environment variables
   - Log sensitive data → must redact or skip
   - Bypass authentication → must add auth checks

2. TDD PACK: Verify:
   - Regression test exists (Step 3) ✅
   - Test follows Given-When-Then structure
   - Test is independent (no shared state)

3. QUALITY PACK: Check if the fix will:
   - Exceed 30 lines → consider refactoring
   - Add nesting > 3 levels → use early return
   - Duplicate logic → extract shared function

4. STACK-SPECIFIC patterns:
   - Spring Boot: Optional<T>? Constructor injection? DTOs?
   - React: Hooks correctly? No direct DOM manipulation?
   - Node: Error handling patterns? Async/await usage?

5. Report:
   PACK RULE VALIDATION
   Security: ✅ No BLOCK rules violated
   TDD: ✅ Test follows RED-GREEN-REFACTOR
   Quality: ⚠️ Fix adds 2 nesting levels (currently 2 → will be 4)
     Suggestion: Extract helper function to reduce nesting
   Stack ({detected}): ✅ Follows patterns

6. On BLOCK violation:
   - Do NOT implement the fix as proposed
   - Reconsider approach to satisfy pack rules
   - If no alternative exists → ask user for guidance

7. On WARN violation:
   - Note in report
   - Implement fix (non-blocking)
   - Consider refactoring after fix passes
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
   Pack violations: {BLOCK}/{WARN}/{SUGGEST} across affected files
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

### Step 4.8: Simplify (if code-simplifier agent is available)

After implementing the fix, if the `code-simplifier:code-simplifier` agent is available:
- Run it on files you created or modified during this fix
- Focus on clarity, consistency, and maintainability
- Preserve all functionality — simplification must not change behavior
- If the agent is not available in this installation: skip this step

### Step 5: Validate (via /temper:check)

```
1. Run /temper:check (compile → test → lint → coverage)
2. If failure related to your fix → fix it
3. If pre-existing failure → note in report (verify with git stash → test → git stash pop)
4. After check passes, run semantic test validation:
   - READ the regression test body (not just the name)
   - Verify assertions match expected behavior
   - Classify: STRONG (proves fix) / WEAK (incomplete) / TRIVIAL (always passes)

REGRESSION TEST VERIFICATION:
  Run the specific regression test individually (not as part of the full suite):
  - Jest/Vitest: npx jest --testPathPattern="{test}" --testNamePattern="{test_method}" --no-coverage
  - pytest: pytest {test}::test_{method} -v
  - Maven: ./mvnw test -Dtest="{TestClass#testMethod}"
  - Gradle: ./gradlew test --tests "{TestClass.testMethod}"
  - Go: go test -run Test{Method} -v
  - Rust: cargo test test_{method} -- --nocapture
  Show: test name, PASS/FAIL, assertion output, execution time
  Label: [PROVEN] — actual test runner output

5. Report:
   VALIDATION RESULTS
   Check: ✅ All levels passed
   Test quality: ✅ Semantic validation passed (STRONG)
   Regression test: ✅ {test_name} PASS ({time}s) [PROVEN]
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
│ 📋 PACK VALIDATION                                          │
│    Rules checked: {N} (security, tdd, quality, {stack})    │
│    Violations: {none / listed}                              │
│                                                             │
│ What next?                                                  │
│   ▸ Commit (Recommended)                                   │
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

**On Change (via "Other" free-text input):**
1. User types their change request in the "Other" field
2. Make the change
3. ⚠️ MANDATORY: Re-show AskUserQuestion with same options

GATE ENFORCEMENT: The user's change input is NOT approval to commit.
Do NOT commit after making changes. The user MUST explicitly select
"Commit" from the gate to proceed.

**On Save for later (second option):**
1. Save state to .temper/build-state.json:
   ```json
   {
     "stage": "fix_complete",
     "spec": "{bug-slug}",
     "spec_path": ".temper/specs/{bug-slug}",
     "original_args": "{from prior state}",
     "next_stage": "review",
     "artifacts": ["rca.md"],
     "updated": "{ISO timestamp}"
   }
   ```
2. Report: "✅ Saved. Run /temper:fix when ready to continue."

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
