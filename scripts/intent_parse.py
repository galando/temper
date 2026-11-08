"""intent_parse.py: the lifecycle state and the open Blocking questions of an intent.md, read one way.

flow.py (what comes next, the questions it asks), gate_rows.py (the Intent gate's "blocking question open" row) and
intent_closure_rows.py / intent_draft_rows.py (the draft rows) read them here, so a question the flow asks is one the
gate counts, and one the CLI can answer (`temper intent answer` and `intent carry` match the same line). Standard
library only.
"""
import re

STATES = ("draft", "accepted", "completed")
_STATUS = re.compile(r"^\*\*Status:\*\*(.*)$", re.M)
# A Blocking line under ### Open Questions, as the CLI's answer and carry match it (scripts/answer_ops.py, intent carry):
# a bullet, an optional checkbox, then `Blocking:`.
_BLOCKING = re.compile(r"^\s*[-*]\s+(?:\[[ xX]\]\s+)?Blocking:\s*(.+)$")
_CONTEXT_CHECK = re.compile(r"^context check:", re.I)


def status(text):
    """The intent's state: the value of its first **Status:** line (the line `temper intent accept` rewrites), when it is
    draft, accepted or completed (in any case, with spaces around), else None (no line, or a placeholder)."""
    m = _STATUS.search(text or "")
    v = m.group(1).strip().lower() if m else ""
    return v if v in STATES else None


def blocking(text, context_check=True):
    """The open Blocking questions, in order: the text after `Blocking:` of each Blocking line under the Open Questions
    heading (to the next heading). A placeholder bullet (`- {...}`) is not a Blocking line. With context_check False, the Context check
    line Plan writes is left out (the flow asks it with its own question)."""
    out, active = [], False
    for line in (text or "").splitlines():
        h = re.match(r"^#{1,6}\s+(.*)$", line)
        if h:
            active = bool(re.match(r"open questions", h.group(1).strip(), re.I))
            continue
        m = _BLOCKING.match(line) if active else None
        if not m:
            continue
        q = m.group(1).strip()
        if not context_check and _CONTEXT_CHECK.match(q):
            continue
        out.append(q)
    return out
