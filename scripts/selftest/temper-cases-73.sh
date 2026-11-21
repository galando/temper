# Case file 73 (WP29): defaults in code; a template of 10 live lines; the one time question; every key has a reader.
# A new project gets a config of 10 live lines and every other default lives in one table of the CLI
# (scripts/defaults.py: KEYS, OLD, GONE). A project whose config is an older template, of 9.8.4 (7c7a1c1) first and of
# the base (10e965a) second, is asked once, at the start of a run, whether the lines that only repeat old defaults may go
# (config.tidy, its answers tidy-config and keep-config, the calls config tidy --apply and --keep). The CLI names the pack
# files an agent reads (a Packs: line), and no brief or page sends an agent to the config.
# Sourced by test-temper.sh; its helpers (setup, fresh, gpass, nx) are used here. Token: w29. The old templates come
# from scripts/selftest/saved-old.json (WP07), so no case needs an old commit. A call the CLI does not have yet stays
# inside $( ... ) or ends in || true, so the file always runs to its end.

# --- the helpers of this file ---
TPL73="$REPO_ROOT/templates/temper.config.default"
_saved73() { # _saved73 <commit>: the config template of that Temper, from saved-old.json, the plugin folder filled in
  python3 -I - "$TESTS_DIR/saved-old.json" "$1" "$REPO_ROOT" <<'PY'
import json, sys
sys.stdout.write(json.load(open(sys.argv[1]))[sys.argv[2]]["template"].replace("@PLUGIN@", sys.argv[3]))
PY
}
_who73() { [[ "$1" == 7c7a1c1 ]] && echo 9.8.4 || echo base; }
_old73() { # _old73 <commit> [sed expression]: a new /temper:temper run at Intent, no agent launched yet, whose config is
           # the template of that Temper with the change the expression makes; the old file is kept in .git/old-config-73
  setup
  rm -f .temper/specs/demo/intent.md .temper/specs/demo/tasks.md .temper/view.json
  _saved73 "$1" > .claude/temper.config
  [[ -z "${2:-}" ]] || sed -i "$2" .claude/temper.config
  cp .claude/temper.config .git/old-config-73
  "$TEMPER" state init demo --feature "the demo thing" >/dev/null 2>&1; _base_known
}
_qid73() { # the id of the question of `temper next --json`, or its action
  python3 -I -c '
import json, sys
try:
    d = json.loads(sys.argv[1])
except ValueError:
    print("no json"); sys.exit(0)
print((d.get("ask") or {}).get("id") if d.get("action") == "ask" else d.get("action"))' "$("$TEMPER" next --json 2>/dev/null)"
}
_get73() { "$TEMPER" config get "$1" 2>/dev/null | tr '\037' ','; }   # a value as `config get` prints it, a list joined by commas
_src73() { # _src73 <key>: the source `temper config show` names for the key (config, default, old name <key>), or "no line"
  python3 -I - "$1" "$("$TEMPER" config show 2>/dev/null)" <<'PY'
import re, sys
key, out = sys.argv[1], sys.argv[2]
for line in out.splitlines():
    w = [x for x in re.split(r"[\s|]+", line.strip()) if x]
    if not w or w[0].rstrip(":") != key:
        continue
    rest = " ".join(w[1:])
    m = re.search(r"old name\s+(\S+)", rest)
    print("old name %s" % m.group(1).strip("`") if m else "config" if re.search(r"\bconfig\b", rest)
          else "default" if re.search(r"\bdefault\b", rest) else "? " + rest)
    sys.exit(0)
print("no line")
PY
}
_keys73() { # the keys of the defaults table, one a line: "<dot path><TAB><its default, normalized>", or one line ERROR
  python3 -I -B - "$REPO_ROOT" <<'PY'
import json, os, sys
sys.path.insert(0, os.path.join(sys.argv[1], "scripts"))
try:
    import defaults
    K = defaults.KEYS
except Exception as e:
    print("ERROR\tno defaults table (%s)" % type(e).__name__); sys.exit(0)
def default_of(e):
    if isinstance(e, dict):
        return e.get("default", e.get("value"))
    if isinstance(e, (list, tuple)):   # (default, literal, meaning)
        return e[0] if e else None
    return getattr(e, "default", e)
def norm(v):
    if isinstance(v, str) and v.strip().startswith("[") and v.strip().endswith("]"):
        v = [i.strip().strip("\"'") for i in v.strip()[1:-1].split(",") if i.strip()]
    if isinstance(v, (list, tuple)):
        return ",".join(str(i) for i in v)
    if isinstance(v, bool):
        return "true" if v else "false"
    return "" if v is None else str(v)
if isinstance(K, dict):
    items = list(K.items())
else:
    items = [(x.get("key") if isinstance(x, dict) else x[0], x if isinstance(x, dict) else tuple(x[1:])) for x in K]
for k, e in items:
    print("%s\t%s" % (k, norm(default_of(e))))
PY
}
_plan73() { # the run at Plan with no plan written, as the CLI leaves it after Intent
  gpass intent
  python3 -I -c '
import json
p = ".temper/build-state.json"; d = json.load(open(p)); d["next_stage"] = "plan"; json.dump(d, open(p, "w"), indent=2)'
}
_packs73() { # _packs73 <agent type>: the Packs: and Pack entries: lines of that agent's prompt in `temper next --json`
             # ("<n> Packs lines: ..."), the plugin folder written @P and the project folder dropped
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
p = a[0].get("prompt") or ""
packs = [l for l in p.splitlines() if l.startswith("Packs:")]
entries = [l for l in p.splitlines() if l.startswith("Pack entries:")]
out = "%d Packs lines" % len(packs) + "".join(": " + l for l in packs[:1]) + "".join("; " + l for l in entries)
print(out.replace(work + "/", "").replace(plugin, "@P"))
PY
}
_config73() { # _config73 <text>: the project's config is that text
  printf '%s\n' "$1" > .claude/temper.config
}

