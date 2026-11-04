import unittest
from src import textutil, posts


class SlugifyAcceptance(unittest.TestCase):
    def test_lowercase_and_spaces(self):
        self.assertEqual(textutil.slugify("Hello World"), "hello-world")

    def test_accents(self):
        self.assertEqual(textutil.slugify("Café Über Niño"), "cafe-uber-nino")

    def test_runs_collapse(self):
        self.assertEqual(textutil.slugify("a  --  b!!c"), "a-b-c")

    def test_trim(self):
        self.assertEqual(textutil.slugify("  ¡Hola!  "), "hola")

    def test_digits_kept(self):
        self.assertEqual(textutil.slugify("Top 10 Tips"), "top-10-tips")

    def test_nothing_usable(self):
        self.assertEqual(textutil.slugify("!!! ???"), "")
        self.assertEqual(textutil.slugify(""), "")

    def test_wired_into_posts(self):
        p = posts.create_post("My First Post!", "body")
        self.assertEqual(p["slug"], "my-first-post")
