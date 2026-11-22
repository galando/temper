#!/usr/bin/env python3
"""check_done.py: every promise of docs/plans/one-go/done.md has its check, 9.8.5 (WP07).

  python3 scripts/check_done.py [--final] [--root DIR]

It reads the table under the heading "The table" of `docs/plans/one-go/done.md` and the expected to fail list,
`scripts/selftest/expected-fail.txt`, and fails when:
  - a row whose fourth cell is `yes` (it needs no model) names no check, or a row id is used twice;
  - a `case NN <token>` item names a token that no assertion of `scripts/selftest/temper-cases-NN.sh` starts with (the
    token and a space, after a quote: a token is a whole word, so `D10` never matches `D100`);
  - a `scenario <name>` item names a scenario that no file of `scripts/e2e` registers (its quoted name as a key);
  - a line of the list matches no check, names a token that is not a token of the table, or names a scenario that is
    not one of `scripts/e2e/accept.ts`, `scripts/e2e/slow.ts` or `scripts/e2e/broken.ts`;
  - a check of the list was taken off it by an earlier commit and is on it again, in any form (an e2e line stands for
    its scenario in each mode it names, every mode when it names none; from `git log -p` of the list; a
    checkout with no history shows no such commit);
  - a test file of the mod (the pathspecs `*.test.ts` and `*.test.tsx`) holds `.skip(`, `.only(` or `.todo(`;
  - a scenario of those three files does not call the shared assert `worldCheck` (row D105), in its own body or in a
    function of the same file it calls;
  - one of the rows `D30` to `D39` names neither a case nor a scenario that runs in plain mode (rule 11, row D40);
  - a scenario of the three files registers no mode, or modes it cannot read; a row names a mode for one of them that
    it does not register; or a line `e2e:<scenario>:<mode>` names a mode the scenario does not run. A scenario item
    with no mode words means the modes the scenario registers, and rule 11 reads those.
A `mod` item is not looked up: the mod's own suite runs every test file. A `gate` and a `bench` item are not run here.

With `--final` it also fails while the list has an entry, and it runs D75b: each `final` of `scripts/caps.json` and
`scripts/e2e/floor.json` equals the value the table writes after `=` for its key, every such key of the table has its
`final`, and no `final` is above its value in the commit that first added the key. Two more rules close the build
(WP32): each of WP00 to WP31 has a line in the table "Packages" of `docs/plans/one-go/PROGRESS.md` whose state is
`done` or `blocked` (a line that is `todo` or `doing`, or no line, fails; the line of WP32 is not read); and the
working papers, the folder `evidence` of `docs/plans/one-go`, are not tracked (`git ls-files` of the folder prints
nothing) and no tracked file outside `docs/plans/one-go` names the folder by its path.

  python3 scripts/check_done.py --summary [--root DIR]

The form of the summary of the build (row D107), and nothing else: it fails when `docs/history/build-9.8.5.md` is
missing, has more than 150 lines, lacks one of the eight headings of level two of `docs/plans/one-go/contracts.md`
section 8 or has them in another order (each once), or when its part 3 (under `## The plan, item by item`) has no line
for an item id of `docs/plans/two-approval-run.md` or a line there holds none of the three states. An item id is one
digit and one letter at the start of a list item under the headings `### Release 0.` to `### Release 7.` of the plan
(`- **0a, first ...` or `- **2e. The approval ...`); `Pass line` and the other entries with no id are not items. A line
of part 3 is a table row whose first cell is the id, and its state is a cell that is exactly `built and proven`,
`built and not proven` or `not built`.

It prints one line a row: the id and `ok`, `expected to fail` (a check of the row is on the list) or `open` (the row
needs a model or a person, a `final` it names is not written yet, or a cap it names has its `now` above its `final`:
such a row is never `ok`, and with `--final` it fails), or `FAIL` with what is missing; then the count of the list. Python 3 and git only. Exit 0 when every rule holds, else 1 (2 for a wrong call).
"""
import json
import os
import re
import subprocess
import sys

