---
description: "Execute plan with TDD and quality gates"
---

# Build: Execute Plan

**Goal:** Implement approved plan task by task with TDD and graduated quality gates.

## Execution

> **Full methodology:** Read `$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/build.md`

### Quick Reference

1. Load plan from `.temper/specs/{feature}/tasks.md`
2. Verify feature branch (create if on main)
3. For each task: test from intent.md scenario (RED) → implement (GREEN) → validate
4. Scenario coverage gate: every intent.md scenario must have a passing test
5. Success criteria gate: code-validated criteria must be present (WARN only)
6. **Resumes interrupted builds from checkpoint**
7. After all tasks: auto-chain → /temper:review → /temper:check
8. Report results, ask to commit
