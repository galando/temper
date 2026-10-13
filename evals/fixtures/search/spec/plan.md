# Plan: search notes by title

## Approach
Add `search_notes(conn, term)` to `notes.py`: one SELECT on the title with LIKE, ordered by id.

## Files to Modify
| File | Change |
|---|---|
| `notes.py` | add search_notes |
| `tests/test_search.py` | new: one test per scenario |

## Cross-Repo Search
- not available: a single repository fixture

## Blast Radius
- New function; open_db and add_note do not change.
