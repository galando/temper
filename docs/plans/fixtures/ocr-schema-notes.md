# OCR Output Schema Notes

**Captured from:** `ocr` v1.3.1 (open-code-review)
**Date:** 2026-06-12
**Command:** `ocr review --commit <sha> --format json --audience agent --concurrency 8`

## Top-Level Structure

```json
{
  "status": "success" | "error",
  "summary": { ... },
  "comments": [ ... ]
}
```

## `summary` Object

| Field | Type | Description |
|-------|------|-------------|
| `files_reviewed` | int | Number of files reviewed |
| `comments` | int | Total findings count |
| `total_tokens` | int | Total LLM tokens consumed |
| `input_tokens` | int | Input tokens |
| `output_tokens` | int | Output tokens |
| `cache_read_tokens` | int | Cached tokens (cost savings) |
| `elapsed` | string | Wall-clock time (e.g., "22s") |

## `comments[]` Array Items

| Field | Type | Description |
|-------|------|-------------|
| `path` | string | File path relative to repo root |
| `content` | string | Finding description (free text, may contain severity hint in prose) |
| `suggestion_code` | string | Suggested fix (code block) |
| `existing_code` | string | Current code at the finding location |
| `start_line` | int | Start line of the finding |
| `end_line` | int | End line of the finding |

## Severity Extraction

OCR v1.3.1 does NOT emit a structured `severity` field. Severity is embedded
in the `content` prose (e.g., "Critical Bug:", "Security Vulnerability",
"Security Issue").

**Extraction heuristic:**
1. Parse `content` for leading severity keywords:
   - `Critical Bug` or `critical` -> CRITICAL
   - `Security Vulnerability` or `Vulnerability` -> CRITICAL
   - `Security Issue` -> HIGH
   - `Bug` or `Error` -> HIGH
   - `Warning` -> MEDIUM
   - `Suggestion` or `Improvement` -> LOW
2. Default: MEDIUM (if no severity keyword detected)

**Category extraction from content:**
- SQL Injection, XSS, CSRF -> security
- Hardcoded Secret, API Key -> security
- NPE, TypeError, null check -> logic
- Performance, N+1 -> performance
- Default -> quality

## Dirty Tree Behavior

Not tested empirically (requires uncommitted changes). Per OCR docs, the `--commit`
flag reviews a specific commit against its parent. Without `--commit`, OCR reviews
staged + unstaged + untracked changes. Temper should use `--from <base> --to <head>`
for branch reviews and skip OCR on dirty trees.

## Version Pinning

Minimum supported version: **1.3.1** (first version tested against).

## CLI Flags Used by Temper

```bash
ocr review --from <base-ref> --to <head-ref> \
  --format json --audience agent \
  --concurrency {cfg} --timeout {cfg}
```

Note: `--timeout` is not a native OCR flag. Temper wraps the invocation with
a Bash-level timeout (`timeout` command or shell equivalent).

## Dedupe Fields

For deduplication against Temper subagent findings:
- **File:** `path` (exact match)
- **Line:** `start_line` (match within +/- 2)
- **Category:** extracted from `content` (match by category family: security, logic, performance, quality)
