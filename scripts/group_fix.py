"""group_fix.py: `temper group fix G [--commit]` (9.8.4), the fix of a group whose check failed after every task passed.

  python3 group_fix.py GROUPS.json NOW SLUG G            the person chose the fix: groups.json records the request, and
                                                         `temper next` launches one Build fix agent on the group's worktree
  python3 group_fix.py GROUPS.json NOW SLUG G --commit   after that agent: the CLI commits what it changed in the worktree on
                                                         the group's branch, records the commit as its own (cli_commits, so
                                                         the foreign commit check never parks on it) and clears the request

The fix works on the merged tree of the group (every task's work, on the group's branch), so the whole is mended once
instead of every task running again. The agent commits nothing itself; the CLI does, and `temper group gate G` checks the
result. The caller (scripts/temper) holds the run's lock. Standard library only.
"""
import json
import os
import subprocess
import sys

PREFIX = os.environ.get("TEMPER_PREFIX", "")
# the CLI's own folders inside a worktree are never part of a fix
EXCLUDE = [":(exclude,glob)**/.temper/**", ":(exclude,glob).temper/**",
           ":(exclude,glob)**/.claude/worktrees/**", ":(exclude,glob).claude/worktrees/**"]


def git(wt, *args):
    r = subprocess.run(["git", "-C", wt] + list(args), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return r.returncode, r.stdout.decode("utf-8", "replace").strip()


def id_args():
    """A fixed identity only when git has none (the CLI never reads the person's)."""
    for var in ("GIT_AUTHOR_IDENT", "GIT_COMMITTER_IDENT"):
        if subprocess.run(["git", "-c", "user.useConfigOnly=true", "var", var],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
            return ["-c", "user.name=Temper", "-c", "user.email=temper@localhost"]
    return []


def save(path, d):
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w") as fh:
        json.dump(d, fh, indent=2)
        fh.write("\n")
    os.replace(tmp, path)


def fail(msg):
    print("FAIL: " + msg, file=sys.stderr)
    return 1


def main(argv):
    if len(argv) < 5 or not argv[4].startswith("G") or not argv[4][1:].isdigit() or argv[5:] not in ([], ["--commit"]):
        return fail("usage: temper group fix G<n> [--commit]")
    path, now, slug, gid = argv[1:5]
    try:
        d = json.load(open(path))
    except (OSError, ValueError):
        return fail("no grouped Build is running (no groups.json)")
    g = (d.get("groups") or {}).get(gid)
    if not isinstance(g, dict) or not g.get("worktree"):
        return fail("group %s is not started (temper group start %s)" % (gid, gid))
    gate = g.get("gate") or {}
    wt = g["worktree"]
    if argv[5:] == []:
        if gate.get("verdict") != "FAIL":
            return fail("group %s has no failed check to fix (temper group gate %s)" % (gid, gid))
        g["fix"] = {"requested": now}
        save(path, d)
        print("OK: group %s: one Build fix agent works on its merged tree, then the CLI commits it and checks the group again" % gid)
        return 0
    if not os.path.isdir(wt):
        return fail("group %s's worktree %s is gone" % (gid, wt))
    rc, out = git(wt, "add", "-A", "--", ".", *EXCLUDE)
    if rc != 0:
        return fail("git add in %s failed: %s" % (wt, out.splitlines()[-1] if out else "no output"))
    if git(wt, "diff", "--cached", "--quiet")[0] == 0:
        g.pop("fix", None)
        save(path, d)
        print("OK: group %s: the fix agent changed nothing; the group is checked again as it is" % gid)
        return 0
    rc, out = git(wt, *id_args(), "commit", "-q", "-m", "fix(%s): %s group check" % (slug or "run", gid))
    if rc != 0:
        return fail("could not commit the fix of group %s in %s: %s" % (gid, wt, out.splitlines()[-1] if out else "no output"))
    sha = git(wt, "rev-parse", "HEAD")[1]
    d.setdefault("cli_commits", []).append(sha)
    g.pop("fix", None)
    g.setdefault("fix_commits", []).append(sha)
    save(path, d)
    print("OK: group %s: the fix is committed on its branch (%s)" % (gid, sha[:7]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
