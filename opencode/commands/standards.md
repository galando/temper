---
description: "Build team engineering standards interactively"
---

# Standards: Interactive Standards Builder

**Goal:** Scan codebase for patterns, interview about conventions, generate company pack + preset.

## Execution

> **Full methodology:** See temper_standards tool documentation

### Quick Reference
1. Scan codebase via exploration (patterns, consistency, inconsistencies)
2. Interview developer (5-10 questions about conventions)
3. Generate `.claude/packs/{company}/rules.md` + preset
4. Validate against current codebase, set baseline

### Scan Codebase For

- **Patterns**: Common coding patterns used
- **Consistency**: Are patterns followed consistently?
- **Inconsistencies**: Where do patterns diverge?
- **Test coverage**: What's tested? What's not?
- **Naming conventions**: Variable, function, class names
- **File organization**: Directory structure patterns

### Interview Questions

Examples:
- "I see methods typically have 15-20 lines. What's your preferred max?"
- "Error handling uses Result types. Should this be enforced?"
- "Tests use Given-When-Then. Is this a team standard?"
- "API responses use DTOs. Should this be a BLOCK rule?"

### Generate Pack

Create `.claude/packs/{company}/rules.md`:

```markdown
# {Company} Standards

**Version:** 1.0.0
**Last Updated:** {date}

## BLOCK
- [Mandatory rules from interview]

## WARN
- [Quality rules from interview]

## SUGGEST
- [Conventions from interview]
```

### Create Preset (optional)

```yaml
# .claude/presets/{company}.yaml
stack: spring-boot
packs:
  - quality
  - tdd
  - security
  - {company}
```

### Validate

1. Run pack against current codebase
2. Check for false positives
3. Set baseline (current issues are "known")
