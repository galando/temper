# Intent: Order Lookup

## Problem
Support needs to look up an order's total by ID.

## Success Criteria
- Given an order ID, the total in cents can be retrieved
- A missing order ID raises a clear error

## Scenarios

Scenario: Look up an existing order's total
  Given an order exists in the order list
  When its ID is looked up
  Then the order's total in cents is returned

Scenario: Look up a missing order
  Given no order with the given ID exists
  When it is looked up
  Then a ValueError is raised
