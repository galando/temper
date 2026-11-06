import unittest
from src import app, orders


def get(**q):
    return app.handle("GET", "/orders", {"query": {k: str(v) for k, v in q.items()}})


class PaginationAcceptance(unittest.TestCase):
    def setUp(self):
        orders.reset()

    def seed(self, n, same_time_every=1):
        return [orders.add("c%d" % i, 100 + i, 1000 + (i // same_time_every)) for i in range(n)]

    def walk(self, limit):
        seen, cursor, pages = [], None, 0
        while True:
            q = {"limit": limit}
            if cursor is not None:
                q["cursor"] = cursor
            r = get(**q)
            self.assertEqual(r["status"], 200, r)
            seen += [o["id"] for o in r["body"]["items"]]
            cursor = r["body"]["next_cursor"]
            pages += 1
            if cursor is None or pages > 50:
                return seen, pages

    def test_default_limit_20(self):
        self.seed(25)
        r = get()
        self.assertEqual(r["status"], 200)
        self.assertEqual(len(r["body"]["items"]), 20)
        self.assertIsInstance(r["body"]["next_cursor"], str)

    def test_max_100(self):
        self.seed(120)
        self.assertEqual(len(get(limit=100)["body"]["items"]), 100)

    def test_bad_limits(self):
        self.seed(3)
        for bad in ["0", "101", "-1", "abc", "2.5", ""]:
            r = app.handle("GET", "/orders", {"query": {"limit": bad}})
            self.assertEqual(r["status"], 400, bad)
            self.assertIn("error", r["body"])

    def test_newest_first_ties_by_id_desc(self):
        made = self.seed(6, same_time_every=2)  # created_at 1000,1000,1001,1001,1002,1002
        ids = [o["id"] for o in get(limit=10)["body"]["items"]]
        expect = [o["id"] for o in sorted(made, key=lambda o: (o["created_at"], o["id"]), reverse=True)]
        self.assertEqual(ids, expect)

    def test_walk_all_pages_no_dupes_no_gaps(self):
        made = self.seed(23, same_time_every=3)
        seen, pages = self.walk(5)
        self.assertEqual(pages, 5)
        self.assertEqual(sorted(seen), sorted(o["id"] for o in made))
        self.assertEqual(len(seen), len(set(seen)))

    def test_last_page_null_cursor(self):
        self.seed(10)
        r = get(limit=10)
        self.assertIsNone(r["body"]["next_cursor"])

    def test_empty_store(self):
        r = get()
        self.assertEqual(r["status"], 200)
        self.assertEqual(r["body"]["items"], [])
        self.assertIsNone(r["body"]["next_cursor"])

    def test_tampered_cursor(self):
        self.seed(10)
        cur = get(limit=3)["body"]["next_cursor"]
        for bad in ["garbage", cur[:-1] + ("A" if cur[-1] != "A" else "B"), "e30="]:
            r = app.handle("GET", "/orders", {"query": {"limit": "3", "cursor": bad}})
            self.assertEqual(r["status"], 400, bad)

    def test_new_order_does_not_shift_pages(self):
        made = self.seed(9)
        first = get(limit=4)
        ids = [o["id"] for o in first["body"]["items"]]
        orders.add("late", 1, 5000)  # newest of all, created between page fetches
        cursor = first["body"]["next_cursor"]
        while cursor is not None:
            r = get(limit=4, cursor=cursor)
            ids += [o["id"] for o in r["body"]["items"]]
            cursor = r["body"]["next_cursor"]
        self.assertEqual(sorted(ids), sorted(o["id"] for o in made))