# --- 1. the template has 10 live lines ---
_t73="$(python3 -I - "$TPL73" <<'PY'
import re, sys
try:
    lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
except OSError:
    print("no template"); sys.exit(0)
stack, live = [], []
for l in lines:
    if not l.strip() or l.lstrip().startswith("#"):
        continue
    m = re.match(r"^( *)([A-Za-z0-9_.-]+):\s*(.*?)\s*(?:#.*)?$", l)
    if not m:
        live.append("?" + l.strip()); continue
    depth = len(m.group(1)) // 2
    stack[depth:] = [m.group(2)]
    live.append(".".join(stack[:depth + 1]) + ("=" + m.group(3) if m.group(3) else ""))
print("live=%d:%s|lines=%s" % (len(live), ";".join(live), "at most 25" if len(lines) <= 25 else len(lines)))
PY
)"
mkdir -p "$WORKDIR/empty73"; ( cd "$WORKDIR/empty73" && git init -q . 2>/dev/null && "$TEMPER" config init >/dev/null 2>&1 )
assert_eq "w29 the template has 10 live lines: exactly run.default, packs, review.block-on, autonomy.park-on-touch, models.plan and models.task with their parents, at most 25 lines in all, and config init writes it byte equal" \
  'live=10:run;run.default=to-commit;packs=[security, tdd];review;review.block-on=[critical, high];autonomy;autonomy.park-on-touch=["**/auth/**", "**/payment/**", "**/billing/**"];models;models.plan=opus;models.task=sonnet|lines=at most 25|init=byte equal' \
  "$_t73|init=$(cmp -s "$TPL73" "$WORKDIR/empty73/.claude/temper.config" && echo byte equal || echo differs)"
rm -rf "$WORKDIR/empty73"

# --- 2. a default comes from the table ---
fresh; : > .claude/temper.config
_k73="$(_keys73)"
_d73=""
for _key73 in review.block-on packs run.default autonomy.park-on-touch; do
  _d73+="${_d73:+|}$_key73=$(_get73 "$_key73")/$(printf '%s\n' "$_k73" | awk -F'\t' -v k="$_key73" '$1 == k { print $2 }')"
done
assert_eq "w29 a default comes from the table: with an empty config, config get prints the table's value for review.block-on, packs, run.default and autonomy.park-on-touch (config get / the table)" \
  'review.block-on=critical,high/critical,high|packs=security,tdd/security,tdd|run.default=to-commit/to-commit|autonomy.park-on-touch=**/auth/**,**/payment/**,**/billing/**/**/auth/**,**/payment/**,**/billing/**' \
  "$_d73"
assert_eq "w29 config show prints every key of the table with the source default, when the config is empty" "every key default" \
  "$(python3 -I - "$_k73" "$("$TEMPER" config show 2>&1)" <<'PY'
import re, sys
keys = [l.split("\t", 1)[0] for l in sys.argv[1].splitlines() if l.strip()]
if not keys or keys[0] == "ERROR":
    print("no table: " + sys.argv[1][:120]); sys.exit(0)
rows = {}
for line in sys.argv[2].splitlines():
    w = [x for x in re.split(r"[\s|]+", line.strip()) if x]
    if w:
        rows.setdefault(w[0].rstrip(":"), " ".join(w[1:]))
