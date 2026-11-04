"""Customers of a tenant."""
from ledger import audit, errors, store

TABLE = "customers"


def create(tenant_id, actor, name, email):
    if not isinstance(name, str) or not name.strip():
        raise errors.validation("name is required")
    if not isinstance(email, str) or "@" not in email:
        raise errors.validation("email is invalid")
    c = store.insert(TABLE, tenant_id, {"name": name.strip(), "email": email})
    audit.record(tenant_id, actor, "customer.created", "customer", c["id"], {"name": c["name"]})
    return c


def get(tenant_id, customer_id):
    c = store.get(TABLE, tenant_id, customer_id)
    if c is None:
        raise errors.not_found("customer")
    return c


def rename(tenant_id, actor, customer_id, name):
    get(tenant_id, customer_id)
    if not isinstance(name, str) or not name.strip():
        raise errors.validation("name is required")
    c = store.update(TABLE, tenant_id, customer_id, name=name.strip())
    audit.record(tenant_id, actor, "customer.renamed", "customer", customer_id, {"name": c["name"]})
    return c


def delete(tenant_id, actor, customer_id):
    get(tenant_id, customer_id)
    store.soft_delete(TABLE, tenant_id, customer_id)
    audit.record(tenant_id, actor, "customer.deleted", "customer", customer_id)
