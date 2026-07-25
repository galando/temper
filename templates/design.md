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

## Alternatives Considered

<!-- `temper gate design` requires >=2 entries here for medium/complex features:
     either `### ` subsections or `- ` bullets. One option is not a decision. -->

### {Alternative A}

{What it would look like, and why it was not chosen.}

### {Alternative B}

{What it would look like, and why it was not chosen.}

## Risks

<!-- `temper gate design` requires >=1 `- ` bullet here, and EVERY bullet must
     contain the literal string `Mitigation:`. A risk without a mitigation is a
     wish. -->

- **{risk}** — {what goes wrong and when}. Mitigation: {what makes it survivable}
- **{risk}** — {what goes wrong and when}. Mitigation: {what makes it survivable}

## Security Considerations

{Any security implications of the design}

## Performance Considerations

{Any performance implications of the design}
