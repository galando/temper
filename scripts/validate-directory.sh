#!/usr/bin/env bash
# validate-directory.sh: checks the plugin is ready for a plugin directory listing.
# Offline-safe, no network calls. Each rule prints one FAIL line and the script exits 1.
#
# Rules:
#   1. README.md has no raw HTML tags (outside code fences and inline code).
#   2. README.md has an "Install" heading and a "What the mod reads and writes" heading.
#   3. README.md has a plain text line that names the phases, before the Mermaid block.
#   4. Every image in README.md has alt text.
#   5. No text file names the bundled assets folder outside a Markdown link target. git grep
#      reads the files, chosen by fixed pathspecs: top level files, .claude/CLAUDE.md and the
#      folders listed at rule 5 below. No other folder is read.
#   6. plugin.json and marketplace.json carry no "options" key.
#   7. plugin.json has a description, keywords and a version, and marketplace.json
#      names the same plugin.
#   8. A LICENSE file exists (LICENSE, LICENSE.md or LICENSE.txt).
#   9. No shell or Python script writes into, removes from, moves, links or makes a path with a
#      folder named hooks (git's hook folders share that name with the plugin folder that holds
#      the mod, and the directory cannot tell them apart). Comments do not count, and this script
#      is not read. It catches a write whose own words name the folder, also through a $( ) span
#      that runs git rev-parse, ${NAME} or its default, a cd or pushd into the folder (on the same
#      line, or alone on a line before), or a variable (shell, or Python in a .py file) set to such
#      a path earlier in the same file; a name built from pieces at run time is for review.
#
# It checks the plugin folder it sits in, and nothing in the environment moves that folder: the
# tests copy this script into a temporary plugin and run the copy there. The folder must be a git
# work tree (rule 5 reads its files with git grep). This script writes nothing.
set -uo pipefail

# With CDPATH set, cd prints the folder it enters, and the path below would hold it twice.
unset CDPATH
# The plugin folder: this script sits in its scripts folder, so strip that literal suffix.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${HERE%/scripts}"
[[ "$ROOT" != "$HERE" ]] || { echo "FAIL: cannot find the plugin folder from $HERE"; exit 1; }
FAIL=0
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

README="$ROOT/README.md"
PLUGIN="$ROOT/.claude-plugin/plugin.json"
MARKET="$ROOT/.claude-plugin/marketplace.json"

# The README text without fenced code blocks and without inline code spans.
readme_prose() {
  awk '/^```/ { skip = !skip; next } !skip' "$README" | sed -E 's/`[^`]*`//g'
}

if [[ ! -f "$README" ]]; then
  fail "README.md is missing"
else
  # 1. Raw HTML. Comments are tags too; autolinks like <https://x> are not.
  HTML="$(readme_prose | grep -nE '</?[A-Za-z][A-Za-z0-9]*([[:space:]/>]|$)|<!--' | grep -vE '<https?://' || true)"
  if [[ -n "$HTML" ]]; then
    fail "README.md has raw HTML (the directory does not render it):"
    printf '%s\n' "$HTML" | head -5 | sed 's/^/  /'
  fi

  # 2. Required headings.
  grep -qE '^#{1,3} .*Install' "$README" || fail "README.md has no Install heading"
  grep -qE '^#{1,3} What the mod reads and writes' "$README" \
    || fail "README.md has no 'What the mod reads and writes' heading"

  # 3. The plain diagram line must come before the Mermaid block.
  MERMAID_LINE="$(grep -n '^```mermaid' "$README" | head -1 | cut -d: -f1)"
  if [[ -n "$MERMAID_LINE" ]]; then
    head -n "$((MERMAID_LINE - 1))" "$README" | grep -qE 'Intent, Plan, Build, Review, Check' \
      || fail "README.md has a Mermaid diagram with no plain text line of the phases before it"
  fi

  # 4. Alt text on every image.
  if grep -nE '!\[\]\(' "$README" >/dev/null; then
    fail "README.md has an image with empty alt text"
  fi
