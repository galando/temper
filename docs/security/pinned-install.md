# Pinned-Version Install

The default install (README Quickstart) tracks the repo's default branch or the
marketplace's latest listing — convenient, but not reproducible. This document records
the ref/tag pinning support that was empirically verified (2026-07 — never guessed) and
the install path that gives you a reproducible, verifiable checkout.

## Pinning support (verified)

| Vendor | Native ref/tag pinning? | Evidence |
|--------|--------------------------|----------|
| **Claude Code** | ❌ Not on `marketplace add` | `claude plugin marketplace add --help` (run directly, 2026-07) exposes only `--scope` and `--sparse` — no ref/tag/version flag. `claude plugin install <plugin>` accepts a `plugin@marketplace` form, but that `@marketplace` selects *which configured marketplace* to install from, not a version — verified via `claude plugin install --help`. The fallback below is the pinning path for Claude Code today. |

## The always-works fallback: clone at a signed tag

```bash
# 1. Clone and check out the exact release you want.
git clone https://github.com/galando/temper.git
cd temper
git checkout v7.0.1

# 2. Verify the tag is signed by the maintainer (once release signing ships).
git tag -v v7.0.1

# 3. Add the LOCAL checkout as a marketplace source (Claude Code — verified):
#    /plugin marketplace add /path/to/this/checkout
```

This sidesteps remote-pinning support entirely — you already have the exact, verified
commit on disk, and you're just pointing the plugin system at that local directory
instead of a remote URL. It's the one instruction here that doesn't depend on an
evolving vendor CLI surface.

## Verifying a release artifact

Every release publishes a source tarball, `checksums.txt`, and a build-provenance
attestation:

```bash
gh attestation verify temper-v7.0.1.tar.gz --repo galando/temper
sha256sum -c checksums.txt
```

## Summary for the impatient

Clone at the tag, verify it, add the local path as a marketplace source. That is the
reproducible install today.
