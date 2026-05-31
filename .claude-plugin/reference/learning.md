---
description: "Adaptive learning: pattern detection, rule suggestions, noise reduction"
---

# Adaptive Learning Reference

**Goal:** Post-review intelligence layer that detects recurring patterns, suggests pack rules, and suppresses noise.

Adaptive Learning runs as a **passive intelligence layer** inside `/temper:review` (Step 8.5) and `/temper:status` (dashboard section). It introduces no new commands. All learning state lives in `.temper/learning.json`.

---

## Pattern Detection Algorithm

Runs as Step 8.5 in `review.md`, after Step 8 (Update Review Memory).

### Input

- Findings from the completed review (category, file_path, description)
- `review-memory.json` patterns (acceptance/dismissal history)

### Algorithm

```
1. CLUSTER findings by (category, file_path_pattern, description_keywords):
   - file_path_pattern: extract directory prefix (e.g., src/services/*)
   - description_keywords: extract first 3 significant words from description
   - Categories: security, performance, quality, logic, architecture, test_gap, consistency

2. MATCH each cluster against learning.json detected_patterns:
   - If pattern exists: increment total_shown, update acceptance/dismissal counts
   - If new AND count >= 2: create new detected pattern entry

3. EVALUATE per-pattern statistics:
   - acceptance_rate = accepted / total_shown
   - dismissal_rate = dismissed / total_shown
   - context_breakdown: per-context counts
```

### Output

Updated `detected_patterns[]` in `.temper/learning.json`.

---

## Promotion Criteria

When a detected pattern meets these thresholds, the Suggestion Engine generates a rule template.

| Criterion | Threshold | Suggested Severity |
|-----------|-----------|-------------------|
| Accepted >= 3 AND acceptance_rate >= 70% | Met | WARN |
| Accepted >= 5 AND acceptance_rate >= 80% | Met | BLOCK (security/architecture only) |

On promotion:
1. Rule template written to `.temper/learning/suggestions/{pattern_id}.md`
2. Entry added to `suggestion_queue[]` in learning.json with status "pending"
3. Status dashboard shows the pending suggestion

---

## Suppression Criteria (Noise Reduction)

When a detected pattern meets these thresholds, the Noise Filter suppresses it.

| Criterion | Threshold | Action |
|-----------|-----------|--------|
| Dismissed >= 3 AND acceptance_rate < 30% | Met | Downgrade severity by 1 level |
| Dismissed >= 5 AND acceptance_rate < 10% | Met | Auto-suppress entirely |

Suppressed patterns move to `suppressed_patterns[]` in learning.json. Future reviews skip suppressed patterns entirely (review.md Step 4 reads learning.json for noise filter lookup).

---

## Context-Specific Handling

Context-specific dismissals are tracked independently per pattern. A pattern suppressed in one context continues to fire in others.

| Context | Detection | Behavior |
|---------|-----------|----------|
| config-loader | Path contains `config/` | Independent suppression per context |
| test-fixtures | Path contains `test/`, `spec/` | Independent suppression per context |
| data-transfer | Class has `DTO`, `Request`, `Response` | Independent suppression per context |
| legacy-module | Listed in `.temper/legacy-modules.json` | Independent suppression per context |
| generated-code | Header has `@generated` | Independent suppression per context |

Context breakdown is stored inline in each pattern's `context_breakdown` field in learning.json.

---

## Learning Curve Calculation

```
INPUT: metrics.json reviews.total + issues_by_severity counts
OUTPUT: learning_curve object in learning.json

1. Read issues_per_review from metrics history (or derive from issues_by_severity / reviews.total)
2. Compute trend:
   - Last 5 reviews: compute linear regression slope
   - Slope < -0.5 → "improving"
   - Slope between -0.5 and 0.5 → "stable"
   - Slope > 0.5 → "degrading"
   - Fewer than 3 reviews → "insufficient_data"
3. Compute improvement_pct:
   - (first_review_issues - last_review_issues) / first_review_issues * 100
   - Positive = improvement, Negative = degradation
```

---

## learning.json Schema

```json
{
  "version": 1,
  "last_updated": "{ISO timestamp}",
  "detected_patterns": [
    {
      "id": "missing-error-handling-services",
      "category": "quality",
      "file_pattern": "src/services/*",
      "description_keywords": ["missing", "error", "handling"],
      "total_shown": 4,
      "accepted": 3,
      "dismissed": 1,
      "acceptance_rate": 0.75,
      "first_seen": "{ISO timestamp}",
      "last_seen": "{ISO timestamp}",
      "status": "active | degraded | suppressed | promoted",
      "context_breakdown": {
        "test-fixtures": { "shown": 1, "dismissed": 1 },
        "default": { "shown": 3, "accepted": 3 }
      },
      "suggested_rule": null
    }
  ],
  "suppressed_patterns": [
    {
      "id": "n+1-query-repos",
      "reason": "5+ dismissals",
      "suppressed_at": "{ISO timestamp}",
      "contexts": ["default"]
    }
  ],
  "suggestion_queue": [
    {
      "pattern_id": "missing-error-handling-services",
      "suggested_severity": "WARN",
      "rule_template_path": ".temper/learning/suggestions/missing-error-handling-services.md",
      "created_at": "{ISO timestamp}",
      "status": "pending | accepted | rejected"
    },
    {
      "pattern_id": "config-update-error-handling-result-type",
      "suggested_severity": null,
      "type": "config-update",
      "category": "learned_convention",
      "description": "Services use Result<> type for error handling",
      "suggested_text": "- **Error Handling:** Use `Result<T, E>` type for all service methods.",
      "confidence": 0.85,
      "target": "CLAUDE.md",
      "created_at": "{ISO timestamp}",
      "status": "pending | accepted | rejected | deferred"
    }
  ],
  "learning_curve": {
    "reviews_sampled": [],
    "issues_per_review": [],
    "trend": "improving | stable | degrading | insufficient_data",
    "improvement_pct": 0
  }
}
```

---

## Integration Points

| System | Direction | Protocol | Purpose |
|--------|-----------|----------|---------|
| `/temper:review` (Step 8.5) | Inbound | File read/write (learning.json) | Post-review pattern detection trigger |
| `/temper:status` | Inbound | File read (learning.json) | Dashboard rendering |
| `review-memory.json` | Inbound | File read only | Pattern history for clustering |
| `metrics.json` | Inbound/Outbound | File read/write | Learning curve data, evidence updates |
| Pack system | Outbound | File write (suggestions/) | Promoted rule templates |
| review Step 4 | Outbound | File read (learning.json) | Noise filter lookup during confidence filtering |

---

## Graceful Degradation

When `learning.json` does not exist:

1. `/temper:review` skips Step 8.5 entirely. No errors, no warnings.
2. `/temper:status` shows "Adaptive learning: not yet initialized" in the ADAPTIVE LEARNING section.
3. All existing commands work exactly as before.
4. `learning.json` is created automatically on the first review that runs after the feature is built.

---

## Rule Template Format

Promoted patterns generate rule templates in `.temper/learning/suggestions/{pattern_id}.md`:

```markdown
## {Rule Name}

**Severity:** {BLOCK|WARN|SUGGEST}
**Category:** {category}
**Detection:** {file glob} + description keywords: {keywords}
**Auto-generated from learning pattern:** {pattern_id}

### Description
{What the rule catches}

### Detection Pattern
- File pattern: `{file_pattern}`
- Keywords: {description_keywords}
- Acceptance rate: {acceptance_rate} ({accepted}/{total_shown})

### Suggested Action
{Description of what to do when this pattern is found}
```