fi

# 5. The bundled assets folder path may appear only as a Markdown link target.
# git grep reads the files, chosen by the fixed pathspecs below (tracked files, plus new files git
# does not ignore): a top level file, .claude/CLAUDE.md, or a file in one of the named folders.
# docs/history (old release notes), scripts/selftest and this script are excluded. This rule opens
# no file itself: it only filters the lines git grep prints, keeping a file with an md, sh, tape,
# tpl or json extension and a line that still names the folder once every Markdown link target on
# it is removed. The other rules open only the plugin folder plus fixed text (README.md, the two
# manifests, the license).
ASSETS_DIR_NAME="docs/assets"
LEAKS=""
if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  fail "rule 5 reads files with git grep, and $ROOT is not a git work tree"
else
  SEEN=$'\n'
  while IFS= read -r -d '' rel && IFS= read -r -d '' lineno && IFS= read -r line; do
    [[ "$rel" =~ \.(md|sh|tape|tpl|json)$ ]] || continue
    [[ "$SEEN" != *$'\n'"$rel"$'\n'* ]] || continue
    rest="$(printf '%s\n' "$line" | sed -E 's/\]\([^)]*\)//g')"
    [[ "$rest" == *"$ASSETS_DIR_NAME"* ]] || continue
    SEEN+="$rel"$'\n'
    LEAKS+="  $rel: $(printf '%s:%s' "$lineno" "$rest" | cut -c1-100)"$'\n'
  done < <(git -C "$ROOT" -c grep.column=false -c grep.fullName=false -c grep.lineNumber=true \
             grep --untracked -z -n -I -F -e "$ASSETS_DIR_NAME" -- \
             ':(glob)*' .claude/CLAUDE.md .claude-plugin .github agents commands docs examples \
             packs reference scripts skills templates \
             ':(exclude)docs/history' ':(exclude)scripts/selftest' ':(exclude)scripts/validate-directory.sh' \
             2>/dev/null)
fi
if [[ -n "$LEAKS" ]]; then
  fail "the bundled assets folder path is named outside a Markdown link target:"
  printf '%s' "$LEAKS"
fi

# 6 and 7. The manifests.
for m in "$PLUGIN" "$MARKET"; do
  [[ -f "$m" ]] || { fail "$(basename "$m") is missing"; continue; }
  if grep -q '"options"' "$m"; then
    fail "$(basename "$m") has an \"options\" key (it stops the plugin loading before Claude Code 2.1.271)"
  fi
