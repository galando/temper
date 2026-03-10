#!/bin/bash
#
# Temper Version Bump Script
# Usage: ./scripts/version-bump.sh <version>
# Example: ./scripts/version-bump.sh 1.2.0
#
# This script updates the version in all required files:
# 1. .claude-plugin/plugin.json (Claude Code plugin)
# 2. opencode/package.json (OpenCode npm package)
# 3. CHANGELOG.md (adds version header)
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

# 2. Update OpenCode npm package version
echo "  → Updating opencode/package.json"
if [ -f "opencode/package.json" ]; then
    sed -i.bak "s/\"version\": \"[^\"]*\"/\"version\": \"$NEW_VERSION\"/" opencode/package.json
    rm -f opencode/package.json.bak
fi

# 3. Update CHANGELOG.md - add version header if not exists
echo "  → Updating CHANGELOG.md"
if ! grep -q "## \[$NEW_VERSION\]" CHANGELOG.md; then
    # Insert new version header after the intro section
    sed -i.bak "/and this project adheres to \[Semantic Versioning\]/a\\
\\
## [$NEW_VERSION] - $DATE\\
\\
### Added\\
- \\[Add your changes here\\]\\
\\
### Changed\\
- \\[Add your changes here\\]\\
\\
### Fixed\\
- \\[Add your changes here\\]
" CHANGELOG.md
    rm -f CHANGELOG.md.bak
    echo "  → Added version header to CHANGELOG.md (edit to add your changes!)"
else
    echo "  → Version header already exists in CHANGELOG.md"
fi

echo ""
echo "✅ Version bumped to $NEW_VERSION"
echo ""
echo "📋 Files updated:"
echo "   • .claude-plugin/plugin.json"
echo "   • opencode/package.json"
echo "   • CHANGELOG.md"
echo ""
echo "🔍 Next steps:"
echo "   1. Edit CHANGELOG.md with your changes"
echo "   2. Commit: git add -A && git commit -m 'chore: bump version to $NEW_VERSION'"
echo "   3. Tag: git tag v$NEW_VERSION"
echo "   4. Push: git push && git push --tags"
echo ""
