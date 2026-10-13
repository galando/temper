# Plan: order lookup

## Approach
Add `find_order(orders, order_id)` and `order_total(orders, order_id)` to `orders.py`.
`order_total` raises `OrderNotFound`, a `ValueError`, for an unknown id.

## Files to Modify
| File | Change |
|---|---|
| `orders.py` | add find_order, order_total and OrderNotFound |
| `tests/test_orders.py` | tests for both scenarios |

## Cross-Repo Search
- not available: a single repository fixture

## Blast Radius
- Callers: none yet; the functions are new.
