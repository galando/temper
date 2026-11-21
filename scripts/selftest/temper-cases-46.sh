# Case file 46 (WP07): the rows of docs/plans/one-go/done.md that are cases of migration, the front and the surface, and
# D108 (the product's README.md). Sourced by test-temper.sh; its helpers (fresh, gpass, gfail, m_setup, nx, riskH) are
# used here. The first word of every assertion is the token of its row; a token still expected to fail is a line of
# scripts/selftest/expected-fail.txt. A call the CLI does not have yet stays inside $( ... ) or ends in || true, so the
# file always runs to its end. The runs and configs of an older Temper come from scripts/selftest/saved-old.json, which
# scripts/selftest/make-saved-old.sh made once from 9.8.4 (7c7a1c1) and from the base (10e965a); no case runs it.

# --- the helpers of this file ---
SAVED46="$TESTS_DIR/saved-old.json"
_clean46() { # an empty work folder
  cd "$WORKDIR" || exit 1
  find "$WORKDIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
  cd "$WORKDIR" || exit 1
}
_repo46() { # a fresh git repository under the run: two source files, every file but the run's own in one commit
  rm -rf .git src; git init -q . 2>/dev/null; git checkout -q -B master 2>/dev/null
  git config user.email t@example.com; git config user.name T
  mkdir -p src; printf 'echo a\n' > src/a.sh; printf 'echo b\n' > src/b.sh
  git add -A -- . ':(exclude).temper' ':(exclude).claude'; git commit -q -m base
}
_saved46() { # _saved46 <commit> <template|hook>: that text of saved-old.json, the plugin folder filled in
  python3 -I - "$SAVED46" "$1" "$2" "$REPO_ROOT" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))[sys.argv[2]][sys.argv[3]]
sys.stdout.write(d.replace("@PLUGIN@", sys.argv[4]))
PY
}
_restore46() { # _restore46 <commit> <state>: the project as that Temper left it at that state (a git repository whose one
               # commit adds README.md, then every saved file of .temper and the config, the folders filled in)
  _clean46
  git init -q . 2>/dev/null; git config user.email t@example.com; git config user.name t
  printf 'x\n' > README.md; git add README.md; git commit -q -m init
  local b
  b="$(python3 -I - "$SAVED46" "$1" "$2" "$WORKDIR" "$REPO_ROOT" "$(git rev-parse HEAD)" <<'PY'
import json, os, sys
saved, commit, state, work, plugin, head = sys.argv[1:7]
d = json.load(open(saved))[commit]["states"][state]
for rel, text in d["files"].items():
    p = os.path.join(work, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        f.write(text.replace("@PROJECT@", work).replace("@PLUGIN@", plugin).replace("@HEAD@", head))
print(d.get("branch") or "master")
PY
)"
  git checkout -q -B "${b:-master}" 2>/dev/null
}
_drive46() { # drives the run in the current folder with scripted answers and scripted agents, and prints
             # <end>|asked=<stages asked, in order>|reviews=<Review launches>|first=<the first question or launch>, the
             # first being ask:<question id> or the launched agent type. The person takes the recommended option of
             # every question (the first when none is); an agent's stage passes, as a gate run writes a verdict
             # (make-view-fixtures.sh); a Build ends with every group and task passed and the integration passed. The
             # end is commit when a question offers the option commit or is commit.confirm, else what stopped it.
  python3 -I - "$TEMPER" <<'PY'
import json, os, re, subprocess, sys
temper = sys.argv[1]
GATE = re.compile(r"/temper (gate \w+|task gate|group gate|integrate)\b")
def sh(c):
    c = c.replace("{reason}", "a reason").replace("{answer}", "the person").replace("{ms}", "1")
    return subprocess.run(["bash", "-c", c], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
def load(p, default):
    try:
        return json.load(open(p))
    except (OSError, ValueError):
        return default
def gpass(s):
    g = load(".temper/gates.json", {})
    g[s] = {"verdict": "PASS", "requirements": [{"name": "all", "pass": True, "detail": "ok"}]}
    json.dump(g, open(".temper/gates.json", "w"))
def built():
    st = load(".temper/build-state.json", {})
    sp = st.get("spec_path") or ".temper/specs/%s" % st.get("spec", "")
    try:
        text = open(os.path.join(sp, "tasks.md")).read()
    except OSError:
        text = ""
    groups, tasks, g = {}, {}, None
    for line in text.splitlines():
        m = re.match(r"## Group (G\d+)", line)
        if m:
            g = m.group(1)
            groups[g] = {"status": "passed", "gate": {"verdict": "PASS"}}
        m = re.match(r"### Task (\d+)", line)
        if m and g:
            tasks[m.group(1)] = {"status": "passed", "group": g}
    json.dump({"version": 1, "slug": st.get("spec", ""), "groups": groups, "tasks": tasks,
               "integration": {"verdict": "PASS"}}, open(".temper/groups.json", "w"))
    gpass("build")
asked, reviews, end, first = [], 0, "no commit question after 40 steps", ""
for _ in range(40):
    r = subprocess.run([temper, "next", "--json"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        d = json.loads(r.stdout)
    except ValueError:
        end = "no json"
        break
    a = d.get("action")
    s = load(".temper/build-state.json", {}).get("next_stage") or ""
    if a in ("broken", "error"):
        end = a
        break
    if a == "ask":
        q = d.get("ask") or {}
        opts = q.get("options") or []
        qid = str(q.get("id"))
        first = first or "ask:%s" % qid
        if qid.split(".")[0] not in asked:
            asked.append(qid.split(".")[0])
        if qid == "commit.confirm" or any(o.get("id") == "commit" for o in opts):
            end = "commit"
            break
        o = next((o for o in opts if o.get("recommended")), opts[0] if opts else {})
        for c in o.get("calls") or []:
            if sh(c).returncode:
                break
    elif a in ("auto", "work", "wait"):
        if any(x.get("type") == "temper:temper-review" for x in d.get("agents") or []):
            reviews += 1
        first = first or next((str(x.get("type")) for x in d.get("agents") or []), "")
        played = a == "wait" or bool(d.get("agents"))
        for c in (d.get("calls") or []) + [x for x in d.get("steps") or [] if x.startswith("/")]:
            if GATE.search(c):
                played = True
            else:
                sh(c)
        if played:
            built() if s == "build" else gpass(s)
    else:
        end = "action %s" % a
        break
print("%s|asked=%s|reviews=%d|first=%s" % (end, ",".join(asked), reviews, first))
PY
}
_d60d_read() { # _d60d_read <the line of _drive46>: "<end> review again" when the first thing after the restore is a
               # Review launch, before any question and any other launch; a Review of the ordinary fail loop (a
               # question, Build, then Review) is not it
  python3 -I -c "import sys
e, a, r, f = (sys.argv[1].split('|') + ['', '', ''])[:4]
print(e + (' review again' if f == 'first=temper:temper-review' else ' no review again'))" "$1"
}
_d60() { # _d60 <state> <a|c|d>: the saved state of 9.8.4 and of the base, each restored and driven on, joined
  local c out res=""
  for c in 7c7a1c1 10e965a; do
    _restore46 "$c" "$1"; out="$(_drive46)"
    case "$2" in
      a) out="${out%%|*}" ;;
      c) out="$(python3 -I -c "import sys
e, a, r = sys.argv[1].split('|')[:3]
s = a.split('=')[1].split(',')
print(e + (' asks at every stage' if all(x in s for x in ('build', 'review', 'check')) else ' asked only ' + ','.join(s)))" "$out")" ;;
      d) out="$(_d60d_read "$out")" ;;
    esac
    res+="${res:+|}$([[ $c == 7c7a1c1 ]] && echo 9.8.4 || echo base)=$out"
  done
  echo "$res"
}
_oldcfg46() { # _oldcfg46 <commit> [sed expression]: a new run at Intent, nothing launched yet, whose config is the
              # template of that Temper with the one change the expression makes
  setup
  rm -f .temper/specs/demo/intent.md .temper/specs/demo/tasks.md
  _saved46 "$1" template > .claude/temper.config
  [[ -z "${2:-}" ]] || sed -i "$2" .claude/temper.config
  cp .claude/temper.config .git/old-config-46
  "$TEMPER" state init demo --feature "the demo thing" >/dev/null 2>&1; _base_known
}
_qid46() { _ev "r = d.get('ask') or {}; r.get('id') if d.get('action') == 'ask' else d.get('action')" "$("$TEMPER" next --json 2>/dev/null)"; }
_tpl46() { # _tpl46 <function>: what the function prints on a new run whose config is the template of 9.8.4, then of
            # the base, each with one changed line (coverage-threshold 60), joined
  local c res=""
  for c in 7c7a1c1 10e965a; do
    _oldcfg46 "$c" 's/coverage-threshold: 80/coverage-threshold: 60/'
    res+="${res:+|}$([[ $c == 7c7a1c1 ]] && echo 9.8.4 || echo base)=$("$1")"
  done
  echo "$res"
}
_tidyq46() { # the first question: its id, whether its text names the copy, and the calls of tidy-config and keep-config
  python3 -I - "$("$TEMPER" next --json 2>/dev/null)" <<'PY'
import json, re, sys
try:
    d = json.loads(sys.argv[1])
except ValueError:
    d = {}
q = (d.get("ask") or {}) if d.get("action") == "ask" else {}
t = str((q.get("question") or {}).get("question") or "")
def calls(i):
    return " ".join(re.sub(r"^\S*/temper ", "", c) for o in q.get("options") or [] if o.get("id") == i for c in o.get("calls") or [])
print("%s %s tidy-config:%s keep-config:%s" % (q.get("id") or d.get("action"), "copy" if "copy" in t.lower() else "no copy",
                                               calls("tidy-config"), calls("keep-config")))
PY
}
_tidyyes46() { # after config tidy --apply: the copy, the changed line, an old default line, the question
  "$TEMPER" config tidy --apply >/dev/null 2>&1
  echo "copy $(cmp -s .git/old-config-46 .claude/temper.config.before-9.8.5 && echo same || echo differs)|$("$TEMPER" config get check.coverage-threshold 2>/dev/null)|stack $(grep -q '^stack:' .claude/temper.config && echo kept || echo gone)|asked config.tidy $([[ "$(_qid46)" == config.tidy ]] && echo yes || echo no)"
}
_tidyno46() { # after config tidy --keep: the file, the mark, the changed line, the question on the next two calls
  "$TEMPER" config tidy --keep >/dev/null 2>&1
  local f; f="$(python3 -I -c 'import sys; print("old file kept" if open(sys.argv[2]).read().startswith(open(sys.argv[1]).read()) else "file changed")' .git/old-config-46 .claude/temper.config)"
  "$TEMPER" next --json >/dev/null 2>&1
  echo "$f|asked $(grep -q 'asked' .claude/temper.config && echo written || echo missing)|$("$TEMPER" config get check.coverage-threshold 2>/dev/null)|$([[ "$(_qid46)" == config.tidy ]] && echo asked again || echo not asked)"
}

