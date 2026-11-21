# Case file 61 (WP20): the environment check, the baseline and the limits. Before any agent is paid for, a run checks
# the tools and services its project names (under 5 s, no suite) and runs the project's own suite once on the current
# code, in a detached worktree under .claude/worktrees/ (`temper baseline start`, which always exits 0). The result is
# green, red or unknown in .temper/evidence/baseline.json; a red base is the one question `base.red` (add-setup,
# check-again, go-on-anyway, save); "Go on anyway" is a recorded skip of the row `tests pass` (the override
# `base-suite`), kept for a later run with the same key; the measured seconds set the limits (three times the base,
# never below the default), and a first time out runs the check again with twice its limit as the CLI's own call.
# Sourced by test-temper.sh; its helpers (fresh, gpass, nx, _at, m_setup, f9_tasks, f9_intent) are used here, and the
# builders below are this file's own. Token: w20. Every case that tests the start itself removes
# .temper/evidence/baseline.json first, and the suite runs in the foreground (TEMPER_BASELINE_FOREGROUND=1) unless a
# case says otherwise. A call the CLI does not have yet stays inside $( ... ) or ends in || true, so the file always
# runs to its end.

# --- the helpers of this file ---
_x61() { # _x61 <python code over d, the JSON of temper next (or of the second argument)>: prints r. opts(d) is every
         # option of the question and of its More question, opt(d, i) the one with that id, short(c) a call without the
         # path of the CLI, sec(d, i) the card's section i, text(d) the question's text
  python3 -B - "$1" "${2:-$("$TEMPER" next --json 2>/dev/null)}" <<'PY'
import json, re, sys
try:
    d = json.loads(sys.argv[2])
except ValueError:
    d = {}
def opts(d):
    a = d.get("ask") or {}
    return list(a.get("options") or []) + list((a.get("more") or {}).get("options") or [])
def opt(d, i):
    return next((o for o in opts(d) if o.get("id") == i), None)
def short(c):
    return re.sub(r"^\S*/temper ", "", str(c))
def sec(d, i):
    return next((s for s in ((d.get("card") or {}).get("sections") or []) if s.get("id") == i), None)
def text(d):
    return str(((d.get("ask") or {}).get("question") or {}).get("question", ""))
r = None
exec(sys.argv[1])
print(r)
PY
}
_b61() { # _b61 <python expression over d, the JSON of .temper/evidence/baseline.json, {} when absent>: prints it
  python3 -B - "$1" <<'PY'
import json, sys
try:
    d = json.load(open(".temper/evidence/baseline.json"))
except (OSError, ValueError):
    d = {}
d = d if isinstance(d, dict) else {}
num = lambda v: isinstance(v, (int, float)) and not isinstance(v, bool)
print(eval(sys.argv[1]))
PY
}
_clean61() { # the files of this file's projects taken out of the case folder
  rm -rf backend a b scripts go.mod ./*61.sh .claude/worktrees
}
_scripts61() { # the scripts the projects of this file run: each counts its runs in .git/count61 when it starts
  local c="$WORKDIR/.git/count61"
  printf 'echo run >> "%s"\necho ok\n' "$c" > pass61.sh
  printf 'echo run >> "%s"\necho "TOTAL 10 1 90%%"\n' "$c" > cov61.sh
  printf 'echo run >> "%s"\necho "FAIL: test_a"\nexit 1\n' "$c" > fail61.sh
  printf 'echo run >> "%s"\nsleep "${SLOW61:-3}"\n' "$c" > slow61.sh
  printf 'echo run >> "%s"\npwd -P > "%s/.git/where61"\n' "$c" "$WORKDIR" > where61.sh
}
_repo61() { # _repo61 [ignore-config]: the case folder as a git repository on main with one commit of every file but the
            # run's own (.temper/ is excluded); with ignore-config the config is excluded too, so a change of it leaves
            # the tree as it was
  rm -rf .git; git init -q . 2>/dev/null; git checkout -q -B main 2>/dev/null
  git config user.email t@example.com; git config user.name T
  printf '/.temper/\n' >> .git/info/exclude
  [[ "${1:-}" == ignore-config ]] && printf '/.claude/temper.config\n' >> .git/info/exclude
  git add -A >/dev/null 2>&1; git commit -q -m base
  : > .git/count61
}
_cmd61() { # _cmd61 <test command> [coverage command]: the config's check commands
  printf 'check:\n  commands:\n    test: "%s"\n' "$1" >> .claude/temper.config
  [[ -z "${2:-}" ]] || printf '    coverage: "%s"\n' "$2" >> .claude/temper.config
}
_suite61() { # _suite61 <test command> [coverage command]: a fresh run at Intent in a repository whose config names
             # those commands; no baseline file yet
  fresh; _clean61; _scripts61
  [[ $# -eq 0 ]] || _cmd61 "$@"
  _repo61; rm -f .temper/evidence/baseline.json
}
_runs61() { if [[ -f .git/count61 ]]; then grep -c . .git/count61 | tr -d ' '; else echo 0; fi; }
_start61() { TEMPER_BASELINE_FOREGROUND=1 "$TEMPER" baseline start "$@" >/dev/null 2>&1; }
_tools61() { # a fake java that prints version 21 and a fake mvn that counts its runs, in .git/bin61
  mkdir -p .git/bin61
  printf '#!/bin/sh\necho "openjdk version \\"21.0.2\\" 2024-01-16"\necho "openjdk version \\"21.0.2\\" 2024-01-16" >&2\n' \
    > .git/bin61/java
  printf '#!/bin/sh\necho run >> "%s"\necho "[INFO] BUILD SUCCESS"\n' "$WORKDIR/.git/count61" > .git/bin61/mvn
  chmod +x .git/bin61/java .git/bin61/mvn
}
_jdk61() { # _jdk61 [script]: backend/pom.xml asks for JDK 24; with script, scripts/ensure-jdk24.sh --export is there
  mkdir -p backend
  printf '<project><properties><maven.compiler.release>24</maven.compiler.release></properties></project>\n' > backend/pom.xml
  if [[ "${1:-}" == script ]]; then
    mkdir -p scripts
    printf '#!/usr/bin/env bash\n[[ "$1" == --export ]] && echo "export JAVA_HOME=/opt/jdk24"\n' > scripts/ensure-jdk24.sh
    chmod +x scripts/ensure-jdk24.sh
  fi
}
_known61() { # the baseline on record as not run (what the selftest helper _base_known of WP20 writes)
  mkdir -p .temper/evidence
  printf '{"result": "unknown", "why": "not run in the selftest"}\n' > .temper/evidence/baseline.json
}
_run61() { # _run61 <option id>: runs the calls of that option of the question next asks, as the person's answer
  local c
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    c="${c//\{reason\}/the base was red before this run}"
    TEMPER_BASELINE_FOREGROUND=1 bash -c "$c" >/dev/null 2>&1 || break
  done < <(_x61 "o = opt(d, '$1') or {}
r = '\n'.join(o.get('calls') or [])")
}
_settle61() { # runs the CLI's own baseline calls of next (an auto action whose calls are all baseline calls), 3 times
  local i c calls
  for i in 1 2 3; do
    calls="$(_x61 "c = d.get('calls') or []
r = '\n'.join(c) if d.get('action') == 'auto' and c and all(' baseline ' in ' %s ' % short(x) for x in c) else ''")"
    [[ -n "$calls" ]] || return 0
    while IFS= read -r c; do [[ -n "$c" ]] && TEMPER_BASELINE_FOREGROUND=1 bash -c "$c" >/dev/null 2>&1; done <<<"$calls"
  done
}
_row61() { # _row61 <stage> <row name>: pass of that row of the stage's verdict (state too when set), or absent
  python3 -B - "$1" "$2" <<'PY'
import json, sys
try:
    e = json.load(open(".temper/gates.json")).get(sys.argv[1]) or {}
except (OSError, ValueError):
    e = {}
r = next((x for x in e.get("requirements") or [] if x.get("name") == sys.argv[2]), None)
print("absent" if r is None else ("%s:%s" % (r.get("pass"), r.get("state")) if r.get("state") else str(r.get("pass"))))
PY
}
_base_rows61() { # the rows of .temper/overrides.json for base-suite, as by:count
  python3 -B - <<'PY'
import json
try:
    d = json.load(open(".temper/overrides.json"))
except (OSError, ValueError):
    d = []
rows = [x for x in d if isinstance(x, dict) and x.get("stage") == "base-suite"] if isinstance(d, list) else []
print("%s:%d" % (",".join(sorted({str(x.get("by")) for x in rows})) or "none", len(rows)))
PY
}

# --- w20 owner order: the configured command, the detected one, one folder down, the plan's Integration line, none ---
_owner61() { # _owner61 [spec folder]: source|test text|run text of `check_run.py owner`, its last line read as JSON
  python3 -B - "$(python3 -B "$REPO_ROOT/scripts/check_run.py" owner "$PWD" ${1:+"$1"} 2>/dev/null | tail -n 1)" <<'PY'
import json, sys
try:
    d = json.loads(sys.argv[1])
except ValueError:
    d = {}
d = d if isinstance(d, dict) else {}
print("%s|%s|%s" % (d.get("source"), d.get("test") or "", d.get("run") or ""))
PY
}
_why61() { python3 -B -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
except ValueError:
    d = {}
print('why' if isinstance(d, dict) and str(d.get('why') or '').strip() else 'no why')" \
  "$(python3 -B "$REPO_ROOT/scripts/check_run.py" owner "$PWD" 2>/dev/null | tail -n 1)"; }
fresh; _clean61
sed -i 's/^\*\*Integration:\*\* `true`$/**Integration:** `bash it61.sh`/' .temper/specs/demo/tasks.md
_cfg61="$(cat .claude/temper.config)"
printf 'module demo\n' > go.mod
_cmd61 "bash pass61.sh" "bash cov61.sh"
_o61="configured=$(_owner61 .temper/specs/demo)"
printf '%s\n' "$_cfg61" > .claude/temper.config
_o61+=" / root=$(_owner61 .temper/specs/demo | cut -d'|' -f1,2)"
rm -f go.mod; mkdir -p backend; printf '<project/>\n' > backend/pom.xml
_o61+=" / down=$(_owner61 .temper/specs/demo)"
rm -rf backend
_o61+=" / plan=$(_owner61 .temper/specs/demo)"
mkdir -p a b; printf '<project/>\n' > a/pom.xml; printf 'module b\n' > b/go.mod
_o61+=" / two=$(_owner61)|$(_why61)"
_clean61
assert_eq "w20 owner order: the configured command, the detected one, one folder down with cd in front, the plan's Integration line, none with a reason" \
  "configured=configured|bash pass61.sh|bash cov61.sh / root=detected|go test ./... / down=detected|cd backend && mvn -q verify|cd backend && mvn -q verify / plan=plan|bash it61.sh|bash it61.sh / two=none|||why" \
  "$_o61"

# --- w20 environment check: the file that states the need, what the shell has, a closed service; no suite, under 5 s
fresh; _clean61; _jdk61
printf 'setup:\n  services:\n    db61: 127.0.0.1:1\n' >> .claude/temper.config
_repo61; _tools61; rm -f .temper/evidence/baseline.json
_t0=$(date +%s%N)
PATH="$WORKDIR/.git/bin61:$PATH" _start61
_t1=$(date +%s%N)
assert_eq "w20 environment check: a JDK below the pom's and a closed service are two faults that name the file, the need and what the shell has; the call starts no suite and ends in under 5 s" \
  "red|kind|file|need|have|service|2 faults|runs=0|under 5 s" \
  "$(_b61 "'|'.join([str(d.get('result')), 'kind' if d.get('kind') in ('tool-version', 'service-down') else 'kind=%s' % d.get('kind'),
  'file' if 'backend/pom.xml' in json.dumps(d.get('env')) else 'no file', 'need' if '24' in json.dumps(d.get('env')) else 'no need',
  'have' if '21' in json.dumps(d.get('env')) else 'no have', 'service' if '127.0.0.1:1' in json.dumps(d.get('env')) else 'no service',
  '%d faults' % len(d.get('env') or [])])")|runs=$(_runs61)|$( (( _t1 - _t0 < 5000000000 )) && echo 'under 5 s' || echo "$(( (_t1 - _t0) / 1000000 )) ms")"
_clean61

# --- w20 three results: green with seconds and coverage, red with its fail lines, unknown with a reason ---
_suite61 "bash pass61.sh" "bash cov61.sh"; _start61
_r61="green=$(_b61 "'%s:%s:%s' % (d.get('result'), 'seconds' if num(d.get('seconds')) else 'no seconds', '%g' % d['coverage'] if num(d.get('coverage')) else d.get('coverage'))")"
_suite61 "bash fail61.sh"; _start61
_r61+="|red=$(_b61 "'%s:%s' % (d.get('result'), 'fail line' if 'FAIL: test_a' in (d.get('fail_lines') or []) else d.get('fail_lines'))")"
_suite61; rm -f .temper/specs/demo/tasks.md; _start61
_r61+="|no command=$(_b61 "'%s:%s' % (d.get('result'), 'why' if str(d.get('why') or '').strip() else 'no why')")"
_suite61 "bash pass61.sh"; rm -rf .git; git init -q . 2>/dev/null; _start61
_r61+="|no commit=$(_b61 "'%s:%s' % (d.get('result'), 'why' if str(d.get('why') or '').strip() else 'no why')")"
_suite61 "bash slow61.sh"; TEMPER_CHECK_TIMEOUT_S=1 _start61
_r61+="|over=$(_b61 "'%s:%s:%s' % (d.get('result'), 'why' if str(d.get('why') or '').strip() else 'no why', 'seconds_over' if num(d.get('seconds_over')) else 'no seconds_over')")"
"$TEMPER" baseline clean >/dev/null 2>&1 || true
assert_eq "w20 three results: a suite that exits 0 is green with seconds and coverage, one that exits 1 red with its fail lines; no command, no commit and a suite over its limit are unknown with a reason" \
  "green=green:seconds:90|red=red:fail line|no command=unknown:why|no commit=unknown:why|over=unknown:why:seconds_over" "$_r61"
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; _known61
printf '{"result": "unknown", "why": "no test command"}\n' > .temper/evidence/baseline.json
assert_eq "w20 three results: unknown is never read as green: the approval card's baseline line says unknown" "plan.approve|unknown|not passed" \
  "$(_x61 "s = sec(d, 'baseline') or {}
t = ' '.join(str(x.get('text', '')) for x in s.get('rows') or [])
r = '%s|%s|%s' % ((d.get('ask') or {}).get('id'), 'unknown' if 'unknown' in t else 'line: %s' % t, 'passed' if 'pass' in t.lower() else 'not passed')")"
_suite61 "bash slow61.sh"
_t0=$(date +%s%N)
SLOW61=4 env -u TEMPER_BASELINE_FOREGROUND "$TEMPER" baseline start >/dev/null 2>&1
_t1=$(date +%s%N)
_at61="$(_b61 "d.get('result')")|$( (( _t1 - _t0 < 3000000000 )) && echo fast || echo "$(( (_t1 - _t0) / 1000000 )) ms")"
for _i61 in $(seq 1 100); do [[ "$(_b61 "d.get('result')")" == running ]] || break; sleep 0.2; done
"$TEMPER" baseline clean >/dev/null 2>&1 || true
assert_eq "w20 three results: without the foreground switch the start returns in seconds with running, and the suite ends green in its own process" \
  "running|fast|green" "$_at61|$(_b61 "d.get('result')")"

# --- w20 where it runs: a detached worktree under .claude/worktrees/; HEAD, the branches and the status stay ---
_suite61 "bash where61.sh"
assert_eq "w20 where it runs: a run with no baseline file starts with the CLI's own call baseline start, and after it no second one" \
  "auto|baseline start|no agent|file|no second start" \
  "$(_x61 "c = [short(x) for x in d.get('calls') or []]
r = '%s|%s|%s' % (d.get('action'), 'baseline start' if 'baseline start' in c else 'calls: %s' % c, 'agent' if d.get('agents') else 'no agent')")|$(_start61
[[ -f .temper/evidence/baseline.json ]] && echo file || echo 'no file')|$(_x61 "r = 'second start' if 'baseline start' in [short(x) for x in d.get('calls') or []] else 'no second start'")"
_suite61 "bash where61.sh"; rm -f .git/where61
_head61="$(git rev-parse HEAD)|$(git branch --show-current)|$(git for-each-ref --format='%(refname)' refs/heads | tr '\n' ' ')"
_start61
_where61="$(cat .git/where61 2>/dev/null)"
"$TEMPER" baseline clean >/dev/null 2>&1 || true
assert_eq "w20 where it runs: the suite runs under .claude/worktrees/, HEAD did not move, no branch was made, and after baseline clean the worktree is gone and git status is empty" \
  "worktree|same head and branches|1 worktree|status empty" \
  "$([[ "$_where61" == "$WORKDIR/.claude/worktrees/"* ]] && echo worktree || echo "ran in '$_where61'")|$(
  [[ "$(git rev-parse HEAD)|$(git branch --show-current)|$(git for-each-ref --format='%(refname)' refs/heads | tr '\n' ' ')" == "$_head61" ]] && echo 'same head and branches' || echo moved)|$(
  git worktree list | grep -c . | tr -d ' ') worktree|$([[ -z "$(git status --porcelain)" ]] && echo 'status empty' || echo "status: $(git status --porcelain | head -3 | tr '\n' ' ')")"

# --- w20 start never fails: a missing program, no commit, a worktree that cannot be made ---
_suite61 "no-such-program-61 --all"; _start61
_n61="missing=$?:$([[ -f .temper/evidence/baseline.json ]] && echo file || echo 'no file')"
_suite61 "bash pass61.sh"; rm -rf .git; git init -q . 2>/dev/null; _start61
_n61+="|no commit=$?:$([[ -f .temper/evidence/baseline.json ]] && echo file || echo 'no file')"
_suite61 "bash pass61.sh"; rm -rf .claude/worktrees; : > .claude/worktrees; _start61
_n61+="|no worktree=$?:$([[ -f .temper/evidence/baseline.json ]] && echo file || echo 'no file')"
rm -f .claude/worktrees
assert_eq "w20 start never fails: baseline start exits 0 and leaves its file with a missing program, with no commit, and when the worktree cannot be made" \
  "missing=0:file|no commit=0:file|no worktree=0:file" "$_n61"

# --- w20 red base question: base.red before Plan, with the exact block and its add option, or the three options ---
_suite61 "bash fail61.sh"; _start61
assert_eq "w20 red base question: a red suite before Plan is the one question base.red with the command and its first fail line; its options are check-again, go-on-anyway and save; no agent" \
  "ask|base.red|command|fail line|check-again,go-on-anyway,save|baseline accept-red --reason '{reason}'|no agent" \
  "$(_x61 "a = d.get('ask') or {}; o = opt(d, 'go-on-anyway') or {}
r = '|'.join([str(d.get('action')), str(a.get('id')), 'command' if 'bash fail61.sh' in text(d) else 'no command',
    'fail line' if 'FAIL: test_a' in text(d) else 'no fail line', ','.join(sorted(str(x.get('id')) for x in opts(d))),
    ' '.join(short(c) for c in o.get('calls') or []) or 'none', 'agent' if d.get('agents') else 'no agent'])")"
fresh; _clean61; _jdk61 script; _repo61; _tools61; rm -f .temper/evidence/baseline.json
PATH="$WORKDIR/.git/bin61:$PATH" _start61
_blk61="$(PATH="$WORKDIR/.git/bin61:$PATH" "$TEMPER" doctor --propose 2>/dev/null | sed -n '/^setup:/,/^[^ ]/p' | grep -E '^(setup:|  )')"
_hash61="$(python3 -B -c "import hashlib, sys; print(hashlib.sha256(sys.argv[1].encode('utf-8')).hexdigest())" "$_blk61")"
assert_eq "w20 red base question: a JDK fault with a project file that names the JDK shows the exact proposed block; add-setup is first and recommended and carries the block's hash" \
  "ask|base.red|block|add-setup,True|doctor --propose --write --expect hash|baseline start --again|check-again,go-on-anyway,save|no agent" \
  "$(BLK61="$_blk61" HASH61="$_hash61" _x61 "import os; b, h = os.environ.get('BLK61', ''), os.environ.get('HASH61', '-')
a = d.get('ask') or {}; top = (a.get('options') or [{}])[0]; c = [short(x) for x in top.get('calls') or []]
r = '|'.join([str(d.get('action')), str(a.get('id')), 'block' if b and b in text(d) else 'no exact block',
    '%s,%s' % (top.get('id'), top.get('recommended') is True),
    c[0].replace(h, 'hash') if c else 'none', c[-1] if len(c) > 1 else 'none',
    ','.join(sorted(str(x.get('id')) for x in opts(d) if x.get('id') != 'add-setup')), 'agent' if d.get('agents') else 'no agent'])")"
_cfgsum61="$(cksum < .claude/temper.config)"
PATH="$WORKDIR/.git/bin61:$PATH" "$TEMPER" doctor --propose --write --expect 0000000000000000000000000000000000000000000000000000000000000000 >/dev/null 2>&1
_wrong61="$([[ "$(cksum < .claude/temper.config)" == "$_cfgsum61" ]] && echo nothing || echo written)"
PATH="$WORKDIR/.git/bin61:$PATH" _run61 add-setup
assert_eq "w20 red base question: the add call with another block's hash writes nothing; add-setup writes the block that was shown, byte for byte" \
  "wrong hash=nothing|add-setup=the block shown" \
  "wrong hash=$_wrong61|add-setup=$([[ -n "$_blk61" && "$(sed -n '/^setup:/,/^[^ ]/p' .claude/temper.config | grep -E '^(setup:|  )')" == "$_blk61" ]] && echo 'the block shown' || echo 'not the block')"
assert_eq "w20 red base question: a second red result asks again, without the add option" "base.red|no add-setup" \
  "$(PATH="$WORKDIR/.git/bin61:$PATH" _x61 "r = '%s|%s' % ((d.get('ask') or {}).get('id'), 'add-setup' if opt(d, 'add-setup') else 'no add-setup')")"
"$TEMPER" baseline clean >/dev/null 2>&1 || true; _clean61

# U13: the block add-setup proposes for a project's ignored .venv activates it in the baseline's worktree too, where
# the ignored folder is absent
fresh; _clean61; _scripts61; printf 'test "$VENV61" = 1 || { echo "FAIL: test_venv the venv is not active"; exit 1; }\n' > venv61.sh
_cmd61 "bash venv61.sh"; _repo61; mkdir -p .venv/bin; printf 'export VENV61=1\n' > .venv/bin/activate
printf '/.venv/\n' >> .git/info/exclude; rm -f .temper/evidence/baseline.json; _start61
_v61="first=$(_b61 "'%s:%s' % (d.get('result'), d.get('kind'))")|offer=$(_x61 "r = 'add-setup' if opt(d, 'add-setup') else 'no add-setup'")"
_run61 add-setup
assert_eq "w20 red base question: the block add-setup writes for a project's ignored .venv activates it in the baseline's worktree too (U13)" \
  "first=red:red-base|offer=add-setup|then=green" "$_v61|then=$(_b61 "'%s:%s' % (d.get('result'), str(d.get('tail'))[-160:]) if d.get('result') != 'green' else 'green'")"
"$TEMPER" baseline clean >/dev/null 2>&1 || true; rm -rf .venv venv61.sh

# --- w20 go on is a recorded skip: the base's fail lines are skipped in tests pass, a new fail line fails it ---
_suite61 "bash fail61.sh"; _start61
"$TEMPER" baseline accept-red --reason 'the base was red before this run' >/dev/null 2>&1 || true
_g61="override=$(_base_rows61)"
gpass intent plan build review; _at check
"$TEMPER" check run >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
_g61+="|old=$(_row61 check "tests pass")"
printf 'echo "FAIL: test_a"\necho "FAIL: test_b"\nexit 1\n' > fail61.sh
"$TEMPER" check run >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
_g61+="|new=$(_row61 check "tests pass")"
"$TEMPER" baseline clean >/dev/null 2>&1 || true
assert_eq "w20 go on is a recorded skip: accept-red adds a base-suite row by the person; the base's fail lines alone are skipped, one new fail line fails tests pass" \
  "override=the person:1|old=None:skipped|new=False" "$_g61"

# a base of more than eight fail lines keeps them all, and so does each run compared with it: its own failures are
# skipped at Check and match the base at a group's Validate; one new line fails both
_ten61() { # _ten61 [extra test name]: fail61.sh prints ten FAIL lines (and the extra one) and exits 1
  python3 -B -c 'import sys; sys.stdout.write("".join("echo \"FAIL: test_%s\"\n" % n for n in sys.argv[1:]) + "exit 1\n")' \
    alpha beta gamma delta eps zeta eta theta iota kappa ${1:-} > fail61.sh
}
_grp61() { # _grp61: the group's Validate (bash fail61.sh) as the gate runs it; prints whether its fail lines match the base
  local l
  python3 -B "$REPO_ROOT/scripts/task_ops.py" grouprun "$PWD" 60 "$PWD/.git/row61.json" G1 -- bash fail61.sh >/dev/null 2>&1
  l="$(python3 -B "$REPO_ROOT/scripts/task_ops.py" faillines "$PWD/.git/row61.json")"
  python3 -B "$REPO_ROOT/scripts/baseline.py" "$PWD" "" "" like-base "bash fail61.sh" "$l" >/dev/null 2>&1 && echo match || echo 'no match'
}
_suite61 "bash fail61.sh"; _ten61; git add -A >/dev/null 2>&1; git commit -q -m ten; _start61
"$TEMPER" baseline accept-red --reason 'the base was red before this run' >/dev/null 2>&1 || true
_t61="base=$(_b61 "len(d.get('fail_lines') or [])")"
gpass intent plan build review; _at check
"$TEMPER" check run >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
_t61+="|old=$(_row61 check "tests pass")|group=$(_grp61)"
_ten61 test_new_bug
"$TEMPER" check run >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
_t61+="|new=$(_row61 check "tests pass")|group=$(_grp61)"
"$TEMPER" baseline clean >/dev/null 2>&1 || true; rm -f .git/row61.json
assert_eq "w20 go on is a recorded skip: a base of ten fail lines keeps all ten; the same ten are skipped at Check and match the base at a group's Validate, an eleventh fails both" \
  "base=10|old=None:skipped|group=match|new=False|group=no match" "$_t61"

# --- w20 the answer is kept: the same base, setup block and tools ask nothing; a changed setup block asks again ---
fresh; _clean61; _scripts61; _cmd61 "bash fail61.sh"; _repo61 ignore-config; rm -f .temper/evidence/baseline.json
_start61; "$TEMPER" baseline accept-red --reason 'the base was red before this run' >/dev/null 2>&1 || true
_new61() { # a new run of the demo spec on the same project: the state cleared, then a run started and its baseline run
  "$TEMPER" state clear >/dev/null 2>&1; "$TEMPER" state init demo --feature "the demo thing" >/dev/null 2>&1
  rm -f .temper/evidence/baseline.json
  _k61="before=$(_base_rows61)"; _start61; _k61+="|after=$(_base_rows61)"
}
_new61
assert_eq "w20 the answer is kept: a second run on the same base, setup block and tool versions asks nothing and writes its own skip row" \
  "before=none:0|after=the person:1|asked=no|answer" \
  "$_k61|asked=$(_x61 "r = 'base.red' if (d.get('ask') or {}).get('id') == 'base.red' else 'no'")|$(_b61 "'answer' if d.get('answer') else 'no answer'")"
printf 'setup:\n  env:\n    X61: "1"\n' >> .claude/temper.config
_new61
assert_eq "w20 the answer is kept: a changed setup block asks again" "base.red" "$(_x61 "r = (d.get('ask') or {}).get('id')")"
"$TEMPER" baseline clean >/dev/null 2>&1 || true

# an answer given at a red suite is kept for that red suite only: an environment fault of a later run on the same key is
# asked, and going on from it (no suite ran on the base) skips no later failure of the suite
fresh; _clean61; _scripts61; _cmd61 "tool61 && bash fail61.sh"; _repo61; rm -f .temper/evidence/baseline.json
mkdir -p .git/bin61; printf '#!/bin/sh\nexit 0\n' > .git/bin61/tool61; chmod +x .git/bin61/tool61
PATH="$WORKDIR/.git/bin61:$PATH" _start61
_e61="first=$(_b61 "'%s:%s' % (d.get('result'), d.get('kind'))")"
"$TEMPER" baseline accept-red --reason 'the base was red before this run' >/dev/null 2>&1 || true
_new61; _e61+="|then=$(_b61 "'%s:%s:%s' % (d.get('result'), d.get('kind'), d.get('answer'))"):$(_x61 "r = (d.get('ask') or {}).get('id')")"
assert_eq "w20 the answer is kept: an answer given at a red suite is not kept for an environment fault of a later run on the same key, which asks again" \
  "first=red:red-base|then=red:program-missing:None:base.red" "$_e61"
"$TEMPER" baseline accept-red --reason 'the tool comes later' >/dev/null 2>&1 || true
printf '[{"claim": "full test suite", "cmd": "tool61 && bash fail61.sh", "exit_code": 1, "executed_by": "cli", "output": "FAIL: test_new_bug"}]\n' > .git/ledger61.json
assert_eq "w20 go on is a recorded skip: going on from a fault of the environment check, where no suite ran on the base, skips no failure of the suite" \
  "row=none" "row=$(_r61="$(python3 -B "$REPO_ROOT/scripts/baseline.py" "$PWD" .claude/temper.config "" skip-row "$PWD/.git/ledger61.json" 2>&1 | head -c 200)"; echo "${_r61:-none}")"
"$TEMPER" baseline clean >/dev/null 2>&1 || true; rm -f .git/ledger61.json; rm -rf .git/bin61
# every fail line of the ledger counts, the ninth too; a base where no test ran (exit 127 or 125) skips no failure
_sk61() { # _sk61 <kind> <exit> <the base's fail lines, | between> <the suite's output now, | between>: the state of the
          # skip row of a base the person went on from, or none
  python3 -B - "$@" <<'PY'
import json, sys
kind, rc, base, now = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
json.dump({"result": "red", "kind": kind, "exit_code": rc, "answer": "go-on-anyway", "cmd": "bash fail61.sh",
           "run": "bash fail61.sh", "fail_lines": [x for x in base.split("|") if x], "answered": {"reason": "known"}},
          open(".temper/evidence/baseline.json", "w"))
json.dump([{"stage": "base-suite", "reason": "the base was red before this run", "by": "the person"}],
          open(".temper/overrides.json", "w"))
json.dump([{"claim": "full test suite", "cmd": "bash fail61.sh", "exit_code": 1, "executed_by": "cli",
            "output": "\n".join(now.split("|"))}], open(".temper/evidence/ledger61.json", "w"))
PY
  local r; r="$(python3 -B "$REPO_ROOT/scripts/baseline.py" "$PWD" .claude/temper.config "" skip-row "$PWD/.temper/evidence/ledger61.json" 2>/dev/null)"
  python3 -B -c "import json, sys; print(json.loads(sys.argv[1]).get('state') if sys.argv[1].strip() else 'none')" "$r"
}
fresh; mkdir -p .temper/evidence
_eight61="FAIL: test_alpha|FAIL: test_beta|FAIL: test_gamma|FAIL: test_delta|FAIL: test_eps|FAIL: test_zeta|FAIL: test_eta|FAIL: test_theta"
_c61="eight=$(_sk61 red-base 1 "$_eight61" "$_eight61")"
_c61+="|a ninth=$(_sk61 red-base 1 "$_eight61" "$_eight61|FAILED test_b.py::test_new_bug")"
_c61+="|exit 127=$(_sk61 program-missing 127 "" "FAILED test_b.py::test_new_bug")"
_c61+="|exit 125=$(_sk61 setup-line 125 "" "FAILED test_b.py::test_new_bug")"
_c61+="|exit 1, no line=$(_sk61 red-base 1 "" "FAILED test_b.py::test_new_bug")"
assert_eq "w20 go on is a recorded skip: a new fail line after the eighth fails tests pass; a base whose suite could not start (exit 127, exit 125) skips no failure of the suite, a red base with no line that names a test skips them all" \
  "eight=skipped|a ninth=none|exit 127=none|exit 125=none|exit 1, no line=skipped" "$_c61"
rm -f .temper/evidence/ledger61.json .temper/overrides.json

# --- w20 limits: three times the measured seconds, never below the default; a time out doubles once, then asks ---
fresh; _clean61; mkdir -p .temper/evidence
_lim61() { python3 -B -c "
import sys
sys.path.insert(0, sys.argv[1])
import baseline
print(baseline.limit_for('make test', 600))" "$REPO_ROOT/scripts" 2>/dev/null || echo none; }
printf '{"result": "green", "cmd": "make test", "seconds": 400}\n' > .temper/evidence/baseline.json
_l61="400 s=$(_lim61)"
printf '{"result": "green", "cmd": "make test", "seconds": 10}\n' > .temper/evidence/baseline.json
_l61+="|10 s=$(_lim61)"
_known61; _l61+="|none=$(_lim61)"
printf '{"result": "unknown", "cmd": "make test", "seconds_over": 400}\n' > .temper/evidence/baseline.json
_l61+="|over=$(_lim61)"
assert_eq "w20 limits: limit_for gives three times the measured seconds, never below the default, and seconds_over counts as measured" \
  "400 s=1200|10 s=600|none=600|over=1200" "$_l61"
_gate61() { # _gate61: a run at Build whose group G1 has every task passed and the Validate command sleep 3
  f9_tasks | m_setup; f9_intent "true" "true"
  python3 -B - <<'PY'
import json
d = json.load(open('.temper/groups.json'))
for n in ('1', '2'):
    d.setdefault('tasks', {})[n] = {'status': 'passed', 'group': 'G1'}
json.dump(d, open('.temper/groups.json', 'w'))
for f in ('.temper/groups.json', '.temper/build-state.json'):
    d = json.load(open(f)); d.pop('plan_hash', None); json.dump(d, open(f, 'w'))
PY
  sed -i 's/^\*\*Validate:\*\* `true`$/**Validate:** `sleep 3`/' .temper/specs/demo/tasks.md
}
_gv61() { python3 -B -c "
import json
g = (json.load(open('.temper/groups.json')).get('groups') or {}).get('G1', {}).get('gate') or {}
print('%s|%s' % (g.get('verdict'), g.get('timeout_s')) if g.get('timeout_s') else g.get('verdict'))"; }
_gate61; mkdir -p .temper/evidence
printf '{"result": "green", "cmd": "sleep 3", "seconds": 2}\n' > .temper/evidence/baseline.json
TEMPER_TASK_TEST_TIMEOUT_S=1 "$TEMPER" group gate G1 >/dev/null 2>&1
_t61="measured=$(_gv61)"
_gate61; _known61
TEMPER_TASK_TEST_TIMEOUT_S=1 "$TEMPER" group gate G1 >/dev/null 2>&1
_t61+="|none=$(_gv61)"
_t61+="|then=$(_x61 "c = [short(x) for x in d.get('calls') or []]
r = '%s:%s' % (d.get('action'), next((x for x in c if x.startswith('group gate G1')), 'calls: %s' % c))")"
while IFS= read -r _c61; do
  [[ -n "$_c61" ]] && TEMPER_TASK_TEST_TIMEOUT_S=1 bash -c "$_c61" >/dev/null 2>&1
done < <(_x61 "r = '\n'.join(d.get('calls') or []) if d.get('action') == 'auto' else ''")
_t61+="|again=$(_gv61)|then=$(_x61 "r = '%s:%s' % (d.get('action'), (d.get('ask') or {}).get('id'))")"
assert_eq "w20 limits: the group gate's limit follows the base; after one time out the CLI's own call runs it with twice the limit, and after a second the run asks" \
  "measured=PASS|none=FAIL|1|then=auto:group gate G1 --timeout-s 2|again=FAIL|2|then=ask:group.fail" "$_t61"
_lim_kept61() { _b61 "(d.get('limits') or {}).get('bash slow61.sh')"; }   # the limit kept for the slow script
fresh; _clean61; _scripts61; _cmd61 "bash slow61.sh"; _repo61; gpass intent plan build review; _at check
TEMPER_CHECK_TIMEOUT_S=1 "$TEMPER" check run >/dev/null 2>&1
_o61="check=$(_lim_kept61)"
TEMPER_CHECK_TIMEOUT_S=1 "$TEMPER" check run >/dev/null 2>&1
_o61+="|runs=$(wc -l < .git/count61 | tr -d ' ')"
_known61; python3 -B "$REPO_ROOT/scripts/task_ops.py" testrun . 1 "$WORKDIR/.git/row61" 1 G1 1 green -- bash slow61.sh \
  >/dev/null 2>&1 </dev/null
_o61+="|task=$(_lim_kept61)"
assert_eq "w20 limits: a time out of Check's suite or of a task test keeps twice its limit, and the next Check runs it again" \
  "check=2|runs=2|task=2" "$_o61"
fresh; _clean61; _scripts61; _cmd61 "true"; _repo61; gpass intent plan build review; _at check
mkdir -p .temper/specs/demo/acceptance; printf 'sleep 2\necho ok\n' > .temper/specs/demo/acceptance/test_acc61.sh
"$TEMPER" acceptance lock --cmd "bash .temper/specs/demo/acceptance/test_acc61.sh" >/dev/null 2>&1
printf '{"result": "unknown", "limits": {"bash .temper/specs/demo/acceptance/test_acc61.sh": 30}}\n' > .temper/evidence/baseline.json
TEMPER_CHECK_TIMEOUT_S=1 "$TEMPER" check run >/dev/null 2>&1
assert_eq "w20 limits: Check's run of the locked acceptance tests takes its limit from the baseline (limit_for)" "0" \
  "$(python3 -B -c "
import json
r = [x for x in json.load(open('.temper/evidence/check.json')) if str(x.get('claim', '')).startswith('acceptance (written')]
print(r[-1].get('exit_code') if r else 'no acceptance row')" 2>&1)"

# --- w20 fix run and door: a red base of kind red-base in a fix run is recorded, a failing setup line asks (WP28: the
#     door cases went with the doors) ---
_fix61() { # _fix61 [config lines]: a fix run at its root cause, on a project whose suite fails on the base
  fresh; _clean61; _scripts61; _cmd61 "bash fail61.sh"
  [[ -z "${1:-}" ]] || printf '%s\n' "$1" >> .claude/temper.config
  _repo61
  rm -f .temper/groups.json .temper/view.json .temper/build-state.json
  "$TEMPER" state init bug --command fix --feature "the totals drop a cent" >/dev/null 2>&1
  rm -f .temper/evidence/baseline.json; _start61; _settle61
}
_fix61
_f61="red-base=$(_b61 "'%s:%s:%s' % (d.get('result'), d.get('kind'), d.get('answer'))"):$(_x61 "r = 'asked' if (d.get('ask') or {}).get('id') == 'base.red' else 'not asked'")"
_fix61 "setup:
  run: exit 3"
_f61+="|setup line=$(_b61 "'%s:%s' % (d.get('result'), d.get('kind'))"):$(_x61 "r = 'asked' if (d.get('ask') or {}).get('id') == 'base.red' else 'not asked'")"
"$TEMPER" baseline clean >/dev/null 2>&1 || true
assert_eq "w20 fix run and door: a fix run records a red base of kind red-base with the answer fix-run and asks nothing; a failing setup line asks" \
  "red-base=red:red-base:fix-run:not asked|setup line=red:setup-line:asked" "$_f61"
_clean61; rm -f .git/count61 .git/where61; rm -rf .git/bin61
