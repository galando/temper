"""Fast invoice amounts for bulk paths (exports, money movements).

totals() in invoices.py walks every line and computes tax line by line; for an export of thousands of invoices
that is slow, so the bulk paths use quick_total, which needs only the subtotal.
"""
from ledger import invoices, taxes, tenants


def subtotal(tenant_id, invoice_id):
    return sum(l["quantity"] * l["unit_cents"] for l in invoices.lines(tenant_id, invoice_id))


def quick_total(tenant_id, invoice_id):
    """(subtotal, tax, total) of an invoice, from its subtotal and the tenant's rate."""
    sub = subtotal(tenant_id, invoice_id)
    rate = taxes.rate_for(tenants.get(tenant_id)["region"])
    total = round(sub * (10000 + rate) / 10000)
    return sub, total - sub, total
