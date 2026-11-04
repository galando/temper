import unittest

from ledger import audit, tenants
from ledger.testkit import FixedClock, call, issued_invoice, reset


class InvoiceTest(unittest.TestCase):
    def setUp(self):
        reset()
        self.clock = FixedClock(2026, 3, 1, 12, 0).__enter__()
        self.t = tenants.create("Acme", "Asia/Jerusalem", "IL")["id"]

    def tearDown(self):
        self.clock.__exit__()

    def test_tax_per_line_half_even(self):
        inv = issued_invoice(self.t, [(1, 250), (1, 250)])  # 17% of 250 = 42.5 -> 42 each
        self.assertEqual((inv["subtotal_cents"], inv["tax_cents"], inv["total_cents"]), (500, 84, 584))

    def test_issue_sets_dates_in_tenant_timezone(self):
        self.clock.set(2026, 3, 1, 23, 30)  # already March 2 in Jerusalem
        inv = issued_invoice(self.t, [(2, 1000)])
        self.assertEqual((inv["issued_on"], inv["due_on"]), ("2026-03-02", "2026-04-01"))

    def test_pay_in_full(self):
        inv = issued_invoice(self.t, [(1, 1000)])
        r = call("POST", f"/invoices/{inv['id']}/payments", self.t, body={"method": "card"})
        self.assertEqual(r["status"], 201)
        self.assertEqual(r["body"]["amount_cents"], 1170)
        self.assertEqual(call("GET", f"/invoices/{inv['id']}", self.t)["body"]["status"], "paid")

    def test_viewer_cannot_write(self):
        r = call("POST", "/customers", self.t, role="viewer", body={"name": "X", "email": "x@y.z"})
        self.assertEqual((r["status"], r["body"]["error"]["code"]), (403, "forbidden"))

    def test_other_tenant_is_404(self):
        other = tenants.create("Other", "Europe/Berlin", "DE")["id"]
        inv = issued_invoice(self.t, [(1, 100)])
        self.assertEqual(call("GET", f"/invoices/{inv['id'] + 5}", other)["status"], 404)

    def test_idempotent_replay(self):
        h = {"Idempotency-Key": "k1"}
        a = call("POST", "/customers", self.t, body={"name": "A", "email": "a@b.c"}, headers=h)
        b = call("POST", "/customers", self.t, body={"name": "A", "email": "a@b.c"}, headers=h)
        self.assertEqual(a, b)
        self.assertEqual(len([e for e in audit.events(self.t) if e["action"] == "customer.created"]), 1)
        c = call("POST", "/customers", self.t, body={"name": "B", "email": "a@b.c"}, headers=h)
        self.assertEqual(c["body"]["error"]["code"], "idempotency_mismatch")

    def test_credit_note_full_amount(self):
        inv = issued_invoice(self.t, [(3, 333)])
        r = call("POST", f"/invoices/{inv['id']}/credit-notes", self.t, body={"reason": "returned"})
        self.assertEqual(r["body"]["amount_cents"], inv["total_cents"])

    def test_export(self):
        issued_invoice(self.t, [(1, 1000)], customer="Beta")
        csv_text = call("GET", "/exports/invoices.csv", self.t)["body"]
        self.assertIn("INV-0001,Beta,issued,2026-03-01,10.00,1.70,11.70", csv_text)
