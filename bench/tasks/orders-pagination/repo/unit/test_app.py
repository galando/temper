import unittest
from src import app, orders


class AppTest(unittest.TestCase):
    def setUp(self):
        orders.reset()

    def test_get_order(self):
        o = orders.add("ann", 500, 100)
        self.assertEqual(app.handle("GET", "/order", {"query": {"id": str(o["id"])}})["body"]["customer"], "ann")

    def test_get_order_missing(self):
        self.assertEqual(app.handle("GET", "/order", {"query": {"id": "9"}})["status"], 404)
