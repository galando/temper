#!/usr/bin/env python3
"""group_keep.py: a replan keeps the built tasks whose approved fields did not change (9.8.5, WP25).

  python3 -I group_keep.py archive GROUPS     `_groups_reset`, at a step back before Build: stamps groups.json with the
                                              run's id and the plan its tasks were built from (tasks.md as approved),
                                              then prints the rows of `groups_ops.py groups-reset-rows`
  python3 -I group_keep.py keep GROUPS        `temper group keep`, the first Build action after the new approval:
                                              restores each kept task and its group branch, once per replan

A step back to Plan archives groups.json to .temper/archive/groups-<ts>.json and moves each group branch to
refs/temper/kept/<slug>/replan-<ts>/<G> (scripts/temper `_groups_reset`). After the new approval a task is kept when its
files, Depends and Test are those of the archived plan, every task it depends on is kept, and its group's Depends, and
the groups those name, are unchanged and fully kept. A group's branch comes back from its kept ref, reset to the commit
of the last kept task in the order the branch holds them: the walk stops at the first commit that is not a kept task's,
so the branch holds only the CLI's own commits of kept tasks. Those task records come back as passed, with their entries
of cli_commits; the group's gate verdict is kept only when every task of it is kept, nothing followed them on the branch,
and its Validate and Interfaces are equal. Everything else runs as a new group does. A task block's text is never
compared (the CLI ticks a box inside it): the fields of the digest are. Run in the project folder; standard library only.
"""
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import approval  # noqa: E402
import tasks_md  # noqa: E402

TEMPER = ".temper"
STATE = os.path.join(TEMPER, "build-state.json")
KEPT = "refs/temper/kept/"


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


