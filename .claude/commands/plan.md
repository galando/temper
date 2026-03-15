---
description: "Plan feature with impact analysis and blast radius"
argument-hint: "<feature-name-or-JIRA-123>"
---

# Plan a Feature

**Goal:** Transform feature request into implementation plan with impact analysis.

## Feature: $ARGUMENTS

## Execution

> **Full methodology:** Read `$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/plan.md`

### Quick Reference

1. Detect input (Jira/GitHub/description)
2. Auto-prime via Explore subagent (scan codebase, detect stack, find patterns)
3. Build semantic index if needed (optional, for large codebases)
4. Research external docs if needed
5. Assess complexity + risk (trivial/simple/medium/complex)
6. Blast radius analysis (consumers, contracts, architectural drift)
7. Derive BDD scenarios from requirements + blast radius (medium+ complexity) — **before architecture**
8. Clarify if ambiguous (max 2-3 questions, informed by scenarios)
9. Generate spec/plan/tasks/quickstart to `.temper/specs/{feature}/` with file-to-scenario traceability
10. Generate intent.md with structured success criteria + Gherkin scenarios
11. For Complex: spec.md = WHAT, intent.md = WHY + validation (derive scenarios from acceptance criteria)
12. Present for approval

**Scenarios drive architecture. Every file must trace to a scenario or infrastructure need.**
