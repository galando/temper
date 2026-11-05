#!/usr/bin/env python3
"""answer_ops.py: the person's answer to a Blocking question, written by the CLI (9.8.0).

  answer_ops.py SPEC QUESTION ANSWER [QUESTION ANSWER ...]
                                          `temper intent answer '<question>' '<answer>' ['<question>' '<answer>' ...]`:
                                          one call for every answer of a dialog (a session that wrote six calls with the
                                          CLI's long path put the path in a shell variable, which the mod refuses)

Earlier the session wrote each answer itself: it read intent.md, then edited it (in the measured runs, with a Python
script typed into a Bash call), and when the edit left a stray line the Intent gate failed and it edited again. That was
two to four turns per stage that asks, each rereading the whole conversation, and on a cheaper model it was where the
session started editing spec files of its own accord. Now one call per answer:

  - the Blocking line of `### Open Questions` whose question starts like QUESTION (as `temper intent carry` matches it)
    leaves that section;
  - `### Decisions` gains `- {question} -> {answer} (the person, {date})`, the template's row; a placeholder row there
    (`(none yet)`, `none`) goes;
  - a question that starts with `Design:` names an area of concern in design.md: the open concern that shares the most
    words with it gets a `resolved: {answer}` line (when none shares enough, the Design question resolves it as written).

It changes nothing when no Blocking question matches (exit 1). Standard library only.
"""
import datetime
import os
import re
import sys

import flow

PLACEHOLDER = re.compile(r"^\s*[-*]\s+\(?(none( yet)?|n/?a|tbd)\)?\.?\s*$", re.I)


def norm(t):
    return re.sub(r"\W+", " ", t).strip().lower()


def question_of(text):
    """The question part of a Blocking line: the text before ` choices:`."""
    return re.split(r"\s+choices:\s*", text, maxsplit=1)[0].strip()


def write(path, lines):
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    os.replace(tmp, path)


def answer_intent(spec, q, answer, day):
    path = os.path.join(spec, "intent.md")
    lines = open(path, encoding="utf-8").read().split("\n")
    want = norm(question_of(q))[:60]
    active, hit = False, None
    for i, l in enumerate(lines):
        h = re.match(r"^#{1,6}\s+(.*)$", l)
        if h:
            active = bool(re.match(r"open questions", h.group(1).strip(), re.I))
            continue
        m = re.match(r"^\s*[-*]\s+(?:\[[ xX]\]\s+)?Blocking:\s*(.+)$", l) if active else None
        if m and want and (norm(question_of(m.group(1))).startswith(want) or want.startswith(norm(question_of(m.group(1)))[:60])):
            hit = (i, question_of(m.group(1)))
            break
    if hit is None:
        return None
    i, asked = hit
    del lines[i]
    if 0 < i < len(lines) and not lines[i].strip() and not lines[i - 1].strip():
        del lines[i]   # no double blank line where the question was
    row = "- %s -> %s (the person, %s)" % (asked, " ".join(answer.split()), day)
    dec = next((k for k, l in enumerate(lines) if re.match(r"^#{1,6}\s+decisions\s*$", l.strip(), re.I)), None)
    if dec is None:
        # No Decisions section: one goes right after Open Questions' section, before the next heading.
        oq = next((k for k, l in enumerate(lines) if re.match(r"^#{1,6}\s+open questions", l.strip(), re.I)), None)
        lvl = len(re.match(r"^(#+)", lines[oq]).group(1)) if oq is not None else 3
        at = next((k for k in range((oq or 0) + 1, len(lines)) if re.match(r"^#{1,%d}\s" % lvl, lines[k])), len(lines))
        lines[at:at] = ["%s Decisions" % ("#" * lvl), "", row, ""]
    else:
        lvl = len(re.match(r"^(#+)", lines[dec].strip()).group(1))
        end = next((k for k in range(dec + 1, len(lines)) if re.match(r"^#{1,%d}\s" % lvl, lines[k]) or lines[k].strip() == "---"), len(lines))
        body = [k for k in range(dec + 1, end) if PLACEHOLDER.match(lines[k])]
        for k in reversed(body):
            del lines[k]
            end -= 1
        filled = [k for k in range(dec + 1, end) if lines[k].strip()]
        if filled:
            lines[filled[-1] + 1:filled[-1] + 1] = [row]
        else:   # an empty section (or one that held only the placeholder): the row, between two blank lines
            lines[dec + 1:end] = ["", row, ""]
    write(path, lines)
    return asked


def resolve_concern(spec, asked, answer):
    """The open concern of design.md that matches a `Design:` question: a `resolved:` line in it. The title of the concern
    that matched, else None."""
    path = os.path.join(spec, "design.md")
    if not os.path.isfile(path):
        return None
    lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
    words = lambda t: {w for w in norm(t).split() if len(w) > 2}
    want = words(re.sub(r"^\s*design:\s*", "", asked, flags=re.I))
    best, score = None, 0.0
    for b in flow.concern_blocks(lines):
        if b["resolved"]:
            continue
        have = words(" ".join(lines[b["start"]:b["end"]]))
        s = len(want & have) / max(1, len(want))
        if s > score:
            best, score = b, s
    if best is None or score < 0.4:
        return None
    m = re.match(r"^(?:[-*]|\d+[.)])\s+", lines[best["start"]]) if best["item"] else None
    lines[best["end"]:best["end"]] = ["", "%sresolved: %s" % (" " * len(m.group(0)) if m else "", " ".join(answer.split()))]
    write(path, lines)
    return best["title"]


def main(argv):
    pairs = argv[1:]
    if len(argv) < 3 or len(pairs) % 2 or any(not x.strip() for x in pairs):
        print("FAIL: usage: temper intent answer '<question>' '<answer>' ['<question>' '<answer>' ...]", file=sys.stderr)
        return 1
    spec, rc = argv[0], 0
    for q, answer in zip(pairs[0::2], pairs[1::2]):
        asked = answer_intent(spec, q, answer, datetime.date.today().isoformat())
        if asked is None:
            print("FAIL: no Blocking open question starts with: %s" % q[:80], file=sys.stderr)
            rc = 1
            continue
        print("OK: answered: %s" % asked[:80])
        if re.match(r"^\s*design:", asked, re.I):
            title = resolve_concern(spec, asked, answer)
            print("OK: resolved in design.md: %s" % title[:80] if title else "Note: no open concern in design.md matched; the Design question resolves it")
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
