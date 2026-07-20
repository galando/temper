---
description: "Show quality metrics, learning loop, and observability dashboard"
---

# Status: Quality Metrics Dashboard

**Goal:** Display metrics, trends, learning loop suggestions, and observability data.

## Execution

> **Full methodology:** Read `$CLAUDE_PLUGIN_ROOT/reference/status.md`

### Quick Reference

1. Initialize `.temper/` directory if missing (metrics, review-memory, specs/)
2. Read `.temper/metrics.json` + `.temper/review-memory.json`
3. Read `.temper/gates.json` + `.temper/evidence/*.json` (the current/last run's
   evidence-backed gate ledger — run `$CLAUDE_PLUGIN_ROOT/scripts/temper report`, or read
   the files directly)
4. Read `.temper/feedback-loops.json` (if exists — active feedback loop state)
5. **Detect MCP tools**: attempt to call `get_impact_radius_tool` (code-review-graph) and check if semgrep tools are available. Report availability in dashboard.
6. Display: reviews, quality trend, debt, hotspots, top patterns, learning loop, active specs, **MCP TOOLS section**, **GATE LEDGER section**, **FEEDBACK LOOPS section**
7. If pattern count >= 3: suggest auto-rule
8. **Hotspot map**: shows which files generate the most issues

### Gate Ledger Panel (v7 — replaces the v6.x Observability/Economics panels)

v6.x rendered per-stage cost/latency/token estimates here — numbers with no mechanical
backing, exactly what v7 stops presenting as fact. v7 shows only what `temper gate` and
`temper evidence` actually recorded:

```
GATE LEDGER
  {output of: $CLAUDE_PLUGIN_ROOT/scripts/temper report}

  Evidence: {N} PROVEN, {N} HEURISTIC, {N} SEMANTIC (this run)
```

**Graceful absence:** if `.temper/gates.json` does not exist, print `"No gate data yet.
Run /temper to populate it."` Do not error.

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
