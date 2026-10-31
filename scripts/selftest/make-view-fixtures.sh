#!/usr/bin/env bash
# make-view-fixtures.sh: the views the temper CLI writes (.temper/view.json) at the points of a run the mod's tests
# use, printed as one TypeScript module. The mod's tests import that module (its tests cannot read a file), so they
# test against the CLI's real output, and a self test case runs this script and compares, so the two cannot drift.
#
#   bash scripts/selftest/make-view-fixtures.sh > scripts/selftest/view-fixtures.ts
#
# Each run is made in a throwaway folder, with the CLI's own moves; a verdict is written as a gate run writes it. The
# plugin folder, the project folder, run ids, times and commit ids are replaced by fixed text.
set -euo pipefail
exec </dev/null
unset CDPATH
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${HERE%/scripts/selftest}"
[[ "$ROOT" != "$HERE" && -x "$ROOT/scripts/temper" ]] || { echo "FAIL: cannot find the plugin folder from $HERE" >&2; exit 1; }
WORK="$(mktemp -d)"
WORK="$(cd -P "$WORK" && pwd)"
trap 'rm -rf "$WORK"' EXIT
# under its own root and with a home of its own: a call outside the folder is refused, and no real file is read
export TEMPER_SELFTEST_ROOT="$WORK" HOME="$WORK/home"
mkdir -p "$HOME"

python3 - "$ROOT" "$WORK" "${1:-}" <<'PY'
import json, os, re, subprocess, sys

root, work = sys.argv[1], sys.argv[2]
temper = os.path.join(root, "scripts", "temper")
views = {}

INTENT = "\n".join([
    "# Intent: Password reset by email",
    "",
    "**Status:** draft",
    "**Complexity:** simple",
    "",
    "### Success Criteria",
    "",
] + ["- [ ] AC-0%d [required]: criterion %d (source: test)" % (n, n) for n in range(1, 6)] + [""])
PLAN = "\n".join(["# Plan", "", "### Files to Modify", "", "| File | Change |", "|---|---|", "| `src/app.ts` | edit |",
                  "| `unit/app.test.ts` | add |", "| `src/mail.ts` | edit |", ""])
TASKS = "\n".join([
    "# Tasks: Password reset by email", "", "**Integration:** `npm test`", "",
    "## Group G1: Tokens", "**Depends:** none", "**Validate:** `npm test`", "**Context:**", "Keep the token API.", "",
    "### Task 1: Issue a token", "**File:** `src/app.ts`, `unit/app.test.ts`", "**Depends:** none", "**Test:** `npm test`",
    "**Cases:**", "- a token is issued", "**Traced to:** Scenario: \"reset\"", "- [ ] done", "",
    "### Task 2: Expire a token", "**File:** `src/app.ts`", "**Depends:** Task 1", "**Test:** `npm test`",
    "**Cases:**", "- an old token is refused", "**Traced to:** Scenario: \"reset\"", "- [ ] done", "",
    "## Group G2: Mail", "**Depends:** G1", "**Validate:** `npm test`", "**Context:**", "Send the mail.", "",
    "### Task 3: Send the mail", "**File:** `src/mail.ts`", "**Depends:** none", "**Test:** `npm test`",
    "**Cases:**", "- the mail holds the link", "**Traced to:** Scenario: \"reset\"", "- [ ] done", ""])
FINDINGS = [
    {"claim": "src/app.ts:12 the token never expires", "severity": "critical", "label": "PROVEN"},
    {"claim": "src/mail.ts:4 the subject is not localized", "severity": "low", "label": "HEURISTIC"},
]


