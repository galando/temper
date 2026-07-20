# test_orders.py — only exercises the not-found path, so find_order()'s hallucinated
# `.find()` call is never actually invoked with data in the list.
#
# SEEDED DEFECT: no test calls find_order()/order_total() with a non-empty orders list,
# so the AttributeError in orders.py never fires here. /temper:check or /temper:review
# reading orders.py directly (not just running the existing suite) should still flag
# `.find()` as not a list method.

from app.orders import find_order, order_total


def test_find_order_returns_none_for_empty_list():
    assert find_order([], "ord_1") is None


def test_order_total_raises_for_missing_order():
    try:
        order_total([], "ord_1")
        assert False, "expected ValueError"
    except ValueError:
        pass
