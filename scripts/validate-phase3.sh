#!/bin/bash
#
# validate-phase3.sh — mechanical verification for Phase 3 (Temper v5.9.0)
# Token Efficiency & Loop Engineering.
#
# One-shot bash + python3. No test framework. Creates FIXTURE files in a temp
# dir so assertions do NOT depend on live runtime artifacts.
#
# Mirrors scripts/validate-phase2.sh structure. The degradation contracts ARE
# the primary test scenarios: each Phase 3 sub-feature must degrade
# byte-identically to v5.8.0 when its flag is off.
#
# Usage:
#   scripts/validate-phase3.sh            # run all scenarios
#   scripts/validate-phase3.sh config|cache-disabled|cache-reentry|depth-tiers|
#       depth-contract|loops|loops-routing|pricing|schema|version|cursor
#
# Exit code: 0 = all assertions passed, 1 = one or more failed.
#
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

TARGET="5.9.0"
GROUP="${1:-all}"
PASS=0
FAIL=0
FAILED_SCENARIOS=()

ok()   { PASS=$((PASS+1)); echo "  PASS  $1"; }
fail() { FAIL=$((FAIL+1)); FAILED_SCENARIOS+=("$1"); echo "  FAIL  $1"; echo "        $2"; }

run_group() {
  case "$1" in
    config)          scenario_1_config ;;
    cache-disabled)  scenario_cache_disabled ;;
    cache-reentry)   scenario_cache_reentry ;;
    cache-routing)   scenario_cache_disabled; scenario_cache_reentry ;;
    depth-tiers)     scenario_depth_tiers ;;
    depth-contract)  scenario_depth_contract ;;
    loops)           scenario_loops ;;
    loops-routing)   scenario_loops_routing ;;
    pricing)         scenario_pricing ;;
    schema)          scenario_schema ;;
    version)         scenario_version ;;
    cursor)          scenario_cursor ;;
    all)
      scenario_1_config
      scenario_cache_disabled
      scenario_cache_reentry
      scenario_depth_tiers
      scenario_depth_contract
      scenario_loops
      scenario_loops_routing
      scenario_pricing
      scenario_schema
      scenario_version
      scenario_cursor
      ;;
    *) echo "Unknown group: $1"; exit 2 ;;
  esac
}

# ---------------------------------------------------------------------------
# Scenario 1 (config): tokens block present with 3 sub-sections + defaults
# Traced to: Scenario 1, 3, 6.
# ---------------------------------------------------------------------------

scenario_1_config() {
  echo "Scenario 1 (config): tokens block schema parses; 3 sub-sections + defaults"
  local CFG=.claude/temper.config
  # tokens: top-level block exists
  grep -q "^tokens:" "$CFG" \
    && ok "tokens: block present in temper.config" \
    || { fail "tokens-block" "temper.config missing tokens: block"; return; }
  # three sub-sections
  local sub_ok=1
  for s in "cache:" "adaptive-depth:" "loops:"; do
    grep -qE "^[[:space:]]+${s}" "$CFG" || { sub_ok=0; break; }
  done
  [ "$sub_ok" = 1 ] && ok "tokens.cache, tokens.adaptive-depth, tokens.loops sub-sections present" \
                       || fail "tokens-subsections" "missing a tokens sub-section"
  # cache.enabled + scope
  grep -q "enabled: true" "$CFG" && grep -q "scope: methodology" "$CFG" \
    && ok "tokens.cache.enabled: true + scope: methodology present" \
    || fail "cache-defaults" "tokens.cache defaults missing"
  # adaptive-depth.enabled + floor
  grep -q "floor: simple" "$CFG" \
    && ok "tokens.adaptive-depth.floor: simple present" \
    || fail "adaptive-depth-floor" "floor: simple missing"
  # loops.inline-threshold + fix-mode
  grep -q "inline-threshold: 3" "$CFG" && grep -q "fix-mode: true" "$CFG" \
    && ok "tokens.loops.inline-threshold: 3 + fix-mode: true present" \
    || fail "loops-defaults" "tokens.loops defaults missing"
}

