"""findings.py: how the author answers a finding without accepting it (9.7.6). Accepting stays the person's call.

  python3 findings.py contest LEDGER.json ID CITE REASON TS    a contest the reviewer could check: CITE names a file in the
                                                               project (path, path:LINE or path:SYMBOL) that shows the
                                                               finding is wrong
  python3 findings.py escalate LEDGER.json ID REASON TS        the evidence is outside every file (a team rule, a spoken
                                                               decision): the person decides, with what only they know

Both keep the finding open: the gate still counts it, and the gate question shows the contest or the escalation, so the
person accepts it or sends it back. A contest with no readable citation is refused: "This was intentional" is not
evidence. The citation is checked here, from the project folder: the file exists inside the project, the line exists,
the symbol is in the file. Standard library only.
"""
import json
import os
import re
import sys


def fail(msg):
    print("FAIL: %s" % msg, file=sys.stderr)
    return 1


def check_cite(cite, root):
    """None when CITE names something a reviewer could read, else why not."""
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
    if not what:
        return None
    try:
        text = open(full, encoding="utf-8", errors="replace").read()
    except OSError:
        return "%s cannot be read" % path
    if what.isdigit():
        n = text.count("\n") + (0 if text.endswith("\n") or not text else 1)
        return None if 1 <= int(what) <= n else "%s has %d line(s), not line %s" % (path, n, what)
    return None if what in text else "%s does not contain '%s'" % (path, what)


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
    if len(argv) == 7 and argv[1] == "contest":
        _, _, ledger, id_s, cite, reason, ts = argv
        if not reason.strip():
            return fail("a contest needs --reason")
        why = check_cite(cite, os.path.realpath(os.getcwd()))
        if why:
            return fail("%s. A contest must cite a file the reviewer could read; when the evidence is outside every file, "
                        "use temper evidence escalate" % why)
        return mark(ledger, id_s, "contested", {"cite": cite.strip(), "reason": reason, "ts": ts})
    if len(argv) == 6 and argv[1] == "escalate":
        _, _, ledger, id_s, reason, ts = argv
        if not reason.strip():
            return fail("an escalation needs --reason: what only the person knows")
        return mark(ledger, id_s, "escalated", {"reason": reason, "ts": ts})
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
