"""The accounts of the service."""

ACCOUNTS = {
    "ana@example.com": {"name": "Ana"},
    "ben@example.com": {"name": "Ben"},
}


def is_known(email: str) -> bool:
    """Whether an account has this email."""
    return email.strip().lower() in ACCOUNTS
