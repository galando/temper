"""failure.py: the one failure record of a run (9.8.5, WP23). Every failure is one typed record in
.temper/evidence/failures.json, a list written only here; a step back leaves it (it is no stage ledger), and
`temper state archive` copies it into the spec folder's gate-ledger.json (state_ops.archive_ledger).

  python3 failure.py record STAGE SCOPE CHECK KIND WHY [CMD [EXIT [CLASS_BY]]]   one record (the person's or a test's)
  python3 failure.py skip STAGE REASON           the person's skip with its reason resolves the open records of the stage
  python3 failure.py open [STAGE]                the open records, as JSON

A record: {"id", "ts", "stage", "scope", "check", "cmd", "exit", "ran_by", "tree", "setup", "limit_s", "key", "class",
"kind", "class_by", "why", "fail_lines", "row", "n", "step", "resolved"}. `scope` is the budget key of WP10 wherever the
failure has one (`gate:<stage>`, `group:<G>`, `task:<N>`, `acceptance`, `pipeline`), else `base` or `plan-command`.
The class follows from the kind, by structure only (the exit code, the shape of the run, the base), from the closed
list KINDS. A class picks the next step; it never changes a verdict: a record is resolved only by a pass of the same
check and scope on another key, or by the person's skip with a reason. Standard library only.
"""
import hashlib
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
CLASSES = ("environment", "command", "plan", "code", "not measured")
KINDS = {
    "setup-line": "environment", "program-missing": "environment", "service-down": "environment",
    "tool-version": "environment", "red-base": "environment",
    "timeout": "command", "fails-on-base": "command", "fix-changed-nothing": "command", "no-test-found": "command",
    "blocked-task": "plan", "undeclared-change": "plan", "merge-conflict": "plan", "no-validate": "plan",
    "interface-missing": "plan", "test-wrong": "plan",
    "no-tool": "not measured", "no-base": "not measured", "no-run": "not measured",
    "test-failed": "code", "coverage-drop": "code", "finding": "code",
}
CHECKS = ("suite", "validate", "task-test", "scenario", "acceptance", "coverage", "interfaces", "regression")
NO_TESTS = re.compile(r"NO TESTS RAN|no tests ran|collected 0 items|^Ran 0 tests", re.M)


def path(root=None):
    return os.path.join(root or os.getcwd(), ".temper", "evidence", "failures.json")


def read(root=None):
    try:
        d = json.load(open(path(root)))
    except (OSError, ValueError):
        return []
    return [x for x in d if isinstance(x, dict)] if isinstance(d, list) else []


def _now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _change(fn, root=None):
    """Read, change and write the list under a lock of its own (the CLI's processes write it one at a time)."""
    p = path(root)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    try:
        import fcntl
        lk = open(p + ".lock", "w")
        fcntl.flock(lk, fcntl.LOCK_EX)
    except (ImportError, OSError):
        lk = None
    try:
        recs = read(root)
        out = fn(recs)
        tmp = "%s.tmp.%d" % (p, os.getpid())
        with open(tmp, "w") as f:
            json.dump(recs, f, indent=2)
            f.write("\n")
        os.replace(tmp, p)
        return out
    finally:
        if lk:
            lk.close()


def _run_env():
    if HERE not in sys.path:
        sys.path.insert(0, HERE)
    import run_env
    return run_env


def kind_of(out, rc, cmd, setup=None):
    """(kind, class_by) of a failed run, by structure only: the exit code, a setup line or program the runner names, a
    declared service down, a runner that found no test, a time out; every other failure is the code's."""
    text = out.decode("utf-8", "replace") if isinstance(out, bytes) else str(out or "")
    if rc == 124:
        return "timeout", "exit"
    if rc == 125 or "temper-setup: FAIL" in text:
        return "setup-line", "exit"
    if re.search(r"^[\w.-]+: SETUP: ", text, re.M):
        return "setup-line", "structure"
    try:
        why = _run_env().env_fault(text, rc, cmd, setup)
    except Exception:
        why = ""
    if why:
        return ("program-missing", "exit") if rc == 127 else ("service-down", "structure")
    if rc in (4, 5) and NO_TESTS.search(text):
        return "no-test-found", "structure"
    return "test-failed", "exit"


def _budget_n(scope, root=None):
    try:
        d = json.load(open(os.path.join(root or os.getcwd(), ".temper", "budget.json")))
        return sum(1 for x in d.get("used") or [] if isinstance(x, dict) and x.get("key") == scope)
    except (OSError, ValueError, AttributeError):
        return 0


def _setup_digest(root=None):
    try:
        s = _run_env().load_setup()
    except Exception:
        s = {}
    return hashlib.sha256(json.dumps(s or {}, sort_keys=True, default=str).encode("utf-8")).hexdigest()[:16] if s else ""


