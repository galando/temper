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
├── .claude-plugin/          # Plugin manifest and reference docs
│   ├── plugin.json          # Plugin metadata
│   ├── marketplace.json     # Marketplace entry
│   └── reference/           # Full command documentation (loaded on-demand)
├── .claude/                 # Core plugin files
│   ├── CLAUDE.md            # Always-loaded context (~200B)
│   ├── commands/            # Command stubs (loaded on invocation)
│   ├── skills/              # Core skill definitions
│   └── packs/               # Rule packs and stack files
├── templates/               # Plan artifact templates
├── examples/                # Example company packs and presets
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

### Vendor Adapters (Codex, Cursor, Gemini) — maintainer/CI tooling only

`adapters/codex/`, `adapters/cursor/`, `adapters/gemini/`, `.agents/plugins/marketplace.json`,
and `.cursor-plugin/marketplace.json` are **generated, committed output** — never
hand-edit them. They're derived from the same single source of truth as the Claude
Code plugin (`commands/*.md`, `skills/temper-core/SKILL.md`, `.claude-plugin/plugin.json`)
by three generator scripts:

```bash
scripts/generate-codex.sh           # -> adapters/codex/ + .agents/plugins/marketplace.json
scripts/generate-cursor-plugin.sh   # -> adapters/cursor/ + .cursor-plugin/marketplace.json
scripts/generate-gemini.sh          # -> adapters/gemini/
```

**These are maintainer/CI build tooling — never an end-user install step.** End users
install the *committed* output natively (marketplace source + in-agent install; see the
README's [Adapter Tier Matrix](README.md#adapter-tier-matrix)). If you change a command,
skill, or `plugin.json` version, re-run all three generators and commit the diff — CI
(`scripts/validate-adapters.sh`) fails the build if generated output has drifted from
source. Shared extraction/rewrite logic lives in `scripts/adapters/lib.sh`.

`scripts/generate-cursor.sh` (the legacy `.cursor/` snapshot generator) and
`scripts/install-cursor.sh` are frozen — do not modify them; they exist only for
existing consumers of the archived v5.1 Cursor snapshot.

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

## 🏷️ Release Process (maintainer)

**Tag convention: `vX.Y.Z`, always.** `release.yml` triggers only on `v*` tag pushes;
tags without the prefix (e.g. bare `7.0.0`) do not trigger a release and are not a
supported release path. (Two releases were cut this way before the convention was
normalized here — see git history; `release.yml`'s previous-tag lookup tolerates the
mixed history without a code change, since `git describe`/`git log <ref>..HEAD` don't
care about naming convention — verified during this pass.)

1. Run `release-bump.yml` (or `scripts/version-bump.sh <version>` locally) — bumps all
   version stamps, regenerates the three vendor adapters, inserts a CHANGELOG entry.
2. After merge, tag **signed**: `git tag -s vX.Y.Z -m "vX.Y.Z"` then `git push --tags`.
3. `release.yml` creates the GitHub Release with a source tarball, `checksums.txt`,
   and a `actions/attest-build-provenance` attestation — see
   [`docs/security/pinned-install.md`](docs/security/pinned-install.md) for how a user
   verifies a release (`git tag -v`, `gh attestation verify`, `sha256sum -c`).

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
