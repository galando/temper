#!/bin/bash
#
# Temper Version Bump Script
# Usage: ./scripts/version-bump.sh <version>
# Example: ./scripts/version-bump.sh 1.2.0
#
# Rewrites every version stamp so plugin.json is the single source of truth.
# Stamps updated (all derived — never hand-edit these for version purposes):
#   1. .claude-plugin/plugin.json          "version": "X.Y.Z"
#   2. .claude/CLAUDE.md                   **Version:** X.Y.Z
#   3. commands/temper.md          header  (vX.Y.Z)
#   4. CHANGELOG.md                a skeleton "## vX.Y.Z" entry inserted before
#                                  the FIRST existing entry (maintainer fills
#                                  the body) — verified, exit 1 on no anchor
#   5. every other visible version string (README badge fallback, docs page
#                                  labels) in README.md, docs/index.md and
#                                  docs/getting-started.md, kept in sync with plugin.json
#
# Every file this script rewrites is named literally below, relative to the plugin folder.
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

# Operate from repo root regardless of where the script is invoked from. This script sits in
# the plugin's scripts folder, so the root is its folder with that literal suffix stripped.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${HERE%/scripts}"
if [ "$REPO_ROOT" = "$HERE" ]; then
    echo "Error: cannot find the plugin folder from $HERE" >&2
    exit 1
fi
cd "$REPO_ROOT"

echo "Bumping version to $NEW_VERSION..."

# Capture the OLD version first (from plugin.json, the source of truth) so the
# visible-string sweep below (the README version badge among them) replaces exactly the previous version, never an
# unrelated number.
OLD_VERSION="$(sed -n 's/.*"version": "\([0-9][0-9.]*\)".*/\1/p' .claude-plugin/plugin.json 2>/dev/null | head -1 || true)"

# 1. plugin.json (required — the single source of truth)
if [ -f .claude-plugin/plugin.json ]; then
    echo "  -> Updating .claude-plugin/plugin.json"
    sed -i.bak "s/\"version\": \"[^\"]*\"/\"version\": \"$NEW_VERSION\"/" .claude-plugin/plugin.json
    rm -f .claude-plugin/plugin.json.bak
else
    echo "Error: .claude-plugin/plugin.json not found (required source of truth)" >&2
    exit 1
fi

# 3. .claude/CLAUDE.md  **Version:** X.Y.Z
if [ -f .claude/CLAUDE.md ]; then
    echo "  -> Updating .claude/CLAUDE.md (**Version:**)"
    # Match the marker exactly; tolerate any prior X.Y.Z or X.Y.Z-rcN.
    sed -i.bak -E "s/(\*\*Version:\*\*) [0-9][0-9.]+([-+0-9A-Za-z.]*)?/\1 $NEW_VERSION/" .claude/CLAUDE.md
    rm -f .claude/CLAUDE.md.bak
else
    echo "  -> .claude/CLAUDE.md not found, skipping"
fi

# 4. commands/temper.md header  (vX.Y.Z)
if [ -f commands/temper.md ]; then
    echo "  -> Updating commands/temper.md header (vX.Y.Z)"
    # Only the title header line carries the plugin version stamp:
    #   "# Temper: Unified SDLC Command (vX.Y.Z)"
    # Other "(vN.N.N)" markers in the file denote when a *feature* was
    # introduced (e.g. "## Feedback Loops (v4.0.0)") and must NOT be bumped.
    sed -i.bak -E "/^# Temper:.*\(v[0-9]/ s/\(v[0-9][0-9.]+([-+0-9A-Za-z.]*)?\)/(v$NEW_VERSION)/" commands/temper.md
    rm -f commands/temper.md.bak
else
    echo "  -> commands/temper.md not found, skipping"
fi

