# Evidence: Feature Comparison

## Temper vs. Alternatives

An honest comparison of AI code quality approaches. Every cell is factually accurate as of Temper v5.2.0. Where a tool doesn't claim a capability, we say so rather than guessing.

### Feature Matrix

| Capability | Temper | Claude Code Default | Cursor Built-in | CodeRabbit |
|-----------|--------|--------------------|--------------|------------|
| **Intent validation** | Yes — IDD with mechanical validate types | No | No | No |
| **BDD scenarios** | Yes — derived before architecture | No | No | No |
| **File-to-scenario traceability** | Yes — prevents over-engineering | No | No | No |
| **Scenario coverage gate** | Yes — blocks build if uncovered | No | No | No |
| **Blast radius analysis** | Yes — with MCP graph support | No | No | Partial (diff context) |
| **Security hot paths** | Yes — traced to entry points | No | No | Yes (SAST rules) |
| **Evidence labels** | Yes — [PROVEN]/[HEURISTIC]/[SEMANTIC] | No | No | No |
| **External engine integration** | Yes — open-code-review (Alibaba) | No | No | Proprietary engine |
| **TDD enforcement** | Yes — RED-GREEN-REFACTOR from scenarios | No | No | No |
| **Stage gates** | Yes — approve/reject at each stage | No | No | Review-only |
| **Feedback loops** | Yes — Review→Build, Check→Build | No | No | No |
| **Quality packs** | Yes — 7 built-in + custom | No | Partial (rules) | Partial (config) |
| **Adaptive learning** | Yes — pattern detection + noise reduction | No | No | No |
| **Config suggestions** | Yes — CLAUDE.md/AGENTS.md updates | No | No | No |
| **Socratic plan challenge** | Yes — "Grill Me" mode | No | No | No |
| **HTML plan review** | Yes — browser-based comments | No | No | No |
| **Architecture depth** | Yes — 5-dimension module analysis | No | No | No |
| **Observability** | Yes — per-stage metrics | No | No | Partial |
| **Stack auto-detection** | Yes — 6 stacks | Partial | No | Partial |
| **MCP integration** | Yes — code-review-graph, semgrep | Yes (native) | No | No |
| **Multi-IDE support** | Claude Code + Cursor | Claude Code | Cursor | Any (CI) |
| **Cost** | Free, open source | Included | Included | Freemium |

### What Each Tool Does Best

**Temper:** Catches the bugs AI coding tools systematically miss — missing edge cases, over-engineering, wrong problem solved. Adds structured quality gates that enforce intent validation, scenario coverage, and security analysis. Best for developers who want AI to write code but need assurance it's correct.

**Claude Code Default:** Fast code generation with good code quality out of the box. Claude writes clean, idiomatic code. Best for developers who trust AI output and want maximum speed.

**Cursor Built-in:** IDE-integrated AI assistance with autocomplete, chat, and code generation. Best for developers who want AI tightly integrated into their editor workflow.

**CodeRabbit:** Automated code review on pull requests with AI-powered analysis. Best for teams that want review automation on every PR without changing their development workflow.

### When Temper Helps Most

- Building features with security implications (auth, payments, data handling)
- Working on unfamiliar codebases (blast radius shows what's affected)
- When edge cases matter (scenario coverage gate ensures they're tested)
- When AI tends to over-engineer (traceability keeps scope tight)
- When you need evidence, not opinions (PROVEN labels from MCP tools)

### When Temper Is Overkill

- Quick scripts and one-off tools
- Codebases where AI-generated code is manually reviewed line-by-line
- Projects with established QA processes that already catch these patterns
- Simple bug fixes where the scope is obvious

### Stack Support

| Stack | Temper | Cursor | CodeRabbit |
|-------|--------|--------|------------|
| TypeScript/React | Yes | Yes | Yes |
| Spring Boot | Yes | Yes | Yes |
| Node/Express | Yes | Yes | Yes |
| FastAPI | Yes | Yes | Yes |
| Go | Yes | Yes | Yes |
| Rust | Yes | Yes | Yes |
