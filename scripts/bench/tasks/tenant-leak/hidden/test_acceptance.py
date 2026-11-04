"""Acceptance tests for the tenant leak, written from task.md and CONVENTIONS.md only (rule 4: tenant isolation;
rule 9: soft delete). Two tenants share the process, and each reads the other's ids."""
import csv
import io
import unittest

from ledger import tenants
from ledger.testkit import FixedClock, call, issued_invoice, reset


class Leak(unittest.TestCase):
    def setUp(self):
        reset()
        self.clock = FixedClock(2026, 3, 1, 12, 0).__enter__()
        self.a = tenants.create("Acme", "UTC", "IL")["id"]
        self.b = tenants.create("Beta GmbH", "Europe/Berlin", "DE")["id"]

    def tearDown(self):
        self.clock.__exit__()

    def test_same_invoice_id_each_tenant_sees_its_own(self):
        ia = issued_invoice(self.a, [(1, 1000)], customer="Acme Customer")
        call("POST", "/customers", self.b, body={"name": "First", "email": "f@b.b"})
        ib = issued_invoice(self.b, [(2, 500)], customer="Beta Customer")
        self.assertNotEqual(ia["customer_id"], ib["customer_id"])
        self.assertEqual(ia["id"], ib["id"])
        call("GET", f"/invoices/{ia['id']}", self.a)  # Acme reads first
        got = call("GET", f"/invoices/{ib['id']}", self.b)["body"]
        self.assertEqual((got["customer_id"], got["subtotal_cents"]), (ib["customer_id"], 1000))
        self.assertEqual(got["total_cents"], 1190)  # DE 19%

    def test_id_beta_does_not_have_is_404(self):
        for _ in range(3):
            issued_invoice(self.a, [(1, 100)])
        call("GET", "/invoices/3", self.a)
        r = call("GET", "/invoices/3", self.b)
        self.assertEqual((r["status"], r["body"]["error"]["code"]), (404, "not_found"))

    def test_customer_of_other_tenant_is_404(self):
        ca = call("POST", "/customers", self.a, body={"name": "Secret Co", "email": "s@c.o"})["body"]
        call("GET", f"/customers/{ca['id']}", self.a)
        self.assertEqual(call("GET", f"/customers/{ca['id']}", self.b)["status"], 404)

    def test_export_names_only_own_customers(self):
        issued_invoice(self.a, [(1, 100)], customer="Secret Co")
        call("GET", "/exports/invoices.csv", self.a)
        issued_invoice(self.b, [(1, 100)], customer="Beta Customer")
        rows = list(csv.DictReader(io.StringIO(call("GET", "/exports/invoices.csv", self.b)["body"])))
        self.assertEqual([r["customer"] for r in rows], ["Beta Customer"])

    def test_writes_use_own_invoice_state(self):
        c = call("POST", "/customers", self.b, body={"name": "B", "email": "b@b.b"})["body"]
        draft = call("POST", "/invoices", self.b, body={"customer_id": c["id"]})["body"]
        call("POST", f"/invoices/{draft['id']}/lines", self.b, body={"description": "x", "quantity": 1, "unit_cents": 100})
        issued_invoice(self.a, [(1, 100)])  # Acme invoice 1 is issued
        call("GET", "/invoices/1", self.a)
        r = call("POST", f"/invoices/{draft['id']}/payments", self.b, body={"method": "card"})
        self.assertEqual((r["status"], r["body"]["error"]["code"]), (409, "conflict"))  # Beta's invoice 1 is a draft

    def test_rename_and_delete_seen_at_once(self):
        ca = call("POST", "/customers", self.a, body={"name": "Old", "email": "o@l.d"})["body"]
        cb = call("POST", "/customers", self.b, body={"name": "Bee", "email": "b@e.e"})["body"]
        call("GET", f"/customers/{ca['id']}", self.a)
        call("GET", f"/customers/{cb['id']}", self.b)
        call("PATCH", f"/customers/{cb['id']}", self.b, body={"name": "Bee 2"})
        self.assertEqual(call("GET", f"/customers/{ca['id']}", self.a)["body"]["name"], "Old")
        self.assertEqual(call("GET", f"/customers/{cb['id']}", self.b)["body"]["name"], "Bee 2")
        call("DELETE", f"/customers/{ca['id']}", self.a)
        self.assertEqual(call("GET", f"/customers/{ca['id']}", self.a)["status"], 404)
        self.assertEqual(call("GET", f"/customers/{cb['id']}", self.b)["body"]["name"], "Bee 2")
