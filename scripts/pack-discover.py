#!/usr/bin/env python3
"""
pack-discover.py — enumerate linkable pack targets (plugins, skills, commands) across
installed plugins plus project-local and global scopes, for /temper:pack's Step 5a
quick-create-launcher scan (see commands/pack.md).

Output: one line per target, 4 pipe-separated fields, deduplicated and deterministic:

    TYPE|name|path|description

TYPE is one of PLUGIN, SKILL, CMD, LOCAL_CMD, GLOBAL_CMD.

Security: print-only — this never execs or imports anything from a discovered path.
Every discovered file is resolved with os.path.realpath() and must stay under its
recorded installPath (or the project/home commands root) — a symlinked installPath
must not become a directory-traversal read. Glob walks are capped by depth and total
result count so a pathological install tree can't hang the scan. Frontmatter is read
with a line-bounded parse (first ``---``-fenced block, ``key: value`` scalars only) —
no PyYAML dependency added.
"""
import json
import os
import glob
import sys

MAX_DEPTH = 6
MAX_RESULTS = 500
HOME = os.path.expanduser("~")


def read_frontmatter(path):
    """Line-bounded frontmatter parse — first fenced ``---`` block, scalar keys only.
    Deliberately not yaml.safe_load: no new dependency, and nothing here needs lists
    or nested maps."""
    try:
        with open(path, "r", errors="ignore") as f:
            lines = f.readlines()
    except Exception:
        return {}
    if not lines or lines[0].strip() != "---":
        return {}
    fm = {}
    for line in lines[1:200]:  # bounded — frontmatter blocks are always short
        stripped = line.rstrip("\n")
        if stripped.strip() == "---":
            break
        if ":" not in stripped:
            continue
        key, _, val = stripped.partition(":")
        key = key.strip()
        val = val.strip().strip('"').strip("'")
        if key and val:
            fm[key] = val
    return fm


def safe_realpath_under(path, root):
    """realpath(path) must stay under realpath(root); refuse a symlink escape."""
    try:
        rp = os.path.realpath(path)
        rroot = os.path.realpath(root)
    except Exception:
        return None
    if rp == rroot or rp.startswith(rroot + os.sep):
        return rp
    return None


def bounded_glob(root, pattern):
    """glob under root, capped by MAX_DEPTH (path components beyond root) and
    MAX_RESULTS; every hit is realpath-checked to stay under root."""
    out = []
    try:
        hits = glob.glob(os.path.join(root, pattern), recursive=True)
    except Exception:
        return out
    for p in sorted(hits):
        if len(out) >= MAX_RESULTS:
            break
        rel = os.path.relpath(p, root)
        if rel.count(os.sep) > MAX_DEPTH:
            continue
        rp = safe_realpath_under(p, root)
        if rp and os.path.isfile(rp):
            out.append(rp)
    return out


def discover_plugins():
    """Installed plugins: 'name@marketplace' -> name, deduplicated. Iterates
    plugins.items() in sorted (name@marketplace) order so which marketplace wins a
    duplicate name is deterministic across runs, not JSON key-insertion order.
    Install-path selection: sort each name's entries by lastUpdated descending
    (falling back to (version, installPath) descending when lastUpdated is absent —
    real installed_plugins.json entries often carry "version": "unknown", which would
    otherwise make that tiebreak an unrelated path-string sort) and prefer the first
    whose installPath actually exists on disk — entries[-1] ("latest") depended on
    JSON key order and was not actually latest."""
    path = os.path.join(HOME, ".claude", "plugins", "installed_plugins.json")
    if not os.path.exists(path):
        return []
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        return []
    plugins = data.get("plugins", data if isinstance(data, dict) else {})
    if not isinstance(plugins, dict):
        return []

    by_pkg = {}
    for key in sorted(plugins.keys()):
        entries = plugins[key]
        if not isinstance(entries, list) or not entries:
            continue
        pkg_name = key.split("@")[0]
        if pkg_name == "temper":
            continue
        if pkg_name in by_pkg:
            continue  # first (deterministically sorted) marketplace wins

        def sort_key(e):
            last_updated = e.get("lastUpdated")
            has_last_updated = last_updated is not None and str(last_updated) != ""
            # Primary: lastUpdated (when present), so the most-recently-installed
            # entry wins. Fall back to (version, installPath) only for entries that
            # lack lastUpdated — version is frequently "unknown" across entries, so
            # without this, ties silently fell through to an unrelated path sort.
            return (
                has_last_updated,
                str(last_updated) if has_last_updated else "",
                str(e.get("version", "")),
                str(e.get("installPath", "")),
            )

        candidates = sorted(entries, key=sort_key, reverse=True)
        chosen = next(
            (e for e in candidates if e.get("installPath") and os.path.isdir(e["installPath"])),
            candidates[0] if candidates else None,
        )
        if chosen is not None:
            by_pkg[pkg_name] = chosen
    return sorted(by_pkg.items())


def plugin_description(install_path):
    pj = os.path.join(install_path, ".claude-plugin", "plugin.json")
    try:
        with open(pj) as f:
            return json.load(f).get("description", "")
    except Exception:
        return ""


def emit(seen, type_, name, path, desc):
    key = (type_, name)
    if key in seen:
        return False
    seen.add(key)
    desc = (desc or "").replace("|", "/").replace("\n", " ").strip()
    print(f"{type_}|{name}|{path}|{desc}")
    return True


def main():
    seen = set()
    results = 0

    for pkg_name, entry in discover_plugins():
        if results >= MAX_RESULTS:
            break
        install_path = entry.get("installPath", "")
        if not install_path or not os.path.isdir(install_path):
            continue
        plugin_desc = plugin_description(install_path)
        emitted_any = False

        skill_files = bounded_glob(install_path, "skills/*/SKILL.md") + bounded_glob(
            install_path, ".claude/skills/*/SKILL.md"
        )
        for s in sorted(set(skill_files)):
            skill_dir = os.path.basename(os.path.dirname(s))
            fm = read_frontmatter(s)
            if emit(seen, "SKILL", f"{pkg_name}:{skill_dir}", os.path.dirname(s), fm.get("description", plugin_desc)):
                emitted_any = True
                results += 1

        cmd_files = bounded_glob(install_path, "commands/**/*.md") + bounded_glob(
            install_path, ".claude/commands/**/*.md"
        )
        for c in sorted(set(cmd_files)):
            cmd_name = os.path.splitext(os.path.basename(c))[0]
            fm = read_frontmatter(c)
            if emit(seen, "CMD", f"{pkg_name}:{cmd_name}", os.path.dirname(c), fm.get("description", plugin_desc)):
                emitted_any = True
                results += 1

        if not emitted_any:
            if emit(seen, "PLUGIN", pkg_name, install_path, plugin_desc):
                results += 1

    # Project-local and global commands — same 4-field arity as everything above (the
    # arity mismatch was defect #6: these used to emit only 3 fields).
    for label, root in (
        ("LOCAL_CMD", os.path.join(".", ".claude", "commands")),
        ("GLOBAL_CMD", os.path.join(HOME, ".claude", "commands")),
    ):
        if results >= MAX_RESULTS or not os.path.isdir(root):
            continue
        for c in bounded_glob(root, "*.md"):
            if results >= MAX_RESULTS:
                break
            cmd_name = os.path.splitext(os.path.basename(c))[0]
            fm = read_frontmatter(c)
            if emit(seen, label, cmd_name, c, fm.get("description", "")):
                results += 1


if __name__ == "__main__":
    main()
    sys.exit(0)
