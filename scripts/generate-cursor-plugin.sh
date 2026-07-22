#!/usr/bin/env bash
#
# generate-cursor-plugin.sh — Regenerate adapters/cursor/ + the repo-root Cursor
# marketplace manifest (.cursor-plugin/marketplace.json) from plugin sources.
#
# Cursor has a first-party plugin system (.cursor-plugin/plugin.json +
# .cursor-plugin/marketplace.json), verified directly against the published JSON
# Schemas at github.com/cursor/plugins/schemas/{plugin,marketplace}.schema.json
# (2026-07) and the real orchestrate/.cursor-plugin/plugin.json example in that
# repo. Both schemas declare `"additionalProperties": false` — Cursor's manifests do
# NOT tolerate an inline provenance key, unlike Codex's (design.md D2 contingency:
# sidecar `.stamp.json` files carry provenance instead of an embedded key).
#
# The schema's `skills` field takes a directory-glob STRING ("./skills/") wired to
# SKILL.md files — identical envelope to Codex (confirmed empirically: the real
# orchestrate example plugin uses "skills": "./skills/" verbatim) — so
# lib.sh's render_skill is reused verbatim, no `rules/*.mdc` envelope needed
# (design.md Open Question #1 resolved: `skills`, not `rules`).
#
# THIS SCRIPT IS MAINTAINER/CI BUILD TOOLING — never an end-user install step.
# It does NOT touch `.cursor/` or `scripts/generate-cursor.sh` (legacy, frozen,
# Decision 2) — new Cursor support lives only under `adapters/cursor/` and the
# repo-root `.cursor-plugin/marketplace.json`.
#
# Usage:
#   ./scripts/generate-cursor-plugin.sh              # regenerate in place
#   ./scripts/generate-cursor-plugin.sh --out DIR    # write output under DIR; sources
#                                                     # always read from REPO_ROOT
#                                                     # (design.md Decision D3).

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
TIER_NOTE="Tier 2 — Cursor native plugin (single-context, CLI-gated; no design/pack/eval — see adapters/cursor/README.md)"

CURSOR_DIR="$OUT_ROOT/adapters/cursor"
SKILLS_DIR="$CURSOR_DIR/skills"
CURSOR_PLUGIN_DIR="$CURSOR_DIR/.cursor-plugin"
MARKETPLACE_DIR="$OUT_ROOT/.cursor-plugin"

# --- Guard: never touch the legacy frozen paths -------------------------------
if [[ "$CURSOR_DIR" == "$REPO_ROOT/.cursor" ]]; then
    echo "FAIL: refusing to write to legacy .cursor/ (frozen)" >&2
    exit 1
fi

# --- Stale-file cleanup: wholesale regenerate ---------------------------------
rm -rf "$CURSOR_DIR"
mkdir -p "$SKILLS_DIR" "$CURSOR_PLUGIN_DIR"
mkdir -p "$MARKETPLACE_DIR"

# --- Stage set: same as Codex — temper-core (from skills/) + 6 stage skills ---
STAGE_NAMES=(plan build review check fix init)

for stage in "${STAGE_NAMES[@]}"; do
    src="$REPO_ROOT/commands/$stage.md"
    [[ -f "$src" ]] || { echo "FAIL: commands/$stage.md not found" >&2; exit 1; }
    name="temper-$stage"
    mkdir -p "$SKILLS_DIR/$name"
    render_skill "$src" "$name" "$TIER_NOTE" "$VERIFIED_DATE" "$stage" > "$SKILLS_DIR/$name/SKILL.md"
done

CORE_SRC="$REPO_ROOT/skills/temper-core/SKILL.md"
[[ -f "$CORE_SRC" ]] || { echo "FAIL: skills/temper-core/SKILL.md not found" >&2; exit 1; }
mkdir -p "$SKILLS_DIR/temper-core"
render_skill "$CORE_SRC" "temper-core" "$TIER_NOTE" "$VERIFIED_DATE" "" > "$SKILLS_DIR/temper-core/SKILL.md"

# --- .cursor-plugin/plugin.json (schema-strict: additionalProperties=false — no
#     inline x-temper key; see adapters/cursor/.cursor-plugin/plugin.stamp.json) ---
DESCRIPTION=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['description'])" "$PJ")

