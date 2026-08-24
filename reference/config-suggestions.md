---
description: "Post-check config suggestions — analyze what was built and suggest CLAUDE.md/AGENTS.md updates"
---

# Config Suggestions

**Goal:** After Check passes, analyze what was built and suggest updates to CLAUDE.md or AGENTS.md. Captures new patterns, learned conventions, and architectural decisions as config suggestions.

## When to Trigger

After all validation levels in `/temper:check` pass (no failures), before the Commit gate:

1. Check validation passed (compile, tests, coverage, lint, security all green)
2. At least one file was changed (`git diff --name-only` returns results)

## Analysis Inputs

```
1. git diff --stat (files changed, lines added/removed)
2. .temper/specs/{feature}/intent.md (what was planned)
3. .temper/specs/{feature}/build-context.json (what was actually built)
4. .temper/specs/{feature}/tasks.md (tasks completed)
5. Existing CLAUDE.md content (project root or .claude/CLAUDE.md)
6. Existing AGENTS.md content (project root or .claude/AGENTS.md, if exists)
```

## Suggestion Categories

| Category | Detection | Example |
|----------|-----------|---------|
| New pattern | Code introduces a reusable pattern not in existing docs | "Services use Result<> for error handling" |
| Learned convention | Naming/structure convention observed consistently in new code | "Test files follow *.test.ts naming" |
| Architectural decision | Structural choice that affects future code | "All API routes use /api/v2/ prefix" |
| Tooling config | New tool or config discovered | "Add ESLint rule for async/await" |

## Generation Algorithm

```
1. ANALYZE changed files for patterns:
   a. Error handling patterns (try/catch, Result<>, throw, .catch)
   b. Naming conventions (file naming, class naming, function naming)
   c. Directory structure patterns (where new files were placed)
   d. Import/export patterns (barrel exports, named exports)
   e. Testing patterns (describe/it, Given/When/Then, test helpers)
   f. Configuration patterns (env vars, config files, feature flags)
   g. API patterns (route structure, middleware, validation)
   h. Data patterns (DTOs, mappers, serializers)

2. COMPARE against existing CLAUDE.md/AGENTS.md:
   - Is this pattern ALREADY documented? → Skip
   - Is this pattern NEW or DIFFERENT from documented? → Generate suggestion
   - Does this CONTRADICT documented patterns? → Flag as inconsistency

3. GENERATE suggestions:
   For each new/changed pattern:
   - type: new_pattern | learned_convention | architectural_decision | tooling_config
   - description: plain English explanation
   - suggested_text: the actual text to add to CLAUDE.md/AGENTS.md
   - confidence: 0.0-1.0 (how certain this is a real pattern vs one-off)
   - target: CLAUDE.md | AGENTS.md

4. FILTER:
   - Skip suggestions with confidence < 0.6
   - Skip patterns that only appear once (likely one-off)
   - Skip patterns already in existing docs
   - Max 5 suggestions per check (prevent overwhelm)
```

## How suggestions are handled at the gate

1. **Written to the spec:** each suggestion goes to
   `.temper/specs/{feature}/config-suggestions.json`.
2. **User interaction:** Accept, Reject, or Defer each one at the Check gate.
3. **Accepted:** written to CLAUDE.md or AGENTS.md immediately.
4. **Rejected:** recorded as a dismissal in `review-memory.json` (the single finding
   memory) under a `config:{pattern_id}` key — 3+ dismissals of the same suggestion
   pattern auto-suppress it from future checks.
5. **Deferred:** left in the spec's `config-suggestions.json` for the next check.

## Suggestion Format

```json
{
  "pattern_id": "error-handling-result-type",
  "category": "learned_convention",
  "description": "Services use Result<> type for error handling",
  "suggested_text": "- **Error Handling:** Use `Result<T, E>` type for all service methods. Avoid throwing exceptions for business logic errors.",
  "confidence": 0.85,
  "target": "CLAUDE.md",
  "evidence": {
    "files_checked": 5,
    "files_following_pattern": 4,
    "files_contradicting": 1
  }
}
```

## Graceful Degradation

- If CLAUDE.md doesn't exist: still generate suggestions, target file creation
- If AGENTS.md doesn't exist: skip AGENTS.md suggestions
- If no patterns detected (trivial change): show "No config suggestions for this change" at the gate

This capability does NOT modify files without user consent. All suggestions require explicit Accept at the Check gate.
