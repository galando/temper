**Author:** Fixture Author <fixture@example.com>
**Status:** accepted
**Created:** 2026-10-13
**Reviewer:** Fixture Reviewer <reviewer@example.com>
**Complexity:** simple

## Problem
People with many notes cannot find one again. They need to search the titles by a word
they remember.

### Success Criteria
- [ ] AC-01 [required]: `search_notes(conn, term)` in notes.py returns the titles that contain the term, in id order
  Why: a person finds a note by a word of its title
  Validate: scenario — traced to a test below
- [ ] AC-02 [required]: a term that no title contains returns an empty list
  Why: no match is an answer, not an error
  Validate: scenario — traced to a test below

### Constraints
- standard library only (sqlite3)

### Scope and Non-goals
- In scope: search_notes in notes.py
- Out of scope: full text search of the body, ranking
- Must keep working: the notes tests

### Target Users
- note taker: types a word → sees the matching titles

### Open Questions

### Decisions

## Scenarios (BDD)
#### Happy Path
```gherkin
Scenario: Search by a word in the title
  Given the notes "Shopping list" and "Trip to Rome"
  When search_notes is called with "Rome"
  Then it returns ["Trip to Rome"]
  Note: unit
  Covers: AC-01
```
#### Error Path
```gherkin
Scenario: Search with no match
  Given the notes "Shopping list" and "Trip to Rome"
  When search_notes is called with "Paris"
  Then it returns an empty list
  Note: unit
  Covers: AC-02
```

## Scenario Coverage Checklist

## Source Traceability
### Context Sources
- none: description only — nothing linked