# --- D25: TRIVIAL is a verdict the CLI records, and the commit hook holds its bound ---
fresh; _repo46; rm -f .temper/specs/demo/intent.md .temper/specs/demo/tasks.md
"$TEMPER" intent trivial --why "a typo in the help text" >/dev/null 2>&1 || true
"$TEMPER" intent trivial --close >/dev/null 2>&1 || true
printf 'echo a%s\n' 1 2 3 4 5 > src/a.sh; printf 'echo more\n' >> src/a.sh; git add src/a.sh
_d25_small="$("$TEMPER" gate commit >/dev/null 2>&1; echo $?)"
git reset -q 2>/dev/null; git checkout -q -- src 2>/dev/null
printf 'echo a2\n' >> src/a.sh; printf 'echo b2\n' >> src/b.sh; git add src/a.sh src/b.sh
_d25_out="$("$TEMPER" gate commit 2>&1)"; _d25_big=$?
assert_eq "D25 after a trivial exit a commit of one file and 10 lines passes the commit gate; two production files fail on trivial exit" \
  "small=0|big=1|row=trivial exit" "small=$_d25_small|big=$_d25_big|row=$(grep -o 'trivial exit' <<<"$_d25_out" | head -1)"
git reset -q 2>/dev/null; git checkout -q -- src 2>/dev/null

