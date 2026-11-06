"""The HTTP entry point: handle(method, path, request) -> response.

A request is a dict:
    {"tenant_id": 1, "user": {"name": "dana", "role": "clerk"}, "headers": {...}, "body": {...}, "query": {...}}
A response is a dict: {"status": int, "body": ..., "headers": {...}}.

Routes are registered with @route(method, pattern); a pattern's {name} parts are passed to the handler as
integer keyword arguments. A handler gets (ctx, **params) and returns (status, body) or (status, body, headers).
Every POST goes through the idempotency check (CONVENTIONS.md rule 6) before its handler runs.
"""
import hashlib
import json
import re

from ledger import credit_notes, customers, errors, export, invoices, payments, tenants

_ROUTES = []
_IDEMPOTENCY = {}  # (tenant_id, key) -> (body hash, response)
WRITE_ROLES = ("clerk", "admin")
READ_ROLES = ("viewer", "clerk", "admin")


def route(method, pattern, write=False):
    regex = re.compile("^" + re.sub(r"\{(\w+)\}", r"(?P<\1>\\d+)", pattern) + "$")

    def deco(fn):
        _ROUTES.append((method, regex, write, fn))
        return fn
    return deco


class Ctx:
    def __init__(self, request):
        self.tenant_id = request.get("tenant_id")
        self.user = request.get("user") or {}
        self.actor = self.user.get("name", "unknown")
        self.body = request.get("body") or {}
        self.query = request.get("query") or {}
        self.headers = {k.lower(): v for k, v in (request.get("headers") or {}).items()}

    @property
    def tenant(self):
        return tenants.get(self.tenant_id)


def _error(e):
    return {"status": e.status, "body": {"error": {"code": e.code, "message": e.message}}, "headers": {}}


def reset():
    _IDEMPOTENCY.clear()


def handle(method, path, request):
    ctx = Ctx(request)
    if ctx.tenant is None:
        return _error(errors.not_found("tenant"))
    for m, regex, write, fn in _ROUTES:
        match = regex.match(path)
        if m != method or not match:
            continue
        role = ctx.user.get("role")
        if role not in READ_ROLES or (write and role not in WRITE_ROLES):
            return _error(errors.ApiError(errors.FORBIDDEN, "your role may not do this"))
        params = {k: int(v) for k, v in match.groupdict().items()}
        key = ctx.headers.get("idempotency-key") if method == "POST" else None
        if key:
            digest = hashlib.sha256(json.dumps([path, ctx.body], sort_keys=True).encode()).hexdigest()
            seen = _IDEMPOTENCY.get((ctx.tenant_id, key))
            if seen:
                if seen[0] != digest:
                    return _error(errors.ApiError(errors.IDEMPOTENCY_MISMATCH, "this key was used with another request"))
                return json.loads(json.dumps(seen[1]))
        try:
            out = fn(ctx, **params)
            resp = {"status": out[0], "body": out[1], "headers": out[2] if len(out) > 2 else {}}
        except errors.ApiError as e:
            resp = _error(e)
        if key and resp["status"] < 500:
            _IDEMPOTENCY[(ctx.tenant_id, key)] = (digest, json.loads(json.dumps(resp)))
        return resp
    return _error(errors.not_found("route"))


# ---- customers ----
@route("POST", "/customers", write=True)
def create_customer(ctx):
    return 201, customers.create(ctx.tenant_id, ctx.actor, ctx.body.get("name"), ctx.body.get("email"))


@route("GET", "/customers/{customer_id}")
def get_customer(ctx, customer_id):
    return 200, customers.get(ctx.tenant_id, customer_id)


@route("PATCH", "/customers/{customer_id}", write=True)
def rename_customer(ctx, customer_id):
    return 200, customers.rename(ctx.tenant_id, ctx.actor, customer_id, ctx.body.get("name"))


@route("DELETE", "/customers/{customer_id}", write=True)
def delete_customer(ctx, customer_id):
    customers.delete(ctx.tenant_id, ctx.actor, customer_id)
    return 204, None


# ---- invoices ----
@route("POST", "/invoices", write=True)
def create_invoice(ctx):
    inv = invoices.create_draft(ctx.tenant_id, ctx.actor, ctx.body.get("customer_id"))
    return 201, invoices.serialize(ctx.tenant_id, inv)


@route("GET", "/invoices")
def list_invoices(ctx):
    rows = invoices.store.list_rows(invoices.TABLE, ctx.tenant_id)
    return 200, {"items": [invoices.serialize(ctx.tenant_id, i) for i in rows]}


@route("GET", "/invoices/{invoice_id}")
def get_invoice(ctx, invoice_id):
    return 200, invoices.serialize(ctx.tenant_id, invoices.get(ctx.tenant_id, invoice_id))


@route("DELETE", "/invoices/{invoice_id}", write=True)
def delete_invoice(ctx, invoice_id):
    invoices.delete_draft(ctx.tenant_id, ctx.actor, invoice_id)
    return 204, None


@route("POST", "/invoices/{invoice_id}/lines", write=True)
def add_line(ctx, invoice_id):
    b = ctx.body
    invoices.add_line(ctx.tenant_id, ctx.actor, invoice_id, b.get("description"), b.get("quantity"), b.get("unit_cents"))
    return 201, invoices.serialize(ctx.tenant_id, invoices.get(ctx.tenant_id, invoice_id))


@route("POST", "/invoices/{invoice_id}/issue", write=True)
def issue_invoice(ctx, invoice_id):
    return 200, invoices.serialize(ctx.tenant_id, invoices.issue(ctx.tenant_id, ctx.actor, invoice_id))


@route("POST", "/invoices/{invoice_id}/void", write=True)
def void_invoice(ctx, invoice_id):
    return 200, invoices.serialize(ctx.tenant_id, invoices.void(ctx.tenant_id, ctx.actor, invoice_id))


# ---- payments and credit notes ----
@route("POST", "/invoices/{invoice_id}/payments", write=True)
def pay_invoice(ctx, invoice_id):
    return 201, payments.pay_in_full(ctx.tenant_id, ctx.actor, invoice_id, ctx.body.get("method"))


@route("POST", "/invoices/{invoice_id}/credit-notes", write=True)
def credit_invoice(ctx, invoice_id):
    return 201, credit_notes.create(ctx.tenant_id, ctx.actor, invoice_id, ctx.body.get("reason"))


# ---- exports ----
@route("GET", "/exports/invoices.csv")
def export_invoices(ctx):
    return 200, export.invoices_csv(ctx.tenant_id), {"Content-Type": "text/csv"}
