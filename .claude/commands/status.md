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
3. **Detect MCP tools**: attempt to call `get_impact_radius_tool` (code-review-graph) and check if semgrep tools are available. Report availability in dashboard.
4. Display: reviews, quality trend, debt, hotspots, top patterns, learning loop, active specs, **MCP TOOLS section**
5. If pattern count >= 3: suggest auto-rule
6. **Hotspot map**: shows which files generate the most issues
