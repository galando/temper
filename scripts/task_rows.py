"""task_rows.py: the Build gate rows about tasks.md, one mode per call (each prints one JSON row).

  python3 task_rows.py all-tasks TASKS.md GROUPS.json
  python3 task_rows.py all-manual TASKS.md          exit 0 when every task is manual

all-tasks counts every task tasks.md parses (a task with no checkbox too: the old count of unchecked boxes passed a plan
with one task ticked of eight). A task is done as tasks_md.task_done says, the one definition the flow reads too: the run
recorded it passed (groups.json), or, for a task the run holds no record of in a group it never started, its box is ticked.
A tasks.md with no parsable task (an old flat list) is counted by its boxes, as before. Standard library only.
"""
import json
import os
import re
import sys

import tasks_md


def row(ok, detail):
    return {"name": "all tasks complete", "pass": ok, "detail": detail}


def all_tasks(path, groups_path):
    plan = tasks_md.parse(path)
    try:
        run = json.load(open(groups_path, encoding="utf-8"))
    except (OSError, ValueError):
        run = {}
    if not plan["tasks"]:
        try:
            text = open(path, encoding="utf-8").read()
        except OSError:
            text = ""
        left = len(re.findall(r"^\s*- \[ \]", text, re.M))
        return row(left == 0, "no unchecked tasks in tasks.md" if left == 0 else "%d unchecked task(s) remain in tasks.md" % left)
    open_tasks = [t["n"] for t in plan["tasks"] if not tasks_md.task_done(t, run)]
    total = len(plan["tasks"])
    if open_tasks:
        return row(False, "%d of %d task(s) not done in tasks.md (Task %s)" % (
            len(open_tasks), total, ", ".join(str(n) for n in open_tasks[:8]) + (" and more" if len(open_tasks) > 8 else "")))
    return row(True, "all %d task(s) of tasks.md are done" % total)


def all_manual(path):
    tasks = tasks_md.parse(path)["tasks"]
    return bool(tasks) and all(t.get("manual") for t in tasks)


def main(argv):
    if len(argv) == 3 and argv[1] == "all-manual":
        return 0 if all_manual(argv[2]) else 1
    if len(argv) == 4 and argv[1] == "all-tasks":
        print(json.dumps(all_tasks(argv[2], argv[3])))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
