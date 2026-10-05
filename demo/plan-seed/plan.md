# Plan: Password reset tokens

## Approach

Add two functions to the user store: one that makes a random token with an expiry time, and one
that uses a token once. Keep the store in memory, as it is now.

## Blast Radius

### Files to Modify

| File | Change | Why |
|---|---|---|
| `src/users.js` | Add `resetToken` and `useToken` | The user store owns the data |
| `test/users.test.js` | Add tests for single use and expiry | Proves AC-01 and AC-02 |

Nothing else calls the user store. The three existing tests stay as they are.

## Cross-Repo Search

- not available: no cross repo code search tool is connected, so the search ran in this repo only

## Scenarios

- A known user gets a token that works once (AC-01)
- An old token is refused (AC-02)
