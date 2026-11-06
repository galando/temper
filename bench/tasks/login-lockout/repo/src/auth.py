"""Login and logout routes."""
from src import users


def login(request):
    username = request.get("username", "")
    if users.check_password(username, request.get("password", "")):
        return {"status": 200, "body": {"user": username}}
    return {"status": 401, "body": {"error": "invalid credentials"}}


def logout(request):
    return {"status": 204, "headers": {"Set-Cookie": "session=; Max-Age=0"}}
