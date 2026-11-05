"""brief.py: the project brief, the CLI's map of the code a request touches (9.8.0, round 5).

  python3 brief.py PROJECT OUT [--text TEXT | --stdin]   writes OUT (the run's request by default: build-state.json)

Plan, Design and the root cause agent run on Opus, and each began by finding its way around the project: reading the
plugin's reference, then `cat` of the conventions and of every source file, an output too long for the tool that was
saved to a file and read back in a second turn. The brief does that finding with no model: the request's own words
(file paths, `backticked` names, METHOD /routes, nouns) rank the files that name them, their tests are the test files
that mention them, and the conventions files are copied in. The agents read one file, then only what it leaves out.
It is a map, not a limit, and it decides nothing.

Standard library only.
"""
import json
import os
import re
import subprocess
import sys
import time

SKIP_DIRS = (".temper/", ".claude/", ".git/", "node_modules/", "vendor/", "dist/", "build/", "target/", ".venv/",
             "venv/", "__pycache__/", ".idea/", ".vscode/", "coverage/")
TEXT_EXT = re.compile(r"\.(py|pyi|js|jsx|ts|tsx|mjs|cjs|go|rs|java|kt|kts|scala|rb|php|cs|c|h|cc|cpp|hpp|swift|m|sql|sh|"
                      r"bash|yml|yaml|toml|json|ini|cfg|md|txt|html|css|scss|vue|svelte|ex|exs|erl|clj|lua|r|dart)$", re.I)
CONVENTIONS = ("CONVENTIONS.md", "AGENTS.md", "CLAUDE.md", ".claude/CLAUDE.md", "CONTRIBUTING.md", "docs/CONVENTIONS.md")
TEST_PATH = re.compile(r"(^|/)(tests?|unit|spec|__tests__)/|(^|/)test_[^/]*$|_test\.[a-z]+$|\.(test|spec)\.[a-z]+$", re.I)
ROUTE = re.compile(r"\b(GET|POST|PUT|PATCH|DELETE)\s+(/[^\s`'\",;)]*)")
STOP = set("""a an the and or but not no nor for with without into onto from of to in on at by as is are was were be been being
this that these those it its it's their them they there here what which who whom whose when where why how all any each
every some such than then too very can could should would will shall may might must do does did done have has had having
make makes made build builds want wants need needs new add adds added use uses used today only also more most less
least other same one two three after before about above below over under again further once just like per via
customers customer user users finance team way part parts""".split())
WHOLE_BUDGET = 60000     # characters of whole files copied in, best ranked first
WHOLE_MAX = 20000        # a file longer than this is listed, not copied
LIST_MAX = 400           # project files listed


def git_files(project):
    try:
        out = subprocess.run(["git", "-C", project, "ls-files", "-z", "-co", "--exclude-standard"],
                             capture_output=True, check=True).stdout.decode("utf-8", "replace")
        files = [f for f in out.split("\0") if f]
    except (OSError, subprocess.CalledProcessError):
        files = []
        for root, dirs, names in os.walk(project):
            rel = os.path.relpath(root, project)
            dirs[:] = [d for d in dirs if not (("." if rel == "." else rel + "/") + d + "/").lstrip("./").startswith(SKIP_DIRS) and not d.startswith(".git")]
            files += [os.path.normpath(os.path.join(rel, n)) for n in names]
    return sorted(f for f in files if not f.startswith(SKIP_DIRS) and not any("/" + d in "/" + f for d in SKIP_DIRS)
                  and TEXT_EXT.search(f) and os.path.isfile(os.path.join(project, f)))


def read(project, f, limit=None):
    try:
        with open(os.path.join(project, f), encoding="utf-8", errors="replace") as h:
            return h.read(limit) if limit else h.read()
    except OSError:
        return ""


def terms(text):
    """The request's words that can name code: file paths, backticked names, routes, and nouns."""
    paths = sorted(set(re.findall(r"[\w.-]+(?:/[\w.-]+)+\.[A-Za-z]{1,5}\b|\b[\w-]+\.(?:py|js|ts|tsx|go|rs|java|rb|php|cs|sql|sh)\b", text)))
    ticks = re.findall(r"`([^`\n]{2,80})`", text)
    idents = sorted({w for t in ticks for w in re.findall(r"[A-Za-z_][A-Za-z0-9_]{2,}", t)
                     if not w.isupper() and w.lower() not in STOP and w not in ("GET", "POST", "PUT", "PATCH", "DELETE")})
    routes = sorted({(m.group(1), m.group(2).rstrip(".:")) for m in ROUTE.finditer(text)})
    segs = sorted({s for _, p in routes for s in p.split("/") if s and not re.match(r"^[{:<]", s)})
    words = sorted({w.lower() for w in re.findall(r"[A-Za-z][a-z]{3,}", re.sub(r"`[^`]*`", " ", text))} - STOP)
    return {"paths": paths, "identifiers": idents, "routes": ["%s %s" % r for r in routes], "segments": segs, "words": words}


def stem(word):
    return re.sub(r"(ies|es|s)$", "", word.lower())


