# Dev.to: How Temper Catches the Bugs AI Coding Assistants Miss

**Title:** How Temper Catches the Bugs AI Coding Assistants Miss

**Tags:** ai, claude, codequality, testing

---

AI coding assistants write code fast. But "fast" without "right" creates bugs that are hard to catch because the code *looks* correct. Tests pass. Linting is clean. But the edge case was never implemented, or the feature solves the wrong problem, or the architecture is over-engineered for what's needed.

I built Temper — an open-source plugin for Claude Code — to address these structural failure patterns. This article explains the methodology behind it.

## The Three Failure Patterns

After months of using AI coding assistants, I noticed three recurring patterns:

1. **Missing behaviors** — AI builds the happy path, skips edge cases. Rate limiting? Error recovery? Never implemented.
2. **Wrong problem solved** — Feature works perfectly, but nobody asked for it. All tests pass, wrong thing built.
3. **Over-engineering** — AI creates factories, strategies, and abstractions for something used exactly once.

These aren't sloppiness. They're structural. "Be more careful" doesn't fix them. You need structural mechanisms.

## Intent-Driven Development (IDD)

The first question: **Did we solve the right problem?**

IDD captures the *why* behind a feature. Not "add a password reset endpoint" but "users should be able to reset their password without contacting support, completing the flow in under 2 minutes."

Each success criterion gets a **validate type**:

| Type | How it's checked |
|------|-----------------|
| `scenario` | Test passes or doesn't |
| `code` | Code exists or doesn't |
| `metric` | Post-deploy monitoring |
| `manual` | Human review |

With validate types, intent validation is mechanical — not "the AI thinks it looks good."

## BDD Before Architecture

The second question: **Does it do the right things?**

The key design decision in Temper: **scenarios are derived before the architecture exists.**

```
1. Blast radius analysis → identifies affected files and risk areas
2. Scenario derivation → behaviors from requirements + blast radius
3. Architecture → file list follows from scenarios
```

Not the other way around. This prevents the AI from planning 15 files and then writing scenarios that justify them.

Every file must justify its existence by tracing to a scenario. Infrastructure files (migrations, config) must state what they support. Untraced files are flagged.

## The Scenario Coverage Gate

The third question: **Does the code work?**

After all tasks complete, Temper checks: does every scenario have a passing test?

If a scenario has no test → build writes the test → test fails (proves it tests something) → build implements the feature → test passes.

This is how the rate-limiting example works:

```gherkin
Scenario: Rate limiting on reset requests
  Given a user has requested 3 resets in 10 minutes
  When they request another reset
  Then the request is rejected with 429
```

AI built password reset. All tests pass. But the scenario coverage gate caught the gap: no test for rate limiting. Build wrote the test. Test failed. Build implemented rate limiting. Test passed.

Without the coverage gate, rate limiting would never have been implemented.

## Stage Gates and Feedback Loops

Temper runs as a pipeline with gates at each stage:

```
/temper "add password reset"
  → Plan → Gate
  → Build → Gate
  → Review → Gate
  → Check → Gate → Commit
```

At each gate, you approve, edit, or stop. Feedback loops between stages: if Review finds issues, it can loop back to Build with the findings. Circuit breakers prevent infinite loops (same issue twice = stop).

## Evidence Labels

Every finding carries a label:

- **[PROVEN]** — Tool output (MCP server, test runner, SAST scan). Mechanically verified.
- **[HEURISTIC]** — Grep-based analysis. Best-effort.
- **[SEMANTIC]** — AI judgment. Inherently subjective.

This lets you weight findings by evidence quality, not just severity.

## Try It

```bash
/plugin marketplace add galando/temper
/plugin install temper
/temper "add password reset"
```

Or try the playground: [github.com/galando/temper-playground](https://github.com/galando/temper-playground)

Open source, MIT licensed: [github.com/galando/temper](https://github.com/galando/temper)
