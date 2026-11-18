"""approval.py: what the approval binds (9.8.5, WP12; ADR 0019 decision 4).

The person approves the intent and the plan as the question showed them. The approving calls carry the digests of
intent.md and tasks.md as they were when `temper next` built the question (`--shown intent.md=<H1> --shown
tasks.md=<H2>`), and the CLI refuses them when a file changed since. The advance records `intent_hash` beside
`plan_hash`; a later change to either file fails the row `intent unchanged since the approval` of the Build, Check and
commit gates until the person approves again.

  python3 approval.py digest FILE              the digest of intent.md (or another spec text) or of tasks.md
  python3 approval.py bound FILE               what the approval records of intent.md: its digest, or absent
  python3 approval.py row STATE SPEC           the row, one JSON line as the CLI's _req prints it
  python3 approval.py check STATE SPEC NAME=DIGEST...
                                               exit 1 with the reason when a named file of SPEC has another digest now
  python3 approval.py plan-digest PARSED_JSON  the digest of a parsed tasks.md (the CLI's _plan_digest)

Standard library only. The one plan digest lives here: the CLI, the flow (Run.plan_core_digest) and plan_patch.py
call it.
"""
import hashlib
import json
import os
import re
import sys

# Run as `python3 -I` by the CLI, which leaves this folder off the path: put it back for tasks_md.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tasks_md  # noqa: E402

ROW = "intent unchanged since the approval"
# What the approval records for a run with no intent.md (the trivial path): the row then holds intent.md absent
ABSENT = "absent"
# The lines of intent.md the CLI writes itself (`temper intent accept`, `temper intent complete`, through
# scripts/spec_text.py intent-status with the values cmd_intent of scripts/temper passes), in the forms it writes them:
# no digest holds them. Only the first line of each form is the CLI's; other text on such a line, or a second line of a
# form, is the person's and is bound. The Status line is also the line the CLI rewrites, so it takes the forms the
# Intent gate reads as a status header (the word in any case, spaces around it), never any other text.
OWN = (re.compile(r"^\*\*Status:\*\*\s*(?:draft|accepted|completed)\s*$", re.I),
       re.compile(r"^\*\*Accepted-by:\*\* the person(?:, at the plan approval| at the Intent gate)$"),
       re.compile(r"^\*\*Completed:\*\* \d{4}-\d{2}-\d{2}$"))


def without_own(lines):
    """The lines of intent.md without the CLI's own: the first line that matches each form of OWN is left out."""
    left, kept = list(OWN), []
    for l in lines:
        hit = next((rx for rx in left if rx.match(l)), None)
        if hit is None:
            kept.append(l)
        else:
            left.remove(hit)
    return kept


def intent_digest(path):
    """SHA 256 of the text of intent.md without the CLI's own lines; None when the file cannot be read."""
    try:
        with open(path, encoding="utf-8", errors="surrogateescape") as f:
            lines = f.read().split("\n")
    except OSError:
        return None
    kept = "\n".join(without_own(lines))
    return hashlib.sha256(kept.encode("utf-8", "surrogateescape")).hexdigest()


def plan_digest(m):
    """The digest of a parsed plan: each task's files, Depends and Test, each group's Depends, Validate, Interfaces,
    Context and tasks, and the Integration line. Titles, prose and checkbox ticks do not count, so the CLI's own tick
    is no change. None when the plan does not parse."""
    def n(p):
        p = p.strip()
        return p[2:] if p.startswith("./") else p
    try:
        core = {"tasks": [{"n": t["n"], "group": t["group"], "files": [n(f) for f in t["files"]],
                           "depends": t["depends"], "test": t["test"]} for t in m["tasks"]],
                "groups": [{"id": g["id"], "depends": g["depends"], "validate": g["validate"],
                            "interfaces": g["interfaces"], "context": g["context"], "tasks": g["tasks"]}
                           for g in m["groups"]],
                "integration": m["integration"]}
    except (KeyError, TypeError):
        return None
    return hashlib.sha256(json.dumps(core, sort_keys=True).encode("utf-8")).hexdigest()


def digest(path):
    """The digest of a spec file by its name: tasks.md by its parsed plan, any other (intent.md) by its text."""
    if not os.path.isfile(path):
        return None
    if os.path.basename(path) == "tasks.md":
        return plan_digest(tasks_md.parse(path))
    return intent_digest(path)


def bound(path):
    """What the approval records of intent.md: its digest, ABSENT when it is no regular file (the test of `gate intent`
    for its trivial path, so a directory or a dangling link there is absent too), None when it cannot be read."""
    return digest(path) if os.path.isfile(path) else ABSENT


def read_state(path):
    try:
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def row(name, ok, detail):
    return {"name": name, "pass": ok, "detail": detail}


def binding_row(state, spec):
    """Pass when the state holds no intent_hash key (a run saved before WP12), or when intent.md and tasks.md are as
    recorded: intent.md with the digest recorded, or still absent when the approval recorded it absent, and tasks.md
    with plan_hash when one is recorded. Else fail, naming the file that changed."""
    st = read_state(state)
    if "intent_hash" not in st:
        return row(ROW, True, "no digest was recorded at the approval (a run saved before 9.8.5)")
    want = {"intent.md": st.get("intent_hash"), "tasks.md": st.get("plan_hash")}
    changed = []
    if want["intent.md"] == ABSENT:
        if os.path.isfile(os.path.join(spec, "intent.md")):
            changed.append("intent.md")
    elif digest(os.path.join(spec, "intent.md")) != want["intent.md"]:
        changed.append("intent.md")
    if want["tasks.md"] and digest(os.path.join(spec, "tasks.md")) != want["tasks.md"]:
        changed.append("tasks.md")
    if not changed:
        return row(ROW, True, "the intent and the plan are as the person approved them")
    return row("intent unchanged since the approval", False,
               "%s changed since the approval; step back to Plan and approve again, or restore %s"
               % (" and ".join(changed), "them" if len(changed) > 1 else "it"))


def check(spec, pairs):
    """The reason a shown digest differs from the file now, or None. A pair is NAME=DIGEST, NAME a file of the spec."""
    for p in pairs:
        name, sep, want = p.partition("=")
        if not sep or not name or "/" in name or name.startswith("."):
            return "--shown takes NAME=DIGEST, NAME a file of the spec folder; got '%s'" % p
        if digest(os.path.join(spec, name)) != want:
            return "%s changed since the question was shown; ask again" % name
    return None


def main(argv):
    word = argv[1] if len(argv) > 1 else ""
    if word == "digest" and len(argv) == 3:
        d = digest(argv[2])
        if d:
            print(d)
        return 0 if d else 1
    if word == "bound" and len(argv) == 3:
        d = bound(argv[2])
        if d:
            print(d)
        return 0 if d else 1
    if word == "plan-digest" and len(argv) == 3:
        d = plan_digest(json.loads(argv[2]))
        if d:
            print(d)
        return 0 if d else 1
    if word == "row" and len(argv) == 4:
        print(json.dumps(binding_row(argv[2], argv[3])))
        return 0
    if word == "check" and len(argv) >= 4:
        why = check(argv[3], argv[4:])
        if why:
            print("FAIL: %s" % why, file=sys.stderr)
            return 1
        return 0
    print("usage: approval.py digest FILE | bound FILE | row STATE SPEC | check STATE SPEC NAME=DIGEST... "
          "| plan-digest JSON", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
