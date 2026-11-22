#!/usr/bin/env python3
"""check_changed_tests.py: every assertion of a test that was changed or removed is listed (done.md row D84), 9.8.5 (WP07).

  python3 scripts/check_changed_tests.py [--base REV] [--root DIR]

The first base is the commit `10e965a`, the base of the build. The removed lines of `git diff <base>` (the work tree
against the base) for the test files (the case files of the selftest, its runner, the scenarios of the end to end
suite and the test files of the mod) that hold `assert_eq`, `assert_exit`, `expect(` or `test(` are read. For each such
line the statement is taken from the base: a line that ends in a backslash runs on through its last line, and in a
TypeScript file a call of `expect(` runs on until its parentheses close. Its name is its first quoted string that holds
a letter and that no other assertion of its file at the base holds as a quoted string; failing that, the statement
itself, its lines stripped and joined by a space (with `#k` after the k-th of two or more alike). So a name
identifies its statement: a string such as `,`, or a value two checks compare against, names none of them. A statement
that is in the tree as it was is not a change: each of its lines, its indent left out, is a whole line of the tree, in
a row, as many times as the base holds it, and the lines of a statement of code are looked for among the lines of code
only (a line that starts with `#` or `//` is a comment), so an assertion commented out, with a word added at its end,
or one of two alike changed, is a change. Any other one fails unless its name is the text of the code span that is the
first cell of a row of the table of `docs/plans/one-go/changed-tests.md` and the second cell of that row names its
file in a code span (a code span elsewhere on that page names nothing).
So a changed expected value under an unchanged name is a changed assertion, and must be listed.

The second base (row D84b): for every test file the first base does not hold (a case file, a scenario file or a test
file of the mod that the branch added) and for `docs/plans/one-go/done.md` the base is the commit that first added
the file to the branch (the first parent line). An assertion of those files, or a row of the table of `done.md` (its
name is its id), that changed or went since then must be listed too. A file no commit holds yet has no second base.

What it does not compare (row D84 says so): a second change under a name that is already listed, the lines before an
assertion that set up what it reads, and the helper files the case files source.

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


def second_files(root, base):
    """The files of the second base: every tracked test file that the first base does not hold, and done.md."""
    held = set(git(root, "ls-tree", "-r", "--name-only", base, check=False).split("\n"))
    now = git(root, "ls-files", "--", *PATHSPECS, check=False).split("\n")
    return sorted(f for f in now if f and f not in held) + [DONE]
# `expect(` and `test(` as calls of their own, not a method such as a regular expression's `.test(`
MARKERS = re.compile(r"\bassert_eq\b|\bassert_exit\b|(?<![.\w$])expect\(|(?<![.\w$])test\(")
EXPECT = re.compile(r"(?<![.\w$])expect\(")
RUN_ON = 40   # the most lines one `expect(` call runs on through: a parenthesis of a regular expression stops there
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


def parens(text):
    """( less ) in a line of code, leaving out what is inside a quoted string of that line."""
    depth, quote, i = 0, None, 0
    while i < len(text):
        c = text[i]
        if quote is not None:
            if c == "\\":
                i += 1
            elif c == quote:
                quote = None
        elif c in "\"'`":
            quote = c
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        i += 1
    return depth


def statement(lines, i, ts=False):
    """The statement that starts at line i (0 based): a line that ends in a backslash runs on through the next, and in
    a TypeScript file an `expect(` call runs on until its parentheses close (its message is often on the next line)."""
    out = [lines[i]]
    m = EXPECT.search(lines[i]) if ts else None
    if m is not None:
        depth = parens(lines[i][m.start():])
        while depth > 0 and i + 1 < len(lines) and len(out) < RUN_ON:
            i += 1
            out.append(lines[i])
            depth += parens(lines[i])
        return out
    while out[-1].rstrip().endswith("\\") and i + 1 < len(lines):
        i += 1
        out.append(lines[i])
    return out


def statements(lines, ts):
    """[(start, lines)] of the assertions of a file (0 based): a line with a marker that no backslash runs on into."""
    out = []
    for i, line in enumerate(lines):
        if MARKERS.search(line) and (i == 0 or not lines[i - 1].rstrip().endswith("\\")):
            out.append((i, statement(lines, i, ts)))
    return out


def ts_strings(text):
    """The quoted strings of TypeScript, in order: a template literal is read whole, its `${...}` parts and the strings
    and templates inside them too, and a backslash escapes the character after it."""
    out, i = [], 0

    def read(i, q):   # i just after the opening quote q: (content, index after the closing quote)
        start = i
        while i < len(text):
            c = text[i]
            if c == "\\":
                i += 2
                continue
            if c == q:
                return text[start:i], i + 1
            if q == "`" and text.startswith("${", i):
                i = code(i + 2)
                continue
            if q != "`" and c == "\n":
                break
            i += 1
        return text[start:i], i

    def code(i):   # i just after `${`: the index after its closing brace
        depth = 1
        while i < len(text) and depth:
            c = text[i]
            if c in "\"'`":
                i = read(i + 1, c)[1]
                continue
            depth += 1 if c == "{" else -1 if c == "}" else 0
            i += 1
        return i

    while i < len(text):
        c = text[i]
        if c in "\"'`":
            content, i = read(i + 1, c)
            out.append(content)
        else:
            i += 1
    return out


def quoted(text, ts=False):
    if ts:
        return ts_strings(text)
    return [next(g for g in m.groups() if g is not None) for m in QUOTED.finditer(text)]


def names(lines, ts):
    """{start: name} of the assertions of a file. The name of one is its first quoted string that holds a letter and
    that no other assertion of the file holds as a quoted string, so a name identifies its statement (a string such as
    `,` or a value two checks compare against names none). Failing that, the name is the statement itself, its lines
    stripped and joined by a space, with `#k` after it when the file holds that statement more than once (the k-th)."""
    found = statements(lines, ts)
    strings = [quoted("\n".join(st), ts) for _, st in found]
    out, seen = {}, {}
    for k, (start, st) in enumerate(found):
        others = set(q for j, qs in enumerate(strings) if j != k for q in qs)
        name = next((q for q in strings[k] if re.search(r"[A-Za-z]", q) and q not in others), None)
        if name is None:
            name = " ".join(line.strip() for line in st)
            alike = sum(1 for _, o in found if " ".join(line.strip() for line in o) == name)
            seen[name] = seen.get(name, 0) + 1
            if alike > 1:
                name = "%s #%d" % (name, seen[name])
        out[start] = name
    return out


def squeeze(lines):
    return "\n".join(line.strip() for line in lines)


def cells(line):
    """The cells of a table line, a code span (of one or more backticks) kept whole even when it holds a `|`."""
    text, i, out, cell = line.strip()[1:], 0, [], []
    while i < len(text):
        m = SPAN.match(text, i) if text[i] == "`" else None
        if m is not None:
            cell.append(m.group(0))
            i = m.end()
        elif text[i] == "|":
            out.append("".join(cell).strip())
            cell = []
            i += 1
        else:
            cell.append(text[i])
            i += 1
    if "".join(cell).strip():
        out.append("".join(cell).strip())
    return out


def listed_names(root):
    """{name: files} of the table: the name is the text of the code span that is the whole first cell of a line
    starting with `|`, and the files are the texts of the code spans of its second cell. A row covers a change only
    in a file it names, so a name two files share is listed for each on its own; a code span anywhere else on the page
    (its intro, the other columns) names nothing."""
    names = {}
    for path in listing_pages(root):
        with open(path, encoding="utf-8") as f:
            for line in f.read().split("\n"):
                if not line.startswith("|"):
                    continue
                row = cells(line)
                m = SPAN.fullmatch(row[0]) if row else None
                if m is not None:
                    files = set(x.group(2).strip() for x in SPAN.finditer(row[1])) if len(row) > 1 else set()
                    names.setdefault(m.group(2).strip(), set()).update(files)
    return names


def listing_pages(root):
    """The page and its continuation pages, `changed-tests-2.md` and on, read the same way: one page cannot pass
    the plugin directory's 256 KiB limit for a file, so the table goes on in the next page."""
    first = os.path.join(root, LISTING)
    pages = [first] if os.path.isfile(first) else []
    stem = first[:-len(".md")]
    n = 2
    while os.path.isfile("%s-%d.md" % (stem, n)):
        pages.append("%s-%d.md" % (stem, n))
        n += 1
    return pages


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


