---
description: "Technical code review with confidence scoring, review memory, and intent validation"
---

# Review: Confidence-Scored Code Review

**Goal:** Review recent changes with high signal-to-noise ratio. Parallel subagent review, confidence scoring, review memory, and intent validation.

## Prerequisites

**DO NOT RUN if:**

- Code does not compile
- Tests are failing
- Build is broken

**RUN ONLY AFTER:**

- Build succeeds
- All tests pass
- Or: auto-chained from /temper:build (which already validated)

## Execution

### Context Loading

This stage may run in two modes:
- **Standalone** (`/temper:review`) — runs in current context, handles its own gate
- **Agent subprocess** (from `/temper`) — starts with CLEAN context, only loads what's listed below

**Subprocess mode override:** When running as an Agent subprocess, do NOT show AskUserQuestion gates or clear context. Return the review summary to the orchestrator. The orchestrator handles all gate decisions and context transitions.

In both modes, the review methodology is identical.

Files to load at start:
1. Run `git diff --name-only` to identify changed files
2. `$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/review.md` (this file)
3. `.temper/specs/{feature}/intent.md` (for intent validation, if exists)

### Step 1: Gather Context

```bash
# 1. Get changed files
git diff --name-only HEAD~1..HEAD  # if committed
git diff --name-only               # if uncommitted

# 2. Get diff statistics
git diff --stat HEAD

# 3. Read temper.config for review settings
# - block-on: which severities block
# - confidence-threshold: minimum confidence to show
# - auto-fix: whether to auto-fix

# 4. Read active pack rules
# - Load enabled packs from .claude/packs/
# - Load stack-specific rules from .claude/packs/stacks/{detected-stack}.md

# 5. Read review memory
# - Load .temper/review-memory.json if exists
# - Contains: dismissed patterns, accepted patterns, auto-rules

# 6. Find active intent.md
# - If chained from /temper:build: use the same spec (build context contains: spec name, feature path)
# - If single spec in .temper/specs/: use that intent.md
# - If multiple specs: check git branch name for match, or ask user which spec to review
# - If no specs: skip intent validation (existing behavior)
```

### Step 2: Launch Parallel Review Subagents

**If changed files span multiple domains (e.g., backend + frontend), launch parallel subagents.**

Each subagent receives:

```
Review the following files for issues. For each issue found, provide:
1. Severity: CRITICAL / HIGH / MEDIUM / LOW
2. Confidence: 0.0-1.0 (how certain you are this is a real issue)
3. Category: logic / security / performance / quality / standards / architecture / test-gap
4. Location: file:line
5. Description: what the issue is
6. Suggestion: how to fix it

Rules to enforce:
{content of active pack rules}

Stack-specific patterns:
{content of detected stack file}

Review these files:
{list of files in this subagent's domain}

For each file, read the ENTIRE file (not just the diff) to understand full context.

IMPORTANT:
- Only flag issues you are confident about (>0.5 confidence; Step 4 applies user-configured threshold, default 0.7)
- Do not flag style preferences unless they violate pack rules
- Do not flag patterns that are consistent with the rest of the codebase
- Focus on: logic errors, security, performance, missing tests, architectural drift

DIFF-AWARE REVIEW:
For each issue, classify as:
- REGRESSION: Code that was working before, now broken by these changes (highest priority)
- NEW ISSUE: Problem introduced by this change
- PRE-EXISTING: Issue existed before this change (lower priority, optional to fix)
Weight your focus: 80% on changed lines, 20% on context verification.

PERFORMANCE PATTERNS to check:
- N+1 queries: Loops making database/API calls
- Unbounded results: Queries without LIMIT, recursive calls without depth check
- Sync I/O in hot path: Blocking operations in request handlers, event loops
- Large objects in memory: Loading full datasets, unprocessed batch operations
- Missing pagination: Endpoints returning unbounded lists

AI-CODE DETECTION (apply to all files):
- Hallucinated APIs: verify function calls exist in dependencies
- Plausible but wrong: compare against project's existing usage of same library
- Over-engineering: abstractions used only once, premature generalization
- Copy-paste drift: similar blocks with subtle inconsistencies
- Missing integration: new code not wired into routing/DI/config
- Stale patterns: using deprecated APIs when project has migrated
- Incomplete error paths: generic catch blocks without specific handling
```

