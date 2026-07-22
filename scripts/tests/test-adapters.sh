#!/usr/bin/env bash
#
# test-adapters.sh — unit tests for the vendor-neutral adapter generators
# (generate-codex.sh, generate-cursor-plugin.sh, generate-gemini.sh) + lib.sh.
#
# Plain-bash assertions (consistent with test-temper.sh), no framework dependency.
# Everything runs via each generator's `--out DIR` flag into a throwaway tmp dir —
# sources are always read from the real REPO_ROOT (design.md Decision D3), so this
# never touches the working tree.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

PASS=0
FAIL=0

assert_eq() { # assert_eq <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL: $1 — expected '$2', got '$3'"
  fi
}

assert_exit() { # assert_exit <name> <expected-code> <cmd...>
  local name="$1" expected="$2"; shift 2
  local actual out
  out="$(mktemp "$WORKDIR/assert-out.XXXXXX")"
  "$@" >"$out" 2>&1; actual=$?
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL: $name — expected exit $expected, got $actual"
    sed 's/^/    /' "$out"
  fi
  rm -f "$out"
}

assert_file() { # assert_file <name> <path>
  if [[ -f "$2" ]]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL: $1 — file does not exist: $2"
  fi
}

PLUGIN_VERSION=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/.claude-plugin/plugin.json'))['version'])")

# ==============================================================================
# generate-codex.sh
# ==============================================================================
CODEX_OUT="$WORKDIR/codex-run"
assert_exit "generate-codex.sh exits 0" 0 bash "$REPO_ROOT/scripts/generate-codex.sh" --out "$CODEX_OUT"
assert_file "codex plugin.json emitted" "$CODEX_OUT/adapters/codex/.codex-plugin/plugin.json"
assert_file "codex marketplace.json emitted" "$CODEX_OUT/.agents/plugins/marketplace.json"
assert_file "codex temper-build skill emitted" "$CODEX_OUT/adapters/codex/skills/temper-build/SKILL.md"
assert_file "codex AGENTS.temper.md fallback emitted" "$CODEX_OUT/adapters/codex/AGENTS.temper.md"

CODEX_VER=$(python3 -c "import json; print(json.load(open('$CODEX_OUT/adapters/codex/.codex-plugin/plugin.json'))['version'])" 2>/dev/null)
assert_eq "codex plugin.json version matches plugin.json" "$PLUGIN_VERSION" "$CODEX_VER"

CODEX_OUT2="$WORKDIR/codex-run2"
bash "$REPO_ROOT/scripts/generate-codex.sh" --out "$CODEX_OUT2" >/dev/null
assert_exit "generate-codex.sh is idempotent (diff -r empty across two runs)" 0 \
  diff -rq "$CODEX_OUT/adapters/codex" "$CODEX_OUT2/adapters/codex"

# ==============================================================================
# generate-cursor-plugin.sh
# ==============================================================================
CURSOR_OUT="$WORKDIR/cursor-run"
assert_exit "generate-cursor-plugin.sh exits 0" 0 bash "$REPO_ROOT/scripts/generate-cursor-plugin.sh" --out "$CURSOR_OUT"
assert_file "cursor plugin.json emitted" "$CURSOR_OUT/adapters/cursor/.cursor-plugin/plugin.json"
assert_file "cursor marketplace.json emitted" "$CURSOR_OUT/.cursor-plugin/marketplace.json"
assert_file "cursor plugin.stamp.json sidecar emitted (strict schema — no inline x-temper)" \
  "$CURSOR_OUT/adapters/cursor/.cursor-plugin/plugin.stamp.json"

