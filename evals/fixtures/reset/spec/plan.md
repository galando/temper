# Plan: password reset requests

## Approach
A new module `reset.py` with `request_reset(email, now)`. Tokens come from `secrets`. The
issued tokens are kept in memory by email, with the time each was issued, which also gives
the count for the limit of three requests per hour.

## Files to Modify
| File | Change |
|---|---|
| `reset.py` | new: request_reset and TooManyRequests |
| `tests/test_reset.py` | new: one test per scenario |

## Cross-Repo Search
- not available: a single repository fixture

## Blast Radius
- New module; accounts.py is read only.