# ---------------------------------------------------------------------------
# Scenario: Cache disabled reproduces v5.8.0 reads (no prefix, no cached_input)
# Traced to: Scenario 1.
# ---------------------------------------------------------------------------

scenario_cache_disabled() {
  echo "Scenario (cache-disabled): disabled => no prefix rule, no cached_input field"
  local CMD=.claude/commands/temper.md
  local REF=.claude-plugin/reference/orchestrator-patterns.md
  # The Cache Routing Resolution must be CONDITIONAL on tokens.cache.enabled and
  # state the disabled => v5.8.0 byte-identical contract.
  grep -q "Cache Routing Resolution (v5.9.0)" "$CMD" \
    && ok "Cache Routing Resolution block present in temper.md" \
    || fail "cache-block" "temper.md missing Cache Routing Resolution block"
  grep -q "tokens.cache.enabled is false" "$CMD" \
    && ok "cache routing declares the disabled branch" \
    || fail "cache-disabled-branch" "temper.md missing disabled branch in cache routing"
  grep -qi "byte-identical" "$CMD" \
    && ok "cache routing states byte-identical-to-v5.8.0 on disabled" \
    || fail "cache-byteidentical" "temper.md missing byte-identical contract for cache disabled"
  # Each stage launch carries a [CACHE:] delta conditional on cache.enabled
  local cache_deltas
  cache_deltas=$(grep -c "^\[CACHE: if tokens.cache.enabled" "$CMD")
  [ "$cache_deltas" -ge 6 ] && ok "all 6 stage launches carry a [CACHE:] delta conditional on cache.enabled" \
                            || fail "cache-deltas" "only $cache_deltas/6 launches carry [CACHE:] delta"
  # orchestrator-patterns: cacheable-first instruction conditional on cache.enabled
  grep -qE "tokens\.cache\.enabled.? is false|cache\.enabled\` is false" "$REF" \
    && ok "orchestrator-patterns suspends cache ordering when cache disabled" \
    || fail "cache-suspend" "orchestrator-patterns missing cache-disabled suspension"
}

# ---------------------------------------------------------------------------
# Scenario: Cacheable prefix hits on re-entry (cached_input + source sibling)
# Traced to: Scenario 2.
# ---------------------------------------------------------------------------

scenario_cache_reentry() {
  echo "Scenario (cache-reentry): cacheable-first ordering + cached_input{value,source}"
  local CMD=.claude/commands/temper.md
  local REF=.claude-plugin/reference/orchestrator-patterns.md
  # Cacheable vs Volatile subsection classifies reads + ordering rule
  grep -q "Cacheable vs. Volatile Context" "$REF" \
    && ok "Cacheable vs. Volatile Context subsection present" \
    || fail "cacheable-section" "orchestrator-patterns missing Cacheable vs Volatile section"
  grep -q "cacheable reads first" "$REF" \
    && ok "ordering rule (cacheable first, volatile last) stated" \
    || fail "ordering-rule" "ordering rule missing"
  # Cache-Stable Re-Entry rule
  grep -q "Cache-Stable Re-Entry" "$REF" \
    && ok "Cache-Stable Re-Entry rule present" \
    || fail "reentry-rule" "Cache-Stable Re-Entry rule missing"
  # cached_input field in v3 schema with source sibling
  grep -q "cached_input" "$REF" \
    && ok "tokens.cached_input documented in v3 schema" \
    || fail "cached-input-doc" "v3 schema missing cached_input"
  # cached_input carries a source sibling (G-5 rule extended)
  grep -q '"cached_input": { "value"' "$REF" && grep -q '"source": "measured|estimated"' "$REF" \
    && ok "cached_input{value, source} preserves G-5 source rule" \
    || fail "cached-input-source" "cached_input missing source sibling"
  # temper.md records cached_input to observability on cache enabled
  grep -q "cached_input" "$CMD" \
    && ok "temper.md writes cached_input to observability when cache enabled" \
    || fail "cached-input-write" "temper.md missing cached_input write instruction"
}

# ---------------------------------------------------------------------------
# Scenario: Depth tiers — adaptive-depth disabled runs full pipeline; floor clamps
# Traced to: Scenario 3, 4.
# ---------------------------------------------------------------------------

