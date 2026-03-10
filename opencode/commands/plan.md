---
description: "Plan feature with impact analysis and blast radius"
argument-hint: "<feature-name-or-JIRA-123>"
---

# Plan a Feature

**Goal:** Transform feature request into implementation plan with impact analysis.

## Feature: $INPUT

## Execution

> **Full methodology:** See temper_plan tool documentation

### Quick Reference
1. Detect input (Jira/GitHub/description)
2. Auto-prime via codebase exploration (scan codebase, detect stack, find patterns)
3. Research external docs if needed
4. Assess complexity + risk (trivial/simple/medium/complex)
5. Blast radius analysis (consumers, contracts, architectural drift)
6. Clarify if ambiguous (max 2-3 questions)
7. Generate spec/plan/tasks/quickstart to `.temper/specs/{feature}/`
8. Present for approval

### Complexity Levels

| Files | Level | Artifacts |
|-------|-------|-----------|
| <3 | Trivial | None - implement directly |
| 3-5 | Simple | Inline plan |
| 5-10 | Medium | tasks.md + quickstart.md |
| 10+ | Complex | Full spec/plan/tasks/quickstart |

### Blast Radius Output

```
BLAST RADIUS — {feature-name}

  Direct impact:
    {File} ({action}) → used by {N} consumers

  Transitive impact:
    {Module} → calls {changed-function}()

  Risk areas:
    {Module} has {X}% test coverage for {path}

  Architectural compliance:
    ✅ {pattern} followed
    ⚠️ {concern}
```

### Templates

Templates are available in the `templates/` directory:
- `spec.md` — Requirements and acceptance criteria
- `plan.md` — Architecture and file changes
- `tasks.md` — Ordered implementation steps
- `quickstart.md` — 10-line summary
