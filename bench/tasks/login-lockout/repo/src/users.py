"""The user store (in memory for now)."""
_USERS = {"alice": "wonderland", "bob": "builder"}


def check_password(username, password):
    return _USERS.get(username) == password
