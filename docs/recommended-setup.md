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

```bash
pip install code-review-graph
```

Then configure in your Claude Code MCP settings:

```bash
claude mcp add code-review-graph -- code-review-graph
```

### Semgrep (Security Scanning)

Provides SAST scanning for security vulnerabilities. Replaces OWASP pattern-matching with real static analysis.

```bash
brew install semgrep
claude mcp add semgrep -- semgrep --mcp
```

### open-code-review (Line-Level Defect Engine)

Provides deterministic, file-bundled code review via an external LLM. When installed, OCR takes over line-level defect detection (NPEs, injections, thread-safety) during `/temper:review`. Temper keeps intent validation, security analysis, architecture depth, and review memory. Findings are labeled `[OCR]`; cross-validated findings that both engines agree on are labeled `[OCR+TEMPER]`.

```bash
npm install -g @alibaba-group/open-code-review
```

**Verify:**

```bash
ocr --version
ocr review --preview --from HEAD~1 --to HEAD
```

**Configure OCR's LLM:** OCR needs its own LLM configuration (API key, model). See the [open-code-review docs](https://github.com/alibaba/open-code-review) for setup.

**Troubleshooting:**

| Issue | Fix |
|-------|-----|
| `ocr: command not found` | Run `npm install -g @alibaba-group/open-code-review` |
| `ocr --preview` fails with LLM error | Configure OCR's LLM settings (see OCR docs) |
| OCR findings seem wrong | Adjust `tools.ocr.mode: off` in temper.config to disable |
| Review is slow with OCR | Lower `tools.ocr.concurrency` or increase `tools.ocr.timeout` |

**Config** (in `.claude/temper.config`):

```yaml
tools:
  ocr:
    mode: auto                      # auto | off | require
    replace-defect-subagent: true   # Drop generic defect hunting when OCR is active
    timeout: 10                     # minutes
    concurrency: 8
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
