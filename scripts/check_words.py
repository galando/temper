#!/usr/bin/env python3
"""check_words.py: the words a user learns, and the retired words no text a user reads holds (9.8.5, WP31).

`scripts/words.json` holds `words`, at most 12, each with the one line a user gets, and `retired`, each retired word
with what replaces it. This script checks the plugin folder it sits in:

  1. `words.json`: at most 12 words, each with a line that is not empty; every retired word the plan names (RETIRED
     below) is on its `retired` list, which may hold more;
  2. the part `## The words` of `docs/getting-started.md` has one line for each word (a table row whose first cell is
     the word, or a list line that starts with it) and no other entry;
  3. no retired word, as a whole word in any letter case, in what a user reads of a view of the two fixture files
     (`scripts/selftest/view-fixtures.ts` and `view-fixtures-2.ts`): the question, each option's label and
     description, the `say`, the status line and the card;
  4. nor on a page a user reads: `README.md`, `docs/getting-started.md`, `docs/index.md`, `docs/commands.md`, the
     comments of `templates/temper.config.default`, the Arguments table of `commands/temper.md` and the `description`
     of `.claude-plugin/plugin.json`. Code blocks, code spans, link targets and key names are left out.

A retired word inside a name is no word: `phases.pipeline`, `phaseModels`, `park-on-touch` and `run-armed` are names,
"sparkline" holds no "park" and "alarm" no "arm". The texts the mod draws are held by a test of the mod, with the list
written in the test, because a plugin test reads no file; this script names no folder of the mod.

The shapes of `words.json` it reads: `words` is an object (word to line) or a list of objects (`word`, `line`) or of
pairs; `retired` is an object (retired word to what replaces it) or a list of strings, of pairs, or of objects that
hold `word` or `words` (a list of words that share one replacement).

  python3 scripts/check_words.py

Python 3 only, well under a second. Exit 0 when every rule holds, else 1 with one line a fault.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MAX_WORDS = 12
# The retired words the plan names (docs/plans/one-go/wp/phase-7-and-8-front-and-surface.md, WP31 mechanism step 2):
# words.json may add to them and never drops one.
RETIRED = ["armed", "arm", "arms", "arming", "parked", "park", "parks", "phase", "phases", "door", "doors",
           "Autonomous Build", "Stage by stage", "preflight", "band", "hand back"]
FIXTURES = ["scripts/selftest/view-fixtures.ts", "scripts/selftest/view-fixtures-2.ts"]
PAGES = ["README.md", "docs/getting-started.md", "docs/index.md", "docs/commands.md"]
TEMPLATE = "templates/temper.config.default"
COMMAND = "commands/temper.md"
MANIFEST = ".claude-plugin/plugin.json"


def read(rel):
    try:
        with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def flat(items):
    """The strings of a list whose items are strings, pairs (the first) or objects (`word`, `words`, `retired`)."""
    out = []
    for x in items:
        if isinstance(x, str):
            out.append(x)
        elif isinstance(x, (list, tuple)) and x and isinstance(x[0], str):
            out.append(x[0])
        elif isinstance(x, dict):
            for k in ("word", "retired"):
                if isinstance(x.get(k), str):
                    out.append(x[k])
            if isinstance(x.get("words"), list):
                out.extend(w for w in x["words"] if isinstance(w, str))
    return out


def the_words(data):
    """[(word, line)] of `words`."""
    w = data.get("words")
    if isinstance(w, dict):
        return [(k, v if isinstance(v, str) else json.dumps(v)) for k, v in w.items()]
    out = []
    for x in w if isinstance(w, list) else []:
        if isinstance(x, dict):
            out.append((str(x.get("word", "")), str(x.get("line") or x.get("meaning") or x.get("text") or "")))
        elif isinstance(x, (list, tuple)) and len(x) >= 2:
            out.append((str(x[0]), str(x[1])))
        elif isinstance(x, str):
            out.append((x, ""))
    return out


def the_retired(data):
    r = data.get("retired")
    return list(r.keys()) if isinstance(r, dict) else flat(r if isinstance(r, list) else [])


def matcher(words):
    """One pattern for every retired word: whole words, any letter case, a space matching any run of white space; a
    word joined to a name (a dot, a hyphen, a slash or an underscore beside it) is part of that name."""
    alts = sorted({re.escape(w.strip()).replace(r"\ ", r"\s+") for w in words if w.strip()}, key=len, reverse=True)
    return re.compile(r"(?<![\w./-])(?:%s)(?![\w/-]|\.\w)" % "|".join(alts), re.I)


def prose(text):
    """A text without code blocks, code spans, link targets and addresses, as a user reads it."""
    text = re.sub(r"```.*?```", " ", text, flags=re.S)
    text = re.sub(r"`[^`\n]*`", " ", text)
    text = re.sub(r"\]\([^)\s]*\)", "]", text)
    return re.sub(r"https?://\S+", " ", text)


def section(text, heading):
    """The lines under a `## ` heading, up to the next one."""
    if heading not in text:
        return ""
    return text.split(heading, 1)[1].split("\n## ", 1)[0]


def entries(sec):
    """The term of each entry of a part: the first cell of each table row (not the header, not the separator), or what
    a list line starts with, before its first colon, dash or pipe."""
    out, header = [], False
    for line in sec.splitlines():
        s = line.strip()
        if s.startswith("|"):
            if re.match(r"^\|[\s:|-]+\|?$", s):
                continue
            if not header:
                header = True
                continue
            cell = s.strip("|").split("|")[0]
            out.append(re.sub(r"[*`_]", "", cell).strip().lower())
        elif re.match(r"^[-*] ", s):
            term = re.split(r":|\s[-–—]\s|\|", s[2:], 1)[0]
            out.append(re.sub(r"[*`_]", "", term).strip().lower())
    return out


def view_texts(v):
    """What a user reads of one view: the texts of its questions, its say and status, and its card."""
    out = []

    def asks(o):
        if isinstance(o, dict):
            for k, x in o.items():
                if k in ("calls", "do"):
                    continue
                if k in ("question", "header", "label", "description") and isinstance(x, str):
                    out.append(x)
                else:
                    asks(x)
        elif isinstance(o, list):
            for x in o:
                asks(x)

    def card(o):
        if isinstance(o, dict):
            for k, x in o.items():
                if k not in ("id", "file", "run_id", "tag", "kind"):
                    card(x)
        elif isinstance(o, list):
            for x in o:
                card(x)
        elif isinstance(o, str):
            out.append(o)

    asks(v.get("ask"))
    asks(v.get("blocking_asks"))
    nxt = v.get("next")
    if isinstance(nxt, dict) and isinstance(nxt.get("say"), str):
        out.append(nxt["say"])
    if isinstance(v.get("status"), str):
        out.append(v["status"])
    card(v.get("card"))
    return out


def views(rel):
    text = read(rel)
    if text is None or "= {" not in text:
        return None
    try:
        return json.loads(text[text.index("= {") + 2:].rstrip().rstrip(";"))
    except ValueError:
        return None


def main():
    faults = []
    raw = read("scripts/words.json")
    try:
        data = json.loads(raw) if raw is not None else None
    except ValueError:
        data = None
    if not isinstance(data, dict):
        faults.append("scripts/words.json: missing or not a JSON object")
        data = {}
    words = the_words(data)
    if data and not words:
        faults.append("scripts/words.json: no words")
    if len(words) > MAX_WORDS:
        faults.append("scripts/words.json: %d words, at most %d" % (len(words), MAX_WORDS))
    for w, line in words:
        if not w.strip() or not line.strip():
            faults.append("scripts/words.json: the word %r has no line" % w)
    retired = the_retired(data)
    low = {r.strip().lower() for r in retired}
    missing = [r for r in RETIRED if r.lower() not in low]
    if data and missing:
        faults.append("scripts/words.json: retired lacks %s" % ", ".join(missing))
    word = matcher(retired + RETIRED)

    gs = read("docs/getting-started.md") or ""
    sec = section(gs, "## The words")
    if not sec:
        faults.append("docs/getting-started.md: no part ## The words")
    elif words:
        have = entries(sec)
        for w, _ in words:
            n = have.count(w.strip().lower())
            if n != 1:
                faults.append("docs/getting-started.md, The words: %r has %d lines" % (w, n))
        extra = sorted(set(have) - {w.strip().lower() for w, _ in words})
        if extra:
            faults.append("docs/getting-started.md, The words: entries not in words.json: %s" % ", ".join(extra))

    for rel in FIXTURES:
        vs = views(rel)
        if vs is None:
            faults.append("%s: no views read" % rel)
            continue
        for name, v in vs.items():
            for t in view_texts(v if isinstance(v, dict) else {}):
                m = word.search(t)
                if m:
                    faults.append("%s, view %s: %r in %r" % (rel, name, m.group(0), t[:100]))
                    break

    def page(where, text):
        m = word.search(prose(text))
        if m:
            faults.append("%s: %r" % (where, m.group(0)))

    for rel in PAGES:
        text = read(rel)
        if text is None:
            faults.append("%s: missing" % rel)
        else:
            page(rel, text)
    tpl = read(TEMPLATE) or ""
    comments = [l.split("#", 1)[1] for l in tpl.splitlines() if "#" in l]
    page(TEMPLATE + " (its comments)", "\n".join(re.sub(r"^\s*[\w.-]+\s*:", " ", c) for c in comments))
    cmd = read(COMMAND) or ""
    page(COMMAND + " (the Arguments table)",
         "\n".join(l for l in section(cmd, "## Arguments").splitlines() if l.strip().startswith("|")))
    try:
        desc = json.loads(read(MANIFEST) or "{}").get("description", "")
    except ValueError:
        desc = ""
    page(MANIFEST + " (description)", desc if isinstance(desc, str) else "")

    for f in faults:
        print("FAIL: " + f)
    print("check_words: %s" % ("PASS" if not faults else "%d fault(s)" % len(faults)))
    return 1 if faults else 0


if __name__ == "__main__":
    sys.exit(main())
