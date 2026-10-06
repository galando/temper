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
#      the mod, and the directory cannot tell them apart). Comments do not count. The plugin's
#      own hooks folder, the mod's tests folder and this script are not read.
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
# Python files and workflow files. A line counts when, with its comment taken off, a write (a
# redirect, or a command or call that writes, removes, moves, links or makes a file) comes before
# a path part with that name. Only the plugin folder is read.
WRITE_SEGMENT_NAME="hooks"
if command -v python3 >/dev/null 2>&1 && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  python3 - "$ROOT" "$WRITE_SEGMENT_NAME" <<'PY' || FAIL=$((FAIL+1))
import os, re, shlex, subprocess, sys
root, name = sys.argv[1], sys.argv[2]
skip_dirs = (name + "/", "tests/mod/")
skip_files = ("scripts/validate-directory.sh",)
listed = subprocess.run(["git", "-C", root, "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                        capture_output=True, check=False).stdout.decode("utf-8", "replace").split("\0")
writers = {"rm", "rmdir", "mv", "cp", "ln", "mkdir", "chmod", "chown", "touch", "tee", "install",
           "rsync", "truncate", "unlink", "dd"}
prefixes = {"sudo", "command", "exec", "env", "xargs", "nohup", "time", "then", "do", "else", "!"}
redirect = re.compile(r"(?<![<>=-])(?:[0-9]?>>?|&>>?)\|?\s*([^\s;|&<>()]+)")
py_write = re.compile(r"\b(?:write_text|write_bytes|makedirs|mkdir|rename|replace|symlink|link|remove|unlink|"
                      r"rmdir|chmod|copy|copy2|copyfile|copytree|move|rmtree|touch)\s*\(|\bopen\s*\(")
comment = re.compile(r"(?:^|\s)#.*$")


def names_folder(word):
    """True when a word, with its quotes taken off, has a path part equal to the name."""
    word = word.strip("\"'`")
    parts = re.split(r"[/\"']", word)
    return name in parts[:-1] or (word.endswith("/" + name) or word == name)


def shell_hits(text):
    for m in redirect.finditer(text):
        if names_folder(m.group(1)):
            return True
    for part in re.split(r"\$\(|`|&&|\|\||[;|(){}]", text):
        try:
            words = shlex.split(part, posix=True)
        except ValueError:
            words = part.split()
        while words and (words[0] in prefixes or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0])):
            words = words[1:]
        if not words:
            continue
        cmd = os.path.basename(words[0])
        if cmd in writers or (cmd == "find" and ("-delete" in words or "-exec" in words)):
            if any(names_folder(w) for w in words[1:]):
                return True
    return False


def call_args(text, start):
    """The top level arguments of the call whose open paren ends just before start."""
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


def py_hits(text):
    for m in py_write.finditer(text):
        args = call_args(text, m.end())
        if not any(re.search(r"(?:^|[/\s\"'(,])" + re.escape(name) + r"(?:[/\"'\s),]|$)", a) for a in args):
            continue
        if m.group(0).startswith("open"):
            modes = [a.split("=", 1)[1].strip() for a in args if a.replace(" ", "").startswith("mode=")]
            if len(args) > 1 and "=" not in args[1]:
                modes.append(args[1])
            if not any(re.fullmatch(r"['\"][rwabxt+]*[wax+][rwabxt+]*['\"]", md) for md in modes):
                continue
        return True
    return False


def kind(rel, path):
    if rel.endswith((".sh", ".bash", ".py")):
        return True
    if rel.startswith(".github/") and rel.endswith((".yml", ".yaml")):
        return True
    if "." not in os.path.basename(rel):
        try:
            with open(path, "rb") as f:
                first = f.readline(200)
        except OSError:
            return False
        return first.startswith(b"#!") and re.search(rb"\b(?:ba)?sh\b", first) is not None
    return False


found = []
for rel in listed:
    if not rel or rel.startswith(skip_dirs) or rel in skip_files:
        continue
    path = os.path.join(root, rel)
    if not os.path.isfile(path) or os.path.islink(path) or not kind(rel, path):
        continue
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        continue
    for n, line in enumerate(lines, 1):
        text = comment.sub("", line)
        if name not in text:
            continue
        run = re.match(r"^\s*(?:-\s*)?run:\s*(.*)$", text)
        if run:
            text = run.group(1)
        if shell_hits(text) or py_hits(text):
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
