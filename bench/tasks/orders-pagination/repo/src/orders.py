"""The order store (in memory)."""
_ORDERS = []
_NEXT_ID = [1]


def add(customer, total_cents, created_at):
    order = {"id": _NEXT_ID[0], "customer": customer, "total_cents": total_cents, "created_at": created_at}
    _NEXT_ID[0] += 1
    _ORDERS.append(order)
    return order


def all_orders():
    return list(_ORDERS)


def reset():
    _ORDERS.clear()
    _NEXT_ID[0] = 1