missing = [k for k in keys if k not in rows]
other = [k for k in keys if k in rows and not re.search(r"\bdefault\b", rows[k])]
print("every key default" if not missing and not other else
      "missing: %s; not default: %s" % (",".join(missing[:6]) or "none", ",".join(other[:6]) or "none"))
PY
)"
# mechanism step 2: a key of the file in neither KEYS nor GONE is one line `not read: <key>`, never an error; a renamed key
# is read under its old name when the new one is absent, and its source says so
_config73 'models:
  plan: opus
build:
  grouped:
    task-model: haiku
zz73:
  unknown: 1'
assert_eq "w29 config show names a key nobody reads as not read, never an error, and reads a renamed key under its old name" \
  "show=0|not read=zz73.unknown|models.task=haiku,old name build.grouped.task-model|get unknown=0:1" \
  "show=$("$TEMPER" config show >/dev/null 2>&1; echo $?)|not read=$("$TEMPER" config show 2>/dev/null | sed -n 's/^[[:space:]|]*not read:[[:space:]]*`\{0,1\}\([^`[:space:]|]*\).*/\1/p' | LC_ALL=C sort | paste -sd, -)|models.task=$(_get73 models.task),$(_src73 models.task)|get unknown=$("$TEMPER" config get zz73.unknown >/dev/null 2>&1; echo $?):$(_get73 zz73.unknown)"
# Documents: docs/commands.md holds the table of every key, generated by `temper config show --markdown`
: > .claude/temper.config
assert_eq "w29 docs/commands.md holds the key table that temper config show --markdown prints, so it cannot drift" "in docs/commands.md" \
  "$(python3 -I - "$("$TEMPER" config show --markdown 2>/dev/null; echo "exit=$?")" "$REPO_ROOT/docs/commands.md" <<'PY'
import sys
out = sys.argv[1].rsplit("exit=", 1)
table, rc = out[0].strip(), out[1].strip()
try:
    doc = open(sys.argv[2], encoding="utf-8").read()
except OSError:
    doc = ""
if rc != "0" or table.count("\n") < 10 or not table.lstrip().startswith("|"):
    print("no table from config show --markdown (exit %s)" % rc)
else:
    print("in docs/commands.md" if table in doc else "not in docs/commands.md")
PY
)"

# --- 3. every key has a reader ---
assert_eq "w29 every key has a reader: python3 scripts/check_config_keys.py exits 0, and scripts/quality-check.sh runs it" \
  "exit=0|quality-check=runs it" \
  "exit=$(cd "$REPO_ROOT" && python3 scripts/check_config_keys.py >/dev/null 2>&1; echo $?)|quality-check=$(grep -q 'check_config_keys\.py' "$REPO_ROOT/scripts/quality-check.sh" && echo runs it || echo no)"
# One failing input of each kind, in a throwaway copy of the files the reader test reads (a git repository of its own)
_C73="$WORKDIR/copy73"
rm -rf "$_C73"; mkdir -p "$_C73"
( cd "$REPO_ROOT" && git ls-files -z --cached --others --exclude-standard -- scripts agents reference commands templates docs README.md \
    | tar --null --ignore-failed-read -T - -cf - 2>/dev/null ) | ( cd "$_C73" && tar -xf - 2>/dev/null )
( cd "$_C73" && git init -q . && git add -A && git -c user.email=t@example.com -c user.name=t commit -qm copy ) >/dev/null 2>&1
_kind73() { # _kind73 <key or path the output must name>: run the reader test in the copy, then put the copy back
  local out rc
  ( cd "$_C73" && git add -A ) >/dev/null 2>&1
  out="$(cd "$_C73" && python3 -B scripts/check_config_keys.py 2>&1)"; rc=$?
  ( cd "$_C73" && git reset -q --hard && git clean -fdq ) >/dev/null 2>&1
  if [[ $rc -eq 0 ]]; then echo "passes"; elif grep -qF -- "$1" <<<"$out"; then echo "fails naming $1"; else echo "fails (exit $rc) without $1"; fi
}
_r73="copy=$(cd "$_C73" && python3 -B scripts/check_config_keys.py >/dev/null 2>&1; echo $?)"
# a: a key of the table that no file reads (its readers in scripts renamed, defaults.py left as it is)
git -C "$_C73" grep -lF -e 'max-blast-radius' -- scripts ':!scripts/defaults.py' 2>/dev/null \
  | while read -r _f; do sed -i 's/max-blast-radius/zz73-blast-gone/g' "$_C73/$_f"; done