done
if [[ -f "$PLUGIN" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$PLUGIN" "$MARKET" <<'PY' || FAIL=$((FAIL+1))
import json, sys
bad = False
def no(msg):
    global bad
    print("FAIL: " + msg)
    bad = True
p = json.load(open(sys.argv[1]))
if not str(p.get("description", "")).strip():
    no("plugin.json has no description")
if not isinstance(p.get("keywords"), list) or not p["keywords"]:
    no("plugin.json has no keywords")
if not str(p.get("version", "")).strip():
    no("plugin.json has no version")
try:
    m = json.load(open(sys.argv[2]))
    names = [e.get("name") for e in m.get("plugins", [])]
    if p.get("name") not in names:
        no("marketplace.json does not list the plugin named " + str(p.get("name")))
    for e in m.get("plugins", []):
        if not str(e.get("description", "")).strip():
            no("marketplace.json plugin " + str(e.get("name")) + " has no description")
except FileNotFoundError:
    pass
sys.exit(1 if bad else 0)
PY
  else
    fail "python3 is required for the manifest checks"
  fi
fi

# 8. License.
[[ -f "$ROOT/LICENSE" || -f "$ROOT/LICENSE.md" || -f "$ROOT/LICENSE.txt" ]] || fail "no LICENSE file"

# 9. No script writes into a folder named hooks. The files are the ones git lists (tracked, plus
# new files git does not ignore): shell scripts (.sh, .bash, or a first line that runs sh or bash),
# Python files and workflow files. A line counts when, with its comment taken off, the path a
# command, a redirect or a call writes (removes, moves, links or makes) has a part with that name.
# A cp or ln writes its last path, find only the paths it starts from, sed and perl only with -i,
# curl, wget and tar only the file or folder they are told to write. Only the plugin folder is read.
WRITE_SEGMENT_NAME="hooks"
if command -v python3 >/dev/null 2>&1 && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  python3 - "$ROOT" "$WRITE_SEGMENT_NAME" <<'PY' || FAIL=$((FAIL+1))
import os, re, shlex, subprocess, sys
root, name = sys.argv[1], sys.argv[2]
own = "scripts/validate-directory.sh"
listed = subprocess.run(["git", "-C", root, "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                        capture_output=True, check=False).stdout.decode("utf-8", "replace").split("\0")
# Commands that write every path they are given, and those that write the last path only (or the
# one after -t); and words that come before a command.
WRITE_ALL = {"rm", "rmdir", "mv", "mkdir", "chmod", "chown", "chgrp", "touch", "truncate", "unlink", "tee", "shred"}
WRITE_LAST = {"cp", "ln", "install", "rsync"}
PREFIXES = {"sudo", "command", "exec", "env", "xargs", "nohup", "time", "then", "do", "else", "!", "nice"}
redirect = re.compile(r"(?<![<>=-])(?:[0-9]?>>?|&>>?)\|?\s*([^\s;|&<>()]+)")
comment = re.compile(r"(?:^|\s)#.*$")
var_use = re.compile(r"\$([A-Za-z_][A-Za-z0-9_]*)")
braced = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?:(:?[-=])([^}]*)|[^}]*)\}")
quoted = re.compile(r"""(['"])((?:\\.|(?!\1).)*)\1""")
assign = re.compile(r"(?:^|[\s;(])(?:local\s+|export\s+|readonly\s+|declare\s+(?:-\w+\s+)*)?([A-Za-z_][A-Za-z0-9_]*)=(\S+)")
py_assign = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*[\w.\[\], ]+)?=(?!=)\s*(.+)$")


def names_folder(word, folder_vars=()):
    """True when a word names the folder as a path part, or starts with a variable that holds one."""
    w = word.strip("\"'`")
    m = re.match(r"^(?:-{1,2}[A-Za-z][A-Za-z-]*=|of=)(.*)$", w)
    if m:
        w = m.group(1)
    parts = re.split(r"[/\"']", w)
    if name in parts[:-1] or parts[-1] == name:
        return True
    v = var_use.match(w)
    return bool(v and v.group(1) in folder_vars)


def stand_in(body):
    """What a $( ) or ` ` span stands for in a path: git's own folders by name, the words an echo
    prints, and otherwise the word $X."""
    git = re.match(r"^\s*git\b.*\brev-parse\b(.*)$", body)
    if git:
        path = re.search(r"--git-path[\s=]+(\S+)", git.group(1))
        if path:
            return ".git/" + path.group(1).strip("\"'")
        if re.search(r"--(?:absolute-)?git-(?:common-)?dir\b", git.group(1)):
            return ".git"
    echo = re.match(r"^\s*(?:echo|printf\s+%s)\s+(.*)$", body)
    if echo:
        return echo.group(1).strip()
    return "$X"


