import importlib
import unittest
from unittest import mock

import src.timeutil


def fresh_app():
    # A fresh process each test: reload every module so in-memory state starts empty.
    import src.users, src.auth, src.app
    import sys
    # Two passes, so a module that bound another module's objects at import rebinds the fresh ones.
    for _ in range(2):
        for name in sorted([n for n in sys.modules if n == "src" or n.startswith("src.")], reverse=True):
            if name != "src.timeutil":
                importlib.reload(sys.modules[name])
    import src.app
    return src.app


class Clock:
    def __init__(self, t=1_000_000.0):
        self.t = t

    def __call__(self):
        return self.t


class LockoutAcceptance(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.patch = mock.patch.object(src.timeutil, "now", self.clock)
        self.patch.start()
        self.app = fresh_app()

    def tearDown(self):
        self.patch.stop()

    def login(self, user, pw):
        return self.app.handle("POST", "/login", {"username": user, "password": pw})

    def fail(self, user="alice", n=1, step=0):
        for _ in range(n):
            self.assertEqual(self.login(user, "wrong")["status"], 401)
            self.clock.t += step

    def test_two_failures_still_allowed(self):
        self.fail(n=2)
        self.assertEqual(self.login("alice", "wonderland")["status"], 200)

    def test_three_failures_lock(self):
        self.fail(n=3)
        r = self.login("alice", "wrong")
        self.assertEqual(r["status"], 423)

    def test_correct_password_refused_while_locked(self):
        self.fail(n=3)
        self.assertEqual(self.login("alice", "wonderland")["status"], 423)

    def test_retry_after(self):
        self.fail(n=1, step=30)  # failure at t0
        self.fail(n=2)           # failures at t0+30
        r = self.login("alice", "wrong")
        self.assertEqual(r["status"], 423)
        headers = {k.lower(): v for k, v in (r.get("headers") or {}).items()}
        self.assertIn("retry-after", headers)
        self.assertEqual(int(headers["retry-after"]), 570)

    def test_retry_after_rounds_up(self):
        self.fail(n=3)
        self.clock.t += 0.5
        r = self.login("alice", "wrong")
        headers = {k.lower(): v for k, v in (r.get("headers") or {}).items()}
        self.assertEqual(int(headers["retry-after"]), 600)

    def test_window_expiry_unlocks(self):
        self.fail(n=3)
        self.clock.t += 601
        self.assertEqual(self.login("alice", "wonderland")["status"], 200)

    def test_failures_outside_window_do_not_count(self):
        self.fail(n=2)
        self.clock.t += 601
        self.fail(n=1)
        self.assertEqual(self.login("alice", "wonderland")["status"], 200)

    def test_success_clears(self):
        self.fail(n=2)
        self.assertEqual(self.login("alice", "wonderland")["status"], 200)
        self.fail(n=2)
        self.assertEqual(self.login("alice", "wonderland")["status"], 200)

    def test_per_username(self):
        self.fail(user="alice", n=3)
        self.assertEqual(self.login("bob", "builder")["status"], 200)

    def test_other_routes_unaffected(self):
        self.fail(n=3)
        self.assertEqual(self.app.handle("POST", "/logout", {"username": "alice"})["status"], 204)
