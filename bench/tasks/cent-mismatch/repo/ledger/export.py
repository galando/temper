"""CSV exports."""
import csv
import io

from ledger import amounts, customers, errors, invoices, money, store


def invoices_csv(tenant_id):
    out = io.StringIO()
    w = csv.writer(out, lineterminator="\n")
    w.writerow(["number", "customer", "status", "issued_on", "subtotal", "tax", "total"])
    for inv in store.list_rows(invoices.TABLE, tenant_id):
        try:
            name = customers.get(tenant_id, inv["customer_id"])["name"]
        except errors.ApiError:
            name = "(deleted customer)"
        sub, tax, total = amounts.quick_total(tenant_id, inv["id"])
        w.writerow([inv["number"], name, inv["status"], inv["issued_on"] or "",
                    money.fmt(sub), money.fmt(tax), money.fmt(total)])
    return out.getvalue()
