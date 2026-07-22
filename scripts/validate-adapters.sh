#!/usr/bin/env bash
#
# validate-adapters.sh — CI validation for the three generated vendor adapters
# (Codex, Cursor, Gemini) + the two root marketplace manifests.
#
# Six checks (design.md "validate-adapters.sh checks", Task 5):
#   (a) idempotence / no-drift   — regen into a tempdir, diff against committed output
#   (b) parse                   — JSON/TOML parse every manifest
#   (c) version stamp match     — every manifest + stamp header version == plugin.json
#   (d) required-file + wiring  — required files exist; manifest-referenced paths resolve
#   (e) gate-protocol guard     — no generated file reimplements verdict logic (SC4)
#   (f) install-docs guard      — README install section has no generate-*.sh /
#                                  install-*.sh invocation (SC6)
#
# Offline-safe (bash + python3 stdlib only). Does not modify the working tree except
# for a throwaway tempdir (cleaned up on exit).
set -euo pipefail
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
VERBOSE=0
[[ "${1:-}" == "--verbose" ]] && VERBOSE=1 || true

ok() { PASS=$((PASS+1)); if [[ $VERBOSE -eq 1 ]]; then echo "PASS: $1"; fi; return 0; }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

PLUGIN_VERSION=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/.claude-plugin/plugin.json'))['version'])")

# ==============================================================================
# (a) Idempotence / no-drift
# ==============================================================================
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

bash "$REPO_ROOT/scripts/generate-codex.sh" --out "$TMPDIR" >/dev/null
bash "$REPO_ROOT/scripts/generate-cursor-plugin.sh" --out "$TMPDIR" >/dev/null
bash "$REPO_ROOT/scripts/generate-gemini.sh" --out "$TMPDIR" >/dev/null

for pair in \
    "adapters/codex:adapters/codex" \
    "adapters/cursor:adapters/cursor" \
    "adapters/gemini:adapters/gemini" \
    ".agents:.agents" \
    ".cursor-plugin:.cursor-plugin"
do
    rel="${pair%%:*}"
    if [[ ! -e "$REPO_ROOT/$rel" ]]; then
        fail "(a) idempotence: committed $rel does not exist — run the generator once and commit output"
        continue
    fi
    if diff -rq "$TMPDIR/$rel" "$REPO_ROOT/$rel" >/tmp/adapter-diff.$$ 2>&1; then
        ok "(a) idempotence: $rel matches regenerated output"
    else
        fail "(a) idempotence: $rel drifted from regenerated output"
        [[ $VERBOSE -eq 1 ]] && cat /tmp/adapter-diff.$$ || true
    fi
    rm -f /tmp/adapter-diff.$$
done

# ==============================================================================
# (b) Parse — JSON + TOML
# ==============================================================================
JSON_FILES=(
    "adapters/codex/.codex-plugin/plugin.json"
    "adapters/cursor/.cursor-plugin/plugin.json"
    "adapters/cursor/.cursor-plugin/plugin.stamp.json"
    ".agents/plugins/marketplace.json"
    ".cursor-plugin/marketplace.json"
    ".cursor-plugin/marketplace.stamp.json"
    "adapters/gemini/gemini-extension.json"
)
for f in "${JSON_FILES[@]}"; do
    p="$REPO_ROOT/$f"
    if [[ ! -f "$p" ]]; then
        fail "(b) parse: $f missing"
        continue
    fi
    if python3 -c "import json; json.load(open('$p'))" 2>/dev/null; then
        ok "(b) parse: $f is valid JSON"
    else
        fail "(b) parse: $f is not valid JSON"
    fi
done

TOML_COUNT=0
TOML_FAIL=0
while IFS= read -r f; do
    TOML_COUNT=$((TOML_COUNT+1))
    if ! python3 -c "import tomllib; tomllib.load(open('$f','rb'))" 2>/dev/null; then
        fail "(b) parse: $f is not valid TOML"
        TOML_FAIL=$((TOML_FAIL+1))
    fi
done < <(find "$REPO_ROOT/adapters/gemini/commands" -name '*.toml' 2>/dev/null | LC_ALL=C sort)
if [[ $TOML_COUNT -eq 0 ]]; then
    fail "(b) parse: no TOML files found under adapters/gemini/commands"
elif [[ $TOML_FAIL -eq 0 ]]; then
    ok "(b) parse: all $TOML_COUNT TOML files valid"
fi

