#!/usr/bin/env python3
"""plan_review.py: build and read back the interactive HTML plan review.

Usage:
  plan_review.py render <spec_dir> [--feature NAME] [--target file|artifact] [-o OUT]
  plan_review.py merge  --feature SLUG [-o OUT] <file.json|-> [<file.json> ...]

render  Fills templates/plan-review.html from <spec_dir>/plan.md and tasks.md and
        writes it (default <spec_dir>/review.html; "-o -" prints it; any other -o
        is a file name ending in .html). Every value is
        escaped for the context it lands in, so plan text such as "</script>" cannot
        break the page. `--target artifact` emits the fragment shape the Artifact
        tool expects: <title>, <style> and the body content, with no
        <!doctype>/<html>/<head>/<body> wrapper (the tool adds its own skeleton).

merge   Normalizes reviewer comments into the review-comments.json shape that
        reference/plan-review.md applies. Each input is either the page's exported
        JSON or a dump of the shared review's `comments` and `done` collections
        ({"comments": [...], "done": [...]}). Comments are de-duplicated by id,
        unknown types become `general-note`, empty text is dropped. "-o" is "-" or
        a file name ending in .json.

Neither command writes inside this plugin's own folder: an output path that resolves
there is refused (exit 2), so a review can never overwrite a file the plugin ships.
The one exception: when the current folder is the plugin folder and that folder is its
own git repository (a git work tree whose top level is the plugin folder, so never an
installed copy), an output that resolves under its .temper folder is allowed. Inside or
equal is decided by identity (device and inode, os.path.samefile), not by path text.

python3 stdlib only. No network.
"""
import argparse
import html
import json
import os
import re
import subprocess
import sys
from pathlib import Path

# The plugin folder: this file's resolved path with the literal suffix removed (written so that
# Python 3.7 and 3.8 run it too, as 9.6.0 did).
_SELF = str(Path(__file__).resolve())
_SUFFIX = "/scripts/plan_review.py"
ROOT = Path(_SELF[: -len(_SUFFIX)] if _SELF.endswith(_SUFFIX) else _SELF)
TEMPLATE = ROOT / "templates" / "plan-review.html"
SOURCES = ("plan.md", "tasks.md")
VALID_TYPES = ("task-change", "scenario-change", "plan-change", "general-note")
FENCE_RE = re.compile(r"^\s*(```|~~~)")
H1_RE = re.compile(r"^#\s+(.+?)\s*$")
H2_RE = re.compile(r"^##\s+(.+?)\s*$")


def js_json(value):
    """JSON that is safe inside an inline <script> block."""
    text = json.dumps(value, ensure_ascii=False)
    for ch, esc in (("<", "\\u003c"), (">", "\\u003e"), ("&", "\\u0026"),
                    (" ", "\\u2028"), (" ", "\\u2029")):
        text = text.replace(ch, esc)
    return text


def split_sections(text, source):
    """Split markdown at level-2 headings, ignoring headings inside code fences."""
    sections, title, buf, in_fence = [], None, [], False
    preamble_title = None

    def flush():
        body = "\n".join(buf).rstrip()
        if title is not None:
            sections.append({"title": title, "source": source, "content": body})
        else:
            rest = "\n".join(l for l in buf if not H1_RE.match(l)).strip()
            if rest:
                sections.append({"title": preamble_title or "Overview",
                                 "source": source, "content": body})

    for line in text.splitlines():
        if FENCE_RE.match(line):
            in_fence = not in_fence
        m = None if in_fence else H2_RE.match(line)
        if m:
            flush()
            title, buf = m.group(1), [line]
            continue
        if title is None and preamble_title is None and not in_fence:
            h1 = H1_RE.match(line)
            if h1:
                preamble_title = h1.group(1)
        buf.append(line)
    flush()
    return sections


def feature_name(spec_dir, override):
    if override:
        return override
    plan = spec_dir / "plan.md"
    if plan.is_file():
        for line in plan.read_text(encoding="utf-8").splitlines():
            m = H1_RE.match(line)
            if m:
                return re.sub(r"^(plan|tasks)\s*[:\-]\s*", "", m.group(1), flags=re.I)
    return spec_dir.name.replace("-", " ").replace("_", " ").strip().capitalize()


def _same(a, b):
    """True when `a` and `b` are the same file or folder (device and inode)."""
    try:
        return os.path.samefile(a, b)
    except OSError:
        return False


def _under(path, folder):
    """True when `path` is `folder` or lies inside it. Decided by identity, not by text:
    `path` is resolved (links followed) and each of its ancestors is compared with
    `folder` by device and inode, so another case on a file system that does not tell
    case apart, a symlink or a second mount of the same folder is still seen."""
    p = os.path.realpath(path)
    while True:
        if _same(p, folder):
            return True
        parent = os.path.dirname(p)
        if parent == p:
            return False
        p = parent


