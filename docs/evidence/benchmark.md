# Evidence: Benchmark Methodology

## Overview

This document describes the methodology for benchmarking Temper's ability to catch bugs that vanilla AI coding misses. The benchmark is designed to be **reproducible**, **honest**, and **pre-registered** (checklist written before running).

## Bug Pattern Catalog

The following bug patterns are intentionally introduced into a test repository. Each pattern maps to a specific Temper detection mechanism.

| # | Pattern | Description | Expected Detection Stage |
|---|---------|-------------|------------------------|
| 1 | Missing rate limiting | Endpoint has no rate limiting despite business requirement | `/temper:plan` (scenario derivation) |
| 2 | SQL injection | Unparameterized query with user input | `/temper:review` (security hot path) |
| 3 | Missing error handling | No try/catch around external API call | `/temper:build` (scenario coverage gate) |
| 4 | Over-engineering | Factory pattern for single implementation | `/temper:plan` (file-to-scenario traceability) |
| 5 | Missing auth check | Endpoint accessible without authentication | `/temper:review` (security hot path) |
| 6 | N+1 query | Loop with individual DB lookups | `/temper:review` (performance pack) |
| 7 | Missing pagination | Unbounded list endpoint | `/temper:review` (performance pack) |
| 8 | Hardcoded secrets | API key in source code | `/temper:check` (security pack) |
| 9 | Missing null check | No null validation on external input | `/temper:build` (scenario coverage gate) |
| 10 | Wrong error code | Returns 200 instead of 404 for missing resource | `/temper:review` (API design pack) |
| 11 | Race condition | Shared mutable state without synchronization | `/temper:review` (deterministic analysis) |
| 12 | Missing wiring | Service never registered in DI container | `/temper:check` (integration validation) |
| 13 | Breaking API change | Response field renamed without versioning | `/temper:review` (API diff) |
| 14 | Missing test for edge case | Boundary value not tested | `/temper:build` (test gap analysis) |
| 15 | Incorrect async handling | Promise chain without proper error propagation | `/temper:review` (code review) |
| 16 | Missing CORS headers | API endpoint missing CORS configuration | `/temper:check` (stack validation) |
| 17 | Type coercion bug | Loose equality comparison (`==` instead of `===`) | `/temper:review` (code review) |
| 18 | Missing input validation | No schema validation on request body | `/temper:build` (scenario coverage gate) |
| 19 | Resource leak | File handle or connection not closed | `/temper:review` (code review) |
| 20 | Incorrect logging | Sensitive data logged in plaintext | `/temper:review` (security pack) |

## Test Procedure

### Setup

1. Create a TypeScript + Express project (most common stack)
2. Introduce all 20 bug patterns into the codebase
3. Each bug is introduced as a separate commit for traceability

### Run A

**Vanilla Claude Code:**
1. Open fresh Claude Code session (no Temper)
2. Prompt: "Review the codebase for bugs and issues"
3. Record which bugs are found
4. Repeat 3 times with fresh sessions to account for variance

### Run B

**Temper:**
1. Install Temper
2. Run `/temper "add search and auth features"`
3. Record which bugs are caught at each stage
4. Repeat 3 times with fresh sessions

### Scoring

For each run, score each bug pattern as:

| Result | Meaning |
|--------|---------|
| **Caught** | Bug detected and reported with correct description |
| **Partial** | Bug area flagged but specific issue not identified |
| **Missed** | Bug not mentioned at all |
| **False Positive** | Non-existent bug reported |

### Pre-Registration Checklist

This checklist is committed **before** running any tests to prevent cherry-picking:

- [ ] All 20 bug patterns documented with exact file locations
- [ ] Expected detection stage recorded for each pattern
- [ ] Test repository URL recorded
- [ ] Model version recorded for both runs
- [ ] Scoring criteria defined (above)

## Results

> Results will be populated after running the benchmark. Honest reporting including losses — credibility comes from the misses being listed.

### Detection Rate Summary

| Category | Patterns | Caught | Partial | Missed | Rate |
|----------|----------|--------|---------|--------|------|
| Security | 5 | — | — | — | — |
| Error Handling | 4 | — | — | — | — |
| Performance | 2 | — | — | — | — |
| API Design | 2 | — | — | — | — |
| Code Quality | 4 | — | — | — | — |
| Integration | 3 | — | — | — | — |
| **Total** | **20** | — | — | — | — |

### Per-Pattern Results

| # | Pattern | Vanilla (avg of 3) | Temper (avg of 3) | Detection Stage |
|---|---------|--------------------|--------------------|----------------|
| 1 | Missing rate limiting | — | — | — |
| 2 | SQL injection | — | — | — |
| 3 | Missing error handling | — | — | — |
| 4 | Over-engineering | — | — | — |
| 5 | Missing auth check | — | — | — |
| 6 | N+1 query | — | — | — |
| 7 | Missing pagination | — | — | — |
| 8 | Hardcoded secrets | — | — | — |
| 9 | Missing null check | — | — | — |
| 10 | Wrong error code | — | — | — |
| 11 | Race condition | — | — | — |
| 12 | Missing wiring | — | — | — |
| 13 | Breaking API change | — | — | — |
| 14 | Missing edge case test | — | — | — |
| 15 | Incorrect async handling | — | — | — |
| 16 | Missing CORS headers | — | — | — |
| 17 | Type coercion bug | — | — | — |
| 18 | Missing input validation | — | — | — |
| 19 | Resource leak | — | — | — |
| 20 | Incorrect logging | — | — | — |

### Headline Metric

> _To be filled after benchmark completion._

**Temper catches X/20 bugs that vanilla Claude Code misses.**

## Reproducibility

Each benchmark run is reproducible:

1. **Test repo**: `github.com/galando/temper-playground` (public)
2. **Model**: Recorded per run
3. **Prompt**: Exact prompts recorded above
4. **Scoring**: Binary per pattern, pre-registered criteria
5. **Raw output**: Full session transcripts archived per run
