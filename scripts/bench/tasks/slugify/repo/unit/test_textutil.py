import unittest
from src import textutil


class TruncateTest(unittest.TestCase):
    def test_short_text_is_unchanged(self):
        self.assertEqual(textutil.truncate("hi", 10), "hi")

    def test_long_text_is_cut(self):
        self.assertEqual(textutil.truncate("abcdef", 4), "abc…")
