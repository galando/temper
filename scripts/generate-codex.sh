#!/usr/bin/env bash
#
# generate-codex.sh — Regenerate adapters/codex/ + the repo-root Codex marketplace
# manifest (.agents/plugins/marketplace.json) from plugin sources.
#
# Codex CLI has a first-party plugin system (.codex-plugin/plugin.json + a `skills`
# field wiring skill folders, verified against github.com/openai/plugins,
# 2026-07 — shape pinned to plugins/figma/.codex-plugin/plugin.json and
# plugins/superpowers/.codex-plugin/plugin.json). This script is MAINTAINER/CI
# BUILD TOOLING — it is never an end-user install step (Superpowers pattern: the
# committed output IS the install artifact; users add this repo as a Codex
# marketplace source and install the plugin natively).
#
# Pure function: (plugin.json, commands/*.md, skills/temper-core/SKILL.md) ->
# adapters/codex/** + .agents/plugins/marketplace.json. Deterministic, idempotent,
# offline (bash + python3 stdlib only).
#
# Usage:
#   ./scripts/generate-codex.sh              # regenerate in place (REPO_ROOT)
#   ./scripts/generate-codex.sh --out DIR    # write output under DIR; sources are
#                                             # ALWAYS read from this script's own
#                                             # REPO_ROOT (see design.md Decision D3 —
#                                             # this differs from legacy --target,
#                                             # which overrides both read and write).
#
# Canonical stage set for Codex (design.md "Canonical stage set"): temper-core
# (always-loaded, from skills/temper-core/SKILL.md) + one skill per of
# plan/build/review/check/fix/init (from commands/*.md). No `status`, no unified
# `/temper` command — those live only in the Gemini + Claude Code surfaces.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_ROOT="$REPO_ROOT"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --out) OUT_ROOT="$(cd "$2" 2>/dev/null && pwd || { mkdir -p "$2" && cd "$2" && pwd; })"; shift 2 ;;
        *) echo "Usage: $0 [--out DIR]" >&2; exit 2 ;;
    esac
done

# shellcheck source=scripts/adapters/lib.sh
source "$REPO_ROOT/scripts/adapters/lib.sh"

PJ="$REPO_ROOT/.claude-plugin/plugin.json"
if [[ ! -f "$PJ" ]]; then
    echo "FAIL: plugin.json not found at $PJ" >&2
    exit 1
fi
for d in skills commands; do
    if [[ ! -d "$REPO_ROOT/$d" ]]; then
        echo "FAIL: $d/ not found at $REPO_ROOT/$d" >&2
        exit 1
    fi
done

VERSION=$(plugin_version)
VERIFIED_DATE="2026-07"
TIER_NOTE="Tier 2 — Codex CLI native plugin (single-context, CLI-gated; no design/pack/eval — see adapters/codex/README.md)"

CODEX_DIR="$OUT_ROOT/adapters/codex"
SKILLS_DIR="$CODEX_DIR/skills"
CODEX_PLUGIN_DIR="$CODEX_DIR/.codex-plugin"
MARKETPLACE_DIR="$OUT_ROOT/.agents/plugins"

# --- Stale-file cleanup: wholesale regenerate ---------------------------------
rm -rf "$CODEX_DIR"
mkdir -p "$SKILLS_DIR" "$CODEX_PLUGIN_DIR" "$MARKETPLACE_DIR"

# --- Stage set: temper-core (from skills/) + 6 stage skills (from commands/) --
STAGE_NAMES=(plan build review check fix init)

for stage in "${STAGE_NAMES[@]}"; do
    src="$REPO_ROOT/commands/$stage.md"
    [[ -f "$src" ]] || { echo "FAIL: commands/$stage.md not found" >&2; exit 1; }
    name="temper-$stage"
    mkdir -p "$SKILLS_DIR/$name"
    render_skill "$src" "$name" "$TIER_NOTE" "$VERIFIED_DATE" "$stage" > "$SKILLS_DIR/$name/SKILL.md"
done

# temper-core: no single stage (always-loaded core protocol).
CORE_SRC="$REPO_ROOT/skills/temper-core/SKILL.md"
[[ -f "$CORE_SRC" ]] || { echo "FAIL: skills/temper-core/SKILL.md not found" >&2; exit 1; }
mkdir -p "$SKILLS_DIR/temper-core"
render_skill "$CORE_SRC" "temper-core" "$TIER_NOTE" "$VERIFIED_DATE" "" > "$SKILLS_DIR/temper-core/SKILL.md"

# --- .codex-plugin/plugin.json (shape pinned to openai/plugins figma + superpowers
#     examples, verified 2026-07; no published strict schema found for Codex, so the
#     provenance stamp is embedded as an additive "x-temper" key — see design.md D2) --
DESCRIPTION=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['description'])" "$PJ")

