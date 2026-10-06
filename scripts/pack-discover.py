#!/usr/bin/env python3
"""
pack-discover.py: list the project's own link targets for the quick-create launcher of
/temper:pack (Step 5a of commands/pack.md).

It reads only the project, the folder it runs in:

    LOCAL_CMD    each visible .md file directly in <project>/.claude/commands
    LOCAL_SKILL  each visible folder in <project>/.claude/skills that holds a SKILL.md

Output: one line per target, 4 pipe-separated fields, deduplicated and deterministic (commands
first, then skills, each sorted by name):

    TYPE|name|path|description

name is the command's file name without .md, or the skill's folder name. path is the file a link
reads: the command file, or the skill's SKILL.md, as a full resolved path. description comes from
that file's frontmatter (empty when it has none).

It reads nothing in the home folder and none of Claude Code's own files: no installed plugin list,
no plugin folder, no home commands or skills. Link targets from plugins, and from the user's own
home skills and commands, come from the skills and slash commands the Claude session lists (see
reference/pack.md).

Security: print-only. It never runs or imports anything it finds. Each folder and file is resolved
with os.path.realpath(): the commands and skills folders must stay inside the project, and each
file inside the folder it was listed from, so a symlink cannot turn into a read outside the
project (a .claude/commands linked to the home folder is not listed). Folders are listed
with os.scandir (no wildcard patterns), hidden entries (a leading '.') are left out, and the number
of rows is capped. Frontmatter is read with a line-bounded parse (the first block fenced by '---',
'key: value' scalars only), so no YAML library is needed.
"""
import os
import sys

MAX_RESULTS = 500
COMMANDS = os.path.join(".claude", "commands")
SKILLS = os.path.join(".claude", "skills")


def read_frontmatter(path):
    """The first block fenced by '---', scalar 'key: value' pairs only. Not yaml.safe_load: no new
    dependency, and nothing here needs lists or nested maps."""
    try:
        with open(path, "r", errors="ignore") as f:
            lines = f.readlines()
    except OSError:
        return {}
    if not lines or lines[0].strip() != "---":
        return {}
    fm = {}
    for line in lines[1:200]:  # bounded: frontmatter blocks are always short
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


def inside(path, folder):
    """realpath(path) when it stays inside realpath(folder), else None (a symlink escape)."""
    try:
        rp = os.path.realpath(path)
        rfolder = os.path.realpath(folder)
    except (OSError, ValueError):
        return None
    return rp if rp.startswith(rfolder + os.sep) else None


def visible_entries(folder):
    """Entries of one folder, sorted by name, hidden ones (a leading '.') left out. A missing or
    unreadable folder has none."""
    try:
        with os.scandir(folder) as it:
            entries = [e for e in it if not e.name.startswith(".")]
    except OSError:
        return []
    return sorted(entries, key=lambda e: e.name)


def project_folder(project, sub):
    """<project>/<sub> when it is a folder that resolves inside the project, else None: a
    .claude, commands or skills folder that links out of the project is never listed."""
    folder = os.path.join(project, sub)
    rp = inside(folder, project)
    return folder if rp and os.path.isdir(rp) else None


def project_commands(project):
    """(name, path) for each visible .md file directly in <project>/.claude/commands."""
    folder = project_folder(project, COMMANDS)
    if folder is None:
        return
    for e in visible_entries(folder):
        if not e.name.endswith(".md"):
            continue
        rp = inside(os.path.join(folder, e.name), folder)
        if rp and os.path.isfile(rp):
            yield e.name[: -len(".md")], rp


def project_skills(project):
    """(name, path of SKILL.md) for each visible folder in <project>/.claude/skills that holds one."""
    folder = project_folder(project, SKILLS)
    if folder is None:
        return
    for e in visible_entries(folder):
        rp = inside(os.path.join(folder, e.name, "SKILL.md"), folder)
        if rp and os.path.isfile(rp):
            yield e.name, rp


def clean(text):
    return (text or "").replace("|", "/").replace("\n", " ").strip()


def main():
    project = "."
    seen = set()
    for type_, targets in (("LOCAL_CMD", project_commands(project)), ("LOCAL_SKILL", project_skills(project))):
        for name, path in targets:
            if len(seen) >= MAX_RESULTS:
                return
            # A name or path with '|' or a line break would break the row format: left out.
            if (type_, name) in seen or any(c in name + path for c in "|\n\r"):
                continue
            seen.add((type_, name))
            print(f"{type_}|{name}|{path}|{clean(read_frontmatter(path).get('description', ''))}")


if __name__ == "__main__":
    main()
    sys.exit(0)
