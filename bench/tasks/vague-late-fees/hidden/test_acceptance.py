"""Hidden tests. test_ticket_*: follow from task.md and CONVENTIONS.md. test_brief_N_*: brief fact N."""
import unittest

from ledger import tenants
from ledger.testkit import FixedClock, call, issued_invoice, reset


class LateFees(unittest.TestCase):
    def setUp(self):
        reset()
        self.clock = FixedClock(2026, 3, 1, 12, 0).__enter__()
        self.t = tenants.create("Acme", "Asia/Jerusalem", "IL")["id"]
        # due 2026-03-31; total 117000 (2% = 2340)
        self.inv = issued_invoice(self.t, [(1, 100000)])

    def tearDown(self):
        self.clock.__exit__()

    def run_job(self, role="clerk", tenant=None):
        return call("POST", "/invoices/run-late-fees", tenant or self.t, role=role)

    def get(self, iid):
        return call("GET", f"/invoices/{iid}", self.t)["body"]

    def all_ids(self):
        return [i["id"] for i in call("GET", "/invoices", self.t)["body"]["items"]]

    def far_overdue(self):
        self.clock.set(2026, 5, 1, 12, 0)

    # ---- the ticket ----
    def test_ticket_charges_an_overdue_invoice(self):
        self.far_overdue()
        r = self.run_job()
        self.assertEqual(r["status"], 200)
        self.assertEqual(len(r["body"]["invoices"]), 1)
        fee = self.get(r["body"]["invoices"][0])
        self.assertEqual(fee["customer_id"], self.inv["customer_id"])
        self.assertNotEqual(fee["id"], self.inv["id"])

    def test_ticket_nothing_before_due(self):
        self.clock.set(2026, 3, 20, 12, 0)
        self.assertEqual(self.run_job()["body"]["invoices"], [])

    def test_ticket_paid_invoices_not_charged(self):
        call("POST", f"/invoices/{self.inv['id']}/payments", self.t, body={"method": "card"})
        self.far_overdue()
        self.assertEqual(self.run_job()["body"]["invoices"], [])

    def test_ticket_viewer_forbidden(self):
        self.far_overdue()
        self.assertEqual(self.run_job(role="viewer")["status"], 403)

    def test_ticket_other_tenant_not_charged(self):
        other = tenants.create("Beta", "UTC", "DE")["id"]
        self.far_overdue()
        self.assertEqual(self.run_job(tenant=other)["body"]["invoices"], [])

    # ---- the brief ----
    def test_brief_1_fee_invoice_shape(self):
        self.far_overdue()
        fee = self.get(self.run_job()["body"]["invoices"][0])
        self.assertEqual(fee["status"], "issued")
        self.assertEqual(len(fee["lines"]), 1)
        self.assertEqual((fee["lines"][0]["description"], fee["lines"][0]["quantity"]), ("Late fee for INV-0001", 1))

    def test_brief_2_two_percent(self):
        self.far_overdue()
        fee = self.get(self.run_job()["body"]["invoices"][0])
        self.assertEqual(fee["lines"][0]["unit_cents"], 2340)

    def test_brief_2_half_even_and_minimum(self):
        a = issued_invoice(self.t, [(1, 21368)], customer="B")   # total 25000.56 -> 25001; 2% = 500.02 -> 500
        b = issued_invoice(self.t, [(1, 2137)], customer="C")    # total 2500 (2137 + 363.29 -> 363); 2% = 50 -> min 500
        c = issued_invoice(self.t, [(1, 106838)], customer="D")  # total 106838 + 18162.46 -> 125000; 2% = 2500
        self.far_overdue()
        ids = self.run_job()["body"]["invoices"]
        by_line = {self.get(i)["lines"][0]["description"]: self.get(i)["lines"][0]["unit_cents"] for i in ids}
        self.assertEqual(by_line.get(f"Late fee for {b['number']}"), 500)
        self.assertEqual(by_line.get(f"Late fee for {c['number']}"), 2500)
        self.assertEqual(by_line.get(f"Late fee for {a['number']}"), 500)

    def test_brief_2_rounds_half_to_even(self):
        k = issued_invoice(self.t, [(1, 53440)], customer="J")  # 53440 + 9085 = 62525; 2% = 1250.5 -> 1250
        self.far_overdue()
        ids = self.run_job()["body"]["invoices"]
        by_line = {self.get(i)["lines"][0]["description"]: self.get(i)["lines"][0]["unit_cents"] for i in ids}
        self.assertEqual(by_line.get(f"Late fee for {k['number']}"), 1250)

    def test_brief_3_grace_period(self):
        self.clock.set(2026, 4, 7, 12, 0)   # 7 days after due: not yet
        self.assertEqual(self.run_job()["body"]["invoices"], [])
        self.clock.set(2026, 4, 7, 21, 30)  # Apr 8 00:30 in Jerusalem: 8 days after due
        self.assertEqual(len(self.run_job()["body"]["invoices"]), 1)

    def test_brief_4_once_ever(self):
        self.far_overdue()
        self.run_job()
        self.clock.advance(days=1)
        self.assertEqual(self.run_job()["body"]["invoices"], [])
        self.clock.advance(days=40)
        self.assertEqual(self.run_job()["body"]["invoices"], [])

    def test_brief_5_small_invoices_exempt(self):
        small = issued_invoice(self.t, [(1, 1709)], customer="Small")  # 1709 + 290.53 -> 291 = 2000: charged
        tiny = issued_invoice(self.t, [(1, 1708)], customer="Tiny")    # 1708 + 290.36 -> 290 = 1998: exempt
        self.far_overdue()
        names = [self.get(i)["lines"][0]["description"] for i in self.run_job()["body"]["invoices"]]
        self.assertIn(f"Late fee for {small['number']}", names)
        self.assertNotIn(f"Late fee for {tiny['number']}", names)

    def test_brief_6_fees_never_get_fees(self):
        self.far_overdue()
        self.run_job()
        self.clock.set(2026, 7, 1, 12, 0)  # the fee invoice is now far overdue too
        self.assertEqual(self.run_job()["body"]["invoices"], [])
