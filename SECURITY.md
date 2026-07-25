# Security Policy

Temper is Markdown and shell: every command, skill, pack, and gate is a prompt file or
a script you can read in this repository. This document is the reporting process, the
supported-version window, and the scope for security issues.

## Reporting a Vulnerability

**Preferred: GitHub private vulnerability reporting.** Open the
[Security tab](https://github.com/galando/temper/security) on this repository and use
"Report a vulnerability" to open a private advisory. This keeps the report
confidential until a fix ships.

*Current status: as of this writing, private vulnerability reporting is not yet
enabled on this repository — the maintainer should enable it under Settings → Security
→ "Private vulnerability reporting" (or via `gh api -X PUT
repos/galando/temper/private-vulnerability-reporting`).* Until it is enabled, or if you
prefer not to use GitHub's flow, email the maintainer directly (see the GitHub profile
at [github.com/galando](https://github.com/galando)) with subject line `SECURITY:
temper`. Do not open a public issue for a suspected vulnerability.

**Acknowledgment expectation:** an initial response within **7 days** of the report.
Fix timelines depend on severity and are communicated in that first response.

## Supported Versions

| Version | Supported |
|---------|-----------|
| 7.x     | ✅ |
| < 7.0   | ❌ |

Only the 7.x line (the deterministic-spine architecture — `scripts/temper`, the
evidence ledger, the native commit-gate hook) receives security fixes. Earlier
releases and the archived Cursor `.cursor/` snapshot are not maintained.

## Scope

**In scope:**
- Bypassing the native git pre-commit hook or the in-agent PreToolUse hook
  (`scripts/hooks/*`) so a FAIL gate does not block `git commit`.
- Gate evasion via any non-human path — forging `.temper/evidence/*.json` or
  `.temper/gates.json` entries so `scripts/temper gate <stage>` reports PASS without
  the underlying claim being true.
- Bypassing the secret-scanner class of hook (`scripts/hooks/block-secrets.sh`) or the
  forbidden-imports guard (`scripts/hooks/block-forbidden-imports.sh`).
- Prompt injection via a generated hook, a generated file (`.cursor/**`), or the
  self-hosted marketplace manifest (`.claude-plugin/marketplace.json`) that causes an
  agent to execute unintended commands.
- Supply-chain issues in the release process (unsigned/tampered tags, release
  artifacts, or the `version-bump.sh` / `release.yml` / `release-bump.yml` workflows).

**Out of scope:**
- Vulnerabilities in third-party MCP servers a user chooses to install
  (`code-review-graph`, `semgrep`, `open-code-review`, etc.) — report those upstream.
- Vulnerabilities in the OCR external-LLM integration itself (`tools.ocr.mode`) —
  Temper's data-flow statement documents this as a conditional, opt-in egress path;
  the OCR tool's own security is out of scope here.
- Issues that require an attacker to already control the local machine, the git
  hooks directory, or the `TEMPER_HOOKS_DIR` / `TEMPER_FORBIDDEN_IMPORTS` /
  `TEMPER_BUILD_STATE` environment overrides — see
  [`docs/security/threat-model.md`](docs/security/threat-model.md) for why this is a
  documented non-goal rather than a vulnerability class.
- Social-engineering reports with no technical finding.

## Safe Harbor

Good-faith security research conducted under this policy — testing against your own
checkout, not against other users' data, and reporting privately before any public
disclosure — will not result in legal action from the maintainer. Please give a
reasonable window to remediate before any public disclosure.

## Related Documents

- [Threat model](docs/security/threat-model.md) — assets, trust boundaries, attacker
  stories, and mitigations.
- [Data-flow statement](docs/security/data-flow.md) — audited network-egress table.
