"""block_stdin_wait.py: PreToolUse (Bash), refuse a command that would wait for input until the Bash timeout.

Claude Code runs a Bash command that holds a heredoc with its standard input left open, so a `cat` in that command
with no input of its own (`cat > file` before a `python3 - <<'EOF'`) waits until the tool's timeout, two minutes,
and the agent gets nothing back. Measured in 9.8.0's benchmark: 4 commands of Build agents, 480 seconds across 3 of
8 feature runs. Refused at once, the agent writes the file another way in its next step.

The hook only ever refuses: on a hit it prints one JSON answer, permissionDecision "deny", with the reason, and on
anything else it prints nothing. It never changes a tool call's input.

DEGRADATION CONTRACT:
  - no heredoc, or no `cat`, in the command                                   => no output, exit 0
  - the folder is not in a Temper project (no `.temper` folder in it or above) => no output, exit 0
  - a `cat` with no input in a command with a heredoc                          => the deny answer on stdout, exit 0
  - anything else, an internal error included                                  => no output, exit 0 (FAIL-OPEN)
"""
import json
import os
import re
import sys

SQ = "'"
DQ = '"'
HEREDOC = re.compile(r"<<(-?)\s*([" + SQ + DQ + r"]?)([A-Za-z_][A-Za-z0-9_]*)\2")
QUOTED = re.compile(SQ + "[^" + SQ + "]*" + SQ + "|" + DQ + r"(?:\\.|[^" + DQ + r"\\])*" + DQ)


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
        for m in HEREDOC.finditer(line):
            dash, word = m.group(1) == "-", m.group(3)
            while i < len(lines) and (lines[i].lstrip("\t") if dash else lines[i]) != word:
                i += 1
            i += 1
    return "\n".join(out)


def bare_cat(text):
    """The first `cat` of the text that has no input: no file, no `<`, not after a pipe."""
    text = QUOTED.sub(" Q ", text)
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


def main():
    raw = sys.stdin.read()
    # Most commands stop here: the JSON holds no heredoc marker, or no cat.
    if "<<" not in raw or "cat" not in raw:
        return
    d = json.loads(raw)
    cmd = (d.get("tool_input") or {}).get("command") or ""
    if "<<" not in cmd or not project(d.get("cwd")):
        return
    hit = bare_cat(without_bodies(cmd))
    if not hit:
        return
    reason = ("Temper: this command would wait for input until the Bash timeout (two minutes): `%s` has no input, and a "
              "command that holds a heredoc keeps its input open. Write the file with its own heredoc (cat > FILE <<'EOF' ... EOF) "
              "or with the Write tool, or leave that cat out, and run the rest again." % hit)
    sys.stdout.write(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                                        "permissionDecisionReason": reason}}) + "\n")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
