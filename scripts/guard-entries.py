#!/usr/bin/env python3
"""
guard-entries.py: list the Temper guard entries in the project's own settings files, for the
stale guard check of /temper:pack (Step 1) and /temper:init (step 5).

It reads exactly two files, both in the project (the folder it runs in):

    <project>/.claude/settings.json
    <project>/.claude/settings.local.json

It never reads the home folder, and it refuses (exit 2, one line) when the project folder is
the home folder, because the .claude settings there are the user's own settings.

Output: one line per Temper guard entry, in file order (settings.json first), 5 fields:

    FILE|EVENT|MATCHER|SCRIPT|STATUS

FILE is .claude/settings.json or .claude/settings.local.json. EVENT is the hooks key (such as
PreToolUse). MATCHER is the block's matcher as the file writes it (empty when the block has
none), so it can hold '|' itself (Edit|Write): read FILE and EVENT from the left and SCRIPT and
STATUS from the right. SCRIPT is the script path taken from the command. STATUS is current when
SCRIPT lies under the current plugin folder and the file exists, and stale otherwise (a path that
holds a quote, a backslash, a dollar sign, a backtick or a line break is never tested as a file:
it is stale). A '|' in EVENT or SCRIPT is printed as '/', and a line break in any field as a
space.

A hook is a Temper guard entry when its command names one of the guard script files below, by
the rules of "Temper Guard Entries" in commands/pack.md (and reference/pack.md):

  1. A script path under the current plugin folder is Temper's, also when the plugin folder
     lies inside the project folder or is the project folder.
  2. A path that ends in /scripts/, one folder name, '/' and that script file, and lies outside
     the project folder, is Temper's (earlier plugin versions and earlier guard script
     folders). A path that starts with the CLAUDE_PLUGIN_ROOT variable is Temper's too: a
     settings hook gets no such variable.
  3. Anything else (a relative path, a path through the CLAUDE_PROJECT_DIR variable or another
     variable, a path inside the project folder) is the user's own copy and is not printed.

The script path is the command word whose last part is the script file name (the command is
split the way a shell splits words, so quotes are removed). The current plugin folder is this
script's own folder, after following links, with the literal /scripts taken off.

Exit codes:
  0  done (zero or more lines)
  1  a settings file that exists could not be read as a JSON object, or resolves outside the
     project folder: one line on stderr names it, and the other file's entries are still listed
  2  refused: the project folder is the home folder, or the plugin folder cannot be found

Security: print-only. It never runs, imports or sources anything it finds. Paths are checked
with os.path.realpath() and os.path.isfile(), which look at file metadata only. The only files
opened are the two project settings files, each after its resolved path is checked to be inside
the project folder. Python stdlib only.
"""
import json
import os
import pwd
import shlex
import sys

SETTINGS = (os.path.join(".claude", "settings.json"), os.path.join(".claude", "settings.local.json"))
GUARD_SCRIPTS = (
    "block-secrets.sh",
    "protect-regression-test.sh",
    "block-protected-paths.sh",
    "block-uncommitted-gate.sh",
    "confirm-override.sh",
    "block-forbidden-imports.sh",
    "run-formatter.sh",
    "stage-marker.sh",
    "verify-stage-gate.sh",
)
# Built from its name, so this file holds no plugin path form.
ROOT_VAR = "$" + "CLAUDE_PLUGIN_ROOT"
ROOT_VAR_BRACED = "$" + "{" + "CLAUDE_PLUGIN_ROOT"
# A path holding one of these is never tested as a file: it counts as stale.
UNSAFE = ("'", '"', "\\", "$", "`", "\n", "\r")


def refuse(message):
    print("guard-entries: " + message, file=sys.stderr)
    sys.exit(2)


def same_folder(a, b):
    try:
        return os.path.samefile(a, b)
    except (OSError, ValueError):
        return False


