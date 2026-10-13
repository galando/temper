import unittest

from orders import Order, order_total


class OrderTotalHidden(unittest.TestCase):
    def test_total_of_an_existing_order(self):
        orders = [Order("a", "a@example.com", 500), Order("b", "b@example.com", 700)]
        self.assertEqual(order_total(orders, "b"), 700)

    def test_a_missing_order_is_a_value_error(self):
        with self.assertRaises(ValueError):
            order_total([Order("a", "a@example.com", 500)], "zzz")


if __name__ == "__main__":
    unittest.main()