def record(stage, scope, check, kind, why, cmd="", exit=None, ran_by="cli", tree="", key="", limit_s=None,
           fail_lines=(), row="", class_by="exit", step="", root=None):
    """Append one record and return it; a record of the same ledger row is not written twice (None). A step back empties
    the stage's ledger, so a row of the same place with another key is another run, and gets its own record."""
    if kind not in KINDS:
        kind = "finding" if kind else "test-failed"

    def add(recs):
        if row and any(x.get("row") == row and (x.get("key") or "") == (key or "") for x in recs):
            return None
        rec = {"id": "F%d" % (1 + max([int(x["id"][1:]) for x in recs if re.match(r"^F\d+$", str(x.get("id")))] or [0])),
               "ts": _now(), "stage": stage, "scope": scope, "check": check, "cmd": cmd or "", "exit": exit,
               "ran_by": ran_by, "tree": tree or "", "setup": _setup_digest(root), "limit_s": limit_s, "key": key or "",
               "class": KINDS[kind], "kind": kind, "class_by": class_by, "why": " ".join(str(why or "").split())[:300],
               "fail_lines": [" ".join(str(x).split())[:200] for x in list(fail_lines or [])[:8]], "row": row,
               "n": _budget_n(scope, root), "step": step, "resolved": None}
        recs.append(rec)
        return rec
    return _change(add, root)


def of_row(stage, scope, check, r, index=None, setup=None, root=None, kind=None):
    """A record of one failed ledger row the CLI ran (its command, exit, key, tree and fail lines)."""
    rc = r.get("exit_code")
    out = str(r.get("output") or "")
    k, by = (kind, "structure") if kind else kind_of(out, rc if isinstance(rc, int) else 1, str(r.get("cmd") or ""), setup)
    why = "%s failed (exit %s): %s" % (check, rc, " ".join(str(r.get("cmd") or "").split())[:160])
    if check == "coverage":
        why = str(r.get("output") or why)
    elif KINDS.get(k) == "environment":   # the environment's own words: the SETUP marker, the setup line, the program
        m = re.search(r"^[\w.-]+: SETUP: (.+)$", out, re.M)
        try:
            why = m.group(1) if m else (_run_env().env_fault(out, rc, str(r.get("cmd") or ""), setup) or why)
        except Exception:
            pass
    return record(stage, scope, check, k, why, cmd=str(r.get("cmd") or ""), exit=rc if isinstance(rc, int) else None,
                  ran_by=str(r.get("executed_by") or "cli"), tree=r.get("tree") or "", key=r.get("key") or "",
                  fail_lines=r.get("fail_lines") or [], row="%s#%s" % (stage, index) if index is not None else "",
                  class_by=by, root=root)


def resolve_pass(scope, check, key, root=None):
    """A pass of the same check and scope on another key resolves the open records of that check (WP23, rule 6); a record
    with no key (a task's, a gate row's) is resolved by any pass."""
    def fix(recs):
        n = 0
        for x in recs:
            if x.get("resolved") is None and x.get("scope") == scope and x.get("check") == check and (
                    not x.get("key") or x.get("key") != (key or "")):
                x["resolved"] = {"by": "pass", "key": key or "", "ts": _now()}
                n += 1
        return n
    if not os.path.exists(path(root)):
        return 0
    return _change(fix, root)


SKIP_SCOPE = {"base-suite": "base", "plan-command": "plan-command"}


def resolve_skip(stage, reason, root=None):
    """The person's skip of a stage's check, with the reason: it resolves the open records of that stage; the skip of a
    red base (base-suite) or of a plan command (plan-command) resolves the records of that scope, and no stage's skip does."""
    def hit(x):
        if stage in SKIP_SCOPE:
            return x.get("scope") == SKIP_SCOPE[stage]
        return x.get("scope") not in SKIP_SCOPE.values() and (x.get("stage") == stage or x.get("scope") == "gate:%s" % stage)

    def fix(recs):
        n = 0
        for x in recs:
            if x.get("resolved") is None and hit(x):
                x["resolved"] = {"by": "person", "reason": reason, "ts": _now()}
                n += 1
        return n
    if not os.path.exists(path(root)):
        return 0
    return _change(fix, root)


def open_records(stage=None, scope=None, root=None):
    return [x for x in read(root) if x.get("resolved") is None and (stage is None or x.get("stage") == stage)
            and (scope is None or x.get("scope") == scope)]


def set_step(ids, step, root=None):
    """What a rule did about a record (the commit card lists it)."""
    def fix(recs):
        for x in recs:
            if x.get("id") in ids:
                x["step"] = step
    if ids and os.path.exists(path(root)):
        _change(fix, root)


ROW_CHECK = {"integration": "suite", "tests pass": "suite", "acceptance tests written before Build": "acceptance",
             "coverage": "coverage", "regression proof": "regression", "scenarios traced to tests": "scenario"}