def is_home(project):
    """True when the project folder is the home folder, by file identity (HOME, or the
    account's home folder when HOME says otherwise)."""
    homes = []
    if os.environ.get("HOME"):
        homes.append(os.environ["HOME"])
    try:
        homes.append(pwd.getpwuid(os.getuid()).pw_dir)
    except (KeyError, OSError):
        pass
    return any(same_folder(project, h) for h in homes)


def plugin_folder():
    """This script's folder, after following links, with the literal /scripts taken off."""
    here = os.path.dirname(os.path.realpath(__file__))
    if os.path.basename(here) != "scripts":
        return None
    return os.path.dirname(here)


def under(path, folder):
    """True when path lies inside folder (both already resolved)."""
    prefix = folder.rstrip(os.sep) + os.sep
    return path.startswith(prefix)


def script_path(command):
    """The command word whose last part is a guard script file name, or None."""
    try:
        words = shlex.split(command)
    except ValueError:  # an unbalanced quote: split on whitespace and drop the quotes
        words = [w.strip("\"'") for w in command.split()]
    for word in words:
        if word.rsplit("/", 1)[-1] in GUARD_SCRIPTS:
            return word
    return None


def classify(path, plugin, project):
    """'current' or 'stale' for a Temper guard entry, None for the user's own copy."""
    if path.startswith(ROOT_VAR) or path.startswith(ROOT_VAR_BRACED):
        return "stale"
    if not path.startswith("/"):
        return None
    norm = os.path.normpath(path)
    real = os.path.realpath(norm)
    if under(real, plugin) or under(norm, plugin):
        if any(c in path for c in UNSAFE):
            return "stale"
        return "current" if os.path.isfile(real) else "stale"
    parts = norm.split("/")
    if len(parts) >= 4 and parts[-3] == "scripts" and parts[-2] not in ("", ".", ".."):
        if not under(real, project) and not under(norm, project):
            return "stale"
    return None


def clean(text, keep_pipe=False):
    text = text.replace("\r", " ").replace("\n", " ")
    return text if keep_pipe else text.replace("|", "/")


def read_settings(rel, project):
    """The parsed settings object, None when the file does not exist, or a reason string."""
    full = os.path.join(project, rel)
    if not os.path.lexists(full):
        return None
    real = os.path.realpath(full)
    if not under(real, project):
        return "resolves outside the project folder"
    if not os.path.isfile(real):
        return "is not a file"
    try:
        with open(real, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return "is not valid JSON"
    if not isinstance(data, dict):
        return "is not a JSON object"
    return data


def entries(data):
    """(event, matcher, command) for each hook with a string command, in file order."""
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        return
    for event, blocks in hooks.items():
        if not isinstance(blocks, list):
            continue
        for block in blocks:
            if not isinstance(block, dict) or not isinstance(block.get("hooks"), list):
                continue
            matcher = block.get("matcher")
            matcher = matcher if isinstance(matcher, str) else ""
            for hook in block["hooks"]:
                if isinstance(hook, dict) and isinstance(hook.get("command"), str):
                    yield str(event), matcher, hook["command"]


def main():
    project = os.path.realpath(".")
    if is_home(project):
        refuse("the project folder is your home folder, whose .claude settings are your own "
               "settings; Temper does not read them. Run this from a project folder.")
    plugin = plugin_folder()
    if plugin is None:
        refuse("cannot find the plugin folder: this script is not in a folder called scripts.")
    status = 0
    for rel in SETTINGS:
        data = read_settings(rel, project)
        if data is None:
            continue
        if isinstance(data, str):
            print("guard-entries: %s %s; its entries are not listed." % (rel, data), file=sys.stderr)
            status = 1
            continue
        for event, matcher, command in entries(data):
            path = script_path(command)
            if path is None:
                continue
            verdict = classify(path, plugin, project)
            if verdict is not None:
                print("|".join((rel, clean(event), clean(matcher, keep_pipe=True), clean(path), verdict)))
    return status


if __name__ == "__main__":
    sys.exit(main())