_r73+="|a=$(_kind73 autonomy.max-blast-radius)"
# b: a key read in code that the table lacks
printf '\n_zz73_read() { _cfg_get zz73.never-in-the-table; }\n' >> "$_C73/scripts/temper"
_r73+="|b=$(_kind73 zz73.never-in-the-table)"
# c: a key of the template, a commented one, that the table lacks
printf '# zz73:\n#   template-only: 1\n' >> "$_C73/templates/temper.config.default"
_r73+="|c=$(_kind73 template-only)"
# d: a page that names a key that is gone
mkdir -p "$_C73/docs"; printf '# A page\n\nRaise `review.confidence-threshold` to see fewer findings.\n' > "$_C73/docs/zz73.md"
_r73+="|d=$(_kind73 review.confidence-threshold)"
# e (mechanism step 4): a brief other than reference/pack.md that sends an agent to the config
printf '# A brief\n\nRead `.claude/temper.config` first.\n' > "$_C73/agents/zz73.md"
_r73+="|e=$(_kind73 agents/zz73.md)"
assert_eq "w29 the reader test fails on each kind of input: a table key no file reads, a key read in code the table lacks, a template key the table lacks, a page naming a gone key, a brief naming the config" \
  "copy=0|a=fails naming autonomy.max-blast-radius|b=fails naming zz73.never-in-the-table|c=fails naming template-only|d=fails naming review.confidence-threshold|e=fails naming agents/zz73.md" \
  "$_r73"
rm -rf "$_C73"

# --- 4. no agent is sent to the config ---
_g73="$(git -C "$REPO_ROOT" grep -nF ".claude/temper.config" -- agents reference 2>/dev/null | grep -v '^reference/pack\.md:')"
assert_eq "w29 no agent is sent to the config: git grep of .claude/temper.config in agents and reference prints only lines of reference/pack.md" \
  "none" "$([[ -z "$_g73" ]] && echo none || printf '%d lines: %s' "$(printf '%s\n' "$_g73" | wc -l)" "$(printf '%s\n' "$_g73" | cut -d: -f1 | LC_ALL=C sort -u | paste -sd, -)")"
# mechanism step 5: the seven pages say "read the pack files your prompt lists"
_p73=""
for _f73 in reference/plan.md reference/build.md reference/review.md reference/check.md reference/design.md agents/rca.md agents/fix.md; do
  tr '\n' ' ' < "$REPO_ROOT/$_f73" 2>/dev/null | tr -s ' ' | grep -qiF 'pack files your prompt lists' || _p73+="${_p73:+,}$_f73"
done
assert_eq "w29 the seven pages that resolved packs from the config say to read the pack files the prompt lists" "all seven" "${_p73:-all seven}"

# --- 5. the CLI names the pack files ---
fresh; rm -f .claude/temper.config; "$TEMPER" config init >/dev/null 2>&1; _plan73
_a73="plan=$(_packs73 temper:temper-plan)"
fresh; rm -f .temper/specs/demo/intent.md .temper/specs/demo/tasks.md .claude/temper.config; "$TEMPER" config init >/dev/null 2>&1
_a73+="|intent=$(_packs73 temper:temper-intent)"
assert_eq "w29 the CLI names the pack files: with the default config the plan agent's prompt holds one Packs line with the plugin's security and tdd rules, the Intent agent's none" \
  "plan=1 Packs lines: Packs: @P/packs/security/rules.md, @P/packs/tdd/rules.md|intent=0 Packs lines" "$_a73"
# a project file takes the place of the plugin's; a pack whose phases leave the stage out is not listed; a pack in the
# home folder is no longer found; an entry in braces goes into the line Pack entries as written
_project_pack73() { mkdir -p ".claude/packs/$1"; printf -- '---\nphases: %s\n---\n\n# %s\n\n- a rule\n' "$2" "$1" > ".claude/packs/$1/rules.md"; }
fresh; rm -f .claude/temper.config; "$TEMPER" config init >/dev/null 2>&1; _plan73
mkdir -p .claude/packs/security; cp "$REPO_ROOT/packs/security/rules.md" .claude/packs/security/rules.md
_project_pack73 zz73a '[review]'; _project_pack73 zz73b '[plan]'
mkdir -p home73/.claude/packs/zz73c; printf -- '---\nphases: all\n---\n\n# zz73c\n' > home73/.claude/packs/zz73c/rules.md
python3 -I - <<'PY'
import re
p = ".claude/temper.config"
t = open(p).read()
line = "packs: [security, tdd, zz73a, zz73b, zz73c, { name: api-standards, link: plugin://my-api-linter }]"
t = re.sub(r"(?m)^packs:.*$", line, t) if re.search(r"(?m)^packs:", t) else line + "\n" + t
open(p, "w").write(t)
PY
assert_eq "w29 a project pack takes the place of the plugin's, a pack whose phases leave Plan out is not listed, a home folder pack is not found, an entry in braces is a Pack entries line" \
  "1 Packs lines: Packs: .claude/packs/security/rules.md, @P/packs/tdd/rules.md, .claude/packs/zz73b/rules.md; Pack entries: { name: api-standards, link: plugin://my-api-linter }" \
  "$(HOME="$(pwd -P)/home73" _packs73 temper:temper-plan)"
