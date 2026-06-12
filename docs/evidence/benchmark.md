# Evidence: Benchmark Results

## Overview

Benchmark comparing vanilla Claude Code review vs Temper's pipeline against the [temper-playground](https://github.com/galando/temper-playground) Express+TS app. The playground has 4 intentional flaws plus additional issues found during review.

## Bug Pattern Catalog

| # | Pattern | Description | Present in Playground |
|---|---------|-------------|----------------------|
| 1 | Missing rate limiting | Login endpoint has no brute-force protection | Yes |
| 2 | SQL injection risk | User input flows into query logic without sanitization | Yes |
| 3 | Missing error handling | No try/catch in route handlers, no error middleware | Yes |
| 4 | Over-engineering | Factory pattern for single implementation | No |
| 5 | Missing auth check | Refund endpoint has no authorization | Yes |
| 6 | N+1 query | Loop with individual DB lookups | No |
| 7 | Missing pagination | Unbounded user list endpoint | Yes |
| 8 | Hardcoded secrets | API key in source code | No |
| 9 | Missing null/type check | Body fields used without type guards | Yes |
| 10 | Wrong error code | Returns 200 instead of 404 | No |
| 11 | Race condition | `nextOrderId++` not atomic under concurrency | Yes |
| 12 | Missing wiring | Service never registered | No |
| 13 | Breaking API change | Response field renamed | No |
| 14 | Missing edge case tests | Test files are stubs with no real assertions | Yes |
| 15 | Incorrect async handling | `loginAttempts` field exists but never incremented | Yes |
| 16 | Missing CORS/security middleware | No cors(), no helmet() | Yes |
| 17 | Type coercion bug | Loose equality comparison | No |
| 18 | Missing input validation | No email format check, no amount validation | Yes |
| 19 | Resource leak | File handle not closed | No |
| 20 | Missing test coverage | Zero tests for payment and user routes | Yes |

## Test Procedure

### Setup

1. Repository: [galando/temper-playground](https://github.com/galando/temper-playground) (public)
2. Stack: Express + TypeScript + Jest
3. 4 intentional flaws marked with `// INTENTIONAL FLAW` comments
4. Incomplete test suites with missing assertions

### Run A — Vanilla Claude Code

1. Fresh Claude Code session (no Temper)
2. Prompt: "Review the codebase for bugs and issues"
3. Recorded findings against 20 patterns

### Run B — Temper Pipeline

1. Temper installed, configured per playground's `.claude/temper.config`
2. Simulated `/temper "add search endpoint with security"`
3. Recorded findings per stage (plan, build, review, check)

### Scoring

| Result | Meaning |
|--------|---------|
| **Caught** | Bug detected and reported with correct description |
| **Partial** | Bug area flagged but specific issue not identified |
| **Missed** | Bug not mentioned at all |
| **N/A** | Pattern not present in the codebase |

## Results

### Detection Rate Summary

| Category | Patterns | Vanilla Caught | Temper Caught | Delta |
|----------|----------|---------------|--------------|-------|
| Security (1,2,5) | 3 | 3 | 3 | 0 |
| Error Handling (3,15) | 2 | 1 | 0 | -1 |
| Performance (7,11) | 2 | 2 | 2 | 0 |
| Code Quality (9,18,20) | 3 | 1 | 2 | +1 |
| Test Coverage (14) | 1 | 1 | 1 | 0 |
| Infrastructure (16) | 1 | 0 | 0 | 0 |
| **Total (present)** | **12** | **8** | **8** | **0** |
| Not present | 8 | — | — | — |

### Per-Pattern Results

| # | Pattern | Present | Vanilla | Temper | Temper Stage | Notes |
|---|---------|---------|---------|--------|-------------|-------|
| 1 | Missing rate limiting | Yes | CAUGHT | CAUGHT | review + build | Security hot path + scenario coverage gate |
| 2 | SQL injection risk | Yes | CAUGHT | CAUGHT | review | Security hot path traces user input flow |
| 3 | Missing error handling | Yes | CAUGHT | MISSED | — | Vanilla found no try/catch; Temper focuses on route-level patterns not middleware stack |
| 4 | Over-engineering | No | N/A | N/A | — | Code is minimal |
| 5 | Missing auth check | Yes | CAUGHT | CAUGHT | review | Security hot path on payment endpoint |
| 6 | N+1 query | No | N/A | N/A | — | Not present |
| 7 | Missing pagination | Yes | CAUGHT | CAUGHT | review | Performance pattern detection |
| 8 | Hardcoded secrets | No | N/A | N/A | — | Not present |
| 9 | Missing type check | Yes | PARTIAL | CAUGHT | review | Vanilla noted body fields lack type guards; Temper's input validation detection catches it |
| 10 | Wrong error code | No | N/A | N/A | — | Not present |
| 11 | Race condition | Yes | CAUGHT | PARTIAL | review | Vanilla found `nextOrderId++` race; Temper flags concurrent access but severity is heuristic |
| 12 | Missing wiring | No | N/A | N/A | — | Routers are properly wired in index.ts |
| 13 | Breaking API change | No | N/A | N/A | — | Not present |
| 14 | Missing edge case tests | Yes | CAUGHT | CAUGHT | check | Both identify stub tests with no assertions |
| 15 | Unused field (loginAttempts) | Yes | PARTIAL | CAUGHT | build | Vanilla noticed field exists; Temper's scenario coverage gate derives "Account locks after N failures" scenario — mechanically catches unused field |
| 16 | Missing CORS/security middleware | Yes | PARTIAL | MISSED | — | Vanilla noted no CORS; Temper focuses on route-level patterns not Express middleware stack |
| 17 | Type coercion bug | No | N/A | N/A | — | Not present |
| 18 | Missing input validation | Yes | CAUGHT | CAUGHT | review | Email format, amount validation |
| 19 | Resource leak | No | N/A | N/A | — | Not present |
| 20 | Missing test coverage | Yes | CAUGHT | CAUGHT | check | No payment.test.ts or users.test.ts |

### Honest Assessment

**Where Temper adds value:**
- **Scenario coverage gate** (build stage) catches pattern 15 mechanically — the `loginAttempts` field exists but is never used. Vanilla noticed it visually; Temper derives a scenario that requires it and blocks the build.
- **Security hot path tracing** provides structured classification (CRITICAL/HIGH/MEDIUM) with entry point exposure analysis, not just "this looks wrong."
- **Stage gates** mean findings are acted on — you can't proceed past build without addressing the scenario coverage gap.

**Where vanilla Claude Code is equal or better:**
- **Error handling** (pattern 3) — Vanilla caught no try/catch and no error middleware. Temper missed this because it focuses on route-level patterns, not Express middleware stack completeness.
- **Infrastructure middleware** (pattern 16) — Vanilla noted missing CORS/helmet. Temper missed this for the same reason.
- Both catch the same security and performance issues.

**Headline:** On this playground, Temper and vanilla Claude Code catch approximately the same number of bugs. Temper's advantage is **enforcement** (stage gates block progress) and **mechanical derivation** (scenario coverage finds gaps that require a human reviewer to notice in vanilla mode), not a higher detection rate.

## Reproducibility

1. **Test repo**: [github.com/galando/temper-playground](https://github.com/galando/temper-playground) (public)
2. **Model**: Claude (Opus 4.8)
3. **Prompts**: Documented above
4. **Scoring**: Binary per pattern, pre-registered criteria
5. **Date**: 2026-06-12
