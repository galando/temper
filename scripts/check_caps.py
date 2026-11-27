#!/usr/bin/env python3
"""check_caps.py: the growth caps of the product (scripts/caps.json), 9.8.5 (WP05).

Each key of the caps file has `now`, the measure of the tree as it is, and `final`, the number of part F of
docs/plans/one-go/done.md (row D108 for `readme_lines`). Three rules:

  1. `now` equals the measure: a change that adds a question site, a byte of prompt or a config line sets `now` in the
     same commit, and one that removes some lowers it, so the file never drifts above or below the truth;
  2. a `final` is never above its value in the commit of the file that first added the key (read from the history of
     the file in git; a key no commit holds yet is exempt): a rule that read only the file as it is would be passed by
     the very commit that raises a value. A removed bound is a raised one: a final of that first commit that the file
     no longer holds (its key deleted), or holds as no number (null), fails too. The one exception is a raise the
     owner made: an entry of `owner_raises` ({key, from, to, reason}) whose `from` is the first committed final and
     whose `to` is the final the file holds lets exactly that raise through, and no other;
  3. no `now` above its `final` is also above its value in the earlier version of the file (scripts/growth_base.py:
     the file at the merge base with the main branch, or with --base REV; when that cannot be read, a line says so
     and the previous committed version of the file stands in, and with none the rule passes): an overrun recorded
     for the owner stays green and cannot grow, and a new cap does not start above its final;
  4. with --final, no `now` is above its `final` at all (rule 3 is then left out).

  python3 scripts/check_caps.py [--final] [--base REV] [--caps FILE]

FILE defaults to scripts/caps.json; the measure is always of the plugin folder this script sits in. Each cap's line
also gives the same measure taken on the base 10e965a (git show of that commit; "not found" when the history lacks it),
so a report says how much of an overrun is growth since the base and how much was there already. The code of each
measure is the function named in the `measure` field beside its key. Files are listed with git ls-files. Python 3 and
git only, a second or two (the base measures read the base commit). Exit 0 when every rule holds, else 1 (2 for a wrong call).
"""
import ast
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CAPS = os.path.join(HERE, "caps.json")
TEMPLATE = "templates/temper.config.default"


BASE = "10e965a"   # the base of the build (docs/plans/one-go/contracts.md): each measure is also taken there
SRC = None         # None: the measures read the tree as it is; a commit: they read that commit (at_base)


def git(cwd, *args):
    p = subprocess.run(["git", "-C", cwd] + list(args), capture_output=True, text=True)
    return p.stdout if p.returncode == 0 else None


def files(*specs):
    """The files of the tree under the pathspecs, tracked or new, that exist (with SRC: the files of that commit)."""
    if SRC:
        return sorted({f for f in (git(ROOT, "ls-tree", "-r", "--name-only", SRC, "--", *specs) or "").splitlines() if f})
    out = git(ROOT, "ls-files", "--cached", "--others", "--exclude-standard", "--", *specs) or ""
    return sorted({f for f in out.splitlines() if os.path.isfile(os.path.join(ROOT, f))})


def in_folder(folder, suffix):
    """The files directly in a folder of the tree (not below it) with a suffix."""
    depth = folder.count("/") + 1
    out = []
    for rel in files(folder):
        if rel.count("/") == depth and rel.endswith(suffix):
            out.append(rel)
    return out


def text(rel):
    if SRC:   # a file the commit does not hold reads as empty: its measure there counts nothing of it
        return git(ROOT, "show", "%s:%s" % (SRC, rel)) or ""
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def size(rels):
    if SRC:
        return sum(int((git(ROOT, "cat-file", "-s", "%s:%s" % (SRC, r)) or "0").strip() or 0) for r in rels)
    return sum(os.path.getsize(os.path.join(ROOT, r)) for r in rels)


def at_base(fn, doc):
    """The measure fn taken on the base commit BASE, as git holds it (git show), or None when the history has no BASE:
    the report gives it beside the measure of the tree, so an overrun reads as growth since the base and as what was
    there already (lane E)."""
    global SRC
    if git(ROOT, "cat-file", "-e", BASE + "^{commit}") is None:
        return None
    SRC = BASE
    try:
        return fn(doc)
    except (OSError, ValueError, SyntaxError, KeyError, TypeError):
        return None
    finally:
        SRC = None


def lines(rel):
    return text(rel).count("\n")


def flow_text(doc):
    return "".join(text(f) for f in doc.get("flow_files") or [])


# ---- the measures: one function a key ----

def measure_question_sites(doc):
    """calls of self.question( and self.with_more( in the flow files"""
    t = flow_text(doc)
    return len(re.findall(r"self\.question\(", t)) + len(re.findall(r"self\.with_more\(", t))


