"""Orders of the shop."""

from dataclasses import dataclass
from typing import Optional


@dataclass
class Order:
    id: str
    customer_email: str
    total_cents: int


class OrderNotFound(ValueError):
    """No order has the id that was asked for."""


def find_order(orders: list, order_id: str) -> Optional[Order]:
    """The order with this id, or None."""
    return next((order for order in orders if order.id == order_id), None)


def order_total(orders: list, order_id: str) -> int:
    """The total in cents of the order with this id."""
    order = find_order(orders, order_id)
    if order is None:
        raise OrderNotFound(order_id)
    return order.total_cents