DONE = "docs/plans/one-go/done.md"
LIST = "scripts/selftest/expected-fail.txt"
SELFTEST = "scripts/selftest"
E2E = "scripts/e2e"
CAPS = "scripts/caps.json"
FLOOR = "scripts/e2e/floor.json"
THREE = ("accept.ts", "slow.ts", "broken.ts")
KINDS = ("case", "scenario", "floor", "caps", "mod", "gate", "bench")
MODES = ("plain", "mod", "driver")
RULE_ROWS = ["D%d" % n for n in range(30, 40)]
KIT = "docs/plans/one-go"
PROGRESS = KIT + "/PROGRESS.md"
PAPERS = os.path.join(KIT, "evidence")   # the working papers (the path is joined so this file does not name it)
PACKAGES = ["WP%02d" % n for n in range(0, 32)]
SUMMARY = "docs/history/build-9.8.5.md"
PLAN = "docs/plans/two-approval-run.md"
SUMMARY_LINES = 150
HEADINGS = ["In five lines", "The numbers, before and after", "The plan, item by item",
            "What changes for someone who used 9.8.4", "What went differently from the plan",
            "What is not done, and what is yours to do", "The build in numbers", "Was it run for real"]
STATES = ("built and proven", "built and not proven", "not built")
ITEM = re.compile(r"^- \*\*([0-7][a-z])[.,]")
SPAN = re.compile(r"`([^`]+)`")
VALUE = re.compile(r"\s*=\s*([^\s;,()]+)(?:\s+in\s+(plain|mod|driver)\s+mode)?")
MODES_AFTER = re.compile(r"\s+((?:plain|mod|driver)(?:\s*,\s*(?:plain|mod|driver))*)\b")
IDENT = r"[A-Za-z_$][\w$]*"


def read(root, rel):
    p = os.path.join(root, rel)
    if not os.path.isfile(p):
        return None
    with open(p, encoding="utf-8", errors="replace") as f:
        return f.read()


def git(root, *args):
    p = subprocess.run(["git", "-C", root] + list(args), capture_output=True, text=True, errors="replace")
    return p.returncode, p.stdout


# ---- the table ---------------------------------------------------------------------------------------------------------

def cells_of(line):
    """The cells of a table line, split on `|` outside code spans."""
    out, cur, tick = [], [], False
    for ch in line.strip().strip("|"):
        if ch == "`":
            tick = not tick
        if ch == "|" and not tick:
            out.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
    out.append("".join(cur).strip())
    return out


def table(text):
    """[(line number, cells)] of the rows under the heading "The table"."""
    rows, inside = [], False
    for n, line in enumerate(text.split("\n"), 1):
        if line.strip() == "## The table":
            inside = True
            continue
        if not inside:
            continue
        if line.startswith("## "):
            break
        if not line.startswith("|"):
            continue
        cells = cells_of(line)
        if cells[0] == "Id" or set(cells[0]) <= set("-: "):
            continue
        rows.append((n, cells))
    return rows


def parse_value(s):
    s = s.rstrip(".")
    if s in ("true", "false"):
        return s == "true"
    try:
        return int(s)
    except ValueError:
        try:
            return float(s)
        except ValueError:
            return s


def items_of(check):
    """The items of a check cell: dicts with kind, words, value (or None), mode (of the value) and modes (a scenario)."""
    items = []
    for m in SPAN.finditer(check):
        words = m.group(1).split()
        if not words or words[0] not in KINDS:
            continue
        after = check[m.end():]
        item = {"kind": words[0], "words": words[1:], "text": m.group(1), "value": None, "mode": None, "modes": None}
        v = VALUE.match(after)
        if v is not None and words[0] in ("floor", "caps"):
            item["value"] = parse_value(v.group(1))
            item["mode"] = v.group(2)
        if words[0] == "scenario":
            ms = MODES_AFTER.match(after)
            item["modes"] = re.findall(r"plain|mod|driver", ms.group(1)) if ms else list(MODES)
            item["modes_named"] = ms is not None
        items.append(item)
    return items


# ---- where the checks live ---------------------------------------------------------------------------------------------

def case_files(root):
    d = os.path.join(root, SELFTEST)
    if not os.path.isdir(d):
        return {}
    out = {}
    for f in sorted(os.listdir(d)):
        m = re.match(r"^temper-cases-(\d+)\.sh$", f)
        if m:
            out[m.group(1)] = read(root, "%s/%s" % (SELFTEST, f)) or ""
    return out


