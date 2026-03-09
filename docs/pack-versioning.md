---
title: Pack Versioning
nav_order: 6
---

# Pack Versioning

Packs are just markdown files. Use git for version control.

## Simple Approach

Your pack is a markdown file in `.claude/packs/company/rules.md`. Track changes with git:

```bash
# See what changed
git log --oneline .claude/packs/company/rules.md

# Roll back if needed
git checkout HEAD~1 -- .claude/packs/company/rules.md
```

## Changelog in Pack

Add a changelog section to your pack for human readability:

```markdown
# Company Engineering Standards

## Changelog
- 2025-03-09: Added "no raw SQL" rule
- 2025-02-15: Moved "constructor injection" to BLOCK
- 2025-01-10: Initial version
```

That's it. No lock files, no semantic versioning, no upgrade commands. Just git.
