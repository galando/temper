"""group_fix.py: `temper group fix G [--commit]` (9.8.4), the fix of a group whose check failed after every task passed.

  python3 group_fix.py GROUPS.json NOW SLUG G            the person chose the fix: groups.json records the request, and
                                                         `temper next` launches one Build fix agent on the group's worktree
  python3 group_fix.py GROUPS.json NOW SLUG G --commit   after that agent: the CLI commits what it changed in the worktree on
                                                         the group's branch, records the commit as its own (cli_commits, so
                                                         the foreign commit check never parks on it), clears the request and
                                                         the group's gate, so the next action checks the group again

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


def byproducts(wt):
    """WP22: what a run of the reuse store left in the worktree (coverage data, caches; never a tracked, declared, source or
    test file, run_env.byproducts_of), as exclude paths: a check's byproduct is no part of a fix; none when unknown. A
    folder entry stands for the untracked files in it now, less every source, test or declared file: what the fix agent
    wrote there is part of the fix."""
    try:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import run_env
        lst = run_env.byproducts_of(wt, run_env.store_read(run_env._store(wt)), os.getcwd())
        out = [x for x in lst if not x.endswith("/")]
        dirs = [":(top,literal)%s" % x for x in lst if x.endswith("/")]
        if dirs:
            prefix, decl = run_env._git(wt, "rev-parse", "--show-prefix"), run_env.declared(os.getcwd()) | run_env.declared(wt)
            p = subprocess.run(["git", "-C", wt, "ls-files", "-o", "--exclude-standard", "--full-name", "-z", "--"] + dirs,
                               stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True)
            out += [f for f in p.stdout.decode("utf-8", "surrogateescape").split("\0")
                    if f and not run_env._bad_byproduct(f, prefix, set(), decl)]
        return [":(exclude,top,literal)%s" % x.rstrip("/") for x in out]
    except Exception:
        return []


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
        g["fix_tries"] = int(g.get("fix_tries") or 0) + 1   # a fix that did not pass is not recommended again (flow.py)
        save(path, d)
        print("OK: group %s: one Build fix agent works on its merged tree, then the CLI commits it and checks the group again" % gid)
        return 0
    if not os.path.isdir(wt):
        return fail("group %s's worktree %s is gone" % (gid, wt))
    rc, out = git(wt, "add", "-A", "--", ".", *(EXCLUDE + byproducts(wt)))
    if rc != 0:
        return fail("git add in %s failed: %s" % (wt, out.splitlines()[-1] if out else "no output"))
    # the group is checked again by the next action, as an ordinary call of the CLI: its gate goes (the count stays)
    if git(wt, "diff", "--cached", "--quiet")[0] == 0:
        # 9.8.5 (S8): no change means the cause is not in the group's code. The same tree would fail the same way, so its
        # check stays failed (no rerun) and the next question points at the plan or the environment.
        g.pop("fix", None)
        g["fix_empty"] = int(g.get("fix_empty") or 0) + 1
        save(path, d)
        try:   # WP23: one failure record of class command
            sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
            import failure
            failure.record("build", "group:%s" % gid, "validate", "fix-changed-nothing",
                           "group %s: the fix agent changed nothing, so the cause is not in the group's code" % gid,
                           ran_by="agent", class_by="structure")
        except Exception:
            pass
        print("OK: group %s: the fix agent changed nothing, so the cause is not in the group's code; its check stays failed" % gid)
        return 0
    rc, out = git(wt, *id_args(), "commit", "-q", "-m", "fix(%s): %s group check" % (slug or "run", gid))
    if rc != 0:
        return fail("could not commit the fix of group %s in %s: %s" % (gid, wt, out.splitlines()[-1] if out else "no output"))
    sha = git(wt, "rev-parse", "HEAD")[1]
    d.setdefault("cli_commits", []).append(sha)
    g.pop("fix", None)
    g.pop("gate", None)
    g.setdefault("fix_commits", []).append(sha)
    save(path, d)
    print("OK: group %s: the fix is committed on its branch (%s)" % (gid, sha[:7]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
