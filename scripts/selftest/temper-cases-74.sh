# Case file 74 (WP30): packs, skills and dormant machinery removed; Grill Me asks in rounds.
# What no default run reads is not shipped: the six stack packs, the three skills nobody can call (temper-core,
# context-engineering, source-driven-development), the OCR text, the bands monitor (temper bands, scripts/bands.py),
# review memory, the metrics writes (temper metrics append) and the key evidence.claimed-runs. A test run an agent only
# claimed with `temper evidence add --exit N` counts at no gate, and no config key makes it count. The eight packs stay
# shipped. The owner's addition of 2026-11-19: skills/grill-me/SKILL.md asks in rounds of up to four questions.
# Sourced by test-temper.sh; its helpers (setup, fresh, gpass, _at, ev_red, ev_green) are used here. Token: w30.
# A call the CLI does not have yet stays inside $( ... ) or ends in || true, so the file always runs to its end.

# --- the helpers of this file ---
_row74() { # _row74 <stage> <row name>: the pass value of that row of the stage's last verdict, or "absent"
  python3 -I - "$1" "$2" <<'PY'
import json, sys
try:
    e = json.load(open(".temper/gates.json")).get(sys.argv[1]) or {}
except (OSError, ValueError):
    e = {}
r = [x for x in e.get("requirements") or [] if x.get("name") == sys.argv[2]]
print(r[0].get("pass") if r else "absent")
PY
}
_files74() { # _files74 <git grep args...>: the tracked files git grep finds in the repository, at most five, or "none"
  git -C "$REPO_ROOT" grep "$@" 2>/dev/null | head -5 | { tr '\n' ','; echo; } | sed 's/,$//;s/^$/none/'
}
_strict74() { # a fresh run whose config holds no line of the key evidence.claimed-runs
  fresh; sed -i '/^evidence:$/d; /claimed-runs:/d' .claude/temper.config
}
_count74() { # a fresh run whose config holds evidence: claimed-runs: count
  _strict74; printf 'evidence:\n  claimed-runs: count\n' >> .claude/temper.config
}
_claims74() { # a red and a green test run of the Build stage that an agent only claimed (evidence add with an exit code)
  "$TEMPER" evidence add --stage build --claim "unit tests" --exit 1 --phase red >/dev/null 2>&1
  "$TEMPER" evidence add --stage build --claim "unit tests" --exit 0 --phase green >/dev/null 2>&1
}
_packs74() { # _packs74 <agent type>: the Packs: lines of that agent's prompt in `temper next --json` ("<n> Packs lines:
             # ..."), the plugin folder written @P and the project folder dropped
  python3 -I - "$1" "$("$TEMPER" next --json 2>/dev/null)" "$REPO_ROOT" "$(pwd -P)" <<'PY'
import json, sys
kind, text, plugin, work = sys.argv[1:5]
try:
    d = json.loads(text)
except ValueError:
    print("no json"); sys.exit(0)
a = [x for x in d.get("agents") or [] if x.get("type") == kind]
if not a:
    print("no %s agent (action %s)" % (kind, d.get("action"))); sys.exit(0)
packs = [l for l in (a[0].get("prompt") or "").splitlines() if l.startswith("Packs:")]
print(("%d Packs lines" % len(packs) + "".join(": " + l for l in packs[:1])).replace(work + "/", "").replace(plugin, "@P"))
PY
}
# The paths the dormant words are looked for in (spec test 3), with what may still name them left out: the history, the
# plans of this build, the evidence and the decision records; the selftest, whose cases test that the words are gone and
# whose saved-old.json holds the old templates; the defaults table and its two readers, whose GONE names a retired key;
# the word check of WP31, whose list names retired words.
_DORMANT74=(-- agents reference commands templates scripts README.md docs ':(exclude)docs/history' ':(exclude)docs/plans'
  ':(exclude)docs/evidence' ':(exclude)docs/decisions' ':(exclude)scripts/selftest' ':(exclude)scripts/defaults.py'
  ':(exclude)scripts/config_tidy.py' ':(exclude)scripts/check_config_keys.py' ':(exclude)scripts/check_words.py')

