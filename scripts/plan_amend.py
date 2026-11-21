#!/usr/bin/env python3
"""plan_amend.py: `temper plan amend task N --add-file F [--failure ID]`, the plan amendment by rule (9.8.5, WP25, ADR 0019
decision 3 and ADR 0021).

  python3 plan_amend.py SPEC STATE GROUPS LEDGER task N --add-file F [--failure ID]

A task whose test needs a file its own group already owns (`temper task blocked N --needs F`, Task M of the same group
declares F) is no fault of the plan's shape: one more file on the task and one Depends entry on its owner build it. The
amendment does only that, and its whole effect is bounded here, whoever calls it: the caller passes no text, the CLI
writes Task N's **File:** line with F added and its **Depends:** line with the owner added. It refuses unless the plan
is approved (the run is past Plan) and tasks.md is that plan; a task of the same group that precedes Task N, or that
passed, declares F and F is in approved_files; F is no test file of that task, no locked acceptance test and under no
sensitive path; Task N is neither running nor passed; the result differs from the plan only in those two lines; the
static rows of the plan gate (scripts/plan_rows.py and gate_rows.py plan-rows) pass on the result where they passed
before; and the budget of WP10 has room (one repeat, the key task:N, the kind plan amend). Then it writes tasks.md in
one rename, moves plan_hash in the run state and in groups.json (so the approval still binds the plan Build runs),
appends an entry to .temper/evidence/amendments.json (the approved record, approved-tasks.json, is never written here),
writes the plan ledger row `plan amended by rule: ...` (never a person's label: the CLI cannot know who called it,
docs/trust.md), writes the rule log entry of the kind amend, and reopens Task N (its blocked mark, the group's park,
gate and failure marks go; the task runs again).

The helpers here (the static rows on a result, the record of the amendments, the reopen of a task that holds no work on
the group branch) are scripts/plan_patch.py's too. The flow asks `can` before it offers the call, so it never offers an
amendment this refuses. Run in the project folder, under the CLI's lock; standard library only.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import approval  # noqa: E402
import budget  # noqa: E402
import commit_rows  # noqa: E402
import config_yaml  # noqa: E402
import sensitive  # noqa: E402
import tasks_md  # noqa: E402

TEMPER = ".temper"
AMENDS = os.path.join(TEMPER, "evidence", "amendments.json")
CONFIG = os.path.join(".claude", "temper.config")


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def load(path, default=None):
    try:
        d = json.load(open(path, encoding="utf-8"))
        return d if isinstance(d, type(default if default is not None else {})) else default
    except (OSError, ValueError):
        return default


def save(path, d):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(d, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)


def write_text(path, text):
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


def norm(p):
    p = str(p).strip()
    return p[2:] if p.startswith("./") else p


def parse_text(text):
    fd, p = tempfile.mkstemp(suffix=".md")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        return tasks_md.parse(p)
    finally:
        os.unlink(p)


def cfg(key):
    """A config value; a key the config lacks gets the table's default (scripts/defaults.py, WP29)."""
    try:
        v = config_yaml.get(config_yaml.load(CONFIG), key)
    except Exception:
        v = ""
    return "" if v is None else v


# ---- the static rows of the plan gate, on a plan text --------------------------------------------------------------------

def _limit(name, default):
    """A byte limit of the CLI (GROUP_CONTEXT_MAX_BYTES, TASK_BLOCK_MAX_BYTES), read from scripts/temper: one source."""
    try:
        m = re.search(r"^%s=(\d+)" % name, open(os.path.join(HERE, "temper"), encoding="utf-8").read(), re.M)
        return int(m.group(1)) if m else default
    except OSError:
        return default


