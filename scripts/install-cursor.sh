#!/bin/bash
#
# Temper — Cursor IDE Install Script
#
# Usage:
#   Local:   ./scripts/install-cursor.sh [project-path]
#   Remote:  bash <(curl -fsSL https://raw.githubusercontent.com/galando/temper/main/scripts/install-cursor.sh)
#
# Local path (default): if the target is a Temper repo (.claude/ + plugin.json
# present), regenerates .cursor/ from sources via scripts/generate-cursor.sh —
# honest parity, offline-safe, no drift. This is the recommended path.
#
# Remote path (curl | bash into an arbitrary project): downloads a static
# snapshot of .cursor/ from GitHub at the tagged version. Limitation: a remote
# install cannot regenerate from sources it does not have, so it ships whatever
# is committed on main. Re-run from inside the repo to regenerate.
#
set -e

TARGET_DIR="${1:-.}"
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || {
    echo "Error: Target directory '$1' does not exist."
    exit 1
}

# --- Local-repo branch: regenerate from sources ------------------------------
if [[ -d "$TARGET_DIR/.claude" && -f "$TARGET_DIR/.claude-plugin/plugin.json" && -f "$TARGET_DIR/scripts/generate-cursor.sh" ]]; then
    echo "Temper repo detected — regenerating .cursor/ from .claude/ sources."
    bash "$TARGET_DIR/scripts/generate-cursor.sh" --target "$TARGET_DIR"
    VERSION=$(cat "$TARGET_DIR/.cursor/VERSION")
    RULE_COUNT=$(find "$TARGET_DIR/.cursor/rules" -name '*.mdc' | wc -l | tr -d ' ')
    CMD_COUNT=$(find "$TARGET_DIR/.cursor/commands" -name '*.md' | wc -l | tr -d ' ')
    echo ""
    echo "Temper v${VERSION} — Cursor IDE Setup (regenerated)"
    echo ""
    echo "  Commands: ${CMD_COUNT}"
    echo "  Rules:    ${RULE_COUNT}"
    echo ""
    echo "Cursor support frozen at v5.1 feature set (CHANGELOG v5.2.1)."
    echo "Optional: Configure MCP servers in .cursor/mcp.json"
    exit 0
fi

# --- Remote branch: download static snapshot ---------------------------------
BASE="https://raw.githubusercontent.com/galando/temper/main/.cursor"
RULES_DIR="$TARGET_DIR/.cursor/rules"
CMDS_DIR="$TARGET_DIR/.cursor/commands"

mkdir -p "$RULES_DIR" "$CMDS_DIR"

download() {
    curl -fsSL "$BASE/$1" -o "$TARGET_DIR/.cursor/$1" || {
        echo "Error: Failed to download $1"
        exit 1
    }
}

# Metadata
download VERSION

# Enumerate the rules/commands index from the committed repo manifest so counts
# stay honest as the plugin evolves. The remote path ships a static snapshot at
# the tagged version (see header limitation note).
RULES_INDEX=$(curl -fsSL "$BASE/rules/" 2>/dev/null || true)
if [[ -z "$RULES_INDEX" ]]; then
    echo "Error: could not fetch rule listing from $BASE/rules/" >&2
    exit 1
fi

# GitHub directory listings are HTML; extract .mdc and .md filenames.
mapfile -t RULES < <(printf '%s' "$RULES_INDEX" | grep -oE 'temper-[a-z0-9-]+\.(mdc|md)' | sort -u)
if [[ ${#RULES[@]} -eq 0 ]]; then
    echo "Error: no rules found in remote listing" >&2
    exit 1
fi
for rule in "${RULES[@]}"; do download "rules/$rule"; done

COMMANDS_INDEX=$(curl -fsSL "$BASE/commands/" 2>/dev/null || true)
mapfile -t COMMANDS < <(printf '%s' "$COMMANDS_INDEX" | grep -oE 'temper[a-z0-9-]*\.md' | sort -u)
for cmd in "${COMMANDS[@]}"; do download "commands/$cmd"; done

VERSION=$(cat "$TARGET_DIR/.cursor/VERSION")
RULE_COUNT=${#RULES[@]}
CMD_COUNT=${#COMMANDS[@]}

echo "Temper v${VERSION} — Cursor IDE Setup (static snapshot)"
echo ""
echo "  Commands: ${CMD_COUNT}"
echo "  Rules:    ${RULE_COUNT}"
echo ""
echo "Note: remote install ships a static snapshot. To regenerate from sources,"
echo "run ./scripts/install-cursor.sh from inside a Temper repo checkout."
echo ""
echo "Optional: Configure MCP servers in .cursor/mcp.json"
