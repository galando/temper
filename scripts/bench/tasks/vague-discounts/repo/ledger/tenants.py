"""Tenants: the companies that use Ledger. A tenant has a timezone and a tax region."""
_TENANTS = {}


def create(name, timezone, region):
    tid = len(_TENANTS) + 1
    _TENANTS[tid] = {"id": tid, "name": name, "timezone": timezone, "region": region}
    return dict(_TENANTS[tid])


def get(tenant_id):
    t = _TENANTS.get(tenant_id)
    return dict(t) if t else None


def reset():
    _TENANTS.clear()