# --- D26a to D26d: the plan amendment by rule, the plan patch by the person, the record and the replan ---
# (WP25: each task of _tasks46 has two cases, so the plan passes every static row an amendment and a patch run)
_tasks46() { cat <<'TASKS'
# Tasks: demo

**Integration:** `true`

## Group G1: Core
**Depends:** none
**Validate:** `true`
**Context:**
The core.

### Task 1: first
**File:** `src/a.sh`, `unit/a_test.sh`, `src/auth/login.sh`
**Depends:** none
**Test:** `true`
**Cases:**
- a holds
- a bad input is refused
- [ ] done

### Task 2: second
**File:** `src/b.sh`
**Depends:** Task 1
**Test:** `true`
**Cases:**
- b holds
- a bad input is refused
- [ ] done

## Group G2: Later
**Depends:** G1
**Validate:** `true`
**Context:**
The later work.

### Task 3: third
**File:** `src/c.sh`
**Depends:** none
**Test:** `true`
**Cases:**
- c holds
- a bad input is refused
- [ ] done
TASKS
}
_amend46() { # _amend46 <args...>: taken when the call exits 0 and changes tasks.md, refused when it exits non zero and
             # leaves tasks.md as it was
  local before rc; before="$(cksum < .temper/specs/demo/tasks.md)"
  "$TEMPER" plan "$@" >/dev/null 2>&1; rc=$?
  if [[ $rc -eq 0 && "$before" != "$(cksum < .temper/specs/demo/tasks.md)" ]]; then echo taken
  elif [[ $rc -ne 0 && "$before" == "$(cksum < .temper/specs/demo/tasks.md)" ]]; then echo refused
  else echo "rc=$rc"; fi
}
_tasks46 | m_setup
_d26a="none=$(_amend46 amend task 2 --add-file src/new.sh)|other-group=$(_amend46 amend task 2 --add-file src/c.sh)"
_d26a+="|test-file=$(_amend46 amend task 2 --add-file unit/a_test.sh)|sensitive=$(_amend46 amend task 2 --add-file src/auth/login.sh)"
_d26a+="|own=$(_amend46 amend task 2 --add-file src/a.sh)"
_d26a+="|line=$(grep -A1 '^### Task 2' .temper/specs/demo/tasks.md | grep '^\*\*File:\*\*' | grep -c '`src/a.sh`')"
assert_eq "D26a plan amend adds to a task only a file its own group declares; a new file, another group's, a test file and a sensitive path are refused" \
  "none=refused|other-group=refused|test-file=refused|sensitive=refused|own=taken|line=1" "$_d26a"

_tasks46 | m_setup
_d26b="amend-cmd=$(_amend46 amend G1 --cmd 'bash v.sh')|patch-cmd=$(_amend46 patch G1 --cmd 'bash v.sh')"
_d26b+="|amend-file=$(_amend46 amend task 2 --add-file src/new.sh)|patch-file=$(_amend46 patch task 2 --add-file src/new.sh)"
_d26b+="|approved=$(python3 -I -c "import json; print('src/new.sh' in json.load(open('.temper/build-state.json')).get('approved_files', []))")"
assert_eq "D26b a command line and a file outside the approved set are refused by plan amend and taken by plan patch" \
  "amend-cmd=refused|patch-cmd=taken|amend-file=refused|patch-file=taken|approved=True" "$_d26b"

_tasks46 | m_setup
_d26c_before="$(cksum < .temper/evidence/approved-tasks.json 2>/dev/null)"
"$TEMPER" plan amend task 2 --add-file src/a.sh >/dev/null 2>&1 || true
"$TEMPER" plan patch G1 --cmd 'bash v.sh' >/dev/null 2>&1 || true
assert_eq "D26c the approved record is byte equal after an amendment and a patch, and amendments.json gains one entry each" \
  "record=same|entries=amend,patch" \
  "record=$([[ -n "$_d26c_before" && "$_d26c_before" == "$(cksum < .temper/evidence/approved-tasks.json 2>/dev/null)" ]] && echo same || echo changed)|entries=$(python3 -I -c "
import json
try:
    d = json.load(open('.temper/evidence/amendments.json'))
except (OSError, ValueError):
    d = []
print(','.join(str(e.get('kind')) for e in d if isinstance(e, dict)))")"

fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
sed -i '/^\*\*Validate:\*\*/d' .temper/specs/demo/tasks.md
"$TEMPER" gate plan >/dev/null 2>&1
_d26d_row="$(python3 -I -c "
import json
rows = (json.load(open('.temper/gates.json')).get('plan') or {}).get('requirements') or []
print(next((str(x.get('pass')) for x in rows if x.get('name') == 'group validate command'), 'absent'))" 2>/dev/null)"
_replan46() { cat <<'TASKS'
# Tasks: demo

**Integration:** `true`

## Group G1: Core
**Depends:** none
**Validate:** `true`
**Context:**
The core.

### Task 1: first
**File:** `src/a.sh`
**Depends:** none
**Test:** `test -f src/a.sh`
**Cases:**
- a holds
- [ ] done

### Task 2: second
**File:** `src/b.sh`
**Depends:** Task 1
**Test:** `true`
**Cases:**
- b holds
- [ ] done
TASKS
}
_task46() { python3 -I -c "import json,sys; print(json.load(open('.temper/groups.json')).get('tasks', {}).get(sys.argv[1], {}).get(sys.argv[2], ''))" "$1" "$2" 2>/dev/null; }
_replan46 | m_setup
"$TEMPER" task start 1 >/dev/null 2>&1; "$TEMPER" task test 1 --phase red >/dev/null 2>&1
mkdir -p .claude/worktrees/temper-demo-T1/src; echo 'echo a' > .claude/worktrees/temper-demo-T1/src/a.sh
"$TEMPER" task test 1 --phase green >/dev/null 2>&1; "$TEMPER" task gate 1 --model m >/dev/null 2>&1
_d26d_c1="$(_task46 1 commit)"
"$TEMPER" state loop build plan --reason "a new Test line for Task 2" >/dev/null 2>&1
_replan46 | sed '/^### Task 2/,$s/^\*\*Test:\*\* `true`/**Test:** `bash unit-b.sh`/' > .temper/specs/demo/tasks.md
gpass plan; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
for _i in 1 2 3; do   # the first Build actions after the new approval: the CLI's own calls, or the before calls of its agents
  _d26d_calls="$(_ev "r = ((d.get('calls') or []) + [c for x in d.get('agents') or [] for c in x.get('before') or []]) if d.get('action') in ('auto', 'work') else []; chr(10).join(r)" "$("$TEMPER" next --json 2>/dev/null)")"
  [[ -n "$_d26d_calls" ]] || break
  while IFS= read -r _c; do [[ -n "$_c" ]] && bash -c "$_c" >/dev/null 2>&1; done <<<"$_d26d_calls"
