#!/bin/bash
#
# Temper Version Bump Script
# Usage: ./scripts/version-bump.sh <version>
# Example: ./scripts/version-bump.sh 1.2.0
#
# This script updates the version in plugin.json.
#

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 1.2.0"
    exit 1
fi

NEW_VERSION="$1"
DATE=$(date +%Y-%m-%d)

# Validate version format
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Version must be in format X.Y.Z (e.g., 1.2.0)"
    exit 1
fi

echo "📝 Bumping version to $NEW_VERSION..."

# 1. Update Claude Code plugin version
echo "  → Updating .claude-plugin/plugin.json"
if [ -f ".claude-plugin/plugin.json" ]; then
    sed -i.bak "s/\"version\": \"[^\"]*\"/\"version\": \"$NEW_VERSION\"/" .claude-plugin/plugin.json
    rm -f .claude-plugin/plugin.json.bak
fi

# 2. Update Cursor IDE version
echo "  → Updating .cursor/VERSION"
if [ -d ".cursor" ]; then
    echo "$NEW_VERSION" > .cursor/VERSION
fi

echo ""
echo "✅ Version bumped to $NEW_VERSION"
echo ""
echo "📋 Files updated:"
echo "   • .claude-plugin/plugin.json"
echo "   • .cursor/VERSION"
echo ""
echo "🔍 Next steps:"
echo "   1. Commit: git add -A && git commit -m 'chore: bump version to $NEW_VERSION'"
echo "   2. Tag: git tag v$NEW_VERSION"
echo "   3. Push: git push && git push --tags"
echo ""