BASE_TEXT = {}


def base_text(root, base, specs):
    """The (all, code) of tree_text for the files of the commit base that the pathspecs match."""
    if (root, base) in BASE_TEXT:
        return BASE_TEXT[(root, base)]
    out = git(root, "grep", "-I", "--name-only", "-e", "^", base, "--", *specs, check=False)
    lines = []
    for n in out.split("\n"):
        if n.startswith(base + ":"):
            lines += [line.strip() for line in git(root, "show", n, check=False).split("\n")]
    BASE_TEXT[(root, base)] = ("\n" + "\n".join(lines) + "\n",
                               "\n" + "\n".join(x for x in lines if not is_comment(x)) + "\n")
    return BASE_TEXT[(root, base)]


def count(text, lines):
    """How many times the text holds the lines as whole lines, in a row (a part of a line is not enough)."""
    needle, k, i = "\n" + "\n".join(lines) + "\n", 0, -1
    while True:
        i = text.find(needle, i + 1)
        if i < 0:
            return k
        k += 1


def holds(text, lines):
    """True when the text holds the lines as whole lines, in a row (a part of a line is not enough)."""
    return count(text, lines) > 0


def first_added(root, path):
    out = git(root, "log", "--first-parent", "--diff-filter=A", "--format=%H", "--", path, check=False).split()
    return out[-1] if out else None


def changes(root, base, specs, tree, rows=False):
    """[(path, line, name)] of the assertions (or rows) of the base that the tree no longer holds as they were."""
    found, cache, seen, owners = [], {}, set(), {}
    based = None if rows else base_text(root, base, PATHSPECS)
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
        if path not in owners:
            found_here = statements(old, path.endswith((".ts", ".tsx")))
            owners[path] = ({k: start for start, st in reversed(found_here) for k in range(start, start + len(st))},
                            dict(found_here), names(old, path.endswith((".ts", ".tsx"))))
        owner, whole, named = owners[path]
        # a removed line inside a statement (run on by backslashes, or a call of expect( over lines) belongs to it
        start = owner.get(n - 1)
        if start is None or (path, start + 1) in seen:
            continue
        st = squeeze(whole[start]).split("\n")
        # a statement is compared whole line by whole line; one that is code is looked for among the code lines only.
        # It is held when the tree holds it as many times as the base does: of two alike, one changed is a change
        k = 0 if is_comment(st[0]) else 1
        if count(tree[k], st) >= max(1, count(based[k], st)):
            continue
        seen.add((path, start + 1))
        found.append((path, start + 1, named[start]))
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
    for path in second_files(root, base):
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
    bad = [f for f in found if f[0] not in names.get(f[2], ())]
    for f in found:
        print("%s %s:%d (base %s): %s" % ("UNLISTED" if f in bad else "listed  ", f[0], f[1], f[3], f[2]))
    if bad:
        print("check_changed_tests: FAIL: %d changed or removed assertion(s) not listed in %s" % (len(bad), LISTING))
        return 1
    print("check_changed_tests: PASS (%d changed or removed assertion(s), each listed)" % len(found))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