done
assert_eq "D26d the plan gate fails a group with no Validate, and a replan keeps a built task whose fields did not change" \
  "row=False|task1=passed|kept commit=True|task2=not passed" \
  "row=$_d26d_row|task1=$(_task46 1 status)|kept commit=$([[ -n "$_d26d_c1" && "$_d26d_c1" == "$(_task46 1 commit)" ]] && git merge-base --is-ancestor "$_d26d_c1" temper/demo/G1 2>/dev/null && echo True || echo False)|task2=$([[ "$(_task46 2 status)" == passed ]] && echo passed || echo 'not passed')"
# the plan as approved has no Validate line for G1: plan patch adds the missing line, and the plan's row then passes
_tasks46 | sed '/^## Group G1/,/^### /{/^\*\*Validate:\*\*/d}' | m_setup
_d26e="patch=$(_amend46 patch G1 --cmd 'bash v.sh')|$(python3 -I - "$REPO_ROOT/scripts" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import plan_amend, tasks_md
g = next(g for g in tasks_md.parse(".temper/specs/demo/tasks.md")["groups"] if g["id"] == "G1")
row = plan_amend.static_rows(".temper/specs/demo", open(".temper/specs/demo/tasks.md").read()).get("group validate command")
print("G1=%s|row=%s" % (g["validate"] or "none", row[0] if row else "absent"))
PY
)"
assert_eq "D26e plan patch adds the missing Validate line of a group whose approved plan has none, and the plan's row then passes" \
  "patch=taken|G1=bash v.sh|row=True" "$_d26e"

# --- D27a to D27c: the simple tier writes tasks.md only, the briefs ask for nothing unread, and the CLI bounds the tier ---
_tier46() { # a run at Plan, tier simple, the plan gate run on the plan as it stands
  fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
  "$TEMPER" state set complexity simple >/dev/null 2>&1; rm -f .temper/specs/demo/plan.md
}
_row46() { # _row46 <stage> <row>: pass of that row of the stage's verdict, or absent
  python3 -I -c "
import json, sys
rows = (json.load(open('.temper/gates.json')).get(sys.argv[1]) or {}).get('requirements') or []
print(next((str(x.get('pass')) for x in rows if x.get('name') == sys.argv[2]), 'absent'))" "$1" "$2" 2>/dev/null || echo absent
}
_tier46; "$TEMPER" gate plan >/dev/null 2>&1
assert_eq "D27a at the simple tier a plan of tasks.md only passes the plan gate, and no cut row is left in it" \
  "verdict=PASS|cut rows=none" \
  "verdict=$(python3 -I -c "import json; print((json.load(open('.temper/gates.json')).get('plan') or {}).get('verdict'))" 2>/dev/null)|cut rows=$(python3 -I -c "
import json
rows = (json.load(open('.temper/gates.json')).get('plan') or {}).get('requirements') or []
cut = [x['name'] for x in rows if x.get('name') in ('cross-repo search recorded', 'blast radius documented', 'criteria -> scenarios')]
print(','.join(cut) or 'none')" 2>/dev/null)"
assert_eq "D27b no brief, reference page or template asks for a part that nothing reads" "none|mermaid=0" \
  "$(git -C "$REPO_ROOT" grep -l -F -e 'Cross-Repo Search' -e 'Files to Create' -e 'Files to Modify' -e 'Patterns to Follow' \
      -e 'Risk Level:' -e 'Scenario Coverage Checklist' -e 'Target Users' -e 'Business Outcome' -e 'Traced to' \
      -e 'Given/When/Then' -e 'Approach Decisions' -e '## Diagram' -- agents reference templates | { tr '\n' ' '; echo; } | sed 's/ $//;s/^$/none/')|mermaid=$(cat "$REPO_ROOT/templates/plan.md" 2>/dev/null | grep -c mermaid)"
_d27c=""
_tier46; second_group; "$TEMPER" gate plan >/dev/null 2>&1; _d27c+="two groups=$(_row46 plan 'tier recorded')"
_tier46; sed -i 's|^\*\*File:\*\* `src/demo.sh`|**File:** `src/demo.py`, `src/one.py`, `src/two.py`, `src/three.py`|' .temper/specs/demo/tasks.md
"$TEMPER" gate plan >/dev/null 2>&1; _d27c+="|four files=$(_row46 plan 'tier recorded')"
_tier46; riskH; "$TEMPER" gate plan >/dev/null 2>&1; _d27c+="|risk H=$(_row46 plan 'tier recorded')"
assert_eq "D27c tier simple with two groups, with four production files or at risk H fails the row tier recorded" \
  "two groups=False|four files=False|risk H=False" "$_d27c"

# --- D28: the builders on Sonnet with a key for Haiku; the planner on Opus behind a key ---
_models46() { # the plan and task lines of temper model --all --source, as <model> <source>
  "$TEMPER" model --all --source 2>/dev/null | python3 -I -c "
import re, sys
got = {}
for line in sys.stdin:
    m = re.match(r'^\s*(plan|task)(?:\s*[=:]\s*|\s+)(\S+?)[,\s]+\(?([a-z]+)', line)
    if m:
        got[m.group(1)] = '%s %s' % (m.group(2), m.group(3))
print('plan=%s|task=%s' % (got.get('plan', 'none'), got.get('task', 'none')))"
}
setup; printf 'review:\n  block-on: [critical, high]\n' > .claude/temper.config
_d28="table: $(_models46)"
printf 'models:\n  plan: sonnet\n  task: haiku\n' >> .claude/temper.config
_d28+=" / keys: $(_models46)"
assert_eq "D28 the default table runs the planner on Opus and the builders on Sonnet; models.plan and models.task change them" \
  "table: plan=opus table|task=sonnet table / keys: plan=sonnet config|task=haiku config" "$_d28"

# --- D29a to D29d: two listed commands, the words of /temper:temper, no armed or parked, at most 12 words ---
assert_eq "D29a the manifest lists two commands, /temper:temper and /temper:fix, and no door file is tracked" \
  "manifest=./commands/fix.md,./commands/temper.md|tracked=commands/fix.md,commands/temper.md" \
  "manifest=$(python3 -I -c "import json,sys; print(','.join(sorted(json.load(open(sys.argv[1])).get('commands') or [])))" "$REPO_ROOT/.claude-plugin/plugin.json")|tracked=$(git -C "$REPO_ROOT" ls-files commands | sort | tr '\n' ',' | sed 's/,$//')"
assert_eq "D29b draft, status, report, init and pack are rows of the Arguments table, and a word with text after it is a request" \
  "draft,init,pack,report,status|rule=yes" "$(python3 -I - "$REPO_ROOT/commands/temper.md" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
