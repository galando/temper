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
- Only flag issues you are confident about (>0.5 confidence)
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

After review completes, show a nice summary:

```
┌─────────────────────────────────────────────────────────────┐
│ 🔍 REVIEW — {Feature Name}                                 │
├─────────────────────────────────────────────────────────────┤
│ ✅ WHAT WAS REVIEWED                                         │
│    Files: {N} changed files                                 │
│    Confidence: {X}%                                         │
│                                                             │
│ 📊 ISSUES FOUND                                              │
│    Critical: {N} | High: {N} | Medium: {N} | Low: {N}       │
│    Auto-fixable: {N}                                        │
│                                                             │
│ 🔧 TOP ISSUES                                                │
│    1. [{severity}] {file}:{line} — {one-line description}   │
│    2. [{severity}] {file}:{line} — {one-line description}   │
│                                                             │
│ What next?                                                  │
│   ▸ Fix & continue to Check (Recommended)                     │
│     Change something first                                    │
│     Save for later                                            │
└─────────────────────────────────────────────────────────────┘
```

Use AskUserQuestion with these options:

```
AskUserQuestion:
  question: "What next?"
  options:
    - label: "Fix & continue to Check (Recommended)"
      description: "Apply auto-fixes, re-run review, then proceed to check."
    - label: "Change something first"
      description: "Type what you want to change. Claude edits, then re-asks."
    - label: "Save for later"
      description: "Skip review fixes and save state."
  multiSelect: false
```

| Response | Action |
|----------|--------|
| **Fix & continue** (first option) | Apply all auto-fixes, wait, re-run review |
| **Change something** | User types what to change. Claude edits. Re-ask. |
| **Save** | Skip review fixes, save state |

**On Fix & continue (first option):**

```
1. If auto-fixable issues exist: apply fixes
2. Signal:
   "✅ Continuing to CHECK...
    🧹 Clearing context for efficiency."
3. Clear context
4. If fixes applied: Re-run review (single pass, no subagents)
   - If new issues found: show updated summary, ask again (max 1 more loop)
   - If clean: proceed to /temper:check
5. If no fixes needed: proceed directly to /temper:check
```

**On Change something (second option):**

```
1. Ask: "What would you like to change?"
2. User types their change request
3. Claude makes the change
4. Re-show AskUserQuestion with same options
```

**On Save (third option):**

```
1. Skip review fixes
2. Signal:
   "✅ Continuing to CHECK...
    🧹 Clearing context for efficiency."
3. Clear current context
4. Load nothing new (check doesn't need additional context)
5. Proceed to /temper:check
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

### AI-Generated Code: Extra Scrutiny

AI-written code has specific failure patterns. Flag these with higher confidence:

```
- Hallucinated APIs: method/function calls that don't exist in the project's dependencies
- Plausible but wrong: code that looks correct but misuses a library's API
- Over-engineering: unnecessary abstractions, helper utils used once, premature generalization
- Copy-paste drift: similar-looking code blocks with subtle inconsistencies
- Missing integration: new code not wired into existing routing, DI, or config
- Stale patterns: using deprecated APIs when the project has already migrated to newer ones
- Incomplete error paths: happy path works, error handling is placeholder or generic
```

### Automatic Next Step

- If CRITICAL or HIGH issues remain after auto-fix → show report, ask user
- If all clean → auto-chain to `/temper:check`
- If called manually (not from /temper:build) → show report, ask user for next action
