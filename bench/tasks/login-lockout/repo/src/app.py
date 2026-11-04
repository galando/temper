"""The app: routes in ROUTES, middleware in MIDDLEWARE.

A middleware is called as mw(method, path, request) before the route, in order; when it returns a
response, that response is sent and the route does not run. A response is a dict with "status", and
optionally "body" and "headers".
"""
from src import auth

MIDDLEWARE = []
ROUTES = {
    "POST /login": auth.login,
    "POST /logout": auth.logout,
}


def handle(method, path, request):
    for mw in MIDDLEWARE:
        early = mw(method, path, request)
        if early is not None:
            return early
    route = ROUTES.get(f"{method} {path}")
    if route is None:
        return {"status": 404, "body": {"error": "not found"}}
    return route(request)