python3 -c "$(cat <<'PY'
import json, sys
version, description = sys.argv[1], sys.argv[2]
out_path = sys.argv[3]
manifest = {
    "name": "temper",
    "displayName": "Temper",
    "description": description,
    "version": version,
    "author": {"name": "galando"},
    "homepage": "https://github.com/galando/temper",
    "repository": "https://github.com/galando/temper",
    "license": "MIT",
    "keywords": ["temper", "quality-gates", "tdd", "code-review", "sdlc"],
    "category": "developer-tools",
    "tags": ["quality-gates", "tdd", "code-review", "automation"],
    "skills": "./skills/",
}
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PY
)" "$VERSION" "$DESCRIPTION" "$CURSOR_PLUGIN_DIR/plugin.json"

# Sidecar provenance stamp (schema forbids inline unknown keys — design.md D2 contingency).
python3 -c "$(cat <<'PY'
import json, sys
version, verified, source = sys.argv[1], sys.argv[2], sys.argv[3]
out_path = sys.argv[4]
stamp = {"source": source, "version": version, "tier": "2", "schemaVerified": verified,
         "note": "Cursor's plugin.schema.json declares additionalProperties: false; provenance lives in this sidecar instead of an inline key."}
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(stamp, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PY
)" "$VERSION" "$VERIFIED_DATE" ".claude-plugin/plugin.json" "$CURSOR_PLUGIN_DIR/plugin.stamp.json"

# --- .cursor-plugin/marketplace.json (repo-root, self-hosted Cursor marketplace) -
python3 -c "$(cat <<'PY'
import json, sys
description = sys.argv[1]
out_path = sys.argv[2]
manifest = {
    "name": "temper-marketplace",
    "owner": {"name": "galando"},
    "metadata": {"description": "Temper: deterministic quality gates + intent-driven development"},
    "plugins": [
        {"name": "temper", "source": "adapters/cursor", "description": description}
    ],
}
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PY
)" "$DESCRIPTION" "$MARKETPLACE_DIR/marketplace.json"

python3 -c "$(cat <<'PY'
import json, sys
version, verified = sys.argv[1], sys.argv[2]
out_path = sys.argv[3]
stamp = {"source": "scripts/generate-cursor-plugin.sh", "version": version, "tier": "2",
         "schemaVerified": verified,
         "note": "Cursor's marketplace.schema.json declares additionalProperties: false; provenance lives in this sidecar instead of an inline key."}
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(stamp, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PY
)" "$VERSION" "$VERIFIED_DATE" "$MARKETPLACE_DIR/marketplace.stamp.json"

# --- adapters/cursor/README.md ------------------------------------------------
cat > "$CURSOR_DIR/README.md" <<EOF
# Temper — Cursor plugin (Tier 2, native)

**AUTO-GENERATED by scripts/generate-cursor-plugin.sh from plugin sources. Do not
hand-edit.** Plugin version: $VERSION · Upstream schema verified: $VERIFIED_DATE
(github.com/cursor/plugins schemas/plugin.schema.json + marketplace.schema.json)

Tier 2: native plugin, single-context, CLI-gated. Ships \`temper-core\` +
plan/build/review/check/fix/init skills. \`design\`, \`pack\`, and \`eval\` remain
Claude Code-only. This is a **new, separate surface** from the legacy \`.cursor/\`
snapshot (frozen at the v5.1 track, see \`.cursor/README.md\`) — that snapshot is
superseded by this native plugin, not replaced in place.

## Install (native, no shell scripts)

1. Register this repo as a Cursor marketplace source, then install the \`temper\`
   plugin via the editor's \`/add-plugin\`.
2. **Honest limitation (as of $VERIFIED_DATE):** Cursor's official docs
   (cursor.com/docs/plugins, cursor.com/docs/reference/plugins) document plugin
   *submission* to the central marketplace and the manifest schema, but do not yet
   document a command for registering an arbitrary third-party repo as a custom
   marketplace source. The editor's \`/add-plugin\` flow is Cursor's documented
   installer surface; treat any specific "register a custom source" command syntax
   as unverified until Cursor's docs publish one — do not guess at it.

## Gate protocol

Every skill ends with the same epilogue: record evidence with \`scripts/temper evidence
add\`, compute the verdict with \`scripts/temper gate <stage>\` — never self-asserted.
EOF

# --- Summary -------------------------------------------------------------------
SKILL_COUNT=$(find "$SKILLS_DIR" -name 'SKILL.md' | wc -l | tr -d ' ')
echo "Generated adapters/cursor/ (version $VERSION)"
echo "  Skills: $SKILL_COUNT"
echo "  Marketplace manifest: .cursor-plugin/marketplace.json"
