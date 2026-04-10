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
