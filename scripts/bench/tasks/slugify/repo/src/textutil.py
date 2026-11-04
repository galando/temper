"""Small text helpers."""


def truncate(text, limit):
    """Cut text to at most limit characters, ending with an ellipsis when cut."""
    if len(text) <= limit:
        return text
    return text[: max(limit - 1, 0)] + "…"
