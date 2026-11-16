"""Prototype (scratch only): the four static plan rows of draft item 3c, from tasks.md, intent.md and the project tree.
usage: python3 static_rows_proto.py <repo scripts dir> <spec dir> <project dir>"""
import json, os, re, shlex, subprocess, sys
sys.path.insert(0, sys.argv[1])
import tasks_md, scenario_ops, acceptance  # the CLI's own parsers
spec, project = sys.argv[2], sys.argv[3]
plan = tasks_md.parse(os.path.join(spec, "tasks.md"))
groups, tasks = plan["groups"], plan["tasks"]
by_n = {t["n"]: t for t in tasks}
def row(name, bad, ok): print(json.dumps({"name": name, "pass": not bad, "detail": "; ".join(bad) if bad else ok}))
# 1. a group with no Validate (tasks.md alone)
row("group validate command", ["%s: no **Validate:** command" % g["id"] for g in groups if not g["validate"].strip()],
    "every group declares its Validate command")
# 2. an interface no task builds (tasks.md + the tree at HEAD)
declared = {f for t in tasks for f in t["files"]}
def at_head(path):
    r = subprocess.run(["git", "-C", project, "show", "HEAD:" + path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return r.stdout.decode("utf-8", "replace") if r.returncode == 0 else None
bad = []
for g in groups:
    for x in g["interfaces"]:
        if x["path"] in declared: continue
        text = at_head(x["path"])
        if text is None: bad.append("%s: Interfaces file %s is declared by no task and is not in the project" % (g["id"], x["path"]))
        elif x["literal"] not in text: bad.append("%s: %s lacks `%s` and no task declares the file" % (g["id"], x["path"], x["literal"]))
row("interfaces built", bad, "every Interfaces file is declared by a task, or holds its literal already")
# 3. a Traced to name the intent lacks, and a scenario no task is traced to (tasks.md + intent.md)
names = [b["name"] for b in acceptance.scenario_blocks(open(os.path.join(spec, "intent.md"), encoding="utf-8").read().splitlines())]
bad = ["Task %d: Traced to \"%s\", which intent.md does not have" % (t["n"], n) for t in tasks for n in scenario_ops.traced(t) if n not in names]
own = scenario_ops.owners(plan, os.path.join(spec, "intent.md"))
bad += ["scenario \"%s\": no task is traced to it" % n for n in names if n not in own]
row("scenarios traced", bad, "every Traced to names a scenario of the intent, and every scenario has a task")
# 4. a group check that runs another group's tests: the existing row, plus a file that is not there yet and is named exactly
gdeps = {g["id"]: g["depends"] for g in groups}
def closure(g):
    seen, stack = set(), list(gdeps.get(g, []))
    while stack:
        x = stack.pop()
        if x not in seen: seen.add(x); stack.extend(gdeps.get(x, []))
    return seen
def words(cmd):
    try: ws = shlex.split(cmd)
    except ValueError: ws = cmd.split()
    return [w.split("::", 1)[0][2:] if w.startswith("./") else w.split("::", 1)[0] for w in ws if not w.startswith("-")]
bad = []
for g in groups:
    before = closure(g["id"]) | {g["id"]}
    for w in words(g["validate"]):
        for t in tasks:
            if t["group"] and t["group"] not in before and w in t["files"] and not os.path.exists(os.path.join(project, w)):
                bad.append("%s's Validate names %s, a new file Task %d of %s writes: it is not on %s's worktree" % (g["id"], w, t["n"], t["group"], g["id"]))
row("group validate order (new files)", bad, "no Validate names a file only a later or unrelated group writes")