sec = text.split("## Arguments", 1)[1].split("\n## ", 1)[0] if "## Arguments" in text else ""
first = [l.split("|")[1] for l in sec.splitlines() if l.startswith("|") and l.count("|") >= 3]
have = sorted(w for w in ("draft", "status", "report", "init", "pack") if any(re.search(r"`%s\b" % w, c) for c in first))
low = " ".join(sec.lower().split())
print("%s|rule=%s" % (",".join(have), "yes" if "alone" in low and "is a request" in low else "no"))
PY
)"
assert_eq "D29c armed and parked are in no text of a fixture view and on no page a user reads" "none" "$(python3 -I - "$REPO_ROOT" <<'PY'
import json, os, re, sys
root = sys.argv[1]
WORD = re.compile(r"\b(armed|parked)\b", re.I)
hits = []
def views(path):
    text = open(path, encoding="utf-8").read()
    return json.loads(text[text.index("= {") + 2:])
def walk(o, key, where, top=False):
    if isinstance(o, dict):
        for k, v in o.items():
            if k != "calls" and (k != "status" or top):
                walk(v, k, where)
    elif isinstance(o, list):
        for v in o:
            walk(v, key, where)
    elif isinstance(o, str) and key in ("question", "label", "description", "say", "status", "header", "text") and WORD.search(o):
        hits.append(where)
for f in ("view-fixtures.ts", "view-fixtures-2.ts"):
    for name, v in views(os.path.join(root, "scripts", "selftest", f)).items():
        walk(v, "", "view " + name, top=True)
def prose(text):
    text = re.sub(r"```.*?```", " ", text, flags=re.S)
    return re.sub(r"`[^`\n]*`", " ", text)
for page in ("README.md", "docs/getting-started.md", "docs/index.md", "docs/commands.md"):
    p = os.path.join(root, page)
    if os.path.isfile(p) and WORD.search(prose(open(p, encoding="utf-8").read())):
        hits.append(page)
tpl = open(os.path.join(root, "templates", "temper.config.default"), encoding="utf-8").read()
if WORD.search(prose("\n".join(l.split("#", 1)[1] for l in tpl.splitlines() if "#" in l))):
    hits.append("the comments of the template")
cmd = open(os.path.join(root, "commands", "temper.md"), encoding="utf-8").read()
args = cmd.split("## Arguments", 1)[1].split("\n## ", 1)[0] if "## Arguments" in cmd else ""
if WORD.search(prose(args)):
    hits.append("the Arguments of commands/temper.md")
if WORD.search(json.load(open(os.path.join(root, ".claude-plugin", "plugin.json"))).get("description", "")):
    hits.append("the description of the manifest")
print(", ".join(sorted(set(hits))[:6]) or "none")
PY
)"
assert_eq "D29d scripts/words.json holds at most 12 words, and The words of Getting Started has one line for each and no other" \
  "ok" "$(python3 -I - "$REPO_ROOT" <<'PY'
import json, os, re, sys
root = sys.argv[1]
try:
    w = json.load(open(os.path.join(root, "scripts", "words.json"))).get("words")
except (OSError, ValueError, AttributeError):
    print("no scripts/words.json"); sys.exit(0)
words = list(w.keys()) if isinstance(w, dict) else [x.get("word") if isinstance(x, dict) else x for x in w or []]
try:
    gs = open(os.path.join(root, "docs", "getting-started.md"), encoding="utf-8").read()
except OSError:
    gs = ""
sec = gs.split("## The words", 1)[1].split("\n## ", 1)[0] if "## The words" in gs else ""
rows, seen_table = [], False
for l in sec.splitlines():
    if l.startswith("|"):
        if re.match(r"^\|[\s:|-]+\|?\s*$", l):
            continue
        if not seen_table:
            seen_table = True
            continue
        rows.append(l)
    elif re.match(r"^\s*[-*] ", l):
        rows.append(l)
bad = [x for x in words if sum(1 for r in rows if re.search(r"\b%s\b" % re.escape(str(x)), r, re.I)) != 1]
if not words or len(words) > 12:
    print("%d words" % len(words))
elif bad or len(rows) != len(words):
    print("lines %d for %d words; not one line: %s" % (len(rows), len(words), ",".join(map(str, bad))))
else:
    print("ok")
PY
)"

# --- D58b: the weights of the replay are not below those of the base for any agent type ---
assert_eq "D58b the minutes a launch in scripts/e2e/replay.ts are not below those of 10e965a for any agent type" "none below" \
  "$(python3 -I - "$REPO_ROOT" <<'PY'
import os, re, subprocess, sys
def table(text):
    m = re.search(r"const AGENT_MIN[^=]*=\s*\{(.*?)\}", text, re.S)
    return {k: float(v) for k, v in re.findall(r"'([^']+)':\s*([0-9.]+)", m.group(1))} if m else None
base_text = subprocess.run(["git", "-C", sys.argv[1], "show", "10e965a:scripts/e2e/replay.ts"], stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, text=True).stdout
now = table(open(os.path.join(sys.argv[1], "scripts", "e2e", "replay.ts"), encoding="utf-8").read())
base = table(base_text)
if not now or not base:
    print("no table: now=%s base=%s" % (bool(now), bool(base)))
else:
    low = ["%s %g<%g" % (k, now[k], v) for k, v in sorted(base.items()) if k in now and now[k] < v]
    print(", ".join(low) or "none below")
PY
)"

# --- D60a to D60e: a run saved by 9.8.4 and one saved by the base each go on to the commit question ---
assert_eq "D60a the plan question saved by 9.8.4 and by the base goes on to the commit question, never broken or error" \
  "9.8.4=commit|base=commit" "$(_d60 plan a)"
assert_eq "D60b Build with a group running, saved by 9.8.4 and by the base, goes on to the commit question" \
  "9.8.4=commit|base=commit" "$(_d60 build-group a)"
assert_eq "D60c an armed run in Build saved by 9.8.4 and by the base is taken up asking at every stage, to the commit question" \
  "9.8.4=commit asks at every stage|base=commit asks at every stage" "$(_d60 armed-build c)"
assert_eq "check46: the reader of D60d takes a Review launch first after the restore, not the Review of the fail loop" \
  "commit review again|commit no review again" \
  "$(_d60d_read 'commit|asked=build,check|reviews=1|first=temper:temper-review')|$(
    _d60d_read 'commit|asked=review,build,check|reviews=1|first=ask:review.fail')"
