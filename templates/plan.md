# Plan: {Feature Name}

## Architecture

{Description of approach}

## Approach Decisions

<!-- Load-bearing only: record a decision ONLY when a real alternative was genuinely
     considered and rejected. Omit this entire section if no such decision exists.
     One genuine decision is enough. Do NOT fabricate alternatives to fill the section.
     Structure reused from templates/adr.md "Alternatives Considered". -->

### Decision {N}: {chosen approach in one line}
- **Chosen:** {the approach selected, stated specifically — not "use X" but "use X for Y"}
- **Alternative — {name of the rejected alternative}:**
  - **Pros:** {what the alternative had going for it}
  - **Cons:** {what made it worse or riskier}
  - **Why not chosen:** {the specific reason it lost; must reference a concrete tradeoff,
    not a vague "less optimal"}

<!-- Additional decisions follow the same sub-section shape. Add an Alternative block per
     genuine rejected option. Omit Pros/Cons lines only if the alternative is obviously
     inferior AND a one-line "Why not chosen" makes the rejection self-evident. -->

## Diagram

<!-- Legend: new = blue, modified = orange, existing = grey -->
<!-- Generate two blocks: (1) mermaid for GitHub/tools, (2) ASCII for terminal -->

```mermaid
{diagram type and content}
```

```text
{ASCII art equivalent of the diagram above}
{Use +--+ boxes, --> arrows, | lanes for sequences}
{Keep under 80 columns; abbreviate labels if needed}
```

## Blast Radius

{Direct impact, transitive impact, risk areas, architectural compliance}

## Files to Create

| File | Purpose | Traced to |
|------|---------|-----------|
| {path} | {purpose} | {scenario name or Infrastructure: reason} |

## Files to Modify

| File | Change | Traced to |
|------|--------|-----------|
| {path} | {description of change} | {scenario name or Infrastructure: reason} |

## Patterns to Follow

- {pattern}: see {example file}

## Dependencies

- {external library or service dependency}

## Risk Level: {LOW/MEDIUM/HIGH}

{Justification for risk assessment}
