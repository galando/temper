---
description: "Run stack-aware validation pipeline"
---

# Check: Validation Pipeline

**Goal:** Auto-detect stack and run validation levels in order.

## Execution

> **Full methodology:** See temper_check tool documentation

### Quick Reference

Levels (stop on failure):
0. Environment — verify not production
1. Compile/Build
2. Unit Tests
3. Integration Tests (if configured)
4. Coverage (threshold from config)
5. Lint/Format
6. Type Check
7. Security (dependency scan)

### Stack Detection

| Stack | Detection | Commands |
|-------|-----------|----------|
| Spring Boot | `pom.xml` / `build.gradle` | `mvn compile`, `mvn test`, `mvn build` |
| React + TS | `package.json` + `tsconfig.json` | `npm test`, `npm run build`, `npm run lint` |
| Node/Express | `package.json` + express | `npm test`, `npm run build`, `npm run lint` |
| FastAPI | `pyproject.toml` + fastapi | `pytest`, `ruff check`, `mypy` |
| Go | `go.mod` | `go test`, `golangci-lint`, `go build` |
| Rust | `Cargo.toml` | `cargo test`, `cargo clippy`, `cargo build` |

### Output Format

```
✅ Level 0: Environment - Not production
✅ Level 1: Compile - Passed
✅ Level 2: Unit Tests - 42 passed
❌ Level 3: Integration Tests - 2 failed

Fix integration tests before proceeding.
```

### Coverage Threshold

Default: 80% for new code
Configurable in `.claude/temper.config`:
```yaml
coverage:
  threshold: 80
  newCodeThreshold: 85
```
