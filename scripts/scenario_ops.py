"""scenario_ops.py: the scenario tests of a grouped Build (F8, F9). A scenario of intent.md carries a `Test:` line, a scoped
shell command that proves it on the merged tree. The commands run through run_env.py, so a credential-named variable is left
out and the folder they run in comes first on PYTHONPATH, and through its reuse store (WP22): the same test on the same tree
runs once.

  python3 scenario_ops.py owed INTENT TASKS.md N                 the scenarios Task N owes, one `name<TAB>command` per line
  python3 scenario_ops.py group-run INTENT TASKS.md G CWD TIMEOUT  run the scenarios a group owes; print the failure or nothing

Library use (task_ops.py): owed(), group_owed(), run_owed(), failure(). The run of every scenario test on the merged tree
is part of the checks when Build ends (check_run.py build-checks, WP23). Standard library only.
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


def cmd_files(cmd):
    """The project files a scenario's Test command names: each path (a word with a / or a file extension), and a dotted
    module (`unit.test_api`) as its path."""
    out = set()
    for tok in re.findall(r"[\w./-]+", cmd):
        tok = tok.strip("./") if tok.startswith("./") else tok
        if "/" in tok or re.search(r"\.[A-Za-z]{1,5}$", tok):
            out.add(tok)
        if re.fullmatch(r"[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)+", tok):
            out.add(tok.replace(".", "/") + ".py")
    return out


def owners(plan, intent_path=None):
    """{scenario name: (task n or None, group id)}: a scenario traced to one task is owed by it; traced to several, by the
    task all the others precede; else (no such task) by the group gate of the last of those tasks.

    9.8.0 (round 5): a task that writes a file the scenario's Test command runs is traced too. A Plan traced API scenarios
    to the task that builds the domain module, while their test file came with the route's later task: that task's gate
    could never pass, and the group parked three times over. Now the later task (or the group gate) owes it."""
    tracing = {}
    for t in plan["tasks"]:
        for name in traced(t):
            tracing.setdefault(name, []).append(t)
    for b in blocks(intent_path) if intent_path else []:
        if b["name"] in tracing and b["cmd"].strip():
            files = cmd_files(b["cmd"])
            for t in plan["tasks"]:
                if t not in tracing[b["name"]] and files & set(t.get("files") or []):
                    tracing[b["name"]].append(t)
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
    own = owners(plan, intent_path)
    return [(b["name"], b["cmd"]) for b in blocks(intent_path) if b["cmd"].strip() and own.get(b["name"], (0,))[0] == n]


def group_owed(plan, intent_path, gid):
    """[(name, cmd)] the group gate runs on the merged group branch: what a task of the group owes, and what has no single
    task to owe it."""
    own = owners(plan, intent_path)
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
    """Run (name, cmd) pairs; returns the first failure message, or ''. Records only a flaky pass (_flaky_row)."""
    import baseline
    for name, cmd in items:   # WP22: through the reuse store, so the same test on the same tree runs once
        info = {}
        out, rc, _ = run_env.run_cached(cwd, baseline.limit_for(cmd, timeout), [cmd], info=info)   # WP20: the limit from the base
        if rc != 0:
            return failure(name, cmd, rc, out)
        if info.get("flaky"):
            _flaky_row(name, cmd, info)
    return ""


def _flaky_row(name, cmd, info):
    """WP22 step 9: a flaky pass of an owed scenario test is a row of the Build ledger, which the commit card lists. It is
    appended under the CLI's own lock (.temper/.lock, taken as the CLI takes it); a lock not had in 10 s leaves it out."""
    import shutil
    lock, tok = os.path.join(".temper", ".lock"), "%d.%d" % (os.getpid(), int(time.time() * 1e6))
    end, nw = time.time() + 10, os.path.join(".temper", ".lock.new." + tok)
    while True:
        try:
            if not os.path.exists(lock):
                os.mkdir(nw)
                open(os.path.join(nw, "owner"), "w").write(tok)
                os.rename(nw, lock)
                if open(os.path.join(lock, "owner")).read() == tok:
                    break
        except OSError:
            pass
        shutil.rmtree(nw, ignore_errors=True)
        if time.time() > end:
            return
        time.sleep(0.02)
    try:
        p = os.path.join(".temper", "evidence", "build.json")
        try:
            rows = json.load(open(p))
        except (OSError, ValueError):
            rows = []
        rows = rows if isinstance(rows, list) else []
        rows.append(dict({"claim": "scenario test at a gate: %s" % name, "cmd": cmd, "exit_code": 0, "phase": "scenario",
                          "executed_by": "cli", "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())},
                         **run_env.row_fields(info)))
        with open(p + ".tmp.%d" % os.getpid(), "w") as fh:
            json.dump(rows, fh, indent=2)
        os.replace(p + ".tmp.%d" % os.getpid(), p)
    except OSError:
        pass
    finally:
        shutil.rmtree(lock, ignore_errors=True)


def main(argv):
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
