"""Credit notes: a full credit of an issued or paid invoice."""
from ledger import amounts, audit, errors, invoices, store

TABLE = "credit_notes"


def create(tenant_id, actor, invoice_id, reason):
    inv = invoices.get(tenant_id, invoice_id)
    if inv["status"] not in ("issued", "paid"):
        raise errors.conflict("only an issued or paid invoice can be credited")
    if store.list_rows(TABLE, tenant_id, invoice_id=invoice_id):
        raise errors.conflict("the invoice already has a credit note")
    if not isinstance(reason, str) or not reason.strip():
        raise errors.validation("reason is required")
    amount = amounts.quick_total(tenant_id, invoice_id)[2]
    cn = store.insert(TABLE, tenant_id, {"invoice_id": invoice_id, "amount_cents": amount, "reason": reason.strip()})
    audit.record(tenant_id, actor, "credit_note.created", "credit_note", cn["id"], {"invoice_id": invoice_id, "amount_cents": amount})
    return cn
