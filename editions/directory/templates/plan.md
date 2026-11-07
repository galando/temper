# Plan: {Feature Name}

**Complexity:** {trivial | simple | medium | complex}
**Risk:** {L | M | H}

## Context Map

- use: {a source of context and why; one line per source, an area is one line: src/auth/ (12 files)}
- ignore: {a source that looks related and is not, and why}
- gap: {something the plan needs that the sources do not give}

## Architecture

{The approach, in a few paragraphs.}

## Approach Decisions

{Only when a real alternative was considered and rejected. Leave the section out when no
such choice was made. One real decision is worth more than three padded ones.}

### Decision 1: {chosen approach in one line}
- **Chosen:** {the approach, stated specifically}
- **Alternative: {name}**
  - **Pros:** {what it had going for it}
  - **Cons:** {what made it worse or riskier}
  - **Why not chosen:** {a concrete constraint, risk or cost a reviewer could challenge}

## Diagram

```mermaid
{flowchart, sequenceDiagram, stateDiagram-v2 or classDiagram; under 30 nodes}
```

```text
{the same diagram as ASCII box art, under 80 columns, for the terminal}
```

## Blast Radius

{Required for medium and complex. Every row comes from something you opened or grepped.}

```
BLAST RADIUS: {feature}
  Direct impact:     {file} ({action}) → used by {N} consumers
  Transitive impact: {module} → calls {changed function}()
  Risk areas:        {module} has {X}% coverage for {path}
  Architectural compliance: [ok]/[warn] {pattern}
```

## Cross-Repo Search

- used: {tool}: {query} → {finding}
- not available: {reason}

## Files to Create

| File | Purpose | Traced to |
|------|---------|-----------|
| {path} | {purpose} | {Scenario: "name" or Infrastructure: reason} |

## Files to Modify

| File | Change | Traced to |
|------|--------|-----------|
| {path} | {change} | {Scenario: "name" or Infrastructure: reason} |

## Patterns to Follow

- {pattern}: see {example file}

## Dependencies

- {external library or service}