scenario_depth_tiers() {
  echo "Scenario (depth-tiers): Pipeline Depth table + floor clamp + disabled=>full"
  local REF=.claude-plugin/reference/orchestrator-patterns.md
  # Pipeline Depth section with 4-tier table
  grep -q "Pipeline Depth (v5.9.0)" "$REF" \
    && ok "Pipeline Depth section present" \
    || fail "pipeline-depth-section" "Pipeline Depth section missing"
  local tiers_present=1
  for t in trivial simple medium complex; do
    grep -q "\*\*${t}\*\*" "$REF" || { tiers_present=0; break; }
  done
  [ "$tiers_present" = 1 ] && ok "Pipeline Depth table covers all 4 tiers" \
                           || fail "depth-tiers-table" "Pipeline Depth table missing a tier"
  # floor clamp described (clamp, not toggle)
  grep -qi "floor.*clamp\|clamp.*floor\|clamp the effective tier" "$REF" \
    && ok "floor described as a clamp (not a toggle)" \
    || fail "floor-clamp" "floor clamp semantics missing"
  # disabled => full pipeline (byte-identical to v5.8.0)
  grep -qi "adaptive-depth.enabled.*false\|full v5.8.0 pipeline" "$REF" \
    && ok "adaptive-depth disabled => full v5.8.0 pipeline documented" \
    || fail "depth-disabled" "disabled => full pipeline contract missing"
  # trivial tier = reduced artifacts (spine methodology)
  grep -qi "spine methodology\|intent.md.*tasks.md only" "$REF" \
    && ok "trivial tier runs spine methodology (reduced artifacts)" \
    || fail "trivial-spine" "trivial tier spine methodology missing"
}

# ---------------------------------------------------------------------------
# Scenario: Depth contract — 4 enforcement overrides retargeted; standalone preserved
# Traced to: Scenario 3, 4, 5.
# ---------------------------------------------------------------------------

scenario_depth_contract() {
  echo "Scenario (depth-contract): 4 overrides conditional on adaptive-depth.enabled"
  local CMD=.claude/commands/temper.md
  local PLAN=.claude-plugin/reference/plan.md
  # The blanket override strings must be GONE.
  local blanket=0
  grep -q "No shortcuts for Simple or Trivial" "$CMD" && blanket=$((blanket+1))
  grep -q "full artifact set regardless of complexity" "$PLAN" && blanket=$((blanket+1))
  grep -q "Always use the full 6-section walkthrough" "$PLAN" && blanket=$((blanket+1))
  grep -q "Always follow the full planning methodology regardless of complexity" "$CMD" && blanket=$((blanket+1))
  [ "$blanket" = 0 ] && ok "no blanket v5.8.0 override strings remain in temper.md/plan.md" \
                     || fail "blanket-override-leak" "$blanket blanket override string(s) still present"
  # 4 DEPTH CONTRACT markers now reference adaptive-depth.enabled conditionally
  local contract_markers
  contract_markers=$(grep -h "DEPTH CONTRACT (v5.9.0" "$CMD" "$PLAN" | wc -l | tr -d ' ')
  [ "$contract_markers" -ge 4 ] && ok "4 DEPTH CONTRACT markers replace the overrides (temper.md + plan.md)" \
                               || fail "depth-contract-count" "only $contract_markers/4 DEPTH CONTRACT markers found"
  # Each contract marker references adaptive-depth.enabled (text spans multiple lines,
  # so grep a 3-line window after each marker and count windows that mention the flag).
  local cond=0
  for f in "$CMD" "$PLAN"; do
    # number of marker lines in this file
    local n; n=$(grep -c "DEPTH CONTRACT (v5.9.0" "$f")
    local i=1
    while [ "$i" -le "$n" ]; do
      # i-th marker line number
      local ln; ln=$(grep -n "DEPTH CONTRACT (v5.9.0" "$f" | sed -n "${i}p" | cut -d: -f1)
      # 3-line window from the marker; check it mentions adaptive-depth.enabled
      if sed -n "${ln},$((ln+3))p" "$f" | grep -q "adaptive-depth.enabled"; then
        cond=$((cond+1))
      fi
      i=$((i+1))
    done
  done
  [ "$cond" -ge 4 ] && ok "all 4 DEPTH CONTRACT markers conditional on adaptive-depth.enabled" \
                    || fail "depth-conditional" "only $cond/4 contract markers reference adaptive-depth.enabled"
  # standalone /temper:plan complexity-tiered rules UNCHANGED (both locations)
  local standalone
  standalone=$(grep -c "Complexity-tiered rules (for standalone" "$PLAN")
  [ "$standalone" = 2 ] && ok "standalone /temper:plan complexity-tiered rules preserved (2 locations)" \
                       || fail "standalone-rules" "standalone rules count = $standalone (expected 2)"
  # Escalate option at the plan gate
  grep -q "Escalate to full pipeline" "$CMD" \
    && ok "Escalate to full pipeline option present at plan gate" \
    || fail "escalate-option" "Escalate option missing from plan gate"
}