# --- 1. no stack pack ---
assert_eq "w30 no stack pack: git ls-files packs/stacks prints nothing, and no tracked file but the CHANGELOG and docs/history holds packs/stacks" \
  "tracked=none|named=none" \
  "tracked=$(git -C "$REPO_ROOT" ls-files packs/stacks | head -3 | { tr '\n' ','; echo; } | sed 's/,$//;s/^$/none/')|named=$(_files74 -l -F 'packs/stacks' -- . \
     ':(exclude)CHANGELOG.md' ':(exclude)docs/history' ':(exclude)docs/plans' \
     ':(exclude)scripts/selftest/temper-cases-46.sh' ':(exclude)scripts/selftest/temper-cases-74.sh')"

# --- 2. two skills ---
assert_eq "w30 two skills: the skills of plugin.json are grill-me and teach-me, the skills folder holds only those two, and no tracked file outside the CHANGELOG, docs/history and docs/decisions names temper-core, context-engineering or source-driven-development" \
  "listed=./skills/grill-me,./skills/teach-me|folders=grill-me,teach-me|named=none" \
  "listed=$(python3 -I -c "import json,sys; print(','.join(json.load(open(sys.argv[1])).get('skills') or []))" "$REPO_ROOT/.claude-plugin/plugin.json")|folders=$(git -C "$REPO_ROOT" ls-files skills | cut -d/ -f2 | sort -u | tr '\n' ',' | sed 's/,$//')|named=$(_files74 -l -e temper-core -e context-engineering -e source-driven-development -- . \
     ':(exclude)CHANGELOG.md' ':(exclude)docs/history' ':(exclude)docs/decisions' ':(exclude)docs/plans' \
     ':(exclude)scripts/selftest/temper-cases-74.sh')"

# --- 3. the dormant words are gone ---
assert_eq "w30 the dormant words are gone: no file of agents, reference, commands, templates, scripts, README.md or docs names review-memory, open-code-review, tools.ocr, metrics append, metrics.json, temper bands or claimed-runs" \
  "none" "$(_files74 -il -e 'review-memory' -e 'open-code-review' -e 'tools.ocr' -e 'metrics append' -e 'metrics.json' \
     -e 'temper bands' -e 'claimed-runs' "${_DORMANT74[@]}")"
# the same pieces in other words (mechanism steps 4 and 6): no page names OCR or review memory, and .gitignore keeps no line
# for the review memory file
assert_eq "w30 no page names OCR or review memory, and .gitignore has no line for review-memory.json" "ocr=none|memory=none|gitignore=none" \
  "ocr=$(_files74 -iwl -e ocr "${_DORMANT74[@]}")|memory=$(_files74 -il -e 'review memory' -e 'review_memory' "${_DORMANT74[@]}")|gitignore=$(grep -c 'review-memory' "$REPO_ROOT/.gitignore" | sed 's/^0$/none/')"

# --- 4. the two commands are gone ---
_gone74() { # _gone74 <args...>: "<exit>,<usage named>,<metrics.json written>" of a CLI call in a fresh project
  fresh; rm -f .temper/metrics.json .temper/bands.json
  local out rc; out="$("$TEMPER" "$@" 2>&1)"; rc=$?
  printf '%s,%s,%s' "$([[ $rc -ne 0 ]] && echo nonzero || echo 0)" \
    "$(grep -qiE 'temper --help|usage' <<<"$out" && echo usage || echo no-usage)" \
    "$([[ -e .temper/metrics.json || -e .temper/bands.json ]] && echo written || echo nothing)"
}
assert_eq "w30 the two commands are gone: temper bands and temper metrics append x 1 exit non zero with the usage text and write nothing, and temper --help names neither" \
  "bands=nonzero,usage,nothing|metrics=nonzero,usage,nothing|help=none" \
  "bands=$(_gone74 bands)|metrics=$(_gone74 metrics append x 1)|help=$("$TEMPER" --help 2>&1 | grep -E 'temper (bands|metrics)\b' | head -2 | { tr '\n' ','; echo; } | sed 's/,$//;s/^$/none/')"

