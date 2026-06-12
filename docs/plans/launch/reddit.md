# Reddit: r/ClaudeAI Post

**Title:** Temper — open-source quality gates for Claude Code (catches the bugs AI skips)

**Body:**

Been using Claude Code for a while and kept hitting the same issue: AI writes clean code that works on the happy path, but misses edge cases, over-engineers simple things, and sometimes solves the wrong problem entirely.

Built Temper as a Claude Code plugin that adds structured quality gates. It's not another linter — it enforces intent validation, behavior-driven testing, and security analysis at every stage.

Here's what it actually catches:

**The rate-limiting bug:** AI built password reset. All tests pass. But Temper's scenario coverage gate found the gap: no test for rate limiting. Build wrote the test → test failed → build implemented rate limiting → test passed. Without the gate, rate limiting would never have been implemented.

**Over-engineering:** AI planned `UserValidatorFactory`, `ValidationStrategy`, and `ValidationChain` for a single validation rule. Temper's file-to-scenario traceability flagged it — one scenario, one function needed. Three files became zero.

**How it works:**

```
/temper "add password reset"
```

One command runs the full pipeline: plan → build → review → check. At each stage you get a gate — approve, edit, or stop.

The key idea: BDD scenarios are derived *before* architecture, not after. The file plan follows from what the system must do. This prevents over-engineering structurally.

Also integrates with open-code-review (Alibaba's external review engine) for an extra layer of defect detection, and supports MCP tools like code-review-graph and semgrep for mechanically verified findings.

Evidence: [docs/evidence/](https://github.com/galando/temper/tree/main/docs/evidence)

Install:
```
/plugin marketplace add galando/temper
/plugin install temper
```

Open source, MIT licensed. Feedback welcome.

---

**Cross-post note:** Also posted to r/ExperiencedDevs with a different angle focusing on the evidence/metrics.
