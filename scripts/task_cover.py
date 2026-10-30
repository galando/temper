"""task_cover.py: a task an earlier task already built (F19). The task's RED run passed before any change, so there is nothing
to make go green. The gate neither retries nor parks it; the person accepts it as done, or has it run again.

  python3 task_cover.py accept GROUPS.json BUILD_LEDGER.json N REASON   record the person's acceptance: a ledger row of phase
                                                                        covered (executed_by person) and the task back to running,
                                                                        so its gate passes it and commits its declared files
  python3 task_cover.py retry GROUPS.json N                              the task starts again from the group branch

Standard library only.
"""
import json
import os
import sys
import time


def load(path, default):
    try:
        d = json.load(open(path, encoding="utf-8"))
        return d if isinstance(d, type(default)) else default
    except (OSError, ValueError):
        return default


def save(path, d):
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(d, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)


def accept(groups_path, ledger_path, n, reason):
    run = load(groups_path, {})
    t = (run.get("tasks") or {}).get(str(n)) or {}
    if t.get("status") != "covered":
        raise ValueError("Task %s is not waiting on a decision about covered tests (status: %s)" % (n, t.get("status", "none")))
    if not reason.strip():
        raise ValueError("accepting a covered task needs the person's reason (--reason '<why>')")
    c = t.get("covered") or {}
    rows = load(ledger_path, [])
    rows.append({"claim": "Task %s accepted as done: its tests passed before any change" % n, "cmd": c.get("cmd"), "exit_code": 0,
                 "artifact": None, "sha256": None, "value": None, "severity": None, "phase": "covered", "scenario": None,
                 "criterion": None, "label": "PROVEN", "task": int(n), "executed_by": "person", "reason": reason.strip(),
                 "output": c.get("tail", ""), "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())})
    save(ledger_path, rows)
    t["status"] = "running"
    t["accepted_covered"] = reason.strip()
    run["tasks"][str(n)] = t
    save(groups_path, run)


def retry(groups_path, n):
    run = load(groups_path, {})
    t = (run.get("tasks") or {}).get(str(n)) or {}
    if t.get("status") != "covered":
        raise ValueError("Task %s is not waiting on a decision about covered tests (status: %s)" % (n, t.get("status", "none")))
    t["status"] = "pending"
    t.pop("covered", None)
    run["tasks"][str(n)] = t
    save(groups_path, run)


def main(argv):
    try:
        if len(argv) == 6 and argv[1] == "accept":
            accept(argv[2], argv[3], argv[4], argv[5])
            return 0
        if len(argv) == 4 and argv[1] == "retry":
            retry(argv[2], argv[3])
            return 0
    except ValueError as e:
        print("FAIL: %s" % e, file=sys.stderr)
        return 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
