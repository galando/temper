#!/bin/bash
#
# Temper Version Bump Script
# Usage: ./scripts/version-bump.sh <version>
# Example: ./scripts/version-bump.sh 1.2.0
#
# Rewrites every version stamp so plugin.json is the single source of truth.
# Stamps updated (all derived — never hand-edit these for version purposes):
#   1. .claude-plugin/plugin.json          "version": "X.Y.Z"
#   2. .cursor/VERSION                     bare X.Y.Z (if .cursor/ exists; the
#                                          generator owns this post-Task-4, but
#                                          the stamp is kept honest here too)
#   3. .claude/CLAUDE.md                   **Version:** X.Y.Z
#   4. .claude/commands/temper.md          header  (vX.Y.Z)
#
# CHANGELOG.md is NOT auto-rewritten — the maintainer owns the new `## vX.Y.Z`
# entry and its body. validate-plugin.sh asserts CHANGELOG top version matches.
#
# Idempotent: re-running with the same version is a no-op. Tolerant of missing
# files: a missing stamp file is skipped with a warning (pack/skill layouts may
# vary across forks), but plugin.json itself is required.

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 1.2.0"
    exit 1
fi

NEW_VERSION="$1"

# Validate version format
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Version must be in format X.Y.Z (e.g., 1.2.0)"
    exit 1
fi

# Operate from repo root regardless of where the script is invoked from.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "Bumping version to $NEW_VERSION..."

# 1. plugin.json (required — the single source of truth)
PJ=".claude-plugin/plugin.json"
if [ -f "$PJ" ]; then
    echo "  -> Updating $PJ"
    sed -i.bak "s/\"version\": \"[^\"]*\"/\"version\": \"$NEW_VERSION\"/" "$PJ"
    rm -f "$PJ.bak"
else
    echo "Error: $PJ not found (required source of truth)" >&2
    exit 1
fi

# 2. .cursor/VERSION (optional — generator owns it, but keep honest if present)
if [ -d ".cursor" ]; then
    echo "  -> Updating .cursor/VERSION"
    echo "$NEW_VERSION" > .cursor/VERSION
else
    echo "  -> .cursor/ not found, skipping .cursor/VERSION (run scripts/generate-cursor.sh)"
fi

# 3. .claude/CLAUDE.md  **Version:** X.Y.Z
CLAUDE_MD=".claude/CLAUDE.md"
if [ -f "$CLAUDE_MD" ]; then
    echo "  -> Updating $CLAUDE_MD (**Version:**)"
    # Match the marker exactly; tolerate any prior X.Y.Z or X.Y.Z-rcN.
    sed -i.bak -E "s/(\*\*Version:\*\*) [0-9][0-9.]+([-+0-9A-Za-z.]*)?/\1 $NEW_VERSION/" "$CLAUDE_MD"
    rm -f "$CLAUDE_MD.bak"
else
    echo "  -> $CLAUDE_MD not found, skipping"
fi

# 4. .claude/commands/temper.md header  (vX.Y.Z)
TEMPER_CMD=".claude/commands/temper.md"
if [ -f "$TEMPER_CMD" ]; then
    echo "  -> Updating $TEMPER_CMD header (vX.Y.Z)"
    # Only the title header line carries the plugin version stamp:
    #   "# Temper: Unified SDLC Command (vX.Y.Z)"
    # Other "(vN.N.N)" markers in the file denote when a *feature* was
    # introduced (e.g. "## Feedback Loops (v4.0.0)") and must NOT be bumped.
    sed -i.bak -E "/^# Temper:.*\(v[0-9]/ s/\(v[0-9][0-9.]+([-+0-9A-Za-z.]*)?\)/(v$NEW_VERSION)/" "$TEMPER_CMD"
    rm -f "$TEMPER_CMD.bak"
else
    echo "  -> $TEMPER_CMD not found, skipping"
fi

echo ""
echo "Version bumped to $NEW_VERSION"
echo ""
echo "Files updated:"
echo "   * .claude-plugin/plugin.json"
[ -d ".cursor" ]            && echo "   * .cursor/VERSION"
[ -f "$CLAUDE_MD" ]         && echo "   * $CLAUDE_MD"
[ -f "$TEMPER_CMD" ]        && echo "   * $TEMPER_CMD"
echo ""
echo "Next steps:"
echo "   1. Update CHANGELOG.md with a '## v$NEW_VERSION' entry at the top"
echo "   2. Commit: git add -A && git commit -m 'chore: bump version to $NEW_VERSION'"
echo "   3. Tag: git tag v$NEW_VERSION"
echo "   4. Push: git push && git push --tags"
echo ""