def spans(text):
    """The text with ${NAME} written $NAME (${NAME:-word} as its word), each $( ) and ` ` span put
    as what it stands for, and the text of each span."""
    text = braced.sub(lambda m: m.group(3) if m.group(2) else "$" + m.group(1), text)
    out, bodies, i = [], [], 0
    while i < len(text):
        if text.startswith("$(", i) and not text.startswith("$((", i):
            depth, j = 1, i + 2
            while j < len(text) and depth:
                depth += {"(": 1, ")": -1}.get(text[j], 0)
                j += 1
            bodies.append(text[i + 2:j - 1])
            out.append(stand_in(bodies[-1]))
            i = j
            continue
        if text[i] == "`":
            j = text.find("`", i + 1)
            j = len(text) if j < 0 else j
            bodies.append(text[i + 1:j])
            out.append(stand_in(bodies[-1]))
            i = j + 1
            continue
        out.append(text[i])
        i += 1
    return "".join(out), bodies


def script_files(words):
    """The file words of sed or perl, without the program text."""
    files, skip, program = [], False, False
    for a in words:
        if skip:
            skip = False
            continue
        if a in ("-e", "-f", "--expression", "--file"):
            skip = program = True
            continue
        if a.startswith("-"):
            continue
        if not program:
            program = True
            continue
        files.append(a)
    return files


def targets(words):
    """The words a command writes, or [] when it writes none."""
    cmd, args = os.path.basename(words[0]), words[1:]
    plain = [a for a in args if not a.startswith("-")]
    if cmd in WRITE_ALL:
        return plain
    if cmd in WRITE_LAST:
        for k, a in enumerate(args):
            if a in ("-t", "--target-directory") and k + 1 < len(args):
                return [args[k + 1]]
            if a.startswith("--target-directory="):
                return [a]
        return plain[-1:]
    if cmd == "sed" and any(re.match(r"^-[A-Za-z]*i", a) or a.startswith("--in-place") for a in args):
        return script_files(args)
    if cmd == "perl" and any(re.match(r"^-[A-Za-z]*i", a) for a in args):
        return script_files(args)
    if cmd == "dd":
        return [a for a in args if a.startswith("of=")]
    out = []
    flags = {"curl": ("-o", "--output", "--output-dir"), "wget": ("-O", "--output-document", "-P", "--directory-prefix"),
             "tar": ("-C", "--directory"), "bsdtar": ("-C", "--directory"), "unzip": ("-d",)}.get(cmd)
    if flags:
        for k, a in enumerate(args):
            if a in flags and k + 1 < len(args):
                out.append(args[k + 1])
            elif "=" in a and a.split("=", 1)[0] in flags:
                out.append(a)
            elif cmd == "curl" and re.match(r"^-[A-Za-z]*o$", a) and k + 1 < len(args):
                out.append(args[k + 1])
        return out
    if cmd == "find":
        runs = [k for k, a in enumerate(args) if a in ("-exec", "-execdir", "-ok", "-okdir")]
        writer = any(k + 1 < len(args) and (os.path.basename(args[k + 1]) in WRITE_ALL | WRITE_LAST
                                            or targets(args[k + 1:])) for k in runs)
        if "-delete" in args or writer:
            for a in args:
                if a.startswith("-") or a in ("(", "!", "\\("):
                    break
                out.append(a)
        return out
    return []


def parts(text):
    """The simple commands of a shell line, split on ; && || | ( ) { } outside quotes."""
    out, cur, quote, i = [], "", "", 0
    while i < len(text):
        ch = text[i]
        if quote:
            cur += ch
            if ch == "\\" and quote == '"' and i + 1 < len(text):
                cur += text[i + 1]
                i += 1
            elif ch == quote:
                quote = ""
        elif ch in "\"'":
            quote = ch
            cur += ch
        elif text.startswith("&&", i) or text.startswith("||", i):
            out.append(cur)
            cur = ""
            i += 1
        elif ch in ";|(){}" and not (ch == "|" and cur.rstrip().endswith(">")):
            out.append(cur)
            cur = ""
        else:
            cur += ch
        i += 1
    out.append(cur)
    return [p for p in out if p.strip()]


