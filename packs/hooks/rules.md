---
phases: []
---

# Hooks Pack

**Version:** 2.0.0
**Last Updated:** 2026-07-19

Deterministic safety net for Temper. Unlike the model-driven advisory checks in
review/check, these hooks are plain bash: they block on a *detected* violation with a
non-model exit code and no-op when their inputs are absent. They are the determinism layer.

**`phases: []` is deliberate.** This file is install-and-behaviour documentation read by
`/temper:pack` and by humans — there is nothing here for a stage agent to apply, because
enforcement happens in bash at edit- and commit-time whether or not any prompt mentions
it. Loading it into Plan/Build/Review/Check would spend context on instructions no stage
can act on.

**v7:** the commit-time gate is now `temper gate commit` (`scripts/temper`) — it reads
the evidence ledger written by every stage (`temper evidence add`) and computes PASS/FAIL
per gate, rather than checking a single `build-state.json` stage field. `verify-tests-ran.sh`
is kept as a fallback for a project that installed only this pack, without the CLI.

**Plugin-shipped subset (v8):** the standalone-stage gate pair (`stage-marker.sh` +
`verify-stage-gate.sh`, last two rows of the catalog) also ships in the plugin's own
`hooks/hooks.json`, so any install of the Temper plugin — `--plugin-dir` or marketplace —
gets that guarantee with **no settings merge and no pack enablement**. Enabling this pack
adds the remaining hooks (secrets, imports, in-agent commit gate); if both are active the
stage-gate pair fires twice per event. On the satisfied path the second firing sees the
verdict or no marker and no-ops; on the blocking path both firings increment the refusal
counter, so the loop guard trips after one blocked stop instead of two — the error is in
the fail-open direction, never a double-block.

## Install

There are **two** layers, and both are needed for the full guarantee:

### 1. In-agent layer — `settings.json` hooks (Edits/Writes)

```
/temper:pack enable hooks
```

Enabling this pack routes through the global **update-config** skill, which block-merges
`settings.hooks.json` (the copy-paste source in this directory) into the project or user
`settings.json`. This wires `PreToolUse`/`PostToolUse` blocks that fire when the **agent**
edits or writes files (block-secrets on every Edit/Write) or runs Bash (block-secrets and
the commit gate on every Bash call — the commit-gate check is a no-op unless the command is
a `git commit`). The merge is additive — it never clobbers unrelated existing hooks. To
uninstall, run `/temper:pack disable hooks` (update-config removes the Temper hook block).

You can also copy `settings.hooks.json` into your `settings.json` manually if you prefer.

### 2. Commit-time layer — native git pre-commit hook (REQUIRED for deterministic blocking)

Claude Code's `settings.json` has **no `PreCommit` event** — only `PreToolUse`,
`PostToolUse`, `Stop`, `Notification`, `SubagentStop`, `PreCompact`, `SessionStart`,
`SessionEnd`, `UserPromptSubmit`. A `settings.json` block therefore **cannot** deterministically
block a raw `git commit`. The only gate that fires on every commit — agent-driven or not —
is a real git hook. Install it:

```
bash scripts/hooks/install.sh          # install into .git/hooks/pre-commit
bash scripts/hooks/install.sh --global # install via core.hooksPath
```

The installed `pre-commit` runs `block-secrets.sh` then `temper gate commit` and blocks
(exit 1) on a detected secret or a FAILing commit gate (any upstream gate not PASS and not
explicitly overridden via `temper override`). Absent scripts/CLI degrade to no-op.

If a non-Temper `pre-commit` already exists (husky, lefthook, hand-rolled), the installer
backs it up to `.git/hooks/pre-commit.bak.<timestamp>` before overwriting and prints the
backup path — it is never silently destroyed. Re-installing over an existing Temper hook is
idempotent (no backup pile-up).

> **This two-layer split is the determinism guarantee.** Layer 1 catches secrets at
> edit-time inside the agent; layer 2 catches them at commit-time, deterministically,
> independent of the agent. Without layer 2, the pack's headline SC-8 guarantee
> ("commit with a hard-coded secret blocked deterministically") is unreachable.

## Degradation Contract (Critical)

Every hook in this pack follows two non-negotiable rules:

1. **Absent script → no-op.** If the referenced `scripts/hooks/*.sh` is missing, the hook
   event must `exit 0` and block nothing. Missing tooling never blocks a commit.
2. **Internal error → fail-open (exit 0).** A bug or unexpected input in the script itself
   must NOT block the workflow. Only a *detected violation* (secret, forbidden import, check
   not green) is the fail-closed path.

The single fail-closed path for each script is documented below. Everything else is fail-open.

## Hook Catalog

| Script | Event | Default action | Fail-closed when |
|--------|-------|----------------|------------------|
| `scripts/hooks/block-secrets.sh` | PreToolUse / native pre-commit | **BLOCK** | A staged/edited file matches a secret pattern (AWS `AKIA...`, GitHub `gh[ps]_...`, private-key header, `sk-ant-...` / `sk-proj-...` / OpenAI legacy) |
| `scripts/hooks/block-forbidden-imports.sh` | PostToolUse | **warn** (no-op by default) | An edited file imports a name on the explicit denylist (empty by default) |
| `scripts/hooks/protect-regression-test.sh` | PreToolUse (Edit\|Write) | **BLOCK** | A /temper:fix run edits the regression test it recorded at RED (`state.regression_test`) — the fix loop's own check must not be weakened by the agent running it |
| `scripts/hooks/block-uncommitted-gate.sh` | PreToolUse (Bash) | **BLOCK** | The agent runs `git commit` and `temper gate commit` FAILs (in-agent mirror of the native hook, below) |
| `scripts/hooks/stage-marker.sh` | UserPromptSubmit | **no-op** (records only) | Never — it writes `.temper/pending-stage.json` when a `/temper:{plan,build,review,check}` prompt is submitted, and blocks nothing |
| `scripts/hooks/verify-stage-gate.sh` | Stop | **BLOCK** | A standalone stage session tries to end while `.temper/gates.json` has no verdict (PASS *or* FAIL both satisfy it) for the marked stage — see `docs/decisions/0005-deterministic-stage-gate-enforcement.md`. Fails open after 2 refusals |
| `scripts/temper gate commit` | native pre-commit | **BLOCK** | Any stage's evidence-backed gate is not PASS and has no recorded `temper override` |
| `scripts/hooks/verify-tests-ran.sh` | native pre-commit (fallback) | **BLOCK** | `.temper/build-state.json` shows the latest `check_complete` absent or failed — used only when `scripts/temper` isn't present |
| `scripts/hooks/install.sh` | n/a (installer) | **install** | Wires block-secrets + `temper gate commit` into a native git `pre-commit` hook (the deterministic commit gate) |