def measure_option_sites(doc):
    """calls of self.opt( in the flow files"""
    return len(re.findall(r"self\.opt\(", flow_text(doc)))


def option_labels(doc):
    """The labels of the self.opt( calls of the flow files, read from the syntax tree so a label is seen however it
    reaches the call (phase 6): a string; a format string, as the text it gives when its arguments are fixed, else as
    written; an f-string, or a string's .format(), as written (lane E); the left part of a sum (a suffix keeps the label); both arms of a choice; a name, through what the
    function assigns to it, a loop over a list of tuples or a zip of lists (the function's own or a module's), or a
    parameter, through the self.NAME( calls that pass it."""
    consts, calls = {}, []
    for t in [ast.parse(text(f)) for f in doc.get("flow_files") or []]:
        consts.update({n.targets[0].id: n.value for n in t.body if isinstance(n, ast.Assign) and len(n.targets) == 1
                       and isinstance(n.targets[0], ast.Name)})
        for fn in ast.walk(t):
            if isinstance(fn, ast.FunctionDef):
                calls += [(c, fn) for c in ast.walk(fn) if isinstance(c, ast.Call) and isinstance(c.func, ast.Attribute)
                          and getattr(c.func.value, "id", "") == "self"]

    def bound(name, fn):
        got = [n.value for n in ast.walk(fn) if isinstance(n, ast.Assign) and any(getattr(t, "id", "") == name for t in n.targets)]
        return got or ([consts[name]] if name in consts else [])

    def items(node, fn, depth):
        if isinstance(node, (ast.List, ast.Tuple)):
            return node.elts
        return [e for v in bound(node.id, fn) for e in items(v, fn, depth + 1)] if isinstance(node, ast.Name) and depth < 9 else []

    def vals(node, fn, depth=0):
        if depth > 9:
            return set()
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            return {node.value}
        if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Mod, ast.Add)):
            left = vals(node.left, fn, depth + 1)
            args = node.right.elts if isinstance(node.right, ast.Tuple) else [node.right]
            if isinstance(node.op, ast.Add) or not all(isinstance(a, ast.Constant) for a in args):
                return left
            out = set()
            for s in left:
                try:
                    out.add(s % tuple(a.value for a in args))
                except (TypeError, ValueError):
                    out.add(s)
            return out
        if isinstance(node, ast.IfExp):
            return vals(node.body, fn, depth + 1) | vals(node.orelse, fn, depth + 1)
        if isinstance(node, ast.JoinedStr):   # an f-string, as written (the measure before phase 6 read it so)
            return {"".join(v.value if isinstance(v, ast.Constant) else "{%s}" % ast.unparse(v.value) for v in node.values)}
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "format":
            return vals(node.func.value, fn, depth + 1)   # "... {}".format(x): the string it formats, as written
        if not isinstance(node, ast.Name):
            return set()
        out = set().union(*[vals(v, fn, depth + 1) for v in bound(node.id, fn)])
        for g in ast.walk(fn):
            if not isinstance(g, (ast.For, ast.comprehension)):
                continue
            names = [getattr(e, "id", None) for e in getattr(g.target, "elts", [g.target])]
            if node.id not in names:
                continue
            i = names.index(node.id)
            if isinstance(g.iter, ast.Call) and getattr(g.iter.func, "id", "") == "zip":
                rows = items(g.iter.args[i], fn, depth + 1) if i < len(g.iter.args) else []
            elif isinstance(g.target, ast.Tuple):
                rows = [e.elts[i] for e in items(g.iter, fn, depth + 1) if isinstance(e, ast.Tuple) and i < len(e.elts)]
            else:
                rows = items(g.iter, fn, depth + 1)
            out = out.union(*[vals(e, fn, depth + 1) for e in rows])
        params = [a.arg for a in fn.args.args]
        if not out and node.id in params:
            i = params.index(node.id) - 1
            for c, caller in calls:
                if c.func.attr == fn.name:
                    passed = ([c.args[i]] if 0 <= i < len(c.args) else []) + [k.value for k in c.keywords if k.arg == node.id]
                    out = out.union(*[vals(a, caller, depth + 1) for a in passed])
        return out

    return set().union(*[vals(c.args[0], fn) for c, fn in calls if c.func.attr == "opt" and c.args])


def measure_option_labels(doc):
    """distinct labels of those calls, seen through a tuple, a variable or a format string (option_labels)"""
    return len(option_labels(doc))


def measure_question_ids(doc):
    """entries of QUESTIONS in scripts/flow_base.py"""
    for node in ast.parse(text("scripts/flow_base.py")).body:
        if isinstance(node, ast.Assign) and any(getattr(t, "id", "") == "QUESTIONS" for t in node.targets):
            return len(node.value.keys) if isinstance(node.value, ast.Dict) else 0
    return 0


