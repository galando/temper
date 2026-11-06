#!/usr/bin/env bash
#
# block-stdin-wait.sh — PreToolUse (Bash): refuse a command that would wait for input until the Bash timeout.
#
# Claude Code runs a Bash command that holds a heredoc with its standard input left open, so a `cat` in that command
# with no input of its own (`cat > file` before a `python3 - <<'EOF'`) waits until the tool's timeout, two minutes,
# and the agent gets nothing back. Measured in 9.8.0's benchmark: 4 commands of Build agents, 480 seconds across 3 of
# 8 feature runs. Refused at once, the agent writes the file another way in its next step.
#
# DEGRADATION CONTRACT:
#   - no heredoc, or no `cat`, in the command        => exit 0 (no-op, before any other program runs)
#   - the folder is not in a Temper project (no `.temper` folder in it or above it) => exit 0
#   - a `cat` with no input in a command with a heredoc => exit 2 (BLOCK, the reason on stderr)
#   - anything else, an internal error included      => exit 0 (FAIL-OPEN)
set -uo pipefail

_main() {
  local input
  input="$(cat)" || return 0
  # Most commands stop here: the JSON holds no heredoc marker, or no cat.
  [[ "$input" == *"<<"* && "$input" == *cat* ]] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  local why
  why="$(printf '%s' "$input" | python3 -I -c '
import json, os, re, sys

def project(cwd):
    d = os.path.abspath(cwd or ".")
    while True:
        if os.path.isdir(os.path.join(d, ".temper")):
            return True
        up = os.path.dirname(d)
        if up == d:
            return False
        d = up

def without_bodies(cmd):
    """The command with each heredoc body cut out: a body is data, never a command."""
    lines, out, i = cmd.split("\n"), [], 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        i += 1
        for m in re.finditer(r"<<(-?)\s*([\x27\"]?)([A-Za-z_][A-Za-z0-9_]*)\2", line):
            dash, word = m.group(1) == "-", m.group(3)
            while i < len(lines) and (lines[i].lstrip("\t") if dash else lines[i]) != word:
                i += 1
            i += 1
    return "\n".join(out)

def bare_cat(text):
    """The first `cat` of the text that has no input: no file, no `<`, not after a pipe."""
    text = re.sub(r"\x27[^\x27]*\x27|\"(?:\\.|[^\"\\])*\"", " Q ", text)
    prev = None
    for seg in re.split(r"(\|\||&&|;|\n|\||&(?!>))", text):
        if seg in ("||", "&&", ";", "\n", "|", "&"):
            prev = seg
            continue
        seg = re.sub(r"(\d*>>?|&>>?|<<<|<<-?|<)", r" \1 ", seg)
        words = seg.split()
        while words and (re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0]) or words[0] in ("then", "do", "else", "{", "(", "!", "time")):
            words = words[1:]
        after_pipe, prev = prev == "|", None
        if not words or words[0] != "cat" or after_pipe:
            continue
        rest, j, has_input = words[1:], 0, False
        while j < len(rest):
            w = rest[j]
            if w.startswith("<"):
                has_input = True
            elif re.fullmatch(r"\d*>>?|&>>?", w):
                j += 1
            elif not w.startswith("-") or w == "--":
                has_input = w != "--" or has_input
            j += 1
        if not has_input:
            return " ".join(words)[:80]
    return None

try:
    d = json.load(sys.stdin)
    cmd = (d.get("tool_input") or {}).get("command") or ""
    if "<<" in cmd and project(d.get("cwd")):
        hit = bare_cat(without_bodies(cmd))
        if hit:
            print(hit)
except Exception:
    pass
' 2>/dev/null)" || return 0
  [[ -z "$why" ]] && return 0
  {
    echo "Temper: this command would wait for input until the Bash timeout (two minutes): \`$why\` has no input, and a"
    echo "command that holds a heredoc keeps its input open. Write the file with its own heredoc (cat > FILE <<'EOF' ... EOF)"
    echo "or with the Write tool, or leave that cat out, and run the rest again."
  } >&2
  return 2
}

_main
exit $?
