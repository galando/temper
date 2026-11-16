#!/usr/bin/env bash
# make-saved-old.sh: the runs and the configs an older Temper left in a project, saved as text for the migration
# cases of row D60 to D64 of docs/plans/one-go/done.md (scripts/selftest/temper-cases-46.sh).
#
#   bash scripts/selftest/make-saved-old.sh > scripts/selftest/saved-old.json
#
# Users have 9.8.4 (7c7a1c1); the base of the build (10e965a) was never released. For each of the two commits the
# script makes a detached work tree (git worktree add --detach), removes it after, and in it drives the scripted run of
# that tree's own scripts/selftest/make-view-fixtures.sh (its intent, plan, tasks, findings and helpers, with that
# tree's CLI) to five points:
#   plan          the plan question (the plan gate passed, the run at Plan)
#   build-group   Build with a group running
#   armed-build   an armed run in Build (run_mode autonomous, set as that version set it)
#   review-finding Review with an open critical finding
#   parked        a parked run (an armed run whose Build failed, parked with that version's park call)
# At each point it writes every file of .temper (the spec folder is inside it) and the project's config as text. Under
# the same key it stores the tree's templates/temper.config.default and the commit hook the tree's installer writes
# (scripts/guards/install.sh run in a throwaway repository). In the saved text the project folder is @PROJECT@ and the
# plugin folder is @PLUGIN@ and the project's one commit is @HEAD@; a case fills them in (the project is a git
# repository whose one commit adds README.md with the text x, on the branch the state names). The view is kept
# compact. No case runs this script: its output is committed.
set -euo pipefail
exec </dev/null
unset CDPATH
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${HERE%/scripts/selftest}"
[[ "$ROOT" != "$HERE" && -x "$ROOT/scripts/temper" ]] || { echo "FAIL: cannot find the plugin folder from $HERE" >&2; exit 1; }
WORK="$(mktemp -d)"
WORK="$(cd -P "$WORK" && pwd)"
TREES=()
cleanup() {
  local t
  for t in "${TREES[@]}"; do git -C "$ROOT" worktree remove --force "$t" >/dev/null 2>&1 || true; done
  git -C "$ROOT" worktree prune >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT
export TEMPER_SELFTEST_ROOT="$WORK" HOME="$WORK/home"
mkdir -p "$HOME"

for C in 7c7a1c1 10e965a; do
  TREE="$WORK/tree-$C"
  git -C "$ROOT" worktree add --detach -q "$TREE" "$C" >/dev/null 2>&1
  TREES+=("$TREE")
  TREE="$(cd -P "$TREE" && pwd)"
  mkdir -p "$WORK/projects-$C"
  python3 -I - "$TREE" "$WORK/projects-$C" "$C" > "$WORK/saved-$C.json" <<'PY'
import json, os, re, subprocess, sys

tree, work, commit = sys.argv[1], sys.argv[2], sys.argv[3]
# The scripted run of the tree's own make-view-fixtures.sh: its Python part up to the first run, which defines the
# texts (INTENT, PLAN, TASKS, FINDINGS) and the helpers (project, cli, write, verdict) on that tree's CLI.
src = open(os.path.join(tree, "scripts", "selftest", "make-view-fixtures.sh"), encoding="utf-8").read()
body = src.split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
head = body.split("# A /temper run from Intent to the commit.", 1)[0]
ns = {"__name__": "fixtures"}
sys.argv = ["make-view-fixtures", tree, work]
exec(compile(head, "make-view-fixtures.sh", "exec"), ns)
project, cli, write, verdict = ns["project"], ns["cli"], ns["write"], ns["verdict"]
INTENT, PLAN, TASKS, FINDINGS = ns["INTENT"], ns["PLAN"], ns["TASKS"], ns["FINDINGS"]
FEATURE = "Password reset by email"


def git(cwd, *args):
    return subprocess.run(["git"] + list(args), cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          text=True).stdout.strip()


def mark(text, cwd):
    out = text.replace(cwd, "@PROJECT@").replace(tree, "@PLUGIN@")
    head = git(cwd, "rev-parse", "HEAD")
    return out.replace(head, "@HEAD@") if head else out


def save(cwd):
    cli(cwd, "next", "--json")   # the view as the CLI leaves it at this point
    files = {}
    base = os.path.join(cwd, ".temper")
    for d, subs, names in os.walk(base):
        subs[:] = sorted(s for s in subs if s != ".lock")
        for n in sorted(names):
            p = os.path.join(d, n)
            rel = os.path.relpath(p, cwd)
            with open(p, encoding="utf-8", errors="replace") as f:
                text = f.read()
            if rel == os.path.join(".temper", "view.json"):   # the CLI writes it again at once: kept compact
                text = json.dumps(json.loads(text), sort_keys=True, separators=(",", ":")) + "\n"
            files[rel] = mark(text, cwd)
    cfg = os.path.join(cwd, ".claude", "temper.config")
    if os.path.isfile(cfg):
        files[".claude/temper.config"] = mark(open(cfg, encoding="utf-8").read(), cwd)
    return {"branch": git(cwd, "rev-parse", "--abbrev-ref", "HEAD"), "files": files}


def to_plan(cwd):
    cli(cwd, "state", "init", "pw", "--feature", FEATURE)
    write(cwd, ".temper/specs/pw/intent.md", INTENT)
    verdict(cwd, "intent", True)
    cli(cwd, "state", "advance", "intent_complete", "plan")
    write(cwd, ".temper/specs/pw/plan.md", PLAN)
    write(cwd, ".temper/specs/pw/tasks.md", TASKS)
    verdict(cwd, "plan", True)


states = {}
p = project("plan")
to_plan(p)
states["plan"] = save(p)

g = project("group")
to_plan(g)
cli(g, "state", "advance", "plan_complete", "build")
write(g, ".temper/groups.json", json.dumps({"version": 1, "slug": "pw", "groups": {"G1": {"status": "running", "worktree": "w"}},
                                             "tasks": {"1": {"status": "running", "group": "G1", "attempt": 1}}}))
states["build-group"] = save(g)

ARMED = "review:\n  block-on: [critical]\nautonomy:\n  enabled: true\n"
a = project("armed")
write(a, ".claude/temper.config", ARMED)
to_plan(a)
cli(a, "state", "set", "run_mode", "autonomous")
cli(a, "state", "advance", "plan_complete", "build")
states["armed-build"] = save(a)

r = project("review")
to_plan(r)
cli(r, "state", "advance", "plan_complete", "build")
verdict(r, "build", True)
cli(r, "state", "advance", "build_complete", "review")
write(r, ".temper/evidence/review.json", json.dumps(FINDINGS))
verdict(r, "review", False, "critical findings", "1 open critical finding")
states["review-finding"] = save(r)

k = project("parked")
write(k, ".claude/temper.config", ARMED)
to_plan(k)
cli(k, "state", "set", "run_mode", "autonomous")
cli(k, "state", "advance", "plan_complete", "build")
verdict(k, "build", False, "tests pass", "2 tests fail: unit/app.test.ts")
cli(k, "park", "--verdict", "PARKED-NEEDS-DECISION", "--reason", "2 tests fail: unit/app.test.ts")
states["parked"] = save(k)

# The commit hook the tree's installer writes, in a throwaway repository of its own
h = project("hook")
subprocess.run(["bash", os.path.join(tree, "scripts", "guards", "install.sh")], cwd=h, check=True,
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
gitdir = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=h, stdout=subprocess.PIPE, text=True).stdout.strip()
hook = open(os.path.join(h, gitdir, "temper-gate", "pre-commit"), encoding="utf-8").read()

template = open(os.path.join(tree, "templates", "temper.config.default"), encoding="utf-8").read()
print(json.dumps({"states": states, "template": template, "hook": mark(hook, h)}))
PY
done

python3 -I - "$WORK/saved-7c7a1c1.json" "$WORK/saved-10e965a.json" <<'PY'
import json, sys
out = {"about": "Written by scripts/selftest/make-saved-old.sh; do not edit by hand. Five run states, the config template "
                "and the commit hook of 9.8.4 (7c7a1c1) and of the base (10e965a). @PROJECT@ and @PLUGIN@ mark the "
                "project folder and the plugin folder."}
out["7c7a1c1"] = json.load(open(sys.argv[1]))
out["10e965a"] = json.load(open(sys.argv[2]))
print(json.dumps(out, indent=1, sort_keys=True))
PY
