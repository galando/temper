# Design: {Feature Name}

**Created:** {date}
**Complexity:** {level}
**Based on:** intent.md, plan.md

---

## System Architecture

{Describe the high-level architecture. What components are involved? How do they connect?}

## API Contracts

### {Endpoint Name}

```
{Method} {Path}
Request:  {request body/params}
Response: {response body}
Errors:   {error codes and messages}
```

## Database Changes

### {Table Name}

```sql
-- New table or modification
{SQL schema}
```

## Integration Points

| System | Direction | Protocol | Purpose |
|--------|-----------|----------|---------|
| {name} | inbound/outbound | REST/gRPC/event | {purpose} |

## Decision Log

| Decision | Options Considered | Chosen | Rationale |
|----------|-------------------|--------|-----------|
| {decision} | {options} | {chosen} | {why} |

## Security Considerations

{Any security implications of the design}

## Performance Considerations

{Any performance implications of the design}

## Areas of Concern

{The points an analyst would have escalated — especially anywhere two applicable
policies or pack rules pull in opposite directions, or a constraint from intent.md
cannot be fully satisfied. Name the conflict, the options, and WHO owns the call
(which policy/pack, which person or role). This section is ALWAYS present —
`temper gate design` requires the heading. Nothing to flag? Write
"None flagged — {one line on why}" so the no-concerns claim is explicit, not an
omission. Concerns are resolved by a human before Build, not discovered by Review
after it.}

- {concern} — owner: {policy/pack/person}
