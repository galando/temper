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
3. Read `.temper/observability.json` (if exists — per-stage metrics from v4.0.0)
4. Read `.temper/feedback-loops.json` (if exists — active feedback loop state)
5. **Detect MCP tools**: attempt to call `get_impact_radius_tool` (code-review-graph) and check if semgrep tools are available. Report availability in dashboard.
6. Display: reviews, quality trend, debt, hotspots, top patterns, learning loop, active specs, **MCP TOOLS section**, **OBSERVABILITY section**, **FEEDBACK LOOPS section**
7. If pattern count >= 3: suggest auto-rule
8. **Hotspot map**: shows which files generate the most issues

### Observability Dashboard (v5.6.0)

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

### Economics Panel (v5.6.0 — Deliverable 4)

If `.temper/observability.json` has `version: 2` AND `.temper/metrics.json` exists, render:

```
ECONOMICS
  Per-stage cost / latency / tier (last run):

  | Stage   | Tier          | Cost (USD)  | Latency   | Tokens      | Tool Calls |
  |---------|---------------|-------------|-----------|-------------|------------|
  | Plan    | tier-frontier | $0.{cc}     | {Y}s      | {in+out}    | {N}        |
  | Build   | tier-standard | $0.{cc}     | {Y}s      | {in+out}    | {N}        |
  | Review  | tier-fast     | $0.{cc}     | {Y}s      | {in+out}    | {N}        |
  | ...     | ...           | ...         | ...       | ...         | ...        |

  Rolling averages (last K runs):
    Avg cost / feature:   $0.{cc}  (source: pricing)
    Avg latency / feature: {Y}s    (source: measured)

  Eval-score trend (last K runs): {score1} -> {scoreK}  ({trend: up|flat|down})

  Drift flags (Deliverable 3): {N} active
    [SUGGEST] build.tool_calls = {v} ({std_devs}σ above baseline {mean})

  CapEx vs OpEx summary:
    CapEx (one-time): eval sets authored ({N}), packs/hooks configured ({N}),
                      context files ({N})
    OpEx  (per-feature): ~${cc} tokens/feature, {Y} pipeline-mins/feature
    Thesis: upfront structure lowers marginal cost per shipped feature.
```

Surface the `source` flag next to each numeric (e.g. "$0.04 (pricing)", "tokens: 12.4k (estimated)")
so the dashboard never lies about provenance.

**Graceful absence:** if `.temper/observability.json` does NOT exist OR is not v2, print:

```
ECONOMICS
  No observability data yet. Run /temper to capture per-stage cost and telemetry.
```

Do NOT error. Preserve the prior graceful behavior for the OBSERVABILITY panel.

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