def rank(project, files, t):
    """Each file the request's words reach, with its score and why."""
    stems = {stem(w): w for w in t["words"]}
    out = {}
    for f in files:
        why, score = [], 0
        base = os.path.basename(f)
        if any(f.endswith(p) or base == os.path.basename(p) for p in t["paths"]):
            why.append("named in the request")
            score += 10
        parts = [stem(x) for x in re.split(r"[/_.\-]", f.lower()) if x]
        hit = sorted({stems[s] for s in parts if s in stems})
        if hit:
            why.append("its path matches " + ", ".join(hit))
            score += 2 * len(hit)
        if t["identifiers"] or t["segments"]:
            text = read(project, f, 400000)
            ids = [i for i in t["identifiers"] if re.search(r"\b%s\b" % re.escape(i), text)]
            if ids:
                why.append("names " + ", ".join(ids[:8]) + (" and %d more" % (len(ids) - 8) if len(ids) > 8 else ""))
                score += 3 * len(ids)
            segs = [s for s in t["segments"] if ("/" + s) in text]
            if segs:
                why.append("holds the route part " + ", ".join("/" + s for s in segs))
                score += 2 * len(segs)
        if score:
            out[f] = (score, why)
    return out


def tests_of(project, files, touched):
    """The test files that mention a touched file's module (its stem or its import path)."""
    tests = [f for f in files if TEST_PATH.search(f)]
    out = {}
    for f in touched:
        if TEST_PATH.search(f):
            continue
        mod = os.path.splitext(os.path.basename(f))[0]
        dotted = os.path.splitext(f)[0].replace("/", ".")
        if mod in ("__init__", "index", "main"):
            continue
        for tf in tests:
            text = read(project, tf, 200000)
            if re.search(r"\b%s\b" % re.escape(mod), text) or dotted in text:
                out.setdefault(tf, []).append(f)
    return out


def lines_of(project, f):
    return read(project, f).count("\n")


def write(project, out_path, text):
    files = git_files(project)
    t = terms(text)
    conv = [c for c in CONVENTIONS if os.path.isfile(os.path.join(project, c))]
    ranked = rank(project, [f for f in files if f not in conv], t)
    # Test files go in their own list; a test that names the request's words but no touched module is still listed.
    order = sorted((f for f in ranked if not TEST_PATH.search(f)), key=lambda f: (-ranked[f][0], f))
    tests = tests_of(project, files, order)
    for f in ranked:
        if TEST_PATH.search(f) and f not in tests:
            tests[f] = []
    md = ["# Project brief", "",
          "Made by `temper brief` on %s from the request's words and the project's files, with no model: the files the "
          "request reaches, ranked, their tests, the conventions, and the project's file list. It is a map, not a limit: "
          "read any other file you need, and never take its ranking as a decision." % time.strftime("%Y-%m-%d"), "",
          "## The request's words that can name code", ""]
    for k, label in (("paths", "file paths"), ("identifiers", "backticked names"), ("routes", "routes"), ("words", "nouns")):
        if t[k]:
            md.append("- %s: %s" % (label, ", ".join(t[k][:60])))
    md += ["", "## Files the request reaches (%d)" % len(order), ""]
    if order:
        md += ["| File | Lines | Why |", "|---|---|---|"]
        md += ["| `%s` | %d | %s |" % (f, lines_of(project, f), "; ".join(ranked[f][1])) for f in order[:40]]
    else:
        md.append("None found by name: search the project for the request's terms.")
    if tests:
        md += ["", "## Their tests (%d)" % len(tests), ""]
        md += ["- `%s`: %s" % (tf, ("mentions " + ", ".join("`%s`" % x for x in sorted(set(src))[:6])) if src else "; ".join(ranked[tf][1]))
               for tf, src in sorted(tests.items())]
    if conv:
        md += ["", "## Conventions", ""]
        for c in conv:
            body = read(project, c, 12000)
            md += ["### `%s`" % c, "", "````markdown", body.rstrip(), "````", ""]
    whole, used = [], 0
    for f in order + sorted(tests):
        body = read(project, f)
        if not body or len(body) > WHOLE_MAX or used + len(body) > WHOLE_BUDGET or f in whole:
            continue
        whole.append(f)
        used += len(body)
    if whole:
        md += ["", "## The best ranked files, whole (%d, %d characters)" % (len(whole), used), ""]
        for f in whole:
            ext = os.path.splitext(f)[1].lstrip(".")
            md += ["### `%s`" % f, "", "````" + ext, read(project, f).rstrip(), "````", ""]
    md += ["", "## The project's files (%d)" % len(files), ""]
    md += ["- `%s` (%d)" % (f, lines_of(project, f)) for f in files[:LIST_MAX]]
    if len(files) > LIST_MAX:
        md.append("- and %d more: `git ls-files` lists them" % (len(files) - LIST_MAX))
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as h:
        h.write("\n".join(md).rstrip() + "\n")
    return len(order), len(tests), len(whole)


def main(argv):
    if len(argv) < 3:
        print("usage: brief.py PROJECT OUT [--text TEXT | --stdin]", file=sys.stderr)
        return 1
    project, out = argv[1], argv[2]
    if "--stdin" in argv:
        text = sys.stdin.read()
    elif "--text" in argv and argv.index("--text") + 1 < len(argv):
        text = argv[argv.index("--text") + 1]
    else:
        try:
            text = json.load(open(os.path.join(project, ".temper", "build-state.json"), encoding="utf-8")).get("feature") or ""
        except (OSError, ValueError):
            text = ""
    # No request (a run entered at a later stage with no feature text): the conventions and the file list still help, and
    # a call of the CLI's own action never fails for it.
    n, t, w = write(project, os.path.join(project, out) if not os.path.isabs(out) else out, text)
    print("OK: %s: %d files the request reaches, %d of their tests, %d copied whole" % (out, n, t, w))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
