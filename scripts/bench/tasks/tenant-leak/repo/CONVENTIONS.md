# House rules

Every change to this codebase follows these rules. Reviews reject code that breaks one.

1. **Money is integer cents.** Never use float for money. Amounts cross the API as integer cents. Use
   `ledger.money` for every calculation that can produce a fraction of a cent: `money.apply_rate` rounds half to
   even.
2. **Tax is computed per line, then summed.** An invoice's tax is the sum of each line's
   `money.apply_rate(line_subtotal, rate_bp)`. `invoices.totals(invoice)` is the one place that computes an
   invoice's subtotal, tax and total; everything else (API, exports, credit notes, payments) calls it.
3. **Every state change writes exactly one audit event**, with `audit.record(tenant_id, actor, action, entity,
   entity_id, data)`. The action is `<entity>.<past tense verb>`, for example `invoice.issued`. A request that
   changes nothing (a rejected request, an idempotent replay) writes no event.
4. **Tenant isolation.** Every store call takes the tenant id. A request for another tenant's object answers
   404 `not_found`, never 403, so ids cannot be probed.
5. **Roles.** `viewer` may only read. `clerk` and `admin` may change data. A viewer's change request answers 403
   `forbidden`.
6. **Idempotency.** Every POST accepts an `Idempotency-Key` header. A repeat with the same key and the same body
   returns the first response and changes nothing. The same key with a different body answers 409
   `idempotency_mismatch`. `api.py` does this for every POST route in one place.
7. **Errors** answer `{"error": {"code": ..., "message": ...}}` with a code from `ledger.errors`. Bad input is 400
   `validation`; a request that conflicts with the object's state is 409 `conflict`.
8. **Dates.** A tenant has a timezone. "Today" for a tenant is `clock.today(tenant)`, in that timezone. Dates
   cross the API as ISO strings (`YYYY-MM-DD`).
9. **Soft delete.** Deleting sets `deleted_at`. The store's `get` and `list` never return deleted rows.
10. **Tests** live in `unit/` and use only the standard library.
