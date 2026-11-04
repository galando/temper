"""The audit log."""
from ledger import clock

_EVENTS = []


def record(tenant_id, actor, action, entity, entity_id, data=None):
    _EVENTS.append({
        "tenant_id": tenant_id, "actor": actor, "action": action, "entity": entity,
        "entity_id": entity_id, "data": dict(data or {}), "at": clock.now().isoformat(),
    })


def events(tenant_id):
    return [dict(e) for e in _EVENTS if e["tenant_id"] == tenant_id]


def reset():
    _EVENTS.clear()