def sh(*args, cwd):
    subprocess.run(args, cwd=cwd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def cli(cwd, *args):
    return subprocess.run([temper] + list(args), cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def write(cwd, rel, text):
    path = os.path.join(cwd, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def verdict(cwd, stage, ok, row="all", detail="ok"):
    path = os.path.join(cwd, ".temper", "gates.json")
    try:
        d = json.load(open(path))
    except Exception:
        d = {}
    d[stage] = {"verdict": "PASS" if ok else "FAIL", "requirements": [{"name": row, "pass": ok, "detail": detail}]}
    json.dump(d, open(path, "w"))


def project(name):
    cwd = os.path.join(work, name)
    os.makedirs(os.path.join(cwd, ".temper"))
    for a in (["git", "init", "-q"], ["git", "config", "user.email", "t@example.com"], ["git", "config", "user.name", "t"]):
        sh(*a, cwd=cwd)
    write(cwd, "README.md", "x\n")
    sh("git", "add", "README.md", cwd=cwd)
    sh("git", "commit", "-qm", "init", cwd=cwd)
    write(cwd, ".claude/temper.config", "review:\n  block-on: [critical]\n")
    return cwd


def snap(cwd, name, run_name):
    cli(cwd, "next", "--json")
    text = open(os.path.join(cwd, ".temper", "view.json")).read()
    head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=cwd, stdout=subprocess.PIPE, text=True).stdout.strip()
    text = text.replace(root, "/plugin").replace(cwd, "/project").replace(work, "/work")
    if head:
        text = text.replace(head, "0" * 40)
    text = re.sub(r"its last commit is [0-9a-f]{7,40} ", "its last commit is 0000000 ", text)
    d = json.loads(text)
    rid = (d.get("run") or {}).get("id")
    text = json.dumps(d, sort_keys=True)
    if rid:
        text = text.replace(rid, run_name)
    text = re.sub(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:?\d\d)?", "2026-01-01T00:00:00Z", text)
    views[name] = json.loads(text)


# A /temper run from Intent to the commit.
p = project("pw")
snap(p, "none", "")
cli(p, "state", "init", "pw", "--feature", "Password reset by email")
snap(p, "intent-work", "run-pw")
write(p, ".temper/specs/pw/intent.md", INTENT)
verdict(p, "intent", False, "Success criteria", "AC-03 has no Validate line")
snap(p, "intent-fail", "run-pw")
verdict(p, "intent", True)
snap(p, "intent-pass", "run-pw")
cli(p, "state", "advance", "intent_complete", "plan")
snap(p, "plan-work", "run-pw")
write(p, ".temper/specs/pw/plan.md", PLAN)
write(p, ".temper/specs/pw/tasks.md", TASKS)
verdict(p, "plan", False, "Blast radius", "src/mail.ts is not in the plan")
snap(p, "plan-fail", "run-pw")
verdict(p, "plan", True)
snap(p, "plan-pass", "run-pw")
write(p, ".claude/temper.config", "review:\n  block-on: [critical]\nautonomy:\n  enabled: true\n")
snap(p, "plan-pass-autonomy", "run-pw")
write(p, ".claude/temper.config", "review:\n  block-on: [critical]\n")
cli(p, "state", "advance", "plan_complete", "build")
snap(p, "build-work", "run-pw")
verdict(p, "build", False, "tests pass", "2 tests fail: unit/app.test.ts")
snap(p, "build-fail", "run-pw")
verdict(p, "build", True)
snap(p, "build-pass", "run-pw")
cli(p, "state", "advance", "build_complete", "review")
snap(p, "review-work", "run-pw")
write(p, ".temper/evidence/review.json", json.dumps(FINDINGS))
verdict(p, "review", False, "critical findings", "1 open critical finding")
snap(p, "review-fail", "run-pw")
verdict(p, "review", True)
snap(p, "review-pass", "run-pw")
cli(p, "state", "advance", "review_complete", "check")
snap(p, "check-work", "run-pw")
verdict(p, "check", False, "tests pass", "exit 1: 2 failed")
snap(p, "check-fail", "run-pw")
verdict(p, "check", True)
snap(p, "check-pass", "run-pw")
cli(p, "state", "advance", "check_complete", "commit")
snap(p, "commit-work", "run-pw")
verdict(p, "commit", False, "review gate", "review has no PASS verdict")
snap(p, "commit-fail", "run-pw")
verdict(p, "commit", True)
snap(p, "commit-pass", "run-pw")
cli(p, "report", "--end")
snap(p, "commit-page", "run-pw")
cli(p, "report", "--no-html")
snap(p, "commit-record", "run-pw")

# A run with a Design stage (a medium plan, with phases.design on).
d = project("design")
write(d, ".claude/temper.config", "review:\n  block-on: [critical]\nphases:\n  design: true\n")
cli(d, "state", "init", "pw", "--feature", "Password reset by email")
write(d, ".temper/specs/pw/intent.md", INTENT.replace("**Complexity:** simple", "**Complexity:** medium"))
verdict(d, "intent", True)
cli(d, "state", "advance", "intent_complete", "plan")
cli(d, "state", "set", "complexity", "medium")
write(d, ".temper/specs/pw/plan.md", PLAN)
write(d, ".temper/specs/pw/tasks.md", TASKS)
verdict(d, "plan", True)
snap(d, "design-plan-pass", "run-design")
cli(d, "state", "advance", "plan_complete", "design")
snap(d, "design-work", "run-design")
verdict(d, "design", False, "API contracts", "no contract for the reset endpoint")
snap(d, "design-fail", "run-design")
verdict(d, "design", True)
snap(d, "design-pass", "run-design")

# An armed run: it goes on by itself after a passed stage, loops back after a failed Review or Check, and parks after a
# failed Build and before the commit.
a = project("armed")
write(a, ".claude/temper.config", "review:\n  block-on: [critical]\nautonomy:\n  enabled: true\n")
cli(a, "state", "init", "pw", "--feature", "Password reset by email")
write(a, ".temper/specs/pw/intent.md", INTENT)
verdict(a, "intent", True)
cli(a, "state", "advance", "intent_complete", "plan")
write(a, ".temper/specs/pw/plan.md", PLAN)
write(a, ".temper/specs/pw/tasks.md", TASKS)
verdict(a, "plan", True)
cli(a, "state", "set", "run_mode", "autonomous")
cli(a, "state", "advance", "plan_complete", "build")
verdict(a, "build", False, "tests pass", "2 tests fail: unit/app.test.ts")
snap(a, "armed-build-fail", "run-armed")
verdict(a, "build", True)
snap(a, "armed-build-pass", "run-armed")
cli(a, "state", "advance", "build_complete", "review")
write(a, ".temper/evidence/review.json", json.dumps(FINDINGS))
verdict(a, "review", False, "critical findings", "1 open critical finding")
snap(a, "armed-review-fail", "run-armed")
verdict(a, "review", True)
snap(a, "armed-review-pass", "run-armed")
cli(a, "state", "advance", "review_complete", "check")
verdict(a, "check", False, "tests pass", "exit 1: 2 failed")
snap(a, "armed-check-fail", "run-armed")
verdict(a, "check", True)
snap(a, "armed-check-pass", "run-armed")
cli(a, "state", "advance", "check_complete", "commit")
verdict(a, "commit", True)
snap(a, "armed-commit-pass", "run-armed")

# A /temper:fix run: the mod stands aside for it.
f = project("fix")
cli(f, "state", "init", "bug", "--command", "fix")
snap(f, "fix-rca", "run-fix")

# ---- the states 9.7.5 added (printed by `make-view-fixtures.sh extra`, view-fixtures-2.ts) ----
extra = {}

def snap2(cwd, name, run_name, *args):
    cli(cwd, "next", "--json", *args)
    saved = dict(views)
    snap(cwd, name, run_name)
    extra[name] = views.pop(name)
    views.pop(name + "::next", None)
    views.clear(); views.update(saved)

def at_build(cwd):
    write(cwd, ".temper/specs/pw/intent.md", INTENT)
    verdict(cwd, "intent", True)
    cli(cwd, "state", "advance", "intent_complete", "plan")
    write(cwd, ".temper/specs/pw/plan.md", PLAN)
    write(cwd, ".temper/specs/pw/tasks.md", TASKS)
    verdict(cwd, "plan", True)
    cli(cwd, "state", "advance", "plan_complete", "build")

# The Context check of Plan
c = project("ctx")
cli(c, "state", "init", "pw", "--feature", "Password reset by email")
write(c, ".temper/specs/pw/intent.md", INTENT + "\n### Open Questions\n\n- Blocking: Context check: is this the right context for the plan? choices: Right direction | Narrow the focus | Fix the sources.\n")
verdict(c, "intent", True)
cli(c, "state", "advance", "intent_complete", "plan")
write(c, ".temper/specs/pw/plan.md", "# Plan\n\n## Context Map\n- use: intent.md - scope\n- gap: no rate limit policy\n- reviewed: pending\n\n## Files to Modify\n")
verdict(c, "plan", False, "context map reviewed", "the Context check is pending: the person's answer is not recorded yet")
snap2(c, "context-check", "run-ctx")

# A manual task, a covered task and the group Change question
m = project("manual")
cli(m, "state", "init", "pw", "--feature", "Password reset by email")
at_build(m)
write(m, ".temper/groups.json", json.dumps({"version": 1, "slug": "pw", "groups": {"G1": {"status": "running", "worktree": "w"}}, "tasks": {"1": {"status": "running", "group": "G1", "attempt": 1, "awaiting": "confirm"}}}))
snap2(m, "manual-task", "run-manual")
write(m, ".temper/groups.json", json.dumps({"version": 1, "slug": "pw", "groups": {"G1": {"status": "running", "worktree": "w"}}, "tasks": {"1": {"status": "covered", "group": "G1", "attempt": 1, "covered": {"cmd": "npm test", "tail": "3 passed"}}}}))
snap2(m, "covered-task", "run-manual")
write(m, ".temper/groups.json", json.dumps({"version": 1, "slug": "pw", "groups": {"G1": {"status": "passed", "worktree": "w", "gate": {"verdict": "PASS"}}}, "tasks": {"1": {"status": "passed", "group": "G1"}, "2": {"status": "passed", "group": "G1"}}}))
snap2(m, "group-change", "run-manual")

# A small change at Check, the pull request options, a branch clash, the Pipeline stage
s = project("small")
cli(s, "state", "init", "pw", "--feature", "Password reset by email")
at_build(s)
for st, nxt in (("build", "review"), ("review", "check")):
    verdict(s, st, True)
    cli(s, "state", "advance", st + "_complete", nxt)
verdict(s, "check", True)
snap2(s, "check-pr-options", "run-small")
cli(s, "next", "--json")
r = cli(s, "adhoc", "open", "--stage", "check", "--reason", "a fix")
snap2(s, "small-change-open", "run-small")
cli(s, "adhoc", "close")

pl = project("pipe")
cli(pl, "state", "init", "pw", "--feature", "Password reset by email")
at_build(pl)
for st, nxt in (("build", "review"), ("review", "check"), ("check", "commit")):
    verdict(pl, st, True)
    cli(pl, "state", "advance", st + "_complete", nxt)
verdict(pl, "commit", True)
cli(pl, "state", "set", "pr", "one")
cli(pl, "state", "advance", "commit_complete", "pipeline")
write(pl, ".temper/specs/pw/pipeline-context.json", json.dumps({"status": "red", "round": 1, "failed_jobs": [{"name": "unit", "stage": "test", "id": "1", "error": "boom"}], "fix": ["src/app.ts: fix"]}))
verdict(pl, "pipeline", False, "jobs passed", "1 job(s) failed: unit")
snap2(pl, "pipeline-red", "run-pipe")

bc = project("clash")
sh("git", "checkout", "-q", "-b", "feature/pw", cwd=bc)
write(bc, "old.txt", "x\n")
sh("git", "add", "old.txt", cwd=bc)
sh("git", "commit", "-qm", "an earlier run", cwd=bc)
sh("git", "checkout", "-q", "-", cwd=bc)
cli(bc, "state", "init", "pw", "--feature", "Password reset by email")
write(bc, ".temper/specs/pw/intent.md", INTENT)
verdict(bc, "intent", True)
snap2(bc, "branch-clash", "run-clash")


if len(sys.argv) > 3 and sys.argv[3] == "extra":
    views = extra
print("// Generated by scripts/selftest/make-view-fixtures.sh%s from the temper CLI: the .temper/view.json it writes at" % (" extra" if views is extra else ""))
print("// each point of a run. Do not edit by hand: a self test case runs the script again and compares.")
print("export const %s: Record<string, unknown> = " % ("EXTRA_VIEWS" if views is extra else "VIEWS") + json.dumps(views, indent=1, sort_keys=True))
PY