def _own_repository(folder):
    """True when `folder` is a git work tree whose top level is `folder` itself. Every
    GIT_* variable is dropped first, so a caller's GIT_DIR cannot answer for it."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    try:
        r = subprocess.run(["git", "-C", str(folder), "rev-parse", "--show-toplevel"],
                           env=env, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return False
    top = r.stdout.strip()
    return r.returncode == 0 and bool(top) and _same(top, folder)


def output_refusal(out, suffix):
    """Why `out` may not be written, or None. An output is a file name ending in `suffix`
    whose resolved location is outside this plugin's own folder. The one exception is the
    plugin's own repository used as the project (the current folder is the plugin folder,
    and that folder is a git work tree whose top level is itself): there an output under
    its .temper folder, the run state, is allowed, provided that folder is no symlink."""
    path = Path(out)
    if path.suffix.lower() != suffix:
        return f"output must be a file name ending in {suffix}: {out}"
    if _under(path, ROOT):
        temper = ROOT / ".temper"
        try:
            project_is_plugin = _same(os.getcwd(), ROOT)
        except OSError:
            project_is_plugin = False
        if (project_is_plugin and temper.is_dir() and not temper.is_symlink()
                and _under(path, temper) and _own_repository(ROOT)):
            return None
        return f"refusing to write inside the plugin's own folder: {out}"
    return None


def to_artifact_fragment(doc):
    """Drop the document wrapper; keep <title>, <style> and the body content."""
    title = re.search(r"<title>.*?</title>", doc, re.S)
    style = re.search(r"<style>.*?</style>", doc, re.S)
    body = re.search(r"<body[^>]*>(.*)</body>", doc, re.S)
    if not (title and style and body):
        raise ValueError("template is missing <title>, <style> or <body>")
    return "\n".join((title.group(0), style.group(0), body.group(1).strip())) + "\n"


def cmd_render(args):
    spec_dir = Path(args.spec_dir)
    if not spec_dir.is_dir():
        print(f"plan_review: no such spec directory: {spec_dir}", file=sys.stderr)
        return 2
    sections = []
    for name in SOURCES:
        path = spec_dir / name
        if path.is_file():
            sections += split_sections(path.read_text(encoding="utf-8"), name)
    if not sections:
        print(f"plan_review: no plan.md or tasks.md content under {spec_dir}", file=sys.stderr)
        return 2
    out = args.output or str(spec_dir / "review.html")
    refusal = None if out == "-" else output_refusal(out, ".html")
    if refusal:
        print(f"plan_review: {refusal}", file=sys.stderr)
        return 2
    if not TEMPLATE.is_file():
        print(f"plan_review: the page template is missing from the plugin: {TEMPLATE}", file=sys.stderr)
        return 2
    values = {
        "FEATURE_NAME": html.escape(feature_name(spec_dir, args.feature)),
        "FEATURE_SLUG": js_json(spec_dir.name),
        "SECTIONS_JSON": js_json(sections),
    }
    template = TEMPLATE.read_text(encoding="utf-8")
    # One pass, so a placeholder-looking string inside the plan is never re-expanded.
    doc = re.sub(r"\{\{(\w+)\}\}", lambda m: values.get(m.group(1), m.group(0)), template)
    if args.target == "artifact":
        doc = to_artifact_fragment(doc)
    if out == "-":
        sys.stdout.write(doc)
    else:
        Path(out).write_text(doc, encoding="utf-8")
        print(out)
    return 0


def normalize_comment(raw):
    if not isinstance(raw, dict):
        return None
    text = str(raw.get("text") or "").strip()
    if not text:
        return None
    ctype = raw.get("type") if raw.get("type") in VALID_TYPES else "general-note"
    out = {
        "id": str(raw.get("id") or ""),
        "target": str(raw.get("target_title") or raw.get("target") or ""),
        "type": ctype,
        "text": text,
        "timestamp": str(raw.get("timestamp") or ""),
        "resolved": bool(raw.get("resolved")),
    }
    author = str(raw.get("author") or "").strip()
    if author:
        out["author"] = author
    return out


def cmd_merge(args):
    refusal = None if args.output in (None, "-") else output_refusal(args.output, ".json")
    if refusal:
        print(f"plan_review: {refusal}", file=sys.stderr)
        return 2
    comments, seen, done_by, completed = [], set(), [], []
    flagged_done = False
    for src in args.inputs:
        try:
            data = json.load(sys.stdin if src == "-" else open(src, encoding="utf-8"))
        except (OSError, ValueError) as err:
            print(f"plan_review: cannot read {src}: {err}", file=sys.stderr)
            return 2
        if not isinstance(data, dict):
            print(f"plan_review: {src} is not a JSON object", file=sys.stderr)
            return 2
        for raw in data.get("comments") or []:
            c = normalize_comment(raw)
            key = c and (c["id"] or json.dumps(c, sort_keys=True))
            if c and key not in seen:
                seen.add(key)
                comments.append(c)
        for d in data.get("done") or []:
            if isinstance(d, dict):
                flagged_done = True
                if d.get("completed_at"):
                    completed.append(str(d["completed_at"]))
                if str(d.get("author") or "").strip():
                    done_by.append(str(d["author"]).strip())
        if data.get("review_completed"):
            flagged_done = True
            if data.get("completed_at"):
                completed.append(str(data["completed_at"]))
    comments.sort(key=lambda c: (c["timestamp"], c["id"]))
    result = {
        "version": 1,
        "feature": args.feature,
        "comments": comments,
        "review_completed": flagged_done,
        "completed_at": max(completed) if completed else None,
        "reviewers_done": sorted(set(done_by)),
    }
    text = json.dumps(result, indent=2, ensure_ascii=False) + "\n"
    if args.output and args.output != "-":
        Path(args.output).write_text(text, encoding="utf-8")
        print(args.output)
    else:
        sys.stdout.write(text)
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render")
    r.add_argument("spec_dir")
    r.add_argument("--feature")
    r.add_argument("--target", choices=("file", "artifact"), default="file")
    r.add_argument("-o", "--output")
    r.set_defaults(fn=cmd_render)
    m = sub.add_parser("merge")
    m.add_argument("--feature", required=True)
    m.add_argument("-o", "--output")
    m.add_argument("inputs", nargs="+")
    m.set_defaults(fn=cmd_merge)
    args = parser.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
