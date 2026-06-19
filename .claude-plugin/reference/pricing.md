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

Round to 6 decimal places when writing to `observability.json`.

## Notes

- Prices reflect public Anthropic API pricing as of the "Last updated" date above. They
  exclude volume discounts, caching, and batch-mode pricing. Treat `cost_usd` as an
  upper-bound advisory, not an accounting figure.
- The markdown table and the YAML block carry identical data; either is parseable. The
  shell validator (`scripts/validate-phase2.sh schema`) parses the YAML form.
