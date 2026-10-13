import unittest

from orders import Order


class OrderTest(unittest.TestCase):
    def test_order_keeps_its_total(self):
        order = Order(id="ord_1", customer_email="a@example.com", total_cents=1500)
        self.assertEqual(order.total_cents, 1500)


if __name__ == "__main__":
    unittest.main()
