**Author:** Fixture Author <fixture@example.com>
**Status:** accepted
**Created:** 2026-10-13
**Reviewer:** Fixture Reviewer <reviewer@example.com>
**Complexity:** simple

## Problem
Support staff need the total of an order when a customer calls with its id. Today they
read it from the raw list by hand.

### Success Criteria
- [ ] AC-01 [required]: the total in cents of an existing order can be read by its id
  Why: support answers the call without reading the raw list
  Validate: scenario — traced to a test below
- [ ] AC-02 [required]: an id that no order has raises a clear error, a ValueError
  Why: a wrong id must not look like a total of zero
  Validate: scenario — traced to a test below

### Constraints
- standard library only

### Scope and Non-goals
- In scope: find_order and order_total in orders.py
- Out of scope: storage, an HTTP layer
- Must keep working: the existing Order tests

### Target Users
- support staff: types an order id → reads its total

### Open Questions

### Decisions

## Scenarios (BDD)
#### Happy Path
```gherkin
Scenario: Look up the total of an existing order
  Given an order "b" with a total of 700 cents in the list
  When order_total is called with "b"
  Then it returns 700
  Note: unit
  Covers: AC-01
```
#### Error Path
```gherkin
Scenario: Look up an order that does not exist
  Given no order with the id "zzz"
  When order_total is called with "zzz"
  Then a ValueError is raised
  Note: unit
  Covers: AC-02
```

## Scenario Coverage Checklist

## Source Traceability
### Context Sources
- none: description only — nothing linked
