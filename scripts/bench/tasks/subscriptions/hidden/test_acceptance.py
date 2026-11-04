"""Acceptance tests for subscriptions, written from task.md and CONVENTIONS.md only."""
import unittest

from ledger import audit, tenants
from ledger.testkit import FixedClock, call, reset


class Base(unittest.TestCase):
    TZ = "UTC"

    def setUp(self):
        reset()
        self.clock = FixedClock(2027, 1, 31, 9, 0).__enter__()
        self.t = tenants.create("Acme", self.TZ, "IL")["id"]
        self.cust = call("POST", "/customers", self.t, body={"name": "Zed", "email": "z@e.d"})["body"]["id"]
        self.basic = self.plan("Basic", 10000)
        self.pro = self.plan("Pro", 20000)

    def tearDown(self):
        self.clock.__exit__()

    def plan(self, name, cents, role="clerk"):
        r = call("POST", "/plans", self.t, role=role, body={"name": name, "monthly_cents": cents})
        return r["body"]["id"] if r["status"] == 201 else r

    def subscribe(self, plan_id=None, start=None, role="clerk", tenant=None):
        body = {"customer_id": self.cust, "plan_id": plan_id or self.basic}
        if start:
            body["start_date"] = start
        return call("POST", "/subscriptions", tenant or self.t, role=role, body=body)

    def run_billing(self, tenant=None, role="clerk"):
        return call("POST", "/subscriptions/run-billing", tenant or self.t, role=role)

    def invoice(self, iid):
        return call("GET", f"/invoices/{iid}", self.t)["body"]

    def descriptions(self, ids):
        return [self.invoice(i)["lines"][0]["description"] for i in ids]

    def sub(self, sid, tenant=None):
        return call("GET", f"/subscriptions/{sid}", tenant or self.t)


class Plans(Base):
    def test_create_and_get(self):
        r = call("GET", f"/plans/{self.basic}", self.t)
        self.assertEqual((r["status"], r["body"]["name"], r["body"]["monthly_cents"]), (200, "Basic", 10000))

    def test_bad_prices(self):
        for bad in [0, -1, 1.5, "10", True]:
            r = self.plan("X", bad)
            self.assertEqual((r["status"], r["body"]["error"]["code"]), (400, "validation"), bad)

    def test_viewer_cannot_create(self):
        self.assertEqual(self.plan("X", 100, role="viewer")["status"], 403)


class Subscribing(Base):
    def test_defaults_to_today(self):
        r = self.subscribe()
        self.assertEqual(r["status"], 201)
        b = r["body"]
        self.assertEqual((b["status"], b["anchor_day"], b["next_billing_date"]), ("active", 31, "2027-01-31"))

    def test_future_start(self):
        b = self.subscribe(start="2027-02-15")["body"]
        self.assertEqual((b["anchor_day"], b["next_billing_date"]), (15, "2027-02-15"))

    def test_bad_start_dates(self):
        for bad in ["2027-01-30", "2027-02-30", "31/01/2027", "soon"]:
            r = self.subscribe(start=bad)
            self.assertEqual(r["status"], 400, bad)

    def test_audit_one_event(self):
        n = len(audit.events(self.t))
        sid = self.subscribe()["body"]["id"]
        new = audit.events(self.t)[n:]
        self.assertEqual(len(new), 1)
        self.assertRegex(new[0]["action"], r"^subscription\.[a-z_]+ed$")

    def test_other_tenant(self):
        other = tenants.create("Beta", "UTC", "DE")["id"]
        sid = self.subscribe()["body"]["id"]
        self.assertEqual(self.sub(sid, tenant=other)["status"], 404)
        r = call("POST", f"/subscriptions/{sid}/cancel", other)
        self.assertEqual(r["status"], 404)
        self.assertEqual(self.sub(sid)["body"]["status"], "active")

    def test_viewer(self):
        self.assertEqual(self.subscribe(role="viewer")["status"], 403)
        self.assertEqual(self.run_billing(role="viewer")["status"], 403)


