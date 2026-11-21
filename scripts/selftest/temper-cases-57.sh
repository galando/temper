# Case file 57 (WP16): the CLI words that take the place of the calls of the flow that were no CLI calls, and Scope drift
# as the CLI's own question. `temper spec branch --carry NAME` carries the spec files across a switch as the shell line
# of carry_switch did; `temper group take-out G SHA...` takes out only the newest commits of the group's branch it is
# given; `temper drift ask` records a file outside the plan in the stage's ledger, and the CLI asks the Scope drift
# question before anything else of Build; with every drift answered the agent runs again with one `Drift decision:`
# line a file. The cap handback_kinds counts the closed list NEEDS. Sourced by test-temper.sh; its helpers (fresh, gpass,
# m_setup, f9_tasks, _unattended) are used here, and the builders below are this file's own. Token: w16.

# --- the helpers of this file ---
_x57() { # _x57 <python code over d, the JSON of temper next>: prints r
  python3 -B - "$1" "$("$TEMPER" next --json 2>/dev/null)" <<'PY'
import json, re, sys
try:
    d = json.loads(sys.argv[2])
except ValueError:
    d = {}
r = None
exec(sys.argv[1])
print(r)
PY
}
_repo57() { # a git repository under the run: one source file in one commit on master, the run's files left out
  rm -rf .git src; git init -q . 2>/dev/null; git checkout -q -B master 2>/dev/null
  git config user.email t@example.com; git config user.name T
  mkdir -p src; echo 'echo demo' > src/demo.sh
  git add -A -- . ':(exclude).temper' ':(exclude).claude'; git commit -q -m base
}
_clash57() { # a run on master whose branch feature/demo exists from an earlier run: that branch tracks an old intent.md
             # of the spec folder and another src/demo.sh; master holds the new intent.md and a plan.md, not tracked
  fresh; _repo57
  _NEW57="$(cat .temper/specs/demo/intent.md)"
  git checkout -q -b feature/demo
  printf 'the old intent of an earlier run\n' > .temper/specs/demo/intent.md
  echo 'echo other' > src/demo.sh
  git add .temper/specs/demo/intent.md src/demo.sh; git commit -q -m 'an earlier run'
  git checkout -q master
  printf '%s\n' "$_NEW57" > .temper/specs/demo/intent.md
  printf '# Plan: the new one\n' > .temper/specs/demo/plan.md
}
_spec57() { # the spec files as the run wrote them: the new intent.md, and plan.md there
  printf '%s|%s' "$([[ "$(cat .temper/specs/demo/intent.md 2>/dev/null)" == "$_NEW57" ]] && echo same || echo differs)" \
    "$([[ -f .temper/specs/demo/plan.md ]] && echo plan || echo no-plan)"
}
_build57() { # a run at Build: the default tasks.md of the suite, whose one file is src/demo.sh
  fresh; gpass intent plan
  "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
}
_answer57() { # _answer57 <option id>: runs the calls of that option of the question next asks, as the person's answer
  local c
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    c="${c//\{reason\}/the person said so}"
    bash -c "$c" >/dev/null 2>&1 || break
  done < <(_x57 "r = '\n'.join(next((o.get('calls') or [] for o in (d.get('ask') or {}).get('options') or [] if o.get('id') == '$1'), []))")
}
_first57() { _x57 "r = str(((d.get('ask') or {}).get('question') or {}).get('question', '')).split('\n')[0]"; }

# --- spec branch --carry: the spec files cross the switch; a refused switch puts them back and fails ---
_clash57; _at build   # WP32, rule 1 (D30): a branch and a commit come after the approval
assert_eq "w16 spec branch --carry: the spec files cross the switch to the run's branch, which a plain switch refuses" \
  "refused|0|feature/demo|same|plan" \
  "$(git checkout -q feature/demo >/dev/null 2>&1 && echo switched || echo refused)|$("$TEMPER" spec branch --carry feature/demo >/dev/null 2>&1; echo $?)|$(git branch --show-current)|$(_spec57)"
