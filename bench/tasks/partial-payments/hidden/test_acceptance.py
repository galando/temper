"""Acceptance tests for partial payments, written from task.md and CONVENTIONS.md only."""
import re
import unittest

from ledger import audit, tenants
from ledger.testkit import FixedClock, call, issued_invoice, reset


class Base(unittest.TestCase):
    def setUp(self):
        reset()
        self.clock = FixedClock(2026, 3, 1, 12, 0).__enter__()
        self.t = tenants.create("Acme", "Asia/Jerusalem", "IL")["id"]
        self.inv = issued_invoice(self.t, [(1, 10000)])  # total 11700
        self.iid = self.inv["id"]

    def tearDown(self):
        self.clock.__exit__()

    def pay(self, amount=None, method="card", role="clerk", headers=None, iid=None, tenant=None):
        body = {"method": method}
        if amount is not None:
            body["amount_cents"] = amount
        return call("POST", f"/invoices/{iid or self.iid}/payments", tenant or self.t, role=role, body=body, headers=headers)

    def refund(self, payment_id, amount, iid=None, role="clerk", headers=None, tenant=None):
        return call("POST", f"/invoices/{iid or self.iid}/refunds", tenant or self.t, role=role,
                    body={"payment_id": payment_id, "amount_cents": amount}, headers=headers)

    def get(self, iid=None):
        return call("GET", f"/invoices/{iid or self.iid}", self.t)["body"]

    def events(self):
        return audit.events(self.t)


class Payments(Base):
    def test_partial_payment_status_and_amounts(self):
        r = self.pay(5000)
        self.assertEqual(r["status"], 201)
        inv = self.get()
        self.assertEqual((inv["status"], inv["paid_cents"], inv["balance_cents"]), ("partially_paid", 5000, 6700))

    def test_second_payment_completes(self):
        self.pay(5000)
        self.pay(6700)
        inv = self.get()
        self.assertEqual((inv["status"], inv["paid_cents"], inv["balance_cents"]), ("paid", 11700, 0))

    def test_no_amount_pays_the_balance(self):
        self.pay(1700)
        r = self.pay()
        self.assertEqual(r["status"], 201)
        self.assertEqual(r["body"]["amount_cents"], 10000)
        self.assertEqual(self.get()["status"], "paid")

    def test_no_amount_on_fresh_invoice_still_pays_in_full(self):
        self.pay()
        inv = self.get()
        self.assertEqual((inv["status"], inv["paid_cents"], inv["balance_cents"]), ("paid", 11700, 0))

    def test_overpayment_is_conflict_and_changes_nothing(self):
        self.pay(5000)
        n = len(self.events())
        r = self.pay(6701)
        self.assertEqual((r["status"], r["body"]["error"]["code"]), (409, "conflict"))
        self.assertEqual(self.get()["paid_cents"], 5000)
        self.assertEqual(len(self.events()), n)

    def test_bad_amounts(self):
        for bad in [0, -5, 10.5, "100", True]:
            r = self.pay(bad)
            self.assertEqual((r["status"], r["body"]["error"]["code"]), (400, "validation"), bad)
        self.assertEqual(self.get()["paid_cents"], 0)

    def test_paid_invoice_takes_no_more(self):
        self.pay()
        self.assertEqual(self.pay(1)["status"], 409)

    def test_draft_and_void_take_none(self):
        c = call("POST", "/customers", self.t, body={"name": "D", "email": "d@e.f"})["body"]
        d = call("POST", "/invoices", self.t, body={"customer_id": c["id"]})["body"]
        self.assertEqual(self.pay(100, iid=d["id"])["status"], 409)
        call("POST", f"/invoices/{self.iid}/void", self.t)
        self.assertEqual(self.pay(100)["status"], 409)

    def test_one_audit_event_per_payment(self):
        n = len(self.events())
        self.pay(100)
        new = self.events()[n:]
        self.assertEqual([e["action"] for e in new], ["payment.recorded"])

    def test_idempotent_payment(self):
        h = {"Idempotency-Key": "p-1"}
        a = self.pay(4000, headers=h)
        b = self.pay(4000, headers=h)
        self.assertEqual(a, b)
        self.assertEqual(self.get()["paid_cents"], 4000)

    def test_viewer_cannot_pay(self):
        r = self.pay(100, role="viewer")
        self.assertEqual((r["status"], r["body"]["error"]["code"]), (403, "forbidden"))

    def test_list_includes_amounts(self):
        self.pay(700)
        items = call("GET", "/invoices", self.t)["body"]["items"]
        self.assertEqual((items[0]["paid_cents"], items[0]["balance_cents"]), (700, 11000))


