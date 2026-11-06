"""Payments. Today an invoice is paid in full, in one payment."""
from ledger import audit, errors, invoices, store

TABLE = "payments"
METHODS = ("card", "bank_transfer", "cash")


def pay_in_full(tenant_id, actor, invoice_id, method):
    inv = invoices.get(tenant_id, invoice_id)
    if inv["status"] != "issued":
        raise errors.conflict("only an issued invoice can be paid")
    if method not in METHODS:
        raise errors.validation(f"method must be one of {', '.join(METHODS)}")
    amount = invoices.totals(tenant_id, inv)["total"]
    p = store.insert(TABLE, tenant_id, {"invoice_id": invoice_id, "amount_cents": amount, "method": method})
    invoices.set_status(tenant_id, invoice_id, "paid")
    audit.record(tenant_id, actor, "payment.recorded", "payment", p["id"], {"invoice_id": invoice_id, "amount_cents": amount})
    return p


def for_invoice(tenant_id, invoice_id):
    return store.list_rows(TABLE, tenant_id, invoice_id=invoice_id)
