---
title: Enterprise Setup
nav_order: 5
---

# Enterprise Setup Guide

This guide explains how to deploy Temper across your organization.

## Step 1: Fork and Own

Fork [galando/temper](https://github.com/galando/temper) on GitHub, or mirror it into your
internal git server (for example a `platform/temper` repository), so your platform team owns
the copy your developers install from.

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

### Option B: Use Interactive Pack Builder

In Claude Code, in your project:

```text
/temper:pack
```

At the menu, choose **Other** and describe the pack. Temper scans your codebase, interviews you about conventions, and generates the rules file.

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

Temper is a Claude Code plugin, so teams get it through a plugin marketplace. Copying a folder
of the Temper repository into a project does not install it: the commands, briefs, skills, CLI
and mod live in the plugin's own folders, and the repository's `.claude` folder holds only its
own developer notes and config.

### Option A: Your fork as a marketplace

Your fork carries the marketplace file, so each developer can add it and install from it:

```text
/plugin marketplace add internal/temper
/plugin install temper
```

### Option B: Project settings

To offer it in every session of a project, add your fork's marketplace and enable the plugin in
the project's shared `.claude/settings.json` (the `extraKnownMarketplaces` and `enabledPlugins`
settings). See the [Claude Code plugin docs](https://code.claude.com/docs/en/discover-plugins).

### Option C: Template Repository

Create a template repository with that project settings block and your company packs in
`.claude/packs`. New services inherit from the template.

## Step 5: Team Onboarding

**Day 1 for new developers:**

Clone the project, start Claude Code in it, and accept the plugin when the project settings
offer it. Then run:

```text
/temper:status    # See pre-configured packs and quality metrics
```

No other setup is needed: the project settings bring the plugin, and the project brings its packs.

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
  - git
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
