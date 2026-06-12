# Show HN: Temper — quality gates for AI-generated code

**Title:** Show HN: Temper – quality gates for AI-generated code (now orchestrating Alibaba's open-code-review)

**Body:**

I built Temper because I kept seeing the same failure patterns in AI-generated code: missing edge cases, over-engineering, and solving the wrong problem. "Be careful" doesn't fix structural issues.

Temper is a Claude Code plugin that adds three layers of validation:

1. **IDD (Intent-Driven Development)** — Captures *why* you're building something, with mechanical validate types (scenario, code, metric, manual). Review checks if the intent was actually met.

2. **BDD before architecture** — Scenarios are derived *before* the file plan exists. Files must justify their existence by tracing to scenarios. This prevents the AI from planning 15 files and writing scenarios to justify them.

3. **Scenario coverage gate** — Every scenario must have a passing test before build completes. No test = build writes it = test fails = build implements the feature.

The architecture is a stage-gate pipeline:

```
/temper "add password reset"
  → Plan (blast radius + scenarios + architecture)
  → Gate: approve/edit/stop
  → Build (scenario-driven TDD, coverage gate)
  → Gate
  → Review (intent validation, security hot paths, diff fingerprint)
  → Gate
  → Check (stack validation, test execution)
  → Gate → commit
```

Each stage runs in an isolated Agent subprocess (genuine context clearing, not "please forget everything"). Feedback loops between stages with circuit breakers (same issue twice = stop).

v5.2 adds integration with Alibaba's open-code-review as an external review engine. Cross-validated findings get boosted confidence.

Evidence labels on every finding: [PROVEN] (tool-verified via MCP), [HEURISTIC] (grep-based), [SEMANTIC] (judgment), [OCR] (external engine).

Links:
- Repo: https://github.com/galando/temper
- Evidence: https://github.com/galando/temper/tree/main/docs/evidence
- Methodology: https://github.com/galando/temper/blob/main/docs/methodology.md

Happy to answer questions about the architecture, the stage-gate model, or why scenarios-before-architecture matters.