def has_token(text, token):
    """True when an assertion name in the text starts with the token and a space (the token as a whole word)."""
    return text is not None and ('"%s ' % token in text or "'%s " % token in text)


def e2e_files(root):
    d = os.path.join(root, E2E)
    if not os.path.isdir(d):
        return {}
    return {f: read(root, "%s/%s" % (E2E, f)) or "" for f in sorted(os.listdir(d))
            if f.endswith(".ts") and not f.endswith(".test.ts")}


def has_scenario(files, name):
    """True when a file of scripts/e2e registers the scenario: its quoted name as the key of an entry, or as a name:."""
    q = "['\"]%s['\"]" % re.escape(name)
    reg = re.compile(r"%s\s*:|\bname\s*:\s*%s" % (q, q))
    return any(reg.search(t) for t in files.values())


def split_top(text):
    """The parts of the text split on commas outside brackets, strings and comments."""
    parts, cur, depth, i, quote = [], [], 0, 0, None
    while i < len(text):
        ch = text[i]
        if quote is not None:
            cur.append(ch)
            if ch == "\\" and i + 1 < len(text):
                cur.append(text[i + 1])
                i += 1
            elif ch == quote:
                quote = None
        elif text.startswith("//", i):
            end = text.find("\n", i)
            i = len(text) if end < 0 else end
            continue
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = len(text) if end < 0 else end + 2
            continue
        elif ch in "'\"`":
            quote = ch
            cur.append(ch)
        elif ch in "([{":
            depth += 1
            cur.append(ch)
        elif ch in ")]}":
            depth -= 1
            cur.append(ch)
        elif ch == "," and depth == 0:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
        i += 1
    parts.append("".join(cur))
    return [x.strip() for x in parts if x.strip()]


KEY = re.compile(r"^(?:'([^']*)'|\"([^\"]*)\"|(%s))\s*:\s*(.*)$" % IDENT, re.S)


def registered(src):
    """{scenario name: entry} of a scenario file. The entries of its objects named *SCENARIOS: each key (quoted or bare)
    and its value, a function name or { run, ... } whose run is a function name or a function written in place. An
    entry is {"fn": name or None, "inline": the text of a function written in place or None, "modes": the modes it
    registers (a list literal, or the name of a const list of the file) or None, "error": what cannot be read or None}.
    A file with no such object: every object entry whose key is a lower case name joined by hyphens and whose value is
    a function or { run: function }."""
    out = {}
    for m in re.finditer(r"(?:const|let)\s+\w*SCENARIOS\b[^\n]*=\s*\{", src):
        block = braced(src, m.end() - 1) or ""
        for part in split_top(block[1:-1]):
            k = KEY.match(part)
            if k is None:
                out[part.split("\n")[0][:60]] = {"fn": None, "inline": None, "error": "an entry that cannot be read"}
                continue
            name, value = next(g for g in k.groups()[:3] if g is not None), k.group(4).strip()
            entry = {"fn": None, "inline": None, "modes": None, "error": None}
            run, modes = value, None
            if value.startswith("{"):
                run = None
                for field in split_top(value[1:-1] if value.endswith("}") else ""):
                    f = KEY.match(field)
                    if f is not None and f.group(3) == "run":
                        run = f.group(4).strip()
                    elif f is not None and f.group(3) == "modes":
                        modes = f.group(4).strip()
            entry["modes"] = modes_of(src, modes)
            if entry["modes"] is None:
                entry["error"] = "an entry whose modes cannot be read (a list of plain, mod and driver)"
            elif not entry["modes"]:
                entry["error"] = "an entry that registers no mode"
            if run is None:
                entry["error"] = "an entry with no run"
            elif re.fullmatch(IDENT, run):
                entry["fn"] = run
            elif re.match(r"^(?:async\s+)?(?:function\b|\(|%s\s*=>)" % IDENT, run):
                entry["inline"] = run
            else:
                entry["error"] = "a run that is neither a function of the file nor a function written in place"
            out[name] = entry
    if not out:
        entry = re.compile(r"['\"]([a-z0-9]+(?:-[a-z0-9]+)+)['\"]\s*:\s*(?:\{\s*run\s*:\s*)?(%s)" % IDENT)
        out = {k: {"fn": v, "inline": None, "modes": list(MODES), "error": None} for k, v in entry.findall(src)}
    return out


