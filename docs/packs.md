---
title: Packs
nav_order: 4
---

# Packs

Packs are collections of rules that Temper uses to validate and guide AI-generated code.

## Built-in Packs

Temper ships with 4 quality packs:

### `quality`

Code quality rules — method length, DRY, naming conventions.

**Rules include:**

- Methods max 30 lines
- Classes max 300 lines
- No duplicate code blocks
- Descriptive naming
- Single responsibility

### `tdd`

Test-driven development — RED-GREEN-REFACTOR cycle.

**Rules include:**

- Write test first
- Tests must fail initially (RED)
- Minimal implementation (GREEN)
- Refactor with tests passing
- Coverage thresholds

### `security`

Security best practices — OWASP Top 10.

**Rules include:**

- No SQL injection
- No XSS vulnerabilities
- Input validation
- Secure password storage
- No secrets in code
- HTTPS enforcement

### `git`

Git workflow — conventional commits, branching strategy.

**Rules include:**

- Conventional commit format
- Branch naming conventions
- No force push
- Atomic commits
- Meaningful commit messages

## Creating Custom Packs

**Recommended:** Use `/temper:standards` to create packs interactively. Temper scans your codebase, asks about your preferences, and generates a custom `rules.md` tailored to your team.

### Manual Creation

```
.claude/
└── packs/
    └── my-pack/
        └── rules.md
```

### Rules Format

```markdown
# My Custom Pack

## BLOCK (Violations stop the build)

- Never expose database entities in API responses
- All external calls must have timeout
- No hardcoded credentials

## WARN (Violations trigger warning)

- Methods should not exceed 30 lines
- Avoid nested conditionals deeper than 3 levels
- Use meaningful variable names

## SUGGEST (Violations shown as tips)

- Consider extracting magic numbers to constants
- Add JSDoc for public functions
- Use early returns to reduce nesting
```

### Severity Levels

| Level | Behavior |
|-------|----------|
| `BLOCK` | Stops the build/commit. Must fix. |
| `WARN` | Shows warning. Can proceed, but should fix. |
| `SUGGEST` | Informational. Nice to have. |

## Enabling Packs

Edit `.claude/temper.config`:

```yaml
packs:
  - quality
  - tdd
  - security
  - my-custom-pack  # Your pack
```

## Pack Discovery

Temper automatically discovers packs in `.claude/packs/`. Just create the folder and add `rules.md`.

## Company Packs

For enterprise deployments, see [Enterprise Setup](enterprise).

### Example: Company Pack

```markdown
# Acme Corp Engineering Standards

## BLOCK (Security & Architecture)

- All API endpoints require authentication
- PII must be encrypted at rest
- No raw SQL queries — use ORM
- All external API calls through gateway

## WARN (Quality)

- Constructor injection only
- Structured logging with correlationId
- No magic numbers — use constants
- Max cyclomatic complexity: 10

## SUGGEST (Conventions)

- Use Optional instead of null
- Prefer immutable data structures
- Add integration tests for API endpoints
```

## Versioning

Packs are just markdown files. Use git for version control.

```bash
# See what changed
git log --oneline .claude/packs/company/rules.md

# Roll back if needed
git checkout HEAD~1 -- .claude/packs/company/rules.md
```

See [Pack Versioning](pack-versioning) for more details.
