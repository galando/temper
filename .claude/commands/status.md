---
description: "Show quality metrics and learning loop"
---

# Status: Quality Metrics Dashboard

**Goal:** Display metrics, trends, learning loop suggestions.

## Execution

> **Full methodology:** Read `$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/status.md`

### Quick Reference

1. Initialize `.temper/` directory if missing (metrics, review-memory, specs/)
2. Read `.temper/metrics.json` + `.temper/review-memory.json`
3. Display: reviews, quality trend, debt, hotspots, top patterns, learning loop, active specs
4. If pattern count >= 3: suggest auto-rule
5. **Hotspot map**: shows which files generate the most issues