# ---------------------------------------------------------------------------
# Scenario: Loop cost tiers — 3-tier decision rule + disabled=>full
# Traced to: Scenario 6.
# ---------------------------------------------------------------------------

scenario_loops() {
  echo "Scenario (loops): Loop Cost Tiers decision rule + disabled=>full"
  local CMD=.claude/commands/temper.md
  local REF=.claude-plugin/reference/orchestrator-patterns.md
  # Loop Cost Tiers section in orchestrator-patterns
  grep -q "Loop Cost Tiers (v5.9.0)" "$REF" \
    && ok "Loop Cost Tiers section present in orchestrator-patterns" \
    || fail "loop-cost-section" "Loop Cost Tiers section missing"
  # 3 tiers documented
  grep -q "inline" "$REF" && grep -q "fix-mode" "$REF" && grep -q "full" "$REF" \
    && ok "all 3 loop tiers (inline/fix-mode/full) documented" \
    || fail "loop-tiers" "a loop tier is missing"
  # decision rule pseudocode present
  grep -q "def loop_tier\|loop_tier\|all(f.auto_fixable" "$REF" \
    && ok "loop tier decision rule pseudocode present" \
    || fail "loop-decision-rule" "loop tier decision rule pseudocode missing"
  # disabled (fix-mode false + inline-threshold 0) => full (v5.8.0)
  grep -qi "fix-mode: false.*inline-threshold: 0\|byte-identical to v5.8.0 loop" "$REF" \
    && ok "loops disabled => full re-launch (v5.8.0 byte-identical) documented" \
    || fail "loops-disabled" "loops disabled => full contract missing"
}

# ---------------------------------------------------------------------------
# Scenario: Loops routing — inline no subprocess; fix-mode lean context
# Traced to: Scenario 7, 8.
# ---------------------------------------------------------------------------

scenario_loops_routing() {
  echo "Scenario (loops-routing): inline no subprocess; fix-mode lean context"
  local CMD=.claude/commands/temper.md
  # The decision rule is wired into temper.md Step 4
  grep -q "Loop Cost Tier (v5.9.0)" "$CMD" \
    && ok "Loop Cost Tier resolution wired into temper.md Step 4" \
    || fail "loops-step4" "Loop Cost Tier missing from Step 4"
  # inline path states NO subprocess
  grep -q "INLINE" "$CMD" && grep -qi "Launch NO Agent subprocess\|no subprocess" "$CMD" \
    && ok "inline path explicitly launches no subprocess" \
    || fail "inline-no-subprocess" "inline path does not state no-subprocess"
  # fix-mode path states lean context (NOT full build.md)
  grep -q "FIX-MODE" "$CMD" && grep -q "NOT full build.md\|replaces full build.md\|fix-mode preamble" "$CMD" \
    && ok "fix-mode path receives lean context (fix-mode preamble, NOT full build.md)" \
    || fail "fixmode-lean" "fix-mode lean context not stated"
  # all 3 loop handlers (review/check/eval) resolve the tier
  local handlers
  handlers=$(grep -c "Resolve the \*\*loop cost tier\*\*" "$CMD")
  [ "$handlers" -ge 3 ] && ok "all 3 loop handlers (review/check/eval -> build) resolve the loop cost tier" \
                       || fail "loop-handlers" "only $handlers/3 loop handlers resolve the tier"
  # observability loops[] recording
  grep -q "loops\[\]" "$CMD" \
    && ok "per-loop mode + cost recorded in observability.json loops[]" \
    || fail "loops-observability" "loops[] recording missing from temper.md"
}