assert_eq "D60d Review with an open finding saved by 9.8.4 and by the base runs Review once more and reaches the commit question" \
  "9.8.4=commit review again|base=commit review again" "$(_d60 review-finding d)"
assert_eq "D60e a parked run saved by 9.8.4 and by the base goes on to the commit question" \
  "9.8.4=commit|base=commit" "$(_d60 parked a)"

# --- D61a, D61b: an old config works; a key that is no longer read is named once and is never an error ---
_d61() { # _d61 <commit>: next, every gate, config get and config show with that Temper's template as the config
  _oldcfg46 "$1"
  local s rc nx_ok=ok gates=ok get=ok out
  out="$("$TEMPER" next --json 2>/dev/null)"
  _ev "d.get('action')" "$out" | grep -qvE '^(broken|error)$' || nx_ok="no"
  for s in intent plan design build review check commit; do
    out="$("$TEMPER" gate "$s" 2>&1)"; rc=$?
    [[ $rc -le 1 ]] && ! grep -q 'Traceback' <<<"$out" || gates="$s exit $rc"
  done
  "$TEMPER" config get review.block-on >/dev/null 2>&1 || get="no"
  out="$("$TEMPER" config show 2>&1)"; rc=$?
  echo "next=$nx_ok|gates=$gates|get=$get|stale=$([[ $rc -eq 0 ]] && echo "named $(grep -c 'loops.max-per-type' <<<"$out")" || echo "show exit $rc")"
}
assert_eq "D61a with the template of 9.8.4 as the config, next, every gate and config get run, and a key no longer read is named once" \
  "next=ok|gates=ok|get=ok|stale=named 1" "$(_d61 7c7a1c1)"
assert_eq "D61b with the template of the base as the config, next, every gate and config get run, and a key no longer read is named once" \
  "next=ok|gates=ok|get=ok|stale=named 1" "$(_d61 10e965a)"

# --- D62a to D62c, D63b: the one time question on a config of 9.8.4 and of the base ---
assert_eq "D62a the first next of a run on an old config asks config.tidy once, names the copy, and offers tidy and keep" \
  "9.8.4=config.tidy copy tidy-config:config tidy --apply keep-config:config tidy --keep|base=config.tidy copy tidy-config:config tidy --apply keep-config:config tidy --keep" \
  "$(_tpl46 _tidyq46)"
assert_eq "D62b yes keeps the line the person changed, drops the old defaults, keeps a copy, and is not asked again" \
  "9.8.4=copy same|60|stack gone|asked config.tidy no|base=copy same|60|stack gone|asked config.tidy no" "$(_tpl46 _tidyyes46)"
assert_eq "D62c no keeps the file with upgrade.asked, the old values still rule, and it is never asked again" \
  "9.8.4=old file kept|asked written|60|not asked|base=old file kept|asked written|60|not asked" "$(_tpl46 _tidyno46)"
_d63b=""
for _c in 7c7a1c1 10e965a; do
  _oldcfg46 "$_c" 's/^autonomy:$/autonomy:\n  enabled: false/'
  "$TEMPER" config tidy --apply >/dev/null 2>&1 || true
  _d63b+="${_d63b:+|}$([[ $_c == 7c7a1c1 ]] && echo 9.8.4 || echo base)=$("$TEMPER" config get run.default 2>/dev/null)"
  _d63b+=",$(python3 -I -c "
import re, sys
t = open('.claude/temper.config').read()
print('file says ask' if re.search(r'^run:\s*\n(?:\s+.*\n)*?\s+default:\s*ask\b', t, re.M) else 'file does not say ask')"),$(grep -q 'enabled: false' .claude/temper.config && echo 'enabled kept' || echo 'enabled gone')"
done
assert_eq "D63b autonomy.enabled false in a config of 9.8.4 or of the base becomes run.default ask after the answer that removes old lines" \
  "9.8.4=ask,file says ask,enabled gone|base=ask,file says ask,enabled gone" "$_d63b"

# --- D64a, D64b: the commit hook of 9.8.4, which is also the base's, blocks under a failed gate and is not asked again ---
_hook46() { # the hook as the installer of 9.8.4 writes it, kept in the git folder, with core.hooksPath on its folder
  mkdir -p .git/temper-gate; _saved46 7c7a1c1 hook > .git/temper-gate/pre-commit; chmod +x .git/temper-gate/pre-commit
  git config core.hooksPath "$(cd .git/temper-gate && pwd -P)"
}
fresh; _repo46; _hook46
gpass intent plan build; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
"$TEMPER" state advance plan_complete build >/dev/null 2>&1; "$TEMPER" state advance build_complete review >/dev/null 2>&1
gfail review "no blocking findings" "1 open critical finding"
git checkout -q -B "$("$TEMPER" state get branch 2>/dev/null)" 2>/dev/null   # the gate holds a commit on the run's branch
printf 'echo changed\n' >> src/a.sh; git add src/a.sh
assert_eq "D64a the commit hook the installer of 9.8.4 wrote (no file under scripts/guards differs at the base) refuses a commit under a failed gate" \
  "refused|1" "$(git commit -q -m change >/dev/null 2>&1 && echo committed || echo refused)|$(git rev-list --count HEAD)"
_d64b_chg="$(python3 -I - "$REPO_ROOT/scripts/guards/install.sh" "$(git -C "$REPO_ROOT" show 10e965a:scripts/guards/install.sh 2>/dev/null)" <<'PY'
import re, sys
def body(text):
    m = re.search(r"^_hook_body\(\) \{\n(.*?)^\}\n", text, re.S | re.M)
    return m.group(1) if m else None
now, base = body(open(sys.argv[1], encoding="utf-8").read()), body(sys.argv[2])
print("unknown" if base is None or now is None else ("yes" if now != base else "no"))
PY
)"
assert_eq "D64b the setup check asks a hook of 9.8.4 or of the base to install again exactly when this build changed the hook body" \
  "body changed=$_d64b_chg|asked=$_d64b_chg" \
  "body changed=$_d64b_chg|asked=$(nx "'yes' if any('guards install' in c for c in d.get('setup') or []) else 'no'")"
git config --unset core.hooksPath 2>/dev/null; git reset -q 2>/dev/null

# --- D65: the view stays version 1, and no field of a view of the base is renamed or removed ---
assert_eq "D65 every field name of the fixture views of the base is in the fixture views of the head, and every view is version 1" \
  "missing=none|version=1" "$(python3 -I - "$REPO_ROOT" <<'PY'
