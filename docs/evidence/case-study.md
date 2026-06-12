# Evidence: Dogfooding Case Study

## How Temper Uses Temper

Temper is developed using its own pipeline. Every feature goes through `/temper` — plan, build, review, check. This is the most honest evidence we can offer: real bugs caught during Temper's own development.

## Methodology

Bugs documented here were caught by Temper's gates during normal development — not seeded or constructed. Each entry includes:
- The feature being built
- What the gate caught
- The fix applied
- The commit (when available)

---

## Case 001: Missing Stage Gate in Unified Command

**Feature:** Unified `/temper` command (v2.0.0)
**Caught by:** `/temper:review` — intent validation

**What happened:** The unified command pipeline ran stages sequentially but the review stage never validated that the build stage's output matched the plan's intent. The scenario "Plan summary shown to user" existed in intent.md but no test verified the summary was displayed.

**Fix:** Added a test assertion verifying the plan summary format matches the specification, then added the display logic to the orchestrator.

**Lesson:** Even pipeline infrastructure needs scenario coverage. The scenario was in intent.md but the test gap wasn't caught until review.

---

## Case 002: Over-Engineering in Pack Discovery

**Feature:** Three-tier pack resolution (v2.3.0)
**Caught by:** `/temper:plan` — file-to-scenario traceability

**What happened:** The plan included `PackResolver`, `PackCache`, `PackValidator`, and `PackLoader` — four classes for what amounts to "check three directories for a rules.md file." File-to-scenario traceability flagged it: only one scenario needed pack resolution, and it mapped to a single function.

**Fix:** Consolidated to one `resolvePack(name)` function. Three files became zero (the function lives in the existing stage runner).

**Lesson:** Traceability catches over-engineering that code review misses because the code itself is well-written — it's just unnecessary.

---

## Case 003: Context Clearing Theater

**Feature:** Stage gate isolation (v2.4.0)
**Caught by:** `/temper:review` — semantic intent verification

**What happened:** The plan claimed stages run with "clean context" but the implementation used a self-directed prompt ("CLEAR ALL CONTEXT") rather than actual isolation. The semantic verification layer in review caught this: the intent said "isolated" but the implementation was "instructed to forget."

**Fix:** Rewrote to use Agent subprocesses (actual separate invocations) instead of self-directed clearing prompts. Each stage now starts with a genuinely clean context window.

**Lesson:** Semantic verification catches the gap between what the plan promises and what the code does, even when the code "works" by coincidence.

---

## Case 004: Feedback Loop Circuit Breaker

**Feature:** Review → Build feedback loops (v4.0.0)
**Caught by:** `/temper:check` — test gap analysis

**What happened:** The feedback loop implementation had no circuit breaker — if Review kept finding issues and Build kept fixing them, the loop would run forever. The test suite had a happy-path test but no test for "same issue found twice → stop."

**Fix:** Added circuit breaker logic: same file:line + same description appearing in two consecutive loops triggers human intervention. Added test for the circuit breaker.

**Lesson:** Feedback loops without termination conditions are infinite loops. Test gap analysis found the missing test, which revealed the missing production logic.

---

## Case 005: Gate Bypass in Nested Invocation

**Feature:** Nested subagent support (v5.1.0)
**Caught by:** `/temper:review` — security hot path analysis

**What happened:** When a nested agent returned an error, the orchestrator's error handling skipped the stage gate and proceeded to the next stage. This meant a failed planning agent could silently skip to build. Security hot path analysis flagged the orchestrator as CRITICAL (it's the entry point for all pipeline execution).

**Fix:** Added explicit gate enforcement after every agent return, regardless of success/failure status. Failed agents now show a gate with "retry" and "abort" options.

**Lesson:** Security hot path analysis catches control flow issues in critical paths, not just traditional security vulnerabilities.

---

## Metrics Summary

| Metric | Value |
|--------|-------|
| Features shipped using `/temper` | All (100%) |
| Bugs caught by Temper gates | 5+ documented |
| Bugs shipped to production | 0 (caught before commit) |
| Average scenarios per feature | 8-13 |
| Average test coverage | 85%+ |
| Most common catch stage | `/temper:review` (3/5 cases) |

---

## Reproducibility

The commit history for Temper itself serves as reproducibility evidence. Each case above can be traced to:
- The intent.md for that feature (in `.temper/specs/`)
- The review or check output that flagged the issue
- The fix commit in git history
