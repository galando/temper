"""task_blocked.py: `temper task blocked N --needs PATH --reason TEXT` (9.8.4), a Build task that cannot be built as planned.

  python3 task_blocked.py GROUPS.json PLAN.json NOW N --needs PATH --reason TEXT

The task's agent records it when the task's test needs a change in a file the task does not declare (the fix is outside
its files): no attempt on any model can build it, so the task is not retried or escalated. The CLI checks that PATH is
outside the task's declared files and names the tasks that declare it; the task's gate then fails once and parks the group
(scripts/temper), and `temper next` asks the person, Loop back to Plan first. A benchmark run spent four attempts (two on
Haiku, two on Sonnet) on such a task before the loop back. `group reopen` clears the mark. The caller holds the run's lock.
Standard library only.
"""
import json
import os
import sys


def norm(p):
    p = p.strip()
    return p[2:] if p.startswith("./") else p


def fail(msg):
    print("FAIL: " + msg, file=sys.stderr)
    return 1


def main(argv):
    if len(argv) < 5 or not argv[4].isdigit():
        return fail("usage: temper task blocked N --needs PATH --reason TEXT")
    path, plan_json, now, n = argv[1], argv[2], argv[3], int(argv[4])
    needs = reason = ""
    rest = argv[5:]
    while rest:
        if rest[0] == "--needs" and len(rest) > 1:
            needs, rest = norm(rest[1]), rest[2:]
        elif rest[0] == "--reason" and len(rest) > 1:
            reason, rest = rest[1].strip(), rest[2:]
        else:
            return fail("unknown flag %s (usage: temper task blocked N --needs PATH --reason TEXT)" % rest[0])
    if not needs or not reason:
        return fail("temper task blocked N needs --needs PATH (the file the task's test needs) and --reason TEXT (why)")
    try:
        plan = json.loads(plan_json)
        d = json.load(open(path))
    except (OSError, ValueError):
        return fail("no grouped Build is running (no groups.json or tasks.md)")
    task = next((t for t in plan.get("tasks", []) if t.get("n") == n), None)
    if task is None:
        return fail("tasks.md has no Task %d" % n)
    t = (d.get("tasks") or {}).get(str(n))
    if not isinstance(t, dict) or t.get("status") != "running":
        return fail("Task %d is not running; only the agent of a running task records a block" % n)
    if needs in {norm(f) for f in task.get("files", [])}:
        return fail("Task %d declares %s itself: change it there, it is no block" % (n, needs))
    owners = sorted(x["n"] for x in plan.get("tasks", []) if x.get("n") != n and needs in {norm(f) for f in x.get("files", [])})
    t["blocked"] = {"needs": needs, "owners": owners, "reason": " ".join(reason.split())[:400], "ts": now}
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w") as fh:
        json.dump(d, fh, indent=2)
        fh.write("\n")
    os.replace(tmp, path)
    owner = ("declared by " + ", ".join("Task %d" % o for o in owners)) if owners else "declared by no task"
    print("OK: Task %d is blocked: its test needs %s (%s). Gate it now: it fails once and the group parks for the person; "
          "it is not retried." % (n, needs, owner))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
