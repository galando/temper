#!/usr/bin/env python3
"""grade.py RUN_DIR: grade one benchmark run against its task's hidden tests. Standard library only.

It never changes RUN_DIR/work. It copies it to RUN_DIR/grade, then:
  1. hidden   copies the task's hidden/ tests in (no arm ever saw them) and runs each test: pass, fail or error.
  2. suite    runs the task's ORIGINAL suite from its repo/unit folder (as they were before the run, so an arm that
              deleted or weakened a test gains nothing): did the change break what worked?
  3. diff     what the arm changed against the base commit: files and lines, the Temper and Claude folders
              (.temper/, .claude/) counted apart, and every changed file outside the task's expected paths
              (meta.json "expected_paths"), which is scope creep or a missed file.
It writes RUN_DIR/grade.json and prints it.
"""
import json
import re
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

RUNNER = r'''
import json, sys, unittest, os
sys.path.insert(0, os.getcwd())
start = sys.argv[1]
suite = unittest.defaultTestLoader.discover(start, top_level_dir=os.getcwd())
res = {}
class R(unittest.TextTestResult):
    def addSuccess(self, t): super().addSuccess(t); res[t.id()] = "pass"
    def addFailure(self, t, e): super().addFailure(t, e); res[t.id()] = "fail"
    def addError(self, t, e): super().addError(t, e); res[t.id()] = "error"
    def addSkip(self, t, r): super().addSkip(t, r); res[t.id()] = "skip"
# A module that cannot be imported shows up as one failed loader test: count it as an error.
r = unittest.TextTestRunner(stream=open(os.devnull, "w"), resultclass=R).run(suite)
for t, _ in r.errors:
    res.setdefault(t.id(), "error")
print("BENCH_JSON " + json.dumps(res))
'''


def run_tests(cwd, start, timeout=300):
    runner = os.path.join(cwd, ".bench_runner.py")
    with open(runner, "w") as f:
        f.write(RUNNER)
    try:
        env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
        p = subprocess.run([sys.executable, runner, start], cwd=cwd, capture_output=True, text=True, timeout=timeout, env=env)
        out = p.stdout + p.stderr
    except subprocess.TimeoutExpired:
        return {"__timeout__": "error"}
    finally:
        os.remove(runner)
    for line in out.splitlines():
        if line.startswith("BENCH_JSON "):
            return json.loads(line[len("BENCH_JSON "):])
    return {"__crash__": "error"}


def run_node_tests(cwd, start, timeout=300):
    """A Node project's tests (node --test, TypeScript by type stripping): {test name: pass|fail}, from the TAP report. A file
    that does not load is one failed entry named after the file."""
    files = sorted(os.path.join(start, f) for f in os.listdir(os.path.join(cwd, start)) if re.search(r"\.test\.[cm]?[jt]s$", f))
    if not files:
        return {}
    try:
        p = subprocess.run(["node", "--test", "--experimental-strip-types", "--test-reporter=tap"] + files, cwd=cwd,
                           capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return {"__timeout__": "error"}
    res = {}
    for line in p.stdout.splitlines():
        m = re.match(r"^(\s*)(not ok|ok) \d+ - (.+?)(?:\s+#.*)?$", line)
        if m and not m.group(3).startswith("#"):
            res[m.group(3)] = "pass" if m.group(2) == "ok" else "fail"
    return res or {"__crash__": "error"}


def split(hidden):
    """A vague task's hidden tests are test_ticket_* (from the ticket and the house rules) and test_brief_N_* (brief
    fact N). A fact counts as met when every one of its tests passes."""
    ticket = {k: v for k, v in hidden.items() if ".test_ticket_" in k}
    facts = {}
    for k, v in hidden.items():
        m = re.search(r"\.test_brief_(\d+)_", k)
        if m:
            facts.setdefault(int(m.group(1)), []).append(v == "pass")
    if not ticket and not facts:
        return {}
    return {"ticket_pass": sum(v == "pass" for v in ticket.values()), "ticket_total": len(ticket),
            "facts_met": sorted(n for n, ok in facts.items() if all(ok)), "facts_tested": sorted(facts)}


def git(cwd, *a):
    return subprocess.run(["git", *a], cwd=cwd, capture_output=True, text=True).stdout


def main():
    run_dir = os.path.abspath(sys.argv[1])
    run = json.load(open(os.path.join(run_dir, "run.json")))
    task_dir = os.path.join(HERE, "tasks", run["task"])
    meta = json.load(open(os.path.join(task_dir, "meta.json")))
    work = os.path.join(run_dir, "work")
    g = os.path.join(run_dir, "grade")
    shutil.rmtree(g, ignore_errors=True)
    shutil.copytree(work, g, symlinks=True, ignore=shutil.ignore_patterns("__pycache__"))

    # 3 first: the diff, before any grading file lands in the copy.
    git(g, "add", "-A")
    files = []
    for line in git(g, "diff", "--cached", "--numstat", run["base"]).splitlines():
        add, rem, p = line.split("\t", 2)
        files.append({"path": p, "added": int(add) if add.isdigit() else 0, "removed": int(rem) if rem.isdigit() else 0})
    files = [f for f in files if "__pycache__/" not in f["path"] and not f["path"].endswith(".pyc") and f["path"] != ".coverage"]
    tool = lambda p: p.startswith(".temper/") or p.startswith(".claude/") or p.startswith(".githooks/")
    code = [f for f in files if not tool(f["path"])]
    expected = meta.get("expected_paths", [])
    outside = [f["path"] for f in code if not any(f["path"].startswith(e) for e in expected)]

    # 1. hidden tests
    shutil.copytree(os.path.join(task_dir, "hidden"), os.path.join(g, "bench_hidden"))
    node = meta.get("runner") == "node"
    hidden = run_node_tests(g, "bench_hidden") if node else run_tests(g, "bench_hidden")
    # 2. the original suite, as it was at the base
    orig = os.path.join(task_dir, "repo", meta.get("suite_dir", "unit"))
    suite = {}
    if os.path.isdir(orig):
        shutil.copytree(orig, os.path.join(g, "bench_suite"))
        suite = run_node_tests(g, "bench_suite") if node else run_tests(g, "bench_suite")

    passed = sum(1 for v in hidden.values() if v == "pass")
    # A test file that does not load counts as one test: the task's own count keeps the rate comparable.
    for i in range(len(hidden), int(meta.get("hidden_count", 0))):
        hidden["__not_run_%d__" % i] = "error"
    grade = {
        "task": run["task"], "arm": run["arm"], "rep": run["rep"],
        "hidden_pass": passed, "hidden_total": len(hidden),
        "hidden_rate": round(passed / len(hidden), 3) if hidden else 0.0,
        "hidden_all": bool(hidden) and passed == len(hidden),
        "hidden": hidden,
        **split(hidden),
        "suite_ok": all(v == "pass" for v in suite.values()),
        "suite": suite,
        "code_files": len(code),
        "code_lines": sum(f["added"] + f["removed"] for f in code),
        "tool_files": len(files) - len(code),
        "outside_expected": outside,
        "files": files,
    }
    with open(os.path.join(run_dir, "grade.json"), "w") as f:
        json.dump(grade, f, indent=2)
        f.write("\n")
    print(json.dumps({k: v for k, v in grade.items() if k not in ("hidden", "suite", "files")}))


if __name__ == "__main__":
    main()
