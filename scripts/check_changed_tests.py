#!/usr/bin/env python3
"""check_changed_tests.py: every assertion of a test that was changed or removed is listed (done.md row D84), 9.8.5 (WP07).

  python3 scripts/check_changed_tests.py [--base REV] [--root DIR]

The first base is the commit `10e965a`, the base of the build. The removed lines of `git diff <base>` (the work tree
against the base) for the test files (the case files of the selftest, its runner, the scenarios of the end to end
suite and the test files of the mod) that hold `assert_eq`, `assert_exit`, `expect(` or `test(` are read. For each such
line the statement is taken from the base, a line that ends in a backslash running on through its last line; its name
is its first quoted string. A statement that is in the tree as it was is not a change: each of its lines, its indent
left out, is a whole line of the tree, in a row, and the lines of a statement of code are looked for among the lines
of code only (a line that starts with `#` or `//` is a comment), so an assertion commented out or with a word added
at its end is a change. Any other one fails unless its name is the text of the code span that is the first cell of a row of the
table of `docs/plans/one-go/changed-tests.md` (a code span elsewhere on that page names nothing).
So a changed expected value under an unchanged name is a changed assertion, and must be listed.

The second base (row D84b): for the case files 43 to 46, `scripts/e2e/accept.ts`, `scripts/e2e/slow.ts`,
`scripts/e2e/broken.ts` and `docs/plans/one-go/done.md` the base is the commit that first added the file to the
branch (the first parent line). An assertion of those files, or a row of the table of `done.md` (its name is its id),
that changed or went since then must be listed too. A file no commit holds yet has no second base.

The generated fixture modules are left out. Python 3 and git only. Exit 0 when every change is listed, else 1 (2 for
a wrong call, or a base git does not know).
"""
import os
import re
import subprocess
import sys

BASE = "10e965a"
LISTING = "docs/plans/one-go/changed-tests.md"
DONE = "docs/plans/one-go/done.md"
PATHSPECS = ["scripts/selftest/temper-cases-*.sh", "scripts/selftest/test-temper.sh", "scripts/e2e/*.ts",
             "*.test.ts", "*.test.tsx", ":(exclude)*view-fixtures*"]
SECOND = ["scripts/selftest/temper-cases-43.sh", "scripts/selftest/temper-cases-44.sh",
          "scripts/selftest/temper-cases-45.sh", "scripts/selftest/temper-cases-46.sh", "scripts/e2e/accept.ts",
          "scripts/e2e/slow.ts", "scripts/e2e/broken.ts", DONE]
# `expect(` and `test(` as calls of their own, not a method such as a regular expression's `.test(`
MARKERS = re.compile(r"\bassert_eq\b|\bassert_exit\b|(?<![.\w$])expect\(|(?<![.\w$])test\(")
QUOTED = re.compile(r"\"((?:[^\"\\]|\\.)*)\"|'([^']*)'|`([^`]*)`")
SPAN = re.compile(r"(`+)(.+?)\1")
HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+\d+(?:,\d+)? @@")


def git(root, *args, check=True):
    p = subprocess.run(["git", "-C", root] + list(args), capture_output=True, text=True, errors="replace")
    if check and p.returncode != 0:
        raise RuntimeError("git %s: %s" % (" ".join(args[:3]), p.stderr.strip()))
    return p.stdout


def removed_lines(root, base, specs):
    """[(path, old line number)] of the lines `git diff base` removes, for the pathspecs."""
    # the prefixes are named, so a person's diff.noprefix or diff.mnemonicPrefix cannot hide the paths
    out = git(root, "diff", "--no-color", "--no-ext-diff", "--src-prefix=a/", "--dst-prefix=b/", "--unified=0", base,
              "--", *specs)
    found, path, old = [], None, 0
    for line in out.split("\n"):
        if line.startswith("--- "):
            if line.startswith("--- a/"):
                path = line[6:]
            elif line.rstrip() == "--- /dev/null":
                path = None
            else:
                raise RuntimeError("git diff names a file this script cannot read: %s" % line)
        elif line.startswith("+++ "):
            continue
        elif line.startswith("@@"):
            m = HUNK.match(line)
            old = int(m.group(1)) if m else 0
        elif line.startswith("-") and path is not None:
            found.append((path, old))
            old += 1
    return found


def statement(lines, i):
    """The statement that starts at line i (0 based): a line that ends in a backslash runs on through the next."""
    out = [lines[i]]
    while out[-1].rstrip().endswith("\\") and i + 1 < len(lines):
        i += 1
        out.append(lines[i])
    return out


def name_of(text):
    m = QUOTED.search(text)
    if m is None:
        return text.strip().split("\n")[0].strip()
    return next(g for g in m.groups() if g is not None)


def squeeze(lines):
    return "\n".join(line.strip() for line in lines)


def first_cell(line):
    """The first cell of a table line, a code span (of one or more backticks) kept whole even when it holds a `|`."""
    text, i, cell = line.strip()[1:], 0, []
    while i < len(text):
        m = SPAN.match(text, i) if text[i] == "`" else None
        if m is not None:
            cell.append(m.group(0))
            i = m.end()
        elif text[i] == "|":
            break
        else:
            cell.append(text[i])
            i += 1
    return "".join(cell).strip()


