---
description: "Build team engineering standards interactively"
---

# Standards: Interactive Standards Builder

**Goal:** Scan codebase for patterns, interview about conventions, generate company pack + preset.

## Execution

> **Full methodology:** Read `$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/standards.md`

### Quick Reference
1. Scan codebase via Explore subagent (patterns, consistency, inconsistencies)
2. Interview developer (5-10 questions about conventions)
3. Generate `.claude/packs/{company}/rules.md` + preset
4. Validate against current codebase, set baseline