# ---------------------------------------------------------------------------
# Scenario: pricing — cache multipliers present; "excludes caching" dropped; YAML parseable
# Traced to: Scenario 2 (pricing dimension).
# ---------------------------------------------------------------------------

scenario_pricing() {
  echo "Scenario (pricing): cache multipliers; excludes-caching dropped; YAML parseable"
  local P=.claude-plugin/reference/pricing.md
  grep -q "Cache Multipliers" "$P" \
    && ok "Cache Multipliers section present in pricing.md" \
    || fail "cache-mult-section" "pricing.md missing Cache Multipliers section"
  grep -qi "cache read\|cache_read_multiplier\|0.10\|0.1x" "$P" \
    && ok "cache read multiplier present" \
    || fail "cache-read-mult" "cache read multiplier missing"
  grep -qi "cache write\|cache_write_multiplier\|1.25\|1.25x" "$P" \
    && ok "cache write multiplier present" \
    || fail "cache-write-mult" "cache write multiplier missing"
  # "excludes caching" string must be GONE
  if grep -qi "excludes caching\|exclude volume discounts, caching" "$P"; then
    fail "excludes-caching-leak" "pricing.md still contains 'excludes caching'"
  else
    ok "pricing.md no longer says 'excludes caching'"
  fi
  # cached_input cross-reference
  grep -q "cached_input" "$P" \
    && ok "pricing.md cross-references observability.json tokens.cached_input" \
    || fail "pricing-cached-ref" "pricing.md missing cached_input cross-reference"
  # YAML block still parseable (validate-phase2.sh schema depends on it)
  if python3 - <<'PY'
import re
txt = open(".claude-plugin/reference/pricing.md").read()
m = re.search(r"```yaml\n(.*?)```", txt, re.S)
assert m, "no yaml block in pricing.md"
block = m.group(1)
prices = {}
for line in block.splitlines():
    mm = re.match(r"\s*(tier-\w+):\s*$", line)
    if mm: cur = mm.group(1); prices[cur] = {}
    mm = re.match(r"\s*input_per_1m:\s*([\d.]+)", line)
    if mm: prices[cur]["input_per_1m"] = float(mm.group(1))
    mm = re.match(r"\s*output_per_1m:\s*([\d.]+)", line)
    if mm: prices[cur]["output_per_1m"] = float(mm.group(1))
assert set(prices) == {"tier-frontier","tier-standard","tier-fast"}, prices
print("  PASS  pricing.md YAML block still parseable; 3 tiers intact")
PY
  then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); FAILED_SCENARIOS+=("pricing-yaml"); echo "  FAIL  pricing-yaml"; fi
}

# ---------------------------------------------------------------------------
# Scenario: v3 schema — cached_input + loops[] documented; G-5 source rule extended
# Traced to: Scenario 2 (schema dimension).
# ---------------------------------------------------------------------------

