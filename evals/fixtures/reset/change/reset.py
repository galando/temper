"""Password reset requests."""

import secrets

from accounts import is_known

# Tokens issued, by email: a list of (token, issued_at) pairs.
ISSUED = {}


def request_reset(email: str, now: float):
    """Ask for a password reset link.

    Returns a new token for a known email. Returns None for an unknown email, so a caller
    cannot tell which emails have an account.
    """
    if not is_known(email):
        return None
    key = email.strip().lower()
    token = secrets.token_urlsafe(16)
    ISSUED.setdefault(key, []).append((token, now))
    return token
