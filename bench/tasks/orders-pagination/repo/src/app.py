"""The app. handle(method, path, request) -> response.

A request is a dict; its "query" is a dict of the query string's parameters, every value a string.
A response is a dict with "status" and "body".
"""
from src import orders


def list_orders(request):
    return {"status": 200, "body": {"items": orders.all_orders()}}


def get_order(request):
    oid = request.get("query", {}).get("id", "")
    for o in orders.all_orders():
        if str(o["id"]) == oid:
            return {"status": 200, "body": o}
    return {"status": 404, "body": {"error": "not found"}}


ROUTES = {"GET /orders": list_orders, "GET /order": get_order}


def handle(method, path, request):
    route = ROUTES.get(f"{method} {path}")
    if route is None:
        return {"status": 404, "body": {"error": "not found"}}
    return route(request)
