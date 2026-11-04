import unittest
from src import app


class AppTest(unittest.TestCase):
    def test_login_ok(self):
        self.assertEqual(app.handle("POST", "/login", {"username": "alice", "password": "wonderland"})["status"], 200)

    def test_login_bad(self):
        self.assertEqual(app.handle("POST", "/login", {"username": "alice", "password": "x"})["status"], 401)

    def test_unknown_route(self):
        self.assertEqual(app.handle("GET", "/nope", {})["status"], 404)