**Subagent split strategy:**

- If all files are same domain: single review subagent
- If backend + frontend: 2 parallel subagents
- If >20 changed files: split into groups of ~10 per subagent (max 3 parallel)

### Step 3: Intent Validation (IDD + BDD)

If `.temper/specs/{feature}/intent.md` exists, validate at TWO levels:

**BDD Level (mechanical):**

- Each scenario in intent.md → has a corresponding test → test passes
- Report as checklist in review

**IDD Level (structured validation):**

- Read the Intent section (problem, success criteria, constraints)
- Each success criterion has a `Validate:` field specifying how to check it:

| Validate Type | How to Check | Result |
|---------------|-------------|--------|
| `scenario` | Linked scenario's test passes | Mechanical — ✅/❌ |
| `code` | Grep for specified code/endpoint/config | Mechanical — ✅/❌ |
| `metric` | Cannot verify pre-deploy | Deferred — 📊 "Post-deploy monitoring required" |
| `manual` | Requires human judgment | Flagged — 🔍 "Manual check needed" |

- For each success criterion, execute its validation method:
  - ✅ Met: validation method confirms (scenario passes, code exists)
  - ❌ Not met: validation method fails (scenario fails, code missing)
  - 📊 Deferred: metric-based criterion, requires post-deploy measurement
  - 🔍 Manual: qualitative criterion, flagged for human review
- For each constraint: was it respected?
- Overall: "Intent satisfied" / "Intent partially satisfied — gaps: X, Y" / "Intent not satisfied"
- Count: "{N} mechanical, {N} deferred, {N} manual" — higher mechanical ratio = higher confidence

If no intent.md: fall back to checking linked issue (Jira/GitHub) as before.

### Step 3a: Semantic Test Validation (if intent.md exists)

After the mechanical BDD/IDD check in Step 3, validate that tests actually prove what they claim:

```
For each scenario with a passing test, validate the test BODY (not just its name):

0. LOCATE the test file for each scenario:
   a. Check intent.md's Scenario Coverage Checklist for test name mapping
   b. Grep test files for the scenario name or Gherkin annotations (e.g., @scenario-name)
   c. If not found → flag as "test not locatable" and skip to next scenario
1. READ the test function/method body (not just the name)
2. Verify structural alignment with Gherkin:
   - Given → test sets up preconditions (fixtures, mocks, data)
   - When → test invokes the action under test
   - Then → test asserts the expected outcomes
3. Check assertion quality:
   - Flag trivial assertions: assertTrue(true), assertEquals(x, x), no assertions at all
   - Flag incomplete assertions: Then clause expects "response contains token" but test only asserts status code
   - Flag catch-all assertions: assert response != null without checking specific fields
4. Report per-scenario:
   ✅ Scenario: "User logs in" — structurally aligned (Given/When/Then mapped)
   ⚠️ Scenario: "Rate limiting" — trivial assertion detected (assertTrue(true))
   ⚠️ Scenario: "Token returned" — incomplete: Then expects "token field" but test only asserts status 200
```

**Assertion quality labels:**
- STRONG — test sets up Given, invokes When, asserts Then with meaningful, specific assertions
- WEAK — test has incomplete assertions (Then expects "token" but only asserts status code); flagged as MEDIUM issue. Accept indirect assertions (helper methods, custom matchers) if they semantically cover the Then clause. If unsure whether an assertion covers a Then clause, do NOT flag.
- TRIVIAL — test has assertions that always pass (assertTrue(true), no assertions); flagged as LOW issue

These labels feed into the INTENT VERDICT evidence count: STRONG scenarios count toward the numerator, TRIVIAL scenarios do not, WEAK count as half.

**This step is additive** — existing mechanical checks still run first. Only runs when intent.md exists (backward compatible). Test body reading happens in the main review context, which already has access to changed files.

### Step 3b: Problem Statement Traceback (if intent.md exists)

After validating individual scenarios, step back and assess the BIG picture:

```
1. Re-read the Problem: field from intent.md
2. Read the implementation code (changed files)
3. Ask: "Does this implementation actually solve the stated problem?"
4. Check for implementation drift:
   - Problem says "password reset" but code implements "password change" → drift detected
   - Problem says "caching" but code implements "prefetching" → partial match (different strategies)
   - Problem says "multi-user" but code handles single user → gap detected

5. Report:
   ✅ Intent satisfied — implementation addresses: {list of problem aspects covered}
   ⚠️ Intent partially satisfied — gaps: {list of uncovered aspects}
   ❌ Intent not satisfied — implementation doesn't address the stated problem

6. This produces the SEMANTIC intent verdict (distinct from Step 3's mechanical verdict)
```

**Verdict reconciliation:** When both Step 3 (mechanical) and Step 3b (semantic) produce verdicts, use the most conservative:
- If only one verdict is available, use that verdict directly
- If both are available: any "Not satisfied" → final verdict is "Not satisfied"; all "Satisfied" → "Satisfied"; otherwise → "Partially satisfied"
The INTENT VERDICT in the summary always reflects this reconciled verdict.

**This is the "semantic bridge"** — it requires understanding the relationship between problem and solution. When the review runs as a subagent, it has access to changed files, so it can read them.

### Step 3c: Decision Point Coverage (if intent.md exists)

Check whether the code's decision points have corresponding scenarios:

```
1. Scan changed files for decision points:
   - if/else branches (especially in business logic)
   - try/catch blocks with different error types
   - switch/case statements
   - Early returns with different outcomes
   - Error response variations

   EXCLUDE (do not flag):
   - Input validation guards (null/undefined checks)
   - Logging branches (if (logger.isDebugEnabled()))
   - Single-line early returns with no business logic
   - Standard framework patterns (auth middleware redirects, etc.)

   FOCUS ON:
   - Business logic conditionals (different user types, states, outcomes)
   - Multi-branch error handling (different error types → different responses)
   - Branches that produce different user-visible outcomes

2. For each decision point:
   - Does a scenario in intent.md cover this branch?
   - If no scenario → flag as potential gap

3. Report:
   ✅ All decision points covered by scenarios
   ⚠️ Uncovered decision points:
     - auth.ts:42 — branch for "email not verified" → no matching scenario
     - payment.ts:89 — catch StripeCardError → no matching scenario

4. Severity: LOW (informational) — the developer decides whether to add scenarios
```

This catches missing scenarios that the plan phase didn't anticipate. Only scans changed files (not entire codebase) to keep scope reasonable. Low severity by default — it's a suggestion, not a blocker.

**If a Jira ticket or GitHub issue was linked (legacy mode):**

```
1. Re-read the original issue/ticket requirements
2. For each requirement, check if the implementation addresses it:
   - ✅ Requirement met
   - ⚠️ Partially met (explain what's missing)
   - ❌ Not addressed
3. Check edge cases mentioned in the issue/ticket comments
4. Flag any requirements that were not implemented
```

### Step 4: Apply Confidence Filtering

Combine results from all subagents. For each finding:

```
1. Check confidence score against threshold (default 0.7)
   - Below threshold → SUPPRESS (don't show to user)
   - Above threshold → include in report

2. Check review memory (.temper/review-memory.json)
   - Finding pattern dismissed 5+ times → SUPPRESS
   - Finding pattern dismissed 3-4 times → downgrade severity by 1 level
   - Finding pattern consistently accepted → keep as-is

3. Apply severity classification from pack rules
   - BLOCK rules → always CRITICAL regardless of confidence
   - WARN rules → HIGH or MEDIUM
   - SUGGEST rules → LOW
```

### Step 5: Nice Summary + Stage Gate

**If running as Agent subprocess:** Skip the AskUserQuestion gate. Return the review summary to the orchestrator. The orchestrator handles all gate decisions.

**If running standalone:** Show the summary and gate below.

After review completes, show a nice summary:

```
┌─────────────────────────────────────────────────────────────┐
│ REVIEW — {Feature Name}                                     │
├─────────────────────────────────────────────────────────────┤
│ WHAT WAS REVIEWED                                           │
│    Files: {N} changed files                                 │
│    Confidence: {X}% (avg of all finding confidence scores)  │
│                                                             │
│ ISSUES FOUND                                                │
│    Critical: {N} | High: {N} | Medium: {N} | Low: {N}      │
│    Auto-fixable: {N}                                        │
│                                                             │
│ SCENARIO COVERAGE (from intent.md)                          │
│    Covered: {X}/{Y} ({Z} automated, {W} manual)            │
│    ❌ {uncovered scenario name}                              │
│                                                             │
│ TOP ISSUES                                                  │
│    1. [{severity}] {file}:{line} — {one-line description}  │
│    2. [{severity}] {file}:{line} — {one-line description} │
│                                                             │
│ INTENT VERDICT (if intent.md exists)                        │
│    Problem: {one-line problem statement}                    │
│    Verdict: ✅ Intent satisfied / ⚠️ Partial / ❌ Not met    │
│    Evidence: {X}/{Y} scenarios substantively validated      │
│      (Y = total scenarios in intent.md, X = STRONG + ½ WEAK) │
│    Gaps:                                                    │
│      [assertion] {trivial/incomplete assertion gaps}        │
│      [drift] {implementation vs problem drift}              │
│      [coverage] {uncovered decision points}                 │
│                                                             │
│ What next?                                                  │
│   ▸ Fix all & continue to Check (Recommended)               │
│     Save for later                                          │
└─────────────────────────────────────────────────────────────┘
```

Use AskUserQuestion with these options:

```
AskUserQuestion:
  question: "What next?"
  options:
    - label: "Fix all & continue to Check (Recommended)"
      description: "Apply ALL fixes (including low severity), clear context, proceed to check."
    - label: "Save for later"
      description: "Skip review fixes and save state."
  multiSelect: false
```

| Response | Action |
|----------|--------|
| **Fix all & continue to Check** (first option) | Apply ALL fixes (including low severity), clear context, proceed to check |
| **Save for later** (second option) | Skip fixes, save state |

**On Fix all & continue to Check (first option):**

```
1. If auto-fixable issues exist: apply fixes
2. Save state to .temper/build-state.json
3. If running standalone:
   Signal:
   "✅ Continuing to CHECK...
    📂 Check needs no additional context — running validation pipeline."
   If running as Agent subprocess: The orchestrator handles context — return summary and stop.
4. If fixes applied: Re-run review (single pass, no subagents)
   - If new issues found: show updated summary, ask again (max 1 more loop)
   - If clean: proceed to /temper:check
5. If no fixes needed: proceed directly to /temper:check
```

**On Change (via "Other" free-text input):**

```
1. User types their change request in the "Other" field
2. Make the change
3. ⚠️ MANDATORY: Re-show AskUserQuestion with same options

GATE ENFORCEMENT: The user's change input is NOT approval to proceed.
Do NOT skip to check after making changes. The user MUST explicitly
select "Fix all & continue to Check" from the gate to proceed.
```

**On Save for later (second option):**

```
1. Skip review fixes
2. Save state to .temper/build-state.json:
   {
     "stage": "review_complete",
     "spec": "{feature-slug}",
     "spec_path": ".temper/specs/{feature-slug}",
     "original_args": "{from prior state}",
     "next_stage": "check",
     "artifacts": ["intent.md", "tasks.md"],
     "updated": "{ISO timestamp}"
   }
3. Report: "✅ Saved. Run /temper when ready to continue."
```

### Step 6: Auto-Fix (if enabled)

```
1. For each HIGH+ issue marked as auto-fixable:
   - Apply the suggested fix
   - Run relevant tests to verify fix doesn't break anything

2. After all auto-fixes applied:
   - Re-run review (single pass, no subagents) to verify fixes
   - Max 2 auto-fix loops total
   - If issues persist after 2 loops → show to user

3. Update review report with fix status
```

### Step 7: Update Metrics

Append to `.temper/metrics.json`:

```json
{
  "reviews": {
    "total": "+1",
    "issues_found": "+{count}",
    "by_severity": { "critical": "+X", "high": "+Y", ... },
    "by_category": { "security": "+X", "performance": "+Y", ... },
    "auto_fixed": "+{count}",
    "confidence_avg": "{avg score of all findings}"
  }
}
```

### Step 8: Update Review Memory