class Billing(Base):
    def test_month_end_anchor(self):
        sid = self.subscribe()["body"]["id"]
        got = []
        for day in [(2027, 1, 31), (2027, 2, 28), (2027, 3, 31), (2027, 4, 30)]:
            self.clock.set(*day, 9, 0)
            got += self.run_billing()["body"]["invoices"]
        self.assertEqual(self.descriptions(got), [
            "Basic 2027-01-31 to 2027-02-27",
            "Basic 2027-02-28 to 2027-03-30",
            "Basic 2027-03-31 to 2027-04-29",
            "Basic 2027-04-30 to 2027-05-30",
        ])
        self.assertEqual(self.sub(sid)["body"]["next_billing_date"], "2027-05-31")

    def test_leap_year(self):
        self.clock.set(2028, 1, 30, 9, 0)
        self.subscribe()
        self.clock.set(2028, 3, 30, 9, 0)
        ids = self.run_billing()["body"]["invoices"]
        self.assertEqual(self.descriptions(ids), [
            "Basic 2028-01-30 to 2028-02-28",
            "Basic 2028-02-29 to 2028-03-29",
            "Basic 2028-03-30 to 2028-04-29",
        ])

    def test_catch_up_oldest_first_and_once(self):
        self.clock.set(2026, 3, 15, 9, 0)
        self.subscribe()
        self.clock.set(2026, 6, 20, 9, 0)
        ids = self.run_billing()["body"]["invoices"]
        self.assertEqual(self.descriptions(ids), [
            "Basic 2026-03-15 to 2026-04-14", "Basic 2026-04-15 to 2026-05-14",
            "Basic 2026-05-15 to 2026-06-14", "Basic 2026-06-15 to 2026-07-14",
        ])
        self.assertEqual(self.run_billing()["body"]["invoices"], [])

    def test_invoice_is_issued_with_tax(self):
        self.subscribe()
        inv = self.invoice(self.run_billing()["body"]["invoices"][0])
        self.assertEqual((inv["status"], inv["customer_id"], inv["total_cents"]), ("issued", self.cust, 11700))
        self.assertEqual((inv["lines"][0]["quantity"], inv["lines"][0]["unit_cents"]), (1, 10000))

    def test_nothing_before_due(self):
        self.subscribe(start="2027-02-10")
        self.assertEqual(self.run_billing()["body"]["invoices"], [])

    def test_other_tenant_not_billed(self):
        other = tenants.create("Beta", "UTC", "DE")["id"]
        self.subscribe()
        self.assertEqual(self.run_billing(tenant=other)["body"]["invoices"], [])
        self.assertEqual(len(self.run_billing()["body"]["invoices"]), 1)

    def test_cancel(self):
        sid = self.subscribe()["body"]["id"]
        self.run_billing()
        n = len(audit.events(self.t))
        r = call("POST", f"/subscriptions/{sid}/cancel", self.t)
        self.assertEqual((r["status"], self.sub(sid)["body"]["status"]), (200, "canceled"))
        self.assertEqual(len(audit.events(self.t)), n + 1)
        self.clock.set(2027, 4, 1, 9, 0)
        self.assertEqual(self.run_billing()["body"]["invoices"], [])
        self.assertEqual(call("POST", f"/subscriptions/{sid}/cancel", self.t)["status"], 409)


class TenantToday(Base):
    TZ = "Asia/Jerusalem"

    def test_billing_uses_tenant_today(self):
        self.clock.set(2026, 3, 15, 9, 0)
        self.subscribe()
        self.run_billing()
        self.clock.set(2026, 4, 14, 20, 0)   # 23:00 on Apr 14 in Jerusalem
        self.assertEqual(self.run_billing()["body"]["invoices"], [])
        self.clock.set(2026, 4, 14, 22, 30)  # 01:30 on Apr 15 in Jerusalem
        self.assertEqual(len(self.run_billing()["body"]["invoices"]), 1)


