#!/usr/bin/env python3
"""spec_ops.py: the git steps of leaving Intent, Plan and Design, run by the CLI (9.9.0).

  spec_ops.py branch BRANCH            `temper spec branch`: switch to the run's branch (create it when it is new)
  spec_ops.py deviations SPEC          `temper spec deviations`: the deviations build-context.json records, written into
                                       plan.md as its `## Deviations` section (nothing when it records none)
  spec_ops.py commit SPEC MESSAGE [-- FILE...]
                                       `temper spec commit '<message>' [-- FILE...]`: stage the spec folder (and the files
                                       named after `--`, the run's record commit) and commit, when that holds a change

Before 9.9.0 the options that leave a stage handed the session `git checkout`, `git add` and `git commit` calls, and the
commit had to go in a Bash call of its own (the in-agent commit hook judges a commit before the call runs, so a `git add`
in the same call is not staged yet when it looks). That was two or three turns per accepted stage, each rereading the
whole conversation. Run here, the commit goes through the native pre-commit hook like any other, and every call of the
answer is a `temper` call, so the session runs them with `temper go` in one Bash call. Standard library only.
"""
import subprocess
import sys


def git(*args, check=False):
    return subprocess.run(["git"] + list(args), capture_output=True, text=True, check=check)


def branch(name):
    cur = git("rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
    if not name:
        print("FAIL: the run has no branch", file=sys.stderr)
        return 1
    if cur == name:
        print("OK: on %s" % name)
        return 0
    exists = git("show-ref", "--verify", "--quiet", "refs/heads/%s" % name).returncode == 0
    r = git("checkout", name) if exists else git("checkout", "-b", name)
    if r.returncode != 0:
        print("FAIL: git checkout %s: %s" % (name, (r.stderr or r.stdout).strip()[-300:]), file=sys.stderr)
        return 1
    print("OK: switched to %s%s" % ("" if exists else "a new branch ", name))
    return 0


def commit(spec, message, files=()):
    if not spec or not message.strip():
        print("FAIL: usage: temper spec commit '<message>' [-- FILE...]", file=sys.stderr)
        return 1
    import os
    # A named file that is not there and git does not track (a lesson file the run did not write) is left out: git add
    # would refuse the whole call for it.
    paths = [f for f in files if os.path.exists(f) or git("ls-files", "--error-unmatch", "--", f).returncode == 0] if files else [spec + "/"]
    if not paths:
        print("OK: nothing to commit")
        return 0
    r = git("add", "--", *paths)
    if r.returncode != 0:
        print("FAIL: git add -- %s: %s" % (" ".join(paths), (r.stderr or r.stdout).strip()[-300:]), file=sys.stderr)
        return 1
    if git("diff", "--cached", "--quiet").returncode == 0:
        print("OK: nothing to commit in %s" % spec)
        return 0
    r = git("commit", "-q", "-m", message)
    out = (r.stdout + r.stderr).strip()
    if r.returncode != 0:
        print("FAIL: git commit: %s" % out[-600:], file=sys.stderr)
        return 1
    head = git("log", "-1", "--format=%h %s").stdout.strip()
    print("OK: committed %s" % head)
    return 0


def deviations(spec):
    """build-context.json's deviations (unplanned files, skipped tasks, approach changes) as plan.md's `## Deviations`
    section, replacing one an earlier call wrote. Before 9.9.0 this was an instruction the session carried out itself."""
    import json
    import os
    import re
    try:
        d = (json.load(open(os.path.join(spec, "build-context.json"))) or {}).get("deviations") or {}
    except (OSError, ValueError, AttributeError):
        d = {}
    kinds = (("unplanned_files", "Files outside the plan"), ("skipped_tasks", "Tasks skipped"), ("approach_changes", "Approach changes"))
    rows = []
    for key, title in kinds:
        for x in d.get(key) or [] if isinstance(d, dict) else []:
            text = x if isinstance(x, str) else "; ".join("%s: %s" % (k, v) for k, v in x.items()) if isinstance(x, dict) else str(x)
            rows.append("- %s: %s" % (title, " ".join(str(text).split())))
    if not rows:
        print("OK: no deviations recorded")
        return 0
    path = os.path.join(spec, "plan.md")
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        print("FAIL: no plan.md in %s" % spec, file=sys.stderr)
        return 1
    text = re.sub(r"\n## Deviations\n.*?(?=\n## |\Z)", "", text, flags=re.S).rstrip("\n")
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text + "\n\n## Deviations\n\n" + "\n".join(rows) + "\n")
    os.replace(tmp, path)
    print("OK: %d deviation(s) written into plan.md" % len(rows))
    return 0


def main(argv):
    if argv[:1] == ["branch"] and len(argv) == 2:
        return branch(argv[1])
    if argv[:1] == ["deviations"] and len(argv) == 2:
        return deviations(argv[1])
    if argv[:1] == ["commit"] and len(argv) >= 3 and (len(argv) == 3 or argv[3] == "--"):
        return commit(argv[1], argv[2], argv[4:])
    print("FAIL: usage: temper spec branch | deviations | commit '<message>' [-- FILE...]", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