# --- 5. a claim never counts ---
_strict74; _claims74; _at build; "$TEMPER" gate build >/dev/null 2>&1; _w30c="default=$(_row74 build 'RED then GREEN')"
_count74; _claims74; _at build; "$TEMPER" gate build >/dev/null 2>&1; _w30c+="|count=$(_row74 build 'RED then GREEN')"
# the control: the same runs made by the CLI pass the row, so the two above fail for the claim alone
_strict74; ev_red build "unit tests"; ev_green build "unit tests"; _at build; "$TEMPER" gate build >/dev/null 2>&1
_w30c+="|real=$(_row74 build 'RED then GREEN')"
assert_eq "w30 a claim never counts: a build ledger with a red and a green test row written by evidence add and no row run by the CLI fails the Build gate's test first row, also with evidence.claimed-runs: count, while the same runs made by the CLI pass it" \
  "default=False|count=False|real=True" "$_w30c"
_count74; _claims74
assert_eq "w30 a claim never counts: scripts/runs.py takes no mode, and counts no claimed run" "build=0 0 0|check=0|" \
  "build=$(python3 -E -s "$REPO_ROOT/scripts/runs.py" build .temper/evidence/build.json 2>/dev/null)|check=$(python3 -E -s "$REPO_ROOT/scripts/runs.py" check .temper/evidence/build.json 2>/dev/null)"
assert_eq "w30 a claim never counts: evidence.claimed-runs is a key of GONE, and temper config show prints it as not read" \
  "gone=yes|show=not read" \
  "gone=$(python3 -I -B - "$REPO_ROOT" <<'PY'
import os, sys
sys.path.insert(0, os.path.join(sys.argv[1], "scripts"))
try:
    import defaults
    g = defaults.GONE
except Exception:
    print("no defaults table"); sys.exit(0)
keys = list(g.keys()) if isinstance(g, dict) else [x.get("key") if isinstance(x, dict) else (x[0] if isinstance(x, (list, tuple)) else x) for x in g]
print("yes" if "evidence.claimed-runs" in keys else "no")
PY
)|show=$("$TEMPER" config show 2>/dev/null | grep -F 'evidence.claimed-runs' | grep -qi 'not read' && echo 'not read' || echo 'no not read line')"

# --- 6. the run still works with five packs listed ---
fresh   # the packs line in the place of the config's own, or added when the config has none
if grep -q '^packs:' .claude/temper.config; then
  sed -i 's/^packs:.*$/packs: [quality, tdd, security, git, performance]/' .claude/temper.config
else
  printf 'packs: [quality, tdd, security, git, performance]\n' >> .claude/temper.config
fi
gpass intent
python3 -I -c '
import json
p = ".temper/build-state.json"; d = json.load(open(p)); d["next_stage"] = "plan"; json.dump(d, open(p, "w"), indent=2)'
assert_eq "w30 the run still works with five packs listed: the plan agent's Packs line names the five rule files, which stay shipped" \
  "1 Packs lines: Packs: @P/packs/quality/rules.md, @P/packs/tdd/rules.md, @P/packs/security/rules.md, @P/packs/git/rules.md, @P/packs/performance/rules.md|shipped=5" \
  "$(_packs74 temper:temper-plan)|shipped=$(for p in quality tdd security git performance; do git -C "$REPO_ROOT" ls-files "packs/$p/rules.md"; done | wc -l | tr -d ' ')"

# --- the cited words go where they are used (mechanism step 3) ---
assert_eq "w30 the words the three skills gave are where they are used: the build and fix briefs say to check a framework call against the version the project pins, and reference/build.md defines SUGGEST, WARN and BLOCK itself" \
  "build=yes|fix=yes|levels=yes" "$(python3 -I - "$REPO_ROOT" <<'PY'
import os, re, sys
root = sys.argv[1]
def text(p):
    try:
        return " ".join(open(os.path.join(root, p), encoding="utf-8").read().split())
    except OSError:
        return ""
pins = lambda p: "yes" if re.search(r"version the project pins", text(p), re.I) else "no"
lines = open(os.path.join(root, "reference/build.md"), encoding="utf-8").read().splitlines()
own = any(all(w in l for w in ("SUGGEST", "WARN", "BLOCK")) and not re.search(r"\bskill\b", l, re.I) for l in lines)
print("build=%s|fix=%s|levels=%s" % (pins("agents/build.md"), pins("agents/fix.md"), "yes" if own else "no"))
PY
)"

