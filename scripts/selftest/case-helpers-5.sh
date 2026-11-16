# case-helpers-5.sh: the helper functions and constants of temper-cases-5.sh, so temper-cases-6.sh runs on its own
# (9.8.5). Made by make-helpers-5.sh; do not edit by hand. temper-cases-6.sh sources it when the helpers are not defined.
gp_base() { # write the valid two-group fixture to the demo spec's tasks.md (a plan not built yet, so no groups.json)
  rm -f .temper/groups.json
  cat > .temper/specs/demo/tasks.md <<'GP'
# Tasks: demo

**Integration:** `bash run-all.sh`

## Group G1: Core
**Depends:** none
**Validate:** `bash unit/g1.sh`
**Interfaces:** `src/a.sh` — `a_main`
**Context:**
Shared notes for G1. Use bash.

### Task 1: Alpha
**File:** `src/a.sh`, `unit/a_test.sh`
**Depends:** none
**Test:** `bash unit/a_test.sh`
**Cases:**
- the normal input gives the expected result
- an empty input is refused
- [ ] done

### Task 2: Beta
**File:** `src/b.sh`
**Depends:** Task 1
**Test:** `bash unit/b_test.sh`
**Cases:**
- the normal input gives the expected result
- an empty input is refused
- [ ] done

## Group G2: Edge
**Depends:** none
**Validate:** `bash unit/g2.sh`
**Context:**
Notes for G2.

### Task 3: Gamma
**File:** `src/c.sh`
**Depends:** none
**Test:** `bash unit/c_test.sh`
**Cases:**
- the normal input gives the expected result
- an empty input is refused
- [ ] done
GP
}
gp_mut() { # gp_mut <old> <new>: a fixture edit; a recorded plan digest (H3) is dropped, as if re-approved
  gp_tamper "$1" "$2" || return 1
  local f
  for f in .temper/groups.json .temper/build-state.json; do
    [[ -f "$f" ]] && python3 -c "
import json, sys
d = json.load(open(sys.argv[1])); d.pop('plan_hash', None)
json.dump(d, open(sys.argv[1], 'w'))" "$f"
  done
  return 0
}
gp_tamper() { # gp_tamper <old> <new>: replace the first occurrence in the demo tasks.md, keeping groups.json as is
  python3 - "$1" "$2" <<'PY'
import sys
p = '.temper/specs/demo/tasks.md'
s = open(p).read()
assert sys.argv[1] in s, 'fixture text not found: ' + sys.argv[1]
open(p, 'w').write(s.replace(sys.argv[1], sys.argv[2], 1))
PY
}
gp_setup() { setup; printf 'build:\n  mode: grouped\n' >> .claude/temper.config; gp_base; mkdir -p unit; : > unit/b_test.sh; : > unit/c_test.sh; }
gp_gate() { "$TEMPER" gate plan 2>&1; }
gp_has() { gp_gate | grep -c -- "$1" | tr -d ' '; }
sg_setup() { setup; printf 'build:\n  mode: grouped\n' >> .claude/temper.config; gp_base; }
sg_groups() { # sg_groups <json>: write .temper/groups.json the way a started run would hold it
  printf '%s\n' "$1" > .temper/groups.json
}
SG_RUN='"G1":{"status":"running","worktree":".claude/worktrees/temper-demo-G1","branch":"temper/demo/G1"},"G2":{"status":"running","worktree":".claude/worktrees/temper-demo-G2","branch":"temper/demo/G2"}'
sg_state() { # sg_state <tasks-json> [groups-json]: both groups started, plus per-task state
  sg_groups "{\"version\":1,\"slug\":\"demo\",\"groups\":{${2:-$SG_RUN}},\"tasks\":$1}"
}
sg_ready() { # the ready task numbers, comma separated, in the order printed
  "$TEMPER" schedule 2>/dev/null | python3 -c "
import json, sys
print(','.join(str(json.loads(l)['task']) for l in sys.stdin if l.strip().startswith('{') and 'task' in json.loads(l)))"
}
sg_last() { "$TEMPER" schedule 2>/dev/null | tail -1; }
sg_amodel() { # sg_amodel <task-model>: agent_model of the first ready line under that task-model
  sg_setup; printf '  grouped:\n    task-model: %s\n' "$1" >> .claude/temper.config; sg_state '{}'
  "$TEMPER" schedule | head -1 | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['agent_model'])"
}
sw_setup() { # sg_setup + a fresh repository with one commit, on the run's feature branch
  sg_setup
  rm -rf .git README; git init -q . 2>/dev/null
  git config user.email t@example.com; git config user.name T
  echo base > README; git add README; git commit -q -m base
  git checkout -q -B feature/demo
}
sw_head() { git rev-parse HEAD; }
sw_field() { # sw_field <G> <field>
  python3 -c "import json,sys; print(json.load(open('.temper/groups.json'))['groups'][sys.argv[1]].get(sys.argv[2],''))" "$1" "$2"
}
ST_WT=".claude/worktrees/temper-demo-G1"
T1W=".claude/worktrees/temper-demo-T1"   # one worktree per task: Task N works in temper-demo-T<N>
st_setup() { # sw_setup + the upstream gates ADR 0009 asks for + both groups started
  sw_setup
  printf '{"plan":{"verdict":"PASS"},"intent":{"verdict":"PASS"}}\n' > .temper/gates.json
  # the declared Test: commands are controllable from outside the worktree: ST_EXIT is the exit, ST_SLEEP
  # hangs, ST_LONG prints a long output, ST_ENV prints the names of the variables the command was given
  local t="bash -c 'echo boom; pwd; [ -z \"\$ST_ENV\" ] || env | cut -d= -f1; [ -z \"\$ST_LONG\" ] || for i in \$(seq 1 400); do echo \"line \$i of a long failing output\"; done; [ -z \"\$ST_SLEEP\" ] || sleep \$ST_SLEEP; exit \${ST_EXIT:-0}'"
  gp_mut '`bash unit/a_test.sh`' "\`$t\`"; gp_mut '`bash unit/b_test.sh`' "\`$t\`"; gp_mut '`bash unit/c_test.sh`' "\`$t\`"
  [[ -z "${ST_PRE:-}" ]] || eval "$ST_PRE"   # a case may edit the plan before the first group start
  "$TEMPER" group start G1 >/dev/null 2>&1; "$TEMPER" group start G2 >/dev/null 2>&1
}
st_field() { # st_field <task> <field>
  python3 -c "import json,sys; print(json.load(open('.temper/groups.json'))['tasks'][sys.argv[1]].get(sys.argv[2],''))" "$1" "$2"
}
st_rows() { # st_rows <task>: the ledger rows of one task as phase:exit,phase:exit
  python3 -c "
import json,sys
rows=json.load(open('.temper/evidence/build.json'))
print(','.join('%s:%s' % (r['phase'], r['exit_code']) for r in rows if r.get('task')==int(sys.argv[1])))" "$1" 2>/dev/null
}
st_twt() { # st_twt [path]: the worktree a task agent writes in: the running task that declares the path, else the most
          # recently started running task, each in its own worktree; with none running, G1's worktree
  python3 - "${1:-}" "$ST_WT" <<'PY'
import json, re, sys
path, fallback = sys.argv[1], sys.argv[2]
try:
    d = json.load(open('.temper/groups.json'))
except Exception:
    d = {}
files, n = {}, None
try:
    for l in open('.temper/specs/demo/tasks.md'):
        m = re.match(r'^###\s+Task\s+(\d+)\s*:', l)
        if m: n = int(m.group(1))
        elif n is not None and l.startswith('**File:**'):
            files[n] = re.findall(r'`([^`]+)`', l)
except Exception:
    pass
import os
def made(w):  # started_at has one-second resolution; two tasks started in the same second are told apart by when
    try:      # their worktree was made (its .git file is written once, by git worktree add)
        return os.stat(os.path.join(w, '.git')).st_mtime_ns
    except OSError:
        return 0
run = sorted(((v.get('started_at') or '', made(v.get('worktree')), int(k), v.get('worktree')) for k, v in (d.get('tasks') or {}).items()
              if v.get('status') == 'running' and v.get('worktree')), reverse=True)
own = [w for _, _, k, w in run if path and path in files.get(k, [])]
print(own[0] if own else (run[0][3] if run else fallback))
PY
}
st_edit() { # st_edit <task-file-relative-path>: write a file into the running task's worktree (st_twt)
  # Only ever inside the selftest's throwaway folder: a case that left the folder would
  # otherwise write into the repository it runs from.
  local here top; here="$(pwd -P)"; top="$(cd "$WORKDIR" && pwd -P)"
  [[ "$here" == "$top" || "${here#"$top"/}" != "$here" ]] || { echo "st_edit refused: cwd $(pwd) is outside WORKDIR" >&2; return 1; }
  local w; w="$(st_twt "$1")"
  mkdir -p "$w/$(dirname "$1")"; echo "work $1" > "$w/$1"
}
st_unticked() { # the number of unticked boxes in the demo tasks.md
  grep -c '^- \[ \]' .temper/specs/demo/tasks.md
}
st_fail() { # st_fail <red-exit|none> <green-exit|none> [more ledger shape]: start 1, record, gate; prints the output
  "$TEMPER" task start 1 >/dev/null 2>&1
  [[ "$1" != "none" ]] && ST_EXIT=$1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1
  st_edit src/a.sh
  [[ "$2" != "none" ]] && ST_EXIT=$2 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
  "$TEMPER" task gate 1 --model m 2>&1
}
st_pass_ready() { "$TEMPER" task start 1 >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1; st_edit src/a.sh; ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1; }
st_nextcount() { printf '%s\n' "$1" | grep -c '^NEXT:'; }
st_attempt() { # st_attempt <model> <ms>: start Task 1, write a declared file and a stray one, no RED: a FAIL
  "$TEMPER" task start 1 >/dev/null 2>&1
  st_edit src/a.sh; st_edit stray.txt
  "$TEMPER" task gate 1 --model "$1" --ms "$2" 2>&1
}
gg_setup() { # st_setup + a controllable G1 Validate command (GV_EXIT is its exit)
  st_setup
  gp_mut '`bash unit/g1.sh`' "\`bash -c 'echo validating; pwd; exit \${GV_EXIT:-0}'\`"
}
gg_pass() { # gg_pass <task> <file>: drive one task through RED, an edit, GREEN and its gate
  "$TEMPER" task start "$1" >/dev/null 2>&1
  ST_EXIT=1 "$TEMPER" task test "$1" --phase red >/dev/null 2>&1
  st_edit "$2"
  ST_EXIT=0 "$TEMPER" task test "$1" --phase green >/dev/null 2>&1
  "$TEMPER" task gate "$1" --model claude-haiku-5-5 --ms 5 >/dev/null 2>&1
}
gg_g() { # gg_g <group> <field>
  python3 -c "
import json,sys
v=json.load(open('.temper/groups.json'))['groups'][sys.argv[1]]
for k in sys.argv[2].split('.'):
    v=(v or {}).get(k,'') if isinstance(v,dict) else ''
print(v)" "$1" "$2"
}
gg_ready_g1() { "$TEMPER" schedule | python3 -c "
import json,sys
print(','.join('%d@%d' % (r['task'], r['attempt']) for r in (json.loads(l) for l in sys.stdin if l.startswith('{')) if r.get('group')=='G1'))"
}
gi_setup() { # both groups started, G1/G2 Validate and the Integration suite controllable (GI_EXIT)
  rm -rf src unit shared.txt   # files an earlier case merged into the shared throwaway folder
  gg_setup
  gp_mut '`bash unit/g2.sh`' '`true`'
  gp_mut '`bash run-all.sh`' "\`bash -c 'echo integrating; pwd; ls src; exit \${GI_EXIT:-0}'\`"
  "$TEMPER" group start G2 >/dev/null 2>&1
}
gi_pass() { # gi_pass <task> <group> <file> <content>: RED, edit in the task's own worktree, GREEN, task gate
  local wt=".claude/worktrees/temper-demo-T$1"
  "$TEMPER" task start "$1" >/dev/null 2>&1
  ST_EXIT=1 "$TEMPER" task test "$1" --phase red >/dev/null 2>&1
  mkdir -p "$wt/$(dirname "$3")"; printf '%s\n' "$4" > "$wt/$3"
  ST_EXIT=0 "$TEMPER" task test "$1" --phase green >/dev/null 2>&1
  "$TEMPER" task gate "$1" --model claude-haiku-5-5 --ms 5 >/dev/null 2>&1
}
gi_all() { # every task passed and both group gates PASS
  gi_setup
  gi_pass 1 G1 src/a.sh 'a_main() { :; }'; gi_pass 2 G1 src/b.sh 'b_main() { :; }'
  gi_pass 3 G2 src/c.sh 'c_main() { :; }'
  "$TEMPER" group gate G1 >/dev/null 2>&1; "$TEMPER" group gate G2 >/dev/null 2>&1
}
gi_int() { python3 -c "
import json,sys
v=json.load(open('.temper/groups.json')).get('integration') or {}
for k in sys.argv[1].split('.'):
    v=v.get(k,'') if isinstance(v,dict) else ''
print(v if not isinstance(v,list) else ','.join(v))" "$1"
}
gi_gate_row() { "$TEMPER" gate build 2>&1 | grep -c "integration"; }
nums() { printf '%s\n' "$1" | grep -x '[0-9][0-9]*' | sed -n '1p;$p' | paste -sd'-' -; printf '%s\n' "$1" | grep -cx '[0-9][0-9]*'; }
gc_setup() { # gc_setup <grouped|fix>: autonomous run, max-blast-radius 3, four declared files changed
  gp_setup
  [[ "$1" != "fix" ]] || rm -f .temper/specs/demo/tasks.md   # a /temper:fix run has no tasks.md
  sed 's/max-blast-radius: 15/max-blast-radius: 3/' .claude/temper.config > .claude/temper.config.new && mv .claude/temper.config.new .claude/temper.config
  "$TEMPER" state set run_mode autonomous >/dev/null 2>&1
  # setup keeps the work tree, so the four files an earlier gc_setup left would be committed into this
  # base with the same content and stop counting as changes. Clear them first so every call starts from
  # the same tree.
  rm -rf src unit
  git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -q -m base >/dev/null 2>&1
  mkdir -p src unit
  for f in src/a.sh unit/a_test.sh src/b.sh src/c.sh; do echo "x" > "$f"; done
}
gc_row() { "$TEMPER" gate commit 2>&1 | grep 'blast radius'; }
gr_json() { "$TEMPER" group report --json 2>/dev/null | python3 -c "
import json,sys
v=json.load(sys.stdin)
for k in sys.argv[1].split('.'):
    v=v.get(k,'') if isinstance(v,dict) else ''
print(json.dumps(v,sort_keys=True) if isinstance(v,(dict,list)) else v)" "$1"
}
us_json() { "$TEMPER" report --json 2>/dev/null | python3 -c "
import json,sys
v=json.load(sys.stdin)
for k in sys.argv[1].split('.'):
    v=v.get(k,'') if isinstance(v,dict) else ''
print(json.dumps(v,sort_keys=True) if isinstance(v,(dict,list)) else v)" "$1"
}
TB="$REPO_ROOT/agents/build-task.md"
TPL="$REPO_ROOT/templates/tasks.md"
OT="$REPO_ROOT/commands/temper.md"
OF="$REPO_ROOT/commands/fix.md"
case_hook() { # case_hook <shell line>: a native pre-commit hook that runs the line, for every commit of this case's
  # repository and its worktrees. It sits in a folder of the case's own in the git folder, which core.hooksPath names by
  # its absolute path (as Temper's installer does), never in git's default hook folder; sw_setup removes it with .git.
  local hd; hd="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)/case-gate"; mkdir -p "$hd"
  printf '#!/bin/sh\n%s\nexit 0\n' "$1" > "$hd/pre-commit"; chmod +x "$hd/pre-commit"
  git config core.hooksPath "$hd"
}
h5_hook() { case_hook 'mkdir -p .temper && echo "{}" > .temper/gates.json'; }
slow_hook() { case_hook "sleep $1"; }
lock_owner() { cat .temper/.lock/owner 2>/dev/null || echo none; }
f_add_t4() { # a fourth, independent G1 task (src/d.sh) with its own controllable test
  gp_mut '### Task 2: Beta' '### Task 4: Delta
**File:** `src/d.sh`
**Depends:** none
**Test:** `bash -c '"'"'exit ${ST_EXIT:-0}'"'"'`
**Cases:**
- the normal input gives the expected result
- an empty input is refused
- [ ] done

### Task 2: Beta'
}
f_setup() { ST_PRE=f_add_t4 st_setup; ST_PRE=""; gp_mut '**Depends:** Task 1' '**Depends:** none'; }
f_tree() { git -C "$ST_WT" ls-tree -r --name-only HEAD | paste -sd, -; }
