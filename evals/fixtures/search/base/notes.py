"""Notes kept in SQLite."""

import sqlite3


def open_db(path: str = ":memory:") -> sqlite3.Connection:
    """A database with the notes table."""
    conn = sqlite3.connect(path)
    conn.execute("CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY, title TEXT NOT NULL, body TEXT NOT NULL)")
    return conn


def add_note(conn: sqlite3.Connection, title: str, body: str) -> int:
    """Store a note and return its id."""
    cur = conn.execute("INSERT INTO notes (title, body) VALUES (?, ?)", (title, body))
    conn.commit()
    return cur.lastrowid
