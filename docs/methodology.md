# Methodology: IDD + BDD + TDD

Temper combines three development methodologies in a single contract file called `intent.md`. Each layer answers a different question and is enforced at a different stage of the pipeline.

---

## IDD: Intent-Driven Development

**Question:** Did we solve the problem?
**When:** Defined during `/temper:plan`, validated during `/temper:review`

IDD captures the *why* behind a feature. Not "add a password reset endpoint" but "users should be able to reset their password without contacting support, completing the flow in under 2 minutes."

The Intent section of `intent.md` contains:

- **Problem** — What problem are we solving? For whom?
- **Success Criteria** — Measurable outcomes, each with a **`Validate:` type** that tells review *how* to check it
- **Constraints** — Technical or business limitations
- **Target Users** — Who benefits

### Validate Types

Each success criterion gets a validation type. This is what makes IDD mechanical instead of subjective:

| Type | What It Means | How Review Checks It | Example |
|------|--------------|---------------------|---------|
| `scenario` | Criterion is satisfied when a linked BDD scenario's test passes | Finds the test, runs it, checks PASS | "Users can reset password" → linked to scenario "Successful password reset" |
| `code` | Criterion is satisfied when specific code exists | Greps the codebase for the pattern | "POST /api/reset endpoint exists" → greps for route definition |
| `metric` | Can't be verified before deployment | Flags for post-deploy monitoring | "Support tickets decrease 30%" → requires production data |
| `manual` | Requires human judgment | Flags for human review, non-blocking | "Reset flow feels intuitive" → UX review needed |

**Why this matters:** Without validate types, "intent validation" means the AI reads your success criteria and subjectively judges "yeah, this looks met." With validate types, most criteria are mechanically verified — a test passes or it doesn't, code exists or it doesn't. Only `metric` and `manual` require judgment.

### Intent Validation in Review

When `/temper:review` runs, it produces:

```
Intent Validation (IDD): 4/5 (3 mechanical, 1 deferred, 1 manual)
  Problem: Users unable to reset passwords without support

  [x] Users can reset password without support
      validate: scenario -> test_successful_reset PASS
  [x] Reset endpoint exists at POST /api/reset
      validate: code -> route found in AuthController.ts:23
  [x] Rate limiting prevents abuse
      validate: scenario -> test_rate_limiting PASS
  [ ] Support ticket volume decreases 30%
      validate: metric -> post-deploy monitoring required
  [ ] Reset flow completes in under 2 minutes
      validate: manual -> requires human review

  Confidence: 3/5 mechanically verified
```

---

## BDD: Behavior-Driven Development

**Question:** Does it do the right things?
**When:** Scenarios derived during `/temper:plan` (before architecture), enforced during `/temper:build`

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

### Scenario Coverage Gate

After all tasks complete, `/temper:build` runs the scenario coverage gate:

```
Scenario Coverage: 5/5
  [x] Successful password reset     -> test_successful_reset (PASS)
  [x] Expired token rejected        -> test_expired_token (PASS)
  [x] Rate limiting enforced        -> test_rate_limiting (PASS)
  [x] Invalid email format          -> test_invalid_email (PASS)
  [x] Non-existent user handled     -> test_nonexistent_user (PASS)
```

If any scenario has no passing test, build cannot proceed.

---

## TDD: Test-Driven Development

**Question:** Does the code work?
**When:** During `/temper:build`, per scenario

TDD in Temper is **scenario-driven**. Instead of the AI deciding what to test, tests are derived from BDD scenarios:

| BDD Scenario | Becomes TDD |
|-------------|-------------|
| `Given` (preconditions) | Test setup |
| `When` (action) | Method/endpoint call |
| `Then` (expected outcome) | Assertions |
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
  Given a user has requested 3 resets in 10 minutes
  When they request another reset
  Then the request is rejected with 429
  Note: unit
```

Scenario coverage gate caught it: no test for rate limiting. Build wrote the test. Test failed. Build implemented rate limiting. Test passed.

### Over-Engineering Caught by Traceability

AI planned `UserValidatorFactory`, `ValidationStrategy` interface, and `ValidationChain` — for a single validation rule. File-to-scenario traceability flagged it: only one scenario needed validation, and it mapped to a single function. Three files became one.

### Wrong Problem Solved

Success criterion: "Users can reset password without contacting support." AI built it correctly but also added an admin-only reset endpoint nobody asked for. The untraced file was flagged and removed.
