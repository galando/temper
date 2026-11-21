"""plan_patch.py: `temper plan patch`, the person's change of one command line of the plan (9.8.5, S6; WP21: also
before the approval, as the answer at plan.command, when the plan's line changes and no hash moves; WP25: a file outside
the approved set).

  python3 plan_patch.py SPEC STATE GROUPS LEDGER G<n> --cmd '<command>'        a group's **Validate:** line (inserted
                                                                              after its **Depends:** line, or its head,
                                                                              when it has none)
  python3 plan_patch.py SPEC STATE GROUPS LEDGER task <N> --cmd '<command>'    a task's **Test:** line
  python3 plan_patch.py SPEC STATE GROUPS LEDGER integration --cmd '<command>' the plan's **Integration:** line
  python3 plan_patch.py SPEC STATE GROUPS LEDGER task <N> --add-file F         a file on Task N's **File:** line, and in
                                                                              approved_files

A wrong command line (a suite that cannot finish in the time limit, a filter that can never meet a coverage rule) used to
need a loop back to Plan: Plan, Design and every passed task again, and the run's one loop. A patch changes that one
line of tasks.md and nothing else, keeps every passed task, and spends no loop. It is the person's (the mod lets only
the answer to the CLI's question run it). The approved plan's hash moves with it, so Build does not refuse the plan;
the plan ledger records the old and the new line; a patched group's check runs again, with its failure marks reset.
WP25: the static rows of the plan gate run on the result first, and a row the result newly fails refuses the patch with
tasks.md as it was; the budget is spent here, once every check holds (one repeat: group:<G>, task:<N> or gate:build); an
approved plan's patch is appended to .temper/evidence/amendments.json (the approved record is never written); a passed
task whose Test line changed is reopened (the CLI's group reopen runs after this, on the REOPEN line it prints; a patch
whose reopen could not run, for any refusal of that reopen, is refused first, before anything is written or spent); a task
that gained a file and is neither running nor passed runs again. The ledger row says what changed, never who called: the
CLI cannot know it (docs/trust.md; with the mod, only the person's answer runs it). Standard library only.
"""
import json
import os
import re
import sys
import time

