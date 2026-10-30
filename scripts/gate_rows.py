"""gate_rows.py: gate rows that scripts/temper asks for by name, one mode per call (each prints JSON rows, one per line).

  python3 gate_rows.py intent-blocking INTENT.md   the row for a Blocking question left open in a draft intent

They live here so scripts/temper stays under the directory's 256 KiB limit. Standard library only.
"""
import json
import re
import sys


def row(name, ok, detail):
    return {"name": name, "pass": ok, "detail": detail}


def intent_blocking(path):
    """A draft intent fails while a `- Blocking:` line is under its Open Questions: the person answers it first (it goes
    into Decisions). A Deferred question and an accepted or completed intent pass."""
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return row("blocking question open", True, "intent.md unreadable; the other rows report it")
    m = re.search(r"^\*\*Status:\*\*\s*(draft|accepted|completed)\s*$", text, re.I | re.M)
    status = m.group(1).lower() if m else None
    if status != "draft":
        return row("blocking question open", True, "skipped: the intent is %s; this check applies to drafts only" % (status or "of no known status"))
    open_q, active = [], False
    for line in text.splitlines():
        h = re.match(r"^#{1,6}\s+(.*)$", line)
        if h:
            active = bool(re.match(r"open questions", h.group(1).strip(), re.I))
            continue
        b = re.match(r"^\s*[-*]\s+Blocking:\s*(.+)$", line) if active else None
        if b:
            open_q.append(b.group(1).strip())
    if open_q:
        return row("blocking question open", False, "%d Blocking question(s) open: %s%s; answer them before the plan" % (
            len(open_q), open_q[0][:80], "" if len(open_q) == 1 else " and %d more" % (len(open_q) - 1)))
    return row("blocking question open", True, "no Blocking question is open")


def main(argv):
    if len(argv) == 3 and argv[1] == "intent-blocking":
        print(json.dumps(intent_blocking(argv[2])))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