_clash57; _at build   # WP32, rule 1 (D30): a branch and a commit come after the approval
echo 'echo a local edit' > src/demo.sh
_out57="$("$TEMPER" spec branch --carry feature/demo 2>&1)"; _rc57=$?
_dir57=""
for _w57 in $_out57; do
  _w57="${_w57%[.,;:]}"
  [[ "$_w57" == /* && -f "$_w57/plan.md" ]] && { _dir57="$_w57"; break; }
done
assert_eq "w16 spec branch --carry: a refused switch puts the spec files back, fails, and names the folder that holds them" \
  "failed|master|same|plan|FAIL|named" \
  "$([[ $_rc57 -ne 0 ]] && echo failed || echo passed)|$(git branch --show-current)|$(_spec57)|$(grep -o 'FAIL' <<<"$_out57" | head -n 1)|$([[ -n "$_dir57" ]] && echo named || echo none)"

# --- spec branch --carry takes only the run's branch: a path as NAME is refused, its edits stay (phase 4b review) ---
_clash57; _at build   # WP32, rule 1 (D30): a branch and a commit come after the approval
echo 'echo a local edit' > src/demo.sh
_out57="$("$TEMPER" spec branch --carry src/demo.sh 2>&1)"; _rc57=$?
assert_eq "w16 spec branch --carry: a NAME that is not the run's branch is refused, and a path's edits stay" \
  "1|FAIL|master|echo a local edit|same|plan" \
  "$_rc57|$(grep -o '^FAIL' <<<"$_out57" | head -n 1)|$(git branch --show-current)|$(cat src/demo.sh)|$(_spec57)"

# --- spec commit -- FILE...: the commit holds the files named and nothing staged before it (phase 4b review) ---
fresh; _repo57; _at build   # WP32, rule 1 (D30)
echo 'echo other' > src/old.sh; git add src/old.sh; git commit -q -m old
echo 'echo changed' > src/demo.sh; rm src/old.sh
echo staged > unrelated.txt; git add unrelated.txt
_rc57="$("$TEMPER" spec commit 'feat(demo): demo' -- src/demo.sh src/old.sh >/dev/null 2>&1; echo $?)"
assert_eq "w15 spec commit -- FILE...: the commit holds the files named, and a file staged before stays staged" \
  "0|src/demo.sh,src/old.sh|A  unrelated.txt" \
  "$_rc57|$(git show --name-only --format= HEAD | sort | paste -sd, -)|$(git status --porcelain -- unrelated.txt)"

# --- spec commit 'msg' with no files: the commit holds the spec folder and nothing staged before it (phase 4b) ---
fresh; rm -f unrelated.txt; _repo57; _at build   # WP32, rule 1 (D30)
printf '# Plan: demo\n' > .temper/specs/demo/plan.md
echo staged > unrelated.txt; git add unrelated.txt
_rc57="$("$TEMPER" spec commit 'docs(spec): demo' >/dev/null 2>&1; echo $?)"
assert_eq "w15 spec commit with no files: the commit holds the spec folder, and a file staged before stays staged" \
  "0|spec|A  unrelated.txt" \
  "$_rc57|$(git show --name-only --format= HEAD | sed 's|^\.temper/specs/demo/.*|spec|' | sort -u | paste -sd, -)|$(git status --porcelain -- unrelated.txt)"

# --- group take-out: only the newest commits of the group's branch it is given ---
f9_tasks | m_setup
_wt57="$(python3 -B -c "import json; print(json.load(open('.temper/groups.json'))['groups']['G1'].get('worktree') or '')" 2>/dev/null)"
[[ -n "$_wt57" && "$_wt57" != /* ]] && _wt57="$WORKDIR/$_wt57"
echo one > "$_wt57/one.txt"; git -C "$_wt57" add one.txt; git -C "$_wt57" commit -q -m 'a commit the CLI did not make'
_c1="$(git -C "$_wt57" rev-parse HEAD)"
echo two > "$_wt57/two.txt"; git -C "$_wt57" add two.txt; git -C "$_wt57" commit -q -m 'a second commit the CLI did not make'
_c2="$(git -C "$_wt57" rev-parse HEAD)"
python3 -B - "$_c1" "$_c2" <<'PY'
import json, sys
p = ".temper/groups.json"
d = json.load(open(p))
d.setdefault("integration", {})["foreign"] = {"G1": sys.argv[1:]}
json.dump(d, open(p, "w"), indent=2)
PY
_old57="$("$TEMPER" group take-out G1 "${_c1:0:7}" >/dev/null 2>&1; echo $?)|$(git -C "$_wt57" rev-parse HEAD)"
_newest57="$("$TEMPER" group take-out G1 "${_c2:0:7}" >/dev/null 2>&1; echo $?)|$(git -C "$_wt57" rev-parse HEAD)"
assert_eq "w16 group take-out: a commit that is not the newest of the group's branch is refused; the newest it is given goes, the older stays" \
  "refused|$_c2|0|$_c1" "$([[ "${_old57%%|*}" != 0 ]] && echo refused || echo taken)|${_old57#*|}|$_newest57"

# --- drift ask, and Scope drift as the CLI's question ---
_build57
assert_eq "w16 drift ask: a path of the plan is refused; a path outside it is recorded" "refused|0" \
  "$("$TEMPER" drift ask --path src/demo.sh --why 'it needs a helper' --change 'one line' >/dev/null 2>&1 && echo recorded || echo refused)|$("$TEMPER" drift ask --path src/other.sh --why 'the parser needs it' --change 'one helper' >/dev/null 2>&1; echo $?)"
assert_eq "w16 drift: a pending drift gives the Scope drift question, with its three options and their calls" \
  "ask|scope.drift|Scope drift|Outside the plan: src/other.sh|why|change|add-to-plan,revert,allow-once|drift,drift,drift|calls" \
  "$(_x57 "a = d.get('ask') or {}
q = a.get('question') or {}
lines = [l.strip() for l in str(q.get('question', '')).split('\n')]
o = a.get('options') or []
cli = all(o) and len(o) > 0 and all(x.get('calls') and all(str(c).startswith('$TEMPER ') for c in x['calls']) for x in o)
r = '|'.join([str(d.get('action')), str(a.get('id')), str(q.get('header')), lines[0],
    'why' if 'Why: the parser needs it' in lines else 'no why', 'change' if 'Change: one helper' in lines else 'no change',
    ','.join(str(x.get('id')) for x in o), ','.join(str(x.get('move')) for x in o), 'calls' if cli else 'not all CLI calls'])")"
"$TEMPER" drift ask --path src/more.sh --why 'the docs need it' --change 'one line' >/dev/null 2>&1
for _i57 in 1 2; do
  case "$(_first57)" in
    *src/other.sh*) _answer57 add-to-plan ;;
    *src/more.sh*) _answer57 allow-once ;;
  esac
done
assert_eq "w16 drift: all answered, the agent runs again with one Drift decision line a file" "work|2|other add|more allow-once" \
  "$(_x57 "p = '\n'.join(str(a.get('prompt', '')) for a in d.get('agents') or [])
dl = [l.strip() for l in p.split('\n') if l.strip().startswith('Drift decision:')]
r = '|'.join([str(d.get('action')), str(len(dl)),
    'other add' if any('src/other.sh' in l and l.endswith(': add') for l in dl) else 'other: %s' % dl,
    'more allow-once' if any('src/more.sh' in l and l.endswith(': allow-once') for l in dl) else 'more: %s' % dl])")"
_unattended build
"$TEMPER" drift ask --path src/other.sh --why 'the parser needs it' --change 'one helper' >/dev/null 2>&1
_go57="$("$TEMPER" go 2>/dev/null | tail -n 1)"
assert_eq "w16 drift: an unattended run with a pending drift asks the Scope drift question and never moves by rule" \
  "ask|scope.drift|ask|scope.drift|0" \
  "$(_x57 "r = '%s|%s' % (d.get('action'), (d.get('ask') or {}).get('id'))")|$(python3 -B -c "
import json, sys
try:
    g = json.loads(sys.argv[1])
except ValueError:
    g = {}
moved = [c for c in g.get('ran') or [] if ' state advance ' in ' %s ' % c]
print('%s|%s|%d' % (g.get('action'), (g.get('ask') or {}).get('id'), len(moved)))" "$_go57")"

# --- the report step and the no record note are kinds (step 4): `step_kinds` beside `steps`, in next and in go ---
_kinds57() { # the kind of the report step and of the no record note, in `temper next --json` and in `temper go`
  python3 -B - "$("$TEMPER" next --json 2>/dev/null)" "$("$TEMPER" go 2>/dev/null | tail -n 1)" <<'PY'
import json, sys
out = []
for text in sys.argv[1:]:
    try:
        d = json.loads(text)
    except ValueError:
        d = {}
    steps, kinds = d.get("steps") or [], d.get("step_kinds") or []
    pairs = [(s, kinds[i] if i < len(kinds) else "") for i, s in enumerate(steps)]
    out.append(",".join(k for s, k in pairs if k) + ":" + str(sum(1 for s, k in pairs if not k and not s.startswith("/"))))
print("|".join(out))
PY
}
fresh; gpass intent plan build review check commit
git add -A >/dev/null 2>&1; git -c user.email=t@example.com -c user.name=T commit -qm "the spec is committed" >/dev/null 2>&1
_at commit
assert_eq "w16 step kinds: the report step carries the kind show-last beside the steps of next and go, and no other step is untyped text"   "show-last:0|show-last:0" "$(_kinds57)"
_vkinds57() { # the view's work action: its steps and its step_kinds, as `temper next --json` gives them
  python3 -B - "$("$TEMPER" next --json 2>/dev/null)" <<'PY'
import json, sys
try:
    d, v = json.loads(sys.argv[1]), json.load(open(".temper/view.json")).get("next") or {}
except (OSError, ValueError):
    d, v = {}, {}
print("%s|%s|%s" % (v.get("action"), ",".join(k for k in v.get("step_kinds") or [] if k) or "none",
                    "same" if (v.get("steps"), v.get("step_kinds")) == (d.get("steps"), d.get("step_kinds")) else "differ"))
PY
}
assert_eq "w16 step kinds: the view's work action carries step_kinds beside its steps, as next gives them" \
  "work|show-last|same" "$(_vkinds57)"
"$TEMPER" report --end >/dev/null 2>&1; "$TEMPER" report --no-html >/dev/null 2>&1
assert_eq "w16 step kinds: the no record note carries the kind note beside the steps of next and go, and no other step is untyped text"   "note:0|note:0" "$(_kinds57)"

# --- the cap: the closed list of hand back kinds is exactly seven, counted from NEEDS ---
_cap57="$(mktemp -d)"
mkdir -p "$_cap57/scripts"; find "$REPO_ROOT/scripts" -maxdepth 1 -type f -name '*.py' -exec cp {} "$_cap57/scripts/" \;
python3 -B - "$_cap57/scripts/flow_base.py" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r"([\"'])pipeline-fix\1", lambda m: '%spipeline-fix%s, %sw16-extra%s' % ((m.group(1),) * 4), s, count=1)
open(p, "w").write(s)
PY
assert_eq "w16 caps: handback_kinds is 7, now and final, counted from NEEDS of scripts/flow_base.py and from no file of the mod" \
  "7|7|7|8|no mod file" \
  "$(python3 -B - "$REPO_ROOT" "$_cap57" <<'PY'
import importlib.util, inspect, json, sys
def load(root, name):
    spec = importlib.util.spec_from_file_location(name, root + "/scripts/check_caps.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m
try:
    doc = json.load(open(sys.argv[1] + "/scripts/caps.json"))
    cap = doc["caps"]["handback_kinds"]
    real, copy = load(sys.argv[1], "check_caps_real"), load(sys.argv[2], "check_caps_copy")
    fn = real.MEASURES["handback_kinds"]
    src = inspect.getsource(fn)
    mod = "names a file of the mod" if (("hooks" + chr(47)) in src or "temper-mod" in src or ".ts" in src) else "no mod file"
    print("%s|%s|%s|%s|%s" % (cap["now"], cap["final"], fn(doc), copy.MEASURES["handback_kinds"](doc), mod))
except Exception as e:
    print("no cap handback_kinds: %s %s" % (type(e).__name__, e))
PY
)"
rm -rf "$_cap57"
setup
