"""scenario_ops.py: the scenario tests of a grouped Build (F8, F9). A scenario of intent.md carries a `Test:` line, a scoped
shell command that proves it on the merged tree. The commands run through run_env.py, so a credential-named variable is left
out and the folder they run in comes first on PYTHONPATH.

  python3 scenario_ops.py integrate INTENT CWD TIMEOUT LEDGER    run every Test: command, record one CLI-run row each, print
                                                                 one line each (name, exit, seconds); exit 0 whatever they give
  python3 scenario_ops.py owed INTENT TASKS.md N                 the scenarios Task N owes, one `name<TAB>command` per line
  python3 scenario_ops.py group-run INTENT TASKS.md G CWD TIMEOUT  run the scenarios a group owes; print the failure or nothing

Library use (task_ops.py): owed(), group_owed(), run_owed(), failure(). Standard library only.
"""
import json
import os
import re
import sys
import time

import acceptance
import run_env
import tasks_md


def blocks(intent_path):
    try:
        return acceptance.scenario_blocks(open(intent_path, encoding="utf-8").read().splitlines())
    except OSError:
        return []


def traced(task):
    """The scenario names a task's `Traced to:` line names (quoted names after `Scenario:`)."""
    m = re.search(r"^\*\*Traced to:\*\*\s*Scenario:\s*(.+)$", task.get("block", ""), re.M)
    if not m:
        return []
    names = re.findall(r'"([^"]+)"', m.group(1))
    return names or [m.group(1).strip()]


def _precedes(plan, a, b):
    """True when Task a must finish before Task b: b depends on a, directly or not, or b's group depends on a's group."""
    by_n = {t["n"]: t for t in plan["tasks"]}
    gdep = {g["id"]: g["depends"] for g in plan["groups"]}

    def task_deps(n, seen):
        out = set()
        for d in by_n[n]["depends"]:
            if d in by_n and d not in seen:
                out |= {d} | task_deps(d, seen | {d})
        return out

    def group_deps(g, seen):
        out = set()
        for d in gdep.get(g, []):
            if d not in seen:
                out |= {d} | group_deps(d, seen | {d})
        return out

    return a in task_deps(b, {b}) or by_n[a]["group"] in group_deps(by_n[b]["group"], {by_n[b]["group"]})


def owners(plan):
    """{scenario name: (task n or None, group id)}: a scenario traced to one task is owed by it; traced to several, by the
    task all the others precede; else (no such task) by the group gate of the last of those tasks."""
    tracing = {}
    for t in plan["tasks"]:
        for name in traced(t):
            tracing.setdefault(name, []).append(t)
    out = {}
    for name, ts in tracing.items():
        if len(ts) == 1:
            out[name] = (ts[0]["n"], ts[0]["group"])
            continue
        last = [x for x in ts if all(o is x or _precedes(plan, o["n"], x["n"]) for o in ts)]
        out[name] = (last[0]["n"], last[0]["group"]) if last else (None, ts[-1]["group"])
    return out


def owed(plan, intent_path, n):
    """[(name, cmd)] Task n owes at its gate."""
    own = owners(plan)
    return [(b["name"], b["cmd"]) for b in blocks(intent_path) if b["cmd"].strip() and own.get(b["name"], (0,))[0] == n]


def group_owed(plan, intent_path, gid):
    """[(name, cmd)] the group gate runs on the merged group branch: what a task of the group owes, and what has no single
    task to owe it."""
    own = owners(plan)
    return [(b["name"], b["cmd"]) for b in blocks(intent_path)
            if b["cmd"].strip() and b["name"] in own and own[b["name"]][1] == gid]


def failure(name, cmd, rc, out=b""):
    """The message of a failed scenario test: scenario, command (cut at 60) and exit; pytest's exit 4 or 5 (no such test,
    or none collected) says to write the test under that exact name."""
    msg = "scenario '%s' (%s) exit %s" % (name, cmd[:60], rc)
    if rc in (4, 5) and "pytest" in cmd:
        msg += ": pytest found no such test. Write the test with the exact name the Test: command gives (%s); a test named otherwise does not count" % cmd[:120]
    return msg


def run_owed(items, cwd, timeout):
    """Run (name, cmd) pairs; returns the first failure message, or ''. Records nothing."""
    for name, cmd in items:
        out, rc = run_env.run_cmd(cwd, timeout, [cmd])
        if rc != 0:
            return failure(name, cmd, rc, out)
    return ""


def integrate(intent_path, cwd, timeout, ledger):
    """Run every scenario's Test: command at the merged tree and record a CLI-run row each (a failing one too: the Build gate
    then fails for a real reason). Prints one line each."""
    try:
        rows = json.load(open(ledger))
        rows = rows if isinstance(rows, list) else []
    except (OSError, ValueError):
        rows = []
    for b in blocks(intent_path):
        if not b["cmd"].strip():
            continue
        t0 = time.time()
        out, rc = run_env.run_cmd(cwd, timeout, [b["cmd"]])
        secs = time.time() - t0
        rows.append({"claim": "scenario test at integration", "cmd": b["cmd"], "exit_code": rc, "artifact": None, "sha256": None,
                     "value": None, "severity": None, "phase": "scenario", "scenario": b["name"], "criterion": None,
                     "label": "PROVEN" if rc == 0 else "HEURISTIC", "executed_by": "cli",
                     "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "output": out[-2048:].decode("utf-8", "replace")})
        print("scenario '%s': exit %d, %.1f s" % (b["name"], rc, secs))
    tmp = "%s.tmp.%d" % (ledger, os.getpid())
    with open(tmp, "w") as f:
        json.dump(rows, f, indent=2)
    os.replace(tmp, ledger)


def main(argv):
    if len(argv) == 6 and argv[1] == "integrate":
        integrate(argv[2], argv[3], argv[4], argv[5])
        return 0
    if len(argv) == 7 and argv[1] == "group-run":   # the failure message of the group's scenario tests, '' when all pass
        print(run_owed(group_owed(tasks_md.parse(argv[3]), argv[2], argv[4]), argv[5], argv[6]))
        return 0
    if len(argv) == 5 and argv[1] == "owed":
        plan = tasks_md.parse(argv[3])
        for name, cmd in owed(plan, argv[2], int(argv[4])):
            print("%s\t%s" % (name, cmd))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
