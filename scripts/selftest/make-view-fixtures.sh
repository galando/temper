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

python3 - "$ROOT" "$WORK" <<'PY'
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

print("// Generated by scripts/selftest/make-view-fixtures.sh from the temper CLI: the .temper/view.json it writes at")
print("// each point of a run. Do not edit by hand: a self test case runs the script again and compares.")
print("export const VIEWS: Record<string, unknown> = " + json.dumps(views, indent=1, sort_keys=True))
PY
