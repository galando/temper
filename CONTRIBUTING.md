# Contributing to Temper

Thank you for your interest in contributing to Temper! This document provides guidelines and instructions for contributing.

## 🚀 Quick Start

```bash
# Fork and clone
git clone https://github.com/YOUR_USERNAME/temper.git
cd temper

# Create a feature branch
git checkout -b feature/my-improvement

# Make your changes
# ...

# Test in a real project
cp -r .claude /path/to/test-project/

# Submit a pull request
git push origin feature/my-improvement
```

## 📁 Project Structure

```
temper/
├── .claude-plugin/          # Plugin manifest (plugin.json, marketplace.json)
├── .claude/                 # CLAUDE.md + the plugin's own temper.config
├── commands/                # Slash commands (loaded on invocation)
├── agents/                  # Stage subprocess briefs (model frontmatter = defaults)
├── reference/               # Per-stage methodology docs (loaded on demand)
├── skills/                  # Skill definitions (temper-core, grill-me, ...)
├── packs/                   # Rule packs, stack files, hooks pack
├── hooks/                   # Plugin-shipped hooks.json (stage-gate pair)
├── scripts/                 # temper CLI (the deterministic spine), hooks/, tests/
├── templates/               # Artifact templates (intent/plan/design/config)
├── evals/                   # Seeded-defect fixtures + wiring smoke (CI-run)
├── examples/                # Company packs, CI workflow templates, example hooks
├── docs/                    # GitHub Pages documentation
└── README.md                # Project README
```

## 🎯 Ways to Contribute

### Add a New Stack

1. Create `packs/stacks/{stack-name}.md`
2. Include:
   - Detection patterns (files, dependencies)
   - Validation commands (test, build, lint)
   - Patterns to follow
   - Test patterns
3. Update README.md supported stacks table

**Example:**
```markdown
# packs/stacks/django.md

## Detection
- manage.py in root
- settings.py with Django config
- requirements.txt with django

## Commands
- test: python manage.py test
- build: python manage.py collectstatic --noinput
- lint: ruff check .
```

### Add a New Pack

1. Create `packs/{pack-name}/rules.md`
2. Use sections:
   - `## BLOCK` — Violations stop the build
   - `## WARN` — Violations trigger warning
   - `## SUGGEST` — Informational improvements
3. Update README.md packs table

### Add a New Command

1. Create `commands/{command}.md` (stub, ~300B)
2. Create `reference/{command}.md` (full docs)
3. Update `.claude-plugin/plugin.json`
4. Update README.md commands table

### Improve Documentation

- Fix typos or unclear sections
- Add examples
- Improve the GitHub Pages site

## 📏 Guidelines

### Context Budget

Keep always-loaded content minimal:
| File | Target Size |
|------|-------------|
| CLAUDE.md | ~200B |
| SKILL.md | ~1KB |
| Command stubs | ~300B each |
| Reference docs | Can be larger (loaded on-demand) |

### Code Style

- Use markdown for all content
- Follow existing formatting patterns
- Keep lines under 80 characters where possible
- Use relative links within the repo

### Commit Style

Use conventional commits:

```
feat: add Django stack support
fix: correct Spring Boot detection pattern
docs: improve installation instructions
refactor: simplify blast radius logic
```

## 🔍 Pull Request Process

1. **Test your changes** — Copy `.claude/` to a real project and verify
2. **Update documentation** — If adding features, update relevant docs
3. **Keep commits atomic** — One logical change per commit
4. **Write clear descriptions** — Explain what and why

### PR Checklist

- [ ] Tested in a real project
- [ ] Updated documentation if needed
- [ ] Followed context budget guidelines
- [ ] Commits follow conventional format
- [ ] No unrelated changes

## 🎮 Playground

Try Temper in a sandbox before contributing:

```bash
git clone https://github.com/galando/temper-playground
cd temper-playground
# Follow the README to see Temper's gates in action
```

The playground has intentional flaws that Temper's gates catch — a quick way to understand how Temper works before contributing.

## 🤝 Code of Conduct

- Be respectful and inclusive
- Welcome newcomers
- Focus on constructive feedback
- Assume good intentions

## 📬 Questions?

- Open an issue for bugs or feature requests
- Start a [GitHub Discussion](https://github.com/galando/temper/discussions) for questions
- Check [Good First Issues](https://github.com/galando/temper/labels/good%20first%20issue) for beginner-friendly contributions

---

Thank you for helping make Temper better!
