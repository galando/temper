# Evidence: Benchmark Results

## Overview

Benchmark comparing vanilla Claude Code review vs the Temper pipeline against the
[temper-playground](https://github.com/galando/temper-playground) Express+TS app.
The playground has 4 intentional flaws plus additional issues found during review.

Two runs are documented here: the **current re-run** (2026-07, Temper v6.0.1,
claude-fable-5) and the **historical run** (2026-06, Temper v5.2.1, Opus 4.8).
Read the current one first — it corrects two methodology problems in the original
setup and reaches a materially different conclusion.

## Bug Pattern Catalog

Shared by both runs. "Present" reflects playground HEAD `d5c1292`.

| # | Pattern | Description | Present in Playground |
|---|---------|-------------|----------------------|
| 1 | Missing rate limiting | Login endpoint has no brute-force protection | Yes |
| 2 | SQL injection risk | User input flows into query logic without sanitization | Comment-only (see 2026-07 re-run) |
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

## 2026-07 Re-run — Temper v6.0.1, claude-fable-5

### Two methodology problems found in the original setup

1. **The playground labels its own flaws.** At playground HEAD (`d5c1292`), every
   seeded bug is marked in-source with `// INTENTIONAL FLAW` comments (often with
   multi-line explanations of the correct fix), the README says "each flaw is
   marked with `// INTENTIONAL FLAW`", and `CLAUDE.md` lists all four flaws for
   any agent that loads it. Any reviewer — tool or vanilla — reads the answers off
   the page. A run against the annotated repo measures reading comprehension, not
   detection.
2. **The SQL-injection pattern (#2) exists only in comments.** The executable code
   filters an in-memory array with `String(category)` — there is no query
   construction and nothing injectable. The "vulnerability" is a comment describing
   what the code *would* do with a real DB. With hint comments removed, pattern #2
   is undetectable because it is not present.

### Procedure

- **Conditions:** *annotated* (playground as-is) and *sanitized* (byte-identical
  copy with every flaw-hint comment removed, plus neutral README/CLAUDE.md; no
  code changed).
- **Arms per condition:** (A) vanilla — a clean-context agent prompted only to
  review the app exhaustively; (B) Temper — a clean-context agent executing the
  v6.0.1 review-stage methodology (`commands/review.md` + `reference/review.md`)
  with the quality, security, performance, tdd, and node-express packs. Neither
  arm had access to the bug catalog or this document.
- **Model:** claude-fable-5, both arms, single run each (2026-07-11).
- **Scoring:** same pre-registered per-pattern criteria as the historical run,
  scored against the 20-pattern catalog above.

### Results

| Condition | Detectable patterns | Vanilla | Temper v6.0.1 |
|-----------|--------------------|---------|----------------|
| Annotated (flaws labeled in source) | 12 | 12/12 | 12/12 |
| Sanitized (all hints removed) | 11 (SQLi #2 is comment-only) | **11/11** | **11/11** |

**Detection parity.** The v5.2.1 result ("Temper catches 4 bugs vanilla misses")
did **not** reproduce: on a current-generation model, a plain exhaustive vanilla
review caught every catalog pattern present in the code — including error
middleware, CORS/helmet, the `nextOrderId++` race, and the dead `loginAttempts`
field, all of which vanilla missed or only partially caught in 2026-06. The raw
detection gap this benchmark was built to demonstrate has been closed by base-model
improvement.

### Where the runs actually differed

Detection count is no longer the differentiator on this playground. What the
Temper arm produced that the vanilla arm structurally does not:

| Capability | Vanilla arm | Temper arm |
|------------|-------------|------------|
| Ship/no-ship decision | None — flat findings list | **Gate verdict: ❌ BLOCKED** (`block-on: [critical]`, 5 criticals named) |
| Coverage quantification | "Tests are fake" (prose) | **Coverage gate: FAIL, 0% effective vs 80% threshold**, per-behavior gap table |
| Confidence discipline | None | Per-finding scores, 0.7 threshold applied, below-threshold findings quarantined but disclosed |
| Rule traceability | None | Every finding tied to a pack rule (BLOCK/WARN tier) |
| Config integrity | Out of scope | Caught `stack: react-ts` misdeclaration in the playground's own `temper.config` |
| Prerequisite discipline | Reviewed anyway | Flagged "tests must pass before review" violation before proceeding |
| Severity calibration | Plaintext passwords = critical, rest ad hoc | Unauthenticated-reachability escalation rule applied consistently (4 auth-bypass criticals) |

Both arms independently found the same broken-build defect (missing `supertest`
dependency makes the suite unrunnable) and the same refund state-machine hole
(refunding `pending` orders) — neither is in the 20-pattern catalog.

### Honest assessment (2026-07)

- **Detection-rate claims vs vanilla should be retired for current models.** On a
  300-line playground, claude-fable-5 finds everything with a one-line prompt.
  The 2026-06 numbers below remain true for their date and model but no longer
  describe the present.
- **Temper's measured value moved up the stack:** deterministic gating (a BLOCKED
  verdict a CI pipeline can act on), quantified coverage-gate failure, confidence
  filtering, and rule-traceable findings — consistency and enforcement rather than
  raw recall. Larger, unlabeled codebases are where a detection delta may still
  exist; this playground can no longer show one.
- **The playground needs rework to stay a meaningful benchmark:** remove the
  in-source flaw labels (or maintain a sanitized branch), replace the
  comment-only SQLi with a real injectable code path (e.g. actual query-string
  assembly), and grow beyond 300 lines so exhaustive single-pass review stops
  being trivial.

### Limitations

Single run per arm; both arms used the same model; arms ran as fresh-context
subagents rather than interactive sessions; scoring was performed by the session
that prepared the sanitized copy (not blind). Directionally robust — parity at
11/11 vs 11/11 leaves no room for scoring bias to manufacture a gap — but the
per-finding details should be treated as one sample.

---

## Historical: v5.2.1 benchmark (2026-06-12, Opus 4.8)

> Superseded by the 2026-07 re-run above. Preserved as recorded; the runs below
> were performed against the annotated playground (flaw-label contamination was
> not yet recognized as a methodology problem), and pattern #2 was scored as
> present.

#
## What Changed in v5.2.1

Three new detection capabilities added to close the benchmark gaps:

1. **Middleware stack completeness** — Review now checks for error middleware, CORS, helmet in the app entry point (security hot path step 5)
2. **Race condition detection** — Performance pack flags non-atomic mutations on shared state in concurrent contexts
3. **MIDDLEWARE risk signal** — Diff fingerprint now flags middleware-related changes for elevated scrutiny

#
## Test Procedure

#
### Setup

1. Repository: [galando/temper-playground](https://github.com/galando/temper-playground) (public)
2. Stack: Express + TypeScript + Jest
3. 4 intentional flaws marked with `// INTENTIONAL FLAW` comments
4. Incomplete test suites with missing assertions

#
### Run A — Vanilla Claude Code

1. Fresh Claude Code session (no Temper)
2. Prompt: "Review the codebase for bugs and issues"
3. Recorded findings against 20 patterns

#
### Run B — Temper Pipeline (v5.2.1)

1. Temper installed, configured per playground's `.claude/temper.config`
2. Simulated `/temper "add search endpoint with security"`
3. Recorded findings per stage (plan, build, review, check)

#
### Scoring

| Result | Meaning |
|--------|---------|
| **Caught** | Bug detected and reported with correct description |
| **Partial** | Bug area flagged but specific issue not identified |
| **Missed** | Bug not mentioned at all |
| **N/A** | Pattern not present in the codebase |

#
## Results

#
### Detection Rate Summary

| Category | Patterns | Vanilla Caught | Temper Caught | Delta |
|----------|----------|---------------|--------------|-------|
| Security (1,2,5) | 3 | 3 | 3 | 0 |
| Error Handling (3,15) | 2 | 1 | 2 | **+1** |
| Performance (7,11) | 2 | 2 | 2 | 0 |
| Code Quality (9,18,20) | 3 | 1 | 2 | +1 |
| Test Coverage (14) | 1 | 1 | 1 | 0 |
| Infrastructure (16) | 1 | 0 | **1** | **+1** |
| **Total (present)** | **12** | **8** | **12** | **+4** |
| Not present | 8 | — | — | — |

#
### Per-Pattern Results

| # | Pattern | Present | Vanilla | Temper | Temper Stage | Notes |
|---|---------|---------|---------|--------|-------------|-------|
| 1 | Missing rate limiting | Yes | CAUGHT | CAUGHT | review + build | Security hot path + scenario coverage gate |
| 2 | SQL injection risk | Yes | CAUGHT | CAUGHT | review | Security hot path traces user input flow |
| 3 | Missing error handling | Yes | CAUGHT | **CAUGHT** | **review** | **v5.2.1: Middleware stack completeness check finds no error middleware** |
| 4 | Over-engineering | No | N/A | N/A | — | Code is minimal |
| 5 | Missing auth check | Yes | CAUGHT | CAUGHT | review | Security hot path on payment endpoint |
| 6 | N+1 query | No | N/A | N/A | — | Not present |
| 7 | Missing pagination | Yes | CAUGHT | CAUGHT | review | Performance pattern detection |
| 8 | Hardcoded secrets | No | N/A | N/A | — | Not present |
| 9 | Missing type check | Yes | PARTIAL | CAUGHT | review | Input validation detection |
| 10 | Wrong error code | No | N/A | N/A | — | Not present |
| 11 | Race condition | Yes | CAUGHT | **CAUGHT** | **review** | **v5.2.1: Race condition detection flags `nextOrderId++` as non-atomic** |
| 12 | Missing wiring | No | N/A | N/A | — | Routers properly wired |
| 13 | Breaking API change | No | N/A | N/A | — | Not present |
| 14 | Missing edge case tests | Yes | CAUGHT | CAUGHT | check | Both identify stub tests |
| 15 | Unused field (loginAttempts) | Yes | PARTIAL | CAUGHT | build | Scenario coverage gate derives account lockout scenario |
| 16 | Missing CORS/security middleware | Yes | PARTIAL | **CAUGHT** | **review** | **v5.2.1: Middleware stack completeness check finds no cors/helmet** |
| 17 | Type coercion bug | No | N/A | N/A | — | Not present |
| 18 | Missing input validation | Yes | CAUGHT | CAUGHT | review | Email format, amount validation |
| 19 | Resource leak | No | N/A | N/A | — | Not present |
| 20 | Missing test coverage | Yes | CAUGHT | CAUGHT | check | No payment.test.ts or users.test.ts |

#
### What Temper Catches That Vanilla Misses

| # | Pattern | How Temper Catches It |
|---|---------|----------------------|
| 3 | Missing error handling | Middleware stack completeness check reads app entry point, flags no error middleware (HIGH) |
| 11 | Race condition | Race condition detection finds `nextOrderId++` as non-atomic mutation on shared state in concurrent context (HIGH) |
| 15 | Unused loginAttempts field | Scenario coverage gate derives "Account locks after N failures" scenario mechanically — vanilla only noticed it visually |
| 16 | Missing CORS/security middleware | Middleware stack completeness check flags no cors() or helmet() in Express app setup (MEDIUM) |

#
### What Vanilla Catches That Temper Misses

| # | Pattern | Why Temper Misses It |
|---|---------|---------------------|
| — | _None_ | **v5.2.1 closes all gaps from v5.2.0 benchmark** |

#
### Honest Assessment

**v5.2.0** (previous): Temper tied with vanilla Claude Code at 8/12 patterns. Vanilla caught 2 things Temper missed (error middleware, CORS infrastructure). Temper's only advantage was enforcement via stage gates.

**v5.2.1** (current): Temper catches **12/12** present patterns vs vanilla's **8/12**. The three new detection capabilities (middleware stack, race conditions, enhanced security checks) close the gaps and push Temper ahead. Vanilla still catches patterns 3 and 16 at PARTIAL level but Temper catches them at CAUGHT level with specific file:line references.

Temper misses nothing that vanilla catches. **Every pattern present in the codebase is detected.**

**Temper catches 4 bugs that vanilla misses.** The advantage comes from structured methodology (scenario coverage gates, middleware stack checks, race condition rules) rather than raw intelligence — which is the point.

#
## Reproducibility

1. **Test repo**: [github.com/galando/temper-playground](https://github.com/galando/temper-playground) (public)
2. **Model**: Claude (Opus 4.8)
3. **Temper version**: 5.2.1
4. **Prompts**: Documented above
5. **Scoring**: Binary per pattern, pre-registered criteria
6. **Date**: 2026-06-12
