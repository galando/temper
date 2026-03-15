---
title: Enterprise Setup
nav_order: 5
---

# Enterprise Setup Guide

This guide explains how to deploy Temper across your organization.

## Step 1: Fork and Own

```bash
# Clone the official Temper repo
git clone https://github.com/galando/temper.git && cd temper

# Remove the original git history and start fresh
rm -rf .git && git init

# Add your internal remote
git remote add origin https://gitlab.internal.company.com/platform/temper.git

# Commit and push
git add -A && git commit -m "feat: import Temper v1.0"
git push -u origin main
```

**Why fork?**

- Full control over updates
- No external dependencies
- Security team can audit
- Customize for your needs

## Step 2: Add Company Standards

### Option A: Write Manually

Create `.claude/packs/{company}/rules.md`:

```markdown
# {Company} Engineering Standards

## Mandatory Rules (BLOCK if violated)
- Never expose entities in API responses, use DTOs
- All database access through repository layer
- PII must be encrypted at rest
- No secrets in source code

## Quality Rules (WARN if violated)
- Methods max 30 lines, classes max 300 lines
- Constructor injection only
- Structured logging with correlationId

## Conventions (SUGGEST improvements)
- Error codes follow {COMPANY-XXXX} format
- Branch names: feature/{ticket}-{description}

## Architectural Constraints (BLOCK if violated)
- All external API calls go through gateway service
- No circular dependencies between domain modules
- Event consumers must be idempotent
```

### Option B: Use Interactive Builder

```
cd your-project
/temper:standards
```

This scans your codebase, interviews you about conventions, and generates the rules file.

## Step 3: Create Stack Preset

Create `.claude/presets/{company}-{stack}.yaml`:

```yaml
name: company-microservice
description: "Standard company Java microservice"

stack:
  runtime: java-21
  framework: spring-boot-3.2
  database: postgresql
  orm: spring-data-jdbc
  tests: junit5 + testcontainers
  build: gradle

validation:
  compile: "./gradlew compileJava"
  unit-test: "./gradlew test"
  integration-test: "./gradlew integrationTest"
  coverage: "./gradlew jacocoTestReport"
  lint: "./gradlew checkstyleMain"
  security: "./gradlew dependencyCheckAnalyze"
  build: "./gradlew build"

packs:
  - quality
  - tdd
  - security
  - company

review:
  block-on: [critical, high]
  auto-fix: true

branch:
  pattern: "feature/{ticket}-{description}"
  commit-style: conventional
```

## Step 4: Distribute to Teams

### Option A: Mono-repo

Copy the entire `.claude/` directory into each project:

```bash
# In each project
cp -r /path/to/temper/.claude .
```

### Option B: Git Submodule

```bash
# In each project
git submodule add https://gitlab.internal.company.com/platform/temper.git .claude-temper
ln -s .claude-temper/.claude .claude
```

### Option C: Template Repository

Create a template repository with Temper pre-configured. New services inherit from the template.

### Option D: Internal Plugin Registry

If you have an internal plugin marketplace:

```bash
/plugin marketplace add internal/temper
/plugin install temper
```

## Step 5: Team Onboarding

**Day 1 for new developers:**

```bash
git clone project
cd project
/temper:status    # See pre-configured standards, packs, and metrics
```

No setup required. Everything is pre-configured.

## Configuration Reference

### temper.config

```yaml
# Stack override (auto-detect by default)
stack: auto

# Enabled packs
packs:
  - quality
  - tdd
  - security
  - company    # Your company pack

# Planning options
plan:
  default-depth: auto

# Review options
review:
  block-on: [critical, high]  # Block on these severities
  auto-fix: true
  confidence-threshold: 0.7

# Check options
check:
  coverage-threshold: 85
  debt-tracking: true

# Branch conventions
branch:
  pattern: "feature/{COMPANY}-{ticket}-{description}"
  commit-style: conventional
```

## Governance

### Updating Standards

1. Update the rules file in your forked Temper repo
2. Version the change (tag with v1.1, v1.2, etc.)
3. Teams pull the update when ready

### Rollout Strategy

- Start with SUGGEST rules (non-blocking)
- Graduate to WARN rules after team feedback
- Use BLOCK rules only for critical security/architecture

### Metrics Collection

Each project's `.temper/metrics.json` tracks:

- Reviews run, issues found, auto-fixed
- Coverage trends
- Pattern frequencies

Aggregate these across projects to measure improvement.

## Support

- Internal: Your platform team
- Upstream: <https://github.com/galando/temper/issues>