def words_of(part):
    try:
        words = shlex.split(part, posix=True)
    except ValueError:
        words = part.split()
    dropped = False
    while words and (words[0] in PREFIXES or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0])
                     or (dropped and words[0].startswith("-"))):
        dropped = dropped or words[0] in PREFIXES
        words = words[1:]
    return words


def relative(word):
    return not word.strip("\"'").startswith(("/", "$", "&", "~"))


def shell_hits(text, folder_vars, in_folder=False):
    """True when the shell line writes into the folder. in_folder: an earlier line went into it."""
    flat, bodies = spans(text)
    if any(shell_hits(b, folder_vars) for b in bodies):
        return True
    for part in parts(flat):
        words = words_of(part)
        if words and words[0] in ("cd", "pushd"):
            in_folder = len(words) > 1 and names_folder(words[1], folder_vars)
            continue
        if words and words[0] in ("[[", "[", "test"):
            continue
        for m in redirect.finditer(part):
            target = m.group(1)
            if names_folder(target, folder_vars) or (in_folder and relative(target)):
                return True
        if not words:
            continue
        found = targets(words)
        if any(names_folder(w, folder_vars) for w in found) or (in_folder and any(relative(w) for w in found)):
            return True
    return False


def cd_state(text, folder_vars, state):
    """Whether a line that is only a cd or pushd (or popd) leaves the next lines in the folder."""
    flat, _ = spans(text)
    found = parts(flat)
    words = words_of(found[0]) if len(found) == 1 else []
    if words and words[0] in ("cd", "pushd"):
        return len(words) > 1 and names_folder(words[1], folder_vars)
    if words and words[0] == "popd":
        return False
    return state


# Python calls that write their first argument, their second (the destination), or both (a move).
PY_FIRST = r"(?:os\.(?:makedirs|mkdir|remove|unlink|rmdir|removedirs|chmod|chown|truncate)|shutil\.(?:rmtree|chown)|makedirs|rmtree)"
PY_SECOND = r"(?:os\.(?:symlink|link)|shutil\.(?:copy|copy2|copyfile|copytree|copymode|copystat))"
PY_BOTH = r"(?:os\.(?:rename|renames|replace)|shutil\.move)"
PY_METHODS = r"\.(?:write_text|write_bytes|mkdir|touch|unlink|rmdir|symlink_to|hardlink_to|chmod|rename|replace|open)\s*\("


def call_args(text, start):
    """The top level arguments of the call (or list) whose open bracket ends just before start."""
    args, depth, cur, quote = [], 0, "", ""
    for ch in text[start:]:
        if quote:
            cur += ch
            if ch == quote:
                quote = ""
            continue
        if ch in "\"'":
            quote = ch
        elif ch in "([{":
            depth += 1
        elif ch in ")]}":
            if depth == 0:
                break
            depth -= 1
        elif ch == "," and depth == 0:
            args.append(cur.strip())
            cur = ""
            continue
        cur += ch
    args.append(cur.strip())
    return args


def py_names(expr, py_vars):
    """True when a Python expression names the folder in a string literal, or uses a variable that does."""
    if any(names_folder(m.group(2)) for m in quoted.finditer(expr)):
        return True
    return any(re.search(r"(?<![\w.'\"])" + re.escape(v) + r"(?![\w'\"])", expr) for v in py_vars)


def write_mode(args):
    modes = [a.split("=", 1)[1].strip() for a in args if a.replace(" ", "").startswith("mode=")]
    modes += [a for a in args[:1] if re.fullmatch(r"['\"][rwabxt+]*['\"]", a)]
    flags = [a for a in args if re.search(r"\bO_(?:WRONLY|RDWR|CREAT|TRUNC|APPEND)\b", a)]
    return bool(flags) or any(re.fullmatch(r"['\"][rwabxt+]*[wax+][rwabxt+]*['\"]", md) for md in modes)


