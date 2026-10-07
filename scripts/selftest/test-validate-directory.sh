#!/usr/bin/env bash
# Tests for scripts/validate-directory.sh: a good fixture passes, and one fixture per rule fails.
# Every fixture is a git work tree under one mktemp folder outside this clone, with a copy of the
# script in its scripts folder; the copy checks the fixture it sits in. The test writes and deletes
# only inside that folder.
set -uo pipefail
# With CDPATH set, cd prints the folder it enters, and the path below would hold it twice.
unset CDPATH
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${HERE%/scripts/selftest}"
[[ "$ROOT" != "$HERE" ]] || { echo "FAIL: cannot find the plugin folder from $HERE"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FAIL: git is required (validate-directory.sh lists files with git ls-files)"; exit 1; }
PASS=0; FAIL=0

# The one folder this test writes in: an absolute path with no '..', not this clone, not inside
# it, and not a folder that holds it.
FIXTURES="$(mktemp -d)" || { echo "FAIL: mktemp -d failed"; exit 1; }
if [[ ! -d "$FIXTURES" || "${FIXTURES#/}" == "$FIXTURES" || "$FIXTURES" != "${FIXTURES//../}" \
      || "$FIXTURES" == "$ROOT" || "${FIXTURES#"$ROOT"/}" != "$FIXTURES" || "${ROOT#"$FIXTURES"/}" != "$ROOT" ]]; then
  echo "FAIL: unsafe fixture folder '$FIXTURES'"; exit 1
fi
trap 'rm -rf "$FIXTURES"' EXIT
# git stops looking for a repository at the fixture folder, so a fixture is its own work tree
# (or none) even when the temp folder sits inside another repository.
export GIT_CEILING_DIRECTORIES="$FIXTURES"

# The picture lines of a fixture are put together here, when the test runs, so this tracked file
# holds no image reference to a missing file and no raw picture HTML.
IMG_EXT=png
PIC="docs/assets/pic.$IMG_EXT"
LT='<'
image() { printf '%s[%s](%s)' '!' "$1" "$2"; }   # image <alt text> <path>

# make_fixture <name> [plain]: creates a folder of that name in FIXTURES that passes every rule,
# with a copy of validate-directory.sh in its scripts folder, made a git work tree unless 'plain'
# is given. The name is a plain word (letters and '_'), so the folder is always directly in
# FIXTURES.
make_fixture() {
  local name="$1" kind="${2:-}" d
  [[ "$name" =~ ^[a-z_]+$ ]] || { echo "FAIL: bad fixture name '$name'"; return 1; }
  d="$FIXTURES/$name"
  mkdir -p "$d/.claude-plugin" "$d/docs/assets" "$d/scripts"
  cp "$ROOT/scripts/validate-directory.sh" "$d/scripts/validate-directory.sh"
  cat > "$d/README.md" <<'MD'
# Demo

## Install

Run the install command.

## How it works

The order is Intent, Plan, Build, Review, Check, then Done.

```mermaid
flowchart LR
  A["one<br/>two"] --> B
```

## What the mod reads and writes

It reads files.

MD
  { image 'A picture' "$PIC"; printf '\n'; } >> "$d/README.md"
  printf 'MIT\n' > "$d/LICENSE"
  cat > "$d/.claude-plugin/plugin.json" <<'JSON'
{"name":"demo","description":"A demo plugin.","version":"1.0.0","keywords":["demo"]}
JSON
  cat > "$d/.claude-plugin/marketplace.json" <<'JSON'
{"name":"demo","plugins":[{"name":"demo","source":"./","description":"A demo plugin."}]}
JSON
  [[ "$kind" == plain ]] || git init -q "$d"
}

# check <name> <expected exit> <dir> [VAR=value ...]: runs the copy of the script in <dir> from
# <dir>, by its relative path, with any extra environment given.
check() {
  local name="$1" want="$2" dir="$3" out rc
  shift 3
  out="$(cd "$dir" && env "$@" bash scripts/validate-directory.sh 2>&1 </dev/null)"; rc=$?
  if [[ $rc -eq $want ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $name (exit $rc, wanted $want): $out"; fi
}

# variant <name> <expected exit> <what to change, a function name>: a fresh fixture named after
# the function, changed by it, then checked.
variant() {
  local name="$1" want="$2" fn="$3"
  make_fixture "$fn" || { FAIL=$((FAIL+1)); return; }
  "$fn" "$FIXTURES/$fn"
  check "$name" "$want" "$FIXTURES/$fn"
}
broken() { variant "$1" 1 "$2"; }

add_html()      { printf '\n%spicture>%simg src="x.%s">%s/picture>\n' "$LT" "$LT" "$IMG_EXT" "$LT" >> "$1/README.md"; }
html_in_code()  { printf '\nUse `<br>` in code.\n' >> "$1/README.md"; }
no_install()    { sed 's/^## Install/## Setup/' "$1/README.md" > "$1/R" && mv "$1/R" "$1/README.md"; }
no_reads()      { sed 's/^## What the mod reads and writes/## Reads/' "$1/README.md" > "$1/R" && mv "$1/R" "$1/README.md"; }
no_diagram()    { sed 's/Intent, Plan, Build, Review, Check/the phases/' "$1/README.md" > "$1/R" && mv "$1/R" "$1/README.md"; }
empty_alt()     { { printf '\n'; image '' "$PIC"; printf '\n'; } >> "$1/README.md"; }
assets_code()   { printf '\nSee `%s` for it.\n' "$PIC" >> "$1/README.md"; }
assets_block()  { mkdir -p "$1/examples"; printf 'Output docs/assets/x.%s\n' "$IMG_EXT" > "$1/examples/a.tape"; }
assets_top()    { printf 'The pictures are in docs/assets.\n' > "$1/NOTES.md"; }
assets_unread() { mkdir -p "$1/vendor"; printf 'The pictures are in docs/assets.\n' > "$1/vendor/notes.md"; }
has_options()   { printf '{"name":"demo","description":"d","version":"1","keywords":["k"],"options":["a"]}\n' > "$1/.claude-plugin/plugin.json"; }
no_keywords()   { printf '{"name":"demo","description":"d","version":"1"}\n' > "$1/.claude-plugin/plugin.json"; }
wrong_market()  { printf '{"name":"x","plugins":[{"name":"other","source":"./","description":"d"}]}\n' > "$1/.claude-plugin/marketplace.json"; }
no_license()    { rm -f "$1/LICENSE"; }
license_md()    { rm -f "$1/LICENSE"; printf 'MIT\n' > "$1/LICENSE.md"; }

# Rule 9 names one folder in one line. These cases change that line in the fixture's copy to the
# name gate_dir, so the scripts they write hold no write into the real name.
seg_name() { sed 's/^WRITE_SEGMENT_NAME=.*$/WRITE_SEGMENT_NAME="gate_dir"/' "$1/scripts/validate-directory.sh" > "$1/scripts/v" \
               && mv "$1/scripts/v" "$1/scripts/validate-directory.sh"; }
seg_redirect() { seg_name "$1"; printf '#!/usr/bin/env bash\nprintf "x\\n" > "$D/.git/gate_dir/pre-commit"\n' > "$1/scripts/a.sh"; }
seg_rm()       { seg_name "$1"; printf 'set -u\ncd "$W" && rm -f .git/gate_dir/pre-commit\n' > "$1/scripts/a.sh"; }
seg_mkdir()    { seg_name "$1"; printf 'mkdir -p "$W/old/scripts/gate_dir"\n' > "$1/scripts/a.sh"; }
seg_ln()       { seg_name "$1"; printf 'ln -s "$T" .git/gate_dir\n' > "$1/scripts/a.sh"; }
seg_noext()    { seg_name "$1"; printf '#!/bin/sh\nchmod +x .git/gate_dir/pre-commit\n' > "$1/scripts/tool"; }
seg_python()   { seg_name "$1"; printf 'import os\nopen(os.path.join(d, "gate_dir", "x"), "w").write("y")\n' > "$1/scripts/a.py"; }
seg_workflow() { seg_name "$1"; mkdir -p "$1/.github/workflows"; printf 'jobs:\n  t:\n    steps:\n      - run: cp a .git/gate_dir/x\n' > "$1/.github/workflows/ci.yml"; }
seg_reads()    { seg_name "$1"
                 { printf 'ls -A .git/gate_dir\nsum="$(cksum < .git/gate_dir/pre-commit)"\n'
                   printf 'echo "install.sh never writes into .git/gate_dir"\n# rm -f .git/gate_dir/pre-commit\n'
                   printf 'mkdir -p gate_dir-old\ncp a "$W/x" # .git/gate_dir is only read\n'; } > "$1/scripts/a.sh"
                 printf 'import os\ndata = open(os.path.join(d, "gate_dir", "x")).read()\n' > "$1/scripts/a.py"; }
seg_subst()    { seg_name "$1"; printf 'cp a "$(git rev-parse --git-path gate_dir)/pre-commit"\nln -s a "$(git rev-parse --git-common-dir)/gate_dir/x"\n' > "$1/scripts/a.sh"; }
seg_sed()      { seg_name "$1"; printf "sed -i 's/exit 1/exit 0/' .git/gate_dir/pre-commit\n" > "$1/scripts/a.sh"; }
seg_fetch()    { seg_name "$1"; printf 'curl -fsS -o .git/gate_dir/pre-commit "$SOURCE"\n' > "$1/scripts/a.sh"; }
seg_tar()      { seg_name "$1"; printf 'tar -xf h.tar -C .git/gate_dir\n' > "$1/scripts/a.sh"; }
seg_cd()       { seg_name "$1"; printf 'cd .git/gate_dir && rm -f pre-commit\n' > "$1/scripts/a.sh"; }
seg_var()      { seg_name "$1"; printf 'H=.git/gate_dir/pre-commit\necho "exit 0" > "$H"\n' > "$1/scripts/a.sh"; }
seg_find()     { seg_name "$1"; printf 'find .git/gate_dir -name pre-commit -delete\n' > "$1/scripts/a.sh"; }
seg_pathlib()  { seg_name "$1"; printf 'from pathlib import Path\nPath(".git/gate_dir/pre-commit").write_text("x")\n' > "$1/scripts/a.py"; }
seg_argv()     { seg_name "$1"; printf 'import subprocess\nsubprocess.run(["cp", src, ".git/gate_dir/pre-commit"])\n' > "$1/scripts/a.py"; }
seg_system()   { seg_name "$1"; printf 'import os\nos.system("rm -f .git/gate_dir/pre-commit")\n' > "$1/scripts/a.py"; }
seg_braced()   { seg_name "$1"; printf 'cp x "${GIT_DIR}/gate_dir/pre-commit"\nln -s x "${HOOKS:-.git/gate_dir}/pre-commit"\n' > "$1/scripts/a.sh"; }
seg_spanvar()  { seg_name "$1"; printf 'D="$(git rev-parse --git-path gate_dir)"\ncp a "$D/pre-commit"\n' > "$1/scripts/a.sh"; }
seg_cdline()   { seg_name "$1"; printf 'cd .git/gate_dir\nln -sf ../../x pre-commit\n' > "$1/scripts/a.sh"; }
seg_pushd()    { seg_name "$1"; printf 'pushd .git/gate_dir\nrm -f pre-commit\npopd\n' > "$1/scripts/a.sh"; }
seg_pyvar()    { seg_name "$1"; printf 'import os\nHOOK = os.path.join(".git", "gate_dir", "pre-commit")\nopen(HOOK, "w").write("x")\n' > "$1/scripts/a.py"; }
seg_pathvar()  { seg_name "$1"; printf 'from pathlib import Path\nhook = Path(".git/gate_dir/pre-commit")\nhook.write_text("x")\n' > "$1/scripts/a.py"; }
seg_osopen()   { seg_name "$1"; printf 'import os\nfd = os.open(".git/gate_dir/pre-commit", os.O_WRONLY | os.O_CREAT)\n' > "$1/scripts/a.py"; }
seg_more_ok()  { seg_name "$1"
                 { printf "find gate_dir -name '*.ts' -exec grep -l TODO {} +\n"
                   printf 'echo "to remove it: (cd .git/gate_dir && rm -f pre-commit)"\n'
                   printf '[[ $a > gate_dir ]] && echo yes\n'
                   printf 'cd .git/gate_dir && ls\ncat .git/gate_dir/pre-commit > /tmp/copy\ncd /tmp\nrm -f x\n'; } > "$1/scripts/a.sh"
                 { printf 'import shutil, subprocess\nshutil.copy("gate_dir/x.json", out)\nshutil.copytree("gate_dir", out)\n'
                   printf 'subprocess.run(["cp", "gate_dir/x.json", out])\nentries = d.get("gate_dir", {})\n'; } > "$1/scripts/a.py"; }
# Rule 10 names one folder in one line too; these cases change it to gate_dir the same way.
named_name()   { sed 's/^NAMED_SEGMENT_NAME=.*$/NAMED_SEGMENT_NAME="gate_dir"/' "$1/scripts/validate-directory.sh" > "$1/scripts/v" \
                   && mv "$1/scripts/v" "$1/scripts/validate-directory.sh"; }
named_read()    { named_name "$1"; printf 'ls -A .git/gate_dir\n' > "$1/scripts/a.sh"; }
named_var()     { named_name "$1"; printf 'D="$COMMON/gate_dir"\n[ -d "$D" ] && echo yes\n' > "$1/scripts/a.sh"; }
named_comment() { named_name "$1"; printf '# never writes into .git/gate_dir\nexit 0\n' > "$1/scripts/a.sh"; }
named_python()  { named_name "$1"; printf 'import os\nprint(os.path.exists("gate_dir/x.json"))\n' > "$1/scripts/a.py"; }
named_ok()      { named_name "$1"; printf 'D="$(git rev-parse --git-path gate_dir)"\nmkdir -p .git/gate_dir-temper/x\necho "the gate_dir folder"\n' > "$1/scripts/a.sh"; }
seg_misc_ok()  { seg_name "$1"
                 { printf "find . -path ./gate_dir -prune -o -name '*.tmp' -delete\n"
                   printf 'cp gate_dir/gate_dir.json "$OUT/manifest.json"\n'
                   printf "sed 's|scripts/gate_dir|scripts/guards|' a > b\n"
                   printf "sed -i 's|scripts/gate_dir|scripts/guards|' notes.txt\n"
                   printf 'git rev-parse --git-path gate_dir/pre-commit\n'; } > "$1/scripts/a.sh"
                 printf 'rel = path.replace("gate_dir/", "")\nprint(Path("gate_dir/x.json").read_text())\n' > "$1/scripts/a.py"; }

# Rule 11 needs no name: a wildcard after a variable fails wherever it is.
glob_for()     { printf 'for f in "$1"/pre-commit.bak.*; do echo "$f"; done\n' > "$1/scripts/a.sh"; }
glob_cp()      { printf 'cp "$SRC"/scripts/*.sh "$OUT/"\n' > "$1/scripts/a.sh"; }
glob_subst()   { printf 'n="$(cat "$A" "$B"/x/*.sh | wc -l)"\n' > "$1/scripts/a.sh"; }
glob_bare()    { printf 'ls $DIR/*.json\n' > "$1/scripts/a.sh"; }
glob_comment() { printf '# lists "$d"/*.sh\nexit 0\n' > "$1/scripts/a.sh"; }
glob_python()  { printf 'import glob, os\nfiles = glob.glob(os.path.join(d, "x.sh"))\n' > "$1/scripts/a.py"; }
glob_pathlib() { printf 'from pathlib import Path\nfiles = sorted(Path(d).glob("x.json"))\n' > "$1/scripts/a.py"; }
glob_ok()      { { printf 'n="${f##*/}"\nd="${p%%/*}"\n[[ "$v" == */x ]] && echo a\n[[ "$p" == "$X"/* ]] && echo b\n'
                   printf 'echo "$d/*"\nfind "$d" -mindepth 1 -maxdepth 1 -print0\ncase "$n" in pre-commit.bak.*) echo c ;; esac\n'
                   printf 'echo "$((a * b))"\nrm -f ./*.tmp\n'; } > "$1/scripts/a.sh"
                 printf 'import fnmatch, os\nnames = [n for n in sorted(os.listdir(d)) if fnmatch.fnmatch(n, "x.json")]\n' > "$1/scripts/a.py"; }

make_fixture good && check "a good fixture passes" 0 "$FIXTURES/good"

# Inline code with a tag is allowed.
variant "a tag inside inline code passes" 0 html_in_code
# A Markdown link target may name the assets folder (the good fixture does).
# Only the listed folders are read: a folder outside that list is never opened.
variant "a folder outside the read list is not opened" 0 assets_unread
variant "a LICENSE.md counts as the license" 0 license_md

broken "raw HTML fails" add_html
broken "no Install heading fails" no_install
broken "no 'What the mod reads and writes' heading fails" no_reads
broken "no plain text diagram line fails" no_diagram
broken "empty image alt text fails" empty_alt
broken "assets folder in backticks fails" assets_code
broken "assets folder in a tape file fails" assets_block
broken "assets folder in a top level Markdown file fails" assets_top
broken "an options key fails" has_options
broken "missing keywords fails" no_keywords
broken "marketplace without the plugin fails" wrong_market
broken "no LICENSE fails" no_license
broken "a redirect into the named folder fails" seg_redirect
broken "rm in the named folder, after cd and &&, fails" seg_rm
broken "mkdir of a path with the named folder fails" seg_mkdir
broken "a link made at the named folder fails" seg_ln
broken "a write in a shell script with no extension fails" seg_noext
broken "a Python open for writing in the named folder fails" seg_python
broken "a workflow run step that writes there fails" seg_workflow
variant "reads, prose, comments and a longer folder name pass" 0 seg_reads
broken "a path from git rev-parse in a \$( ) span fails" seg_subst
broken "sed -i on a file in the named folder fails" seg_sed
broken "curl writing into the named folder fails" seg_fetch
broken "tar unpacking into the named folder fails" seg_tar
broken "cd into the named folder, then a write, fails" seg_cd
broken "a variable set to such a path, then written, fails" seg_var
broken "find -delete in the named folder fails" seg_find
broken "a pathlib write in the named folder fails" seg_pathlib
broken "a subprocess argument list that writes there fails" seg_argv
broken "os.system with a write there fails" seg_system
variant "a pruned find, a copy out of the folder, sed on other files and str.replace pass" 0 seg_misc_ok
broken "a \${NAME} path, or a default in one, that writes there fails" seg_braced
broken "a variable set from git rev-parse, then written, fails" seg_spanvar
broken "a cd into the folder alone on a line, then a write, fails" seg_cdline
broken "pushd into the folder, then a write, fails" seg_pushd
broken "a Python variable set to such a path, then opened for writing, fails" seg_pyvar
broken "a pathlib variable set to such a path, then written, fails" seg_pathvar
broken "os.open for writing there fails" seg_osopen
variant "find -exec grep, quoted text, a test, a cd with a read, and copies out of the folder pass" 0 seg_more_ok
broken "rule 10: a read of a path with the named folder fails" named_read
broken "rule 10: a variable path that ends in the named folder fails" named_var
broken "rule 10: a comment that names such a path fails" named_comment
broken "rule 10: a Python path with the named folder fails" named_python
variant "rule 10: a bare word, a longer folder name and prose pass" 0 named_ok
broken "rule 11: a for loop over a wildcard after a variable fails" glob_for
broken "rule 11: a cp of a wildcard after a variable fails" glob_cp
broken "rule 11: a wildcard after a variable in a quoted \$( ) span fails" glob_subst
broken "rule 11: a wildcard after an unquoted variable fails" glob_bare
broken "rule 11: a comment with such a wildcard fails" glob_comment
broken "rule 11: a Python glob.glob call fails" glob_python
broken "rule 11: a pathlib glob call fails" glob_pathlib
variant "rule 11: \${ } patterns, [[ == ]] patterns, quoted text, find, case, arithmetic and listdir pass" 0 glob_ok
make_fixture no_git plain && check "a folder that is not a git work tree fails" 1 "$FIXTURES/no_git"

# Nothing in the environment moves the checked folder: the variable older versions read to check
# another folder is ignored, both ways.
check "the old folder variable cannot point a good plugin's check at a broken one" 0 "$FIXTURES/good" \
  VALIDATE_DIRECTORY_ROOT="$FIXTURES/no_license"
check "the old folder variable cannot point a broken plugin's check at a good one" 1 "$FIXTURES/no_license" \
  VALIDATE_DIRECTORY_ROOT="$FIXTURES/good"
# The script finds its folder with CDPATH naming that folder (cd would print it otherwise).
check "a good fixture passes with CDPATH naming it" 0 "$FIXTURES/good" CDPATH="$FIXTURES/good"

# The real clone passes.
check "this clone passes" 0 "$ROOT"

echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
