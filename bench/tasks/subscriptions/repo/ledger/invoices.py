"""Invoices. Status: draft -> issued -> paid, or issued -> void. A draft can be deleted."""
import datetime

from ledger import audit, clock, customers, errors, money, store, taxes, tenants

TABLE = "invoices"
LINES = "invoice_lines"
PAYMENT_TERMS_DAYS = 30


def number(invoice_id):
    return f"INV-{invoice_id:04d}"


def create_draft(tenant_id, actor, customer_id):
    customers.get(tenant_id, customer_id)
    inv = store.insert(TABLE, tenant_id, {"customer_id": customer_id, "status": "draft", "issued_on": None, "due_on": None})
    inv = store.update(TABLE, tenant_id, inv["id"], number=number(inv["id"]))
    audit.record(tenant_id, actor, "invoice.created", "invoice", inv["id"])
    return inv


def get(tenant_id, invoice_id):
    inv = store.get(TABLE, tenant_id, invoice_id)
    if inv is None:
        raise errors.not_found("invoice")
    return inv


def lines(tenant_id, invoice_id):
    return store.list_rows(LINES, tenant_id, invoice_id=invoice_id)


def add_line(tenant_id, actor, invoice_id, description, quantity, unit_cents):
    inv = get(tenant_id, invoice_id)
    if inv["status"] != "draft":
        raise errors.conflict("only a draft invoice takes new lines")
    if not isinstance(description, str) or not description.strip():
        raise errors.validation("description is required")
    if not money.is_cents(quantity) or quantity < 1:
        raise errors.validation("quantity must be a whole number of at least 1")
    if not money.is_cents(unit_cents) or unit_cents < 0:
        raise errors.validation("unit_cents must be a whole number of cents, zero or more")
    line = store.insert(LINES, tenant_id, {"invoice_id": invoice_id, "description": description.strip(),
                                           "quantity": quantity, "unit_cents": unit_cents})
    audit.record(tenant_id, actor, "invoice.line_added", "invoice", invoice_id, {"line_id": line["id"]})
    return line


def totals(tenant_id, invoice):
    """The one place that computes an invoice's money: tax per line, half to even, then summed."""
    rate = taxes.rate_for(tenants.get(tenant_id)["region"])
    subtotal = tax = 0
    for line in lines(tenant_id, invoice["id"]):
        line_sub = line["quantity"] * line["unit_cents"]
        subtotal += line_sub
        tax += money.apply_rate(line_sub, rate)
    return {"subtotal": subtotal, "tax": tax, "total": subtotal + tax}


def issue(tenant_id, actor, invoice_id):
    inv = get(tenant_id, invoice_id)
    if inv["status"] != "draft":
        raise errors.conflict("only a draft invoice can be issued")
    if not lines(tenant_id, invoice_id):
        raise errors.conflict("an invoice needs at least one line")
    today = clock.today(tenants.get(tenant_id))
    inv = store.update(TABLE, tenant_id, invoice_id, status="issued", issued_on=today.isoformat(),
                       due_on=(today + datetime.timedelta(days=PAYMENT_TERMS_DAYS)).isoformat())
    audit.record(tenant_id, actor, "invoice.issued", "invoice", invoice_id)
    return inv


def void(tenant_id, actor, invoice_id):
    inv = get(tenant_id, invoice_id)
    if inv["status"] != "issued":
        raise errors.conflict("only an issued invoice can be voided")
    inv = store.update(TABLE, tenant_id, invoice_id, status="void")
    audit.record(tenant_id, actor, "invoice.voided", "invoice", invoice_id)
    return inv


def delete_draft(tenant_id, actor, invoice_id):
    inv = get(tenant_id, invoice_id)
    if inv["status"] != "draft":
        raise errors.conflict("only a draft invoice can be deleted")
    store.soft_delete(TABLE, tenant_id, invoice_id)
    audit.record(tenant_id, actor, "invoice.deleted", "invoice", invoice_id)


def set_status(tenant_id, invoice_id, status):
    """For other modules (payments): change the status without an audit event of its own."""
    return store.update(TABLE, tenant_id, invoice_id, status=status)


def serialize(tenant_id, inv):
    t = totals(tenant_id, inv)
    return {
        "id": inv["id"], "number": inv["number"], "customer_id": inv["customer_id"], "status": inv["status"],
        "issued_on": inv["issued_on"], "due_on": inv["due_on"],
        "lines": [{"id": l["id"], "description": l["description"], "quantity": l["quantity"],
                   "unit_cents": l["unit_cents"]} for l in lines(tenant_id, inv["id"])],
        "subtotal_cents": t["subtotal"], "tax_cents": t["tax"], "total_cents": t["total"],
    }
