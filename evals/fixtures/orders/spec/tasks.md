# Tasks: orders

**Integration:** `python3 -m unittest discover -s tests -t .`

## Group G1: Order lookup
**Depends:** none
**Validate:** `python3 -m unittest discover -s tests -t .`
**Context:**
Standard library only. Tests use unittest.

### Task 1: Look up an order and its total
**File:** `orders.py`
**File:** `tests/test_orders.py`
**Depends:** none
**Test:** `python3 -m unittest discover -s tests -t .`
**Cases:**
- the total of an existing order
- a missing order raises ValueError
- [x] Look up an order and its total
