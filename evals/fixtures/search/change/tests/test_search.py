import unittest

from notes import add_note, open_db, search_notes


class SearchTest(unittest.TestCase):
    def setUp(self):
        self.conn = open_db()
        add_note(self.conn, "Shopping list", "milk, bread")
        add_note(self.conn, "Trip to Rome", "train at nine")

    def test_search_by_a_word_in_the_title(self):
        self.assertEqual(search_notes(self.conn, "Rome"), ["Trip to Rome"])

    def test_search_with_no_match(self):
        self.assertEqual(search_notes(self.conn, "Paris"), [])


if __name__ == "__main__":
    unittest.main()
