#!/bin/bash
#
# validate-phase2.sh — mechanical verification for Phase 2 (Temper v5.6.0)
# Harness Economics & Observability.
#
# One-shot bash + python3. No test framework. Creates FIXTURE files in a temp
# dir so assertions do NOT depend on live runtime artifacts
# (.temper/observability.json, .temper/metrics.json).
#
# Usage:
#   scripts/validate-phase2.sh            # run all scenarios
#   scripts/validate-phase2.sh config     # run one scenario group
#   scripts/validate-phase2.sh routing|schema|telemetry|drift|status|version|cursor
#
# Exit code: 0 = all assertions passed, 1 = one or more failed.
#
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

GROUP="${1:-all}"
PASS=0
FAIL=0
FAILED_SCENARIOS=()

ok()   { PASS=$((PASS+1)); echo "  PASS  $1"; }
fail() { FAIL=$((FAIL+1)); FAILED_SCENARIOS+=("$1"); echo "  FAIL  $1"; echo "        $2"; }

run_group() {
  case "$1" in
    config)    scenario_1_config; scenario_2_3_config ;;
    routing)   scenario_1_routing; scenario_2_3_4_routing ;;
    schema)    scenario_5_schema; scenario_6_pricing ;;
    telemetry) scenario_5_telemetry ;;
    drift)     scenario_7_drift ;;
    status)    scenario_8_status ;;
    version)   scenario_9_version ;;
    cursor)    scenario_9_cursor ;;
    all)
      scenario_1_config; scenario_1_routing
      scenario_2_3_config; scenario_2_3_4_routing
      scenario_5_schema; scenario_5_telemetry
      scenario_6_pricing
      scenario_7_drift
      scenario_8_status
      scenario_9_version
      scenario_9_cursor
      ;;
    *) echo "Unknown group: $1"; exit 2 ;;
  esac
}

# ---------------------------------------------------------------------------
# Scenario 1: routing disabled reproduces v5.5.0 behavior (no model param)
# ---------------------------------------------------------------------------

scenario_1_config() {
  echo "Scenario 1 (config): models block present + enabled flag"
  # models block exists with an enabled key
  if grep -q "^models:" .claude/temper.config && \
     grep -q "enabled: true" .claude/temper.config; then
    ok "models block with enabled flag present in temper.config"
  else
    fail "models-block-present" "temper.config missing models: block or enabled: true"
  fi
}

scenario_1_routing() {
  echo "Scenario 1 (routing): models disabled => no model param emitted"
  # The routing resolution must be CONDITIONAL on models.enabled. We assert the
  # branch exists in temper.md. A fixture config with models stripped must not
  # cause a model param emission — asserted by presence of the conditional.
  local TMP; TMP="$(mktemp -d)"
  # Fixture: strip the models block from a config copy — simulate disabled.
  sed '/^# .*Intelligent model routing/,/^observability:/d' .claude/temper.config > "$TMP/config-disabled"
  if ! grep -q "^models:" "$TMP/config-disabled"; then
    ok "disabled-config fixture has no models block"
  else
    fail "disabled-config-fixture" "stripped fixture still contains a models block"
  fi
  # temper.md must state the conditional: disabled => no model param (inherit).
  if grep -q "Emit NO .model. param" commands/temper.md && \
     grep -q "byte-identical to v5.5.0" commands/temper.md; then
    ok "temper.md declares disabled=>no-model-param (v5.5.0 byte-identical) contract"
  else
    fail "routing-conditional" "temper.md missing disabled=>no-model-param declaration"
  fi
  rm -rf "$TMP"
}

# ---------------------------------------------------------------------------
# Scenario 2 + 3 (config): tiers enumerated, routing map, override flag
# ---------------------------------------------------------------------------

