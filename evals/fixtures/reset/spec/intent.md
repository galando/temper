**Author:** Fixture Author <fixture@example.com>
**Status:** accepted
**Created:** 2026-10-13
**Reviewer:** Fixture Reviewer <reviewer@example.com>
**Complexity:** simple

## Problem
People who forget their password write to support. They need to ask for a reset link
themselves, without the service telling strangers which emails have an account and
without letting anyone flood an inbox with reset mails.

### Success Criteria
- [ ] AC-01 [required]: `request_reset(email, now)` in reset.py returns a new token for a known email
  Why: the person gets a link without writing to support
  Validate: scenario — traced to a test below
- [ ] AC-02 [required]: it returns None for an unknown email, with no error
  Why: a stranger cannot tell which emails have an account
  Validate: scenario — traced to a test below
- [ ] AC-03 [required]: a fourth request for the same email within one hour raises `TooManyRequests`; after the hour it is served again
  Why: nobody can flood an inbox with reset mails
  Validate: scenario — traced to a test below

### Constraints
- standard library only; `now` is passed in, in seconds

### Scope and Non-goals
- In scope: reset.py
- Out of scope: sending the mail, storing tokens across restarts
- Must keep working: the accounts tests

### Target Users
- account holder: asks for a reset → receives a link

### Open Questions

### Decisions

## Scenarios (BDD)
#### Happy Path
```gherkin
Scenario: Request a reset for a known email
  Given the account ana@example.com
  When request_reset is called for it
  Then a new token is returned
  Note: unit
  Covers: AC-01
```
#### Error Path
```gherkin
Scenario: Request a reset for an unknown email
  Given no account for zoe@example.com
  When request_reset is called for it
  Then None is returned and no error is raised
  Note: unit
  Covers: AC-02
```
```gherkin
Scenario: Too many reset requests in one hour
  Given three requests for ana@example.com in the last hour
  When a fourth request arrives
  Then TooManyRequests is raised
  And a request after the hour is served again
  Note: unit
  Covers: AC-03
```

## Scenario Coverage Checklist

## Source Traceability
### Context Sources
- none: description only — nothing linked
