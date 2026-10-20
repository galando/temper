#!/usr/bin/env python3
"""
guardrails-snippet.py: print the guardrails pack's hook entries, ready to paste into a project
settings file, for /temper:pack enable guardrails.

It opens one file, the plugin's own ${CLAUDE_PLUGIN_ROOT}/packs/guardrails/settings-guardrails.json,
and prints its `hooks` object as JSON with 2-space indents: in every command the plugin root
variable gives way to the plugin's absolute folder, and the script path is put in double quotes
(hooks in a settings file get no such variable). The person adds the entries to their project's
.claude/settings.local.json or .claude/settings.json themselves. Temper never opens a settings
file: this script reads only that one file of its own plugin, and nothing of the project, of the
home folder or of Claude Code's settings.

The plugin folder is this script's own folder, after following links, with the literal /scripts
taken off.

Exit codes:
  0  printed
  2  refused: the plugin folder cannot be found, holds a quote, a backslash, a dollar sign, a
     backtick or a line break (a command could not quote it), or the snippet file cannot be read

Python stdlib only. It runs, imports or sources nothing it reads.
"""
import json
import os
import sys

# The name of the plugin root variable, as the snippet file writes it in each command.
ROOT_VAR_NAME = "CLAUDE_PLUGIN_ROOT"
# A plugin folder holding one of these cannot go inside double quotes in a command.
UNSAFE = ("'", '"', "\\", "$", "`", "\n", "\r")


def refuse(message):
    print("guardrails-snippet: " + message, file=sys.stderr)
    sys.exit(2)


def plugin_folder():
    """This script's folder, after following links, with the literal /scripts taken off."""
    here = os.path.dirname(os.path.realpath(__file__))
    if os.path.basename(here) != "scripts":
        return None
    return os.path.dirname(here)


def filled(command, plugin):
    """The command with the plugin root variable replaced by the plugin folder, the script path in double quotes."""
    for form in ("${%s}" % ROOT_VAR_NAME, "$%s" % ROOT_VAR_NAME):
        at = command.find(form)
        if at < 0:
            continue
        head, rest = command[:at], command[at + len(form):]
        path, sep, tail = rest.partition(" ")
        return '%s"%s%s"%s%s' % (head, plugin, path, sep, tail)
    return command


def main():
    plugin = plugin_folder()
    if plugin is None:
        refuse("cannot find the plugin folder from this script's own folder")
    if any(c in plugin for c in UNSAFE):
        refuse("the plugin folder holds a character a command cannot quote; copy the entries by hand "
               "(packs/guardrails/rules.md, Install)")
    snippet = os.path.join(plugin, "packs", "guardrails", "settings-guardrails.json")
    try:
        with open(snippet, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError) as e:
        refuse("cannot read packs/guardrails/settings-guardrails.json (%s)" % str(e)[:120])
    hooks = data.get("hooks") if isinstance(data, dict) else None
    if not isinstance(hooks, dict):
        refuse("packs/guardrails/settings-guardrails.json has no hooks object")
    for blocks in hooks.values():
        for block in blocks if isinstance(blocks, list) else []:
            for hook in block.get("hooks", []) if isinstance(block, dict) else []:
                if isinstance(hook, dict) and isinstance(hook.get("command"), str):
                    hook["command"] = filled(hook["command"], plugin)
    print(json.dumps({"hooks": hooks}, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
