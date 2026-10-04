# Intent: Password reset tokens

**Author:** Demo User <demo@example.com>
**Status:** accepted
**Created:** 2026-10-03
**Ticket:** none
**Reviewer:** Demo User <demo@example.com> (Engineer)
**Complexity:** simple

---

## Intent (IDD)

### Problem

A user who forgot their password has no way back in. The user store in `src/users.js`
only supports login. Desired: a one time reset token that expires after one hour.

### Success Criteria

- [ ] AC-01 [required]: A reset token is generated for a known user and works once (source: request)
  Why: a forgotten password must be recoverable without support
  Validate: code - `npm test` covers token creation and single use
- [ ] AC-02 [required]: A token older than one hour is refused (source: request)
  Why: a leaked old token must not open an account
  Validate: code - `npm test` covers expiry

### Constraints

- No new dependencies (proposed)

### Scope and Non-goals

- In scope: `src/users.js` and its tests
- Out of scope: sending email, a web form, rate limiting
- Must keep working: the three existing tests

### Target Users

- Account owner: requests a reset token, then uses it once to set a new password

### Open Questions

- Deferred: token format; consequence: none for the tests; why work can proceed: any random string works; needed by: release.

### Decisions

- none

---

## Scenarios (BDD)

```gherkin
Scenario: A known user gets a token that works once
  Given a user "ann@example.com" exists
  When a reset token is requested for "ann@example.com"
  And the token is used twice
  Then the first use succeeds and the second use is refused
```

```gherkin
Scenario: An old token is refused
  Given a reset token made more than one hour ago
  When the token is used
  Then the use is refused
```

## Scenario Coverage Checklist

- AC-01 is covered by the first scenario.
- AC-02 is covered by the second scenario.

## Source Traceability

### Context Sources

- none: description only, nothing linked
