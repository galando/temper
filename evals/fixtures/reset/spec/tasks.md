# Tasks: reset

**Integration:** `python3 -m unittest discover -s tests -t .`

## Group G1: Reset requests
**Depends:** none
**Validate:** `python3 -m unittest discover -s tests -t .`
**Context:**
Standard library only. Tests use unittest. `now` is passed in.

### Task 1: Request a reset, with the hourly limit
**File:** `reset.py`
**File:** `tests/test_reset.py`
**Depends:** none
**Test:** `python3 -m unittest discover -s tests -t .`
**Cases:**
- a known email gets a token
- an unknown email gets None
- the fourth request in an hour raises TooManyRequests
- [x] Request a reset, with the hourly limit
