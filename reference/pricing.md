---
description: "Advisory per-tier token price table for cost_usd computation"
---

# Pricing Table (Advisory)

_Last updated: 2026-06-19_

These prices are **advisory** and used solely to compute the `cost_usd` field in
`.temper/observability.json` (Deliverable 2, Phase 2). They are NOT a bill. Update this
file as published prices change; the `source: "pricing"` flag on `cost_usd` records that
the value was derived from this table, not measured from an invoice.

Keyed by the tier names in `temper.config models.tiers` (tier-frontier/standard/fast).

## Price Table

| Tier           | input_per_1m (USD) | output_per_1m (USD) | Maps to model  |
|----------------|--------------------|---------------------|----------------|
| tier-frontier  | 15.00              | 75.00               | claude-opus    |
| tier-standard  | 3.00               | 15.00               | claude-sonnet  |
| tier-fast      | 0.80               | 4.00                | claude-haiku   |

## YAML form (machine-parseable alternative)

```yaml
tiers:
  tier-frontier:
    input_per_1m: 15.00
    output_per_1m: 75.00
    model: claude-opus
  tier-standard:
    input_per_1m: 3.00
    output_per_1m: 15.00
    model: claude-sonnet
  tier-fast:
    input_per_1m: 0.80
    output_per_1m: 4.00
    model: claude-haiku
```

## cost_usd computation

```
cost_usd = (input_tokens  / 1_000_000) * tier.input_per_1m
         + (output_tokens / 1_000_000) * tier.output_per_1m
```

When `observability.json` reports `tokens.cached_input > 0` (Phase 3, D1) and
`tokens.cache.enabled` is true, `cost_usd` MAY reflect the cache savings by subtracting the
cache discount: replace `(cached_input / 1_000_000) * tier.input_per_1m` of the input cost
with `(cached_input / 1_000_000) * tier.input_per_1m * cache_read_multiplier` (see Cache
Multipliers below). The `source` stays `"pricing"` (still derived from this table, not a
bill). If the harness does not report cache usage, do not adjust — emit the uncached cost.

Round to 6 decimal places when writing to `observability.json`.

## Cache Multipliers (v5.9.0 — advisory)

Cache read/write multipliers applied to the base input price when the harness reports
`cached_input`. These are **advisory** multipliers sourced from public Anthropic docs; they
do NOT add tiers (the tier table above is unchanged from v5.6.0). Update as published
pricing changes.

| Operation   | Multiplier vs base input | Source (advisory)  |
|-------------|--------------------------|--------------------|
| cache read  | ~0.1x                    | public Anthropic docs |
| cache write | ~1.25x                   | public Anthropic docs |

```
cached_input_cost  = (cached_input  / 1_000_000) * tier.input_per_1m * 0.10   # cache read
cache_write_cost   = (cache_write_tokens / 1_000_000) * tier.input_per_1m * 1.25  # cache write (one-off)
```

## Notes

- Prices reflect public Anthropic API pricing as of the "Last updated" date above. They
  exclude volume discounts and batch-mode pricing. `cost_usd` MAY now reflect cache savings
  when the harness reports `cached_input`; see observability.json `tokens.cached_input` and
  the Cache Multipliers section above. Treat `cost_usd` as an upper-bound advisory when
  cache is off, and a cache-adjusted advisory when cache is on — not an accounting figure.
- The markdown table and the YAML block carry identical data; either is parseable. The
  shell validator (`scripts/validate-phase2.sh schema`) parses the YAML form.
