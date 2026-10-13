import unittest

import reset


class RateLimitHidden(unittest.TestCase):
    def setUp(self):
        reset.ISSUED.clear()

    def test_the_fourth_request_within_an_hour_is_refused(self):
        for i in range(3):
            reset.request_reset("ana@example.com", now=1000.0 + i)
        with self.assertRaises(reset.TooManyRequests):
            reset.request_reset("ana@example.com", now=1100.0)

    def test_a_request_after_the_hour_is_served(self):
        for i in range(3):
            reset.request_reset("ana@example.com", now=1000.0 + i)
        self.assertIsInstance(reset.request_reset("ana@example.com", now=1000.0 + 3601), str)


if __name__ == "__main__":
    unittest.main()
