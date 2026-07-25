# Data-Flow Statement

**Claim: zero network egress by default** for the core enforcement surface
(`scripts/temper` and `scripts/hooks/*`) — audit-verified, not asserted. This is
deliberately a *qualified* claim, not "nothing ever leaves the machine": the table
below enumerates every conditional egress path this repository can produce, each with
its off switch, so the qualified claim is checkable rather than taken on faith.

## Audited core: always zero egress

```
grep -nE 'curl|wget|nc |urllib|requests|socket|http\.client|ftp://' scripts/temper scripts/hooks/*.sh
```

returns no matches, verified as of this writing. `scripts/temper` is bash +
python3-stdlib only (`json`, `hashlib`, `os`, `sys` — no `urllib`/`requests`/`socket`);
`scripts/hooks/*.sh` are git/grep/python3 local-file operations only. Neither
component makes, nor can silently be made to make, a network call without a code
change — and a CI guard (below) now fails the build the moment one is introduced.

| Component | Egress | Verdict |
|-----------|--------|---------|
| `scripts/temper` (state/evidence/gate/override/report) | None | Zero egress, always |
| `scripts/hooks/*.sh` (all four hooks + install.sh) | None | Zero egress, always |

## Conditional egress paths (enumerated, each with its disable switch)

Everything else in the repository that *can* produce network traffic is optional,
user-initiated, and listed here — not folded into the "core" claim above.

| Path | What leaves the machine | Trigger | Disable switch |
|------|--------------------------|---------|------------------|
| OCR (`tools.ocr.mode`) | **Code content** sent to the OCR tool's configured external LLM (Alibaba `open-code-review` today) for defect detection. | Enabled in `.claude/temper.config` under `tools:` and the tool is installed. | Set `tools.ocr.mode: off` (or leave the optional tool uninstalled — the default). |
| Optional MCP servers (`tools.mode`) | Depends on which MCP servers are registered — `code-review-graph` and `semgrep` run as local processes today (no network by design), but MCP servers are third-party code and a user could register one that does call out. | A server is registered via `claude mcp add ...` and Temper's `tools.mode` allows using it. | Set `tools.mode: heuristic-only` to disable MCP-backed analysis entirely; only register MCP servers you trust. |
| Plan-stage issue-tracker fetch | Outbound request to GitHub/Jira for the issue referenced (`gh`/`curl` under the hood in the Plan agent's tooling), when a user passes a ticket reference to `/temper:plan`. | User-initiated: passing a JIRA-123 / #456 style reference as the plan argument. | Don't pass an issue reference — describe the feature in plain text instead. |
| `scripts/install-cursor.sh` remote mode | `curl` from `raw.githubusercontent.com` to fetch `.cursor/` files. | Running `install-cursor.sh` directly (legacy, in-tree, deprecated). | Don't run it. The `.cursor/` snapshot it fetches is archived at the v6.0.1 feature set and is not an install path the README documents; it remains in-tree only for consumers who already depend on that snapshot. |

**Framing note:** the legacy `install-cursor.sh` remote mode is *present in-tree,
deprecated, and **not** an end-user path* — the Claude Code plugin install documented
in the README's Quickstart makes no such call. It is listed here as a conditional
egress path because the file still exists and still works if hand-run; it is not listed as
part of the "audited core" because it is not part of the enforcement surface
(`scripts/temper` / `scripts/hooks/*`) this document's zero-egress claim covers.

## CI Guard

`scripts/validate-plugin.sh` greps `scripts/temper` and `scripts/hooks/` for network
primitives (`curl`, `wget`, `nc `, `urllib`, `requests`, `socket`) on every push/PR (via
`.github/workflows/quality.yml`). If a future change introduces one of these into the
core enforcement surface, the build goes red — the "zero egress, always" row above is
enforced mechanically, not just documented.

## README Alignment

The README's Security & Trust section states "No network calls, no telemetry" for the
core CLI + hooks, linking here for the qualified version and the conditional-path
table — the unqualified README bullet and this document's qualified claim describe the
same audited reality, worded for two different levels of detail.
