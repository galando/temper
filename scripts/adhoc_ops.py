"""adhoc_ops.py: the small-change window (F14). A person changes a little at Build, Review, Check or Commit (or Pipeline)
without a loop back; the window records what changed so the run re-runs only what the change touches.

  python3 adhoc_ops.py open STATE STAGE REASON     start the window: the base commit and the hash of each changed file
  python3 adhoc_ops.py close STATE                 end it: record the files changed since the open, and the steps that re-run
  python3 adhoc_ops.py step STATE NAME             an orchestrator gate for step NAME ran: mark it done

The run state is the JSON file the CLI keeps (STATE). Under `adhoc` while the window is open; under `adhoc_done` once
closed, with the steps still to run. A step is `review` (the Review agent over the changed files, then its gate), `check`
or `commit` (their gates) or `gate` (only the stage's own gate: a change of docs only, or a change made at Build).
Standard library only.
"""
import hashlib
import json
import os
import subprocess
import sys
import time

STAGES = ("build", "review", "check", "commit", "pipeline")
DOC_DIRS = ("docs/", "doc/")
DOC_EXT = (".md", ".rst", ".txt")


def load(path):
    try:
        d = json.load(open(path, encoding="utf-8"))
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def save(path, d):
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(d, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)


def git(*args):
    r = subprocess.run(["git"] + list(args), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return r.stdout.decode("utf-8", "surrogateescape") if r.returncode == 0 else ""


def internal(p):
    return p.startswith(".temper/") or p.startswith(".claude/worktrees/")


def dirty():
    """{path: sha256 or 'DELETED'} of every dirty or untracked path of the work tree, run state left out."""
    out = {}
    ents = git("status", "--porcelain=v1", "-z", "-uall").split("\0")
    i = 0
    while i < len(ents):
        e = ents[i]
        i += 1
        if len(e) < 4:
            continue
        path = e[3:]
        if e[0] in "RC":
            i += 1
        if internal(path):
            continue
        try:
            out[path] = hashlib.sha256(open(path, "rb").read()).hexdigest() if os.path.isfile(path) else "DELETED"
        except OSError:
            out[path] = "DELETED"
    return out


def is_doc(p):
    return p.startswith(DOC_DIRS) or p.lower().endswith(DOC_EXT) or os.path.basename(p).lower().startswith(("readme", "changelog"))


def open_window(state_path, stage, reason):
    if stage not in STAGES:
        raise ValueError("--stage takes one of: %s" % ", ".join(STAGES))
    if not reason.strip():
        raise ValueError("a small change needs a reason (--reason '<why>')")
    d = load(state_path)
    if d.get("adhoc"):
        raise ValueError("a small change is open already (at %s); run temper adhoc close first" % d["adhoc"].get("stage"))
    d["adhoc"] = {"stage": stage, "reason": reason.strip(), "base": git("rev-parse", "HEAD").strip(), "files": dirty(),
                  "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    d.pop("adhoc_done", None)
    save(state_path, d)
    return d["adhoc"]


def steps_for(stage, files):
    """What a change made at the stage re-runs. A doc only change, and a change made at Build, re-run only the stage's own
    gate; a code change at Review re-runs Review; at Check or Commit, Review of the changed files, then Check, then the
    commit gate. A change made at Pipeline (a CI fix, already pushed) re-runs nothing: `state redo pipeline`, which the fix ends
    with, makes the Pipeline stage read the checks again."""
    if stage == "pipeline":
        return []
    if not files or all(is_doc(f) for f in files) or stage == "build":
        return ["gate"]
    if stage == "review":
        return ["review"]
    return ["review", "check", "commit"]


def close_window(state_path):
    d = load(state_path)
    w = d.get("adhoc")
    if not w:
        raise ValueError("no small change is open (temper adhoc open --stage <stage> --reason '<why>')")
    now = dirty()
    changed = set()
    for p, h in now.items():
        if w["files"].get(p) != h:          # edited since the open, or a new dirty file
            changed.add(p)
    for p in w["files"]:
        if p not in now:                     # restored since the open
            changed.add(p)
    if w.get("base"):                        # committed since the open
        changed |= {p for p in git("diff", "--name-only", "--no-renames", w["base"], "HEAD").split("\n") if p and not internal(p)}
    files = sorted(changed)
    done = {"stage": w["stage"], "reason": w["reason"], "files": files, "doc_only": bool(files) and all(is_doc(f) for f in files),
            "steps": steps_for(w["stage"], files), "closed": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    d.pop("adhoc", None)
    if done["steps"]:
        d["adhoc_done"] = done
    else:
        d.pop("adhoc_done", None)
    save(state_path, d)
    return done


def mark_step(state_path, name):
    d = load(state_path)
    done = d.get("adhoc_done")
    if not done or name not in done.get("steps", []):
        return False
    done["steps"] = [s for s in done["steps"] if s != name]
    if not done["steps"]:
        d.pop("adhoc_done", None)
    save(state_path, d)
    return True


def main(argv):
    try:
        if len(argv) == 5 and argv[1] == "open":
            w = open_window(argv[2], argv[3], argv[4])
            print("OK: small change open at %s (%s); make the change, run temper adhoc close, then temper next --json" % (w["stage"], w["reason"]))
            return 0
        if len(argv) == 3 and argv[1] == "close":
            done = close_window(argv[2])
            print("OK: small change closed: %d file(s) changed%s; still to run: %s" % (
                len(done["files"]), " (docs only)" if done["doc_only"] else "", ", ".join(done["steps"]) or "nothing here (the Pipeline stage reads the checks again)"))
            return 0
        if len(argv) == 4 and argv[1] == "step":
            mark_step(argv[2], argv[3])
            return 0
    except ValueError as e:
        print("FAIL: %s" % e, file=sys.stderr)
        return 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
