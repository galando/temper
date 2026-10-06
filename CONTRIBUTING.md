# Contributing to Temper

Thank you for your interest in contributing to Temper! This document provides guidelines and instructions for contributing.

## 🚀 Quick Start

```bash
# Fork and clone
git clone https://github.com/YOUR_USERNAME/temper.git
cd temper

# Create a feature branch
git checkout -b feature/my-improvement

# Make your changes, then run the checks
bash scripts/tests/test-temper.sh
bash scripts/quality-check.sh

# Submit a pull request
git push origin feature/my-improvement
```

To try a change in a real project, open a terminal in that project and start Claude Code with
your clone loaded: `claude --plugin-dir <path of your clone>`. That loads your clone for one
session and installs nothing. Copying a folder of this repository into a project does not
install Temper: the commands, briefs, skills and CLI live in the plugin folders listed below.
[Testing the mod](docs/mods-testing.md) has the full checklist for the mod.

## 📁 Project Structure

```
temper/
├── .claude-plugin/          # Plugin manifest (plugin.json, marketplace.json)
├── .claude/                 # CLAUDE.md + the plugin's own temper.config
├── commands/                # Slash commands (loaded on invocation)
├── agents/                  # Stage subprocess briefs (model frontmatter = defaults)
├── reference/               # Per-stage methodology docs (loaded on demand)
├── skills/                  # Skill definitions (temper-core, grill-me, ...)
├── packs/                   # Rule packs, stack files, guardrails pack
├── scripts/                 # temper CLI (the deterministic spine), guards/, tests/
├── templates/               # Artifact templates (intent/plan/design/config)
├── examples/                # Company packs, CI workflow templates, an example gate
├── docs/                    # GitHub Pages documentation
└── README.md                # Project README
```

The tree leaves out the mod, the plugin's hooks file that loads it, and the mod's tests. After a
change to any of them, run `claude plugin test .`, the type check (`tsc -p tsconfig.mod.json`
with TypeScript 5.6) and `bash scripts/check-mod-calls.sh`.

## 🎯 Ways to Contribute

### Add a New Stack

1. Create a stack file in `packs/stacks/`, named after the stack (for example `packs/stacks/django.md`)
2. Include:
   - Detection patterns (files, dependencies)
   - Validation commands (test, build, lint)
   - Patterns to follow
   - Test patterns
3. Add the stack name to the `stack:` comment in `templates/temper.config.default`

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

1. Create a folder for the pack in `packs/`, named after the pack, with a `rules.md` in it
2. Use sections:
   - `## BLOCK` — Violations stop the build
   - `## WARN` — Violations trigger warning
   - `## SUGGEST` — Informational improvements
3. Add the pack to the built-in list in `reference/pack.md` and to `docs/packs.md`

### Add a New Command

1. Create the command's stub in `commands/`, named after the command (~300B)
2. Create its full docs in `reference/`, under the same name
3. Update `.claude-plugin/plugin.json`
4. Update the commands table in README.md and the command's section in `docs/commands.md`

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

1. **Test your changes**: run the checks above, and try the change in a real project with `claude --plugin-dir`
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

Try Temper in a sandbox before contributing. The
[temper-playground](https://github.com/galando/temper-playground) repository is a small project
with intentional flaws that Temper's gates catch; its README shows how to use it. It is a quick
way to understand how Temper works before contributing.

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
