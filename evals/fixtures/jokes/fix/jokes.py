"""A small store of jokes."""

JOKES = [
    "I told my computer a joke about UDP. It did not get it.",
    "There are 10 kinds of people: those who read binary and those who do not.",
    "A SQL query walks into a bar, sees two tables and asks: may I join you?",
]


def all_jokes():
    """Every joke, in order."""
    return list(JOKES)


def first():
    """The first joke."""
    return all_jokes()[0]


def list_jokes(n):
    """The first n jokes; every joke when n is larger than the list."""
    return all_jokes()[:n]
