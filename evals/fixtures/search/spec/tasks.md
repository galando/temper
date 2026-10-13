# Tasks: search

**Integration:** `python3 -m unittest discover -s tests -t .`

## Group G1: Search
**Depends:** none
**Validate:** `python3 -m unittest discover -s tests -t .`
**Context:**
Standard library only (sqlite3). Tests use unittest.

### Task 1: Search notes by a word of the title
**File:** `notes.py`
**File:** `tests/test_search.py`
**Depends:** none
**Test:** `python3 -m unittest discover -s tests -t .`
**Cases:**
- a word of a title finds that note
- a word in no title finds nothing
- [x] Search notes by a word of the title
