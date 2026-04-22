---
description: "Plan feature with impact analysis and blast radius"
argument-hint: "<feature-name-or-JIRA-123>"
---

# Plan a Feature

**Goal:** Transform feature request into implementation plan with impact analysis.

## Feature: $ARGUMENTS

## Execution

> **Full methodology:** Loaded via the `temper-ref-plan` rule

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
11. For Medium and Complex: generate mermaid diagram + ASCII art equivalent in plan.md (## Diagram section); render ASCII in terminal summary (not raw mermaid)
12. Present for approval with 4 options: Continue / Walkthrough / Change / Save

**Scenarios drive architecture. Every file must trace to a scenario or infrastructure need.**