class ChangePlan(Base):
    def setUp(self):
        super().setUp()
        self.clock.set(2027, 2, 1, 9, 0)
        self.small = self.plan("Small", 1000)
        self.big = self.plan("Big", 2010)
        self.sid = self.subscribe(plan_id=self.small)["body"]["id"]
        self.run_billing()  # period 2027-02-01 to 2027-02-28: 28 days

    def change(self, plan_id, tenant=None):
        return call("POST", f"/subscriptions/{self.sid}/change-plan", tenant or self.t, body={"plan_id": plan_id})

    def invoice_count(self):
        return len(call("GET", "/invoices", self.t)["body"]["items"])

    def test_upgrade_prorates_half_even(self):
        self.clock.set(2027, 2, 22, 9, 0)  # 7 days left of 28: 1010 * 7 / 28 = 252.5
        before = self.invoice_count()
        r = self.change(self.big)
        self.assertEqual(r["status"], 200)
        items = call("GET", "/invoices", self.t)["body"]["items"]
        self.assertEqual(len(items), before + 1)
        inv = items[-1]
        self.assertEqual(inv["status"], "issued")
        self.assertEqual(inv["lines"][0]["description"], "Upgrade to Big 2027-02-22 to 2027-02-28")
        self.assertEqual((inv["lines"][0]["quantity"], inv["lines"][0]["unit_cents"]), (1, 252))
        self.assertEqual(self.sub(self.sid)["body"]["plan_id"], self.big)

    def test_upgrade_then_next_period_bills_new_price(self):
        self.clock.set(2027, 2, 22, 9, 0)
        self.change(self.big)
        self.clock.set(2027, 3, 1, 9, 0)
        ids = self.run_billing()["body"]["invoices"]
        self.assertEqual(self.descriptions(ids), ["Big 2027-03-01 to 2027-03-31"])
        self.assertEqual(self.invoice(ids[0])["lines"][0]["unit_cents"], 2010)

    def test_downgrade_no_invoice(self):
        self.clock.set(2027, 2, 22, 9, 0)
        self.change(self.big)
        before = self.invoice_count()
        self.assertEqual(self.change(self.small)["status"], 200)
        self.assertEqual(self.invoice_count(), before)

    def test_change_on_first_day_counts_whole_period(self):
        self.clock.set(2027, 2, 1, 15, 0)
        self.change(self.big)
        inv = call("GET", "/invoices", self.t)["body"]["items"][-1]
        self.assertEqual(inv["lines"][0]["unit_cents"], 1010)
        self.assertEqual(inv["lines"][0]["description"], "Upgrade to Big 2027-02-01 to 2027-02-28")

    def test_due_unbilled_is_conflict(self):
        self.clock.set(2027, 3, 2, 9, 0)
        r = self.change(self.big)
        self.assertEqual((r["status"], r["body"]["error"]["code"]), (409, "conflict"))
        self.assertEqual(self.sub(self.sid)["body"]["plan_id"], self.small)

    def test_not_started_changes_without_invoice(self):
        sid = self.subscribe(plan_id=self.small, start="2027-02-20")["body"]["id"]
        before = self.invoice_count()
        r = call("POST", f"/subscriptions/{sid}/change-plan", self.t, body={"plan_id": self.big})
        self.assertEqual(r["status"], 200)
        self.assertEqual(self.invoice_count(), before)
        self.assertEqual(self.sub(sid)["body"]["plan_id"], self.big)

    def test_audit_one_event(self):
        self.clock.set(2027, 2, 22, 9, 0)
        tiny = self.plan("Tiny", 500)
        n = len(audit.events(self.t))
        self.change(tiny)  # a downgrade: a change, no invoice
        new = audit.events(self.t)[n:]
        self.assertEqual(len(new), 1)
        self.assertRegex(new[0]["action"], r"^subscription\.[a-z_]+ed$")

    def test_other_tenant_404(self):
        other = tenants.create("Beta", "UTC", "DE")["id"]
        self.assertEqual(self.change(self.big, tenant=other)["status"], 404)