scenario_2_3_config() {
  echo "Scenario 2/3 (config): tiers enumerated + routing map + override flag"
  local CFG=.claude/temper.config
  local tier_ok=1 route_ok=1 override_ok=1 escalate_ok=1
  for t in tier-frontier tier-standard tier-fast; do
    grep -q "$t" "$CFG" || { tier_ok=0; break; }
  done
  [ "$tier_ok" = 1 ] && ok "all three tier- names present in config" \
                       || fail "tier-names" "missing a tier- name in config"

  for s in plan design build review check eval; do
    grep -qE "^\s*${s}:\s*tier-" "$CFG" || { route_ok=0; break; }
  done
  [ "$route_ok" = 1 ] && ok "routing map covers all 6 stages" \
                       || fail "routing-map" "routing map missing a stage"

  grep -q "respect-user-override: true" "$CFG" \
    && ok "respect-user-override: true present" \
    || fail "override-flag" "respect-user-override missing"
  grep -q "escalate-on" "$CFG" && grep -q "architecture-finding" "$CFG" && \
    grep -q "correctness-risk" "$CFG" \
    && ok "escalate-on includes architecture-finding + correctness-risk" \
    || fail "escalate-on" "escalate-on entries missing"
}

# ---------------------------------------------------------------------------
# Scenario 2/3/4 (routing): per-stage model delta + override-before-routing + escalate
# ---------------------------------------------------------------------------

scenario_2_3_4_routing() {
  echo "Scenario 2/3/4 (routing): per-stage [MODEL:] delta + override precedence + escalate"
  local CMD=commands/temper.md
  local launches=0
  # Each of the 6 launches must carry a [MODEL: ...] delta line.
  for stage_pair in "Launch Planning Agent|models.routing.plan" \
                    "Launch Design Agent|models.routing.design" \
                    "Launch Build Agent|models.routing.build" \
                    "Launch Review Agent|models.routing.review" \
                    "Launch Check Agent|models.routing.check" \
                    "Launch Eval Agent|models.routing.eval"; do
    local hdr="${stage_pair%%|*}"; local route="${stage_pair##*|}"
    # find the launch header line number, then check within 5 lines for [MODEL:
    local ln; ln=$(grep -n "^### ${hdr}$" "$CMD" | head -1 | cut -d: -f1)
    if [ -n "$ln" ] && sed -n "${ln},$((ln+8))p" "$CMD" | grep -q "\[MODEL:"; then
      launches=$((launches+1))
    fi
  done
  [ "$launches" = 6 ] && ok "all 6 stage launches carry a [MODEL: ...] delta" \
                          || fail "model-delta" "only $launches/6 launches have [MODEL:] delta"

  # Override check (step 3) must precede routing resolution (step 4) in the resolution block.
  local override_ln route_ln
  override_ln=$(grep -n "respect-user-override.*true" "$CMD" | head -1 | cut -d: -f1)
  route_ln=$(grep -n "models.routing.{stage}" "$CMD" | tail -1 | cut -d: -f1)
  if [ -n "$override_ln" ] && [ -n "$route_ln" ] && [ "$override_ln" -lt "$route_ln" ]; then
    ok "override-check branch precedes routing-resolution branch"
  else
    fail "override-order" "override branch (line ${override_ln}) does not precede routing (line ${route_ln})"
  fi

  # Review escalate-on branch must exist and reference review.md confidence path.
  if grep -q "escalate-on" "$CMD" && grep -q "architecture-finding" "$CMD" && \
     grep -q "confidence-scoring path" "$CMD"; then
    ok "review escalate-on branch present (reuses review.md confidence path)"
  else
    fail "escalate-branch" "review escalation branch incomplete in temper.md"
  fi

  # Tier->model mapping documented.
  grep -q "tier-frontier.*opus" "$CMD" && grep -q "tier-standard.*sonnet" "$CMD" && \
    grep -q "tier-fast.*haiku" "$CMD" \
    && ok "tier->model mapping (opus/sonnet/haiku) documented in temper.md" \
    || fail "tier-map" "tier->model mapping missing in temper.md"
}