def py_hits(text, py_vars):
    for m in re.finditer(r"(?:\b(?:io|codecs|os)\.|(?<![\w.]))open\s*\(", text):
        args = call_args(text, m.end())
        if args and py_names(args[0], py_vars) and write_mode(args[1:]):
            return True
    for pattern, pick in ((PY_FIRST, lambda a: a[:1]), (PY_SECOND, lambda a: a[1:2]), (PY_BOTH, lambda a: a[:2])):
        for m in re.finditer(r"(?<![\w.])" + pattern + r"\s*\(", text):
            if any(py_names(a, py_vars) for a in pick(call_args(text, m.end()))):
                return True
    for m in re.finditer(PY_METHODS, text):
        receiver = text[:m.start()]
        tail = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\s*$", receiver)
        by_var = bool(tail and tail.group(1) in py_vars)
        by_path = bool(re.search(r"\b(?:Pure)?(?:Posix|Windows)?Path\s*\(|\s/\s", receiver)) and py_names(receiver, ())
        if not (by_var or by_path):
            continue
        if m.group(0).startswith(".open") and not write_mode(call_args(text, m.end())):
            continue
        return True
    for m in re.finditer(r"\[\s*(['\"])([A-Za-z0-9_.-]+)\1\s*,", text):
        words = []
        for a in call_args(text, m.start() + 1):
            q = quoted.fullmatch(a)
            words.append(q.group(2) if q else "$X")
        if words and any(names_folder(w) for w in targets(words)):
            return True
    if re.search(r"\bos\.(?:system|popen)\s*\(|shell\s*=\s*True", text):
        if any(shell_hits(q.group(2), ()) for q in quoted.finditer(text)):
            return True
    return False


def kind(rel, path):
    if rel.endswith((".sh", ".bash")):
        return "sh"
    if rel.endswith(".py"):
        return "py"
    if rel.startswith(".github/") and rel.endswith((".yml", ".yaml")):
        return "sh"
    if "." not in os.path.basename(rel):
        try:
            with open(path, "rb") as f:
                first = f.readline(200)
        except OSError:
            return None
        if first.startswith(b"#!") and re.search(rb"\b(?:ba)?sh\b", first):
            return "sh"
    return None


found = []
for rel in listed:
    if not rel or rel == own:
        continue
    path = os.path.join(root, rel)
    if not os.path.isfile(path) or os.path.islink(path):
        continue
    k = kind(rel, path)
    if k is None:
        continue
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        continue
    # Variables set to a path that names the folder, in this file (shell names, and in a Python file
    # Python names too); a line that is only a cd into the folder leaves the lines after it there.
    folder_vars, py_vars, in_folder = set(), set(), False
    for n, line in enumerate(lines, 1):
        text = comment.sub("", line)
        run = re.match(r"^\s*(?:-\s*)?run:\s*(.*)$", text)
        if run:
            text = run.group(1)
        flat, _ = spans(text)
        for m in assign.finditer(flat):
            if names_folder(m.group(2), folder_vars) or any(names_folder(p, folder_vars) for p in re.split(r"[\s+]", m.group(2))):
                folder_vars.add(m.group(1))
        if k == "py":
            m = py_assign.match(text)
            if m and py_names(m.group(2), py_vars):
                py_vars.add(m.group(1))
        hit = shell_hits(text, folder_vars, in_folder) or py_hits(text, py_vars)
        in_folder = cd_state(text, folder_vars, in_folder)
        if hit:
            found.append("  %s:%d: %s" % (rel, n, line.strip()[:100]))
if found:
    print("FAIL: a script writes into a path with a folder named %s:" % name)
    print("\n".join(found[:20]))
    if len(found) > 20:
        print("  (and %d more)" % (len(found) - 20))
    sys.exit(1)
PY
else
  fail "rule 9 needs python3 and a git work tree at $ROOT"
fi

if [[ $FAIL -eq 0 ]]; then
  echo "OK: directory readiness checks passed"
  exit 0
fi
echo "validate-directory: $FAIL failing rule(s)"
exit 1
