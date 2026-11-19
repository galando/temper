#!/usr/bin/env python3
"""trivial.py: a trivial request is a verdict the CLI records, and the commit hook holds its bound (9.8.5, WP17).

  python3 trivial.py --why TEXT   `temper intent trivial --why TEXT`: the verdict, only in a /temper:temper run at Intent,
                                  at step 0, with no intent.md, plan.md, tasks.md or design.md. The run state takes
                                  `trivial: {why, head, at, dirty_before}` (dirty_before: the paths with uncommitted
                                  changes at that moment) and one line is printed. The run stays active: the Intent
                                  agent's after calls still run, and the flow closes it.
  python3 trivial.py --close      `temper intent trivial --close`, the flow's own call once the Intent verdict is
                                  recorded: .temper/trivial.json (the record, with the request and the bound), one line
                                  of kind `trivial` in the kept run summary (scripts/run_summary.py), and the run
                                  cleared by `temper state clear`, which keeps that one file
  python3 trivial.py gate         the commit gate with no active run: its rows and its verdict, as gate_commit prints
                                  them (`ROWS_JSON 1|0`). A record whose head is HEAD holds the staged change to BOUND:
                                  production files outside .temper/ and outside dirty_before (a test file by the gate's
                                  own pattern does not count), and their added plus removed lines
  python3 trivial.py spent        removes a record whose head is not HEAD (`state init` and the view writer)

The bound is a constant here, with no config key: a key would let a project raise it. The CLI never commits the trivial
change; the commit is the person's. Run as `python3 -I` from the project folder. Standard library only.
"""
import datetime
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BOUND = {"files": 1, "lines": 10}
TEMPER = ".temper"
STATE = os.path.join(TEMPER, "build-state.json")
RECORD = os.path.join(TEMPER, "trivial.json")
SPEC_FILES = ("intent.md", "plan.md", "tasks.md", "design.md")
# the gate's own pattern of a test file (scripts/commit_rows.py blast_radius)
TEST = re.compile(r'(^|/)(tests?|unit|spec|__tests__)/|(^|/)test_[^/]*\.py$|_test\.(py|go)$|\.(test|spec)\.[cm]?[jt]sx?$'
                  r'|Tests?\.(java|kt|cs)$|_spec\.rb$')


def git(*args):
    try:
        r = subprocess.run(["git"] + list(args), capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return ""
    return r.stdout if r.returncode == 0 else ""


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def write(path, doc):
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)


def head():
    return git("rev-parse", "HEAD").strip()


PREFIX = []


def own(path):
    """True for a path of the run's own files (.temper/ of this project), which no bound counts."""
    if not PREFIX:
        PREFIX.append(git("rev-parse", "--show-prefix").strip())
    return path.startswith(PREFIX[0] + TEMPER + "/")


def dirty():
    """The paths with uncommitted changes now (staged, unstaged or untracked), from the top of the repository."""
    out = []
    for e in git("status", "--porcelain", "-z", "--untracked-files=all").split("\0"):
        if len(e) > 3 and not own(e[3:]):
            out.append(e[3:])
    return sorted(set(out))


def verdict(why):
    st = load(STATE)
    spec = str(st.get("spec_path") or "")
    if not why.strip():
        return fail("usage: temper intent trivial --why TEXT")
    if not st.get("next_stage"):
        return fail("no run is active")
    if (st.get("command") or "temper") != "temper" or st.get("next_stage") != "intent" or str(st.get("step") or 0) != "0":
        return fail("a trivial verdict is taken only in a /temper:temper run at Intent, before any step (this run: %s at %s, "
                    "step %s)" % (st.get("command") or "temper", st.get("next_stage"), st.get("step")))
    found = [n for n in SPEC_FILES if spec and os.path.exists(os.path.join(spec, n))]
    if found:
        return fail("the run has %s already: it is no trivial request" % ", ".join(found))
    if isinstance(st.get("trivial"), dict):
        return fail("the trivial verdict is recorded already")
    st["trivial"] = {"why": " ".join(why.split())[:300], "head": head(), "at": now(), "dirty_before": dirty()}
    write(STATE, st)
    print("OK: trivial (%s): make the one change (%d production file, %d lines at most), run the tests and return; the "
          "flow closes the run" % (st["trivial"]["why"], BOUND["files"], BOUND["lines"]))
    return 0