assert_eq "w29 temper packs --stage review lists the project's review pack and not the plan pack" "exit=0|security=project|zz73a=yes|zz73b=no|tdd=yes" \
  "$(_o73="$(HOME="$(pwd -P)/home73" "$TEMPER" packs --stage review 2>&1)"; _rc73=$?
     echo "exit=$_rc73|security=$(grep -q '\.claude/packs/security/rules\.md' <<<"$_o73" && echo project || echo other)|zz73a=$(grep -q 'zz73a/rules\.md' <<<"$_o73" && echo yes || echo no)|zz73b=$(grep -q 'zz73b' <<<"$_o73" && echo yes || echo no)|tdd=$(grep -qF "$REPO_ROOT/packs/tdd/rules.md" <<<"$_o73" && echo yes || echo no)")"
rm -rf home73

# --- 6. an old config is asked once ---
_ask73() { # the first question of the run: id, header, the count of lines, the copy, the four lines that change a run,
           # "and M more" when more than eight, and the two options with their calls
  python3 -I - "$1" "$("$TEMPER" next --json 2>/dev/null)" <<'PY'
import json, re, sys
who, text = sys.argv[1], sys.argv[2]
try:
    d = json.loads(text)
except ValueError:
    print("no json"); sys.exit(0)
q = d.get("ask") if d.get("action") == "ask" else None
if not q:
    print("action %s" % d.get("action")); sys.exit(0)
t = str((q.get("question") or {}).get("question") or "")
low = t.lower()
m = re.search(r"holds (\d+) lines?", t)
n = int(m.group(1)) if m else 0
more = re.search(r"and (\d+) more", t)
mm = "no more needed" if n <= 8 else ("and more ok" if more and n - 8 <= int(more.group(1)) < n else "no and M more")
four = ["coverage", "design", "pack"] + (["block"] if who == "9.8.4" else [])
miss = [w for w in four if w not in low]
def opt(i):
    o = [x for x in q.get("options") or [] if x.get("id") == i]
    if not o:
        return "none"
    calls = " ".join(re.sub(r"^\S*/temper ", "", c) for c in o[0].get("calls") or [])
    return "%s%s:%s" % (o[0].get("label"), " rec" if o[0].get("recommended") else "", calls)
print("|".join([str(q.get("id")), str((q.get("question") or {}).get("header")), "lines" if n > 0 else "no count",
                "copy" if "copy" in low else "no copy", "four named" if not miss else "missing " + ",".join(miss), mm,
                "tidy=" + opt("tidy-config"), "keep=" + opt("keep-config")]))
PY
}
_q73=""
for _c73 in 7c7a1c1 10e965a; do
  _old73 "$_c73"
  _q73+="${_q73:+ / }$(_who73 "$_c73")=$(_ask73 "$(_who73 "$_c73")")"
done
_want73="config.tidy|Temper gate|lines|copy|four named|and more ok|tidy=Remove them (Recommended) rec:config tidy --apply|keep=Keep my file:config tidy --keep"
assert_eq "w29 an old config is asked once: the first next of a run on the template of 9.8.4, and of the base, is config.tidy with the count of lines, the copy, the lines that change a run, and the two calls" \
  "9.8.4=$_want73 / base=$_want73" "$_q73"

# --- 7. yes gives the new defaults ---
_y73=""
for _c73 in 7c7a1c1 10e965a; do
  _old73 "$_c73"
  "$TEMPER" config tidy --apply >/dev/null 2>&1; _rc73=$?
  _y73+="${_y73:+ / }$(_who73 "$_c73")=exit $_rc73|file $(cmp -s "$TPL73" .claude/temper.config && echo is the template || echo differs)|copy $(cmp -s .git/old-config-73 .claude/temper.config.before-9.8.5 && echo same || echo differs)|next $(_qid73)"
