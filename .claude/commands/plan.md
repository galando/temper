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
3. Research external docs if needed
4. Assess complexity + risk (trivial/simple/medium/complex)
5. Blast radius analysis (consumers, contracts, architectural drift)
6. Clarify if ambiguous (max 2-3 questions)
7. Generate spec/plan/tasks/quickstart to `.temper/specs/{feature}/`
8. Present for approval