def static_rows(spec, text):
    """{name: (pass, detail)} of scripts/plan_rows.py and `gate_rows.py plan-rows` on the plan `text`, read from a copy of
    the spec folder, so the run's own tasks.md is never written to judge it."""
    tmp = tempfile.mkdtemp(prefix="temper-rows-")
    try:
        d = os.path.join(tmp, os.path.basename(os.path.normpath(spec)) or "spec")
        shutil.copytree(spec, d, symlinks=True, ignore=shutil.ignore_patterns("*.tmp.*"))
        write_text(os.path.join(d, "tasks.md"), text)
        blast = str(cfg("autonomy.max-blast-radius"))
        blast = blast if blast.isdigit() else "15"
        out = []
        for args in ([os.path.join(HERE, "plan_rows.py"), blast, str(_limit("GROUP_CONTEXT_MAX_BYTES", 4096)),
                      str(_limit("TASK_BLOCK_MAX_BYTES", 2048)), json.dumps(tasks_md.parse(os.path.join(d, "tasks.md"))),
                      os.getcwd()],
                     [os.path.join(HERE, "gate_rows.py"), "plan-rows", d, os.getcwd(), str(cfg("plan.context-check"))]):
            r = subprocess.run([sys.executable, "-I" if args[0].endswith("plan_rows.py") else "-s"] + args,
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
            out += r.stdout.decode("utf-8", "replace").splitlines()
        rows = {}
        for line in out:
            try:
                x = json.loads(line)
            except ValueError:
                continue
            if isinstance(x, dict) and x.get("name"):
                rows[x["name"]] = (x.get("pass"), str(x.get("detail") or ""))
        return rows
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def new_faults(spec, before_text, after_text):
    """The rows the result fails that the plan before it did not fail the same way: [(name, detail)]. A row that failed
    before with the same words was the person's to approve; a change by rule or by patch adds no fault."""
    before, after = static_rows(spec, before_text), static_rows(spec, after_text)
    return [(k, v[1]) for k, v in sorted(after.items()) if v[0] is False and before.get(k) != v]


# ---- the record of the amendments and patches ----------------------------------------------------------------------------

def append_entry(kind, what, old, new, hash_before, hash_after, failure_id=None, reopened=()):
    rows = [x for x in load(AMENDS, []) or [] if isinstance(x, dict)]
    e = {"n": len(rows) + 1, "ts": now(), "kind": kind, "what": what, "old": old, "new": new,
         "hash_before": hash_before, "hash_after": hash_after, "failure": failure_id or None, "reopened": list(reopened)}
    rows.append(e)
    save(AMENDS, rows)
    return e


def ledger_row(ledger, claim, approved):
    rows = load(ledger, []) or []
    rows.append({"claim": claim, "cmd": None, "exit_code": None, "artifact": None, "sha256": None, "value": None,
                 "severity": None, "phase": "note",
                 # before the approval the plan is checked again (an edit); after it, Build takes the note (an input)
                 "kind": "input" if approved else "edit", "scenario": None, "criterion": None, "label": "CLI", "ts": now()})
    save(ledger, rows)


def move_hashes(state, groups, h):
    """The approved plan's digest follows the change in the run state and in groups.json, so _plan_fresh holds."""
    st = load(state, {})
    st["plan_hash"] = h
    save(state, st)
    g = load(groups, None)
    if isinstance(g, dict) and g.get("plan_hash"):
        g["plan_hash"] = h
        save(groups, g)


def reopen_unbuilt(groups, n, group):
    """Task n runs again. It holds no work on the group branch (it is neither running nor passed: a failed gate merges
    nothing, an earlier reopen reverted what it had), so no file is restored and the work of the task it now depends on
    stays. Its blocked mark, the group's park, gate and failure marks go. A task that never started is left as it is.
    True when a task was reopened."""
    d = load(groups, None)
    t = ((d or {}).get("tasks") or {}).get(str(n)) if isinstance(d, dict) else None
    if not isinstance(t, dict) or (t.get("status") in (None, "pending") and not t.get("blocked")):
        return False
    import groups_ops
    import task_cover
    groups_ops.task_reopen(d, [str(n), now(), None, group], task_cover.set_status)
    g = (d.get("groups") or {}).get(group)
    if isinstance(g, dict):
        for k in ("fails", "fix_tries", "fix_empty"):
            g.pop(k, None)
    save(groups, d)
    return True


# ---- the amendment ---------------------------------------------------------------------------------------------------

def with_file(text, n, f, owners=()):
    """tasks.md with F added to Task n's first **File:** line and each owner added to its **Depends:** line; None when the
    block has no **File:** line."""
    lines = text.split("\n")
    inside, done_file, done_dep = False, False, not owners
    for i, l in enumerate(lines):
        m = re.match(r"^###\s+Task\s+(\d+)\s*:", l)
        if m:
            inside = int(m.group(1)) == n
            continue
        if re.match(r"^#{1,2}\s", l):
            inside = False
            continue
        if not inside:
            continue
        fm = re.match(r"^(\*\*Files?:\*\*)(\s*)(.*?)\s*$", l)
        if fm and not done_file:   # a path with no slash and no dot (Makefile) is read as a file only as ./Makefile
            tok = f if "/" in f or "." in f else "./" + f
            lines[i] = "%s %s`%s`" % (fm.group(1), fm.group(3) + ", " if fm.group(3) else "", tok)
            done_file = True
        dm = re.match(r"^(\*\*Depends:\*\*)\s*(.*?)\s*$", l)
        if dm and not done_dep:
            have = [int(x) for x in re.findall(r"Task\s+(\d+)", dm.group(2))]
            add = [o for o in owners if o not in have]
            if add:   # a Depends line that names the owner already stays as it is written
                lines[i] = "%s %s" % (dm.group(1), ", ".join("Task %d" % x for x in have + add))
            done_dep = True
    return "\n".join(lines) if done_file and done_dep else None


def fields(plan):
    """Every field the approval binds, task by task and group by group, and the Integration line."""
    t = {x["n"]: (x.get("group"), sorted(norm(f) for f in x.get("files") or []), sorted(x.get("depends") or []), x.get("test"))
         for x in plan.get("tasks") or []}
    g = {x["id"]: (x.get("depends"), x.get("validate"), x.get("interfaces"), x.get("context"), x.get("tasks"))
         for x in plan.get("groups") or []}
    return t, g, plan.get("integration")


def check(r, n, f):
    """(None, plan) when Task n may gain file f by rule, else (why, None): every condition but the static rows and the
    budget, which `can` and the call add. `r` is the flow's Run (or one built for the call)."""
    f = norm(f)
    st = r.state
    if not st.get("plan_hash"):
        return "the plan is not approved: an amendment changes an approved plan only", None
    if st.get("next_stage") in ("intent", "plan"):   # a step back keeps plan_hash until the next approval writes it
        return "the plan is not approved: the run is at %s again, and an amendment changes an approved plan only" % (
            st["next_stage"].capitalize()), None
    if not r.spec or not r.plan or approval.plan_digest(r.plan) != st.get("plan_hash"):
        return "tasks.md differs from the approved plan (a change since the approval): restore it, or loop back to Plan", None
    by_n = {t["n"]: t for t in r.plan.get("tasks") or []}
    t = by_n.get(n)
    if t is None:
        return "tasks.md has no Task %d" % n, None
    if f in [norm(x) for x in t.get("files") or []]:
        return "Task %d declares %s already" % (n, f), None
    owners = [m for m, x in sorted(by_n.items()) if m != n and f in [norm(y) for y in x.get("files") or []]]
    if not owners:
        return ("no other task declares %s: a file outside the approved plan is the person's (plan patch task %d "
                "--add-file %s)" % (f, n, f)), None
    own = [m for m in owners if by_n[m].get("group") == t.get("group")]
    if not own:
        return ("only a task of another group declares %s (%s): an amendment adds a file its own group %s owns, and "
                "nothing else" % (f, ", ".join("Task %d of %s" % (m, by_n[m].get("group")) for m in owners),
                                  t.get("group"))), None
    run = r.groups.get("tasks") or {}
    later = [m for m in own if m > n and (run.get(str(m)) or {}).get("status") != "passed"]
    own = [m for m in own if m not in later]   # only a task that precedes Task n, or that passed, owns it for the rule
    if not own:
        return ("only a later task of the group declares %s (%s): the plan orders it first, so loop back to Plan" % (
            f, ", ".join("Task %d" % m for m in later))), None
    if r.spec and (f + "/").startswith(norm(os.path.join(os.path.relpath(r.spec), "acceptance")) + "/"):
        return "%s is under the acceptance folder of the spec: a locked acceptance test is no task's to change" % f, None
    if commit_rows.TEST_RE.search(f):
        return "%s is a test file Task %s declares: a task never takes another task's test" % (
            f, ", ".join(str(m) for m in own)), None
    hot = [p for p in sensitive.patterns_of(r.cfg("autonomy.park-on-touch")) if sensitive.match(f, p)]
    if hot:
        return "%s is under a sensitive path (autonomy.park-on-touch: %s): nothing there changes by rule" % (f, hot[0]), None
    if f not in [norm(x) for x in st.get("approved_files") or []]:
        return "%s is not in approved_files: the file is outside what the person approved" % f, None
    status = ((r.groups.get("tasks") or {}).get(str(n)) or {}).get("status", "pending")
    if status == "running":
        return "Task %d is running: an amendment waits until its gate failed" % n, None
    if status == "passed":
        return "Task %d passed: a task that passed is not amended" % n, None
    text = open(os.path.join(r.spec, "tasks.md"), encoding="utf-8").read()
    new = with_file(text, n, f, own)
    if new is None:
        return "Task %d has no **File:** or **Depends:** line to add to" % n, None
    after = parse_text(new)
    ta, ga, ia = fields(r.plan)
    tb, gb, ib = fields(after)
    t1 = ta[n]
    want = (t1[0], sorted(t1[1] + [f]), sorted(set(t1[2]) | set(own)), t1[3])
    if ga != gb or ia != ib or set(ta) != set(tb) or tb.get(n) != want or any(ta[k] != tb[k] for k in ta if k != n):
        return "the result would change more than Task %d's files and Depends; loop back to Plan" % n, None
    return None, {"text": text, "new": new, "after": after, "owners": own}


def can(r, n, f):
    """(True, '') when `plan amend task n --add-file f` would be taken now, else (False, why). The flow asks this first."""
    why, p = check(r, n, f)
    if why:
        return False, why
    bad = new_faults(r.spec, p["text"], p["new"])
    if bad:
        return False, "the result fails the plan row %s: %s" % bad[0]
    rm = budget.room("task:%d" % n, budget.Facts(r))
    if not rm["ok"]:
        return False, budget.count_line("task:%d" % n, rm)
    return True, ""


def fail(msg):
    print("FAIL: " + msg, file=sys.stderr)
    return 1


def main(argv):
    if len(argv) < 7:
        print(__doc__, file=sys.stderr)
        return 2
    spec, state, groups, ledger = argv[1:5]
    rest = argv[5:]
    fid = ""
    if "--failure" in rest:
        i = rest.index("--failure")
        fid = rest[i + 1] if i + 1 < len(rest) else ""
        rest = rest[:i] + rest[i + 2:]
        if not re.fullmatch(r"F\d+", fid):
            return fail("--failure takes the id of a failure record (F<n>)")
    if len(rest) != 4 or rest[0] != "task" or not rest[1].isdigit() or rest[2] != "--add-file" or not rest[3].strip():
        return fail("usage: temper plan amend task N --add-file F [--failure ID] (a command line, or a file outside the "
                    "approved set, is the person's: temper plan patch)")
    n, f = int(rest[1]), norm(rest[3])
    if not os.path.isfile(state):
        return fail("no active run (temper state init)")
    from flow_run import Run
    r = Run({})
    why, p = check(r, n, f)
    if why:
        return fail(why)
    bad = new_faults(spec, p["text"], p["new"])
    if bad:
        return fail("the result fails the plan row %s: %s; tasks.md is as it was" % bad[0])
    facts = budget.Facts(r)
    rc, line = budget.spend(["plan", "amend", "task", str(n), "--add-file", f], facts)
    if rc != 0:
        return fail(line.replace("BLOCKED: ", "BLOCKED: the budget has no room: ", 1))
    path = os.path.join(spec, "tasks.md")
    write_text(path, p["new"])
    before, after = r.state.get("plan_hash"), approval.plan_digest(p["after"])
    move_hashes(state, groups, after)
    grp = next((t.get("group") for t in p["after"]["tasks"] if t["n"] == n), "")
    reopened = [n] if reopen_unbuilt(groups, n, grp) else []
    owners = ", ".join("Task %d" % m for m in p["owners"])
    what = "Task %d gains %s" % (n, f)
    append_entry("amend", what, "", f, before, after, fid, reopened)
    claim = "plan amended by rule: %s (%s %s it)" % (what, owners, "declares" if len(p["owners"]) == 1 else "declare")
    ledger_row(ledger, claim, True)
    try:
        import rule_log
        rule_log.append("amend", "build", "%s, which %s declares; the task runs again" % (what, owners))
    except Exception:
        pass
    if fid:
        try:
            import failure
            failure.set_step([fid], "amended by rule: %s" % what)
        except Exception:
            pass
    print("OK: %s; %s. %s" % (claim, "Task %d runs again" % n if reopened else "the task has not run yet", line))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