done
assert_eq "w29 yes gives the new defaults: after config tidy --apply on the template of 9.8.4, and of the base, the file is the new template, the copy is the old file, and the run goes on" \
  "9.8.4=exit 0|file is the template|copy same|next work / base=exit 0|file is the template|copy same|next work" "$_y73"

# --- 8. yes keeps what the person changed ---
_c8_73=""
for _c73 in 7c7a1c1 10e965a; do
  _old73 "$_c73" 's/coverage-threshold: 80/coverage-threshold: 60/; s/block-on: \[critical[^]]*\]/block-on: [critical]/; s/^autonomy:$/autonomy:\n  enabled: false/'
  printf 'build:\n  grouped:\n    max-parallel: 7\n' >> .claude/temper.config
  "$TEMPER" config tidy --apply >/dev/null 2>&1
  _c8_73+="${_c8_73:+ / }$(_who73 "$_c73")=coverage $(_get73 check.coverage-threshold) $(_src73 check.coverage-threshold)|max-parallel $(_get73 build.grouped.max-parallel) $(_src73 build.grouped.max-parallel)|block-on $(_get73 review.block-on)|run.default $(_get73 run.default) $(_src73 run.default)|$(python3 -I -c '
import re, sys
t = open(".claude/temper.config").read()
print("enabled named" if re.search(r"(?m)^\s+enabled\s*:", t) or "autonomy.enabled" in t else "no enabled")')"
done
_w8_73="coverage 60 config|max-parallel 7 config|block-on critical,high|run.default ask config|no enabled"
assert_eq "w29 yes keeps what the person changed: coverage 60 and max-parallel 7 stay from config, block-on critical (the old default) gives way to the new default, enabled false becomes run.default ask" \
  "9.8.4=$_w8_73 / base=$_w8_73" "$_c8_73"

# --- 9. no keeps the file ---
_n73=""
for _c73 in 7c7a1c1 10e965a; do
  _old73 "$_c73"
  "$TEMPER" config tidy --keep >/dev/null 2>&1; _rc73=$?
  _n73+="${_n73:+ / }$(_who73 "$_c73")=exit $_rc73|$(python3 -I -B - .git/old-config-73 .claude/temper.config "$REPO_ROOT/scripts" <<'PY'
import re, sys
sys.path.insert(0, sys.argv[3])
import config_yaml
old, new = open(sys.argv[1]).read(), open(sys.argv[2]).read()
if not new.startswith(old):
    print("file changed"); sys.exit(0)
tail = config_yaml.parse_yaml_subset(new[len(old):])
quoted = re.search(r'(?m)^\s+asked:\s*"9\.8\.5"\s*$', new[len(old):])
print("old file plus %s%s" % (tail, " quoted" if quoted else " not quoted"))
PY
)|next $(_qid73),$(_qid73)|coverage $(_get73 check.coverage-threshold)|block-on $(_get73 review.block-on)"
done
assert_eq "w29 no keeps the file: after config tidy --keep the file is the old one plus upgrade.asked, the question is not asked again, and the old values still rule" \
  "9.8.4=exit 0|old file plus {'upgrade': {'asked': '9.8.5'}} quoted|next work,work|coverage 80|block-on critical / base=exit 0|old file plus {'upgrade': {'asked': '9.8.5'}} quoted|next work,work|coverage 80|block-on critical,high" \
  "$_n73"

# --- 10. never in the middle of a run ---
_m73=""
_old73 7c7a1c1; "$TEMPER" config tidy --apply >/dev/null 2>&1; _m73+="intent=$?"
_same73() { echo "$(cmp -s .git/old-config-73 .claude/temper.config && echo same || echo changed)$([[ -e .claude/temper.config.before-9.8.5 ]] && echo ' copy' || true)"; }
for _how73 in plan fix unattended; do
  _old73 7c7a1c1
  case "$_how73" in
    plan) _plan73 ;;
    fix) "$TEMPER" state init bug --command fix --feature "a bug" >/dev/null 2>&1; _base_known ;;
    unattended) python3 -I -c '
import json
p = ".temper/build-state.json"; d = json.load(open(p)); d.update(run_mode="autonomous", unattended_from="plan"); json.dump(d, open(p, "w"), indent=2)' ;;
  esac
  _x73="$(_qid73)"
  "$TEMPER" config tidy --apply >/dev/null 2>&1; _r1=$?
  "$TEMPER" config tidy --keep >/dev/null 2>&1; _r2=$?
  _m73+="|$_how73=$_r1,$_r2 $(_same73)$([[ $_how73 == fix ]] && echo " asked $([[ $_x73 == config.tidy ]] && echo yes || echo no)")"
