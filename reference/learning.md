---
description: "Adaptive learning: pattern detection, rule suggestions, noise reduction"
---

# Adaptive Learning Reference

**Goal:** A passive intelligence layer inside `/temper:review` (Step 8.5) and
`/temper:status` (dashboard) that detects recurring findings, suggests pack rules, and
suppresses noise. No new commands; all state lives in `.temper/learning.json`.

## Pattern Detection (review.md Step 8.5, after Step 8 Update Review Memory)

**Input:** this review's findings (category, file_path, description) +
`review-memory.json`'s acceptance/dismissal history.

1. **Cluster** findings by `(category, file_path_pattern, description_keywords)` —
   `file_path_pattern` is the directory prefix (`src/services/*`),
   `description_keywords` the first 3 significant words. Categories: security,
   performance, quality, logic, architecture, test_gap, consistency.
2. **Match** each cluster against `detected_patterns[]`: existing → increment
   `total_shown` and acceptance/dismissal counts; new with count >= 2 → create an entry.
3. **Compute** per pattern: `acceptance_rate = accepted / total_shown`,
   `dismissal_rate = dismissed / total_shown`, plus a `context_breakdown`.

## Promotion (Suggestion Engine)

| Threshold | Suggested severity |
|---|---|
| Accepted >= 3 AND acceptance_rate >= 70% | WARN |
| Accepted >= 5 AND acceptance_rate >= 80% | BLOCK (security/architecture only) |

On promotion: write a rule template to `.temper/learning/suggestions/{pattern_id}.md`,
add a `pending` entry to `suggestion_queue[]` — `/temper:status` shows it.

## Suppression (Noise Filter)

| Threshold | Action |
|---|---|
| Dismissed >= 3 AND acceptance_rate < 30% | Downgrade severity by 1 level |
| Dismissed >= 5 AND acceptance_rate < 10% | Auto-suppress entirely |

Suppressed patterns move to `suppressed_patterns[]`; future reviews skip them
(`review.md` Step 4 reads `learning.json` for the noise-filter lookup).

## Context-Specific Handling

Each pattern's dismissals are tracked **independently per context** — suppressed in one
context still fires in another:

| Context | Detection |
|---|---|
| config-loader | path contains `config/` |
| test-fixtures | path contains `test/`, `spec/` |
| data-transfer | class has `DTO`, `Request`, `Response` |
| legacy-module | listed in `.temper/legacy-modules.json` |
| generated-code | header has `@generated` |

Stored inline per pattern's `context_breakdown` field.

## Learning Curve

From `metrics.json`'s `reviews.total` + `issues_by_severity` history: linear-regression
slope over the last 5 reviews — < -0.5 → `improving`, -0.5..0.5 → `stable`, > 0.5 →
`degrading`, fewer than 3 reviews → `insufficient_data`. `improvement_pct =
(first_review_issues - last_review_issues) / first_review_issues * 100` (positive =
improvement).

## learning.json Schema

```json
{
  "version": 1, "last_updated": "{ISO timestamp}",
  "detected_patterns": [ {
    "id": "missing-error-handling-services", "category": "quality",
    "file_pattern": "src/services/*", "description_keywords": ["missing", "error", "handling"],
    "total_shown": 4, "accepted": 3, "dismissed": 1, "acceptance_rate": 0.75,
    "first_seen": "", "last_seen": "", "status": "active|degraded|suppressed|promoted",
    "context_breakdown": { "test-fixtures": { "shown": 1, "dismissed": 1 }, "default": { "shown": 3, "accepted": 3 } },
    "suggested_rule": null
  } ],
  "suppressed_patterns": [ { "id": "n+1-query-repos", "reason": "5+ dismissals",
    "suppressed_at": "", "contexts": ["default"] } ],
  "suggestion_queue": [
    { "pattern_id": "missing-error-handling-services", "suggested_severity": "WARN",
      "rule_template_path": ".temper/learning/suggestions/missing-error-handling-services.md",
      "created_at": "", "status": "pending|accepted|rejected" },
    { "pattern_id": "config-update-error-handling-result-type", "suggested_severity": null,
      "type": "config-update", "category": "learned_convention",
      "description": "Services use Result<> type for error handling",
      "suggested_text": "- **Error Handling:** Use `Result<T, E>` type for all service methods.",
      "confidence": 0.85, "target": "CLAUDE.md", "created_at": "",
      "status": "pending|accepted|rejected|deferred" } ],
  "learning_curve": { "reviews_sampled": [], "issues_per_review": [],
    "trend": "improving|stable|degrading|insufficient_data", "improvement_pct": 0 }
}
```

## Integration Points

| System | Direction | Purpose |
|---|---|---|
| `/temper:review` Step 8.5 | writes | Post-review pattern detection |
| `/temper:status` | reads | Dashboard rendering |
| `review-memory.json` | reads | Pattern history for clustering |
| `metrics.json` | reads/writes | Learning curve data |
| Pack system | writes `suggestions/` | Promoted rule templates |
| `review.md` Step 4 | reads | Noise-filter lookup during confidence filtering |

## Graceful Degradation

No `learning.json` → Review skips Step 8.5 (no errors/warnings), Status shows "Adaptive
learning: not yet initialized", everything else unaffected. Created on the first review
after a feature builds.

## Rule Template Format

`.temper/learning/suggestions/{pattern_id}.md`:

```markdown
## {Rule Name}
**Severity:** {BLOCK|WARN|SUGGEST}  **Category:** {category}
**Detection:** {file glob} + keywords: {keywords}
**Auto-generated from learning pattern:** {pattern_id}

### Description
{What the rule catches}

### Detection Pattern
- File pattern: `{file_pattern}`  Keywords: {description_keywords}
- Acceptance rate: {acceptance_rate} ({accepted}/{total_shown})

### Suggested Action
{What to do when this pattern is found}
```