python3 -c "$(cat <<'PY'
import json, os, sys
version, description, verified = sys.argv[1], sys.argv[2], sys.argv[3]
out_path = sys.argv[4]
manifest = {
    "name": "temper",
    "version": version,
    "description": description,
    "author": {"name": "galando", "url": "https://github.com/galando"},
    "homepage": "https://github.com/galando/temper",
    "repository": "https://github.com/galando/temper",
    "license": "MIT",
    "keywords": ["temper", "quality-gates", "tdd", "code-review", "sdlc"],
    "skills": "./skills/",
    "interface": {
        "displayName": "Temper",
        "shortDescription": "Deterministic quality gates + intent-driven development, driven by scripts/temper",
        "longDescription": "Temper brings Plan/Build/Review/Check/Fix/Init quality gates to Codex CLI. Every gate verdict is computed by scripts/temper from an evidence ledger, never asserted by the model.",
        "developerName": "galando",
        "category": "Developer Tools",
        "capabilities": ["Interactive", "Read", "Write"],
        "websiteURL": "https://github.com/galando/temper",
        "defaultPrompt": [
            "Plan a new feature with blast radius analysis",
            "Build the current plan with TDD and quality gates",
            "Run the check pipeline on my changes",
        ],
        "brandColor": "#0288D1",
        "screenshots": [],
    },
    "x-temper": {
        "source": ".claude-plugin/plugin.json",
        "version": version,
        "tier": "2",
        "schemaVerified": verified,
    },
}
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PY
)" "$VERSION" "$DESCRIPTION" "$VERIFIED_DATE" "$CODEX_PLUGIN_DIR/plugin.json"

# --- .agents/plugins/marketplace.json (self-hosted Codex marketplace source) ---
# Shape verified against openai/plugins' own .agents/plugins/marketplace.json
# (object-form "source": {"source": "local", "path": ...}); no published JSON
# Schema was found for this file (unlike Cursor's), so the "x-temper" provenance
# key is embedded directly (design.md D2 default).
python3 -c "$(cat <<'PY'
import json, sys
version, verified = sys.argv[1], sys.argv[2]
out_path = sys.argv[3]
manifest = {
    "name": "temper-marketplace",
    "interface": {"displayName": "Temper"},
    "plugins": [
        {
            "name": "temper",
            "source": {"source": "local", "path": "./adapters/codex"},
            "description": "Deterministic quality gates + intent-driven development, driven by scripts/temper",
        }
    ],
    "x-temper": {
        "source": "scripts/generate-codex.sh",
        "version": version,
        "tier": "2",
        "schemaVerified": verified,
    },
}
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PY
)" "$VERSION" "$VERIFIED_DATE" "$MARKETPLACE_DIR/marketplace.json"

# --- AGENTS.temper.md — FALLBACK ONLY, not the documented install path --------
{
    stamp_header_md "skills/temper-core/SKILL.md" "$TIER_NOTE (AGENTS.md fallback fragment)" "$VERSION" "$VERIFIED_DATE"
    cat <<'EOF'
# Temper (AGENTS.md fallback fragment)

**This file is a FALLBACK ONLY** for vendored or air-gapped adoption where installing
the native Codex plugin (`adapters/codex/.codex-plugin`) via a marketplace source is not
possible. It is NOT the documented install path — see `adapters/codex/README.md` for the
native install flow. Never overwrites a project's own `AGENTS.md`; append this fragment
manually if you need it.

EOF
    strip_frontmatter < "$CORE_SRC" | rewrite_claude_isms
    gate_epilogue ""
} > "$CODEX_DIR/AGENTS.temper.md"

# --- adapters/codex/README.md -------------------------------------------------
cat > "$CODEX_DIR/README.md" <<EOF
# Temper — Codex CLI plugin (Tier 2)

**AUTO-GENERATED by scripts/generate-codex.sh from plugin sources. Do not hand-edit.**
Plugin version: $VERSION · Upstream schema verified: $VERIFIED_DATE

Tier 2: native plugin, single-context, CLI-gated. Ships \`temper-core\` +
plan/build/review/check/fix/init skills. \`design\`, \`pack\`, and \`eval\` remain
Claude Code-only (multi-agent/interactive constructs that don't port to a
single-context CLI). No \`status\` skill and no unified command here — see the
Gemini adapter for those, or use Claude Code for full parity.

## Install (native, no shell scripts)

1. Add this repo as a Codex marketplace source:
   \`\`\`
   codex marketplace add galando/temper
   \`\`\`
   (per openai/codex PR #17087: supports local dirs, GitHub shorthand, and git URLs;
   \`--ref vX.Y.Z\` pins to a tag.)
2. Install the plugin: open \`/plugins\` in your Codex session and install \`temper\`,
   or non-interactively: \`codex plugin install temper --non-interactive\`.
3. Start a new session — the temper-* skills become available.

## Fallback (air-gapped / vendored only)

If you cannot add a marketplace source, \`AGENTS.temper.md\` in this directory is a
single-file fragment carrying the core gate protocol. Append it to your project's own
\`AGENTS.md\` by hand. This is NOT the primary install path.

## Gate protocol

Every skill ends with the same epilogue: record evidence with \`scripts/temper evidence
add\`, compute the verdict with \`scripts/temper gate <stage>\` — never self-asserted.
EOF

# --- Summary -------------------------------------------------------------------
SKILL_COUNT=$(find "$SKILLS_DIR" -name 'SKILL.md' | wc -l | tr -d ' ')
echo "Generated adapters/codex/ (version $VERSION)"
echo "  Skills: $SKILL_COUNT"
echo "  Marketplace manifest: .agents/plugins/marketplace.json"