import json, os, subprocess, sys
def views(text):
    return json.loads(text[text.index("= {") + 2:]) if "= {" in text else {}
def names(o, out):
    if isinstance(o, dict):
        for k, v in o.items():
            out.add(k)
            names(v, out)
    elif isinstance(o, list):
        for v in o:
            names(v, out)
base, now, versions = set(), set(), set()
for f in ("view-fixtures.ts", "view-fixtures-2.ts"):
    t = subprocess.run(["git", "-C", sys.argv[1], "show", "10e965a:scripts/selftest/" + f], stdout=subprocess.PIPE,
                       stderr=subprocess.DEVNULL, text=True).stdout
    for v in views(t).values():
        names(v, base)
for f in ("view-fixtures.ts", "view-fixtures-2.ts"):
    for v in views(open(os.path.join(sys.argv[1], "scripts", "selftest", f), encoding="utf-8").read()).values():
        names(v, now)
        versions.add(str(v.get("version")))
print("missing=%s|version=%s" % (",".join(sorted(base - now)) or ("none" if base else "no base"), ",".join(sorted(versions))))
PY
)"

# --- D71: every key of the config template, live or commented, has a reader in code ---
assert_eq "D71 python3 scripts/check_config_keys.py holds, and every live key of the template is a key of the defaults table" \
  "reader test=0|live keys=all in KEYS" "reader test=$(cd "$REPO_ROOT" && python3 scripts/check_config_keys.py >/dev/null 2>&1; echo $?)|live keys=$(python3 -I - "$REPO_ROOT" <<'PY'
import os, re, sys
root = sys.argv[1]
sys.path.insert(0, os.path.join(root, "scripts"))
try:
    import defaults
    k = defaults.KEYS
    keys = set(k.keys()) if isinstance(k, dict) else {x[0] if isinstance(x, (list, tuple)) else x.get("key") for x in k}
except Exception as e:
    print("no defaults table (%s)" % type(e).__name__); sys.exit(0)
stack, live = [], []
for line in open(os.path.join(root, "templates", "temper.config.default"), encoding="utf-8"):
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    m = re.match(r"^( *)([A-Za-z0-9_.-]+):\s*(.*?)\s*(?:#.*)?$", line.rstrip("\n"))
    if not m:
        continue
    depth = len(m.group(1)) // 2
    stack[depth:] = [m.group(2)]
    if m.group(3):
        live.append(".".join(stack[:depth + 1]))
missing = [x for x in live if x not in keys]
print("all in KEYS" if not missing else "not in KEYS: " + ",".join(missing[:6]))
PY
)"

# --- D76, D76b: every stop keeps its check, and no stop left the list without a decision record ---
assert_eq "D76 no stop of scripts/stops.json has an empty check, and each check names an assertion or a scenario that exists" "ok" \
  "$(cd "$REPO_ROOT" && python3 -I - <<'PY'
import json, subprocess
stops = json.load(open("scripts/stops.json")).get("stops") or []
bad = []
for s in stops:
    c = (s.get("check") or "").strip()
    found = c and subprocess.run(["git", "grep", "-q", "-F", "-e", c, "--", "scripts/selftest/temper-cases-*.sh", "scripts/e2e/*.ts"]).returncode == 0
    if not found:
        bad.append(s.get("id"))
print("ok" if stops and not bad else ("no stops" if not stops else "no check: " + ",".join(map(str, bad[:6]))))
PY
)"
assert_eq "D76b every stop id a commit of the branch added to scripts/stops.json is still in it, or a decision record names its removal" "ok" \
  "$(cd "$REPO_ROOT" && python3 -I - <<'PY'
import json, re, subprocess
log = subprocess.run(["git", "log", "-p", "--format=", "--", "scripts/stops.json"], stdout=subprocess.PIPE, text=True).stdout
added = set(re.findall(r'^\+\s*"id":\s*"([^"]+)"', log, re.M))
now = {s.get("id") for s in json.load(open("scripts/stops.json")).get("stops") or []}
gone = [i for i in sorted(added - now)
        if subprocess.run(["git", "grep", "-q", "-F", "-e", i, "--", "docs/decisions"]).returncode != 0]
print("ok" if added and not gone else ("no history" if not added else "gone with no record: " + ",".join(gone[:6])))
PY
)"

# --- D79a, D79b: what keeps the product from growing back ---
assert_eq "D79a CI runs the caps and the floor in a job that the gate job needs" "ok" "$(python3 -I - "$REPO_ROOT/.github/workflows/quality.yml" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
jobs = text.split("\njobs:\n", 1)[1] if "\njobs:\n" in text else ""
blocks = {m.group(1): m.group(2) for m in re.finditer(r"^  ([A-Za-z0-9_-]+):\n((?:(?:    .*|\s*)\n)*)", jobs, re.M)}
fc = [n for n, b in blocks.items() if "scripts/check_caps.py" in b and "scripts/check_floor.py" in b]
gate = blocks.get("gate", "")
m = re.search(r"needs:\s*\[([^\]]*)\]", gate, re.S)
needs = [x.strip() for x in m.group(1).split(",")] if m else []
print("ok" if fc and any(n in needs for n in fc) else "jobs %s, gate needs %s" % (fc, needs))
PY
)"
assert_eq "D79b .claude/CLAUDE.md holds the two standing rules: a failing step shown not removable first, and a cap raised alone" \
  "rule one|rule two" "$(python3 -I - "$REPO_ROOT/.claude/CLAUDE.md" <<'PY'
import sys
t = " ".join(open(sys.argv[1], encoding="utf-8").read().split())
one = "show that the failing step cannot be removed or merged" in t
two = "raised only in a pull request of its own" in t
print("%s|%s" % ("rule one" if one else "no rule one", "rule two" if two else "no rule two"))
PY
)"

