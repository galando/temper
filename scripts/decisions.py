"""decisions.py: the person's decisions reach the tasks (9.8.5).

  python3 decisions.py record PROJECT SPEC QUESTION ANSWER    a `Design:` answer given after tasks.md exists: kept with
                                                              the hash tasks.md had at that moment
  python3 decisions.py row PROJECT SPEC                       the Design gate row "tasks agree with decisions" (JSON)
  python3 decisions.py prompt SPEC                            the decision lines a Build agent reads (text, may be empty)

A Design answer can replace a rule the plan wrote (a source run: the person chose "each job against its own schedule",
tasks.md kept the 24 hour rule, and three task agents built the old rule). The CLI cannot read whether a task names the
old rule. So every Build task prompt lists the Design answers, newest first, as decisions that win over tasks.md, and
the row passes with a note that names the answers given after the plan (F2 of WP08: it no longer fails until tasks.md
changes, which sent the run back to Plan and Design for an answer the plan often already had). Standard library only.
"""
import hashlib
import json
import os
import re
import sys
import time

STORE = os.path.join(".temper", "decisions.json")
PROMPT_CAP = 2400


def sha(path):
    try:
        return hashlib.sha256(open(path, "rb").read()).hexdigest()
    except OSError:
        return ""


def load(project):
    try:
        d = json.load(open(os.path.join(project, STORE), encoding="utf-8"))
        return d if isinstance(d, list) else []
    except (OSError, ValueError):
        return []


def record(project, spec, q, a):
    tasks = os.path.join(spec, "tasks.md")
    if not re.match(r"^\s*design:", q, re.I) or not os.path.isfile(tasks):
        return
    d = load(project)
    d.append({"spec": os.path.basename(os.path.normpath(spec)), "question": " ".join(q.split()), "answer": " ".join(a.split()),
              "tasks_sha": sha(tasks), "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())})
    os.makedirs(os.path.join(project, ".temper"), exist_ok=True)
    tmp = os.path.join(project, STORE + ".tmp.%d" % os.getpid())
    json.dump(d, open(tmp, "w", encoding="utf-8"), indent=2)
    os.replace(tmp, os.path.join(project, STORE))


def stale(project, spec):
    """The Design answers given after tasks.md was written, while tasks.md is still byte for byte what it was then."""
    now = sha(os.path.join(spec, "tasks.md"))
    slug = os.path.basename(os.path.normpath(spec))
    return [e for e in load(project) if e.get("spec") == slug and now and e.get("tasks_sha") == now]


def row(project, spec):
    left = stale(project, spec)
    if not left:
        return {"name": "tasks agree with decisions", "pass": True,
                "detail": "no Design answer is newer than tasks.md"}
    # F2 of WP08: the row passes with a note; the answers reach every Build task prompt (prompt below), where they win
    names = "; ".join("%s -> %s" % (e["question"][:140], e["answer"][:140]) for e in left[:4])
    return {"name": "tasks agree with decisions", "pass": True,
            "detail": "%d Design answer(s) came after the plan: %s. They go to every Build task" % (
                len(left), names + ("; and %d more" % (len(left) - 4) if len(left) > 4 else ""))}


def decision_lines(spec):
    try:
        lines = open(os.path.join(spec, "intent.md"), encoding="utf-8").read().split("\n")
    except OSError:
        return []
    out, on, lvl = [], False, 0
    for l in lines:
        h = re.match(r"^(#{1,6})\s+(.*)$", l)
        if h:
            if on and len(h.group(1)) <= lvl:
                break
            if re.match(r"decisions\s*$", h.group(2).strip(), re.I):
                on, lvl = True, len(h.group(1))
            continue
        if on and l.strip() == "---":
            break
        if on and re.match(r"^\s*[-*]\s+\S", l):
            out.append(" ".join(l.strip().lstrip("-* ").split()))
    return out


def prompt(spec):
    rows = [r for r in decision_lines(spec) if re.match(r"^design:", r, re.I)]   # the earlier ones predate the plan
    if not rows:
        return ""
    text, used = [], 0
    for r in reversed(rows):   # the newest first: the Design answers come last in the file
        if used + len(r) > PROMPT_CAP:
            text.append("(%d more in intent.md ### Decisions)" % (len(rows) - len(text)))
            break
        text.append("- " + r)
        used += len(r)
    return ("Decisions the person made at Design, after the plan (intent.md ### Decisions): where tasks.md says otherwise, "
            "the decision wins; say so in your stopped: line.\n" + "\n".join(text))


def main(argv):
    if len(argv) == 6 and argv[1] == "record":
        record(argv[2], argv[3], argv[4], argv[5])
        return 0
    if len(argv) == 4 and argv[1] == "row":
        print(json.dumps(row(argv[2], argv[3])))
        return 0
    if len(argv) == 3 and argv[1] == "prompt":
        print(prompt(argv[2]))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