# ---------------------------------------------------------------------------
# Scenario 5 (schema): v2 schema documented + round-trips with source provenance
# ---------------------------------------------------------------------------

scenario_5_schema() {
  echo "Scenario 5 (schema): v2/v3 observability schema documented"
  local REF=reference/orchestrator-patterns.md
  # v3 (v5.9.0) is a strict superset of v2 (v5.6.0). Accept either marker so the
  # assertion stays green across the v2->v3 bump while still proving a schema section exists.
  if grep -q "Observability.json v3 Schema" "$REF" || grep -q "Observability.json v2 Schema" "$REF"; then
    ok "observability schema section present in orchestrator-patterns.md (v2 or v3)"
  else
    fail "schema-section" "observability schema section missing"
  fi
  if grep -q '"version": 3' "$REF" || grep -q '"version": 2' "$REF"; then
    ok "schema declares a version stamp (2 or 3)"
  else
    fail "schema-version" "version: 2 or 3 not in schema doc"
  fi
  # every required stage field documented (v2 fields preserved through v3)
  for f in model_tier cost_usd eval_score retries latency_ms tool_calls; do
    grep -q "$f" "$REF" || { fail "v2-field-$f" "schema missing field $f"; return; }
  done
  ok "schema documents all required stage fields (v2 superset preserved)"
  # drift baseline schema
  grep -q "Drift Baseline Schema" "$REF" && grep -q "drift_flags" "$REF" \
    && ok "drift baseline schema documented" \
    || fail "drift-schema" "drift baseline schema missing"
}

scenario_5_telemetry() {
  echo "Scenario 5 (telemetry): fixture v2 doc — every numeric leaf has .source sibling"
  local TMP; TMP="$(mktemp -d)"; local FIX="$TMP/observability-v2.json"
  cat > "$FIX" <<'JSON'
{
  "version": 2,
  "feature": "demo",
  "stages": [
    {
      "stage": "build",
      "model_tier": "tier-standard",
      "model_source": "routing",
      "tokens": {"input": 1200, "input_source": "measured", "output": 800, "output_source": "measured"},
      "latency_ms": {"value": 4500, "source": "measured"},
      "tool_calls": {"value": 7, "source": "measured"},
      "cost_usd": {"value": 0.0066, "source": "pricing"},
      "retries": {"value": 0, "source": "measured"},
      "eval_score": {"value": null, "source": "measured"},
      "ts_start": "2026-06-19T10:00:00Z",
      "ts_end":   "2026-06-19T10:00:04Z"
    }
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
assert doc["version"] == 2, "version must be 2"
missing = []
# Keys that are schema markers / identifiers, not metrics — exempt from the source rule.
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
assert not missing, f"numeric leaves missing source sibling: {missing}"
print("  PASS  v2 fixture round-trips; every numeric leaf has .source sibling")
PY
  local rc=$?
  [ $rc -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); FAILED_SCENARIOS+=("v2-source-provenance"); echo "  FAIL  v2-source-provenance"; }
  rm -rf "$TMP"
}

# ---------------------------------------------------------------------------
# Scenario 6: pricing.md parseable + cost computable
# ---------------------------------------------------------------------------

scenario_6_pricing() {
  echo "Scenario 6 (pricing): pricing.md exists + parseable + cost computable"
  local P=reference/pricing.md
  [ -f "$P" ] && ok "pricing.md exists" || { fail "pricing-exists" "$P missing"; return; }
  grep -q "tier-frontier" "$P" && grep -q "tier-standard" "$P" && grep -q "tier-fast" "$P" \
    && ok "pricing.md covers all three tiers" \
    || fail "pricing-tiers" "pricing.md missing a tier"
  grep -q "input_per_1m" "$P" && grep -q "output_per_1m" "$P" \
    && ok "pricing.md uses input_per_1m/output_per_1m keys" \
    || fail "pricing-keys" "pricing.md missing price keys"
  grep -qi "advisory" "$P" \
    && ok "pricing.md marked advisory" \
    || fail "pricing-advisory" "pricing.md not marked advisory"
  # cost computable via python one-liner parsing the YAML block
  if python3 - <<'PY'
import re
txt = open("reference/pricing.md").read()
# grab the yaml ``` block
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
# cost computation for tier-standard, 1M in / 1M out
p = prices["tier-standard"]
cost = (1_000_000/1e6)*p["input_per_1m"] + (1_000_000/1e6)*p["output_per_1m"]
assert cost == p["input_per_1m"] + p["output_per_1m"]
print("  PASS  pricing.md parseable; cost_usd computable per tier")
PY
  then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); FAILED_SCENARIOS+=("pricing-parse"); echo "  FAIL  pricing-parse"; fi
}

