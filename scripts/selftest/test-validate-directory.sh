#!/usr/bin/env bash
# Tests for scripts/validate-directory.sh: a good fixture passes, and one fixture per rule fails.
# Every fixture is a git work tree under one mktemp folder outside this clone, with a copy of the
# script in its scripts folder; the copy checks the fixture it sits in. The test writes and deletes
# only inside that folder.
set -uo pipefail
# With CDPATH set, cd prints the folder it enters, and the path below would hold it twice.
unset CDPATH
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${HERE%/scripts/selftest}"
[[ "$ROOT" != "$HERE" ]] || { echo "FAIL: cannot find the plugin folder from $HERE"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FAIL: git is required (validate-directory.sh lists files with git ls-files)"; exit 1; }
PASS=0; FAIL=0

# The one folder this test writes in: an absolute path with no '..', not this clone, not inside
# it, and not a folder that holds it.
FIXTURES="$(mktemp -d)" || { echo "FAIL: mktemp -d failed"; exit 1; }
if [[ ! -d "$FIXTURES" || "${FIXTURES#/}" == "$FIXTURES" || "$FIXTURES" != "${FIXTURES//../}" \
      || "$FIXTURES" == "$ROOT" || "${FIXTURES#"$ROOT"/}" != "$FIXTURES" || "${ROOT#"$FIXTURES"/}" != "$ROOT" ]]; then
  echo "FAIL: unsafe fixture folder '$FIXTURES'"; exit 1
fi
trap 'rm -rf "$FIXTURES"' EXIT
# git stops looking for a repository at the fixture folder, so a fixture is its own work tree
# (or none) even when the temp folder sits inside another repository.
export GIT_CEILING_DIRECTORIES="$FIXTURES"

# The picture lines of a fixture are put together here, when the test runs, so this tracked file
# holds no image reference to a missing file and no raw picture HTML.
IMG_EXT=png
PIC="docs/assets/pic.$IMG_EXT"
LT='<'
image() { printf '%s[%s](%s)' '!' "$1" "$2"; }   # image <alt text> <path>

# make_fixture <name> [plain]: creates a folder of that name in FIXTURES that passes every rule,
# with a copy of validate-directory.sh in its scripts folder, made a git work tree unless 'plain'
# is given. The name is a plain word (letters and '_'), so the folder is always directly in
# FIXTURES.
make_fixture() {
  local name="$1" kind="${2:-}" d
  [[ "$name" =~ ^[a-z_]+$ ]] || { echo "FAIL: bad fixture name '$name'"; return 1; }
  d="$FIXTURES/$name"
  mkdir -p "$d/.claude-plugin" "$d/docs/assets" "$d/scripts"
  cp "$ROOT/scripts/validate-directory.sh" "$d/scripts/validate-directory.sh"
  cat > "$d/README.md" <<'MD'
# Demo

## Install

Run the install command.

## How it works

The order is Intent, Plan, Build, Review, Check, then Done.

```mermaid
flowchart LR
  A["one<br/>two"] --> B
```

## What the mod reads and writes

It reads files.

MD
  { image 'A picture' "$PIC"; printf '\n'; } >> "$d/README.md"
  printf 'MIT\n' > "$d/LICENSE"
  cat > "$d/.claude-plugin/plugin.json" <<'JSON'
{"name":"demo","description":"A demo plugin.","version":"1.0.0","keywords":["demo"]}
JSON
  cat > "$d/.claude-plugin/marketplace.json" <<'JSON'
{"name":"demo","plugins":[{"name":"demo","source":"./","description":"A demo plugin."}]}
JSON
  [[ "$kind" == plain ]] || git init -q "$d"
}

# check <name> <expected exit> <dir> [VAR=value ...]: runs the copy of the script in <dir> from
# <dir>, by its relative path, with any extra environment given.
check() {
  local name="$1" want="$2" dir="$3" out rc
  shift 3
  out="$(cd "$dir" && env "$@" bash scripts/validate-directory.sh 2>&1 </dev/null)"; rc=$?
  if [[ $rc -eq $want ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $name (exit $rc, wanted $want): $out"; fi
}

# variant <name> <expected exit> <what to change, a function name>: a fresh fixture named after
# the function, changed by it, then checked.
variant() {
  local name="$1" want="$2" fn="$3"
  make_fixture "$fn" || { FAIL=$((FAIL+1)); return; }
  "$fn" "$FIXTURES/$fn"
  check "$name" "$want" "$FIXTURES/$fn"
}
broken() { variant "$1" 1 "$2"; }

add_html()      { printf '\n%spicture>%simg src="x.%s">%s/picture>\n' "$LT" "$LT" "$IMG_EXT" "$LT" >> "$1/README.md"; }
html_in_code()  { printf '\nUse `<br>` in code.\n' >> "$1/README.md"; }
no_install()    { sed 's/^## Install/## Setup/' "$1/README.md" > "$1/R" && mv "$1/R" "$1/README.md"; }
no_reads()      { sed 's/^## What the mod reads and writes/## Reads/' "$1/README.md" > "$1/R" && mv "$1/R" "$1/README.md"; }
no_diagram()    { sed 's/Intent, Plan, Build, Review, Check/the phases/' "$1/README.md" > "$1/R" && mv "$1/R" "$1/README.md"; }
empty_alt()     { { printf '\n'; image '' "$PIC"; printf '\n'; } >> "$1/README.md"; }
assets_code()   { printf '\nSee `%s` for it.\n' "$PIC" >> "$1/README.md"; }
assets_block()  { mkdir -p "$1/examples"; printf 'Output docs/assets/x.%s\n' "$IMG_EXT" > "$1/examples/a.tape"; }
assets_top()    { printf 'The pictures are in docs/assets.\n' > "$1/NOTES.md"; }
assets_unread() { mkdir -p "$1/vendor"; printf 'The pictures are in docs/assets.\n' > "$1/vendor/notes.md"; }
has_options()   { printf '{"name":"demo","description":"d","version":"1","keywords":["k"],"options":["a"]}\n' > "$1/.claude-plugin/plugin.json"; }
no_keywords()   { printf '{"name":"demo","description":"d","version":"1"}\n' > "$1/.claude-plugin/plugin.json"; }
wrong_market()  { printf '{"name":"x","plugins":[{"name":"other","source":"./","description":"d"}]}\n' > "$1/.claude-plugin/marketplace.json"; }
no_license()    { rm -f "$1/LICENSE"; }
license_md()    { rm -f "$1/LICENSE"; printf 'MIT\n' > "$1/LICENSE.md"; }

make_fixture good && check "a good fixture passes" 0 "$FIXTURES/good"

# Inline code with a tag is allowed.
variant "a tag inside inline code passes" 0 html_in_code
# A Markdown link target may name the assets folder (the good fixture does).
# Only the listed folders are read: a folder outside that list is never opened.
variant "a folder outside the read list is not opened" 0 assets_unread
variant "a LICENSE.md counts as the license" 0 license_md

broken "raw HTML fails" add_html
broken "no Install heading fails" no_install
broken "no 'What the mod reads and writes' heading fails" no_reads
broken "no plain text diagram line fails" no_diagram
broken "empty image alt text fails" empty_alt
broken "assets folder in backticks fails" assets_code
broken "assets folder in a tape file fails" assets_block
broken "assets folder in a top level Markdown file fails" assets_top
broken "an options key fails" has_options
broken "missing keywords fails" no_keywords
broken "marketplace without the plugin fails" wrong_market
broken "no LICENSE fails" no_license
make_fixture no_git plain && check "a folder that is not a git work tree fails" 1 "$FIXTURES/no_git"

# Nothing in the environment moves the checked folder: the variable older versions read to check
# another folder is ignored, both ways.
check "the old folder variable cannot point a good plugin's check at a broken one" 0 "$FIXTURES/good" \
  VALIDATE_DIRECTORY_ROOT="$FIXTURES/no_license"
check "the old folder variable cannot point a broken plugin's check at a good one" 1 "$FIXTURES/no_license" \
  VALIDATE_DIRECTORY_ROOT="$FIXTURES/good"
# The script finds its folder with CDPATH naming that folder (cd would print it otherwise).
check "a good fixture passes with CDPATH naming it" 0 "$FIXTURES/good" CDPATH="$FIXTURES/good"

# The real clone passes.
check "this clone passes" 0 "$ROOT"

echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
