#!/usr/bin/env python3
"""growth_base.py: the earlier version of a floor or caps file that a `now` above its `final` is held against.

check_caps.py and check_floor.py, in the mode CI runs (no --final), fail when a `now` is above its `final` and also
above its value in an earlier version of the same file: a size that is over its bound, recorded for the owner, stays
green, and it cannot grow. This module finds that earlier version:

  1. the file at the merge base of HEAD with the main branch (`origin/main`, else `main`; with --base REV, with REV:
     CI gives a pull request its base branch and a push to main the commit before the push);
  2. when no merge base can be read (a shallow clone, no such branch) or it holds no such file (the branch that adds
     the file): the previous committed version of the file, which is HEAD's when the work tree differs from HEAD, else
     the version before the last commit that changed the file;
     The same when HEAD is itself on that branch (the merge base is HEAD), so a commit on main is held too;
  3. else none, and the caller passes with the line printed.

earlier(path, base) gives (doc, where, note): the parsed JSON or None, the words that name the version in a failure
line, and for 2 and 3 the one line that says the merge base was not read. Python 3 and git only.
"""
import json
import os
import subprocess


def git(cwd, *args):
    p = subprocess.run(["git", "-C", cwd] + list(args), capture_output=True, text=True)
    return p.stdout if p.returncode == 0 else None


def parsed(text):
    try:
        doc = json.loads(text or "")
    except ValueError:
        return None
    return doc if isinstance(doc, dict) else None


def earlier(path, base=None):
    d = os.path.dirname(os.path.abspath(path))
    top = (git(d, "rev-parse", "--show-toplevel") or "").strip()
    if not top or git(top, "rev-parse", "--verify", "--quiet", "HEAD^{commit}") is None:
        return None, "", "no commit of git holds %s: a now above its final is held against no earlier value" % os.path.basename(path)
    rel = os.path.relpath(os.path.realpath(path), os.path.realpath(top))
    why = "the merge base with %s cannot be read" % (base or "main")
    for ref in ([base] if base else ["origin/main", "main"]):
        mb = (git(top, "merge-base", "HEAD", ref) or "").strip()
        if not mb:
            continue
        if mb == (git(top, "rev-parse", "HEAD") or "").strip():   # on that branch itself: nothing lies between
            why = "HEAD is on %s" % ref
            break
        doc = parsed(git(top, "show", "%s:%s" % (mb, rel)))
        if doc is not None:
            return doc, "at the merge base with %s (%s)" % (ref, mb[:7]), None
        why = "the merge base with %s (%s) holds no %s" % (ref, mb[:7], rel)
        break
    with open(path, encoding="utf-8") as f:
        cur = f.read()
    head = git(top, "show", "HEAD:%s" % rel)
    if head is not None and head != cur:
        prev, name = head, "HEAD"
    else:
        last = (git(top, "log", "-1", "--format=%H", "--", rel) or "").strip()
        prev, name = (git(top, "show", "%s^:%s" % (last, rel)), "%s^" % last[:7]) if last else (None, "")
    doc = parsed(prev)
    if doc is None:
        return None, "", "%s, and the file has no previous committed version: a now above its final is held against no earlier value" % why
    return doc, "in the file's previous committed version (%s)" % name, \
        "%s: a now above its final is held against the file's previous committed version (%s)" % (why, name)