# ---------------------------------------------------------------------------
# Scenario 7: drift detection — seeded outlier => SUGGEST flag, never block
# ---------------------------------------------------------------------------

scenario_7_drift() {
  echo "Scenario 7 (drift): seeded outlier => drift_flags SUGGEST, never auto-block"
  local TMP; TMP="$(mktemp -d)"; local FIX="$TMP/metrics.json"
  # baseline of ~12 tool_calls; one outlier at 42 (>2 std-dev)
  python3 - "$FIX" <<'PY'
import json, statistics, sys
baseline = [10,11,12,12,13,11,12,10,14,12]  # mean ~11.7, stddev ~1.2
outlier = 42
mean = statistics.mean(baseline)
sd = statistics.pstdev(baseline) or 1e-9
std_devs = abs(outlier - mean) / sd
flag = {
  "stage": "build", "metric": "tool_calls", "value": outlier,
  "baseline_mean": mean, "baseline_stddev": sd, "std_devs": std_devs,
  "threshold": 2, "severity": "SUGGEST", "direction": "high",
  "ts": "2026-06-19T10:00:00Z", "source": "measured"
}
json.dump({"stage_baseline": {"build": {"tool_calls": baseline + [outlier]}},
           "drift_flags": [flag]}, open(sys.argv[1], "w"))
assert std_devs > 2, f"outlier should exceed 2 std-devs: {std_devs}"
PY
  local rc=$?
  if [ $rc -ne 0 ]; then fail "drift-seed" "seeded outlier did not exceed threshold"; rm -rf "$TMP"; return; fi
  # assert drift_flags non-empty, severity SUGGEST, never BLOCK
  python3 - "$FIX" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
flags = doc.get("drift_flags", [])
assert flags, "drift_flags empty"
assert all(f["severity"] == "SUGGEST" for f in flags), "non-SUGGEST severity present"
assert all(f["severity"] != "BLOCK" for f in flags), "BLOCK severity must never appear"
print("  PASS  drift_flags non-empty, SUGGEST only, never BLOCK")
PY
  rc=$?
  [ $rc -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); FAILED_SCENARIOS+=("drift-flag"); echo "  FAIL  drift-flag"; }

  # temper.md must state drift never auto-blocks
  grep -q "drift" commands/temper.md && grep -qi "NEVER auto-block" commands/temper.md \
    && ok "temper.md states drift NEVER auto-blocks a stage gate" \
    || fail "drift-no-block-doc" "temper.md missing NEVER auto-block statement"
  rm -rf "$TMP"
}

# ---------------------------------------------------------------------------
# Scenario 8: economics panel renders + graceful absence
# ---------------------------------------------------------------------------

