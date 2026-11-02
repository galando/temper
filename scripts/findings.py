"""findings.py: how the author answers a finding without accepting it (9.7.6). Accepting stays the person's call.

  python3 findings.py contest LEDGER.json ID CITE QUOTE REASON TS   a contest the reviewer could check: CITE names a file in
                                                               the project (path, path:LINE or path:SYMBOL), and QUOTE
                                                               is the text there that shows the finding is wrong
  python3 findings.py escalate LEDGER.json ID REASON TS        the evidence is outside every file (a team rule, a spoken
                                                               decision): the person decides, with what only they know

Both keep the finding open: the gate still counts it, and the gate question shows the contest or the escalation, so the
person accepts it or sends it back. A contest with no readable citation is refused: "This was intentional" is not
evidence. The citation is checked here, from the project folder: the file exists inside the project, the line exists, the
symbol is in the file, and the quote (at least 12 characters) is in the file, within 3 lines of a cited line. The quote is
what the person reads at the accept question. A comprehension finding (claim `[comprehension] ...`) is never contested or
escalated: when a reader with no context could not follow the plan, the plan is missing context. Standard library only.
"""
import json
import os
import re
import sys


def fail(msg):
    print("FAIL: %s" % msg, file=sys.stderr)
    return 1


def check_cite(cite, root, quote=""):
    """None when CITE names something a reviewer could read and QUOTE is there, else why not."""
    cite = (cite or "").strip()
    if not cite:
        return "a contest needs --cite <file>, <file>:<line> or <file>:<symbol>"
    m = re.match(r"^([^:]+?)(?::(.+))?$", cite)
    path, what = m.group(1).strip(), (m.group(2) or "").strip()
    if os.path.isabs(path) or ".." in path.replace("\\", "/").split("/"):
        return "the cited file must be a path inside the project, not '%s'" % path
    full = os.path.realpath(os.path.join(root, path))
    if not (full == root or full.startswith(root.rstrip("/") + "/")) or not os.path.isfile(full):
        return "no file %s in the project" % path
    try:
        text = open(full, encoding="utf-8", errors="replace").read()
    except OSError:
        return "%s cannot be read" % path
    quote = " ".join((quote or "").split())
    if len(quote) < 12:
        return "a contest needs --quote: at least 12 characters of the cited text, which the person reads"
    lines = text.splitlines()
    flat = lambda part: " ".join(" ".join(part).split())
    if what.isdigit():
        n = int(what)
        if not 1 <= n <= len(lines):
            return "%s has %d line(s), not line %s" % (path, len(lines), what)
        return None if quote in flat(lines[max(n - 4, 0):n + 3]) else "the quote is not within 3 lines of %s:%s" % (path, what)
    if what and what not in text:
        return "%s does not contain '%s'" % (path, what)
    return None if quote in flat(lines) else "%s does not contain the quote" % path


def mark(ledger, id_s, key, value):
    try:
        rows = json.load(open(ledger))
    except (OSError, ValueError):
        return fail("no ledger at %s" % ledger)
    try:
        idx = int(id_s)
    except ValueError:
        return fail("--id must be the 1-based number shown by 'temper evidence list'")
    if idx < 1 or idx > len(rows):
        return fail("no finding #%s in this stage (it has %d entries)" % (id_s, len(rows)))
    e = rows[idx - 1]
    if not isinstance(e, dict) or not e.get("severity"):
        return fail("finding #%s carries no severity, so it never counted against a gate" % id_s)
    if str(e.get("claim") or "").lstrip().lower().startswith("[comprehension]"):
        return fail("finding #%s is a comprehension finding: a reader with no context could not follow the plan, so the plan is "
                    "missing context. Fix the plan; it is never contested or escalated" % id_s)
    for k in ("resolved", "accepted"):
        if e.get(k):
            return fail("finding #%s is already %s" % (id_s, k))
    e.pop("contested", None)
    e.pop("escalated", None)
    e[key] = value
    tmp = "%s.tmp.%d" % (ledger, os.getpid())
    with open(tmp, "w") as fh:
        json.dump(rows, fh, indent=2)
    os.replace(tmp, ledger)
    print("OK: %s finding #%s %s; it stays open until the person accepts it or it is fixed" % (e.get("severity"), id_s, key))
    return 0


def main(argv):
    if len(argv) == 8 and argv[1] == "contest":
        _, _, ledger, id_s, cite, quote, reason, ts = argv
        if not reason.strip():
            return fail("a contest needs --reason")
        why = check_cite(cite, os.path.realpath(os.getcwd()), quote)
        if why:
            return fail("%s. A contest must cite a file the reviewer could read; when the evidence is outside every file, "
                        "use temper evidence escalate" % why)
        return mark(ledger, id_s, "contested", {"cite": cite.strip(), "quote": " ".join(quote.split()), "reason": reason, "ts": ts})
    if len(argv) == 6 and argv[1] == "escalate":
        _, _, ledger, id_s, reason, ts = argv
        if not reason.strip():
            return fail("an escalation needs --reason: what only the person knows")
        return mark(ledger, id_s, "escalated", {"reason": reason, "ts": ts})
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
