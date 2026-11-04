"""Helpers for tests: a clean world, a fixed clock, and short request helpers."""
import datetime
from unittest import mock

from ledger import api, audit, clock, store, tenants


def reset():
    store.reset(); tenants.reset(); audit.reset(); api.reset()


class FixedClock:
    """Patch clock.now with a settable UTC time: with FixedClock(2026, 3, 1) as c: c.advance(days=1)."""

    def __init__(self, *ymd_hms):
        self.t = datetime.datetime(*ymd_hms, tzinfo=datetime.timezone.utc)
        self._p = mock.patch.object(clock, "now", lambda: self.t)

    def __enter__(self):
        self._p.start()
        return self

    def __exit__(self, *a):
        self._p.stop()

    def advance(self, **kw):
        self.t += datetime.timedelta(**kw)

    def set(self, *ymd_hms):
        self.t = datetime.datetime(*ymd_hms, tzinfo=datetime.timezone.utc)


def call(method, path, tenant_id, role="clerk", body=None, headers=None, query=None, user="dana"):
    return api.handle(method, path, {"tenant_id": tenant_id, "user": {"name": user, "role": role},
                                     "body": body or {}, "headers": headers or {}, "query": query or {}})


def issued_invoice(tenant_id, lines, customer="Acme Ltd"):
    """Create a customer and an issued invoice with lines [(quantity, unit_cents), ...]; return the invoice body."""
    c = call("POST", "/customers", tenant_id, body={"name": customer, "email": "billing@example.com"})["body"]
    inv = call("POST", "/invoices", tenant_id, body={"customer_id": c["id"]})["body"]
    for q, u in lines:
        call("POST", f"/invoices/{inv['id']}/lines", tenant_id, body={"description": "item", "quantity": q, "unit_cents": u})
    return call("POST", f"/invoices/{inv['id']}/issue", tenant_id)["body"]