```json
// .temper/review-memory.json
// For each finding that was shown to user, track their response in next session
{
  "patterns": {
    "{pattern-key}": {
      "total_shown": 14,
      "accepted": 12,
      "dismissed": 2,
      "last_seen": "2026-03-09",
      "auto_rule": false,
      "context_variants": {}
    }
  }
}
```

When a pattern reaches 3+ accepted: suggest auto-rule in `/temper:status`.
When a pattern reaches 5+ dismissed: auto-suppress.

### Context-Dependent Dismissals

Findings can be valid in general but invalid in specific contexts. Track per-context in review-memory.json `context_variants`.

**Context detection:**

| Context | Detection | Why Dismissed |
|---------|-----------|---------------|
| Config loader | Path contains `config/` or class has `Config` | Validated at startup |
| Test fixtures | Path contains `test/`, `spec/`, `__tests__/` | Controlled data |
| DTOs | Class has `DTO`, `Request`, `Response` | Framework-validated |
| Legacy | Listed in `.temper/legacy-modules.json` | Known exception |
| Generated | Header contains `@generated` | Not editable |

**Suppression rules:**

```
- Context-specific dismissal >= 3 times → SUPPRESS in that context only
- Context dismissals are ISOLATED: dismissed in auth ≠ dismissed in payments
- On dismissal: ask "Dismiss for this file only, or all {context} files?"
```

### Multi-Agent Severity Consensus

```
1. Same severity from all agents → use that severity
2. Mixed severities → use highest (conservative)
3. One agent CRITICAL + others no finding → escalate to HIGH (not CRITICAL)
4. Disagreement on category → use "quality" as default
```

### AI-Code Detection Checklist (reference for standalone review)

(Expanded version of the inline checklist in Step 2 — subagents use the inline version; this section is reference for standalone review runs.)

When reviewing code, actively check for these AI-specific failure patterns:

```
1. HALLUCINATED APIS:
   - For each method/function call, verify the function EXISTS in the project's dependencies
   - Check: Does the imported module actually export this function?
   - Red flag: function name looks plausible but isn't in the library's API docs
   - How to detect: grep for the function definition. If not found in project or node_modules/vendor → flag as HIGH

2. PLAUSIBLE BUT WRONG:
   - Code uses the correct library but wrong parameters, wrong order, or wrong context
   - Red flag: async function called without await, callback passed to promise-based API
   - How to detect: compare against library's actual API signature in node_modules/vendor
   - Fallback (subagent context without dependency access): compare against the project's existing usage patterns of the same library. If the new call differs from established patterns, flag as MEDIUM.

3. OVER-ENGINEERING:
   - Unnecessary abstractions (interface for single implementation, factory for single product)
   - Helper utilities used only once
   - Premature generalization (type parameters never varied, strategy pattern with one strategy)
   - How to detect: count usages. If abstraction used once → flag as LOW

4. COPY-PASTE DRIFT:
   - Similar code blocks with subtle inconsistencies
   - Red flag: two blocks that look identical except one variable name, but the logic differs
   - How to detect: look for duplicated patterns in changed files, compare variable names and logic

5. MISSING INTEGRATION:
   - New code exists but isn't wired into routing, DI container, event handlers, or config
   - Red flag: new service class never registered, new route never mounted
   - How to detect: grep for imports/usage of the new module in existing wiring files

6. STALE PATTERNS:
   - Using deprecated APIs when the project has already migrated to newer ones
   - Red flag: new code uses patterns that old code used before a migration
   - How to detect: compare new code patterns against recent code in same directory

7. INCOMPLETE ERROR PATHS:
   - Happy path works, error handling is placeholder or generic
   - Red flag: catch blocks that just log or rethrow without meaningful handling
   - How to detect: for each try/catch, check if the catch block does something specific to the error type
```

These checks integrate into the existing parallel review subagents (Step 2). Each subagent runs the checklist on the files in its domain. The checklist doesn't create new subagents — it enhances the prompts for existing ones. All flags follow existing severity rules: hallucinated APIs = HIGH, over-engineering = LOW, etc.

### Automatic Next Step

- If CRITICAL or HIGH issues remain after auto-fix → show report, ask user
- If all clean → auto-chain to `/temper:check`
- If called manually (not from /temper:build) → show report, ask user for next action
