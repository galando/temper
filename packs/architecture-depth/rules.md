---
phases: [design, review]
---

# Architecture Depth Pack

Module-depth analysis inspired by Matt Pocock's "Deep Modules" philosophy.
Evaluates whether modules earn their complexity through leverage and locality.

## Dimensions

### ARCH-DEPTH-1: Seams — Can modules be replaced without touching others?

**Severity:** WARN
**Category:** architecture
**Detection:** Import graph analysis (MCP) or grep for import/require statements

Check whether modules define clear interfaces that allow replacement:
- Does the module have a well-defined interface (types, exports)?
- Can consumers use the module without knowing its internals?
- Are there adapters wrapping external dependencies?
- One adapter = hypothetical seam. Two adapters = real seam.

### ARCH-DEPTH-2: Adapters — Are external dependencies behind adapter layers?

**Severity:** WARN
**Category:** architecture
**Detection:** Wrapper/facade patterns around APIs, databases, file systems, third-party libs

External dependencies should be behind adapter layers:
- Database calls behind a repository/interface
- HTTP calls behind a client abstraction
- File system access behind a service
- Third-party library usage wrapped in a facade
- Check: if you swapped the external dep, how many files change?

### ARCH-DEPTH-3: Locality — Is related code co-located?

**Severity:** WARN
**Category:** architecture
**Detection:** Directory structure + import distance analysis

Related code should live together:
- Functions that change together should be in the same module
- A bug fix should ideally touch one file
- If understanding one concept requires bouncing between many small modules → shallow
- Apply the deletion test: if deleting the module concentrates complexity, it was pass-through

### ARCH-DEPTH-4: Leverage — Do small changes propagate value broadly?

**Severity:** WARN
**Category:** architecture
**Detection:** Fan-out analysis via dependency graph (MCP) or grep

Modules should provide leverage — small interface, rich behavior:
- Does the module hide complexity behind a simple interface?
- Do callers get significant value from a small surface area?
- Interface nearly as complex as implementation → shallow module
- Changes to the module should benefit all consumers

### ARCH-DEPTH-5: Deletion Test — Can a module be removed without cascading?

**Severity:** WARN
**Category:** architecture
**Detection:** Reverse dependency count + import scan

Apply the deletion test to any module suspected of being shallow:
- Imagine deleting the module
- If complexity vanishes → it was a pass-through (shallow)
- If complexity reappears across N callers → it was earning its keep (deep)
- Count reverse dependencies: high fan-in = deep module
- Zero reverse deps + trivial interface = candidate for removal

## Context Sources

- **CONTEXT.md** (if exists): Domain glossary — use glossary terms when naming modules, validate module naming against domain language
- **docs/adr/** (if exists): Architecture Decision Records — check module compliance with established decisions. Violations of ADRs → BLOCK severity

## Report Format

All findings use `[ARCH-DEPTH]` prefix:

```
[ARCH-DEPTH] {dimension}: {file} — {finding}
  Problem: {why current architecture causes friction}
  Solution: {what would change}
  Benefits: {locality/leverage improvement}
  Severity: {WARN|BLOCK}
```

ADR violations are escalated to BLOCK:

```
[ARCH-DEPTH] {dimension}: {file} — contradicts ADR-{number}
  ADR: {ADR title and decision}
  Violation: {what the code does instead}
  Action: Align with ADR or propose ADR amendment
  Severity: BLOCK
```
