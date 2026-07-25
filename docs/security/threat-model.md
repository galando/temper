# Threat Model

Temper's enforcement surface is small and readable — four hook scripts, one CLI, and
(new in this release) three self-hosted marketplace manifests. This document names
what each can execute, the trust boundaries a security reviewer should evaluate, and
what a malicious actor at each boundary could and could not do.

## Assets

| Asset | Why it matters |
|-------|-----------------|
| User source code | The thing Temper reads, edits, and gates. |
| Git history / commits | What the commit gate protects — an unauthorized commit bypasses review discipline. |
| Commit-gate integrity | The property that `git commit` is blocked while any upstream `temper gate` is FAIL and unoverridden. |
| `.temper/` ledger (`gates.json`, `evidence/*.json`, `build-state.json`) | The evidence a gate verdict is computed from. |
| `.git/hooks/pre-commit` | The installed enforcement point — a real file on disk, replaceable by anything with local write access. |
| The marketplace-source manifest (`.claude-plugin/marketplace.json`) | Install-time trust root. A tampered manifest could point an install at a hostile plugin path. |

## Capabilities — what each script executes

All four hook scripts and the installer are plain bash, readable in full; this table
names exactly what each does and its degradation contract (fail-open vs fail-closed).

| Script | What it executes | Env override | Degradation contract |
|--------|-------------------|---------------|------------------------|
| `scripts/hooks/install.sh` | Writes a **new file**, `.git/hooks/pre-commit` (or `.git/hooks-temper/pre-commit` with `--global`), embedding the absolute path to the Temper hooks directory (`HOOKS_DIR`, resolved from `$0` at install time) into the generated hook body. Backs up any pre-existing non-Temper hook. | The generated hook itself reads `TEMPER_HOOKS_DIR` at commit time, defaulting to the embedded `HOOKS_DIR` — **arbitrary execution if an attacker controls this env var or the directory it points at**, since the generated pre-commit hook `bash`-executes whatever is in `$TEMPER_HOOKS_DIR/block-secrets.sh` unconditionally. | Fail-open: missing scripts dir → hook exits 0 (never blocks). |
| `scripts/hooks/block-secrets.sh` | PreToolUse / pre-commit secret-pattern grep over staged files or the file at `$CLAUDE_FILE_PATH`. Deterministic pattern match, no model call. | — | The one fail-closed path: detected secret → exit 2 (BLOCK). No match / internal error → exit 0. |
| `scripts/hooks/block-forbidden-imports.sh` | PostToolUse import-statement grep against a denylist. | `TEMPER_FORBIDDEN_IMPORTS` (colon-separated) — **empty by default (no-op)**; a project sets this to police its own import bans. | Explicit match → exit 2 (BLOCK). Empty/no-match/error → exit 0. |
| `scripts/hooks/block-uncommitted-gate.sh` | PreToolUse hook that inspects the Bash command about to run; if (and only if) it's `git commit`, shells out to `scripts/temper gate commit` and blocks on FAIL. | — | Not a `git commit` → exit 0. CLI/state absent → exit 0 (fail-open). `temper gate commit` FAIL → exit 2 (BLOCK). |
| `scripts/hooks/verify-tests-ran.sh` | Native pre-commit fallback: reads `.temper/build-state.json`'s `stage` field; blocks unless it's `check_complete`/`eval_complete`. | `TEMPER_BUILD_STATE` (path override) — **an attacker who can set this env var for the commit process can point it at a file they control, forging a green state.** | State present + not green → exit 2 (BLOCK — the one fail-closed path). State missing/unreadable → exit 0 (fail-open by design — never blocks repos that don't use Temper). |

**Fail-open vs fail-closed, summarized:** every script defaults to fail-open on
*absence* of signal (missing scripts, missing state, no denylist configured) — a repo
that never adopted Temper is never blocked by it. Every script fails *closed* only on
an explicit, *detected* violation (a matched secret, a matched forbidden import, a
FAIL gate, a non-green build state). This is a deliberate asymmetry: false negatives
(a bypass) are the cost of adoption-safety; the trade-off is documented here rather
than silently assumed.

## Trust Boundaries

### 1. Plugin repo → machine (install-time)

Installing Temper means trusting the repo you point your agent's marketplace/plugin
system at. The self-hosted marketplace manifest (`.claude-plugin/marketplace.json`) is
a **listing file, not an auto-activating skill** — an entry only names a path; nothing
in it executes on its own. A contributor who opens this repo is not silently handed an
active prompt surface merely because the manifest exists in the tree — `/plugin
marketplace add` followed by `/plugin install` is the step that activates anything, and
that step is always user-initiated.

The residual risk is a **tampered repo or tarball** presented as this one (a
malicious fork, a compromised release asset, or a MITM'd clone) — mitigated by signed,
verifiable git tags and attested release artifacts (Tasks 11–12 of this same change;
see [`SECURITY.md`](https://github.com/galando/temper/blob/main/SECURITY.md)
supported-versions + the release process). Prior
to those, install was entirely unpinned; this is the gap this release closes. This is
unchanged in kind from before this release — it is the same boundary Claude Code's
`.claude-plugin/marketplace.json` has always had — this release adds two more instances
of the same, already-accepted risk shape, not a new risk category.

### 2. Packs / config → model prompts

`packs/{name}/rules.md` and `.claude/temper.config` are read into the agent's context
at Build/Review/Check time. **A malicious `rules.md` is a prompt-injection vector**: a
project-local pack (three-tier resolution: project-local > global > built-in) is
literally instructions the model reads and follows. This could, in principle, try to
get an agent to skip evidence recording, approve its own bad code, or exfiltrate
context via a suggested tool call.

Mitigations: (a) pack content is markdown, not executable — it cannot itself run
anything; the model still has to choose to act on an instruction, and Claude Code's own
tool-permission prompts remain the enforcement layer for anything with real effect
(file writes, shell commands); (b) the deterministic gates (`temper gate <stage>`) do
not read pack content at all — verdicts come from the evidence ledger, so a malicious
pack cannot forge a PASS by convincing the model to *say* something; it would have to
convince the model to run a fabricated `temper evidence add`, which is itself
inspectable in the ledger's `cmd`/`exit_code` fields. Adopt project-local packs only
from sources you trust, same as any other prompt content in your repo.

### 3. `.temper/` state (evidence/overrides forgeability)

Every file under `.temper/` — `gates.json`, `evidence/*.json`, `overrides.json`,
`build-state.json` — is plain JSON writable by any local process, including the agent
itself. **This is an explicit non-goal, not an oversight**: the gates defend against a
*confused model* silently self-asserting success (the entire point of the v7
deterministic-spine redesign — see `docs/plans/v7-deterministic-spine.md`), not against
a *hostile local attacker* who already has write access to the repository. If an
attacker already controls the local filesystem enough to hand-edit `.temper/gates.json`,
they could equally hand-edit the source files the gate is supposed to be protecting —
the ledger is a discipline mechanism for a well-intentioned but fallible agent, not a
security boundary against a compromised machine.

### 4. Environment overrides (hook redirection)

`TEMPER_HOOKS_DIR`, `TEMPER_FORBIDDEN_IMPORTS`, and `TEMPER_BUILD_STATE` are all
attacker-relevant if a process running the commit (CI runner, shell profile, CI
secret) can set arbitrary environment variables: `TEMPER_HOOKS_DIR` redirects which
`block-secrets.sh` gets executed (arbitrary code, see Capabilities table above);
`TEMPER_BUILD_STATE` redirects which file is read as "the" build state, letting an
attacker forge a green state; `TEMPER_FORBIDDEN_IMPORTS` only *weakens* a check (empty
denylist is already the default), so it is lower severity. Mitigation: these overrides
exist for legitimate reasons (vendored hook directories, custom build-state locations
in monorepos) and are documented, not hidden — treat an unexpected `TEMPER_*`
environment variable in a CI job the same as you would treat an unexpected `PATH`
override: a sign the runner is compromised, not a Temper-specific gap.

## Attacker Stories

| Story | Impact | Mitigation |
|-------|--------|------------|
| **Malicious plugin update** — an attacker gains push access to this repo (or a fork users are pointed at) and ships a tampered `commands/*.md` or hook. | Every future install/update pulls the tampered content, injecting instructions into every user's agent session. | Signed, verifiable release tags + build-provenance attestation; pinned-version install path documented in `docs/security/pinned-install.md` so consumers can pin to a verified tag rather than tracking `main`. |
| **Malicious pack** — a project adds a `packs/evil/rules.md` (or a global `~/.claude/packs/...`) designed to manipulate Build/Review output. | Prompt injection into the agent's context during those stages (see Trust Boundary #2). | Pack review before adoption (same trust level as any other repo content); gates don't read pack content, so a forged PASS still requires a forged, ledger-visible `temper evidence add`. |
| **Tampered checkout** — a user is handed a zip/tarball or a clone from an untrusted mirror instead of the real repo. | Any of the above, plus a completely arbitrary `scripts/temper` or hook script. | `git tag -v` verification against the maintainer's signing key + `gh attestation verify` against the release's build provenance (Task 12) — both give a cryptographic answer to "is this actually the maintainer's release," which a copied tarball cannot forge. |
| **Hostile repo consumed by a Temper user** — the *reverse* direction: a user runs Temper against a project whose own `.claude/temper.config` or pack content they don't control (e.g. reviewing an untrusted PR's branch). | The untrusted project's config/packs get read into the agent's context, same class as Trust Boundary #2. | Out of Temper's control by design — this is the same risk as running *any* agent against untrusted repo content; Temper does not amplify it, since it still routes every verdict through the CLI rather than trusting prompt content for gate decisions. |

## Non-Goals

- Defending against an attacker who already has arbitrary local code execution or
  filesystem write access on the machine running Temper (Trust Boundary #3).
- Sandboxing the model's own tool calls — that is Claude Code's / the host agent's
  permission system, not Temper's.
- Vetting third-party MCP servers or the OCR external LLM a user opts into — see
  [`SECURITY.md`](https://github.com/galando/temper/blob/main/SECURITY.md) scope and
  [`data-flow.md`](https://github.com/galando/temper/blob/main/docs/security/data-flow.md).
