"""Orders of the shop."""

from dataclasses import dataclass


@dataclass
class Order:
    id: str
    customer_email: str
    total_cents: int
