"""CSV exports."""
import csv
import io

from ledger import customers, errors, invoices, money, store


def invoices_csv(tenant_id):
    out = io.StringIO()
    w = csv.writer(out, lineterminator="\n")
    w.writerow(["number", "customer", "status", "issued_on", "subtotal", "tax", "total"])
    for inv in store.list_rows(invoices.TABLE, tenant_id):
        try:
            name = customers.get(tenant_id, inv["customer_id"])["name"]
        except errors.ApiError:
            name = "(deleted customer)"
        t = invoices.totals(tenant_id, inv)
        w.writerow([inv["number"], name, inv["status"], inv["issued_on"] or "",
                    money.fmt(t["subtotal"]), money.fmt(t["tax"]), money.fmt(t["total"])])
    return out.getvalue()