def of_gate(stage, reqs, root=None):
    """A failed gate: one record per failed row that no run recorded yet (an open record of the stage's gate with the
    row's check). A row that passes resolves the records of its own (row:<name>)."""
    scope = "gate:%s" % stage
    passed = {"row:%s" % x.get("name") for x in reqs if isinstance(x, dict) and x.get("pass") is True}
    for check in {x.get("check") for x in open_records(scope=scope, root=root)} & passed:
        resolve_pass(scope, check, "", root)
    rows = [x for x in reqs if isinstance(x, dict) and x.get("pass") is False]
    if not rows:
        return
    have = {(x.get("scope"), x.get("check")) for x in open_records(root=root)}
    for x in rows:
        name = str(x.get("name") or "")
        check = ROW_CHECK.get(name, "row:%s" % name)
        if (scope, check) in have or (check == "suite" and any(s == scope for s, _ in have)):
            continue
        detail = " ".join(str(x.get("detail") or "").split())
        kind = "no-run" if re.search(r"not run|no passing test-run evidence", detail) else "finding"
        record(stage, scope, check, kind, "%s: %s" % (name, detail), ran_by="cli", class_by="structure", root=root)
        have.add((scope, check))


def _ledger(stage, root=None):
    try:
        rows = json.load(open(os.path.join(root or os.getcwd(), ".temper", "evidence", "%s.json" % stage)))
        return rows if isinstance(rows, list) else []
    except (OSError, ValueError):
        return []


def of_integration(reason, group="", root=None):
    """A failed `temper integrate`: it spends its repeat under gate:build, so that is its scope; `check` says which check
    of integrate failed. A failed suite is the record build-checks wrote of its row (the same row is not written twice)."""
    rows = _ledger("build", root)
    idx = max((i for i, x in enumerate(rows) if isinstance(x, dict) and x.get("claim") == "Integration suite"), default=None)
    if reason.startswith("integration suite failed") and idx is not None and rows[idx].get("exit_code") not in (0, None):
        return of_row("build", "gate:build", "suite", rows[idx], idx, root=root)
    for words, check, kind in (("merge conflict", "row:integration", "merge-conflict"),
                               ("not made by the CLI", "row:integration", "undeclared-change"),
                               ("group gate not passed", "row:integration", "no-run"),
                               ("integration suite failed", "suite", "test-failed")):
        if words in reason:
            break
    else:
        check, kind = "interfaces", "interface-missing"
    return record("build", "gate:build", check, kind, reason, class_by="structure", root=root)


def of_group(gid, reason, timeout="", root=None):
    """A failed group gate: scope group:<G>; the row of its Validate when it ran."""
    rows = _ledger("build", root)
    idx = max((i for i, x in enumerate(rows) if isinstance(x, dict) and x.get("phase") == "group" and x.get("group") == gid),
              default=None)
    r = rows[idx] if idx is not None else {}
    if r and r.get("exit_code") not in (0, None) and "Validate" in reason:
        return of_row("build", "group:%s" % gid, "validate", r, idx, root=root)
    kind = "timeout" if timeout else "no-validate" if "declares no **Validate:**" in reason else \
        "undeclared-change" if "uncommitted changes" in reason or "no longer on the group branch" in reason else \
        "no-run" if "not every task has passed" in reason or "is parked" in reason else "test-failed"
    return record("build", "group:%s" % gid, "scenario" if "scenario" in reason else "validate", kind, reason,
                  class_by="structure", root=root)


def pass_group(gid, root=None):
    """A passed group gate: its Validate and scenario passed on the key of its latest row (resolve_pass)."""
    rows = _ledger("build", root)
    r = next((x for x in reversed(rows) if isinstance(x, dict) and x.get("phase") == "group" and x.get("group") == gid), {})
    for check in ("validate", "scenario"):
        resolve_pass("group:%s" % gid, check, r.get("key") or "", root)


def triaged_test(stage, root=None):
    """The triage calls the failing locked test wrong: the open acceptance records of the stage's gate that the code was
    blamed for are a locked test the triage calls wrong (class plan, kind test-wrong)."""
    def fix(recs):
        for x in recs:
            if x.get("resolved") is None and x.get("scope") == "gate:%s" % stage and x.get("check") == "acceptance" \
                    and x.get("class") == "code":
                x.update({"class": KINDS["test-wrong"], "kind": "test-wrong", "class_by": "triage"})
    if os.path.exists(path(root)):
        _change(fix, root)


def counts(root=None):
    """{class: number of records} (the run summary)."""
    out = {}
    for x in read(root):
        out[x.get("class")] = out.get(x.get("class"), 0) + 1
    return out


def main(argv):
    if len(argv) >= 7 and argv[1] == "record":
        a = argv[2:] + [""] * 4
        rec = record(a[0], a[1], a[2], a[3], a[4], cmd=a[5], exit=int(a[6]) if re.match(r"^-?\d+$", a[6]) else None,
                     class_by=a[7] or "exit")
        print("OK: failure %s recorded" % (rec or {}).get("id"))
        return 0
    if len(argv) == 4 and argv[1] == "skip":
        n = resolve_skip(argv[2], argv[3])
        if n:
            print("OK: %d failure record(s) resolved by the person's skip" % n)
        return 0
    if len(argv) in (2, 3) and argv[1] == "open":
        print(json.dumps(open_records(argv[2] if len(argv) == 3 else None)))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