# --- D102: a project that ran 9.8.4, or the base, is told once that a run now asks twice; a new one never ---
_notice46() { # the say of two nexts: told when the first starts with the notice, quiet when no say does; dialog when a
              # question holds it
  local a b
  a="$("$TEMPER" next --json 2>/dev/null)"; b="$("$TEMPER" next --json 2>/dev/null)"
  echo "$(_ev "'told' if str(d.get('say') or '').startswith('Temper 9.8.5 asks twice') else 'quiet'" "$a"),$(_ev "'told' if 'Temper 9.8.5 asks twice' in str(d.get('say') or '') else 'quiet'" "$b"),$(_ev "import json; 'in a dialog' if 'asks twice' in json.dumps(d.get('ask') or {}) else 'no dialog'" "$a")"
}
_d102=""
for _c in 7c7a1c1 10e965a; do _restore46 "$_c" plan; _d102+="$([[ $_c == 7c7a1c1 ]] && echo 9.8.4 || echo base)=$(_notice46)|"; done
_clean46; git init -q . 2>/dev/null; mkdir -p .claude; printf 'review:\n  block-on: [critical, high]\n' > .claude/temper.config
"$TEMPER" init >/dev/null 2>&1; "$TEMPER" state init demo --feature "the demo thing" >/dev/null 2>&1; _base_known
_d102+="new=$(_notice46)"
assert_eq "D102 a project of 9.8.4 or of the base is told once, in one line that starts Temper 9.8.5 asks twice and never in a dialog; a new one never" \
  "9.8.4=told,quiet,no dialog|base=told,quiet,no dialog|new=quiet,quiet,no dialog" "$_d102"

# --- D103: the places where the documents and the code disagreed are gone (the ones a string can prove) ---
assert_eq "D103 each place where a page and the code disagreed that a string can prove holds what the code does" "$(printf 'ok|%.0s' {1..13} | sed 's/|$//')" \
  "$(cd "$REPO_ROOT" && python3 -I - <<'PY'
import re, subprocess
def text(p):
    try:
        return open(p, encoding="utf-8").read()
    except OSError:
        return ""
def no(p, *s):
    t = text(p)
    return "ok" if not any(x in t for x in s) else "%s holds %s" % (p, [x for x in s if x in t][0])
cm = text("docs/commands.md")
out = [
    "ok" if not re.search(r"^\s*\d+\.\s+Share HTML review", cm, re.M) and "Continue to Build" not in cm
    else "docs/commands.md lists the old plan options",
    no("docs/commands.md", "Confidence: 94%"),
    no(".claude/CLAUDE.md", "enabled: false"),
    no("templates/temper.config.default", "enabled: false"),
    no("commands/temper.md", "HTML page too"),
    "ok" if "critical, high" in text("agents/review.md") and "(default: `critical`)" not in text("agents/review.md")
    else "agents/review.md names another default",
    "ok" if subprocess.run(["git", "grep", "-q", "-F", "-e", "Claude makes it", "--", "docs/commands.md", "*.ts", ":(exclude)*.test.ts",
                                    ":(exclude)scripts/e2e"]).returncode
    else "a page or the mod says Claude makes a typed change",
    no("docs/packs.md", "8 built-in"),
    no("docs/context-hygiene.md", "224", "about 10 KB"),
    no("docs/trust.md", "ten Python scripts"),
    "ok" if subprocess.run(["git", "grep", "-q", "-i", "-F", "-e", "who reviews the intent", "--", "commands", "agents", "reference"]).returncode
    else "a page asks who reviews the intent",
    no("docs/getting-started.md", "review.confidence-threshold", "check.live-scenarios", "tools.label-findings"),
    no("docs/enterprise.md", "plan.default-depth", "branch.pattern", "branch.commit-style"),
]
print("|".join(out))
PY
)"

# --- D104: what no default run reads is not shipped; the default packs are security and tdd ---
setup; printf 'review:\n  block-on: [critical, high]\n' > .claude/temper.config
assert_eq "D104 no stack pack, the two skills grill-me and teach-me, no text on OCR, bands, review memory or metrics, and the default packs security and tdd" \
  "stacks=none|skills=./skills/grill-me,./skills/teach-me|dormant=none|packs=security,tdd" \
  "stacks=$(git -C "$REPO_ROOT" ls-files packs/stacks | head -3 | { tr '\n' ','; echo; } | sed 's/,$//;s/^$/none/')|skills=$(python3 -I -c "import json,sys; print(','.join(sorted(json.load(open(sys.argv[1])).get('skills') or [])))" "$REPO_ROOT/.claude-plugin/plugin.json")|dormant=$(git -C "$REPO_ROOT" grep -il -e 'review-memory' -e 'open-code-review' -e 'tools.ocr' -e 'metrics append' -e 'metrics.json' -e 'temper bands' -e 'claimed-runs' -- agents reference commands templates scripts README.md docs ':(exclude)docs/history' ':(exclude)docs/plans' ':(exclude)docs/evidence' ':(exclude)docs/decisions' ':(exclude)scripts/selftest' ':(exclude)scripts/e2e' ':(exclude)scripts/defaults.py' ':(exclude)scripts/config_tidy.py' ':(exclude)scripts/check_config_keys.py' ':(exclude)scripts/check_words.py' 2>/dev/null | head -4 | { tr '\n' ','; echo; } | sed 's/,$//;s/^$/none/')|packs=$("$TEMPER" config get packs 2>/dev/null | grep -oE '[a-z][a-z-]*' | sort | tr '\n' ',' | sed 's/,$//')"

# --- D108: the product's README.md is concise ---
assert_eq "D108 README.md has at most 80 lines, Install before What the mod reads and writes, the two commands only, and no figure of cost or time but from the scorecard" \
  "lines ok|headings ok|commands=fix,temper|figures ok" "$(python3 -I - "$REPO_ROOT" <<'PY'
import os, re, sys
root = sys.argv[1]
text = open(os.path.join(root, "README.md"), encoding="utf-8").read()
lines = text.split("\n")
if lines and lines[-1] == "":
    lines = lines[:-1]
heads = [l.strip() for l in lines if l.startswith("## ")]
inst = heads.index("## Install") if "## Install" in heads else -1
mod = heads.index("## What the mod reads and writes") if "## What the mod reads and writes" in heads else -1
cmds = sorted(set(re.findall(r"/temper:([a-z][a-z-]*)", text)))
card = "docs/evidence/scorecard-9.8.5.json"
has_card = os.path.isfile(os.path.join(root, card))
FIG = re.compile(r"\$\s?\d|\d(?:[\d,.]*\d)?\s*%|\d(?:[\d,.]*\d)?\s+(?:times|seconds|minutes|hours)\b", re.I)
bad = []
for m in FIG.finditer(text):
    n = text.count("\n", 0, m.start())
    if not (has_card and card in lines[n]):
        bad.append(n + 1)
print("%s|%s|commands=%s|%s" % (
    "lines ok" if len(lines) <= 80 else "%d lines" % len(lines),
    "headings ok" if 0 <= inst < mod else "headings %s" % heads,
    ",".join(cmds),
    "figures ok" if not bad else "figures on lines %s" % ",".join(map(str, bad[:6]))))
PY
)"