def modes_of(src, value):
    """The modes of a `modes:` value: a list literal of quoted modes, or the name of a const list of the file. None when
    it is missing, or is anything else, or names a word that is no mode."""
    if value is None:
        return None
    if re.fullmatch(IDENT, value):
        m = re.search(r"\bconst\s+%s\s*(?::[^=\n]+)?=\s*(\[[^\]]*\])" % re.escape(value), src)
        if m is None:
            return None
        value = m.group(1)
    if not (value.startswith("[") and value.endswith("]")):
        return None
    words = split_top(value[1:-1])
    found = [w[1:-1] for w in words if len(w) >= 2 and w[0] == w[-1] and w[0] in "'\""]
    if len(found) != len(words) or any(w not in MODES for w in found):
        return None
    return found


def braced(src, i):
    """The text from the brace at i to its match, or None."""
    if i < 0 or i >= len(src) or src[i] != "{":
        return None
    depth = 0
    for j in range(i, len(src)):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                return src[i:j + 1]
    return None


def body_of(src, ident):
    m = re.search(r"function\s+%s\s*[<(]" % re.escape(ident), src)
    if m is not None:
        return braced(src, src.find("{", src.find(")", m.end()))) if src.find(")", m.end()) >= 0 else None
    m = re.search(r"(?:const|let)\s+%s\b[^=]*=" % re.escape(ident), src)
    if m is None:
        return None
    arrow = src.find("=>", m.end())
    if arrow < 0:
        return None
    k = arrow + 2
    while k < len(src) and src[k] in " \t":
        k += 1
    if k < len(src) and src[k] == "{":
        return braced(src, k)
    end = src.find("\n", k)
    return src[k:end if end >= 0 else len(src)]


def calls_world_check(src, ident, seen=None, depth=0, body=None):
    """True when the function (or, with body, the function written in place) calls worldCheck, in its own body or in a
    function of the same file it calls."""
    seen = set() if seen is None else seen
    if body is None:
        if ident in seen or depth > 4:
            return False
        seen.add(ident)
        body = body_of(src, ident)
    if body is None:
        return False
    if re.search(r"\bworldCheck\s*\(", body):
        return True
    return any(calls_world_check(src, c, seen, depth + 1) for c in re.findall(r"\b(%s)\s*\(" % IDENT, body)
               if c != ident)


# ---- the list ------------------------------------------------------------------------------------------------------------

