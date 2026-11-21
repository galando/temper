# Methodology: IDD + BDD + TDD

Temper combines three development methodologies in a single contract file called `intent.md`. Each layer answers a different question and is enforced at a different stage of the pipeline.

---

## IDD: Intent-Driven Development

**Question:** Did we solve the problem?
**When:** Defined in the Intent stage (the first gate, before Plan), validated during Review

IDD captures the *why* behind a feature. Not "add a password reset endpoint" but "users should be able to reset their password without contacting support, completing the flow in under 2 minutes."

The Intent section of `intent.md` contains:

- **Problem** — What problem are we solving? For whom?
- **Success Criteria** — Measurable outcomes, each with a **`Validate:` type** that tells review *how* to check it
- **Constraints** — Technical or business limitations

### Validate Types

Each success criterion gets a validation type. This is what makes IDD mechanical instead of subjective:

| Type | What It Means | How Review Checks It | Example |
|------|--------------|---------------------|---------|
| `scenario` | Criterion is satisfied when a linked BDD scenario's test passes | Finds the test, runs it, checks PASS | "Users can reset password" → linked to scenario "Successful password reset" |
| `code` | Criterion is satisfied when specific code exists | The CLI runs the command in backticks on the Validate line, at Build and at Check, and reads its exit code | "POST /api/reset endpoint exists" → `grep -q "POST /api/reset" src/routes.ts` |
| `metric` | Criterion is satisfied when a measured value is inside its bound | The CLI runs the command in backticks on the Validate line, at Build and at Check, and reads its exit code | "The bundle stays under 200 KB" → `test "$(wc -c < dist/app.js)" -lt 200000` |
| `manual` | Requires human judgment, or a value that can be read only after release | The person confirms it at the Check question | "Reset flow feels intuitive" → UX review needed; "Support tickets decrease 30%" → read after release |

A `code` or `metric` criterion with no command in backticks fails the Intent gate; one that can only be checked by a person is `manual`.

**Why this matters:** Without validate types, "intent validation" means the AI reads your success criteria and subjectively judges "yeah, this looks met." With validate types, most criteria are mechanically verified: a test passes or it does not, a command exits 0 or it does not. Only `manual` requires judgment, and it is the person's.

### Intent Validation in Review

When Review runs, it produces:

```
Intent Validation (IDD): 3/5 (4 mechanical, 1 for the person)
  Problem: Users unable to reset passwords without support

  [x] Users can reset password without support
      validate: scenario -> test_successful_reset PASS
  [x] Reset endpoint exists at POST /api/reset
      validate: code -> grep -q "POST /api/reset" src/routes.ts exit 0 (run by the CLI)
  [x] Rate limiting prevents abuse
      validate: scenario -> test_rate_limiting PASS
  [ ] The bundle stays under 200 KB
      validate: metric -> test "$(wc -c < dist/app.js)" -lt 200000 exit 1 (run by the CLI)
  [ ] Reset flow completes in under 2 minutes
      validate: manual -> the person confirms it at the Check question

  Confidence: 3/4 mechanically verified
```

---

## BDD: Behavior-Driven Development

**Question:** Does it do the right things?
**When:** Scenarios derived during Plan (before architecture), tested during Build, enforced at Check

BDD in Temper isn't an afterthought — **scenarios are derived before the architecture exists.** This is the key design decision:

```
1. Blast radius analysis     → identifies affected files and risk areas
2. Scenario derivation       → behaviors from requirements + blast radius
3. Architecture from scenarios → file list justified by scenarios
```

Not the other way around. This prevents the AI from planning 15 files and then writing scenarios that justify them.

### Where Scenarios Come From

| Source | Becomes |
|--------|---------|
| Feature description | Happy path scenarios |
| Acceptance criteria (Jira/GitHub issue) | Validation scenarios |
| Blast radius: risk areas | Edge case and error scenarios |
| Blast radius: affected consumers | Regression guard scenarios |

### File-to-Scenario Traceability

Every file in the plan must justify its existence. If the AI plans a file that no scenario needs and isn't infrastructure — that file shouldn't exist.

### What Plan writes (9.8.5)

Plan writes only what a script, a gate row or a later agent reads. At the simple tier that is `tasks.md` and the
scenarios of `intent.md`; above it a short `plan.md` as well, with a Context Map and a Blast Radius. Each scenario is
one fenced `gherkin` block of four lines: its name, one `Then` line, `Covers:` and `Test:`. The task that declares the
file a scenario's `Test:` command runs owes that scenario; no `Traced to:` line is written. The CLI bounds the simple
tier: one group, at most 3 production files, a risk below H.

### Scenario Coverage Gate

The Check gate holds the scenario coverage row (`scenarios traced to tests`):

```
Scenario Coverage: 5/5
  [x] Successful password reset     -> test_successful_reset (PASS)
  [x] Expired token rejected        -> test_expired_token (PASS)
  [x] Rate limiting enforced        -> test_rate_limiting (PASS)
  [x] Invalid email format          -> test_invalid_email (PASS)
  [x] Non-existent user handled     -> test_nonexistent_user (PASS)
```

If any scenario has no passing test, the Check gate fails, and the person can loop back to Build.

### A reader with no context checks the plan (9.7.6)

Each Build task runs on a small model that sees only its own task block. A plan that leaves a decision open (an error
status, a field name, a file to register the code in) is a decision that model guesses, and its own test encodes the same
guess, so TDD cannot catch it. The fresh review (`agents/plan-review.md`) reads the plan as that builder will, before
anyone writes code, and the gate counts what it records: the CLI marks its launch, so only rows recorded after it count,
and an edit of the plan after the review makes it stale. The idea comes from Google's Elephant Goldfish Model.

---

## TDD: Test-Driven Development

**Question:** Does the code work?
**When:** During Build, per scenario

TDD in Temper is **scenario-driven**. Instead of the AI deciding what to test, tests are derived from BDD scenarios:

| BDD Scenario | Becomes TDD |
|-------------|-------------|
| `Then` (expected outcome) | Assertions |
| the Cases of the task that owns it | Further cases of the test |
| `Test:` | The command that runs the test |
| Scenario name | Test name |

The cycle per scenario:

1. **RED** — Write test mapped to scenario name. Must fail (proves the test actually tests something).
2. **GREEN** — Write minimal code to make the test pass. Nothing more.
3. **REFACTOR** — Clean up only if safe and obvious. All tests must still pass.

### How TDD and BDD Work Together

- **intent.md drives WHAT to test** — scenarios define the test cases
- **TDD pack drives HOW to test** — RED-GREEN-REFACTOR discipline, naming conventions, test structure
- When only TDD pack is active: freestyle test-first development
- When neither is active: no enforced test-first

---

## Finding Examples

### Missing Edge Case

AI built password reset. All tests pass. But intent.md had:

```gherkin
Scenario: Rate limiting on reset requests
  Then a fourth reset request within 10 minutes is rejected with 429
  Covers: AC-03
  Test: pytest tests/test_reset.py::test_rate_limiting -q
```

The scenario coverage row at Check caught it: no test for rate limiting. The loop back to Build wrote the test. Test failed. Build implemented rate limiting. Test passed.

### Over-Engineering Caught by Traceability

AI planned `UserValidatorFactory`, `ValidationStrategy` interface, and `ValidationChain` — for a single validation rule. File-to-scenario traceability flagged it: only one scenario needed validation, and it mapped to a single function. Three files became one.

### Wrong Problem Solved

Success criterion: "Users can reset password without contacting support." AI built it correctly but also added an admin-only reset endpoint nobody asked for. The untraced file was flagged and removed.