def git(*args):
    r = subprocess.run(["git"] + list(args), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return r.returncode, r.stdout.decode("utf-8", "replace").strip()


def norm(p):
    p = str(p).strip()
    return p[2:] if p.startswith("./") else p


def task_fields(t):
    return (sorted(norm(f) for f in t.get("files") or []), sorted(t.get("depends") or []), t.get("test"))


def archive(argv):
    """Stamp groups.json with the run's id and the plan as approved, then print the reset rows."""
    path = argv[1]
    d = load(path, {})
    st = load(STATE, {})
    spec = st.get("spec_path") or ""
    tasks = os.path.join(spec, "tasks.md") if spec else ""
    if d and st.get("run_id") and tasks and os.path.isfile(tasks):
        plan = tasks_md.parse(tasks)
        want = d.get("plan_hash") or st.get("plan_hash")
        if want and approval.plan_digest(plan) == want:   # only the plan the tasks were built from is kept for a replan
            d["run_id"] = st["run_id"]
            d["plan"] = {"tasks": plan["tasks"], "groups": plan["groups"], "integration": plan["integration"]}
            for t in d["plan"]["tasks"]:
                t.pop("block", None)
            save(path, d)
    import groups_ops
    groups_ops.groups_reset_rows(argv)
    return 0


def latest(state, groups):
    """(ts, archived groups.json) of this run's latest replan that `group keep` has not read yet, else None."""
    rid = state.get("run_id")
    if not rid:
        return None
    folder = os.path.join(TEMPER, "archive")
    try:
        names = [n for n in os.listdir(folder) if n.startswith("groups-") and n.endswith(".json")]
    except OSError:
        names = []
    for name in sorted(names, reverse=True)[:20]:
        p = os.path.join(folder, name)
        d = load(p, {})
        if d.get("run_id") == rid and isinstance(d.get("plan"), dict):
            ts = os.path.basename(p)[len("groups-"):-len(".json")]
            return None if groups.get("kept_from") == ts else (ts, d)
    return None


def pending(state, groups):
    """True when the first Build action after a replan's approval is `temper group keep`: this run archived a plan at a
    step back, and Build has not started a task since."""
    tasks = groups.get("tasks") or {}
    if any(isinstance(t, dict) and t.get("status") not in (None, "pending") for t in tasks.values()):
        return False
    return latest(state, groups) is not None


def keep_set(plan, doc, ts, slug):
    """{G: {"tasks": [n...], "commit": sha, "full": bool, "gate": bool}} of what the new plan keeps of the archive."""
    old = doc.get("plan") or {}
    otasks = {t["n"]: t for t in old.get("tasks") or []}
    ogroups = {g["id"]: g for g in old.get("groups") or []}
    rec = doc.get("tasks") or {}
    ogs = doc.get("groups") or {}
    ntasks = {t["n"]: t for t in plan.get("tasks") or []}
    groups = list(plan.get("groups") or [])
    out, full, kept = {}, {}, set()
    todo = list(groups)
    while todo:
        ready = [g for g in todo if all(d in full for d in g.get("depends") or [])] or todo[:1]
        for g in ready:
            todo.remove(g)
            gid, og = g["id"], ogroups.get(g["id"])
            full[gid] = False
            if not og or sorted(og.get("depends") or []) != sorted(g.get("depends") or []) or \
                    not all(full.get(d) for d in g.get("depends") or []):
                continue
            e = ogs.get(gid) or {}
            ref = KEPT + "%s/replan-%s/%s" % (slug, ts, gid)
            base = e.get("base_sha") or ""
            rc, head = git("rev-parse", "--verify", "-q", ref)
            if rc != 0 or not base or git("merge-base", "--is-ancestor", base, ref)[0] != 0:
                continue
            commits = git("rev-list", "--first-parent", "--reverse", "%s..%s" % (base, ref))[1].split()
            by_commit = {str(r.get("commit")): int(n) for n, r in rec.items() if isinstance(r, dict) and n.isdigit()
                         and r.get("status") == "passed" and r.get("group") == gid and r.get("commit")}
            mine, last = [], ""
            for c in commits:
                n = by_commit.get(c)
                t, o = ntasks.get(n), otasks.get(n)
                if n is None or not t or not o or t.get("group") != gid or o.get("group") != gid \
                        or task_fields(t) != task_fields(o) or not all(d in kept or d in mine for d in t.get("depends") or []):
                    break
                mine.append(n)
                last = c
            if not mine:
                continue
            kept.update(mine)
            whole = sorted(mine) == sorted(g.get("tasks") or []) and last == head
            full[gid] = whole
            same = (og.get("validate") == g.get("validate") and og.get("interfaces") == g.get("interfaces"))
            out[gid] = {"tasks": mine, "commit": last, "full": whole,
                        "gate": whole and same and (e.get("gate") or {}).get("verdict") == "PASS"}
    return out


def count(state, groups, plan):
    """How many built tasks the replan keeps, for the approval card; None when no replan waits."""
    hit = latest(state, groups)
    if hit is None:
        return None
    ts, doc = hit
    return sum(len(x["tasks"]) for x in keep_set(plan, doc, ts, doc.get("slug") or "").values())


def keep(argv):
    path = argv[1]
    st = load(STATE, {})
    g = load(path, {})
    hit = latest(st, g)
    if hit is None:
        print("OK: no replan to keep anything of")
        return 0
    ts, doc = hit
    spec = st.get("spec_path") or ""
    plan = tasks_md.parse(os.path.join(spec, "tasks.md")) if spec else {}
    slug = doc.get("slug") or ""
    started = any(isinstance(t, dict) and t.get("status") not in (None, "pending") for t in (g.get("tasks") or {}).values())
    approved = bool(plan) and st.get("plan_hash") and approval.plan_digest(plan) == st.get("plan_hash")
    ks = keep_set(plan, doc, ts, slug) if approved and not started and slug else {}
    g.setdefault("version", 1)
    g["kept_from"] = ts
    kept = []
    for gid, k in sorted(ks.items()):
        branch = "temper/%s/%s" % (slug, gid)
        if git("show-ref", "--verify", "--quiet", "refs/heads/" + branch)[0] == 0 or \
                git("branch", branch, k["commit"])[0] != 0:
            continue   # a branch of that name is left (a worktree with uncommitted work kept it): nothing of it is kept
        e = (doc.get("groups") or {}).get(gid) or {}
        rec = {"status": "passed" if k["gate"] else "running", "branch": branch, "base_sha": e.get("base_sha"),
               "started_at": e.get("started_at"), "finished_at": e.get("finished_at") if k["gate"] else None,
               "kept": {"from": ts, "tasks": k["tasks"]}}
        if k["gate"]:
            rec["gate"] = e.get("gate")
        g.setdefault("groups", {})[gid] = rec
        for n in k["tasks"]:
            t = dict((doc.get("tasks") or {}).get(str(n)) or {})
            t.pop("worktree", None)
            t.pop("branch", None)
            g.setdefault("tasks", {})[str(n)] = t
            if t.get("commit") and t["commit"] not in g.setdefault("cli_commits", []):
                g["cli_commits"].append(t["commit"])
            kept.append(n)
    if kept:
        g["slug"] = slug
        g.setdefault("feature_branch", doc.get("feature_branch"))
        g["plan_hash"] = st.get("plan_hash")
    save(path, g)
    if kept:
        import spec_text
        for n in sorted(kept):   # the CLI's own tick, as a pass writes it; no digest counts it
            try:
                spec_text.task_box(["task-box", os.path.join(spec, "tasks.md"), str(n), "x"])
            except Exception:
                pass
    try:   # a rule's step after the approval: the commit card lists it (written only while the run goes on by itself)
        import rule_log
        rule_log.append("advance", "build", "the replan keeps %d built task%s whose approved fields did not change" % (
            len(kept), "" if len(kept) == 1 else "s"))
    except Exception:
        pass
    print("OK: the replan keeps %d built task%s%s; the others run as new" % (
        len(kept), "" if len(kept) == 1 else "s", " (%s)" % ", ".join("Task %d" % n for n in sorted(kept)) if kept else ""))
    return 0


def main(argv):
    if len(argv) == 3 and argv[1] in ("archive", "keep"):
        return {"archive": archive, "keep": keep}[argv[1]](argv[1:])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
