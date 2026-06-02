#!/bin/bash
#
# Temper — Cursor IDE Install Script
#
# Usage:
#   Local:   ./scripts/install-cursor.sh [project-path]
#   Remote:  bash <(curl -fsSL https://raw.githubusercontent.com/galando/temper/main/scripts/install-cursor.sh)
#
# Downloads static .cursor/ files from GitHub. Requires only curl.
#
set -e

TARGET_DIR="${1:-.}"
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || {
    echo "Error: Target directory '$1' does not exist."
    exit 1
}

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
download mcp.json

VERSION=$(cat "$TARGET_DIR/.cursor/VERSION")

# Rules
RULES=(
    temper-temper-core.mdc
    temper-pack-adaptive-learning.mdc
    temper-pack-architecture-depth.mdc
    temper-pack-code-simplifier.mdc
    temper-pack-git.mdc
    temper-pack-quality.mdc
    temper-pack-security.mdc
    temper-pack-tdd.mdc
    temper-capability-config-suggestions.mdc
    temper-capability-plan-review.mdc
    temper-ref-build.mdc
    temper-ref-check.mdc
    temper-ref-design.mdc
    temper-ref-fix.mdc
    temper-ref-orchestrator-patterns.mdc
    temper-ref-pack.mdc
    temper-ref-plan.mdc
    temper-ref-review.mdc
    temper-ref-status.mdc
    temper-skill-context-engineering.mdc
    temper-skill-grill-me.mdc
    temper-skill-source-driven.mdc
)
for rule in "${RULES[@]}"; do download "rules/$rule"; done

# Commands
COMMANDS=(
    temper.md
    temper-build.md
    temper-check.md
    temper-design.md
    temper-fix.md
    temper-pack.md
    temper-plan.md
    temper-review.md
    temper-status.md
)
for cmd in "${COMMANDS[@]}"; do download "commands/$cmd"; done

echo "Temper v${VERSION} — Cursor IDE Setup"
echo ""
echo "  Commands: 9"
echo "  Rules:    22"
echo ""
echo "Setup complete. Temper commands available in Cursor:"
echo "  /temper          — Unified SDLC"
echo "  /temper-plan     — Plan with blast radius"
echo "  /temper-build    — TDD + quality gates"
echo "  /temper-review   — Confidence-scored review"
echo "  /temper-check    — Stack validation"
echo ""
echo "Optional: Configure MCP servers in .cursor/mcp.json"
