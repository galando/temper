#!/usr/bin/env bash
#
# generate-gemini.sh — Regenerate adapters/gemini/ (a Gemini CLI extension) from
# plugin sources.
#
# Gemini CLI extensions are TOML commands with `{{args}}` substitution; namespacing
# comes from directory layout (verified against Gemini CLI docs, 2026-07). No root
# marketplace manifest is needed — Gemini installs directly from a git URL
# (`gemini extensions install <git-url>`).
#
# THIS SCRIPT IS MAINTAINER/CI BUILD TOOLING — never an end-user install step.
#
# Canonical stage set for Gemini (design.md "Canonical stage set"): the unified
# `temper.toml` (from commands/temper.md) PLUS one command per
# plan/build/review/check/fix/status/init (7 stages, includes `status` — unlike
# Codex/Cursor). `design`, `pack`, `eval` remain Claude Code-only.
#
# Usage:
#   ./scripts/generate-gemini.sh              # regenerate in place
#   ./scripts/generate-gemini.sh --out DIR    # write output under DIR; sources
#                                              # always read from REPO_ROOT.

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
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required" >&2; exit 1; }
python3 -c "import tomllib" 2>/dev/null || { echo "FAIL: python3 tomllib (3.11+) is required" >&2; exit 1; }

VERSION=$(plugin_version)
VERIFIED_DATE="2026-07"
TIER_NOTE="Tier 2 — Gemini CLI extension (single-context, CLI-gated; no design/pack/eval)"

GEMINI_DIR="$OUT_ROOT/adapters/gemini"
COMMANDS_DIR="$GEMINI_DIR/commands"
STAGE_COMMANDS_DIR="$COMMANDS_DIR/temper"

# --- Stale-file cleanup: wholesale regenerate ---------------------------------
rm -rf "$GEMINI_DIR"
mkdir -p "$STAGE_COMMANDS_DIR"

# --- gemini-extension.json -----------------------------------------------------
python3 -c "$(cat <<'PY'
import json, sys
version = sys.argv[1]
out_path = sys.argv[2]
manifest = {"name": "temper", "version": version, "contextFileName": "GEMINI.md"}
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PY
)" "$VERSION" "$GEMINI_DIR/gemini-extension.json"

# --- GEMINI.md: temper-core + gate protocol + tier-2 note ----------------------
CORE_SRC="$REPO_ROOT/skills/temper-core/SKILL.md"
[[ -f "$CORE_SRC" ]] || { echo "FAIL: skills/temper-core/SKILL.md not found" >&2; exit 1; }
{
    stamp_header_md "skills/temper-core/SKILL.md" "$TIER_NOTE" "$VERSION" "$VERIFIED_DATE"
    echo "# Temper (Gemini CLI extension)"
    echo
    echo "$TIER_NOTE. Ships the unified \`/temper\` command plus"
    echo "plan/build/review/check/fix/status/init. \`design\`, \`pack\`, and \`eval\` remain"
    echo "Claude Code-only (multi-agent/interactive constructs)."
    echo
    strip_frontmatter < "$CORE_SRC" | rewrite_claude_isms
    gate_epilogue ""
} > "$GEMINI_DIR/GEMINI.md"

# --- TOML command emission (python3-serialized, tomllib-parseable) ------------
# $1 = source md file, $2 = output toml path, $3 = stage name (empty for unified)
emit_toml_command() {
    local src="$1" out="$2" stage="$3"
    local desc body
    desc=$(derive_description "$src")
    [[ -z "$desc" ]] && desc="Temper: $(basename "$src" .md)"
    body=$(strip_frontmatter < "$src" | rewrite_claude_isms)
    body="$body
$(gate_epilogue "$stage")"
    VERSION="$VERSION" VERIFIED_DATE="$VERIFIED_DATE" TIER_NOTE="$TIER_NOTE" \
    SRC_REL="${src#"$REPO_ROOT"/}" \
    python3 -c "$(cat <<'PY'
import os, sys
desc, body, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
version = os.environ["VERSION"]
verified = os.environ["VERIFIED_DATE"]
tier = os.environ["TIER_NOTE"]
src_rel = os.environ["SRC_REL"]

def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')

# Gemini-specific substitution (plan.md Transform rules table): $ARGUMENTS -> {{args}}.
# Done here (python str.replace, no shell parameter-expansion brace pitfalls) rather
# than in bash, where literal "}}" in a replacement prematurely closes ${...}.
body = body.replace("$ARGUMENTS", "{{args}}")

lines = []
lines.append(f"# AUTO-GENERATED — do not hand-edit. Regenerate via scripts/generate-gemini.sh.")
lines.append(f"# Source: {src_rel}")
lines.append(f"# Plugin version: {version}")
lines.append(f"# Tier: {tier}")
lines.append(f"# Upstream schema verified: {verified}")
lines.append("")
lines.append(f'description = "{esc(desc)}"')
lines.append(f'prompt = """')
lines.append(esc(body))
lines.append('"""')
with open(out_path, "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines) + "\n")
PY
)" "$desc" "$body" "$out"
}

# Unified /temper -> commands/temper.toml
emit_toml_command "$REPO_ROOT/commands/temper.md" "$COMMANDS_DIR/temper.toml" ""

# Stage commands (7, incl. status)
STAGE_NAMES=(plan build review check fix status init)
for stage in "${STAGE_NAMES[@]}"; do
    src="$REPO_ROOT/commands/$stage.md"
    [[ -f "$src" ]] || { echo "FAIL: commands/$stage.md not found" >&2; exit 1; }
    emit_toml_command "$src" "$STAGE_COMMANDS_DIR/$stage.toml" "$stage"
done

# --- Validate every emitted TOML parses (fail loudly here, not just in CI) ----
python3 -c "$(cat <<'PY'
import glob, os, sys, tomllib
root = sys.argv[1]
files = glob.glob(os.path.join(root, "**", "*.toml"), recursive=True)
for f in files:
    with open(f, "rb") as fh:
        d = tomllib.load(fh)
    assert d.get("prompt"), f"{f}: empty prompt field"
print(f"Parsed {len(files)} TOML files OK")
PY
)" "$COMMANDS_DIR"

# --- adapters/gemini/README.md -------------------------------------------------
cat > "$GEMINI_DIR/README.md" <<EOF
# Temper — Gemini CLI extension (Tier 2)

**AUTO-GENERATED by scripts/generate-gemini.sh from plugin sources. Do not hand-edit.**
Plugin version: $VERSION · Upstream schema verified: $VERIFIED_DATE

Tier 2: generated extension, single-context, CLI-gated. Ships the unified
\`/temper\` command plus plan/build/review/check/fix/status/init. \`design\`,
\`pack\`, and \`eval\` remain Claude Code-only.

## Install (native, no shell scripts)

\`\`\`
gemini extensions install https://github.com/galando/temper
\`\`\`

For local development, \`gemini extensions link /path/to/this/checkout\` links this
directory instead of copying it. As a bare fallback (no extension support), copy
\`adapters/gemini/commands/\` into your project's \`.gemini/commands/\` by hand.

## Gate protocol

Every command ends with the same epilogue: record evidence with \`scripts/temper
evidence add\`, compute the verdict with \`scripts/temper gate <stage>\` — never
self-asserted.
EOF

# --- Summary -------------------------------------------------------------------
TOML_COUNT=$(find "$COMMANDS_DIR" -name '*.toml' | wc -l | tr -d ' ')
echo "Generated adapters/gemini/ (version $VERSION)"
echo "  TOML commands: $TOML_COUNT"
