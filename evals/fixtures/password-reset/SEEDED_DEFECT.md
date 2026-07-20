# Seeded defect: missing rate limiting

**Stack:** node-express (minimal, no framework wiring needed for the eval)

**What's wrong:** `src/resetService.js` implements password-reset token issuance and
expiry, but has no rate limiting. `test/reset.test.js` covers the happy path and token
expiry, but has no test for the "3 resets in 10 minutes -> 429" scenario.
`.temper/specs/password-reset/intent.md` already states the success criterion ("Reset
requests are rate limited") and the Gherkin scenario — the gap is entirely in the
implementation and its test coverage, not in the spec.

**Which gate should catch it:** `/temper:check`'s scenario-coverage verification
(`reference/check.md`) — it reads each Gherkin scenario in `intent.md` and checks
whether a test exercises it. The "Rate limiting on reset requests" scenario has no
matching test, so Check should report it as `missing` in `scenario_verification`
and the pipeline should not report a clean bill of health.

**Pass condition for this fixture:** running `/temper:check` (or the Check stage of
`/temper`) against this fixture reports the rate-limiting scenario as uncovered — not
silently passed. See `evals/run-fixture.sh`.