# 5. CHANGELOG.md — insert a skeleton entry for the new version BEFORE the
# first existing "## vX.Y.Z" heading. The anchor is the FIRST match only
# (inserting at every match would scatter copies down the file), the insert is
# verified to have landed (an anchor that never matches must FAIL, never print
# success with nothing inserted), and a file that already carries the new
# header is left alone (idempotent).
if [ -f CHANGELOG.md ]; then
    if grep -qE "^## v?${NEW_VERSION//./\\.}([[:space:]]|\(|:|$)" CHANGELOG.md; then
        echo "  -> CHANGELOG.md already has a v$NEW_VERSION entry, skipping"
    else
        ANCHOR_LINE=$(grep -nE '^## v?[0-9]+\.[0-9]+\.[0-9]+' CHANGELOG.md | head -1 | cut -d: -f1 || true)
        if [ -z "$ANCHOR_LINE" ]; then
            echo "Error: CHANGELOG.md has no '## vX.Y.Z' entry to anchor against — refusing to bump silently" >&2
            exit 1
        fi
        echo "  -> Inserting CHANGELOG.md v$NEW_VERSION skeleton before line $ANCHOR_LINE"
        ENTRY=$(printf '## v%s — TODO: one-line summary\n\n- TODO: maintainer fills in this entry'"'"'s body.\n' "$NEW_VERSION")
        # head/tail splice, not awk -v: awk's -v rejects embedded newlines in the
        # entry, which silently corrupted the insert (multi-line skeleton).
        { head -n $((ANCHOR_LINE - 1)) CHANGELOG.md; printf '%s' "$ENTRY"; echo; tail -n "+$ANCHOR_LINE" CHANGELOG.md; } > CHANGELOG.md.tmp && mv CHANGELOG.md.tmp CHANGELOG.md
        # Verify the header landed — a silent no-insert must never report success.
        if ! grep -qE "^## v?${NEW_VERSION//./\\.}([[:space:]]|\(|:|$)" CHANGELOG.md; then
            echo "Error: CHANGELOG.md insert failed verification — new header not found after insert" >&2
            exit 1
        fi
    fi
else
    echo "Warning: CHANGELOG.md not found, skipping changelog insert" >&2
fi

# 5b. docs/index.html  "version": "X.Y.Z" (the GitHub page's structured data)
if [ -f docs/index.html ]; then
    echo "  -> Updating docs/index.html (\"version\")"
    sed -i.bak "s/\"version\": \"[^\"]*\"/\"version\": \"$NEW_VERSION\"/" docs/index.html
    rm -f docs/index.html.bak
fi

# 6. Other visible version strings — anything that visibly labels the plugin
# with the OLD version (a README badge alt/fallback text, a docs page label)
# is bumped to the new one. The README badge image itself is dynamic (release
# badge, nothing hardcoded); this sweep catches forks and docs that hardcode a
# literal. Only exact OLD-version tokens are replaced, so unrelated numbers in
# prose are never touched. Zero matches is fine (nothing hardcoded to drift).
# The files are the ones that label the plugin with its current version, each named here.
# Other docs mention past versions on purpose (release history), so they are left alone.
if [ -n "$OLD_VERSION" ] && [ "$OLD_VERSION" != "$NEW_VERSION" ]; then
    OLD_ESC="${OLD_VERSION//./\\.}"
    for f in README.md docs/index.md docs/getting-started.md; do
        [ -f "$f" ] || continue
        if grep -qE "v?${OLD_ESC}([^0-9.]|$)" "$f" 2>/dev/null; then
            echo "  -> Updating visible version strings in $f"
            sed -i.bak -E "s/v?${OLD_ESC}([^0-9.]|\$)/v${NEW_VERSION}\1/g" "$f"
            rm -f "$f.bak"
        fi
    done
fi

echo ""
echo "Version bumped to $NEW_VERSION"
echo ""
echo "Files updated:"
echo "   * .claude-plugin/plugin.json"
[ -f .claude/CLAUDE.md ]    && echo "   * .claude/CLAUDE.md"
[ -f commands/temper.md ]   && echo "   * commands/temper.md"
echo ""
echo "Next steps:"
echo "   1. Fill in the '## v$NEW_VERSION' CHANGELOG entry body (skeleton inserted)"
echo "   2. Commit: git add -A && git commit -m 'chore: bump version to $NEW_VERSION'"
echo "   3. Tag: git tag v$NEW_VERSION"
echo "   4. Push: git push && git push --tags"
echo ""