# ==============================================================================
# (c) Version stamp match
# ==============================================================================
check_json_version() {
    local file="$1" key_path="$2"
    local p="$REPO_ROOT/$file"
    [[ -f "$p" ]] || { fail "(c) version: $file missing"; return; }
    local v
    v=$(python3 -c "
import json
d = json.load(open('$p'))
for k in '$key_path'.split('.'):
    d = d[k]
print(d)
" 2>/dev/null || echo "__ERROR__")
    if [[ "$v" == "$PLUGIN_VERSION" ]]; then
        ok "(c) version: $file ($key_path) == $PLUGIN_VERSION"
    else
        fail "(c) version: $file ($key_path) = '$v', expected $PLUGIN_VERSION"
    fi
}
check_json_version "adapters/codex/.codex-plugin/plugin.json" "version"
check_json_version "adapters/codex/.codex-plugin/plugin.json" "x-temper.version"
check_json_version ".agents/plugins/marketplace.json" "x-temper.version"
check_json_version "adapters/cursor/.cursor-plugin/plugin.json" "version"
check_json_version "adapters/cursor/.cursor-plugin/plugin.stamp.json" "version"
check_json_version ".cursor-plugin/marketplace.stamp.json" "version"
check_json_version "adapters/gemini/gemini-extension.json" "version"

# md/toml stamp headers: "Plugin version: X.Y.Z" comment line.
STAMP_MISMATCHES=0
STAMP_TOTAL=0
while IFS= read -r f; do
    STAMP_TOTAL=$((STAMP_TOTAL+1))
    # Version token immediately after "Plugin version:" — stop at the first run of
    # [0-9.] so a same-line trailer (README's "X.Y.Z · Upstream schema verified: ...")
    # doesn't get slurped into the comparison. \s is not portable in BSD sed's ERE,
    # so match on [[:space:]] instead.
    v=$(grep -m1 -E 'Plugin version:' "$f" | sed -E 's/.*Plugin version:[[:space:]]*([0-9][0-9.]*).*/\1/')
    if [[ "$v" != "$PLUGIN_VERSION" ]]; then
        fail "(c) version: $f stamp header version '$v' != $PLUGIN_VERSION"
        STAMP_MISMATCHES=$((STAMP_MISMATCHES+1))
    fi
done < <(find "$REPO_ROOT/adapters" \( -name 'SKILL.md' -o -name '*.toml' -o -name 'README.md' -o -name 'GEMINI.md' -o -name 'AGENTS.temper.md' \) 2>/dev/null | LC_ALL=C sort)
if [[ $STAMP_TOTAL -gt 0 && $STAMP_MISMATCHES -eq 0 ]]; then
    ok "(c) version: all $STAMP_TOTAL md/toml stamp headers match $PLUGIN_VERSION"
elif [[ $STAMP_TOTAL -eq 0 ]]; then
    fail "(c) version: no stamped md/toml files found under adapters/"
fi

# ==============================================================================
# (d) Required-file manifest + wiring
# ==============================================================================
REQUIRED_FILES=(
    "adapters/codex/.codex-plugin/plugin.json"
    "adapters/codex/skills/temper-core/SKILL.md"
    "adapters/codex/skills/temper-plan/SKILL.md"
    "adapters/codex/skills/temper-build/SKILL.md"
    "adapters/codex/skills/temper-review/SKILL.md"
    "adapters/codex/skills/temper-check/SKILL.md"
    "adapters/codex/skills/temper-fix/SKILL.md"
    "adapters/codex/skills/temper-init/SKILL.md"
    "adapters/codex/AGENTS.temper.md"
    "adapters/codex/README.md"
    ".agents/plugins/marketplace.json"
    "adapters/cursor/.cursor-plugin/plugin.json"
    "adapters/cursor/skills/temper-core/SKILL.md"
    "adapters/cursor/skills/temper-plan/SKILL.md"
    "adapters/cursor/skills/temper-build/SKILL.md"
    "adapters/cursor/skills/temper-review/SKILL.md"
    "adapters/cursor/skills/temper-check/SKILL.md"
    "adapters/cursor/skills/temper-fix/SKILL.md"
    "adapters/cursor/skills/temper-init/SKILL.md"
    "adapters/cursor/README.md"
    ".cursor-plugin/marketplace.json"
    "adapters/gemini/gemini-extension.json"
    "adapters/gemini/GEMINI.md"
    "adapters/gemini/commands/temper.toml"
    "adapters/gemini/commands/temper/plan.toml"
    "adapters/gemini/commands/temper/build.toml"
    "adapters/gemini/commands/temper/review.toml"
    "adapters/gemini/commands/temper/check.toml"
    "adapters/gemini/commands/temper/fix.toml"
    "adapters/gemini/commands/temper/status.toml"
    "adapters/gemini/commands/temper/init.toml"
    "adapters/gemini/README.md"
)
MISSING=0
for f in "${REQUIRED_FILES[@]}"; do
    [[ -f "$REPO_ROOT/$f" ]] || { fail "(d) required-file: $f missing"; MISSING=$((MISSING+1)); }
done
[[ $MISSING -eq 0 ]] && ok "(d) required-file: all ${#REQUIRED_FILES[@]} required files present" || true

# Wiring: manifest-referenced paths resolve on disk.
wiring_check() {
    local desc="$1" path="$2"
    if [[ -e "$REPO_ROOT/$path" ]]; then
        ok "(d) wiring: $desc -> $path resolves"
    else
        fail "(d) wiring: $desc -> $path does NOT resolve"
    fi
}
CODEX_SKILLS_FIELD=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/adapters/codex/.codex-plugin/plugin.json'))['skills'])")
wiring_check "codex plugin.json 'skills'" "adapters/codex/${CODEX_SKILLS_FIELD#./}"
CODEX_MKT_PATH=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/.agents/plugins/marketplace.json'))['plugins'][0]['source']['path'])")
wiring_check ".agents marketplace 'source.path'" "${CODEX_MKT_PATH#./}"

CURSOR_SKILLS_FIELD=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/adapters/cursor/.cursor-plugin/plugin.json'))['skills'])")
wiring_check "cursor plugin.json 'skills'" "adapters/cursor/${CURSOR_SKILLS_FIELD#./}"
CURSOR_MKT_PATH=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/.cursor-plugin/marketplace.json'))['plugins'][0]['source'])")
wiring_check ".cursor-plugin marketplace 'source'" "$CURSOR_MKT_PATH"

GEMINI_CTX=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/adapters/gemini/gemini-extension.json'))['contextFileName'])")
wiring_check "gemini-extension.json 'contextFileName'" "adapters/gemini/$GEMINI_CTX"

# ==============================================================================
# (e) Gate-protocol grep guard (SC4) — no generated file reimplements a verdict.
# Descriptive mentions of reading `.temper/gates.json` (e.g. the status command's
# own documented behavior, carried over verbatim from commands/status.md) are NOT
# a violation — the violation is a generated file WRITING the ledger or computing
# a verdict itself instead of calling `temper gate`/`temper evidence`.
# ==============================================================================
VERDICT_MARKERS_FOUND=0
while IFS= read -r f; do
    # Write-style access to the ledger (redirect, python open(...'w'), json.dump).
    if grep -Eq '(>{1,2}[[:space:]]*[^[:space:]]*gates\.json|gates\.json["\x27]?[[:space:]]*,[[:space:]]*["\x27]w|json\.dump\([^)]*gates)' "$f" 2>/dev/null; then
        fail "(e) gate-protocol: $f writes to gates.json directly (verdict ledger must only be written by scripts/temper)"
        VERDICT_MARKERS_FOUND=$((VERDICT_MARKERS_FOUND+1))
    fi
    # A verdict computed/assigned in generated content instead of delegated to the CLI.
    if grep -Eiq '(^|[^a-zA-Z_])verdict[[:space:]]*=[[:space:]]*["\x27]?(PASS|FAIL)["\x27]?([[:space:]]|$)' "$f" 2>/dev/null; then
        fail "(e) gate-protocol: $f assigns a verdict literal instead of calling 'temper gate'"
        VERDICT_MARKERS_FOUND=$((VERDICT_MARKERS_FOUND+1))
    fi
done < <(find "$REPO_ROOT/adapters" "$REPO_ROOT/.agents" "$REPO_ROOT/.cursor-plugin" -type f \( -name '*.md' -o -name '*.toml' -o -name '*.json' \) 2>/dev/null | LC_ALL=C sort)
[[ $VERDICT_MARKERS_FOUND -eq 0 ]] && ok "(e) gate-protocol: no verdict-logic markers found in generated files" || true

GATE_REF_COUNT=$(grep -rl 'temper gate\|temper evidence' "$REPO_ROOT/adapters" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$GATE_REF_COUNT" -gt 0 ]]; then
    ok "(e) gate-protocol: $GATE_REF_COUNT generated files reference the CLI (temper gate / temper evidence)"
else
    fail "(e) gate-protocol: no generated file references 'temper gate' / 'temper evidence' — epilogue missing?"
fi

# ==============================================================================
# (f) Install-docs guard (SC6) — README install section has no script invocation
# ==============================================================================
README="$REPO_ROOT/README.md"
START_MARKER='<!-- temper:install:start -->'
END_MARKER='<!-- temper:install:end -->'
if [[ ! -f "$README" ]]; then
    fail "(f) install-docs: README.md not found"
elif ! grep -qF "$START_MARKER" "$README" || ! grep -qF "$END_MARKER" "$README"; then
    fail "(f) install-docs: README.md is missing the machine-detectable install-section anchors ($START_MARKER / $END_MARKER — see design.md Open Question #4; add them when reworking the install section)"
else
    SECTION=$(awk "/$(printf '%s' "$START_MARKER" | sed 's/[.[\*^$()+?{|/]/\\&/g')/{flag=1; next} /$(printf '%s' "$END_MARKER" | sed 's/[.[\*^$()+?{|/]/\\&/g')/{flag=0} flag" "$README")
    if echo "$SECTION" | grep -qE 'generate-[a-zA-Z-]+\.sh|install-[a-zA-Z-]+\.sh'; then
        fail "(f) install-docs: README install section invokes a generate-*.sh / install-*.sh script"
        echo "$SECTION" | grep -E 'generate-[a-zA-Z-]+\.sh|install-[a-zA-Z-]+\.sh' | sed 's/^/  /'
    else
        ok "(f) install-docs: README install section has no generate-*.sh / install-*.sh invocation"
    fi
fi

echo ""
echo "=== validate-adapters.sh ==="
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
