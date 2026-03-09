---
description: "Show quality metrics dashboard"
---

# Status: Quality Metrics Dashboard

**Goal:** Display accumulated quality metrics, trends, and learning loop suggestions.

## Execution

### Step 1: Read Metrics

```
1. Read .temper/metrics.json
2. Read .temper/review-memory.json
3. Read .temper/specs/ to find active specs
```

If `.temper/metrics.json` doesn't exist: show "No metrics yet. Run /temper:review or /temper:check to start tracking."

### Step 2: Display Dashboard

```
┌─────────────────────────────────────────────────────┐
│ Temper Status — {project-name}                       │
│ Period: Last 30 days                                 │
│                                                      │
│ REVIEWS                                              │
│   Total:           {count}                           │
│   Issues found:    {count}                           │
│   Auto-fixed:      {count} ({%})                     │
│   Manual fixes:    {count}                           │
│   Acceptance rate:  {%}                              │
│                                                      │
│ QUALITY TREND                                        │
│   Coverage:     {old}% → {new}% {↑/↓}               │
│   Avg issues/review:  {old} → {new} {↑/↓}           │
│   Blocked commits: {count}                           │
│                                                      │
│ TECHNICAL DEBT                                       │
│   Debt indicators: coverage {%}, lint violations {n} │
│   Trend: {improving/stable/degrading}                │
│                                                      │
│ TOP PATTERNS CAUGHT                                  │
│   1. {pattern} ({count}x) {→ AUTO-RULE / suggested}  │
│   2. {pattern} ({count}x)                            │
│   3. {pattern} ({count}x)                            │
│                                                      │
│ LEARNING LOOP                                        │
│   "{pattern}" found in {X}/{Y} reviews.              │
│   Want to add an auto-rule for this?                 │
│   [Yes, add rule]  [No thanks]                       │
│                                                      │
│ REVIEW MEMORY                                        │
│   Suppressed patterns: {count}                       │
│   Promoted to rules: {count}                         │
│                                                      │
│ STANDARDS COMPLIANCE                                 │
│   {standard name}: {%} compliant                     │
│   Violations: {count} ({description})                │
│                                                      │
│ ACTIVE SPECS                                         │
│   - {spec} ({status}, {X/Y tasks done})              │
└─────────────────────────────────────────────────────┘
```

### Step 3: Learning Loop Prompt

If any pattern count >= 3 and no auto-rule exists yet:

```
Use AskUserQuestion:
"'{pattern}' has been found in {X} reviews. Want to add it as an auto-rule?"

Options:
- "Yes, add as BLOCK rule" → add to active pack's Mandatory Rules
- "Yes, add as WARN rule" → add to active pack's Quality Rules
- "No, keep as advisory" → mark in review memory as "no-promote"
```

### Metrics Schema

```json
{
  "version": 1,
  "project": "{project name}",
  "reviews": {
    "total": 0,
    "issues_by_severity": { "critical": 0, "high": 0, "medium": 0, "low": 0 },
    "issues_by_category": { "security": 0, "performance": 0, "quality": 0, "logic": 0, "architecture": 0, "test_gap": 0 },
    "auto_fixed": 0,
    "suppressed": 0,
    "acceptance_rate": 0.0
  },
  "coverage_history": [],
  "test_count_history": [],
  "patterns": {},
  "plans": {
    "created": 0,
    "completed": 0,
    "in_progress": 0,
    "abandoned": 0
  },
  "fixes": {
    "total": 0,
    "rca_used": 0
  },
  "baseline": {
    "date": null,
    "coverage": null,
    "violations": null
  }
}
```

### Metric Calculation Formulas

| Metric | Formula | Notes |
|--------|---------|-------|
| **Acceptance Rate** | `accepted_findings / total_shown_findings` | Ratio of findings user accepted vs shown |
| **Auto-fix Rate** | `auto_fixed / total_issues` | Percentage of issues fixed automatically |
| **Coverage Trend** | `coverage_history[-1] - coverage_history[-7]` | Change over last 7 data points |
| **Issues/Review** | `sum(issues_found) / reviews.total` | Average issues per review |
| **Debt Ratio** | `(violations_current - violations_baseline) / violations_baseline` | Change since baseline |
| **Pattern Frequency** | `patterns[key].total_shown / reviews.total` | How often pattern appears |
| **Standards Compliance** | `(files_total - files_with_violations) / files_total * 100` | Percentage of compliant files |

### Quality Trends

Show change indicators in the dashboard:

| Trend | Visual | Meaning |
|-------|--------|---------|
| Coverage 85% → 77% | 📉 ↓8% | Degrading |
| Issues/review 2.1 → 1.8 | 📉 ↓14% | Improving |
| Debt ratio stable | ➡️ | No change |

**Trend interpretation:**
- If coverage dropping → user notices and can run `/temper:check` to investigate
- If issues/review rising → user sees it in the dashboard
- No automated alerts needed - the user reads the dashboard

### Learning Loop Lifecycle

```
Pattern detected → Shown in review → User response tracked
                                    ↓
                    ┌───────────────┴───────────────┐
                    ↓                               ↓
              Accepted (✓)                    Dismissed (✗)
                    ↓                               ↓
            count++ in patterns              count++ in patterns
            .accepted++                      .dismissed++
                    ↓                               ↓
        if accepted >= 3:                if dismissed >= 5:
        Prompt auto-rule                 Auto-suppress
        (in /temper:status)              (in /temper:review)
                    ↓                               ↓
        User chooses:                    Pattern added to
        BLOCK/WARN/No-promote            suppressed_patterns[]
```

**Auto-rule promotion criteria:**
- Pattern shown in >= 3 reviews
- Acceptance rate >= 70%
- No existing auto-rule for this pattern

**Auto-suppression criteria:**
- Pattern dismissed >= 5 times
- OR: User explicitly marked "no-promote"