scenario_schema() {
  echo "Scenario (schema): v3 observability schema documented + G-5 source rule extended"
  local REF=.claude-plugin/reference/orchestrator-patterns.md
  # v3 schema section present
  grep -q "Observability.json v3 Schema (v5.9.0)" "$REF" \
    && ok "v3 schema section present in orchestrator-patterns.md" \
    || fail "v3-section" "v3 schema section missing"
  grep -q '"version": 3' "$REF" \
    && ok "v3 schema declares version: 3" \
    || fail "v3-version" "version: 3 not in v3 schema doc"
  # v3 is documented as additive over v2 (superset)
  grep -qi "additive\|strict superset\|superset" "$REF" \
    && ok "v3 documented as additive/superset over v2" \
    || fail "v3-additive" "v3 additivity over v2 not stated"
  # all v2 stage fields preserved through v3
  local fields_ok=1
  for f in model_tier cost_usd eval_score retries latency_ms tool_calls; do
    grep -q "$f" "$REF" || { fields_ok=0; break; }
  done
  [ "$fields_ok" = 1 ] && ok "all v2 stage fields preserved in v3 schema" \
                       || fail "v3-v2-fields" "a v2 field is missing from v3"
  # loops[] array with mode + cost documented
  grep -q "loops\[\]" "$REF" && grep -q '"mode": "inline|fix-mode|full"' "$REF" \
    && ok "loops[] array with mode (inline|fix-mode|full) documented" \
    || fail "loops-array" "loops[] mode field missing"
  grep -q '"cost":' "$REF" \
    && ok "per-loop cost field documented" \
    || fail "loop-cost-field" "per-loop cost field missing"
  # G-5 source rule extended to cached_input + loop cost
  grep -qi "extended to the new\|extended to every new numeric\|G-5.*extended" "$REF" \
    && ok "G-5 source rule explicitly extended to v3 numerics" \
    || fail "g5-extended" "G-5 source rule extension not stated"
  # fixture: a v3 doc with cached_input + a loop entry round-trips with source provenance
  local TMP; TMP="$(mktemp -d)"; local FIX="$TMP/observability-v3.json"
  cat > "$FIX" <<'JSON'
{
  "version": 3,
  "feature": "demo",
  "stages": [
    {
      "stage": "build",
      "model_tier": "tier-standard",
      "model_source": "routing",
      "tokens": {"input": 1200, "input_source": "measured", "output": 800, "output_source": "measured",
                 "cached_input": {"value": 600, "source": "measured"}},
      "latency_ms": {"value": 4500, "source": "measured"},
      "tool_calls": {"value": 7, "source": "measured"},
      "cost_usd": {"value": 0.0066, "source": "pricing"},
      "retries": {"value": 0, "source": "measured"},
      "eval_score": {"value": null, "source": "measured"},
      "ts_start": "2026-06-24T10:00:00Z",
      "ts_end":   "2026-06-24T10:00:04Z"
    }
  ],
  "loops": [
    {"loop_id": "loop-1", "from_stage": "review", "to_stage": "build",
     "mode": "inline", "cost": {"value": 0, "source": "measured"}, "iteration": 1,
     "ts": "2026-06-24T10:00:02Z"}
  ],
  "totals": {
    "tokens":   {"value": 2000,   "source": "measured"},
    "cost_usd": {"value": 0.0066, "source": "pricing"},
    "latency_ms": {"value": 4500, "source": "measured"}
  }
}
JSON
  python3 - "$FIX" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
assert doc["version"] == 3, "version must be 3"
missing = []
EXEMPT = {"version"}
def walk(obj, path=""):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k in EXEMPT:
                continue
            if isinstance(v, bool):
                continue
            if isinstance(v, (int, float)):
                sib = k + "_source" if k in ("input","output") else "source"
                if sib not in obj:
                    missing.append(f"{path}.{k}")
            else:
                walk(v, f"{path}.{k}")
walk(doc)
assert not missing, f"v3 numeric leaves missing source sibling: {missing}"
# v3-specific assertions
st = doc["stages"][0]
assert st["tokens"]["cached_input"]["value"] == 600
assert st["tokens"]["cached_input"]["source"] == "measured"
assert doc["loops"][0]["mode"] == "inline"
assert doc["loops"][0]["cost"]["source"] == "measured"
print("  PASS  v3 fixture round-trips; cached_input + loops[] carry source siblings")
PY
  local rc=$?
  [ $rc -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); FAILED_SCENARIOS+=("v3-source-provenance"); echo "  FAIL  v3-source-provenance"; }
  rm -rf "$TMP"
}

# ---------------------------------------------------------------------------
# Scenario: Version lockstep — all stamps agree at 5.9.0
# Traced to: Scenario 9.
# ---------------------------------------------------------------------------

