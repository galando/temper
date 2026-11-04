"""Hidden tests. test_ticket_*: follow from task.md and CONVENTIONS.md. test_brief_N_*: brief fact N."""
import unittest

from ledger import audit, tenants
from ledger.testkit import FixedClock, call, reset


class Discounts(unittest.TestCase):
    def setUp(self):
        reset()
        self.clock = FixedClock(2026, 3, 1, 12, 0).__enter__()
        self.t = tenants.create("Acme", "UTC", "IL")["id"]
        c = call("POST", "/customers", self.t, body={"name": "Acme Ltd", "email": "a@b.c"})["body"]
        self.iid = call("POST", "/invoices", self.t, body={"customer_id": c["id"]})["body"]["id"]

    def tearDown(self):
        self.clock.__exit__()

    def line(self, q, u):
        return call("POST", f"/invoices/{self.iid}/lines", self.t, body={"description": "x", "quantity": q, "unit_cents": u})

    def discount(self, percent, role="admin", tenant=None):
        return call("POST", f"/invoices/{self.iid}/discount", tenant or self.t, role=role, body={"percent": percent})

    def get(self):
        return call("GET", f"/invoices/{self.iid}", self.t)["body"]

    # ---- the ticket ----
    def test_ticket_discount_shown(self):
        self.line(1, 10000)
        r = self.discount(10)
        self.assertIn(r["status"], (200, 201))
        inv = self.get()
        self.assertEqual((inv["discount_percent"], inv["discount_cents"]), (10, 1000))

    def test_ticket_whole_numbers_only(self):
        self.line(1, 10000)
        for bad in [12.5, "10", -5, True]:
            self.assertEqual(self.discount(bad)["status"], 400, bad)

    def test_ticket_viewer_and_other_tenant(self):
        self.line(1, 10000)
        self.assertEqual(self.discount(10, role="viewer")["status"], 403)
        other = tenants.create("Beta", "UTC", "DE")["id"]
        self.assertEqual(self.discount(10, tenant=other)["status"], 404)

    def test_ticket_one_audit_event(self):
        self.line(1, 10000)
        n = len(audit.events(self.t))
        self.discount(10)
        self.assertEqual(len(audit.events(self.t)), n + 1)

    # ---- the brief ----
    def test_brief_1_draft_only(self):
        self.line(1, 10000)
        call("POST", f"/invoices/{self.iid}/issue", self.t)
        r = self.discount(10)
        self.assertEqual((r["status"], r["body"]["error"]["code"]), (409, "conflict"))

    def test_brief_2_before_tax_line_by_line(self):
        self.line(1, 250)
        self.line(1, 250)
        self.line(3, 1999)
        self.discount(15)
        inv = self.get()
        # line discounts: 37.5 -> 38, 37.5 -> 38, 899.55 -> 900; reduced 212, 212, 5097; tax 36.04 -> 36, 36, 866.49 -> 866
        self.assertEqual((inv["subtotal_cents"], inv["discount_cents"], inv["tax_cents"], inv["total_cents"]),
                         (6497, 976, 938, 6459))

    def test_brief_3_role_limits(self):
        self.line(1, 10000)
        r = self.discount(21, role="clerk")
        self.assertEqual((r["status"], r["body"]["error"]["code"]), (403, "forbidden"))
        self.assertIn(self.discount(20, role="clerk")["status"], (200, 201))
        self.assertIn(self.discount(40, role="admin")["status"], (200, 201))
        r = self.discount(41, role="admin")
        self.assertEqual((r["status"], r["body"]["error"]["code"]), (400, "validation"))

    def test_brief_4_replace_remove_and_later_lines(self):
        self.line(1, 10000)
        self.discount(10)
        self.discount(20)
        self.assertEqual(self.get()["discount_cents"], 2000)
        self.line(1, 5000)
        self.assertEqual(self.get()["discount_cents"], 3000)
        self.discount(0)
        inv = self.get()
        self.assertEqual((inv["discount_percent"], inv["discount_cents"], inv["total_cents"]), (0, 0, 17550))

    def test_brief_5_export_column(self):
        self.line(1, 10000)
        self.discount(10)
        call("POST", f"/invoices/{self.iid}/issue", self.t)
        lines = call("GET", "/exports/invoices.csv", self.t)["body"].strip().splitlines()
        header = lines[0].split(",")
        self.assertEqual(header[-1], "discount")
        row = dict(zip(header, lines[1].split(",")))
        self.assertEqual((row["subtotal"], row["discount"], row["tax"], row["total"]), ("100.00", "10.00", "15.30", "105.30"))
