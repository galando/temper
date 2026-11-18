#!/usr/bin/env python3
"""check_caps.py: the growth caps of the product (scripts/caps.json), 9.8.5 (WP05).

Each key of the caps file has `now`, the measure of the tree as it is, and `final`, the number of part F of
docs/plans/one-go/done.md (row D108 for `readme_lines`). Three rules:

  1. `now` equals the measure: a change that adds a question site, a byte of prompt or a config line sets `now` in the
     same commit, and one that removes some lowers it, so the file never drifts above or below the truth;
  2. a `final` is never above its value in the commit of the file that first added the key (read from the history of
     the file in git; a key no commit holds yet is exempt): a rule that read only the file as it is would be passed by
     the very commit that raises a value. A removed bound is a raised one: a final of that first commit that the file
     no longer holds (its key deleted), or holds as no number (null), fails too;
  3. with --final, no `now` is above its `final`.

  python3 scripts/check_caps.py [--final] [--caps FILE]

FILE defaults to scripts/caps.json; the measure is always of the plugin folder this script sits in. The code of each
measure is the function named in the `measure` field beside its key. Files are listed with git ls-files. Python 3 and
git only, well under a second. Exit 0 when every rule holds, else 1 (2 for a wrong call).
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


def git(cwd, *args):
    p = subprocess.run(["git", "-C", cwd] + list(args), capture_output=True, text=True)
    return p.stdout if p.returncode == 0 else None


def files(*specs):
    """The files of the tree under the pathspecs, tracked or new, that exist."""
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
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def size(rels):
    return sum(os.path.getsize(os.path.join(ROOT, r)) for r in rels)


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


def measure_option_labels(doc):
    """distinct first arguments (a string) of those calls"""
    return len(set(re.findall(r'self\.opt\(\s*f?"([^"]+)"', flow_text(doc))))


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
    """distinct _req names of the CLI, distinct row( names of the Python scripts, name lines of gate_rows.py"""
    req = set(re.findall(r'_req "([^"$]+)"', text("scripts/temper")))
    rows = set()
    for f in in_folder("scripts", ".py"):
        rows |= set(re.findall(r'\brow\("([^"]+)"', text(f)))
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


def raised(cur, first):
    """The lines for each final of first that cur raised, dropped or holds as no number: a removed bound is a raised
    one, so deleting a cap or setting its final to null fails as raising it does (a key first does not hold is exempt,
    as is one whose first committed final was no number)."""
    out = []
    for k, f in sorted(first.items()):
        if not number(f):
            continue
        if k not in cur:
            out.append("%s: its final is removed, its first committed value is %s: a final is never removed" % (k, f))
        elif not number(cur[k]):
            out.append("%s: final %s is no number, its first committed value is %s: a final is never removed"
                       % (k, json.dumps(cur[k]), f))
        elif cur[k] > f:
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
    path, final = CAPS, False
    i = 0
    while i < len(argv):
        if argv[i] == "--final":
            final = True
        elif argv[i] == "--caps" and i + 1 < len(argv):
            path = argv[i + 1]
            i += 1
        else:
            print("check_caps.py: unknown argument %s (python3 scripts/check_caps.py [--final] [--caps FILE])" % argv[i], file=sys.stderr)
            return 2
        i += 1
    with open(path, encoding="utf-8") as f:
        doc = json.load(f)
    problems = []
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
        if got != c["now"]:
            problems.append("%s: the measure is %d, the file says now %d (set now to the measure in this commit)" % (k, got, c["now"]))
        if final and c["now"] > c["final"]:
            problems.append("%s: now %d is above its final %d" % (k, c["now"], c["final"]))
    for k in sorted(set(MEASURES) - set(caps)):
        problems.append("%s: measured here, and the file holds no cap for it" % k)
    problems += raised(finals(doc), first_values(path))
    for p in problems:
        print("FAIL caps: %s" % p)
    if not problems:
        print("caps: %d caps, each now equal to its measure%s" % (len(caps), ", none above its final" if final else ""))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
