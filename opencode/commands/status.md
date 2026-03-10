---
description: "Show quality metrics and learning loop"
---

# Status: Quality Metrics Dashboard

**Goal:** Display metrics, trends, learning loop suggestions.

## Execution

> **Full methodology:** See temper_status tool documentation

### Quick Reference
1. Read `.temper/metrics.json` + `.temper/review-memory.json`
2. Display: reviews, quality trend, debt, top patterns, learning loop, active specs
3. If pattern count >= 3: suggest auto-rule

### Dashboard Display

```
╔═══════════════════════════════════════════════════════════════╗
║                     TEMPER METRICS DASHBOARD                   ║
╠═══════════════════════════════════════════════════════════════╣
║  Reviews Run:         {count}                                  ║
║  Quality Trend:       {improving/stable/declining} ↑/→/↓       ║
║  Tech Debt Score:     {score}/10                               ║
║  Active Specs:        {count}                                  ║
╠═══════════════════════════════════════════════════════════════╣
║  TOP PATTERNS DETECTED                                         ║
║  1. {pattern} - {count} occurrences                            ║
║  2. {pattern} - {count} occurrences                            ║
║  3. {pattern} - {count} occurrences                            ║
╠═══════════════════════════════════════════════════════════════╣
║  LEARNING LOOP                                                 ║
║  {suggestion for new rule based on pattern}                    ║
║  Run temper_standards to add as team rule                      ║
╚═══════════════════════════════════════════════════════════════╝
```

### Data Sources

- `.temper/metrics.json` - Review counts, patterns, trends
- `.temper/review-memory.json` - Dismissed findings
- `.temper/specs/*/tasks.md` - Active specs

### Pattern → Rule Suggestion

If a pattern appears 3+ times:
- Suggest creating a team rule
- Show example of rule to add
- Run `temper_standards` to add it

### Metrics Structure

```json
{
  "reviews": {
    "total": 42,
    "thisWeek": 7
  },
  "patterns": [
    { "name": "long-method", "count": 15 },
    { "name": "missing-test", "count": 8 }
  ],
  "trend": "improving"
}
```
