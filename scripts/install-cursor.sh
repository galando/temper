#!/bin/bash
#
# Temper — Cursor IDE Install Script
#
# Usage:
#   Local:   ./scripts/install-cursor.sh [project-path]
#   Remote:  bash <(curl -fsSL https://raw.githubusercontent.com/galando/temper/main/scripts/install-cursor.sh)
#
# Generates .cursor/ directory from .claude/ and copies it
# to the target project (defaults to current directory).
#
set -e

TARGET_DIR="${1:-.}"

# Resolve target to absolute path
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || {
    echo "Error: Target directory '$1' does not exist."
    exit 1
}

# Check for git
if ! command -v git &>/dev/null; then
    echo "Error: git is required."
    exit 1
fi

# Check Python 3
if ! command -v python3 &>/dev/null; then
    echo "Error: Python 3 is required. Install it from https://python.org"
    exit 1
fi

# Detect if running from cloned repo or piped via curl
REPO_ROOT=""
if [ -f "${BASH_SOURCE[0]}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/../.claude-plugin/plugin.json" ]; then
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

TEMP_DIR=""
cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

if [ -z "$REPO_ROOT" ]; then
    # Running via curl | bash — clone a shallow copy
    echo "Downloading Temper from GitHub..."
    TEMP_DIR="$(mktemp -d)"
    git clone --depth 1 https://github.com/galando/temper.git "$TEMP_DIR" >/dev/null 2>&1
    REPO_ROOT="$TEMP_DIR"
fi

# Read version from plugin.json
VERSION=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    print(json.load(f).get('version', 'unknown'))
" "$REPO_ROOT/.claude-plugin/plugin.json" 2>/dev/null || echo "unknown")

echo "Temper v${VERSION} — Cursor IDE Setup"
echo ""

# Generate .cursor/ directory
echo "Generating Cursor IDE files..."
python3 "$REPO_ROOT/scripts/generate-cursor.py" --output "$REPO_ROOT/.cursor"

# Copy to target project
if [ "$TARGET_DIR" != "$REPO_ROOT" ]; then
    echo ""
    echo "Copying .cursor/ to $TARGET_DIR/"
    rm -rf "$TARGET_DIR/.cursor"
    cp -R "$REPO_ROOT/.cursor" "$TARGET_DIR/.cursor"
fi

# Verify
echo ""
echo "Verification:"
if [ -f "$TARGET_DIR/.cursor/VERSION" ]; then
    CURSOR_VERSION=$(cat "$TARGET_DIR/.cursor/VERSION")
    if [ "$CURSOR_VERSION" = "$VERSION" ]; then
        echo "  Version: $CURSOR_VERSION (aligned with plugin.json)"
    else
        echo "  WARNING: .cursor/VERSION ($CURSOR_VERSION) != plugin.json ($VERSION)"
        echo "  Run scripts/generate-cursor.py to regenerate"
    fi
else
    echo "  WARNING: .cursor/VERSION not found"
fi

CMD_COUNT=$(find "$TARGET_DIR/.cursor/commands" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
RULE_COUNT=$(find "$TARGET_DIR/.cursor/rules" -name "*.mdc" 2>/dev/null | wc -l | tr -d ' ')

echo "  Commands: $CMD_COUNT"
echo "  Rules:    $RULE_COUNT"
echo ""
echo "Setup complete. Temper commands available in Cursor:"
echo "  /temper          — Unified SDLC"
echo "  /temper-plan     — Plan with blast radius"
echo "  /temper-build    — TDD + quality gates"
echo "  /temper-review   — Confidence-scored review"
echo "  /temper-check    — Stack validation"
echo ""
echo "Optional: Configure MCP servers in .cursor/mcp.json"