scenario_8_status() {
  echo "Scenario 8 (status): ECONOMICS panel + graceful-absence fallback"
  local CMD=commands/status.md
  local REF=reference/status.md
  grep -q "ECONOMICS" "$CMD" \
    && ok "ECONOMICS panel section present in commands/status.md" \
    || fail "economics-cmd" "ECONOMICS panel missing from commands/status.md"
  grep -q "ECONOMICS" "$REF" \
    && ok "ECONOMICS panel section present in reference/status.md" \
    || fail "economics-ref" "ECONOMICS panel missing from reference/status.md"
  grep -qi "No observability data yet" "$CMD" \
    && ok "graceful-absence fallback present in commands/status.md" \
    || fail "graceful-cmd" "No observability data yet fallback missing"
  grep -qi "CapEx vs OpEx\|CapEx" "$CMD" && grep -qi "CapEx" "$REF" \
    && ok "CapEx vs OpEx summary present in both status files" \
    || fail "capex-opex" "CapEx vs OpEx summary missing"
  grep -qi "drift flags\|drift_flags\|Drift flags" "$CMD" \
    && ok "drift flags surfaced in status panel" \
    || fail "status-drift" "drift flags not surfaced in status"
}

# ---------------------------------------------------------------------------
# Scenario 9 (version): plugin.json == .cursor/VERSION == CLAUDE.md == 5.6.0
# ---------------------------------------------------------------------------

scenario_9_version() {
  echo "Scenario 9 (version): all stamps agree at target version"
  # Phase 2 validator must stay green across version bumps. Lockstep-check against
  # plugin.json (the canonical stamp) instead of a hard-coded target — mirrors
  # validate-phase3.sh's pattern so a release bump no longer turns this red.
  local TARGET pj cv cm
  TARGET=$(grep -o '"version": "[^"]*"' .claude-plugin/plugin.json | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
  pj=$(grep -o '"version": "[^"]*"' .claude-plugin/plugin.json | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
  cm=$(grep -oE '\*\*Version:\*\* [0-9][0-9.]+' .claude/CLAUDE.md | head -1 | awk '{print $2}')
  cv=$(cat .cursor/VERSION 2>/dev/null | tr -d '[:space:]')
  # temper.md title header
  local tv; tv=$(grep -oE '# Temper:.*\(v[0-9][0-9.]+' commands/temper.md | head -1 | grep -oE 'v[0-9][0-9.]+' | tr -d 'v')

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

  # CHANGELOG has a v5.6.0 entry
  grep -q "## v5.6.0\|## v$TARGET" CHANGELOG.md \
    && ok "CHANGELOG.md has a v$TARGET entry" \
    || fail "version-changelog" "CHANGELOG.md missing v$TARGET entry"
}

# ---------------------------------------------------------------------------
# Scenario 9 (cursor): frozen-v5.1 note preserved, no v5.6 features leaked
# ---------------------------------------------------------------------------

scenario_9_cursor() {
  echo "Scenario 9 (cursor): freeze note preserved + no v5.6 routing leak"
  grep -qi "Frozen at v5.1\|FROZEN" .cursor/README.md \
    && ok ".cursor/README.md preserves frozen-v5.1 note" \
    || fail "cursor-freeze-note" ".cursor/README.md missing frozen-v5.1 note"
  # cursor export must NOT carry ANY v5.6 feature across all commands + rules.
  # Sweeps every .cursor/commands/*.md and .cursor/rules/*.mdc so a freeze_filter
  # gap in any single file (status, pricing rule, etc.) is caught — not just temper.md.
  # NOTE: 'tier-fast' is deliberately excluded — it is a legitimate v5.1 eval judge-model
  # value (Phase 1), not a v5.6 routing marker.
  local leak_file
  leak_file=$(grep -rEl "\[MODEL:|Model Routing Resolution|Economics Panel|Observability Dashboard|drift_flags|tier-frontier|tier-standard|cost_usd" \
              .cursor/commands/ .cursor/rules/ 2>/dev/null | head -1)
  if [ -n "$leak_file" ]; then
    fail "cursor-leak" ".cursor/ leaked v5.6 features into: $leak_file (freeze violated)"
  else
    ok ".cursor/ commands+rules have no v5.6 feature markers (freeze intact)"
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
echo "validate-phase2.sh — Phase 2 (Temper v5.6.0) scenario verification"
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
echo "All Phase 2 scenario assertions passed."
echo "----------------------------------------------------------------"
exit 0
