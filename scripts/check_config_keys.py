#!/usr/bin/env python3
"""check_config_keys.py: every key of the config has a reader, and no agent is sent to the config (WP29, ADR 0023).

  python3 scripts/check_config_keys.py      exit 0 when it holds; else one FAIL line for each fault, and exit 1

It reads the tracked files of the plugin folder it sits in, with git, and fails when:
  1. a key of the table (scripts/defaults.py KEYS) has no reader: its literal is in no file of scripts but the table,
     this script and the tests, and no brief reads it through the CLI (a literal `config get <key>`);
  2. a key the scripts read (_cfg_get, cfg(, .on(, config_yaml.get(, config get) is in neither the table nor the old
     names the CLI still reads (a key of GONE with a replacement);
  3. a key line of the template, live or a comment, is not in the table;
  4. a page (agents, reference, commands, templates, README.md, docs but its history, plans, evidence and decisions)
     names a dotted key under one of the template's top names that the table lacks (docs/commands.md may name a key
     that is gone, in its table of what became of an old key);
  5. a brief or a reference page other than reference/pack.md holds temper.config.
A question id, a file name and a field of the view are no key. Python 3 and git only.
"""
import ast
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import defaults  # noqa: E402

NOT_READERS = ("scripts/defaults.py", "scripts/check_config_keys.py")
TESTS = ("scripts/selftest/", "scripts/e2e/")
PAGES = ("agents", "reference", "commands", "templates", "README.md", "docs")
PAGES_OUT = ("docs/history/", "docs/plans/", "docs/evidence/", "docs/decisions/")
EXTENSIONS = {"md", "html", "py", "ts", "sh", "json", "js", "txt", "yml", "yaml", "toml", "css"}
RECORD = "docs/commands.md"   # its table "What became of an old key" names each key that is gone
VIEW_FIELDS = {"run.step", "run.id", "run.armed", "run.walked", "run.stage"}   # fields of `temper next --json`
READS = [re.compile(p) for p in (r"_cfg_get\s+([a-z][\w.-]*)", r"\bcfg\(\s*[\"']([a-z][\w.-]*)[\"']",
                                 r"\.on\(\s*[\"']([a-z][\w.-]*)[\"']",
                                 r"config_yaml\.get\([^,()]+,\s*[\"']([a-z][\w.-]*)[\"']",
                                 r"config get\s+([a-z][\w.-]*)")]


def git(*args):
    r = subprocess.run(["git", "-C", ROOT] + list(args), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    return r.stdout if r.returncode in (0, 1) else ""


def tracked(*specs):
    return [f for f in git("ls-files", "--cached", "--others", "--exclude-standard", "--", *specs).splitlines() if f]


def read(rel):
    try:
        with open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def known(path):
    """True when a dot path is a key of the table: itself, a pattern (models.<agent>), a parent of one, or a key inside
    a block the table names (setup.services.postgres)."""
    for k in defaults.KEYS:
        if path == k or k.startswith(path + ".") or path.startswith(k + "."):
            return True
        if "<" in k and re.fullmatch(re.sub(r"<[^>]+>", "[a-z0-9<>-]+", re.escape(k)), path):
            return True
    return False


def still_read(path):
    return bool(defaults.GONE.get(path, ("",))[0])


def question_ids():
    try:
        tree = ast.parse(read("scripts/flow_base.py"))
    except SyntaxError:
        return set()
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(getattr(t, "id", "") == "QUESTIONS" for t in node.targets):
            return {k.value for k in node.value.keys if isinstance(k, ast.Constant)}
    return set()


def template_keys():
    """[(dot path, live)] of the template's key lines, live and in comments."""
    out, stack = [], []
    for line in read("templates/temper.config.default").splitlines():
        live = not line.lstrip().startswith("#")
        body = line if live else re.sub(r"^\s*# ?", "", line)
        m = re.match(r"^( *)([A-Za-z_][\w.-]*):(?:\s|$)", body)
        if not m:
            continue
        depth = len(m.group(1)) // 2
        stack[depth:] = [m.group(2)]
        out.append((".".join(stack[:depth + 1]), live))
    return out


def main():
    fails = []
    scripts = [f for f in tracked("scripts") if not f.startswith(TESTS)]
    texts = {f: read(f) for f in scripts if f not in NOT_READERS}
    # 1. a key of the table with no reader (a brief reads one only through the CLI: `config get <key>`)
    briefs = " ".join(m for f in tracked("agents", "reference", "commands") for m in re.findall(r"config get [a-z][\w.-]*", read(f)))
    for k, (_d, literal, _m) in defaults.KEYS.items():
        if not any(literal in t for t in texts.values()) and not (literal.startswith("config get ") and literal in briefs):
            fails.append("%s: a key of the table that no script reads (no file of scripts holds %r)" % (k, literal))
    # 2. a key read in code that the table lacks
    for f, t in sorted(texts.items()):
        for rx in READS:
            for k in rx.findall(t):
                if k in defaults.KEYS or still_read(k) or known(k):
                    continue
                fails.append("%s: read in %s, and the table of scripts/defaults.py lacks it" % (k, f))
    # 3. a key line of the template the table lacks
    tops = set()
    for path, live in template_keys():
        tops.add(path.split(".")[0])
        if not known(path):
            fails.append("%s: a %s key line of the template, and the table lacks it" % (path, "live" if live else "commented"))
    # 4. a page that names a key the table lacks
    qids = question_ids()
    seg = r"(?:[a-z][a-z0-9-]*|<[a-z]+>)"
    word = re.compile(r"(?<![\w/.$-])((?:%s)(?:\.%s)+)" % ("|".join(sorted(map(re.escape, tops))), seg))
    for f in tracked(*PAGES):
        if f.startswith(PAGES_OUT) or not f.endswith((".md", ".html", ".default", ".txt")):
            continue
        for k in sorted(set(word.findall(read(f)))):
            if (k.rsplit(".", 1)[-1] in EXTENSIONS or k in VIEW_FIELDS or k in qids or k.rsplit(".", 1)[0] in qids
                    or known(k) or still_read(k) or (f == RECORD and k in defaults.GONE)):
                continue
            fails.append("%s: named in %s, and the table lacks it" % (k, f))
    # 5. a brief or a reference page that sends an agent to the config
    for f in tracked("agents", "reference"):
        if f != "reference/pack.md" and "temper.config" in read(f):
            fails.append("%s: holds temper.config; the CLI names what an agent needs in its prompt (temper config get, "
                         "temper packs)" % f)
    for x in sorted(set(fails)):
        print("FAIL: " + x)
    if fails:
        return 1
    print("OK: %d keys, each with a reader; no page names a key the table lacks; no agent is sent to the config"
          % len(defaults.KEYS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