class Refunds(Base):
    def test_partial_refund_reopens(self):
        p = self.pay()["body"]
        r = self.refund(p["id"], 2000)
        self.assertEqual(r["status"], 201)
        inv = self.get()
        self.assertEqual((inv["status"], inv["paid_cents"], inv["balance_cents"]), ("partially_paid", 9700, 2000))

    def test_full_refund_back_to_issued(self):
        p = self.pay()["body"]
        self.refund(p["id"], 11700)
        inv = self.get()
        self.assertEqual((inv["status"], inv["paid_cents"], inv["balance_cents"]), ("issued", 0, 11700))

    def test_refund_more_than_left_of_payment(self):
        p1 = self.pay(5000)["body"]
        self.pay(6700)
        self.refund(p1["id"], 3000)
        r = self.refund(p1["id"], 2001)  # only 2000 left of p1, though 8700 is paid in all
        self.assertEqual((r["status"], r["body"]["error"]["code"]), (409, "conflict"))
        self.assertEqual(self.refund(p1["id"], 2000)["status"], 201)

    def test_refund_of_other_invoices_payment_is_404(self):
        other = issued_invoice(self.t, [(1, 500)], customer="Other Co")
        p = self.pay(iid=other["id"])["body"]
        self.pay(1000)
        r = self.refund(p["id"], 100)
        self.assertEqual((r["status"], r["body"]["error"]["code"]), (404, "not_found"))

    def test_refund_bad_amount(self):
        p = self.pay()["body"]
        for bad in [0, -1, 1.5, "10"]:
            self.assertEqual(self.refund(p["id"], bad)["status"], 400, bad)

    def test_one_audit_event_per_refund_none_when_rejected(self):
        p = self.pay()["body"]
        n = len(self.events())
        self.refund(p["id"], 100)
        new = self.events()[n:]
        self.assertEqual(len(new), 1)
        self.assertRegex(new[0]["action"], r"^(payment|refund)\.[a-z_]+ed$")
        self.refund(p["id"], 999999)
        self.assertEqual(len(self.events()), n + 1)

    def test_idempotent_refund(self):
        p = self.pay()["body"]
        h = {"Idempotency-Key": "r-1"}
        self.refund(p["id"], 500, headers=h)
        self.refund(p["id"], 500, headers=h)
        self.assertEqual(self.get()["paid_cents"], 11200)

    def test_viewer_cannot_refund(self):
        p = self.pay()["body"]
        self.assertEqual(self.refund(p["id"], 100, role="viewer")["status"], 403)

    def test_other_tenant_gets_404(self):
        other = tenants.create("Beta", "Europe/Berlin", "DE")["id"]
        p = self.pay()["body"]
        self.assertEqual(self.refund(p["id"], 100, tenant=other)["status"], 404)
        self.assertEqual(self.pay(100, tenant=other)["status"], 404)
        self.assertEqual(self.get()["paid_cents"], 11700)


class VoidCreditExport(Base):
    def test_cannot_void_with_money_paid(self):
        self.pay(100)
        self.assertEqual(call("POST", f"/invoices/{self.iid}/void", self.t)["status"], 409)

    def test_can_void_after_full_refund(self):
        p = self.pay(100)["body"]
        self.refund(p["id"], 100)
        self.assertEqual(call("POST", f"/invoices/{self.iid}/void", self.t)["status"], 200)

    def test_credit_note_is_the_balance(self):
        self.pay(7000)
        r = call("POST", f"/invoices/{self.iid}/credit-notes", self.t, body={"reason": "damaged"})
        self.assertEqual((r["status"], r["body"]["amount_cents"]), (201, 4700))

    def test_no_credit_note_when_balance_zero(self):
        self.pay()
        r = call("POST", f"/invoices/{self.iid}/credit-notes", self.t, body={"reason": "x"})
        self.assertEqual((r["status"], r["body"]["error"]["code"]), (409, "conflict"))

    def test_export_columns(self):
        self.pay(5000)
        text = call("GET", "/exports/invoices.csv", self.t)["body"]
        lines = text.strip().splitlines()
        self.assertEqual(lines[0], "number,customer,status,issued_on,subtotal,tax,total,paid,balance")
        self.assertEqual(lines[1], "INV-0001,Acme Ltd,partially_paid,2026-03-01,100.00,17.00,117.00,50.00,67.00")
