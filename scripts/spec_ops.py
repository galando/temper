#!/usr/bin/env python3
"""spec_ops.py: the git steps of leaving Intent, Plan and Design, run by the CLI (9.8.0).

  spec_ops.py WORD BRANCH SPEC ARG...  BRANCH and SPEC are the run's branch and spec folder ('' with no run):
  spec_ops.py branch BRANCH SPEC [--carry NAME | --if-protected] [--shown NAME=DIGEST...]
                                       `temper spec branch`: switch to the run's branch (create it when it is new);
                                       with --carry NAME (WP16), switch to the branch NAME an earlier run left, and
                                       carry the spec files across through a temp folder (never git stash, whose stack
                                       every worktree shares); with --if-protected (WP16, a fix run), switch to the
                                       run's branch only from main, master or the default branch, and on any other
                                       branch record that branch as the run's and switch nothing
  spec_ops.py deviations BRANCH SPEC   `temper spec deviations`: the deviations build-context.json records, written to
                                       deviations.md in the spec folder (WP26; nothing when it records none)
  spec_ops.py commit BRANCH SPEC MESSAGE [--shown NAME=DIGEST...] [-- FILE...]
                                       `temper spec commit '<message>' [-- FILE...]`: stage the spec folder (and the files
                                       named after `--`, the run's record commit) and commit, when that holds a change

Earlier the options that leave a stage handed the session `git checkout`, `git add` and `git commit` calls, and the
commit had to go in a Bash call of its own (the in-agent commit hook judges a commit before the call runs, so a `git add`
in the same call is not staged yet when it looks). That was two or three turns per accepted stage, each rereading the
whole conversation. Run here, the commit goes through the native pre-commit hook like any other, and every call of the
answer is a `temper` call, so the session runs them with `temper go` in one Bash call. Standard library only.

Rule 1 (row D30): before the approval (a /temper:temper run at Intent or Plan, a fix run at its root cause) `branch` and
`commit` are refused unless the approving answer's first call passed its digest check at this step (scripts/approval.py
held): the approval's own calls go on, and no other branch or commit is made before it. The approving option carries the
digests of what its question showed (`--shown NAME=DIGEST`, WP12) on its `branch` and `commit` calls too, and each of
them checks them again before it acts (R2-4): so a stale approval fails on its own every call of it runs, also when the
session ran them as one shell call that does not stop at the first failure.
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


def carry(spec, name, run_branch=""):
    """The spec folder to a temp folder, the folder back to HEAD, the switch, the files back. A refused switch puts the
    files back too, fails, and names the temp folder, which keeps a copy. NAME is the run's own branch, an existing
    one: never a path, whose edits a checkout would discard."""
    import os
    import shutil
    import tempfile
    if not spec or not name or not os.path.isdir(spec):
        print("FAIL: usage: temper spec branch --carry NAME (with an active run)", file=sys.stderr)
        return 1
    if name != run_branch or git("show-ref", "--verify", "--quiet", "refs/heads/%s" % name).returncode != 0:
        print("FAIL: spec branch --carry switches only to the run's branch, a branch that exists (the run's: %s); "
              "got '%s'" % (run_branch or "none", name), file=sys.stderr)
        return 1
    t = tempfile.mkdtemp(prefix="temper-spec-")
    shutil.copytree(spec, t, dirs_exist_ok=True)
    git("restore", "--source=HEAD", "--worktree", "--", spec)
    git("clean", "-fdq", "--", spec)
    r = git("checkout", name, "--")
    os.makedirs(spec, exist_ok=True)
    shutil.copytree(t, spec, dirs_exist_ok=True)
    if r.returncode != 0:
        print("FAIL: could not switch to %s: %s; the spec files are back in place, and a copy is in %s"
              % (name, " ".join((r.stderr or r.stdout).split())[-300:], t), file=sys.stderr)
        return 1
    shutil.rmtree(t, ignore_errors=True)
    print("OK: switched to %s, with the spec files of the run" % name)
    return 0


def if_protected(name, spec):
    """A fix run's branch: from main, master or the default branch, the switch to the run's branch (fix/<slug> when the
    state names none); from any other branch, that branch is recorded as the run's, and nothing switches."""
    import os
    import subprocess
    cur = git("rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
    default = git("symbolic-ref", "--short", "refs/remotes/origin/HEAD").stdout.strip().split("/", 1)[-1]
    if cur in ("main", "master") or (default and cur == default):
        return branch(name or "fix/%s" % os.path.basename(spec.rstrip("/")))
    if not cur or cur == "HEAD":
        print("FAIL: no branch is checked out", file=sys.stderr)
        return 1
    temper = os.path.join(os.path.dirname(os.path.abspath(__file__)), "temper")
    r = subprocess.run([temper, "state", "set", "branch", cur], capture_output=True, text=True)
    if r.returncode != 0:
        print("FAIL: state set branch %s: %s" % (cur, (r.stderr or r.stdout).strip()[-300:]), file=sys.stderr)
        return 1
    print("OK: on %s, now the run's branch" % cur)
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
    # the commit holds the named files, or the spec folder, and nothing else staged before (the card lists what it holds)
    only = ["--"] + paths
    if git("diff", "--cached", "--quiet", *only).returncode == 0:
        print("OK: nothing to commit in %s" % spec)
        return 0
    r = git("commit", "-q", "-m", message, *only)
    out = (r.stdout + r.stderr).strip()
    if r.returncode != 0:
        print("FAIL: git commit: %s" % out[-600:], file=sys.stderr)
        return 1
    head = git("log", "-1", "--format=%h %s").stdout.strip()
    print("OK: committed %s" % head)
    return 0


def deviations(spec):
    """build-context.json's deviations (unplanned files, skipped tasks, approach changes) as `deviations.md` in the spec
    folder, replacing one an earlier call wrote. Earlier this was an instruction the session carried out itself.

    9.8.5 (WP26): a file of its own, at every tier (a simple plan has no plan.md); plan.md and tasks.md stay as the
    approval saw them. The commit of the run's record takes the whole spec folder, so the file is in it."""
    import json
    import os
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
    path = os.path.join(spec, "deviations.md")
    if not rows:   # an earlier file goes, so the file always says what build-context.json holds
        try:
            os.remove(path)
        except OSError:
            pass
        print("OK: no deviations recorded")
        return 0
    tmp = "%s.tmp.%d" % (path, os.getpid())
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("# Deviations\n\n" + "\n".join(rows) + "\n")
        os.replace(tmp, path)
    except OSError as e:
        print("FAIL: cannot write %s: %s" % (path, e), file=sys.stderr)
        return 1
    print("OK: %d deviation(s) written into deviations.md" % len(rows))
    return 0


def main(argv):
    """argv: the word, the run's branch, the run's spec folder ('' with no run), then the word's own arguments."""
    word, name, spec = (list(argv[:3]) + ["", "", ""])[:3]
    rest = list(argv[3:])
    # --shown NAME=DIGEST pairs come off the word's own arguments (R2-4): each call of the approving answer compares
    # them itself, before anything is written, so a stale approval advances nothing however its calls were run
    shown = []
    if word in ("branch", "commit"):
        kept = []
        want = False
        for a in rest:
            if want:
                shown.append(a)
                want = False
            elif a == "--shown":
                want = True
            else:
                kept.append(a)
        rest = kept
        if want or any(not s.partition("=")[0] or "=" not in s for s in shown):
            print("FAIL: --shown takes NAME=DIGEST, NAME a file of the spec folder", file=sys.stderr)
            return 1
    if word in ("branch", "commit"):
        import approval
        why = approval.held(".temper/build-state.json", spec)
        if why:
            print("FAIL: spec %s: %s" % (word, why), file=sys.stderr)
            return 1
        if shown:
            bad = approval.check(spec, shown)
            if bad:
                print("FAIL: spec %s: %s" % (word, bad), file=sys.stderr)
                return 1
    if word == "branch":
        if rest[:1] == ["--carry"] and len(rest) == 2:
            return carry(spec, rest[1], name)
        if rest == ["--if-protected"]:
            return if_protected(name, spec)
        if not rest:
            return branch(name)
    if word in ("commit", "deviations") and not spec:
        print("FAIL: no active run", file=sys.stderr)
        return 1
    if word == "deviations" and not rest:
        return deviations(spec)
    if word == "commit" and rest and (len(rest) == 1 or rest[1] == "--"):
        return commit(spec, rest[0], rest[2:])
    print("FAIL: usage: temper spec branch [--carry NAME | --if-protected] [--shown NAME=DIGEST...] | deviations | "
          "commit '<message>' [--shown NAME=DIGEST...] [-- FILE...]", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