def measure_handback_kinds(doc):
    """entries of NEEDS in scripts/flow_base.py but the three the run driver does itself (more, accept, cancel)"""
    for node in ast.parse(text("scripts/flow_base.py")).body:
        if isinstance(node, ast.Assign) and any(getattr(t, "id", "") == "NEEDS" for t in node.targets):
            elts = node.value.elts if isinstance(node.value, (ast.Set, ast.List, ast.Tuple)) else []
            return len([e for e in elts if getattr(e, "value", None) not in ("more", "accept", "cancel")])
    return 0


def measure_gate_rows(doc):
    """distinct _req names of the CLI, distinct row names of the Python scripts (a row( call in either quotes, a
    dict of a name and a pass a script prints, or, in a script that defines add(name, ok, detail), an add( call in
    either quotes and a name of a tuple a for loop hands to add), name lines of gate_rows.py"""
    req = set(re.findall(r'_req "([^"$]+)"', text("scripts/temper")))
    rows = set()
    for f in in_folder("scripts", ".py"):
        src = text(f)
        rows |= {name for _, name in re.findall(r'''\brow\((["'])(.+?)\1''', src)}
        if re.search(r"(?m)^def add\(name, ok, detail\)", src):   # the Intent gate's rows (p7 lane C)
            rows |= {name for _, name in re.findall(r'''\badd\((["'])(.+?)\1''', src)}
            for d in ast.walk(ast.parse(src)):
                if isinstance(d, ast.For) and isinstance(d.iter, ast.Tuple) and "add(" in ast.unparse(d):
                    rows |= {e.value for e in d.iter.elts if isinstance(e, ast.Constant) and isinstance(e.value, str)}
        for d in ast.walk(ast.parse(src)) if re.search(r"[\"']pass[\"']", src) else []:
            keys = [getattr(k, "value", None) for k in d.keys] if isinstance(d, ast.Dict) else []
            if "name" in keys and "pass" in keys and isinstance(d.values[keys.index("name")], ast.Constant):
                rows.add(d.values[keys.index("name")].value)
    named = len(re.findall(r'(?m)^\s+name = "', text("scripts/gate_rows.py")))
    return len(req) + len(rows) + named


def measure_agent_briefs(doc):
    """files of agents/*.md"""
    return len(in_folder("agents", ".md"))


def plugin():
    return json.loads(text(".claude-plugin/plugin.json"))


def measure_listed_commands(doc):
    """commands of .claude-plugin/plugin.json"""
    return len(plugin().get("commands") or [])


def measure_listed_skills(doc):
    """skills of .claude-plugin/plugin.json"""
    return len(plugin().get("skills") or [])


def measure_config_live_keys(doc):
    """key lines of the config template that are not comments"""
    return len(re.findall(r"(?m)^\s*[A-Za-z_][A-Za-z0-9_.-]*:", text(TEMPLATE)))


def measure_config_comment_keys(doc):
    """commented key lines of the config template"""
    return len(re.findall(r"(?m)^\s*#\s*[A-Za-z_][A-Za-z0-9_-]*:( |$)", text(TEMPLATE)))


def measure_config_lines(doc):
    """lines of the config template"""
    return lines(TEMPLATE)


def measure_prompt_bytes(doc):
    """bytes of commands/*.md, agents/*.md and reference/**/*.md"""
    return size(in_folder("commands", ".md") + in_folder("agents", ".md") + [f for f in files("reference") if f.endswith(".md")])


def measure_pack_skill_bytes(doc):
    """bytes of the markdown under packs and skills"""
    return size([f for f in files("packs", "skills") if f.endswith(".md")])


def measure_cli_bytes(doc):
    """bytes of scripts/temper"""
    return size(["scripts/temper"])


def measure_readme_lines(doc):
    """lines of the product's README.md, in the root"""
    return lines("README.md")


MEASURES = {k[len("measure_"):]: v for k, v in globals().items() if k.startswith("measure_")}


def finals(doc):
    return {k: v["final"] for k, v in (doc.get("caps") or {}).items() if isinstance(v, dict) and "final" in v}


def number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def owner_raised(doc):
    """{key: (from, to)} of the raises the owner made (rule 2): the entries of `owner_raises` that name a key, two whole
    numbers and a reason; an entry that lacks one of them allows nothing."""
    out = {}
    for e in doc.get("owner_raises") or []:
        if (isinstance(e, dict) and isinstance(e.get("key"), str) and type(e.get("from")) is int
                and type(e.get("to")) is int and str(e.get("reason") or "").strip()):
            out[e["key"]] = (e["from"], e["to"])
    return out


