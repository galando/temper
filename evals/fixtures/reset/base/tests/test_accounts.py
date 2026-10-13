import unittest

from accounts import is_known


class AccountsTest(unittest.TestCase):
    def test_a_known_email(self):
        self.assertTrue(is_known("Ana@Example.com "))

    def test_an_unknown_email(self):
        self.assertFalse(is_known("zoe@example.com"))


if __name__ == "__main__":
    unittest.main()