# --- the helpers of step 8 record runs the CLI made ---
fresh; ev_red build "unit tests"; ev_green build "unit tests"
assert_eq "w30 ev_red and ev_green record a failing and a passing test run that the CLI ran" "red,cli,nonzero|green,cli,0" \
  "$(python3 -I -c '
import json
rows = json.load(open(".temper/evidence/build.json"))
print("|".join("%s,%s,%s" % (r.get("phase"), r.get("executed_by"), "0" if r.get("exit_code") == 0 else "nonzero") for r in rows))')"

# --- the owner's addition of 2026-11-19: Grill Me asks in rounds ---
_GRILL74="$REPO_ROOT/skills/grill-me/SKILL.md"
assert_eq "w30 grill me asks in rounds: SKILL.md holds neither one at a time nor One Question at a Time, names the limit of four questions a round, and says that the first option of each question is the recommended answer" \
  "single=none|four a round=yes|first recommended=yes" "$(python3 -I - "$_GRILL74" <<'PY'
import re, sys
try:
    t = open(sys.argv[1], encoding="utf-8").read()
except OSError:
    print("no SKILL.md"); sys.exit(0)
flat = " ".join(t.split())
single = [p for p in ("one at a time", "one question at a time") if p in flat.lower()]
sentences = re.split(r"(?<=[.!?:])\s+|\|", flat)
four = any(re.search(r"\b(up to|at most|no more than|a maximum of|max(imum)?)\s+(4|four)\s+questions\b", s, re.I)
           and re.search(r"\brounds?\b", s, re.I) for s in sentences)
first = any(re.search(r"\bfirst\b", s, re.I) and re.search(r"\b(option|answer)s?\b", s, re.I)
            and re.search(r"\brecommended\b", s, re.I) for s in sentences)
print("single=%s|four a round=%s|first recommended=%s" % (",".join(single) or "none", "yes" if four else "no",
                                                        "yes" if first else "no"))
PY
)"
# the rest of the owner's mechanism and its trap: the front matter and the Mode row say rounds; each question's first
# answer is marked (Recommended); Update plan and Done grilling stay; at most 10 questions in at most 4 rounds; a question
# skipped in a round is listed in the summary as still open; the credit line stays
assert_eq "w30 grill me keeps its limits in rounds: the description and the Mode row say rounds, answers are marked (Recommended), Update plan and Done grilling stay, at most 10 questions in at most 4 rounds, a skipped question is listed as still open, and the credit stays" \
  "description=yes|mode=yes|marked=yes|options=yes|limits=yes|skipped=yes|credit=yes" "$(python3 -I - "$_GRILL74" <<'PY'
import re, sys
try:
    t = open(sys.argv[1], encoding="utf-8").read()
except OSError:
    print("no SKILL.md"); sys.exit(0)
lines = t.splitlines()
yn = lambda b: "yes" if b else "no"
desc = next((l for l in lines if l.startswith("description:")), "")
mode = next((l for l in lines if re.match(r"\|\s*Mode\s*\|", l)), "")
flat = " ".join(t.split())
print("|".join([
    "description=" + yn(re.search(r"\brounds?\b", desc, re.I)),
    "mode=" + yn(re.search(r"\brounds?\b", mode.split("|", 3)[-1] if mode.count("|") >= 3 else "", re.I)),
    "marked=" + yn("(Recommended)" in t),
    "options=" + yn("Update plan" in t and "Done grilling" in t),
    "limits=" + yn(re.search(r"\b10 questions\b", flat, re.I) and re.search(r"\b(4|four) rounds\b", flat, re.I)),
    "skipped=" + yn(any(re.search(r"\bskip", s, re.I) and re.search(r"\bstill open\b|\bopen\b", s, re.I)
                        for s in re.split(r"(?<=[.!?])\s+|\n", t) if "{still open}" not in s)),
    "credit=" + yn("**Credit:** adapted from Matt" in t),
]))
PY
)"
