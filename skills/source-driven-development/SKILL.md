---
description: "Version-aware, source-driven development — fetch official docs before writing framework code"
---

# Source-Driven Development

**Version:** 1.0.0
**Last Updated:** 2026-05-12

## Overview

Source-driven development ensures that framework-specific code is written against *current* official documentation, not stale training data. AI models often generate code using deprecated APIs, wrong parameter orders, or patterns from older versions. Existing usage in the codebase is not verification either: the codebase may be on an older version, and a passing test proves the code runs, not that the API is current. This skill enforces a verification loop:

```
Detect version → Fetch current docs → Write code with citations → Surface conflicts
```

This skill leverages the Context7 MCP server (if available) to fetch version-specific documentation at build time.

## When to Use

- `/temper:build` or `/temper:fix` writing framework-specific code (React, Spring Boot, Express, FastAPI, etc.)
- Adding or updating a dependency
- Writing code that uses a library API you haven't used recently
- Whenever the agent says "I believe the API works like..."

**Skip when:**
- Writing plain logic (no framework dependency)
- Writing tests for code you just read (you already have the source)
- Modifying config files with known structure

## Process

### Step 1: Read Manifest

Detect the project's dependencies and versions:

1. **JavaScript/TypeScript:** Read `package.json` — extract `dependencies` and `devDependencies`
2. **Java:** Read `pom.xml` or `build.gradle` — extract dependency versions
3. **Python:** Read `pyproject.toml` or `requirements.txt` — extract pinned versions
4. **Go:** Read `go.mod` — extract module versions
5. **Rust:** Read `Cargo.toml` — extract dependency versions

For the specific library you're about to use, note the **exact version** installed.

### Step 2: Fetch Current Documentation

If a documentation MCP server such as Context7 is available: resolve the library to its
ID, query it for the specific API or pattern you need at the installed version, and read
the returned snippets. Use the tool names the server exposes in this session rather than
assuming them.

If no documentation server is available: web-search `{library} v{version} {api}
documentation` and fetch the official docs page with the fetch tool you have. This is
`[HEURISTIC]` rather than `[PROVEN]` — note the evidence level.

### Step 3: Cite Sources

When writing framework-specific code, include a citation comment:

```javascript
// Ref: React 19 useActionState — https://react.dev/reference/react/useActionState
const [state, submitAction, isPending] = useActionState(async (prevState, formData) => {
  // ...
}, initialState);
```

Or in Java:

```java
// Ref: Spring Data JDBC 3.4 @Query — https://docs.spring.io/spring-data/jdbc/reference/repositories/query-methods.html
@Query("SELECT * FROM users WHERE email = :email")
Optional<User> findByEmail(@Param("email") String email);
```

**Citation format:** `{framework} v{version} {api/function} — {url}`

### Step 4: Surface Conflicts

After fetching docs, compare against what you were about to write:

1. **API signature changed?** — parameters added, removed, or reordered
2. **Deprecated pattern?** — the pattern you planned to use is now deprecated
3. **New recommended approach?** — a better pattern exists in the current version
4. **Breaking change?** — the version in the project has a breaking change from what training data suggests

If a conflict is found:
- **BLOCK** if the planned code would use a removed API
- **WARN** if the planned code uses a deprecated but still functional API
- **SUGGEST** if a newer pattern exists but the old one still works

### Step 5: Authority Hierarchy

When multiple documentation sources conflict, use this hierarchy:

1. **Official docs** (react.dev, docs.spring.io, fastapi.tiangolo.com) — highest authority
2. **Type definitions** (DefinitelyTyped, built-in .d.ts) — mechanical truth
3. **Source code** (GitHub repo, node_modules) — ground truth but may be internal
4. **Community** (Stack Overflow, blog posts) — useful for patterns, not API signatures
5. **Training data** (what the model "knows") — lowest authority, always verify

## Red Flags

Watch for these signs that source-driven development would have prevented a problem:

- **"Property X does not exist on type Y"** — you used an API from a different version
- **"Warning: X is deprecated, use Y instead"** — you used training-data knowledge, not current docs
- **Test passes but runtime behavior differs** — API contract changed subtly between versions
- **Code works locally but fails in CI** — dependency version mismatch between environments
- **Import not found** — the module was reorganized in a newer version

## Verification

After writing framework-specific code:

1. **Did you include a citation comment?** If not, add one.
2. **Does the cited URL actually contain the API you used?** Verify, don't hallucinate URLs.
3. **Does the code match the version in the manifest?** Not the latest version — the *installed* version.
4. **Were there any conflicts surfaced in Step 4?** If so, were they resolved?
