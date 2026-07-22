# Pinned-Version Install

Every vendor's *default* install (README Quickstart) tracks the repo's default branch
or the marketplace's latest listing — convenient, but not reproducible. This document
is the investigation into per-vendor ref/tag pinning support (empirically verified,
2026-07 — never guessed) and the install path that works for everyone regardless of
what a given vendor's marketplace mechanism supports.

## Per-vendor pinning support (verified)

| Vendor | Native ref/tag pinning? | Evidence |
|--------|--------------------------|----------|
| **Codex CLI** | ✅ Yes — `--ref` | `codex marketplace add <source> --ref <ref>` accepts a branch, tag, or commit (verified directly against [openai/codex PR #17087](https://github.com/openai/codex/pull/17087), which added source parsing for local dirs/GitHub-shorthand/git URLs with an optional `--ref`). |
| **Gemini CLI** | ✅ Yes — `--ref` | `gemini extensions install <source> --ref <ref>` accepts a branch, tag, or commit, and `gemini extensions update` is required to pull further changes (extensions are copied at install time, not tracked live) — verified against the official [Gemini CLI extensions reference](https://github.com/google-gemini/gemini-cli/blob/main/docs/extensions/reference.md). |
| **Claude Code** | ❌ Not on `marketplace add` | `claude plugin marketplace add --help` (run directly, 2026-07) exposes only `--scope` and `--sparse` — no ref/tag/version flag. `claude plugin install <plugin>` accepts a `plugin@marketplace` form, but that `@marketplace` selects *which configured marketplace* to install from, not a version — verified via `claude plugin install --help`. The always-works fallback below is the pinning path for Claude Code today. |
| **Cursor** | ⚠️ Unverified | As documented in `docs/security/threat-model.md` Trust Boundary #1 and the README's Cursor install note: Cursor's official docs (cursor.com/docs/plugins, cursor.com/docs/reference/plugins) do not yet document a mechanism for registering a third-party repo as a custom marketplace source at all, so a ref-pinning flag on top of that is moot until the base mechanism is documented. Do not assert one exists. |

## The always-works fallback: clone at a signed tag

This works today for every vendor that can point at a local path as a source (verified
for Claude Code; the same idea applies to Codex, which supports local-directory
sources per PR #17087):

```bash
# 1. Clone and check out the exact release you want.
git clone https://github.com/galando/temper.git
cd temper
git checkout v7.0.1

# 2. Verify the tag is signed by the maintainer (once release signing ships — Task 12).
git tag -v v7.0.1

# 3. Add the LOCAL checkout as a marketplace source (Claude Code — verified):
#    /plugin marketplace add /path/to/this/checkout
#    Codex (local-directory source, per PR #17087):
#    codex marketplace add /path/to/this/checkout
```

This sidesteps every vendor's own remote-pinning support entirely — you already have
the exact, verified commit on disk, and you're just pointing the vendor's plugin
system at that local directory instead of a remote URL. It's the one instruction in
this document that doesn't depend on any vendor's evolving CLI surface.

## Summary for the impatient

- **Codex, Gemini:** use `--ref v7.0.1` on the native install command (README
  Quickstart) — no extra steps needed.
- **Claude Code, Cursor (or anyone who wants a locally-verified checkout regardless of
  vendor):** clone at the tag, verify it, add the local path as a marketplace source.
