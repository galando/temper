# Design: {Feature Name}

**Created:** {date}
**Complexity:** {medium | complex}
**Based on:** intent.md, plan.md

---

## Areas of Concern

{Always present. Anywhere two applicable rules pull in opposite directions (a pack rule and
a stack pattern, a constraint in intent.md and a security requirement), or a constraint
cannot be fully met: name the conflict, the options, and who owns the call. Give each
concern its own `###` heading. A decided concern carries a line `resolved: {what was
decided}`. With nothing to flag, write `None flagged: {one line on why}`.}

### {Concern}
- Conflict: {what pulls against what}
- Options: {option A} | {option B}
- Owner: {policy, pack or person}

## System Architecture

{The components involved and how they connect.}

## API Contracts

### {Endpoint Name}

```
{Method} {Path}
Request:  {request body or params}
Response: {response body}
Errors:   {error codes and messages}
```

## Database Changes

### {Table Name}

```sql
{schema change}
```

## Integration Points

| System | Direction | Protocol | Purpose |
|--------|-----------|----------|---------|
| {name} | inbound or outbound | REST, gRPC or event | {purpose} |

## Decision Log

| Decision | Options Considered | Chosen | Rationale |
|----------|-------------------|--------|-----------|
| {decision} | {options} | {chosen} | {why} |

## Security Considerations

{Security implications of the design.}

## Performance Considerations

{Performance implications of the design.}
