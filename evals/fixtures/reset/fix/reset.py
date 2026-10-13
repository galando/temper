"""Password reset requests."""

import secrets

from accounts import is_known

# Tokens issued, by email: a list of (token, issued_at) pairs.
ISSUED = {}
LIMIT = 3
WINDOW = 3600.0


class TooManyRequests(Exception):
    """More than LIMIT requests for one email within WINDOW seconds."""


def request_reset(email: str, now: float):
    """Ask for a password reset link.

    Returns a new token for a known email. Returns None for an unknown email, so a caller
    cannot tell which emails have an account. Raises TooManyRequests on the fourth request
    for one email within an hour.
    """
    if not is_known(email):
        return None
    key = email.strip().lower()
    recent = [t for t in ISSUED.get(key, []) if now - t[1] < WINDOW]
    if len(recent) >= LIMIT:
        raise TooManyRequests(key)
    token = secrets.token_urlsafe(16)
    ISSUED[key] = recent + [(token, now)]
    return token
