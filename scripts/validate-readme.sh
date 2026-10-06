#!/usr/bin/env bash
# validate-readme.sh — Validate README.md structure and size
# Offline-safe, no network calls.
set -euo pipefail

# With CDPATH set, cd prints the folder it enters, and the path below would hold it twice.
unset CDPATH
# The plugin folder: this script sits in its scripts folder, so strip that literal suffix.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${HERE%/scripts}"
[[ "$REPO_ROOT" != "$HERE" ]] || { echo "FAIL: cannot find the plugin folder from $HERE"; exit 1; }
PASS=0
FAIL=0

ok() { PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

README="$REPO_ROOT/README.md"

if [[ ! -f "$README" ]]; then
  echo "FAIL: README.md not found"
  exit 1
fi

# 1. Line count <= 300
LINES=$(wc -l < "$README" | tr -d ' ')
if [[ "$LINES" -le 300 ]]; then
  ok
else
  fail "README is $LINES lines (max 300)"
fi

# 2. Required sections exist
for section in "Quick Start\|Installation\|Install" "What It Does\|Overview\|How it works\|How It Works"; do
  if grep -qi "$section" "$README"; then
    ok
  else
    fail "README missing section matching: $section"
  fi
done

# 3. Internal markdown links resolve
# Extract [text](./relative/path) or [text](relative/path) links (not http/https).
# A link target is looked up in the repository's file list (git ls-files, files deleted from
# the working tree left out), never joined onto a folder and opened. A target that contains
# '..' or starts with '/' is reported as broken: README links are relative to the repo root.
LISTED="$(cd "$REPO_ROOT" && git ls-files -co --exclude-standard 2>/dev/null || true)"
DELETED="$(cd "$REPO_ROOT" && git ls-files -d 2>/dev/null || true)"
PRESENT="$(printf '%s\n' "$LISTED" | grep -vxF -f <(printf '%s\n' "$DELETED") || true)"

# in_repo <path>: a listed file, or a folder that holds one. grep reads a here-string, not a
# pipe: under pipefail, grep -q leaving early could end the writer with SIGPIPE and fail the
# whole check for a link that is there.
in_repo() {
  local t="${1%/}"
  [[ -n "$t" ]] || return 1
  grep -qxF -- "$t" <<< "$PRESENT" && return 0
  awk -v p="$t/" 'index($0, p) == 1 { found = 1 } END { exit !found }' <<< "$PRESENT"
}

if [[ -z "$PRESENT" ]]; then
  fail "README link check needs a git checkout (git ls-files listed nothing)"
else
  BROKEN=$(grep -oE '\]\([^)]+\)' "$README" | grep -vE 'http|mailto' | \
    sed 's/\](//;s/)//' | while read -r link; do
      # Strip anchor
      FILE=$(echo "$link" | sed 's/#.*//')
      [[ -z "$FILE" ]] && continue
      FILE="${FILE#./}"
      if [[ "$FILE" != "${FILE//../}" || "$FILE" != "${FILE#/}" ]]; then
        echo "$link (uses .. or starts with /)"
      elif ! in_repo "$FILE"; then
        echo "$link"
      fi
    done || true)

  if [[ -z "$BROKEN" ]]; then
    ok
  else
    fail "Broken internal links in README:"
    echo "$BROKEN" | sed 's/^/  /'
  fi
fi

# 4. First 50 lines contain problem statement and quick start
HEAD50=$(head -50 "$README")
if grep -qi "install\|quick start\|get started\|usage" <<< "$HEAD50"; then
  ok
else
  fail "First 50 lines missing install/quick start instruction"
fi

echo ""
echo "=== validate-readme.sh ==="
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
