import unittest

import reset


class ResetTest(unittest.TestCase):
    def setUp(self):
        reset.ISSUED.clear()

    def test_request_a_reset_for_a_known_email(self):
        token = reset.request_reset("ana@example.com", now=1000.0)
        self.assertIsInstance(token, str)
        self.assertGreater(len(token), 10)

    def test_request_a_reset_for_an_unknown_email(self):
        self.assertIsNone(reset.request_reset("zoe@example.com", now=1000.0))


if __name__ == "__main__":
    unittest.main()
