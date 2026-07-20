# Seeded defect: hallucinated API

**Stack:** fastapi/python (minimal — no HTTP layer needed for the eval, just the module)

**What's wrong:** `app/orders.py`'s `find_order()` calls `orders.find(lambda o: ...)`.
Python `list` has no `.find()` method (that's a JavaScript `Array` method) — this raises
`AttributeError` unconditionally, on any call, empty list or not. `test/test_orders.py`
never calls `find_order()` or `order_total()` at all — it only tests the `Order`
dataclass — so `pytest` reports a fully green suite while the two functions that matter
are completely broken. Neither scenario in `intent.md` is actually verified by anything
that runs.

(An earlier version of this fixture had the test suite call `find_order([], ...)`,
assuming an empty list wouldn't trigger the `AttributeError`. That's wrong — Python
raises `AttributeError` the instant a nonexistent method is referenced, regardless of
the list's contents. Verified by actually running `pytest` against this fixture, not
just written and assumed correct.)

**Which gate should catch it:** `/temper:review`'s defect detection (`reference/
review.md`) reading `orders.py` directly should flag `.find()` as not a valid `list`
method — this doesn't require running the code, just reading it (a `[HEURISTIC]`-or-
better finding). `/temper:check`'s scenario-coverage verification should separately
flag that neither scenario in `intent.md` has a test that actually calls `find_order()`
or `order_total()`.

**Pass condition for this fixture:** `/temper:review` (or the Review stage of
`/temper`) reports a correctness finding on `orders.py`'s `find_order()`, OR
`/temper:check` reports a scenario as uncovered/unverified. See
`evals/run-fixture.sh`.
