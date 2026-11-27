# Recommended Setup

Temper works out of the box with zero configuration. This guide covers optional enhancements that upgrade heuristic analysis to proven findings.

## Live Scenario Verification

No installation needed and no setting: Temper uses your project's existing test runner to execute Gherkin scenarios
from intent.md individually.

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

An agent uses a connected MCP tool when there is one and falls back to a grep based heuristic when there is none; no
setting changes that.

## Verify Setup

During a run, `/temper:temper status` prints each criterion of the intent, passed or open, with its evidence, the
model of each agent, and the line of `temper next --json` that says where the run stands. `temper config show` prints
each key of the config with its value and where it comes from.

```
/temper:temper status
```
