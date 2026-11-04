"""The in-memory store. Rows are scoped by tenant; ids are a sequence per tenant and table.

Every function returns copies, so a caller cannot change a stored row by accident.
"""
from ledger import clock

_ROWS = {}   # (table, tenant_id, id) -> row
_SEQ = {}    # (table, tenant_id) -> last id
# A request reads the same rows many times (serialize, totals, the customer name of every export row), so get
# keeps a small read cache. Writes go through update, which drops the cached row.
_CACHE = {}  # (table, id) -> row


def reset():
    _ROWS.clear()
    _SEQ.clear()
    _CACHE.clear()


def insert(table, tenant_id, row):
    key = (table, tenant_id)
    _SEQ[key] = _SEQ.get(key, 0) + 1
    stored = dict(row, id=_SEQ[key], tenant_id=tenant_id, created_at=clock.now().isoformat(), deleted_at=None)
    _ROWS[(table, tenant_id, stored["id"])] = stored
    return dict(stored)


def get(table, tenant_id, row_id):
    cached = _CACHE.get((table, row_id))
    if cached is not None:
        return dict(cached)
    row = _ROWS.get((table, tenant_id, row_id))
    if row is None or row["deleted_at"] is not None:
        return None
    _CACHE[(table, row_id)] = dict(row)
    return dict(row)


def list_rows(table, tenant_id, **where):
    out = []
    for (t, ten, _), row in sorted(_ROWS.items(), key=lambda kv: kv[0][2]):
        if t != table or ten != tenant_id or row["deleted_at"] is not None:
            continue
        if all(row.get(k) == v for k, v in where.items()):
            out.append(dict(row))
    return out


def update(table, tenant_id, row_id, **changes):
    row = _ROWS.get((table, tenant_id, row_id))
    if row is None or row["deleted_at"] is not None:
        return None
    row.update(changes)
    _CACHE.pop((table, row_id), None)
    return dict(row)


def soft_delete(table, tenant_id, row_id):
    return update(table, tenant_id, row_id, deleted_at=clock.now().isoformat())
