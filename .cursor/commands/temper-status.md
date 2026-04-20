---
description: "Show quality metrics, learning loop, and observability dashboard"
---

# Status: Quality Metrics Dashboard

**Goal:** Display metrics, trends, learning loop suggestions, and observability data.

## Execution

> **Full methodology:** Read `$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/status.md`

### Quick Reference

1. Initialize `.temper/` directory if missing (metrics, review-memory, specs/)
2. Read `.temper/metrics.json` + `.temper/review-memory.json`
3. Read `.temper/observability.json` (if exists — per-stage metrics from v4.0.0)
4. Read `.temper/feedback-loops.json` (if exists — active feedback loop state)
5. **Detect MCP tools**: attempt to call `get_impact_radius_tool` (code-review-graph) and check if semgrep tools are available. Report availability in dashboard.
6. Display: reviews, quality trend, debt, hotspots, top patterns, learning loop, active specs, **MCP TOOLS section**, **OBSERVABILITY section**, **FEEDBACK LOOPS section**
7. If pattern count >= 3: suggest auto-rule
8. **Hotspot map**: shows which files generate the most issues

### Observability Dashboard (v4.0.0)

If `.temper/observability.json` exists and `observability.enabled: true` in temper.config, show:

```
OBSERVABILITY
  Per-stage metrics (last 10 runs):

  | Stage   | Avg Tokens | Avg Latency | Avg Tool Calls | Total Runs |
  |---------|------------|-------------|----------------|------------|
  | Plan    | ~{X}       | ~{Y}s       | ~{Z}           | {N}        |
  | Design  | ~{X}       | ~{Y}s       | ~{Z}           | {N}        |
  | Build   | ~{X}       | ~{Y}s       | ~{Z}           | {N}        |
  | Review  | ~{X}       | ~{Y}s       | ~{Z}           | {N}        |
  | Check   | ~{X}       | ~{Y}s       | ~{Z}           | {N}        |

  Pipeline totals:
    Total runs: {N}
    Avg total pipeline latency: ~{X}s
```

### Feedback Loops Section (v4.0.0)

If `.temper/feedback-loops.json` exists and `feedback.enabled: true` in temper.config, show:

```
FEEDBACK LOOPS
  Active loops: {N}
  History: {N} completed loops
  Most common loop: {type} ({N} times)
  Circuit breaker triggers: {N}
```

If no feedback loops have occurred: "No feedback loops triggered yet."
