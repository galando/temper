# Twitter/X Thread

**Tweet 1:**
AI writes code fast. But it skips edge cases, over-engineers simple things, and sometimes solves the wrong problem entirely.

I built Temper — an open-source Claude Code plugin that catches these structural failures.

Here's how it works:

[Thread]

**Tweet 2:**
The problem isn't sloppiness. It's structural.

- Missing behaviors (rate limiting? error recovery?)
- Wrong problem solved (tests pass, wrong thing built)
- Over-engineering (factories for single implementations)

"Be more careful" doesn't fix these. You need structural mechanisms.

**Tweet 3:**
Temper's approach: three methodologies in one contract file.

1. IDD — captures WHY you're building something, with mechanical validate types
2. BDD — derives scenarios BEFORE architecture (prevents over-engineering)
3. TDD — tests from scenarios, not from the AI's imagination

**Tweet 4:**
The key insight: scenarios are derived BEFORE the file plan exists.

Files must justify their existence by tracing to scenarios.

AI planned 3 classes for a single validation rule? Traceability flags it. Three files become one function.

**Tweet 5:**
The scenario coverage gate catches real bugs.

AI built password reset. All tests pass. But no test for rate limiting.

Gate catches the gap → writes the test → test fails → implements rate limiting → test passes.

Without the gate, rate limiting ships to production.

**Tweet 6:**
Every finding carries an evidence label:

🔬 [PROVEN] — tool-verified (MCP server, test runner)
📊 [HEURISTIC] — grep-based, best-effort
🧠 [SEMANTIC] — AI judgment

Weight findings by evidence quality, not just severity.

**Tweet 7:**
v5.2 integrates Alibaba's open-code-review as an external review engine.

Cross-validated findings get boosted confidence.

Also works with code-review-graph (AST dependency graphs) and semgrep (SAST scanning).

**Tweet 8:**
One command, full pipeline:

/temper "add password reset"

→ Plan (blast radius + scenarios)
→ Build (TDD + coverage gate)
→ Review (intent validation + security)
→ Check (stack validation)
→ Commit

Open source, MIT licensed:
github.com/galando/temper