done
# a run at Intent whose Intent agent already ran (its intent.md written, its usage recorded) is not asked
_old73 7c7a1c1; cp "$REPO_ROOT/templates/example-intent.md" .temper/specs/demo/intent.md 2>/dev/null || printf '# Intent\n' > .temper/specs/demo/intent.md
"$TEMPER" usage add --stage intent --model sonnet --ms 1000 >/dev/null 2>&1
_m73+="|intent after its agent=$([[ "$(_qid73)" == config.tidy ]] && echo asked || echo not asked)"
assert_eq "w29 never in the middle of a run: config tidy runs at Intent, exits 1 and changes nothing past Intent, in a fix run or an unattended run, and a fix run is not asked" \
  "intent=0|plan=1,1 same|fix=1,1 same asked no|unattended=1,1 same|intent after its agent=not asked" "$_m73"

# --- 11. a repeated block is merged: an upgrade block --keep appends does not drop another upgrade block ---
_old73 7c7a1c1 's/^stack: auto$/stack: auto\nupgrade:\n  note: kept73/'
"$TEMPER" config tidy --keep >/dev/null 2>&1
assert_eq "w29 a repeated block is merged: after config tidy --keep on a config that already has an upgrade block, both its keys are read" \
  "note=kept73|asked=9.8.5|next=work" "note=$(_get73 upgrade.note)|asked=$(_get73 upgrade.asked)|next=$(_qid73)"

# --- the review of phase 8 (W29-1 to W29-4) ---
# W29-1: a packs list in block form (reference/pack.md) survives --apply as written, byte for byte, and reads the same
_old73 7c7a1c1 's/^packs: \[.*\]$/packs:\n  - security\n  - name: api-standards\n    link: plugin:\/\/my-api-linter\n  - tdd/'
_blk73="$(printf 'packs:\n  - security\n  - name: api-standards\n    link: plugin://my-api-linter\n  - tdd')"
_pb73="$("$TEMPER" packs --stage review 2>&1)"
"$TEMPER" config tidy --apply >/dev/null 2>&1; _rc73=$?
assert_eq "w29 config tidy --apply keeps a packs list in block form byte for byte, the packs of a stage read the same, and the run goes on" \
  "exit=0|block=as written, once|packs=same|next=work" \
  "exit=$_rc73|block=$(python3 -I - "$_blk73" <<'PY'
import sys
t = open(".claude/temper.config").read()
n = t.count(sys.argv[1] + "\n")
print("as written, once" if n == 1 and t.count("packs:") == 1 and t.count("api-standards") == 1 else "%d times: %r" % (n, t[:400]))
PY
)|packs=$([[ "$("$TEMPER" packs --stage review 2>&1)" == "$_pb73" ]] && echo same || echo differs)|next=$(_qid73)"
# W29-2: a pack whose rules.md says `phases: []` is listed at no stage (docs/packs.md, reference/pack.md, the guardrails
# pack); a pack with no phases line is listed at every stage, as before
fresh; rm -f .claude/temper.config; "$TEMPER" config init >/dev/null 2>&1
_project_pack73 zz73e '[]'
mkdir -p .claude/packs/zz73f; printf '# zz73f\n\n- a rule\n' > .claude/packs/zz73f/rules.md
sed -i 's/^packs: \[security, tdd\]/packs: [security, tdd, zz73e, zz73f, guardrails]/' .claude/temper.config
_e73=""
for _st73 in plan design build review check rca fix; do
  _o73="$("$TEMPER" packs --stage "$_st73" 2>&1)"
  _e73+="${_e73:+|}$_st73=$(grep -c -e 'zz73e' -e 'guardrails' <<<"$_o73"),$(grep -c 'zz73f' <<<"$_o73")"
done
assert_eq "w29 a pack whose phases is [] is listed at no stage (the project's zz73e, the plugin's guardrails), a pack with no phases line at every stage" \
  "plan=0,1|design=0,1|build=0,1|review=0,1|check=0,1|rca=0,1|fix=0,1" "$_e73"
# W29-3: with autonomy.enabled false and no run.default line, the flow asks (Run.run_default); config get and config
# show say ask, from the old name, and do not call autonomy.enabled gone; a default the caller gives still wins
fresh; _config73 'autonomy:
  enabled: false'
_s73="$("$TEMPER" config show 2>/dev/null)"
assert_eq "w29 autonomy.enabled false with no run.default: config get run.default is ask, config show gives it from the old name and names autonomy.enabled gone nowhere" \
  "get=ask|source=old name autonomy.enabled|gone lines=0|given=x73" \
  "get=$(_get73 run.default)|source=$(_src73 run.default)|gone lines=$(grep -c '^gone: autonomy\.enabled' <<<"$_s73")|given=$("$TEMPER" config get run.default x73 2>/dev/null)"
