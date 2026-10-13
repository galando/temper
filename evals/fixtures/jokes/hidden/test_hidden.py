import unittest

import jokes


class ListJokesHidden(unittest.TestCase):
    def test_every_joke_when_n_is_the_size(self):
        self.assertEqual(jokes.list_jokes(len(jokes.JOKES)), jokes.JOKES)

    def test_every_joke_when_n_is_larger(self):
        self.assertEqual(jokes.list_jokes(10), jokes.JOKES)

    def test_first_n(self):
        self.assertEqual(jokes.list_jokes(2), jokes.JOKES[:2])


if __name__ == "__main__":
    unittest.main()
