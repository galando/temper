import unittest

from jokes import first


class FirstTest(unittest.TestCase):
    def test_first_is_the_udp_joke(self):
        self.assertTrue(first().startswith("I told my computer"))


if __name__ == "__main__":
    unittest.main()
