# Recommended Setup

Temper works out of the box with zero configuration. This guide covers optional enhancements that upgrade heuristic analysis to proven findings.

## Live Scenario Verification

No installation needed. Temper uses your project's existing test runner to execute Gherkin scenarios from intent.md individually.

**Configuration** (in `.claude/temper.config`):

```yaml
check:
  live-scenarios: prompt    # prompt | always | never
```

- `prompt` — Ask before running live verification (default)
- `always` — Always run live verification during check
- `never` — Skip live verification, use heuristic analysis only

Works with: Jest, Vitest, pytest, Maven, Gradle, Go test, cargo test.

## Optional MCP Servers

MCP servers provide tool-powered analysis that is mechanically verified (`[PROVEN]`) instead of grep-based heuristics (`[HEURISTIC]`).

### code-review-graph (Blast Radius + Call Chains)

Provides AST-level dependency graphs, call chain tracing, and impact radius analysis.

To set it up, install it by the steps in the
[code-review-graph README](https://github.com/tirth8205/code-review-graph), then add it to
Claude Code as an MCP server named `code-review-graph` (the
[Claude Code MCP docs](https://code.claude.com/docs/en/mcp) show how). Temper does not install it.

### Semgrep (Security Scanning)

Provides SAST scanning for security vulnerabilities. Replaces OWASP pattern-matching with real static analysis.

To set it up, install Semgrep by the steps in the [Semgrep README](https://github.com/semgrep/semgrep),
then add it to Claude Code as an MCP server named `semgrep` that starts Semgrep in its MCP mode
(the Semgrep docs name the option). Temper does not install it.

### open-code-review (Line-Level Defect Engine)

Provides deterministic, file-bundled code review via an external LLM. OCR is off by default. When you turn it on (`tools.ocr.mode: auto` or `require`, see the config below) and `ocr` is on your `PATH`, OCR takes over line-level defect detection (NPEs, injections, thread-safety) during `/temper:review`. Temper keeps intent validation, security analysis, architecture depth, and review memory. Findings are labeled `[OCR]`; cross-validated findings that both engines agree on are labeled `[OCR+TEMPER]`.

To install it, follow the steps in the
[open-code-review README](https://github.com/alibaba/open-code-review). Temper does not install it.

**Verify:**

```bash
ocr --version
ocr review --preview --from HEAD~1 --to HEAD
```

**Configure OCR's model:** OCR needs its own model provider setup. See the [open-code-review docs](https://github.com/alibaba/open-code-review).

**How findings merge into a review** (the mechanics `/temper:review` applies when
`tools.ocr.mode` isn't `off` and `ocr` is ready): Review runs `ocr review --format json
--audience agent` over the diff range under a timeout, parses `comments[]`, and maps
each to a severity/category from its prose (`Critical Bug`/`Vulnerability` → CRITICAL,
`Bug`/`Security Issue` → HIGH, `Warning`/`Performance` → MEDIUM, else LOW; SQLi/XSS/secret
→ security, NPE/null → logic, N+1/query → performance, else quality), labeled `[OCR]`. A
finding within ±2 lines of one Temper already found, same category family, merges to
`[OCR+TEMPER]` at the higher severity. A runtime failure (non-zero/timeout) degrades to
Temper's own review — it never blocks; only `mode: require` with `ocr` *absent* blocks,
and says where to find OCR's install steps.

**Troubleshooting:**

| Issue | Fix |
|-------|-----|
| `ocr: command not found` | Install OCR by the steps in its README (linked above), so `ocr` is on your `PATH` |
| `ocr --preview` fails with LLM error | Set up OCR's model provider (see OCR docs) |
| OCR findings seem wrong | Set `tools.ocr.mode: off` in temper.config to turn it off |
| Review times out with OCR | Increase `tools.ocr.timeout` |

**Config** (in `.claude/temper.config`):

```yaml
tools:
  ocr:
    mode: auto                      # off (the default) | auto | require
    replace-defect-subagent: true   # Drop generic defect hunting when OCR is active
    timeout: 10                     # minutes
```

### tools.mode Configuration

```yaml
tools:
  mode: auto              # auto | heuristic-only | require
  label-findings: true    # Show [PROVEN]/[HEURISTIC]/[SEMANTIC] labels
```

- `auto` — Use MCP tools when available, fall back to heuristics (default)
- `heuristic-only` — Never use MCP tools, always use grep-based analysis
- `require` — Fail if MCP tools are unavailable (for teams that require proven analysis)

## Verify Setup

Run `/temper:status` to check:

- Live scenario verification status
- MCP tool availability (code-review-graph, semgrep)
- Evidence ratio (proven vs heuristic findings)

```
/temper:status
```