import approval
import budget
import plan_amend
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
        # a group's own lines end at its first task's head, a task's lines at the next head
        end = next((i for i in range(start + 1, len(lines)) if re.match(r"^#{1,3}\s", lines[i])), len(lines))
    for i in range(start, end):
        m = re.match(r"^(\s*\*\*%s:\*\*\s*)`([^`]*)`(.*)$" % key, lines[i])
        if m:
            old = m.group(2)
            lines = list(lines)
            lines[i] = "%s`%s`%s" % (m.group(1), cmd, m.group(3))
            return lines, old
    if target == "group":   # WP25: a group with no Validate line gets one, after its **Depends:** line (or its head)
        dep = next((i for i in range(start, end) if re.match(r"^\s*\*\*Depends:\*\*", lines[i])), start)
        return list(lines[:dep + 1]) + ["**Validate:** `%s`" % cmd] + list(lines[dep + 1:]), ""
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
        return fail("usage: temper plan patch G<n>|task <N>|integration --cmd '<command>' | task <N> --add-file F")
    add = target == "task" and len(rest) == 2 and rest[0] == "--add-file"
    if add:
        if not num.isdigit() or not plan_amend.norm(rest[1]) or "`" in rest[1] or re.search(r"[\s*?\[]", rest[1]):
            return fail("temper plan patch task <N> --add-file F takes one exact path")
        cmd = plan_amend.norm(rest[1])
    else:
        if len(rest) != 2 or rest[0] != "--cmd":
            return fail("temper plan patch needs --cmd '<command>' (or task <N> --add-file F)")
        cmd = " ".join(rest[1].split())
        if not cmd or len(cmd) > MAX_CMD or "`" in cmd:
            return fail("the command is one line of at most %d characters, with no backquote" % MAX_CMD)
    st = load(state)
    if st is None:
        return fail("no active run (temper state init)")
    # WP21: before the approval, the answer at plan.command changes the plan's line (a step back to Plan keeps plan_hash
    # until the next approval writes it: the run at Plan is before an approval too)
    approved = bool(st.get("plan_hash")) and st.get("next_stage") not in ("intent", "plan")
    path = os.path.join(spec, "tasks.md")
    text = open(path, encoding="utf-8").read()
    lines = text.split("\n")
    if add:
        plan = tasks_md.parse(path)
        t = next((x for x in plan["tasks"] if str(x["n"]) == num), None)
        if t is None:
            return fail("tasks.md has no Task %s" % num)
        if cmd in [plan_amend.norm(x) for x in t.get("files") or []]:
            return fail("Task %s declares %s already" % (num, cmd))
        new_text, old = plan_amend.with_file(text, int(num), cmd), ""
        if new_text is None:
            return fail("Task %s has no **File:** line to add to" % num)
        new = new_text.split("\n")
    else:
        new, old = patch_lines(lines, target, num, cmd)
        if new is None:
            return fail(old)
    if approved and digest(tasks_md.parse(path)) != st.get("plan_hash"):
        return fail("tasks.md differs from the approved plan in more than this line; loop back to Plan")
    got = plan_amend.parse_text("\n".join(new))   # the plan must read the change as the call wrote it
    if (add and cmd not in [plan_amend.norm(f) for t in got["tasks"] if str(t["n"]) == num for f in t.get("files") or []]) or \
            (target == "group" and next((x.get("validate") for x in got["groups"] if x["id"] == num), None) != cmd):
        return fail("the plan would not read %s as written there; tasks.md is as it was" % cmd)
    if approved and target == "task" and not add:   # the CLI's group reopen runs after this call: what refuses it, first
        why = reopen_refusal(groups, num, got, spec)
        if why:
            return fail("%s; tasks.md is as it was" % why)
    bad = plan_amend.new_faults(spec, text, "\n".join(new))
    if bad:
        return fail("the result fails the plan row %s: %s; tasks.md is as it was" % bad[0])
    words = ["plan", "patch"] + (["task", num] if target == "task" else [num] if target == "group" else ["integration"])
    rc, line = budget.spend(words, budget.Facts())
    if rc != 0:
        return fail(line.replace("BLOCKED: ", "BLOCKED: the budget has no room: ", 1))
    before = st.get("plan_hash")
    plan_amend.write_text(path, "\n".join(new))
    after = tasks_md.parse(path)
    h = digest(after)
    if approved:
        st["plan_hash"] = h
    if add and cmd not in (st.get("approved_files") or []):
        st["approved_files"] = list(st.get("approved_files") or []) + [cmd]
    save(state, st)
    g = load(groups) if approved else None
    reopen, again = [], []
    if g is not None:
        if g.get("plan_hash"):
            g["plan_hash"] = h
        gs = g.get("groups") or {}
        tasks = g.get("tasks") or {}
        gid = num if target == "group" else next((x.get("group") for x in after["tasks"] if str(x["n"]) == num), None)
        if target == "group" and isinstance(gs.get(num), dict):
            gs[num].pop("gate", None)   # the patched group's check runs again
            for k in ("fails", "fix_tries", "fix_empty"):   # U1: and the marks of its earlier failures go with it
                gs[num].pop(k, None)
        if target == "integration":
            g.pop("integration", None)
        save(groups, g)
        st_n = ((tasks.get(num) or {}).get("status") or "pending") if target == "task" else ""
        if target == "task" and not add and st_n == "passed" and gid:
            reopen = [int(num)] + reopen_with(after, g, int(num))   # a new Test line: the task is built against it again
        elif add and gid and st_n not in ("passed", "running") and plan_amend.reopen_unbuilt(groups, int(num), gid):
            again = [int(num)]
    what = {"group": "%s Validate" % num, "task": "Task %s Test" % num, "integration": "Integration"}[target]
    if add:
        what = "Task %s gains %s" % (num, cmd)
    if approved:
        plan_amend.append_entry("patch", what, old, cmd, before, h, None, reopen + again)
    claim = "plan patch: %s" % what if add else "plan patch: %s: `%s` -> `%s`" % (what, old, cmd)
    plan_amend.ledger_row(ledger, claim, approved)
    if add:
        print("OK: %s, and it is in the approved files; %s %s" % (what, "the task runs again." if again else "", line))
    else:
        print("OK: %s is now `%s` (was `%s`); the passed tasks keep their work. %s" % (what, cmd, old or "none", line))
    if reopen:
        print("REOPEN: %s %s" % (gid, " ".join("--task %d" % n for n in reopen)))
    return 0


