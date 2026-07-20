# Intent: Password Reset

## Problem
Users who forget their password have no self-service way to regain access.

## Success Criteria
- A user can request a password reset by email and receive a time-limited token
- Reset requests are rate limited to prevent abuse

## Scenarios

Scenario: User requests a password reset
  Given a registered user with a valid email
  When they request a password reset
  Then a reset token is issued that expires in 15 minutes

Scenario: Rate limiting on reset requests
  Given a user has requested 3 resets in 10 minutes
  When they request another reset
  Then the request is rejected with 429