def close():
    st = load(STATE)
    t = st.get("trivial")
    if not isinstance(t, dict):
        return fail("no trivial verdict is recorded (temper intent trivial --why TEXT)")
    doc = {"request": st.get("feature") or st.get("spec") or "", "why": t.get("why"), "head": t.get("head"),
           "at": t.get("at"), "dirty_before": list(t.get("dirty_before") or []), "bound": dict(BOUND)}
    write(RECORD, doc)
    # `state clear` writes the run's line of runs.jsonl (of kind trivial, run_summary.summary) and keeps this file
    r = subprocess.run([os.path.join(HERE, "temper"), "state", "clear"], capture_output=True, text=True)
    if r.returncode != 0:
        return fail("state clear: %s" % (r.stderr or r.stdout).strip()[-300:])
    print("OK: the trivial request is closed; the change is not committed: the commit is yours, and the commit hook "
          "holds it to %d file and %d lines" % (BOUND["files"], BOUND["lines"]))
    return 0


def record():
    """The open record: .temper/trivial.json whose head is HEAD, or None."""
    d = load(RECORD)
    return d if d.get("head") and d.get("head") == head() else None


def say():
    """The line `temper next` says with no run active and an open record, or None."""
    d = record()
    if d is None:
        return None
    return ("No run is active. The last request was trivial (%s), and its change is not committed: the commit is yours, "
            "and the commit hook holds it to %d file and %d lines." % (d.get("why") or "no reason", BOUND["files"], BOUND["lines"]))


def spent():
    if os.path.isfile(RECORD) and record() is None:
        try:
            os.remove(RECORD)
        except OSError:
            pass
    return 0


def row(name, ok, detail):
    return {"name": name, "pass": bool(ok), "detail": detail}


def gate():
    d = record()
    if d is None:
        print(json.dumps([row("active run", True, "no active run — nothing to gate")]), 1)
        return 0
    before = set(d.get("dirty_before") or [])
    files, lines, tests = [], 0, 0
    for l in git("diff", "--cached", "--numstat", "--no-renames").splitlines():
        parts = l.split("\t", 2)
        if len(parts) != 3 or own(parts[2]) or parts[2] in before:
            continue
        if TEST.search(parts[2]):
            tests += 1
            continue
        if not (parts[0].isdigit() and parts[1].isdigit()):
            # a binary file (numstat counts `-`): its lines are not counted, so it is over the bound whatever its size
            files.append("%s (binary)" % parts[2])
            lines += BOUND["lines"] + 1
            continue
        files.append(parts[2])
        lines += sum(int(x) for x in parts[:2])
    what = "%d production file%s (%s), %d line%s%s" % (len(files), "" if len(files) == 1 else "s", ", ".join(files[:5]) or "none",
                                                      lines, "" if lines == 1 else "s", ", and %d test file(s)" % tests if tests else "")
    if len(files) <= BOUND["files"] and lines <= BOUND["lines"]:
        print(json.dumps([row("trivial exit", True, "%s: within the bound of the trivial request" % what)]), 1)
        return 0
    print(json.dumps([row("trivial exit", False, "%s staged; the trivial request allows %d file and %d lines. Commit the trivial "
                          "change alone, or start /temper:temper with the request for this change"
                          % (what, BOUND["files"], BOUND["lines"]))]), 0)
    return 0


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def fail(why):
    print("FAIL: %s" % why, file=sys.stderr)
    return 1


def main(argv):
    if len(argv) == 3 and argv[1] == "--why":
        return verdict(argv[2])
    if argv[1:] == ["--close"]:
        return close()
    if argv[1:] == ["gate"]:
        try:
            return gate()
        except Exception:   # the commit gate with no run degrades open
            print(json.dumps([row("active run", True, "no active run \u2014 nothing to gate")]), 1)
            return 0
    if argv[1:] == ["spent"]:
        return spent()
    return fail("usage: temper intent trivial --why TEXT | --close")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
