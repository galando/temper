"""plan_ops.py: the Context Map of plan.md and the person's Context check (F6).

Plan writes `## Context Map` at the top of plan.md, after exploring and before any scenario: one line per source of context,
never per code file (an area is one line: `src/auth/ (12 files)`):

  ## Context Map
  - use: intent.md AC-01..AC-04 - the accepted scope
  - ignore: .temper/specs/old-login/ - a finished feature, other scope
  - gap: no rate-limit policy found in code, docs or the ticket
  - reviewed: auto - every source is current and on topic

Modes (python3 plan_ops.py <mode> ...):
  row SPEC_DIR MODE            the plan gate row `context map reviewed` as JSON; MODE is plan.context-check: auto, always or off
  review SPEC_DIR --answer TEXT [--focus AREA]...   write the person's answer into the map and set `- reviewed: human`
  map SPEC_DIR                 the map as JSON for `temper next` and the view

The CLI writes the `reviewed:` line, never Plan and never a model by hand: auto mode may refuse an edit of it
(docs/auto-mode.md). Text is data: one line, at most 100 characters. Standard library only.
"""
import json
import os
import re
import sys

KINDS = ("use", "ignore", "gap")
MAX_ENTRIES = 12
MAX_LINE = 100
HEADING = re.compile(r"^##\s+Context Map\s*$", re.M)
ENTRY = re.compile(r"^-\s+(use|ignore|gap|reviewed|answer|focus):\s*(.*?)\s*$")


def read(spec):
    try:
        return open(os.path.join(spec, "plan.md"), encoding="utf-8").read()
    except OSError:
        return None


def section(text):
    """(start, end, lines) of the Context Map section of plan.md text, or None."""
    m = HEADING.search(text or "")
    if not m:
        return None
    rest = text[m.end():]
    n = re.search(r"^##\s", rest, re.M)
    end = m.end() + (n.start() if n else len(rest))
    return m.start(), end, text[m.end():end].splitlines()


def parse(spec):
    text = read(spec)
    sec = section(text) if text is not None else None
    if sec is None:
        return None
    entries, reviewed, answer, focus, intro, long_lines = [], "", "", [], [], []
    for line in sec[2]:
        if len(line.strip()) > MAX_LINE:
            long_lines.append(line.strip())
        m = ENTRY.match(line.strip())
        if not m:
            if line.strip() and not entries and not reviewed:
                intro.append(line.strip())
            continue
        kind, val = m.group(1), m.group(2)
        if kind in KINDS:
            entries.append({"kind": kind, "text": val})
        elif kind == "reviewed":
            reviewed = val.split(" ")[0].strip(" -:").lower() if val else ""
        elif kind == "answer":
            answer = val
        elif kind == "focus":
            focus.append(val)
    return {"entries": entries, "reviewed": reviewed, "answer": answer, "focus": focus, "intro": " ".join(intro), "long": long_lines}


def row(ok, detail):
    return {"name": "context map reviewed", "pass": ok, "detail": detail}


def gate_row(spec, mode):
    mode = mode if mode in ("auto", "always", "off") else "auto"
    m = parse(spec)
    if m is None:
        return row(False, "plan.md has no ## Context Map at the top: list the sources of context (use, ignore, gap), then the reviewed line")
    if not m["entries"]:
        return row(False, "the Context Map has no use, ignore or gap entry")
    if len(m["entries"]) > MAX_ENTRIES:
        return row(False, "the Context Map has %d entries; keep it to %d, one line per source (group an area: src/auth/ (12 files))" % (len(m["entries"]), MAX_ENTRIES))
    if m["long"]:
        return row(False, "a Context Map line is over %d characters; shorten: %s" % (MAX_LINE, m["long"][0][:60]))
    if m["reviewed"] not in ("human", "auto") and not (mode == "off" and m["reviewed"] == "pending"):
        return row(False, "the Context check is pending: the person's answer is not recorded yet (it is asked as the Is this the right context for the plan? question)"
                   if m["reviewed"] == "pending" else "the Context Map has no `- reviewed: human|auto` line")
    if m["reviewed"] == "auto" and mode != "off":
        flagged = [e["kind"] for e in m["entries"] if e["kind"] in ("ignore", "gap")]
        if mode == "always":
            return row(False, "plan.context-check is always: the person reviews the map every run (reviewed: auto is not accepted)")
        if flagged:
            return row(False, "the map has an %s entry, so the person reviews it (reviewed: auto is not accepted)" % flagged[0])
    return row(True, "%d source(s) listed, reviewed: %s" % (len(m["entries"]), m["reviewed"]))


def table(m):
    out = ["Context Map"]
    for e in m["entries"]:
        out.append("%-7s %s" % (e["kind"], e["text"]))
    if m["answer"]:
        out.append("answer  %s" % m["answer"])
    for f in m["focus"]:
        out.append("focus   %s" % f)
    return "\n".join(out)


def map_json(spec):
    m = parse(spec)
    if m is None:
        return None
    return {"intro": m["intro"] or "The sources Plan used, one line each.", "file": os.path.join(spec, "plan.md"), "rows": m["entries"],
            "answer": m["answer"], "reviewed": m["reviewed"], "table": table(m)}


def review(spec, answer, focus):
    text = read(spec)
    if text is None:
        raise ValueError("there is no plan.md in %s" % spec)
    sec = section(text)
    if sec is None:
        raise ValueError("plan.md has no ## Context Map to review")
    answer = " ".join(str(answer).split())
    if not answer or len(answer) > MAX_LINE:
        raise ValueError("the answer is one line of at most %d characters" % MAX_LINE)
    focus = [" ".join(str(f).split()) for f in focus]
    if any(not f or len(f) > MAX_LINE for f in focus):
        raise ValueError("a focus area is one line of at most %d characters" % MAX_LINE)
    kept = [l for l in sec[2] if not re.match(r"^-\s+(reviewed|answer|focus):", l.strip())]
    while kept and not kept[-1].strip():
        kept.pop()
    body = kept + ["- answer: %s" % answer] + ["- focus: %s" % f for f in focus] + ["- reviewed: human"]
    new = text[:sec[0]] + "## Context Map\n" + "\n".join(body) + "\n\n" + text[sec[1]:].lstrip("\n")
    tmp = os.path.join(spec, ".plan.md.tmp.%d" % os.getpid())
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(new)
    os.replace(tmp, os.path.join(spec, "plan.md"))


def main(argv):
    try:
        if len(argv) == 4 and argv[1] == "row":
            print(json.dumps(gate_row(argv[2], argv[3])))
            return 0
        if len(argv) == 3 and argv[1] == "map":
            print(json.dumps(map_json(argv[2])))
            return 0
        if len(argv) >= 5 and argv[1] == "review" and argv[3] == "--answer":
            focus = [argv[i + 1] for i, a in enumerate(argv) if a == "--focus" and i + 1 < len(argv)]
            review(argv[2], argv[4], focus)
            print("OK: the Context Map is reviewed by the person: %s" % " ".join(argv[4].split()))
            return 0
    except ValueError as e:
        print("FAIL: %s" % e, file=sys.stderr)
        return 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