def raised(cur, first, allowed=None):
    """The lines for each final of first that cur raised, dropped or holds as no number: a removed bound is a raised
    one, so deleting a cap or setting its final to null fails as raising it does (a key first does not hold is exempt,
    as is one whose first committed final was no number). A raise the owner made (owner_raised) passes only when its
    entry names that first value and the very final the file holds."""
    out, allowed = [], allowed or {}
    for k, f in sorted(first.items()):
        if not number(f):
            continue
        if k not in cur:
            out.append("%s: its final is removed, its first committed value is %s: a final is never removed" % (k, f))
        elif not number(cur[k]):
            out.append("%s: final %s is no number, its first committed value is %s: a final is never removed"
                       % (k, json.dumps(cur[k]), f))
        elif cur[k] > f and allowed.get(k) != (f, cur[k]):
            out.append("%s: final %s is above its first committed value %s: a final is never raised" % (k, cur[k], f))
    return out


def first_values(path):
    """{key: final} at the commit of the file that first added each key, oldest commit first."""
    d = os.path.dirname(os.path.abspath(path))
    top_dir = (git(d, "rev-parse", "--show-toplevel") or "").strip()
    if not top_dir:
        return {}
    rel = os.path.relpath(os.path.realpath(path), os.path.realpath(top_dir))
    out = {}
    for c in (git(top_dir, "log", "--reverse", "--format=%H", "--", rel) or "").split():
        try:
            doc = json.loads(git(top_dir, "show", "%s:%s" % (c, rel)) or "")
        except ValueError:
            continue
        for k, v in finals(doc).items():
            out.setdefault(k, v)
    return out


def main(argv):
    path, final, base_rev = CAPS, False, None
    i = 0
    while i < len(argv):
        if argv[i] == "--final":
            final = True
        elif argv[i] in ("--caps", "--base") and i + 1 < len(argv):
            if argv[i] == "--caps":
                path = argv[i + 1]
            else:
                base_rev = argv[i + 1]
            i += 1
        else:
            print("check_caps.py: unknown argument %s (python3 scripts/check_caps.py [--final] [--base REV] [--caps FILE])" % argv[i], file=sys.stderr)
            return 2
        i += 1
    with open(path, encoding="utf-8") as f:
        doc = json.load(f)
    problems, report, over = [], [], []
    caps = doc.get("caps") or {}
    for k, c in sorted(caps.items()):
        fn = MEASURES.get(k)
        if fn is None:
            problems.append("%s: no measure in scripts/check_caps.py" % k)
            continue
        if not isinstance(c, dict) or type(c.get("now")) is not int or type(c.get("final")) is not int:
            problems.append("%s: needs a whole number now and final" % k)
            continue
        got = fn(doc)
        base = at_base(fn, doc)
        report.append("  %s: now %d, base %s %s, final %d%s" % (
            k, got, BASE, "not found" if base is None else base, c["final"],
            "" if base is None else " (%+d since the base; %s)" % (got - base, "the base is over its final too"
                                                                      if base > c["final"] else "the base is within its final")))
        if got != c["now"]:
            problems.append("%s: the measure is %d, the file says now %d (set now to the measure in this commit)" % (k, got, c["now"]))
        if final and c["now"] > c["final"]:
            problems.append("%s: now %d is above its final %d" % (k, c["now"], c["final"]))
        elif c["now"] > c["final"]:
            over.append(k)
    for k in sorted(set(MEASURES) - set(caps)):
        problems.append("%s: measured here, and the file holds no cap for it" % k)
    problems += raised(finals(doc), first_values(path), owner_raised(doc))
    for line in report:
        print(line)
    if over:   # rule 3: a now above its final may not be above its earlier value
        sys.path.insert(0, HERE)   # python3 -I leaves the script's folder off the path
        import growth_base
        old, where, note = growth_base.earlier(path, base_rev)
        if note:
            print("caps: %s" % note)
        for k in over if old is not None else []:
            was = ((old.get("caps") or {}).get(k) or {}).get("now") if isinstance((old.get("caps") or {}).get(k), dict) else None
            if type(was) is not int:
                problems.append("%s: now %d is above its final %d, and the file %s holds no now for it (a new cap "
                                "does not start above its final)" % (k, caps[k]["now"], caps[k]["final"], where))
            elif caps[k]["now"] > was:
                problems.append("%s: now %d is above its final %d and above its value %d %s (a size above its final "
                                "may not grow)" % (k, caps[k]["now"], caps[k]["final"], was, where))
    for p in problems:
        print("FAIL caps: %s" % p)
    if not problems:
        print("caps: %d caps, each now equal to its measure%s" % (len(caps), ", none above its final" if final else ""))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
