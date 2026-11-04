"""Acceptance tests for the cent mismatch, written from task.md and CONVENTIONS.md only.

CONVENTIONS.md rule 2: tax is per line, half to even, summed; invoices.totals is the one place that computes it,
and the API, exports, credit notes and payments all use it. So every place must show the per line numbers.
"""
import csv
import io
import unittest

from ledger import tenants
from ledger.testkit import FixedClock, call, issued_invoice, reset

CASES = [
    ("IL", [(1, 250), (1, 250)], (500, 84, 584)),          # the ticket: 5.84 in the app
    ("IL", [(1, 150), (1, 150), (1, 150)], (450, 78, 528)),
    ("US-NY", [(3, 1999), (1, 5)], (6002, 532, 6534)),
    ("DE", [(1, 1), (1, 1), (1, 1), (1, 1)], (4, 0, 4)),
    ("UK", [(2, 1234)], (2468, 494, 2962)),
    ("IL", [(7, 13), (1, 9999)], (10090, 1715, 11805)),
]


class Mismatch(unittest.TestCase):
    def setUp(self):
        reset()
        self.clock = FixedClock(2026, 3, 1, 12, 0).__enter__()

    def tearDown(self):
        self.clock.__exit__()

    def world(self, region, lines):
        t = tenants.create(f"T-{region}", "UTC", region)["id"]
        return t, issued_invoice(t, lines)

    def test_app_keeps_per_line_tax(self):
        for region, lines, want in CASES:
            t, inv = self.world(region, lines)
            self.assertEqual((inv["subtotal_cents"], inv["tax_cents"], inv["total_cents"]), want, (region, lines))

    def test_export_matches_app(self):
        for region, lines, (sub, tax, total) in CASES:
            t, inv = self.world(region, lines)
            rows = list(csv.DictReader(io.StringIO(call("GET", "/exports/invoices.csv", t)["body"])))
            row = [r for r in rows if r["number"] == inv["number"]][0]
            fmt = lambda c: f"{c // 100}.{c % 100:02d}"
            self.assertEqual((row["subtotal"], row["tax"], row["total"]), (fmt(sub), fmt(tax), fmt(total)), (region, lines))

    def test_credit_note_matches_app(self):
        for region, lines, (_, _, total) in CASES:
            t, inv = self.world(region, lines)
            r = call("POST", f"/invoices/{inv['id']}/credit-notes", t, body={"reason": "credit"})
            self.assertEqual(r["body"]["amount_cents"], total, (region, lines))

    def test_payment_matches_app(self):
        for region, lines, (_, _, total) in CASES:
            t, inv = self.world(region, lines)
            r = call("POST", f"/invoices/{inv['id']}/payments", t, body={"method": "card"})
            self.assertEqual(r["body"]["amount_cents"], total, (region, lines))
