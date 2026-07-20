# test_orders.py — passes green, but never actually calls find_order() or
# order_total(). It only tests the Order dataclass itself.
#
# SEEDED DEFECT: find_order()'s `orders.find(...)` call (app/orders.py) raises
# AttributeError unconditionally — Python's list has no .find() method, that's a
# JavaScript Array method, and the error fires the instant it's called regardless of
# whether `orders` has any items. No test here calls find_order() or order_total() at
# all, so `pytest` reports a fully green suite while the only two functions that matter
# are completely broken. This mirrors the README's story exactly: tests pass, but the
# feature doesn't work — a defect only reading the code (not running the suite) catches.

from app.orders import Order


def test_order_is_constructible():
    order = Order(id="ord_1", customer_email="a@example.com", total_cents=1500)
    assert order.id == "ord_1"
    assert order.total_cents == 1500
