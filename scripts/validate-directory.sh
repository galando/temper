#!/usr/bin/env bash
# validate-directory.sh: checks the plugin is ready for a plugin directory listing.
# Offline-safe, no network calls. Each rule prints one FAIL line and the script exits 1.
#
# Rules:
#   1. README.md has no raw HTML tags (outside code fences and inline code).
#   2. README.md has an "Install" heading and a "What the mod reads and writes" heading.
#   3. README.md has a plain text line that names the phases, before the Mermaid block.
#   4. Every image in README.md has alt text.
#   5. No text file names the bundled assets folder outside a Markdown link target. The files
#      come from git ls-files: top level files, .claude/CLAUDE.md and the folders listed at
#      rule 5 below. No other folder is opened.
#   6. plugin.json and marketplace.json carry no "options" key.
#   7. plugin.json has a description, keywords and a version, and marketplace.json
#      names the same plugin.
#   8. A LICENSE file exists (LICENSE, LICENSE.md or LICENSE.txt).
#
# Test hook: VALIDATE_DIRECTORY_ROOT=<dir> checks that folder instead of this clone. The folder
# must be a git work tree (rule 5 lists its files with git ls-files). This script writes nothing.
set -uo pipefail

# The plugin folder: this script sits in its scripts folder, so strip that literal suffix.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${HERE%/scripts}"
[[ "$ROOT" != "$HERE" ]] || { echo "FAIL: cannot find the plugin folder from $HERE"; exit 1; }
ROOT="${VALIDATE_DIRECTORY_ROOT:-$ROOT}"
FAIL=0
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

README="$ROOT/README.md"
PLUGIN="$ROOT/.claude-plugin/plugin.json"
MARKET="$ROOT/.claude-plugin/marketplace.json"

# The README text without fenced code blocks and without inline code spans.
readme_prose() {
  awk '/^```/ { skip = !skip; next } !skip' "$README" | sed -E 's/`[^`]*`//g'
}

if [[ ! -f "$README" ]]; then
  fail "README.md is missing"
else
  # 1. Raw HTML. Comments are tags too; autolinks like <https://x> are not.
  HTML="$(readme_prose | grep -nE '</?[A-Za-z][A-Za-z0-9]*([[:space:]/>]|$)|<!--' | grep -vE '<https?://' || true)"
  if [[ -n "$HTML" ]]; then
    fail "README.md has raw HTML (the directory does not render it):"
    printf '%s\n' "$HTML" | head -5 | sed 's/^/  /'
  fi

  # 2. Required headings.
  grep -qE '^#{1,3} .*Install' "$README" || fail "README.md has no Install heading"
  grep -qE '^#{1,3} What the mod reads and writes' "$README" \
    || fail "README.md has no 'What the mod reads and writes' heading"

  # 3. The plain diagram line must come before the Mermaid block.
  MERMAID_LINE="$(grep -n '^```mermaid' "$README" | head -1 | cut -d: -f1)"
  if [[ -n "$MERMAID_LINE" ]]; then
    head -n "$((MERMAID_LINE - 1))" "$README" | grep -qE 'Intent, Plan, Build, Review, Check' \
      || fail "README.md has a Mermaid diagram with no plain text line of the phases before it"
  fi

  # 4. Alt text on every image.
  if grep -nE '!\[\]\(' "$README" >/dev/null; then
    fail "README.md has an image with empty alt text"
  fi
fi

# 5. The bundled assets folder path may appear only as a Markdown link target.
# The files come from git ls-files (tracked, plus new files git does not ignore), filtered here:
# a top level file, .claude/CLAUDE.md, or a file in one of the folders named in the case below,
# with an md, sh, tape, tpl or json extension. Every other folder is skipped without being
# opened, and so are docs/history (old release notes), scripts/tests and this script.
ASSETS_DIR_NAME="docs/assets"
LEAKS=""
if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  fail "rule 5 lists files with git ls-files, and $ROOT is not a git work tree"
else
  while IFS= read -r -d '' rel; do
    # A path with a '/' is kept only when its first folder is one of these names.
    if [[ "$rel" =~ ^([^/]+)/ && "$rel" != ".claude/CLAUDE.md" ]]; then
      case "${BASH_REMATCH[1]}" in
        .claude-plugin|.github|agents|commands|docs|examples|packs|reference|scripts|skills|templates) ;;
        *) continue ;;
      esac
    fi
    [[ "${rel#docs/history/}" == "$rel" && "${rel#scripts/tests/}" == "$rel" ]] || continue
    [[ "$rel" != "scripts/validate-directory.sh" ]] || continue
    [[ "$rel" =~ \.(md|sh|tape|tpl|json)$ ]] || continue
    [[ -f "$ROOT/$rel" ]] || continue
    hit="$(sed -E 's/\]\([^)]*\)//g' "$ROOT/$rel" | grep -nF "$ASSETS_DIR_NAME" | head -2 || true)"
    [[ -n "$hit" ]] && LEAKS+="  $rel: $(printf '%s' "$hit" | head -1 | cut -c1-100)"$'\n'
  done < <(git -C "$ROOT" ls-files -z -co --exclude-standard 2>/dev/null)
fi
if [[ -n "$LEAKS" ]]; then
  fail "the bundled assets folder path is named outside a Markdown link target:"
  printf '%s' "$LEAKS"
fi

# 6 and 7. The manifests.
for m in "$PLUGIN" "$MARKET"; do
  [[ -f "$m" ]] || { fail "$(basename "$m") is missing"; continue; }
  if grep -q '"options"' "$m"; then
    fail "$(basename "$m") has an \"options\" key (it stops the plugin loading before Claude Code 2.1.271)"
  fi
done
if [[ -f "$PLUGIN" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$PLUGIN" "$MARKET" <<'PY' || FAIL=$((FAIL+1))
import json, sys
bad = False
def no(msg):
    global bad
    print("FAIL: " + msg)
    bad = True
p = json.load(open(sys.argv[1]))
if not str(p.get("description", "")).strip():
    no("plugin.json has no description")
if not isinstance(p.get("keywords"), list) or not p["keywords"]:
    no("plugin.json has no keywords")
if not str(p.get("version", "")).strip():
    no("plugin.json has no version")
try:
    m = json.load(open(sys.argv[2]))
    names = [e.get("name") for e in m.get("plugins", [])]
    if p.get("name") not in names:
        no("marketplace.json does not list the plugin named " + str(p.get("name")))
    for e in m.get("plugins", []):
        if not str(e.get("description", "")).strip():
            no("marketplace.json plugin " + str(e.get("name")) + " has no description")
except FileNotFoundError:
    pass
sys.exit(1 if bad else 0)
PY
  else
    fail "python3 is required for the manifest checks"
  fi
fi

# 8. License.
[[ -f "$ROOT/LICENSE" || -f "$ROOT/LICENSE.md" || -f "$ROOT/LICENSE.txt" ]] || fail "no LICENSE file"

if [[ $FAIL -eq 0 ]]; then
  echo "OK: directory readiness checks passed"
  exit 0
fi
echo "validate-directory: $FAIL failing rule(s)"
exit 1