# Schema-strictness regression guard: Cursor's plugin.schema.json declares
# additionalProperties: false — plugin.json/marketplace.json must carry ONLY the
# allowed key set (no inline "x-temper", unlike Codex's).
python3 - "$CURSOR_OUT/adapters/cursor/.cursor-plugin/plugin.json" > "$WORKDIR/cursor_schema_check.txt" 2>&1 <<'PY'
import json, sys
allowed = {"name","displayName","description","version","author","publisher","homepage",
    "repository","license","logo","keywords","category","tags","commands","agents","skills","rules","hooks","mcpServers"}
d = json.load(open(sys.argv[1]))
extra = set(d.keys()) - allowed
assert not extra, f"disallowed keys present: {extra}"
print("ok")
PY
assert_exit "cursor plugin.json has no schema-disallowed keys (e.g. no inline x-temper)" 0 \
  grep -q "^ok$" "$WORKDIR/cursor_schema_check.txt"

CURSOR_OUT2="$WORKDIR/cursor-run2"
bash "$REPO_ROOT/scripts/generate-cursor-plugin.sh" --out "$CURSOR_OUT2" >/dev/null
assert_exit "generate-cursor-plugin.sh is idempotent" 0 \
  diff -rq "$CURSOR_OUT/adapters/cursor" "$CURSOR_OUT2/adapters/cursor"

# Legacy zero-diff contract: this generator must never touch .cursor/ or
# scripts/generate-cursor.sh (Decision 2 — frozen).
assert_exit "generate-cursor-plugin.sh leaves legacy .cursor/ + generate-cursor.sh untouched" 0 \
  git -C "$REPO_ROOT" diff --stat main -- .cursor scripts/generate-cursor.sh --quiet

# ==============================================================================
# generate-gemini.sh
# ==============================================================================
GEMINI_OUT="$WORKDIR/gemini-run"
assert_exit "generate-gemini.sh exits 0" 0 bash "$REPO_ROOT/scripts/generate-gemini.sh" --out "$GEMINI_OUT"
assert_file "gemini-extension.json emitted" "$GEMINI_OUT/adapters/gemini/gemini-extension.json"
assert_file "GEMINI.md emitted" "$GEMINI_OUT/adapters/gemini/GEMINI.md"
assert_file "unified temper.toml emitted" "$GEMINI_OUT/adapters/gemini/commands/temper.toml"
assert_file "status.toml emitted (Gemini-only stage)" "$GEMINI_OUT/adapters/gemini/commands/temper/status.toml"

python3 - "$GEMINI_OUT/adapters/gemini/commands/temper/plan.toml" > "$WORKDIR/gemini_args_check.txt" 2>&1 <<'PY'
import sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
assert "{{args}}" in d["prompt"], "expected {{args}} substitution in prompt"
assert "$ARGUMENTS" not in d["prompt"], "leftover $ARGUMENTS was not substituted"
print("ok")
PY
assert_exit "gemini plan.toml substitutes \$ARGUMENTS -> {{args}}" 0 \
  grep -q "^ok$" "$WORKDIR/gemini_args_check.txt"

GEMINI_OUT2="$WORKDIR/gemini-run2"
bash "$REPO_ROOT/scripts/generate-gemini.sh" --out "$GEMINI_OUT2" >/dev/null
assert_exit "generate-gemini.sh is idempotent" 0 \
  diff -rq "$GEMINI_OUT/adapters/gemini" "$GEMINI_OUT2/adapters/gemini"

# ==============================================================================
# lib.sh — shared helpers (spot checks; full behavior covered via the generators)
# ==============================================================================
LIB_CHECK=$(bash -c "
export REPO_ROOT='$REPO_ROOT'
source '$REPO_ROOT/scripts/adapters/lib.sh'
printf 'Use AskUserQuestion now.' | rewrite_claude_isms
")
case "$LIB_CHECK" in
  *AskUserQuestion*) FAIL=$((FAIL+1)); echo "FAIL: rewrite_claude_isms left AskUserQuestion un-rewritten" ;;
  *) PASS=$((PASS+1)) ;;
esac

echo ""
echo "=== test-adapters.sh ==="
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
