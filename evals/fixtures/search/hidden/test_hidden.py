import unittest

from notes import add_note, open_db, search_notes


class SearchHidden(unittest.TestCase):
    def setUp(self):
        self.conn = open_db()
        add_note(self.conn, "Shopping list", "milk, bread")
        add_note(self.conn, "Trip to Rome", "train at nine")

    def test_a_quote_in_the_term_is_text(self):
        self.assertEqual(search_notes(self.conn, "' OR '1'='1"), [])

    def test_an_apostrophe_does_not_break_the_search(self):
        add_note(self.conn, "Ana's birthday", "cake")
        self.assertEqual(search_notes(self.conn, "Ana's"), ["Ana's birthday"])


if __name__ == "__main__":
    unittest.main()
