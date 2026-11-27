"""decisions.py: the person's decisions reach the tasks (9.8.5).

  python3 decisions.py record PROJECT SPEC QUESTION ANSWER [CHOICES]   an answer given after tasks.md exists: kept with
                                                              the hash tasks.md had at that moment, and whether it was the
                                                              first choice of its Blocking line (the one the plan assumes)
  python3 decisions.py row PROJECT SPEC                       the plan gate row "tasks agree with decisions" (JSON)
  python3 decisions.py prompt SPEC                            the decision lines a Build agent reads (text, may be empty)

WP14 (ADR 0019 decision 2): what Design asked is a Blocking question Plan writes into intent.md, its first choice the
answer the tasks are written under. An answer that is the first choice passes the row with a note. Another answer can
replace a rule the plan wrote (a source run: the person chose "each job against its own schedule", tasks.md kept the 24
hour rule, and three task agents built the old rule), so it fails the row until tasks.md changes; the flow then sends
the plan back once by itself, and asks after that. Every Build task prompt lists the answers, newest first, as decisions
that win over tasks.md. Standard library only.
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


def project_of(spec):
    """The project folder of a spec folder (PROJECT/.temper/specs/SLUG), else the current folder."""
    p = os.path.abspath(spec)
    up = os.path.dirname(os.path.dirname(p))
    return os.path.dirname(up) if os.path.basename(up) == ".temper" else os.getcwd()


def norm(t):
    """The normalising of answer_ops.py, with the mark `(house rule)` taken out (the dialog's label carries it)."""
    return re.sub(r"\W+", " ", re.sub(r"\(house rule\)", " ", str(t), flags=re.I)).strip().lower()


def first_choice(choices):
    """The choice the plan assumes: the one marked `(house rule)`, which the flow shows first, else the first one."""
    cs = [c.strip().rstrip(".") for c in str(choices or "").split("|") if c.strip()]
    house = [c for c in cs if re.search(r"\(house rule\)", c, re.I)]
    return (house or cs or [""])[0]


def record(project, spec, q, a, choices=""):
    tasks = os.path.join(spec, "tasks.md")
    if not os.path.isfile(tasks) or re.match(r"^\s*context check:", q, re.I):
        return
    want = norm(first_choice(choices))
    d = load(project)
    d.append({"spec": os.path.basename(os.path.normpath(spec)), "question": " ".join(q.split()), "answer": " ".join(a.split()),
              "first": bool(want) and norm(a) == want, "tasks_sha": sha(tasks),
              "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())})
    os.makedirs(os.path.join(project, ".temper"), exist_ok=True)
    tmp = os.path.join(project, STORE + ".tmp.%d" % os.getpid())
    json.dump(d, open(tmp, "w", encoding="utf-8"), indent=2)
    os.replace(tmp, os.path.join(project, STORE))


def mine(project, spec):
    slug = os.path.basename(os.path.normpath(spec))
    return [e for e in load(project) if e.get("spec") == slug]


def stale(project, spec):
    """The answers that are not the first choice, given after tasks.md was written, while tasks.md is still byte for byte
    what it was then."""
    now = sha(os.path.join(spec, "tasks.md"))
    return [e for e in mine(project, spec) if now and e.get("tasks_sha") == now and not e.get("first")]


def named(entries, n=4):
    return "; ".join("%s -> %s" % (e["question"][:140], e["answer"][:140]) for e in entries[:n]) + (
        "; and %d more" % (len(entries) - n) if len(entries) > n else "")


def unmet(project, spec):
    """The answers the tasks do not follow yet, named in one line, or ''."""
    left = stale(project, spec)
    return named(left) if left else ""


def row(project, spec):
    left, all_ = stale(project, spec), mine(project, spec)
    if left:
        return {"name": "tasks agree with decisions", "pass": False,
                "detail": "%d answer(s) differ from the choice the plan assumes, and tasks.md has not changed since: %s. "
                          "Revise the plan so the tasks follow them" % (len(left), named(left))}
    if not all_:
        return {"name": "tasks agree with decisions", "pass": True, "detail": "no answer is newer than tasks.md"}
    firsts = [e for e in all_ if e.get("first")]
    return {"name": "tasks agree with decisions", "pass": True,
            "detail": "%d answer(s) came after the plan, %d of them the first choice the tasks were written under%s: %s. "
                      "They go to every Build task" % (len(all_), len(firsts),
                                                        "" if len(firsts) == len(all_) else ", tasks.md changed since the others",
                                                        named(all_))}


def prompt(spec, project=None):
    """The answers of the store for this spec, newest first, as decisions that win over tasks.md."""
    rows = ["%s -> %s" % (e.get("question"), e.get("answer")) for e in mine(project or project_of(spec), spec)]
    if not rows:
        return ""
    text, used = [], 0
    for r in reversed(rows):   # the newest first
        if used + len(r) > PROMPT_CAP:
            text.append("(%d more in intent.md ### Decisions)" % (len(rows) - len(text)))
            break
        text.append("- " + r)
        used += len(r)
    return ("Decisions the person made after the plan was written (intent.md ### Decisions): where tasks.md says otherwise, "
            "the decision wins; say so in your stopped: line.\n" + "\n".join(text))


def main(argv):
    if len(argv) in (6, 7) and argv[1] == "record":
        record(*argv[2:])
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
