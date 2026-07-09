---
description: "Architecture depth review: module-depth analysis with seams, adapters, locality, leverage, deletion test"
---

# Architecture Depth Review

**Goal:** Surface shallow modules and propose deepening opportunities — refactors that turn shallow modules into deep ones. Aims for testability and AI-navigability.

Inspired by Matt Pocock's `improve-codebase-architecture` skill.

## Glossary

Use these terms consistently in all findings:

| Term | Definition |
|------|-----------|
| **Module** | Anything with an interface and an implementation (function, class, package, slice) |
| **Interface** | Everything a caller must know to use the module: types, invariants, error modes, ordering, config |
| **Implementation** | The code inside the module |
| **Depth** | Leverage at the interface: lots of behavior behind a small interface. Deep = high leverage. Shallow = interface nearly as complex as implementation |
| **Seam** | Where an interface lives; a place behavior can be altered without editing in place |
| **Adapter** | A concrete thing satisfying an interface at a seam |
| **Leverage** | What callers get from depth |
| **Locality** | What maintainers get from depth: change, bugs, knowledge concentrated in one place |

## When to Trigger

This review runs as an **optional pass** during `/temper:review`:

1. User selects "Architecture Depth Review" at the review gate
2. `architecture-depth` pack is enabled in temper.config
3. Triggered automatically when `capabilities.architecture-depth: true`

## Context Loading

Before analysis, load domain context:

1. **CONTEXT.md** (if exists at project root): Read domain glossary for naming validation
2. **docs/adr/** (if exists): Read Architecture Decision Records for compliance checking
3. **Changed files** from git diff: These are the analysis targets

## Analysis Methodology

### Step 1: Explore

**Check depth budget from agents config:**
- If `depth_remaining > 1`: use Agent tool with `subagent_type=Explore`
- If `depth_remaining <= 1`: explore inline (no subagent)

If spawning is allowed, use the Agent tool with `subagent_type=Explore` to walk the changed files. Explore organically and note where you experience friction:

- Where does understanding one concept require bouncing between many small modules?
- Where are modules **shallow** — interface nearly as complex as the implementation?
- Where have pure functions been extracted just for testability, but the real bugs hide in how they're called (no **locality**)?
- Where do tightly-coupled modules leak across their seams?
- Which parts of the codebase are untested, or hard to test through their current interface?

### Step 2: Score Each Dimension

For each changed file/module, score on a 0-5 scale:

| Score | Meaning |
|-------|---------|
| 0 | No evidence of this dimension |
| 1 | Significant problems detected |
| 2 | Some problems, mostly superficial |
| 3 | Adequate, room for improvement |
| 4 | Well-designed, minor issues |
| 5 | Exemplary, deep module |

**Dimensions:**

1. **Seams** — Can modules be replaced without touching others?
   - Detection: Import graph analysis (MCP) or grep for import statements
   - Score: Number of modules with clear interfaces / total modules

2. **Adapters** — Are external dependencies behind adapter layers?
   - Detection: Wrapper/facade patterns around APIs, databases, file systems
   - Score: Number of external deps wrapped / total external deps

3. **Locality** — Is related code co-located?
   - Detection: Directory structure + import distance
   - Score: Average import distance for related functionality

4. **Leverage** — Do small changes propagate value broadly?
   - Detection: Fan-out analysis via dependency graph
   - Score: Interface surface area vs. behavior delivered

5. **Deletion Test** — Can a module be removed without cascading?
   - Detection: Reverse dependency count + import scan
   - Score: Modules with high fan-in / total modules

### Step 3: Apply Deletion Test

For any module suspected of being shallow, apply the deletion test:

1. Imagine deleting the module
2. If complexity vanishes → it was a pass-through (shallow)
3. If complexity reappears across N callers → it was earning its keep (deep)
4. A "yes, concentrates" is the signal you want — the module was shallow

### Step 4: Present Findings

For each finding:

- **Files** — which files/modules are involved
- **Problem** — why the current architecture causes friction
- **Solution** — plain English description of what would change
- **Benefits** — explained in terms of locality and leverage, and also in how tests would improve

**Use CONTEXT.md vocabulary for the domain, and this glossary's vocabulary for the architecture.** If CONTEXT.md defines "Order," talk about "the Order intake module" — not "the FooBarHandler."

**ADR conflicts:** If a finding contradicts an existing ADR, only surface it when the friction is real enough to warrant revisiting the ADR. Mark it clearly (e.g. _"contradicts ADR-0007 — but worth reopening because…"_).

### Step 5: Severity Classification

| Condition | Severity |
|-----------|----------|
| ADR violation | BLOCK |
| Shallow module with 5+ consumers | WARN |
| Missing adapter for external dep | WARN |
| Low locality (bouncing required) | WARN |
| Deletion test shows pass-through | SUGGEST |

## Integration with Review Pipeline

Findings are added to the main review findings list with `[ARCH-DEPTH]` prefix. They follow the same confidence scoring and filtering as other review findings.

The architecture depth review is additive — it does not replace any existing review steps. It runs after the standard review completes.