### block-secrets.sh

Conservative, high-precision pattern set (favor false-negatives over false-positives — a
broad pattern that blocks legitimate commits is a DX DoS). Detected patterns:

- AWS access key IDs: `AKIA[0-9A-Z]{16}`
- GitHub tokens: `gh[ps]_[0-9A-Za-z]{36}`
- Private key headers: `-----BEGIN ... PRIVATE KEY-----`
- Anthropic live API keys: `sk-ant-[A-Za-z0-9_-]{50,}`
- OpenAI project keys: `sk-proj-[A-Za-z0-9_-]{40,}`
- OpenAI service-account keys: `sk-svcacct-[A-Za-z0-9_-]{40,}`
- OpenAI legacy live keys: `sk-[A-Za-z0-9]{48}` (exact length)

> A bare `sk-[20+]` is deliberately **not** matched — it false-positives on documentation
> and fixture strings. Vendor-specific formats only.

On match: `exit 2` (blocks), reporting the matched pattern + file. On no match: `exit 0`.
On any internal error: `exit 0` (fail-open). Extend the denylist by editing the script's
`patterns` array.

### protect-regression-test.sh

The fix loop's self-protection. `/temper:fix` writes a regression test that must fail
before the fix (RED) and records its path with `temper state set regression_test
<path>`. From that moment until the run's state is cleared, any agent Edit/Write
targeting that file exits 2 — the agent fixing the code cannot also weaken the check on
that code. The block message names the deliberate human release valve
(`temper state set regression_test ""`), so a genuinely-wrong test is a person's edit
to unlock, never the fixing agent's. Outside a fix run (or with no recorded test):
no-op. Internal errors: fail-open, per the contract above.

### block-forbidden-imports.sh

Checks edited files' import statements against a configurable denylist. The denylist defaults
to **empty** → warn-only / no-op. Set `TEMPER_FORBIDDEN_IMPORTS` (colon-separated) to enable
blocking, e.g. `TEMPER_FORBIDDEN_IMPORTS="eval:child_process.exec"`. Exit 2 only on an explicit
denylist match; otherwise exit 0.

### temper gate commit (scripts/temper)

Refuses a commit if any stage's evidence-backed gate isn't PASS and has no recorded
override. Reads `.temper/evidence/*.json` (written by `temper evidence add` throughout
the pipeline) and `.temper/gates.json` (the last-computed verdict per stage); prints the
specific unmet requirement(s). `temper override <stage> --reason "..."` records a human
override — it stays visible in `temper report` and the final summary, it does not erase
the FAIL. See `docs/getting-started.md` for the full CLI reference. Absent `.temper/`
state → `exit 0` (degrade; a repo not running `/temper` for this commit is never blocked).

### verify-tests-ran.sh (fallback)

Used only when `scripts/temper` isn't present. Reads `.temper/build-state.json`; if the
latest stage is not `check_complete` (or check failed), `exit 2` with "run /temper:check".
Missing/unreadable state → `exit 0` (fail-open).

## Beyond the Commit Fence: Approval Gates (example, not wired by default)

Every hook above is a **guardrail** — it allows or blocks with no human involved.
The third mode is an **approval gate**: the hook *asks*, deterministically, by
refusing until a named human authorization exists. Temper's own fence ends at
`git commit` (it never pushes, merges, or deploys), so no pack wires one — but the
pattern is the same script shape, and `examples/hooks/production-gate.sh` is a
copy-paste starting point: a PreToolUse (Bash) hook that blocks `deploy`+`production`
commands until `RELEASE_APPROVAL` names an approver and change ticket, explaining the
route to approval in its block message. Two placement rules from hard experience:

- An approval gate belongs at the **release boundary**, never in the build phase — a
  human prompt mid-build puts a person back on the critical path of every parallel
  session.
- A gate individual engineers must not be able to switch off belongs in **managed
  settings** (owned by an org admin), not the repo's `.claude/settings.json` — a
  repo-level hook can be edited by anyone who can commit.

## Extending the Denylists

- Secrets: add regexes to the `patterns` array in `block-secrets.sh`.
- Imports: set `TEMPER_FORBIDDEN_IMPORTS` in your environment or settings.json `env` block.
- Gate requirements: edit the `gate_*` functions in `scripts/temper` (each is ~20-30 lines).

## Mandatory Rules (BLOCK if violated)
- Never commit a credential matching a known secret pattern (deterministic block via block-secrets.sh)
- Never commit while any stage gate is FAIL and unoverridden (deterministic block via `temper gate commit`)

## Quality Rules (WARN if violated)
- Avoid importing known-dangerous modules (eval, child_process.exec) — warn-by-default, block only on explicit denylist
