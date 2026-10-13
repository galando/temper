import unittest

from notes import add_note, open_db


class NotesTest(unittest.TestCase):
    def test_a_note_is_stored(self):
        conn = open_db()
        note_id = add_note(conn, "Shopping", "milk, bread")
        row = conn.execute("SELECT title FROM notes WHERE id = ?", (note_id,)).fetchone()
        self.assertEqual(row[0], "Shopping")


if __name__ == "__main__":
    unittest.main()