_config73 'autonomy:
  enabled: true'
assert_eq "w29 autonomy.enabled true with no run.default: run.default is the table's to-commit, and autonomy.enabled is gone" \
  "get=to-commit|source=default|gone lines=1" \
  "get=$(_get73 run.default)|source=$(_src73 run.default)|gone lines=$("$TEMPER" config show 2>/dev/null | grep -c '^gone: autonomy\.enabled')"
# W29-4: the copy is never overwritten: a second --apply leaves it the old file; with nothing to remove --apply writes
# nothing; a copy that is there with other text stays, and the old file goes to the next number
_old73 7c7a1c1
"$TEMPER" config tidy --apply >/dev/null 2>&1; cp .claude/temper.config .git/tidy-73
"$TEMPER" config tidy --apply >/dev/null 2>&1; _rc73=$?
_k4_73="second=$_rc73 copy $(cmp -s .git/old-config-73 .claude/temper.config.before-9.8.5 && echo old file || echo overwritten) file $(cmp -s .git/tidy-73 .claude/temper.config && echo same || echo changed)"
fresh; rm -f .claude/temper.config; "$TEMPER" config init >/dev/null 2>&1; cp .claude/temper.config .git/tidy-73
"$TEMPER" config tidy --apply >/dev/null 2>&1; _rc73=$?
_k4_73+="|nothing stale=$_rc73 copy $([[ -e .claude/temper.config.before-9.8.5 ]] && echo written || echo none) file $(cmp -s .git/tidy-73 .claude/temper.config && echo same || echo changed)"
_old73 7c7a1c1; printf 'an older copy\n' > .claude/temper.config.before-9.8.5
"$TEMPER" config tidy --apply >/dev/null 2>&1; _rc73=$?
_k4_73+="|copy there=$_rc73 $(cat .claude/temper.config.before-9.8.5) $(cmp -s .git/old-config-73 .claude/temper.config.before-9.8.5.2 && echo next number || echo lost)"
assert_eq "w29 config tidy --apply never overwrites the copy: a second call keeps the old file, with nothing stale it writes nothing, an existing copy stays" \
  "second=0 copy old file file same|nothing stale=0 copy none file same|copy there=0 an older copy next number" "$_k4_73"

# --- the question is a stop that must stay, and a project of the selftest or of config init is never asked ---
assert_eq "w29 scripts/stops.json holds config.tidy, the one time config question, as a stop that must stay" "config.tidy listed" \
  "$(python3 -I -c '
import json, sys
s = json.load(open(sys.argv[1])).get("stops") or []
print("config.tidy listed" if any(x.get("id") == "config.tidy" for x in s) else "not listed")' "$REPO_ROOT/scripts/stops.json")"
fresh; rm -f .temper/specs/demo/intent.md .temper/specs/demo/tasks.md
_f73="selftest=$(_qid73)"
rm -f .claude/temper.config; "$TEMPER" config init >/dev/null 2>&1
_f73+="|config init=$(_qid73)"
assert_eq "w29 a run on the selftest's own config, or on what config init writes, is never asked (mechanism step 9): its first step is the Intent agent" \
  "selftest=work|config init=work" "$_f73"

# --- mechanism step 10: this repository's own config is tidied, and keeps the run that asks twice ---
fresh; rm -f .temper/specs/demo/intent.md .temper/specs/demo/tasks.md
cp "$REPO_ROOT/.claude/temper.config" .claude/temper.config
assert_eq "w29 this repository's own config holds no old default: a run on it is not asked, and its run.default is to-commit" \
  "next=work|run.default=to-commit|enabled=none" \
  "next=$(_qid73)|run.default=$(_get73 run.default)|enabled=$(grep -cE '^[[:space:]]+enabled:[[:space:]]*false' .claude/temper.config | sed 's/^0$/none/')"

# --- documents of the same change: the decision record ---
assert_eq "w29 the decision record docs/decisions/0023-two-commands-and-defaults-in-code.md says defaults live in code and names config.tidy" \
  "record=yes|defaults=yes|config.tidy=yes" \
  "$(_r="$REPO_ROOT/docs/decisions/0023-two-commands-and-defaults-in-code.md"; echo "record=$([[ -f $_r ]] && echo yes || echo no)|defaults=$(grep -qi 'defaults live in code' "$_r" 2>/dev/null && echo yes || echo no)|config.tidy=$(grep -qF 'config.tidy' "$_r" 2>/dev/null && echo yes || echo no)")"
