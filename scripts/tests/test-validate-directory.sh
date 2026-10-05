#!/usr/bin/env bash
# Tests for scripts/validate-directory.sh: a good fixture passes, and one fixture per rule fails.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0

# make_fixture <dir>: a folder that passes every rule.
make_fixture() {
  local d="$1"
  mkdir -p "$d/.claude-plugin" "$d/docs/assets"
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

![A picture](docs/assets/pic.png)
MD
  printf 'MIT\n' > "$d/LICENSE"
  cat > "$d/.claude-plugin/plugin.json" <<'JSON'
{"name":"demo","description":"A demo plugin.","version":"1.0.0","keywords":["demo"]}
JSON
  cat > "$d/.claude-plugin/marketplace.json" <<'JSON'
{"name":"demo","plugins":[{"name":"demo","source":"./","description":"A demo plugin."}]}
JSON
}

# check <name> <expected exit> <dir>
check() {
  local name="$1" want="$2" dir="$3" out rc
  out="$(VALIDATE_DIRECTORY_ROOT="$dir" bash "$ROOT/scripts/validate-directory.sh" 2>&1 </dev/null)"; rc=$?
  if [[ $rc -eq $want ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $name (exit $rc, wanted $want): $out"; fi
}

# broken <name> <what to change, a function name>
broken() {
  local name="$1" fn="$2" d
  d="$(mktemp -d)"; make_fixture "$d"; "$fn" "$d"
  check "$name" 1 "$d"
  rm -rf "$d"
}

add_html()      { printf '\n<picture><img src="x.png"></picture>\n' >> "$1/README.md"; }
html_in_code()  { printf '\nUse `<br>` in code.\n' >> "$1/README.md"; }
no_install()    { sed 's/^## Install/## Setup/' "$1/README.md" > "$1/R" && mv "$1/R" "$1/README.md"; }
no_reads()      { sed 's/^## What the mod reads and writes/## Reads/' "$1/README.md" > "$1/R" && mv "$1/R" "$1/README.md"; }
no_diagram()    { sed 's/Intent, Plan, Build, Review, Check/the phases/' "$1/README.md" > "$1/R" && mv "$1/R" "$1/README.md"; }
empty_alt()     { printf '\n![](docs/assets/pic.png)\n' >> "$1/README.md"; }
assets_code()   { printf '\nSee `docs/assets/pic.png` for it.\n' >> "$1/README.md"; }
assets_block()  { mkdir -p "$1/demo"; printf 'Output docs/assets/x.gif\n' > "$1/demo/a.tape"; }
has_options()   { printf '{"name":"demo","description":"d","version":"1","keywords":["k"],"options":["a"]}\n' > "$1/.claude-plugin/plugin.json"; }
no_keywords()   { printf '{"name":"demo","description":"d","version":"1"}\n' > "$1/.claude-plugin/plugin.json"; }
wrong_market()  { printf '{"name":"x","plugins":[{"name":"other","source":"./","description":"d"}]}\n' > "$1/.claude-plugin/marketplace.json"; }
no_license()    { rm -f "$1/LICENSE"; }

GOOD="$(mktemp -d)"; make_fixture "$GOOD"
check "a good fixture passes" 0 "$GOOD"
rm -rf "$GOOD"

# Inline code with a tag is allowed.
d="$(mktemp -d)"; make_fixture "$d"; html_in_code "$d"; check "a tag inside inline code passes" 0 "$d"; rm -rf "$d"
# A Markdown link target may name the assets folder (the good fixture does).

broken "raw HTML fails" add_html
broken "no Install heading fails" no_install
broken "no 'What the mod reads and writes' heading fails" no_reads
broken "no plain text diagram line fails" no_diagram
broken "empty image alt text fails" empty_alt
broken "assets folder in backticks fails" assets_code
broken "assets folder in a tape file fails" assets_block
broken "an options key fails" has_options
broken "missing keywords fails" no_keywords
broken "marketplace without the plugin fails" wrong_market
broken "no LICENSE fails" no_license

# The real clone passes.
check "this clone passes" 0 "$ROOT"

echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
