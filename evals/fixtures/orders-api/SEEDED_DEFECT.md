# Seeded defect: hallucinated API

**Stack:** fastapi/python (minimal — no HTTP layer needed for the eval, just the module)

**What's wrong:** `app/orders.py`'s `find_order()` calls `orders.find(lambda o: ...)`.
Python `list` has no `.find()` method (that's a JavaScript `Array` method) — this raises
`AttributeError` at runtime for any non-empty `orders` list. `test/test_orders.py` only
exercises the empty-list path, so the existing test suite passes green while the
function is broken for real data — the first scenario in `intent.md` ("Look up an
existing order's total") is never actually verified.

**Which gate should catch it:** `/temper:review`'s defect detection (`reference/
review.md`) reading `orders.py` directly should flag `.find()` as not a valid `list`
method — this doesn't require running the code, just reading it (a `[HEURISTIC]`-or-
better finding). `/temper:check`'s scenario-coverage verification should separately
flag that the "Look up an existing order's total" scenario has no test that actually
calls `find_order()` with a populated list.

**Pass condition for this fixture:** `/temper:review` (or the Review stage of
`/temper`) reports a correctness finding on `orders.py`'s `find_order()`, OR
`/temper:check` reports the first scenario as uncovered/unverified. See
`evals/run-fixture.sh`.
