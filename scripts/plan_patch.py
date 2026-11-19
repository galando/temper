"""plan_patch.py: `temper plan patch`, the person's change of one command line of the plan (9.8.5, S6; WP21: also
before the approval, as the answer at plan.command, when the plan's line changes and no hash moves).

  python3 plan_patch.py SPEC STATE GROUPS LEDGER G<n> --cmd '<command>'        a group's **Validate:** line
  python3 plan_patch.py SPEC STATE GROUPS LEDGER task <N> --cmd '<command>'    a task's **Test:** line
  python3 plan_patch.py SPEC STATE GROUPS LEDGER integration --cmd '<command>' the plan's **Integration:** line

A wrong command line (a suite that cannot finish in the time limit, a filter that can never meet a coverage rule) used to
need a loop back to Plan: Plan, Design and every passed task again, and the run's one loop. A patch changes that one
line of tasks.md and nothing else, keeps every passed task, and spends no loop. It is the person's (the mod lets only
the answer to the CLI's question run it). The approved plan's hash moves with it, so Build does not refuse the plan;
the plan ledger records the old and the new line; a patched group's check runs again. Standard library only.
"""
import json
import os
import re
import sys
import time

import approval
import tasks_md

MAX_CMD = 400


def digest(m):
    """The approved plan's digest: the one rule of scripts/approval.py, which the CLI's _plan_digest calls too."""
    return approval.plan_digest(m)


def load(path):
    try:
        d = json.load(open(path, encoding="utf-8"))
        return d if isinstance(d, dict) else None
    except (OSError, ValueError):
        return None


def save(path, d):
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(d, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)


def fail(msg):
    print("FAIL: " + msg, file=sys.stderr)
    return 1


def patch_lines(lines, target, num, cmd):
    """(new lines, old command) with the one line replaced, or (None, why)."""
    head = {"group": r"^##\s+Group\s+%s\b" % re.escape(num or ""), "task": r"^###\s+Task\s+%s\b" % re.escape(num or "")}.get(target)
    key = {"group": "Validate", "task": "Test", "integration": "Integration"}[target]
    start, end = 0, len(lines)
    if head:
        start = next((i for i, l in enumerate(lines) if re.match(head, l)), None)
        if start is None:
            return None, "tasks.md has no %s %s" % ("group" if target == "group" else "task", num)
        lvl = 2 if target == "group" else 3
        end = next((i for i in range(start + 1, len(lines)) if re.match(r"^#{1,%d}\s" % lvl, lines[i])), len(lines))
    for i in range(start, end):
        m = re.match(r"^(\s*\*\*%s:\*\*\s*)`([^`]*)`(.*)$" % key, lines[i])
        if m:
            old = m.group(2)
            lines = list(lines)
            lines[i] = "%s`%s`%s" % (m.group(1), cmd, m.group(3))
            return lines, old
    return None, "no **%s:** line with a backticked command there" % key


def main(argv):
    if len(argv) < 7:
        print(__doc__, file=sys.stderr)
        return 2
    spec, state, groups, ledger = argv[1:5]
    rest = argv[5:]
    if rest[0] == "task" and len(rest) >= 2:
        target, num, rest = "task", rest[1], rest[2:]
    elif rest[0] == "integration":
        target, num, rest = "integration", None, rest[1:]
    elif re.match(r"^G\d+$", rest[0]):
        target, num, rest = "group", rest[0], rest[1:]
    else:
        return fail("usage: temper plan patch G<n>|task <N>|integration --cmd '<command>'")
    if len(rest) != 2 or rest[0] != "--cmd":
        return fail("temper plan patch needs --cmd '<command>'")
    cmd = " ".join(rest[1].split())
    if not cmd or len(cmd) > MAX_CMD or "`" in cmd:
        return fail("the command is one line of at most %d characters, with no backquote" % MAX_CMD)
    st = load(state)
    if st is None:
        return fail("no active run (temper state init)")
    approved = bool(st.get("plan_hash"))   # WP21: before the approval, the answer at plan.command changes the plan's line
    path = os.path.join(spec, "tasks.md")
    lines = open(path, encoding="utf-8").read().split("\n")
    new, old = patch_lines(lines, target, num, cmd)
    if new is None:
        return fail(old)
    if approved and digest(tasks_md.parse(path)) != st.get("plan_hash"):
        return fail("tasks.md differs from the approved plan in more than this line; loop back to Plan")
    tmp = path + ".tmp.%d" % os.getpid()
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(new))
    os.replace(tmp, path)
    h = digest(tasks_md.parse(path))
    if approved:
        st["plan_hash"] = h
        save(state, st)
    g = load(groups) if approved else None
    if g is not None:
        if g.get("plan_hash"):
            g["plan_hash"] = h
        if target == "group" and isinstance((g.get("groups") or {}).get(num), dict):
            g["groups"][num].pop("gate", None)   # the patched group's check runs again
        if target == "integration":
            g.pop("integration", None)
        save(groups, g)
    what = {"group": "%s Validate" % num, "task": "Task %s Test" % num, "integration": "Integration"}[target]
    try:
        rows = json.load(open(ledger, encoding="utf-8"))
        rows = rows if isinstance(rows, list) else []
    except (OSError, ValueError):
        rows = []
    rows.append({"claim": "plan patch by the person: %s: `%s` -> `%s`" % (what, old, cmd), "cmd": None, "exit_code": None,
                 "artifact": None, "sha256": None, "value": None, "severity": None, "phase": "note",
                 # before the approval the plan is checked again (an edit); after it, Build takes the note (an input)
                 "kind": "input" if approved else "edit",
                 "scenario": None, "criterion": None, "label": "PERSON", "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())})
    os.makedirs(os.path.dirname(os.path.abspath(ledger)), exist_ok=True)
    save(ledger, rows)
    print("OK: %s is now `%s` (was `%s`); the passed tasks keep their work" % (what, cmd, old))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