def listed_names(root):
    """The names of the table: the text of the code span that is the whole first cell of a line starting with `|`.
    A code span anywhere else on the page (its intro, the other columns) names nothing."""
    path = os.path.join(root, LISTING)
    if not os.path.isfile(path):
        return set()
    names = set()
    with open(path, encoding="utf-8") as f:
        for line in f.read().split("\n"):
            if not line.startswith("|"):
                continue
            m = SPAN.fullmatch(first_cell(line))
            if m is not None:
                names.add(m.group(2).strip())
    return names


def is_comment(line):
    s = line.strip()
    return s.startswith("#") or s.startswith("//")


def tree_text(root, specs):
    """(all, code): the lines of every file of the work tree the pathspecs match, each with its indent left out, joined
    and framed by a newline at each end; `code` leaves out the comment lines (`#` or `//`), so an assertion that was
    commented out is no longer in it."""
    names = git(root, "ls-files", "-co", "--exclude-standard", "--", *specs).split("\n")
    lines = []
    for n in names:
        p = os.path.join(root, n)
        if n and os.path.isfile(p):
            with open(p, encoding="utf-8", errors="replace") as f:
                lines += [line.strip() for line in f.read().split("\n")]
    return ("\n" + "\n".join(lines) + "\n", "\n" + "\n".join(x for x in lines if not is_comment(x)) + "\n")


def holds(text, lines):
    """True when the text holds the lines as whole lines, in a row (a part of a line is not enough)."""
    return "\n" + "\n".join(lines) + "\n" in text


def first_added(root, path):
    out = git(root, "log", "--first-parent", "--diff-filter=A", "--format=%H", "--", path, check=False).split()
    return out[-1] if out else None


def changes(root, base, specs, tree, rows=False):
    """[(path, line, name)] of the assertions (or rows) of the base that the tree no longer holds as they were."""
    found, cache, seen = [], {}, set()
    for path, n in removed_lines(root, base, specs):
        if path not in cache:
            cache[path] = git(root, "show", "%s:%s" % (base, path), check=False).split("\n")
        old = cache[path]
        if n < 1 or n > len(old):
            continue
        line = old[n - 1]
        if rows:
            m = re.match(r"^\|\s*(D\d+[a-z]?)\s*\|", line)
            if m is None or holds(tree, [line.strip()]):
                continue
            found.append((path, n, m.group(1)))
            continue
        start = n - 1   # a removed line inside a statement that runs on with backslashes belongs to that statement
        while start > 0 and old[start - 1].rstrip().endswith("\\"):
            start -= 1
        if not MARKERS.search(old[start]):
            continue
        st = statement(old, start)
        # a statement is compared whole line by whole line; one that is code is looked for among the code lines only
        if holds(tree[0] if is_comment(st[0]) else tree[1], squeeze(st).split("\n")):
            continue
        if (path, start + 1) in seen:
            continue
        seen.add((path, start + 1))
        found.append((path, start + 1, name_of("\n".join(st))))
    return found


def main(argv):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    base = BASE
    args = list(argv)
    while args:
        a = args.pop(0)
        if a in ("--base", "--root") and args:
            v = args.pop(0)
            if a == "--base":
                base = v
            else:
                root = os.path.abspath(v)
        else:
            print("usage: python3 scripts/check_changed_tests.py [--base REV] [--root DIR]")
            return 2
    if subprocess.run(["git", "-C", root, "rev-parse", "--verify", "--quiet", base + "^{commit}"],
                      capture_output=True).returncode != 0:
        print("check_changed_tests: FAIL: git knows no base %s here (the branch must keep it reachable)" % base)
        return 2
    try:
        return check(root, base)
    except RuntimeError as e:
        print("check_changed_tests: FAIL: %s" % e)
        return 1


def check(root, base):
    names = listed_names(root)
    tree = tree_text(root, PATHSPECS)
    found = [(p, n, nm, base) for p, n, nm in changes(root, base, PATHSPECS, tree)]
    for path in SECOND:
        second = first_added(root, path)
        if second is None:
            continue
        if path == DONE:
            done = os.path.join(root, DONE)
            text = "\n"
            if os.path.isfile(done):
                with open(done, encoding="utf-8") as f:
                    text = "\n" + "\n".join(line.strip() for line in f.read().split("\n")) + "\n"
            found += [(p, n, nm, second[:7]) for p, n, nm in changes(root, second, [path], text, rows=True)]
        else:
            found += [(p, n, nm, second[:7]) for p, n, nm in changes(root, second, [path], tree)
                      if (p, nm) not in [(f[0], f[2]) for f in found]]
    bad = [f for f in found if f[2] not in names]
    for path, n, name, b in found:
        print("%s %s:%d (base %s): %s" % ("listed  " if name not in [x[2] for x in bad] else "UNLISTED", path, n, b,
                                          name))
    if bad:
        print("check_changed_tests: FAIL: %d changed or removed assertion(s) not listed in %s" % (len(bad), LISTING))
        return 1
    print("check_changed_tests: PASS (%d changed or removed assertion(s), each listed)" % len(found))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