def read_list(text):
    """[(line number, check, suite, name, mode)] and the errors of the list."""
    out, errors = [], []
    for n, raw in enumerate((text or "").split("\n"), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        words = line.split()
        parts = words[0].split(":")
        if len(words) < 2 or not re.match(r"^WP\d{2}$", words[1]):
            errors.append("line %d of the list names no package: %s" % (n, line))
        if parts[0] == "selftest" and len(parts) == 2 and parts[1]:
            out.append((n, words[0], "selftest", parts[1], None))
        elif parts[0] == "selftest" and len(parts) == 3 and parts[1] and parts[2] == "":
            out.append((n, words[0], "selftest", parts[1] + ":", None))   # a token that ends in a colon
        elif parts[0] == "e2e" and len(parts) in (2, 3) and parts[1]:
            out.append((n, words[0], "e2e", parts[1], parts[2] if len(parts) == 3 else None))
        else:
            errors.append("line %d of the list is neither selftest:<token> nor e2e:<scenario>[:<mode>]: %s" % (n, line))
    return out, errors


def units(check):
    """The checks a line of the list stands for: a selftest token as it is; an e2e line as (scenario, mode) pairs, a
    line with no mode standing for each of plain, mod and driver. So a check taken off in one form is the same check
    when it comes back in another."""
    parts = check.split(":")
    if parts[0] == "e2e" and len(parts) in (2, 3) and parts[1]:
        return {("e2e", parts[1], m) for m in ([parts[2]] if len(parts) == 3 else MODES)}
    return {("line", check)}


def came_back(root, current):
    """The checks of the list that an earlier commit took off it and that are on it again (in any form)."""
    code, out = git(root, "log", "-p", "--reverse", "--no-color", "--format=%x00COMMIT %H", "--", LIST)
    if code != 0:
        return []
    gone = set()
    for chunk in out.split("\x00COMMIT ")[1:]:
        removed, added = set(), set()
        for line in chunk.split("\n"):
            if line.startswith("---") or line.startswith("+++"):
                continue
            body = line[1:].split("#", 1)[0].split()
            if not body:
                continue
            if line.startswith("-"):
                removed |= units(body[0])
            elif line.startswith("+"):
                added |= units(body[0])
        gone |= removed - added
    return sorted(c for c in current if units(c) & gone)


# ---- the finals (D75b) ---------------------------------------------------------------------------------------------------

def flat(d, pre=""):
    out = {}
    for k, v in d.items():
        p = "%s.%s" % (pre, k) if pre else str(k)
        if isinstance(v, dict):
            out.update(flat(v, p))
        else:
            out[p] = v
    return out


def finals_of(rel, doc):
    """{(key, mode): value} of every `final` of the caps file or the floor file, keyed as the table names them."""
    out = {}
    if not isinstance(doc, dict):
        return out
    if rel == CAPS:
        for k, v in (doc.get("caps") or {}).items():
            if isinstance(v, dict) and "final" in v:
                out[(k, None)] = v["final"]
        return out
    for sc, modes in (doc.get("scenarios") or {}).items():
        for mode, entry in (modes or {}).items():
            if isinstance(entry, dict) and isinstance(entry.get("final"), dict):
                for p, v in flat(entry["final"]).items():
                    out[("%s.%s" % (sc, p), mode)] = v
    rep = doc.get("replay")
    if isinstance(rep, dict) and isinstance(rep.get("final"), dict):
        for p, v in flat(rep["final"]).items():
            out[("replay.%s" % p, None)] = v
    return out


def same(a, b):
    num = (int, float)
    if isinstance(a, bool) or isinstance(b, bool):
        return isinstance(a, bool) and isinstance(b, bool) and a == b
    if isinstance(a, num) and isinstance(b, num):
        return a == b
    return type(a) is type(b) and a == b


def above(now, first):
    if isinstance(now, bool) or isinstance(first, bool) or not isinstance(now, (int, float)) \
            or not isinstance(first, (int, float)):
        return not same(now, first)
    return now > first


def first_values(root, rel):
    """{(key, mode): value} of each `final` in the commit of the file that first held it."""
    code, out = git(root, "log", "--reverse", "--format=%H", "--", rel)
    if code != 0:
        return {}
    first = {}
    for c in out.split():
        code, text = git(root, "show", "%s:%s" % (c, rel))
        if code != 0:
            continue
        try:
            doc = json.loads(text)
        except ValueError:
            continue
        for k, v in finals_of(rel, doc).items():
            first.setdefault(k, v)
    return first


def load_json(root, rel):
    text = read(root, rel)
    if text is None:
        return None
    try:
        return json.loads(text)
    except ValueError:
        return None


# ---- the rules that close the build (WP32) -----------------------------------------------------------------------------

def package_problems(root):
    """The packages WP00 to WP31 whose line of the table "Packages" of PROGRESS.md is not done or blocked."""
    text = read(root, PROGRESS)
    if text is None:
        return ["final: no %s, so no package can be shown done" % PROGRESS]
    states, inside = {}, False
    for line in text.split("\n"):
        if line.startswith("## "):
            inside = line.strip() == "## Packages"
            continue
        if inside and line.startswith("|"):
            cells = cells_of(line)
            if len(cells) > 1 and re.match(r"^WP\d\d$", cells[0]):
                states.setdefault(cells[0], cells[1])
    out = []
    for wp in PACKAGES:
        if wp not in states:
            out.append("final: %s has no line in the table Packages of %s" % (wp, PROGRESS))
        elif states[wp] not in ("done", "blocked"):
            out.append("final: %s is %s in %s (every package before WP32 is done or blocked)"
                       % (wp, states[wp] or "empty", PROGRESS))
    return out


def papers_problems(root):
    """The working papers are untracked, and no tracked file outside the kit's folder names them."""
    out = []
    code, listed = git(root, "ls-files", "--", PAPERS)
    if code != 0:
        return ["final: git cannot list the files of %s" % root]
    if listed.strip():
        out.append("final: the working papers are tracked: %d files under %s (git rm -r them)"
                   % (len(listed.strip().split("\n")), PAPERS))
    code, named = git(root, "grep", "-l", "-F", "-e", PAPERS, "--", ".", ":(exclude)%s" % KIT)
    for f in (named.strip().split("\n") if code == 0 and named.strip() else []):
        out.append("final: %s names the working papers (%s), which leave the tree" % (f, PAPERS))
    return out


def plan_items(text):
    """The item ids of releases 0 to 7 of the plan, in their order."""
    out, inside = [], False
    for line in text.split("\n"):
        if line.startswith("#"):
            inside = bool(re.match(r"^### Release [0-7]\.", line))
            continue
        m = ITEM.match(line) if inside else None
        if m and m.group(1) not in out:
            out.append(m.group(1))
    return out


def summary_problems(root):
    """What is wrong with the form of the summary of the build; [] when it holds."""
    text = read(root, SUMMARY)
    if text is None:
        return ["summary: no %s" % SUMMARY]
    out = []
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines = lines[:-1]
    if len(lines) > SUMMARY_LINES:
        out.append("summary: %s has %d lines, at most %d" % (SUMMARY, len(lines), SUMMARY_LINES))
    seen = [l[3:].strip() for l in lines if l.startswith("## ") and l[3:].strip() in HEADINGS]
    for h in HEADINGS:
        if h not in seen:
            out.append("summary: the heading '## %s' is missing" % h)
        elif seen.count(h) > 1:
            out.append("summary: the heading '## %s' is there %d times" % (h, seen.count(h)))
    if len(seen) == len(HEADINGS) and set(seen) == set(HEADINGS) and seen != HEADINGS:
        out.append("summary: the headings are out of order: %s" % " | ".join(seen))
    plan = read(root, PLAN)
    if plan is None:
        return out + ["summary: no %s, so the items of part 3 are not known" % PLAN]
    ids = plan_items(plan)
    if not ids:
        out.append("summary: %s has no item under its headings Release 0 to Release 7" % PLAN)
    rows, inside = {}, False
    for line in lines:
        if line.startswith("## "):
            inside = line[3:].strip() == HEADINGS[2]
            continue
        if inside and line.startswith("|"):
            cells = [c.strip("`* ") for c in cells_of(line)]
            if cells and cells[0] in ids:
                rows.setdefault(cells[0], []).append(cells)
    for i in ids:
        if i not in rows:
            out.append("summary: the item %s of the plan has no line in part 3 (## %s)" % (i, HEADINGS[2]))
            continue
        for cells in rows[i]:
            if not any(c in STATES for c in cells[1:]):
                out.append("summary: the line of %s in part 3 holds none of the three states (%s)"
                           % (i, ", ".join(STATES)))
    return out


def summary_main(root):
    problems = summary_problems(root)
    for p in problems:
        print("FAIL: %s" % p)
    if problems:
        print("check_done --summary: FAIL (%d)" % len(problems))
        return 1
    print("check_done --summary: PASS: %s has the eight headings in their order and a state for each item of the plan"
          % SUMMARY)
    return 0


# ---- the check -------------------------------------------------------------------------------------------------------------

def main(argv):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    final = summary = False
    args = list(argv)
    while args:
        a = args.pop(0)
        if a == "--final":
            final = True
        elif a == "--summary":
            summary = True
        elif a == "--root" and args:
            root = os.path.abspath(args.pop(0))
        else:
            print("usage: python3 scripts/check_done.py [--final | --summary] [--root DIR]")
            return 2
    if final and summary:
        print("usage: python3 scripts/check_done.py [--final | --summary] [--root DIR]")
        return 2
    if summary:
        return summary_main(root)
    done = read(root, DONE)
    if done is None:
        print("check_done: FAIL: no %s" % DONE)
        return 1
    rows = table(done)
    if not rows:
        print("check_done: FAIL: %s has no table under the heading \"The table\"" % DONE)
        return 1
    cases = case_files(root)
    e2e = e2e_files(root)
    lst, problems = read_list(read(root, LIST))
    list_tokens = {name for _, _, suite, name, _ in lst if suite == "selftest"}
    list_scen = {name for _, _, suite, name, _ in lst if suite == "e2e"}
    three = {}
    for f in THREE:
        if f in e2e:
            for name, entry in registered(e2e[f]).items():
                three[name] = (f, entry)
    floor_doc, caps_doc = load_json(root, FLOOR), load_json(root, CAPS)
    finals = {}
    finals.update(finals_of(CAPS, caps_doc))
    finals.update(finals_of(FLOOR, floor_doc))

    def final_keys(item):
        """[(key, mode)] of the finals an item with a value names; [] when the file holds none of them."""
        key = " ".join(item["words"])
        if item["kind"] == "caps":
            return [(key, None)] if (key, None) in finals else []
        if key.startswith("replay."):
            return [(key, None)] if (key, None) in finals else []
        found = [(k, m) for (k, m) in finals if k == key and (item["mode"] is None or m == item["mode"])]
        return found

    seen_ids, table_tokens, counts = {}, set(), {"ok": 0, "expected to fail": 0, "open": 0, "FAIL": 0}
    for n, cells in rows:
        if len(cells) != 5:
            problems.append("line %d of %s: a row has five cells, this one %d" % (n, DONE, len(cells)))
            continue
        rid, _, check, nomodel, _ = cells
        if not re.match(r"^D\d+$", rid):
            problems.append("line %d of %s: '%s' is no row id" % (n, DONE, rid))
            continue
        if rid in seen_ids:
            problems.append("%s: the row id is used twice (lines %d and %d)" % (rid, seen_ids[rid], n))
        seen_ids[rid] = n
        items = items_of(check)
        for it in items:
            if it["kind"] == "case" and len(it["words"]) == 2:
                table_tokens.add(it["words"][1])
        missing, listed, opened = [], False, []
        for it in items:
            if it["kind"] == "case":
                if len(it["words"]) != 2 or not it["words"][0].isdigit():
                    missing.append("`%s` is not case NN <token>" % it["text"])
                    continue
                nn, tok = it["words"]
                if not has_token(cases.get(nn), tok):
                    missing.append("case %s %s (no assertion of %s/temper-cases-%s.sh starts with it)" % (nn, tok, SELFTEST, nn))
                elif tok in list_tokens:
                    listed = True
            elif it["kind"] == "scenario":
                name = it["words"][0] if it["words"] else ""
                if not has_scenario(e2e, name):
                    missing.append("scenario %s (no file of %s registers it)" % (name, E2E))
                    continue
                own = three[name][1]["modes"] if name in three else None
                if own is not None:   # a scenario of the three files runs only in the modes it registers
                    if it["modes_named"]:
                        for mode in it["modes"]:
                            if mode not in own:
                                missing.append("scenario %s %s (the scenario registers the modes %s only)"
                                               % (name, mode, ", ".join(own)))
                    it["modes"] = [m for m in it["modes"] if m in own]
                if name in list_scen:
                    listed = True
            elif it["kind"] in ("floor", "caps") and it["value"] is not None and not final_keys(it):
                opened.append("%s %s has no final yet" % (it["kind"], " ".join(it["words"])))
            elif it["kind"] == "caps" and it["value"] is not None:
                # a cap whose now is above its final is never ok: the row is open, and in the final mode it fails
                c = (caps_doc.get("caps") or {}).get(" ".join(it["words"])) if isinstance(caps_doc, dict) else None
                now, cap = (c.get("now"), c.get("final")) if isinstance(c, dict) else (None, None)
                if type(now) is int and type(cap) is int and now > cap:
                    (missing if final else opened).append("caps %s: now %d is above its final %d" % (" ".join(it["words"]), now, cap))
        if nomodel == "yes" and not items:
            missing.append("the row needs no model and names no check")
        if rid in RULE_ROWS and not any(it["kind"] == "case" or (it["kind"] == "scenario" and "plain" in it["modes"])
                                        for it in items):
            missing.append("rule 11: the row names neither a case nor a scenario that runs in plain mode")
        if missing:
            status = "FAIL"
            problems.extend("%s: %s" % (rid, m) for m in missing)
            print("%s FAIL: %s" % (rid, "; ".join(missing)))
        elif nomodel != "yes":
            status = "open"
            print("%s open (%s)" % (rid, "needs a person" if nomodel == "person" else "needs a model"))
        elif listed:
            status = "expected to fail"
            print("%s expected to fail" % rid)
        elif opened:
            status = "open"
            print("%s open (%s)" % (rid, "; ".join(opened)))
        else:
            status = "ok"
            print("%s ok" % rid)
        counts[status] += 1

    # the list: every line matches a check, a token of the table or a scenario of the three files, and none came back
    for n, check, suite, name, mode in lst:
        if suite == "selftest":
            if not any(has_token(t, name) for t in cases.values()):
                problems.append("line %d of the list: %s matches no check (no assertion starts with %s)" % (n, check, name))
            if name not in table_tokens:
                problems.append("line %d of the list: %s is not a token of the table of %s" % (n, check, DONE))
        else:
            if not has_scenario(e2e, name):
                problems.append("line %d of the list: %s matches no check (no scenario %s)" % (n, check, name))
            if name not in three:
                problems.append("line %d of the list: %s is not a scenario of %s" % (
                    n, check, ", ".join("%s/%s" % (E2E, f) for f in THREE)))
            if mode is not None and mode not in MODES:
                problems.append("line %d of the list: %s names no mode" % (n, check))
            elif mode is not None and name in three and three[name][1]["modes"] is not None \
                    and mode not in three[name][1]["modes"]:
                problems.append("line %d of the list: %s names a mode the scenario does not run (it registers %s)"
                                % (n, check, ", ".join(three[name][1]["modes"])))
    for check in came_back(root, [c for _, c, _, _, _ in lst]):
        problems.append("%s was taken off the list by an earlier commit and is on it again: a line never comes back"
                        % check)

    # no test of the mod is skipped
    code, out = git(root, "grep", "-n", "--untracked", "-F", "-e", ".skip(", "-e", ".only(", "-e", ".todo(", "--",
                    "*.test.ts", "*.test.tsx")
    if code == 0:
        for line in out.strip().split("\n"):
            problems.append("a test is skipped: %s" % line)

    # D105: every scenario of the three files calls the shared assert
    for name, (f, entry) in sorted(three.items()):
        if entry["error"] is not None:
            problems.append("D105: %s/%s registers %s: %s" % (E2E, f, name, entry["error"]))
        elif not calls_world_check(e2e[f], entry["fn"], body=entry["inline"]):
            problems.append("D105: the scenario %s of %s/%s (%s) does not call the shared assert worldCheck"
                            % (name, E2E, f, entry["fn"] or "a function written in place"))

    if final:
        for _, check, _, _, _ in lst:
            problems.append("final: %s is still on the expected to fail list" % check)
        for _, cells in rows:
            if len(cells) != 5:
                continue
            for it in items_of(cells[2]):
                if it["kind"] not in ("floor", "caps") or it["value"] is None:
                    continue
                keys = final_keys(it)
                label = "%s %s" % (it["kind"], " ".join(it["words"]))
                if not keys:
                    problems.append("D75b: %s = %s has no final in its file" % (label, json.dumps(it["value"])))
                for k in keys:
                    if not same(finals[k], it["value"]):
                        problems.append("D75b: %s%s: the final is %s, the table says %s" % (
                            label, " [%s]" % k[1] if k[1] else "", json.dumps(finals[k]), json.dumps(it["value"])))
        problems.extend(package_problems(root))
        problems.extend(papers_problems(root))
        for rel in (CAPS, FLOOR):
            doc = caps_doc if rel == CAPS else floor_doc
            first = first_values(root, rel)
            for k, v in finals_of(rel, doc).items():
                if k in first and above(v, first[k]):
                    problems.append("D75b: %s %s%s: the final %s is above %s, its value in the commit that first "
                                    "added it" % (rel, k[0], " [%s]" % k[1] if k[1] else "", json.dumps(v),
                                                  json.dumps(first[k])))

    print("check_done: %d rows: %d ok, %d expected to fail, %d open, %d failing" % (
        len(rows), counts["ok"], counts["expected to fail"], counts["open"], counts["FAIL"]))
    print("check_done: the list holds %d expected failures (%d selftest, %d e2e)" % (
        len(lst), len([x for x in lst if x[2] == "selftest"]), len([x for x in lst if x[2] == "e2e"])))
    if problems:
        for p in problems:
            print("FAIL: %s" % p)
        print("check_done%s: FAIL (%d)" % (" --final" if final else "", len(problems)))
        return 1
    print("check_done%s: PASS" % (" --final" if final else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
