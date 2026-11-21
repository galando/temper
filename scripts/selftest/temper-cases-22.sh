# Release 9.8.5 case file 22: sourced by test-temper.sh after temper-cases-21.sh; its helpers (nx, vw, fresh, gpass, gfail, labels, m_setup) are used here.

# --- WP21: the per command check of the plan gate is gone, with its four classes, its text patterns, its store and its
#     two config keys. A Validate and the Integration line run once on the base, by `temper baseline plan` after the
#     planner returned (case file 62 holds which commands run, where, under which limit, and the binary rule). Here: the
#     base is as it was after the run, a result is kept, a skip with a reason is a recorded override, and a repository
#     with no commit runs nothing. Every call of `baseline` runs in the foreground (TEMPER_BASELINE_FOREGROUND=1) ---
_w22repo() { # the case folder as a git repository on main with one commit of every file but the run's own
  rm -rf .git src; git init -q . 2>/dev/null; git checkout -q -B main 2>/dev/null
  git config user.email t@example.com; git config user.name T
  printf '/.temper/\n' >> .git/info/exclude
  mkdir -p src; echo 'echo demo' > src/demo.sh
  git add -A >/dev/null 2>&1; git commit -q -m base
}
_w22plan() { # _w22plan <Validate>: the demo plan with that Validate, and a counter program in $W22 (inside .git): `$W22/c X`
             # appends X to $W22/log and exits 0, `$W22/f X` appends X and exits 1
  W22="$WORKDIR/.git/w22"; mkdir -p "$W22"; : > "$W22/log"
  printf '#!/bin/sh\necho "$1" >> "%s/log"\n' "$W22" > "$W22/c"
  printf '#!/bin/sh\necho "$1" >> "%s/log"\necho "FAIL: test_k expected 1"\nexit 1\n' "$W22" > "$W22/f"
  chmod +x "$W22/c" "$W22/f"
  sed -i "s|^\*\*Validate:\*\* \`true\`\$|**Validate:** \`$1\`|" .temper/specs/demo/tasks.md
  mkdir -p .temper/evidence
  printf '{"result": "unknown", "why": "not run in the selftest"}\n' > .temper/evidence/baseline.json
}
_w22n() { if [[ -f "$W22/log" ]]; then grep -cx -- "$1" "$W22/log" | tr -d ' '; else echo 0; fi; }
_w22bp() { TEMPER_BASELINE_FOREGROUND=1 "$TEMPER" baseline plan >/dev/null 2>&1; }
_w22ask() { nx "(d.get('ask') or {}).get('id')"; }
_w22rows() { python3 -B -c "
import json
try:
    d = json.load(open('.temper/overrides.json'))
except (OSError, ValueError):
    d = []
print(sum(1 for x in d if isinstance(x, dict) and x.get('stage') == 'plan-command') if isinstance(d, list) else 0)"; }

fresh; _w22repo; _w22plan "$WORKDIR/.git/w22/c V"
_w22before="$(git status --porcelain | sort | cksum)"
_w22bp; _w22first="$(_w22n V)"; _w22bp
assert_eq "9.8.5 plan commands (WP21): after baseline plan the worktree is gone and the tree is as it was; a second call runs nothing" \
  "ran=1|again=1|worktrees=1|tree=same" \
  "ran=$_w22first|again=$(_w22n V)|worktrees=$(git worktree list | grep -c . | tr -d ' ')|tree=$([[ "$(git status --porcelain | sort | cksum)" == "$_w22before" ]] && echo same || echo "changed: $(git status --porcelain | head -3 | tr '\n' ' ')")"

fresh; _w22repo; _w22plan "$WORKDIR/.git/w22/f K"
gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; _w22bp
_w22asked="$(_w22ask)"
"$TEMPER" baseline skip --cmd "$WORKDIR/.git/w22/f K" >/dev/null 2>&1; _w22rc=$?
assert_eq "9.8.5 plan commands (WP21): a skip with no reason is refused and writes no override row" "asked=plan.command|refused|rows=0" \
  "asked=$_w22asked|$([[ $_w22rc -ne 0 ]] && echo refused || echo 'exit 0')|rows=$(_w22rows)"
"$TEMPER" baseline skip --cmd "$WORKDIR/.git/w22/f K" --reason 'the check needs the staging data' >/dev/null 2>&1 || true
_w22bp
assert_eq "9.8.5 plan commands (WP21): a skip with a reason is one override row named plan-command; the command is not asked about or run again" \
  "rows=1|asked=plan.approve|runs=1" "rows=$(_w22rows)|asked=$(_w22ask)|runs=$(_w22n K)"

fresh; rm -rf .git src; git init -q . 2>/dev/null; _w22plan "$WORKDIR/.git/w22/c V"
_w22before="$(git status --porcelain | sort | cksum)"
TEMPER_BASELINE_FOREGROUND=1 "$TEMPER" baseline plan >/dev/null 2>&1; _w22rc=$?
assert_eq "9.8.5 plan commands (WP21): with no commit to run on, baseline plan exits 0, runs nothing and leaves the tree as it was" \
  "exit=0|ran=0|tree=same" \
  "exit=$_w22rc|ran=$(_w22n V)|tree=$([[ "$(git status --porcelain | sort | cksum)" == "$_w22before" ]] && echo same || echo changed)"
rm -rf .git src
