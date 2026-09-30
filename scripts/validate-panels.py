#!/usr/bin/env python3
"""validate-panels.py — one closed panel per stage brief.

Every agents/*.md brief must:
  1. state the panel rule itself (the brief is all a clean-context stage reads);
  2. show at most ONE panel (a fenced code block containing box borders), and that
     panel must be a single closed box: every line the same width, `+` corners,
     `|` content rows, at least one titled `+--- NAME (N) ---+` section.

It rejects the two degenerate shapes: the count-only box (a closed box with no
titled sections — "Files: 3" tells the reader nothing) and the box-plus-loose-lines
shape (panel rows leaking past the closing border — which box renders then depends
on read order).

Stdlib only. Exit 0 = all briefs conform; exit 1 names each violation.
"""
import re
import sys
from pathlib import Path

RULE_PHRASE = re.compile(r"exactly (ONE|one) closed panel", re.I)
FULL_BORDER = re.compile(r"^\+[-+]*\+$")
# A section divider: '+--- NAME (N) ---+-------...---+' — a border carrying a title.
TITLED_BORDER = re.compile(r"^\+--- [^+]*?\(N\)[^+]*?\+-[-+]*\+$")
BORDER = re.compile(r"^(?:\+[-+]*\+|\+--- [^+]*?\(N\)[^+]*?\+-[-+]*\+)$")
TITLED = TITLED_BORDER


def extract_fences(text):
    """Yield (start_line, block_lines) for each ``` fenced block."""
    lines = text.splitlines()
    i, blocks = 0, []
    while i < len(lines):
        if lines[i].strip().startswith("```"):
            j = i + 1
            block = []
            while j < len(lines) and not lines[j].strip().startswith("```"):
                block.append(lines[j])
                j += 1
            blocks.append((i + 2, block))  # 1-based line of first block line
            i = j + 1
        else:
            i += 1
    return blocks


def validate_panel(block):
    """Return a list of error strings for one panel-shaped block."""
    errs = []
    border_rows = [k for k, ln in enumerate(block) if BORDER.match(ln.strip())]
    if not border_rows:
        return []  # not a panel (some other fenced content)
    first, last = border_rows[0], border_rows[-1]
    if first != 0:
        errs.append("panel box does not start at the top of its fence")
    if not FULL_BORDER.match(block[first].strip()) or not FULL_BORDER.match(block[last].strip()):
        errs.append("outer frame is not a full '+---+' border")
    # uniform width across the box itself (first border .. last border)
    widths = {len(ln) for ln in block[first:last + 1]}
    if len(widths) > 1:
        errs.append("panel rows are not a uniform width (%s)" % sorted(widths))
    # closed: content rows between borders must be '|' rows
    for k in range(first, last + 1):
        ln = block[k].rstrip()
        if BORDER.match(ln.strip()):
            continue
        if not (ln.startswith("|") and ln.endswith("|")):
            errs.append("line %d inside the box is not a padded '|' row: %r" % (k + 1, ln[:40]))
    # at least one titled section
    if not any(TITLED.match(block[k].strip()) for k in border_rows):
        errs.append("count-only box: no titled '+--- NAME (N) ---+' section")
    # no panel-shaped lines leaking past the closing border
    for ln in block[last + 1:]:
        if ln.lstrip().startswith(("+", "|")):
            errs.append("loose panel row past the closing border: %r" % ln[:40])
    return errs


def main():
    repo = Path(__file__).resolve().parent.parent
    agents_dir = repo / "agents"
    files = sorted(agents_dir.glob("*.md"))
    if not files:
        print("FAIL: no agents/*.md found")
        return 1
    failures = 0
    for f in files:
        text = f.read_text(encoding="utf-8")
        errs = []
        if not RULE_PHRASE.search(text):
            errs.append("does not state the one-panel rule ('exactly ONE closed panel')")
        panels = 0
        for lineno, block in extract_fences(text):
            if any(BORDER.match(ln.strip()) for ln in block):
                panels += 1
                for e in validate_panel(block):
                    errs.append("panel at line %d: %s" % (lineno, e))
        if panels > 1:
            errs.append("shows %d panels — a stage returns exactly one" % panels)
        if errs:
            failures += 1
            print("FAIL %s" % f.relative_to(repo))
            for e in errs:
                print("      - %s" % e)
        else:
            print("PASS %s" % f.relative_to(repo))
    print()
    if failures:
        print("FAIL: %d brief(s) violate the one-panel rule" % failures)
        return 1
    print("PASS: every stage brief states and shows the one-panel rule")
    return 0


if __name__ == "__main__":
    sys.exit(main())
