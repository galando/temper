---
description: "Run stack-aware validation pipeline"
---

# Check: Validation Pipeline

**Goal:** Auto-detect stack and run validation levels in order.

## Execution

> **Full methodology:** Read `$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/check.md`

### Quick Reference

Levels (stop on failure):
0. Environment — verify not production

1. Compile/Build
2. Unit Tests
3. Integration Tests (if configured)
4. Coverage (threshold from config)
5. Lint/Format
6. Type Check
7. Security (dependency scan)