def reopen_refusal(groups, num, plan, spec=""):
    """Why the group reopen of passed Task num, whose Test line the patch changes, could not run (the group has no
    worktree, scripts/task_ops.py reopencheck refuses, or one of the reopen's other refusals: reopen_more), checked before
    anything is written or spent; None when it can run or no reopen is needed."""
    g = load(groups) or {}
    if ((g.get("tasks") or {}).get(num) or {}).get("status") != "passed":
        return None
    gid = next((x.get("group") for x in plan["tasks"] if str(x["n"]) == num), None)
    if not gid:
        return None
    if not ((g.get("groups") or {}).get(gid) or {}).get("worktree"):
        return ("Task %s passed and must be built again against the new Test line, but group %s is not started: its "
                "reopen cannot run" % (num, gid))
    import subprocess
    r = subprocess.run([sys.executable, "-E", "-s", os.path.join(os.path.dirname(os.path.abspath(__file__)), "task_ops.py"),
                        "reopencheck", json.dumps(plan), groups, gid] + [str(n) for n in [int(num)] + reopen_with(plan, g, int(num))],
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, stdin=subprocess.DEVNULL)
    if r.returncode != 0:
        lines = r.stderr.decode("utf-8", "replace").strip().splitlines() or ["reopencheck failed"]
        return "the reopen of Task %s cannot run: %s" % (num, lines[-1].replace("FAIL: ", "", 1))
    return reopen_more(groups, gid, num, spec)


def reopen_more(groups, gid, num, spec):
    """The other refusals of the CLI's group reopen (scripts/temper _group_reopen_body), checked here too (lane E): an
    upstream gate the reopen commit needs (ADR 0009: plan, and intent and design where their files exist, passed or
    skipped by the person), and a commit the CLI did not record and nobody accepted on the group's branch or a kept task
    worktree of the group (groups_ops parked-foreign, task_ops foreigncheck). None when the reopen can run."""
    import subprocess
    here = os.path.dirname(os.path.abspath(__file__))
    temper = os.path.dirname(os.path.abspath(groups))
    gates = load(os.path.join(temper, "gates.json")) or {}

    def py(script, *args):
        return subprocess.run([sys.executable, "-I", os.path.join(here, script)] + list(args), stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, stdin=subprocess.DEVNULL)
    missing = [st for st in ("plan", "intent", "design") if (st == "plan" or os.path.isfile(os.path.join(spec or "", st + ".md")))
               and (gates.get(st) or {}).get("verdict") != "PASS"
               and py("commit_rows.py", "override-covers", os.path.join(temper, "overrides.json"), os.path.join(temper, "gates.json"), st).returncode != 0]
    if missing:
        return "the reopen of Task %s cannot run: its commit needs the upstream gate(s) %s passed (ADR 0009)" % (num, " ".join(missing))
    left = py("groups_ops.py", "parked-foreign", groups, gid).stdout.decode("utf-8", "replace").strip() or "[]"
    wt = ((load(groups) or {}).get("groups") or {}).get(gid, {}).get("worktree") or ""
    kept = py("groups_ops.py", "kept-worktrees", groups, gid).stdout.decode("utf-8", "replace").split("\n")
    for w in [wt] + [k for k in kept if k.strip() and os.path.isdir(k.strip())]:
        r = subprocess.run([sys.executable, "-E", "-s", os.path.join(here, "task_ops.py"), "foreigncheck", os.path.abspath(w.strip()), left, "",
                            groups, gid], stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.DEVNULL)
        bad = [x.split()[1][:7] for x in r.stdout.decode("utf-8", "replace").splitlines() if x.split()[:1] in (["ON"], ["UNK"], ["BAD"])]
        if r.returncode != 0 or bad:
            return ("the reopen of Task %s cannot run: group %s holds commit(s) that the CLI did not record and nobody accepted: %s"
                    % (num, gid, " ".join(bad) or r.stderr.decode("utf-8", "replace").strip()[-200:]))
    return None


def reopen_with(plan, run, n):
    """The tasks that must reopen with Task n (the rule of the group reopen): a task of its group that ran, depends on it,
    directly or not, and shares a declared file with it."""
    by_n = {t["n"]: t for t in plan["tasks"]}
    grp = (by_n.get(n) or {}).get("group")

    def ups(m, seen):
        out = set()
        for d in (by_n.get(m) or {}).get("depends") or []:
            if d not in seen:
                out |= {d} | ups(d, seen | {d})
        return out
    out = []
    for m, t in sorted(by_n.items()):
        st = ((run.get("tasks") or {}).get(str(m)) or {}).get("status")
        if m != n and t.get("group") == grp and st in ("passed", "running") and n in ups(m, {m}) \
                and set(t.get("files") or []) & set(by_n[n].get("files") or []):
            out.append(m)
    return out


if __name__ == "__main__":
    sys.exit(main(sys.argv))