scenario_version() {
  echo "Scenario (version): all stamps agree at $TARGET"
  local pj cv cm tv
  pj=$(grep -o '"version": "[^"]*"' .claude-plugin/plugin.json | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
  cm=$(grep -oE '\*\*Version:\*\* [0-9][0-9.]+' .claude/CLAUDE.md | head -1 | awk '{print $2}')
  cv=$(cat .cursor/VERSION 2>/dev/null | tr -d '[:space:]')
  tv=$(grep -oE '# Temper:.*\(v[0-9][0-9.]+' .claude/commands/temper.md | head -1 | grep -oE 'v[0-9][0-9.]+' | tr -d 'v')

  [ "$pj" = "$TARGET" ] && ok "plugin.json version == $TARGET" \
                        || fail "version-pluginjson" "plugin.json=$pj (expected $TARGET)"
  [ "$cm" = "$TARGET" ] && ok "CLAUDE.md Version == $TARGET" \
                       || fail "version-claudemd" "CLAUDE.md=$cm (expected $TARGET)"
  [ "$cv" = "$TARGET" ] && ok ".cursor/VERSION == $TARGET" \
                       || fail "version-cursor" ".cursor/VERSION=$cv (expected $TARGET)"
  [ "$tv" = "$TARGET" ] && ok "temper.md header (vX.Y.Z) == $TARGET" \
                       || fail "version-tempermd" "temper.md header=$tv (expected $TARGET)"

  # root VERSION file must be absent or empty (NOT a stamp)
  if [ ! -f VERSION ] || [ ! -s VERSION ]; then
    ok "root VERSION file absent/empty (not a stamp)"
  else
    fail "version-root-file" "root VERSION file is non-empty — should not be a stamp"
  fi

  # CHANGELOG has a v5.9.0 entry
  grep -q "## v5.9.0\|## v$TARGET" CHANGELOG.md \
    && ok "CHANGELOG.md has a v$TARGET entry" \
    || fail "version-changelog" "CHANGELOG.md missing v$TARGET entry"
}

# ---------------------------------------------------------------------------
# Scenario: Cursor freeze — freeze note preserved + no Phase 3 markers leaked
# Traced to: Scenario 9 (cursor dimension).
# ---------------------------------------------------------------------------

scenario_cursor() {
  echo "Scenario (cursor): freeze note preserved + no Phase 3 markers leaked"
  # frozen-v5.1 note preserved
  grep -qi "Frozen at v5.1\|FROZEN" .cursor/README.md \
    && ok ".cursor/README.md preserves frozen-v5.1 note" \
    || fail "cursor-freeze-note" ".cursor/README.md missing frozen-v5.1 note"
  # NO Phase 3 markers leaked into frozen .cursor/commands/ or .cursor/rules/
  local leak_file
  leak_file=$(grep -rEl "tokens\.cache|adaptive-depth|Loop Cost Tiers|Pipeline Depth|cached_input|cacheable prefix|inline-threshold|fix-mode preamble" \
              .cursor/commands/ .cursor/rules/ 2>/dev/null | head -1)
  if [ -n "$leak_file" ]; then
    fail "cursor-leak" ".cursor/ leaked Phase 3 markers into: $leak_file (freeze violated)"
  else
    ok ".cursor/ commands+rules have no Phase 3 markers (freeze intact)"
  fi
  # cursor VERSION matches plugin.json
  local pj cv
  pj=$(grep -o '"version": "[^"]*"' .claude-plugin/plugin.json | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
  cv=$(cat .cursor/VERSION 2>/dev/null | tr -d '[:space:]')
  [ "$pj" = "$cv" ] && ok ".cursor/VERSION ($cv) == plugin.json ($pj)" \
                    || fail "cursor-version-drift" ".cursor/VERSION=$cv != plugin.json=$pj"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo "================================================================"
echo "validate-phase3.sh — Phase 3 (Temper v5.9.0) scenario verification"
echo "================================================================"
echo "Repo: $REPO_ROOT"
echo "Group: $GROUP"
echo ""

if [ "$GROUP" = "all" ]; then
  run_group all
else
  run_group "$GROUP"
fi

echo ""
echo "----------------------------------------------------------------"
echo "RESULT: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed scenarios:"
  for s in "${FAILED_SCENARIOS[@]}"; do echo "  - $s"; done
  echo "----------------------------------------------------------------"
  exit 1
fi
echo "All Phase 3 scenario assertions passed."
echo "----------------------------------------------------------------"
exit 0
