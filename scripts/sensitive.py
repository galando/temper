#!/usr/bin/env python3
"""sensitive.py: the one matcher of sensitive paths (9.8.5, WP11; the key autonomy.park-on-touch keeps its spelling).

  python3 sensitive.py match FILE PATTERN       exit 0 when the file matches the pattern, else 1
  python3 sensitive.py touched PATTERNS DECLARED [OVERRIDES]
                                                reads the changed files on stdin, one a line; prints each one that matches
                                                a pattern, is not declared and is not confirmed by the person, as
                                                `<file> matches <pattern> and is not in the plan`, joined by "; "

PATTERNS is the config value as the CLI prints it (joined by \\x1f), DECLARED the files the plan declares, one a line,
OVERRIDES the overrides file: a changed file passes when it holds `sensitive-path:<file>`.

A pattern is a proper match, never a substring test: a pattern naming the auth folder at any depth matches the `auth`
path segment, never `auth` inside `oauth`; a star inside a segment stays inside it. Standard library only.
"""
import json
import re
import sys


def match(path, pattern):
    """True when the path matches the pattern (`**/` any folders, `*` and `?` inside one segment)."""
    target = str(path).strip()
    while target.startswith("./"):
        target = target[2:]
    pat, out, i = str(pattern).strip(), [], 0
    n = len(pat)
    while i < n:
        if pat[i:i + 3] == "**/":
            out.append("(?:.*/)?")
            i += 3
        elif pat[i:i + 3] == "/**":
            out.append("(?:/.*)?")
            i += 3
        elif pat[i:i + 2] == "**":
            out.append(".*")
            i += 2
        elif pat[i] == "*":
            out.append("[^/]*")
            i += 1
        elif pat[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(pat[i]))
            i += 1
    return bool(pat) and re.match("^" + "".join(out) + "$", target) is not None


def patterns_of(value):
    """The patterns of a config value: a list, or the CLI's text joined by \\x1f or commas."""
    if isinstance(value, (list, tuple)):
        items = value
    else:
        items = re.split(r"[\x1f,]", str(value or ""))
    return [p.strip().strip("'\"") for p in items if p and p.strip().strip("'\"")]


def declared(files, patterns):
    """The files the plan declares that match a pattern, in their order: [(file, pattern)]."""
    out = []
    for f in files or []:
        hit = next((p for p in patterns_of(patterns) if match(f, p)), None)
        if hit is not None and f not in [x for x, _ in out]:
            out.append((f, hit))
    return out


def confirmed(overrides_path):
    """The files the person confirmed at the commit question (`temper override sensitive-path:<file>`)."""
    try:
        rows = json.load(open(overrides_path))
    except (OSError, ValueError):
        return set()
    return {str(o.get("stage"))[len("sensitive-path:"):] for o in rows if isinstance(o, dict)
            and str(o.get("stage") or "").startswith("sensitive-path:")} if isinstance(rows, list) else set()


def touched(changed, patterns, plan_files, confirmed_files=()):
    """The changed files outside the plan that match a pattern and that the person has not confirmed."""
    out = []
    for f in changed:
        if f in plan_files or f in confirmed_files:
            continue
        hit = next((p for p in patterns_of(patterns) if match(f, p)), None)
        if hit is not None:
            out.append("%s matches %s and is not in the plan" % (f, hit))
    return out


def main(argv):
    if len(argv) == 4 and argv[1] == "match":
        return 0 if match(argv[2], argv[3]) else 1
    if len(argv) in (4, 5) and argv[1] == "touched":
        plan = {x.strip() for x in argv[3].splitlines() if x.strip()}
        conf = confirmed(argv[4]) if len(argv) == 5 else set()
        changed = [x.strip() for x in sys.stdin.read().splitlines() if x.strip()]
        hits = touched(changed, argv[2], plan, conf)
        if hits:
            print("; ".join(hits))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
