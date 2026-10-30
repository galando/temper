"""pr_parts.py: the parts of a stacked pull request, one per Build group (F24).

  python3 pr_parts.py parts BASE_SHA SLUG       prints JSON: [{"part": 1, "groups": ["G1"], "merge": "<sha>"}, ...]

Build merges each group into the feature branch with a commit `merge(<slug>): group G<n>`. A part ends at one of those merge
commits, so a stacked pull request can point a branch at it and every commit keeps the SHA Build gave it. Commits after the
last group merge join the last part (it then ends at HEAD). A group whose change is only comments or blank lines joins the
next part; the last such group joins the part before. Comments are `#` lines, `//` lines and `/* ... */` blocks; the state of
a block comment is reset at each hunk of the diff. Standard library only.
"""
import json
import re
import subprocess
import sys


def git(*args):
    r = subprocess.run(["git"] + list(args), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return r.stdout.decode("utf-8", "replace") if r.returncode == 0 else ""


def comment_only(diff):
    """True when every added or removed line of the unified diff is a comment or blank. Context lines are not changes.
    The block comment state starts again at each hunk, so a block left open at the end of a hunk says nothing about the next."""
    in_block = False
    seen_file = False
    for line in diff.splitlines():
        if line.startswith("diff --git") or line.startswith("index ") or line.startswith("--- ") or line.startswith("+++ "):
            seen_file = seen_file or line.startswith("diff --git")
            continue
        if line.startswith("Binary files") or line.startswith("GIT binary patch"):
            return False
        if line.startswith("@@"):
            in_block = False
            continue
        if not line or line[0] not in "+-":
            continue
        c = line[1:].strip()
        if not c:
            continue
        if in_block:
            if "*/" in c:
                in_block = False
            continue
        if c.startswith("#") or c.startswith("//"):
            continue
        if c.startswith("/*"):
            in_block = "*/" not in c[2:]
            continue
        return False
    return True


def group_merges(base, slug):
    """[(group id, merge sha)] in merge order along the first parent line."""
    out = []
    pat = re.compile(r"^merge\(%s\): group (G\d+)$" % re.escape(slug))
    for line in git("log", "--first-parent", "--reverse", "--format=%H%x09%s", "%s..HEAD" % base).splitlines():
        sha, _, subject = line.partition("\t")
        m = pat.match(subject)
        if m:
            out.append((m.group(1), sha))
    return out


def parts(base, slug):
    merges = group_merges(base, slug)
    if not merges:
        return []
    flat = [(g, sha, comment_only(git("diff", "%s^1" % sha, sha))) for g, sha in merges]
    result, pending = [], []
    for g, sha, only_comments in flat:
        pending.append(g)
        if not only_comments:
            result.append({"groups": pending, "merge": sha})
            pending = []
    if pending:   # the last groups changed only comments: they join the part before
        if result:
            result[-1]["groups"] += pending
            result[-1]["merge"] = flat[-1][1]
        else:
            result.append({"groups": pending, "merge": flat[-1][1]})
    head = git("rev-parse", "HEAD").strip()
    if head and result and head != flat[-1][1]:
        result[-1]["merge"] = head     # commits after the last group merge join the last part
    for i, p in enumerate(result, 1):
        p["part"] = i
    return [{"part": p["part"], "groups": p["groups"], "merge": p["merge"]} for p in result]


def main(argv):
    if len(argv) == 4 and argv[1] == "parts":
        print(json.dumps(parts(argv[2], argv[3])))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
