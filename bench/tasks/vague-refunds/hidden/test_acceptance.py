"""Hidden tests. test_ticket_*: follow from task.md and CONVENTIONS.md. test_brief_N_*: brief fact N."""
import unittest

from ledger import audit, tenants
from ledger.testkit import FixedClock, call, issued_invoice, reset


class Refunds(unittest.TestCase):
    def setUp(self):
        reset()
        self.clock = FixedClock(2026, 3, 1, 12, 0).__enter__()
        self.t = tenants.create("Acme", "Asia/Jerusalem", "IL")["id"]
        self.inv = issued_invoice(self.t, [(1, 10000)])  # total 11700
        self.iid = self.inv["id"]
        call("POST", f"/invoices/{self.iid}/payments", self.t, body={"method": "card"})

    def tearDown(self):
        self.clock.__exit__()

    def refund(self, amount, reason="damaged", role="admin", iid=None, tenant=None):
        body = {"amount_cents": amount}
        if reason is not None:
            body["reason"] = reason
        return call("POST", f"/invoices/{iid or self.iid}/refunds", tenant or self.t, role=role, body=body)

    def status(self):
        return call("GET", f"/invoices/{self.iid}", self.t)["body"]["status"]

    # ---- the ticket ----
    def test_ticket_refund_answers_201_with_the_refund(self):
        r = self.refund(5000)
        self.assertEqual(r["status"], 201)
        b = r["body"]
        self.assertEqual((b["invoice_id"], b["amount_cents"], b["reason"]), (self.iid, 5000, "damaged"))
        self.assertIn("id", b)

    def test_ticket_only_paid_invoices(self):
        other = issued_invoice(self.t, [(1, 500)], customer="Unpaid Co")
        self.assertEqual(self.refund(100, iid=other["id"])["status"], 409)

    def test_ticket_bad_amounts(self):
        for bad in [0, -1, 1.5, "100"]:
            self.assertEqual(self.refund(bad)["status"], 400, bad)

    def test_ticket_viewer_and_other_tenant(self):
        self.assertEqual(self.refund(100, role="viewer")["status"], 403)
        other = tenants.create("Beta", "UTC", "DE")["id"]
        self.assertEqual(self.refund(100, tenant=other)["status"], 404)

    def test_ticket_one_audit_event(self):
        n = len(audit.events(self.t))
        self.refund(100)
        self.assertEqual(len(audit.events(self.t)), n + 1)

    # ---- the brief ----
    def test_brief_1_clerk_forbidden(self):
        r = self.refund(100, role="clerk")
        self.assertEqual((r["status"], r["body"]["error"]["code"]), (403, "forbidden"))
        self.assertEqual(self.refund(100, role="admin")["status"], 201)

    def test_brief_2_sixty_day_window(self):
        self.clock.advance(days=60)
        self.assertEqual(self.refund(100)["status"], 201)
        self.clock.advance(days=1)
        r = self.refund(100)
        self.assertEqual((r["status"], r["body"]["error"]["code"]), (409, "conflict"))

    def test_brief_2_window_uses_tenant_today(self):
        self.clock.set(2026, 4, 30, 20, 0)   # Apr 30 23:00 in Jerusalem: day 60
        self.assertEqual(self.refund(100)["status"], 201)
        self.clock.set(2026, 4, 30, 21, 30)  # May 1 00:30 in Jerusalem: day 61
        self.assertEqual(self.refund(100)["status"], 409)

    def test_brief_3_partial_and_cap(self):
        self.assertEqual(self.refund(7000)["status"], 201)
        r = self.refund(4701)
        self.assertEqual((r["status"], r["body"]["error"]["code"]), (409, "conflict"))
        self.assertEqual(self.refund(4700)["status"], 201)

    def test_brief_4_reason_required(self):
        for reason in [None, "", "   "]:
            r = self.refund(100, reason=reason)
            self.assertEqual((r["status"], r["body"]["error"]["code"]), (400, "validation"), repr(reason))

    def test_brief_5_status(self):
        self.refund(1000)
        self.assertEqual(self.status(), "paid")
        self.refund(10700)
        self.assertEqual(self.status(), "refunded")
