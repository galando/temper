# orders.py — order lookup.
#
# SEEDED DEFECT (do not fix without updating evals/fixtures/orders-api/SEEDED_DEFECT.md):
# find_order() calls `orders.find(...)` — Python lists have no `.find()` method (that's
# a JavaScript Array method). The correct call is `next((o for o in orders if ...), None)`
# or a loop. This is a classic hallucinated-API defect: the method reads as plausible but
# raises AttributeError at runtime. No test currently exercises find_order() with data
# present, so nothing catches it (see test/test_orders.py).

from dataclasses import dataclass


@dataclass
class Order:
    id: str
    customer_email: str
    total_cents: int


def find_order(orders: list[Order], order_id: str) -> Order | None:
    return orders.find(lambda o: o.id == order_id)  # AttributeError: list has no .find


def order_total(orders: list[Order], order_id: str) -> int:
    order = find_order(orders, order_id)
    if order is None:
        raise ValueError(f"no such order: {order_id}")
    return order.total_cents
