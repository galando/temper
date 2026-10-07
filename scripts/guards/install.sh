#!/usr/bin/env bash
#
# install.sh: wire the Temper guardrails pack into a native git pre-commit hook.
#
# Why a native git hook? Claude Code's settings.json has no PreCommit event (it has PreToolUse,
# PostToolUse, Stop and a few more), so a settings.json block cannot block `git commit`. The only
# commit gate that fires on a raw `git commit`, whether or not the agent is involved, is a real
# git hook. This installer sets one up for the repository that holds the current folder.
#
# The scripts themselves work from both places:
#   - PreToolUse and PostToolUse blocks (settings-guardrails.json): what the agent edits and writes
#   - the native git pre-commit hook (this installer): the real commit gate
#
# Where it writes. The installer works on the repository that holds the current folder (it clears
# every GIT_* variable first, so GIT_DIR, GIT_WORK_TREE, GIT_CONFIG and the rest cannot move it).
# It never writes into a folder named hooks: not .git/hooks, not the folder that git rev-parse
# --git-path hooks names, and not a core.hooksPath folder that is not Temper's own. Its only
# writes are these, all in the repository's own git folder (the folder git rev-parse
# --git-common-dir names, with every symlink followed, which every worktree of it shares):
#   - the folder temper-gate, and the hook temper-gate/pre-commit in it (the kept hook);
#   - temper-pre-commit, only when a hook of your own holds the line Temper 9.6.5 printed, which
#     runs that file;
#   - core.hooksPath in the repository's own config (git config --local), set to the absolute path
#     of the temper-gate folder; or, when it holds a relative value of Temper's older folder that
#     must stay (it holds other hooks), set to that same folder's absolute path, so every worktree
#     reaches it.
# It reads hook files to decide what to do, and writes none of them.
#
# What it does:
#   - core.hooksPath unset: when git's default hooks folder (<git folder>/hooks) holds no hook git
#     runs, other than a pre-commit from an older Temper, core.hooksPath is set to the temper-gate
#     folder, so git runs the kept hook in every worktree. When that folder holds such a hook (git
#     skips the whole folder once core.hooksPath is set, so it would stop running), or a hook an
#     older installer set aside, core.hooksPath stays unset and you add one line to your own
#     pre-commit hook there.
#   - core.hooksPath already the temper-gate folder: the kept hook is made current.
#   - core.hooksPath a folder an older Temper set (.git/hooks-temper, .git/temper-git-hooks, or
#     the temper-gate folder of where the repository used to be): it is pointed at the temper-gate
#     folder, unless that folder holds other hooks git runs (git-lfs writes its hooks there); then
#     it stays, as for the default folder. When that folder is the temper-gate folder of another
#     repository that is still there (this one is a copy), the hint says to point core.hooksPath
#     at this repository's own folder; nothing here may change that repository's hook.
#   - core.hooksPath any other folder (husky, lefthook, a team folder): nothing is written there.
#     Its pre-commit hook (for husky's generated _ folder, .husky/pre-commit) counts as installed
#     when it holds the call line, and is executable where git runs it; otherwise you add that line
#     to it. For the pre-commit framework and lefthook, their config file at the repository's top
#     holding the line counts too. When husky's _ folder holds a pre-commit from an older Temper,
#     git runs that in place of husky's, so the installer refuses until husky writes its own again.
# A pre-commit from an older Temper that git still runs (next to other hooks, or in a folder that
# is not Temper's) stays the gate until you replace it with the call line; the refusal says so,
# with the stale plugin path it carries, if any.
# core.hooksPath holds an absolute path, so every worktree finds the folder. Moving or renaming the
# repository, or a folder above it, leaves it naming the old place, and git then runs no
# pre-commit hook until the installer (or /temper, which checks the hook) runs again.
# The call line holds no path of this machine, keeps the result your hook had before it, and runs
# the kept hook, so it works at the start or the end of your hook and is safe in a tracked file.
# A line before it that starts with the word exit or exec would stop it from running, so such a
# hook is refused with that reason.
#
# The plugin's own folder. A path is inside the plugin when it, or a folder above it, holds a real
# scripts/guards folder that is the same folder (device and inode) as this installer's own. A
# repository inside the plugin, a run from a folder inside it whose repository's top is elsewhere,
# and a repository whose git folder is inside it are refused. The one exception is the .git folder
# of a checkout of the plugin itself (developing Temper on its own repository).
#
# No file is written in place: each is written to a new file made by mktemp in its folder and
# moved over the old one, so a kept hook that is a symlink or a hard link to another file leaves
# that file as it was. The temper-gate folder must be a real folder, not a symlink, and the
# repository's config must be a file of its git folder (git writes through a symlink).
#
# Every refusal prints a FAIL line and the hook lines; none ends on a bare shell error. A refusal
# before the kept hook is written prints the whole hook instead, wrapped in a subshell so its exits
# end only that.
#
# DEGRADATION CONTRACT: if the scripts are missing, or python3 is missing, the installed git hook
# skips the checks that need them (exit 0). Installing this never blocks a commit by itself.
#
# Usage:  bash scripts/guards/install.sh
#         (--global is still accepted, and does the same.)
set -euo pipefail

# cd prints the folder it changes to when CDPATH is set, which would spoil every folder this
# script works out with cd and pwd.
unset CDPATH

# Git reads GIT_* variables to reach another repository or config file (GIT_DIR, GIT_WORK_TREE,
# GIT_COMMON_DIR, GIT_CONFIG, GIT_CONFIG_PARAMETERS and more). The installer works on the
# repository that holds the current folder only, so every one of them is cleared.
while IFS= read -r _git_var; do
  unset "$_git_var" 2>/dev/null || true
done < <(compgen -e | grep '^GIT_' || true)
unset _git_var

# This script's own file, with every symlink followed (a link in a bin folder, or a chain of
# links), the same way the temper CLI finds itself; never an environment variable. The hook gets
# each path it runs written out in full, as literal text, at install time: the CLI in the scripts
# folder above this one, and the two guard scripts next to this one.
_self="${BASH_SOURCE[0]}"
_hops=0
while [[ -L "$_self" && $_hops -lt 40 ]]; do
  _link_dir="$(cd -P "$(dirname "$_self")" 2>/dev/null && pwd)" || break
  _self="$(readlink "$_self")" || break
  [[ "$_self" == /* ]] || _self="$_link_dir/$_self"
  _hops=$((_hops + 1))
done
GUARD_SCRIPTS="$(cd -P "$(dirname "$_self")" 2>/dev/null && pwd)" || GUARD_SCRIPTS=""
_self_is_link=0
[[ -L "$_self" ]] && _self_is_link=1
# This installer's own file, by its fixed name in its own folder: the marker that tells the
# plugin's folder below.
SELF_FILE="$GUARD_SCRIPTS/install.sh"
_self_named=0
[[ -n "$GUARD_SCRIPTS" && -f "$_self" && "$SELF_FILE" -ef "$_self" ]] && _self_named=1
unset _self _hops _link_dir
SCRIPTS_FOLDER="${GUARD_SCRIPTS%/guards}"
TEMPER_CLI="$SCRIPTS_FOLDER/temper"
SECRETS_SCRIPT="$GUARD_SCRIPTS/block-secrets.sh"
TESTS_RAN_SCRIPT="$GUARD_SCRIPTS/verify-tests-ran.sh"
Q_TEMPER_CLI="$(printf '%q' "$TEMPER_CLI")"
Q_SECRETS_SCRIPT="$(printf '%q' "$SECRETS_SCRIPT")"
Q_TESTS_RAN_SCRIPT="$(printf '%q' "$TESTS_RAN_SCRIPT")"

if [[ "${1:-}" == "--global" ]]; then
  echo "Note: the default install now does what --global did." >&2
fi

# The mode of a new hook file: what the umask leaves of rwx for everyone, and always rwx for the
# owner, so git can run it.
printf -v HOOK_MODE '%o' $(( (0777 & ~$(umask)) | 0700 ))
# A new file made by mktemp and not yet moved into place; whatever is left of it on an exit is
# removed.
TMP_FILE=""
trap '[[ -z "$TMP_FILE" ]] || rm -f "$TMP_FILE"' EXIT

# The repository's own git folder with every symlink followed (set once it is known), and the kept
# hook in it once it is written there.
COMMON_REAL=""
KEPT_HOOK=""
KEPT_CHANGED=0
KEEP_ERR=""
GATE_NAME="temper-gate"
KEEP_965_NAME="temper-pre-commit"
# Lines a refusal prints after the kept text and before the hook lines.
WARNINGS=""
# The one line a hook of your own adds to run the kept hook. It holds no path of this machine. It
# ends the hook with the hook's own result when that was a failure, and blocks when the kept hook
# blocks, so it works at the start or the end of a hook, under sh -e or not.
CALL_LINE='_temper_rc=$?; [ "$_temper_rc" -eq 0 ] || exit "$_temper_rc"; _temper_hook="$(git rev-parse --git-common-dir)/temper-gate/pre-commit"; [ ! -f "$_temper_hook" ] || bash "$_temper_hook" || exit 1'
# The line Temper 9.6.5 printed: the same, running temper-pre-commit in the git folder.
CALL_LINE_965='_temper_rc=$?; [ "$_temper_rc" -eq 0 ] || exit "$_temper_rc"; _temper_hook="$(git rev-parse --git-common-dir)/temper-pre-commit"; [ ! -f "$_temper_hook" ] || bash "$_temper_hook" || exit 1'

# Git's hook names: once core.hooksPath is set, git runs none of these from its default folder.
GIT_HOOK_NAMES="applypatch-msg pre-applypatch post-applypatch pre-commit pre-merge-commit prepare-commit-msg commit-msg post-commit pre-rebase post-checkout post-merge pre-push pre-receive update proc-receive post-receive post-update reference-transaction push-to-checkout pre-auto-gc post-rewrite sendemail-validate fsmonitor-watchman post-index-change"

# The hook itself. Fail-open by design: a missing script => skipped; a detected secret or a red
# commit gate => exit 1 (block). The paths are literal text in the hook: no environment variable
# moves them, and the hook works none of them out at commit time. The lines are plain sh (no
# bash-only syntax), and safe under sh -e, so they also work wrapped in a subshell in an sh hook of
# your own (an early refusal prints them that way).
_hook_body() {
  cat <<HOOK
#!/usr/bin/env bash
# Temper native pre-commit hook (installed by scripts/guards/install.sh).
# Fail-open: a missing script or a missing python3 never blocks. Only a detected violation blocks.
# The paths below were written in full at install time. A plugin upgrade moves them;
# re-run the installer then (it reports a stale path and writes the current one).
# These lines are plain sh as well, so a hook of your own can run them in a subshell.
set -u
TEMPER_CLI=$Q_TEMPER_CLI
SECRETS_SCRIPT=$Q_SECRETS_SCRIPT
TESTS_RAN_SCRIPT=$Q_TESTS_RAN_SCRIPT

# Git hooks are not guaranteed to run with CWD at the worktree root on every
# platform/version, so pin it explicitly: 'temper gate commit' resolves .temper/ and
# .claude/temper.config relative to the current folder.
cd "\$(git rev-parse --show-toplevel)" || exit 0

# 1. Secrets in the staged files (--staged: this is a commit, not an agent's tool call).
if [ -f "\$SECRETS_SCRIPT" ]; then
  bash "\$SECRETS_SCRIPT" --staged || exit 1
fi

# 2. Every /temper gate must be green (or explicitly overridden): the commit gate itself,
# computed by the temper CLI from the evidence ledger. Absent .temper/ state (the repo
# does not use /temper for this commit, or the CLI is missing) => fail-open.
# Both checks below need python3. Without it they are skipped, so a missing tool never
# blocks a commit.
command -v python3 >/dev/null 2>&1 || exit 0
# A repository inside the plugin's own folder (a second checkout or worktree placed in it)
# is part of the plugin: the CLI refuses to run there, so the gate is skipped. Walking up
# from the repository, a folder above it is the plugin's folder when its scripts folder is
# a real folder (not a symlink) and the same folder (device and inode) as the one that
# holds this hook's CLI. A file cannot pass for a folder, and a folder cannot be hard
# linked, so a planted link to the CLI does not skip the gate. A checkout of the plugin
# itself (its own top) is a project like any other.
REPO_DIR="\$(pwd -P)"
UP_DIR="\$REPO_DIR"
while :; do
  case "\$UP_DIR" in /?*) ;; *) break ;; esac
  UP_DIR="\${UP_DIR%/*}"
  if [ ! -L "\$UP_DIR/scripts" ] && [ "\$UP_DIR/scripts" -ef "\${TEMPER_CLI%/temper}" ]; then exit 0; fi
done
# The home folder is never a project: the CLI refuses to run there, so the gate is skipped.
if [ -n "\${HOME:-}" ] && [ "\$REPO_DIR" -ef "\$HOME" ]; then exit 0; fi
if [ -x "\$TEMPER_CLI" ] && [ -d .temper ]; then
  GATE_RC=0
  "\$TEMPER_CLI" gate commit || GATE_RC=\$?
  if [ "\$GATE_RC" -eq 3 ]; then
    # Exit 3: the CLI refused the .temper folder (a symlink on a path it keeps run state
    # in). While a run is active that refusal must not open the gate.
    if [ -e .temper/build-state.json ] || [ -L .temper/build-state.json ]; then
      echo "Temper: commit blocked. A run is active and the temper CLI refused this project's .temper folder (its reason is above), so remove the symlink, then commit again." >&2
      exit 1
    fi
    echo "Temper: the commit gate was skipped because the temper CLI refused this project's .temper folder (its reason is above) and no run is active." >&2
    exit 0
  fi
  [ "\$GATE_RC" -eq 0 ] || exit 1
elif [ -f "\$TESTS_RAN_SCRIPT" ]; then
  # Fallback for a project that only installed the guardrails pack without the CLI.
  bash "\$TESTS_RAN_SCRIPT" || exit 1
fi

exit 0
HOOK
}

_print_lines() { # prints the hook lines between a BEGIN and an END line, on stderr: the call line
                  # once the hook is kept in the repository's git folder; otherwise the whole hook
                  # without its first line, in a subshell whose exits end only it
  echo "----- BEGIN Temper pre-commit hook lines -----" >&2
  if [[ -n "$KEPT_HOOK" ]]; then
    printf '%s\n' "$CALL_LINE" >&2
  else
    printf '%s\n' '_temper_rc=$?; [ "$_temper_rc" -eq 0 ] || exit "$_temper_rc"' '(' >&2
    _hook_body | sed 1d >&2
    printf '%s\n' ') || exit 1' >&2
  fi
  echo "----- END Temper pre-commit hook lines -----" >&2
}

NO_LINES=0
_refuse() { # _refuse <reason> [hint] -> prints the reason, the hook lines to add by hand and a
            # one-line hint, and exits 1. With NO_LINES set to 1 it prints no hook lines: the hint
            # says what to do instead.
  echo "FAIL: $1" >&2
  local hint
  if [[ $NO_LINES -eq 1 ]]; then
    [[ -z "$KEPT_HOOK" ]] || echo "The Temper hook is kept in $KEPT_HOOK (in the repository's git folder, never committed). Nothing else was written." >&2
    [[ -z "$WARNINGS" ]] || printf '%s' "$WARNINGS" >&2
    echo "${2:-Hint: see the reason above.}" >&2
    exit 1
  fi
  if [[ -n "$KEPT_HOOK" ]]; then
    echo "The Temper hook is kept in $KEPT_HOOK (in the repository's git folder, never committed). Nothing else was written. To use the Temper commit gate, add the line between the BEGIN and END lines below to your pre-commit hook." >&2
    hint="Hint: add the line to your own pre-commit hook, at its start or its end. It keeps your hook's own result."
  else
    echo "Nothing was written. To use the Temper commit gate, add the lines between the BEGIN and END lines below to your pre-commit hook." >&2
    hint="Hint: add the lines to your own pre-commit hook, at its start or its end. They keep your hook's own result."
  fi
  [[ -z "$WARNINGS" ]] || printf '%s' "$WARNINGS" >&2
  _print_lines
  [[ -z "${2:-}" ]] || hint="$2"
  echo "$hint" >&2
  exit 1
}

# The plugin's folder must be found, and its CLI must run: otherwise a hook written now would skip
# every check without a word.
if [[ $_self_is_link -eq 1 ]]; then
  _refuse "this installer is reached through too many symlinks (a loop?)."
fi
if [[ $_self_named -ne 1 || "$GUARD_SCRIPTS" != */scripts/guards ]]; then
  _refuse "this installer is not install.sh in a plugin's scripts/guards folder (${GUARD_SCRIPTS:-unknown}), so the hook would run nothing."
fi
if [[ ! -f "$TEMPER_CLI" || ! -x "$TEMPER_CLI" ]]; then
  _refuse "the temper CLI next to this installer ($TEMPER_CLI) is missing or not executable, so the hook would check nothing."
fi

_plugin_at() { # _plugin_at <folder>: 0 when <folder>/scripts/guards is this installer's own folder:
               # scripts and scripts/guards are real folders (not symlinks), and the same folder (by
               # device and inode, so letter case cannot hide it). A folder cannot be hard linked, so
               # a link planted above a repository cannot pass for the plugin.
  local d="${1%/}"
  [[ -d "$d/scripts/guards" && ! -L "$d/scripts" && ! -L "$d/scripts/guards" && "$d/scripts/guards" -ef "$GUARD_SCRIPTS" ]]
}
_in_plugin() { # _in_plugin <absolute path>: 0 when the path, or a folder above it, is the plugin's
               # folder by that marker
  local p="$1"
  while :; do
    _plugin_at "$p" && return 0
    [[ "$p" == /?* ]] || return 1
    p="${p%/*}"
    p="${p:-/}"
  done
}

# Resolve the TARGET repo (where to install the git hook). This is the current working
# directory's git toplevel, NOT the repo that ships these scripts: a user runs this installer by
# its full path from their own project.
START_REAL="$(pwd -P)"
TARGET_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$TARGET_ROOT" ]]; then
  _refuse "not inside a git repository (the current folder is not in a work tree)." \
    "Hint: run this installer from the project where you want the pre-commit hook installed."
fi
cd "$TARGET_ROOT" 2>/dev/null || _refuse "the repository's top folder ($TARGET_ROOT) could not be entered."
REPO_REAL="$(pwd -P)"

# The plugin's own folder is a project only when it is the top of this git work tree (developing
# Temper on its own repository). A repository inside it gets nothing: every place in it is part of
# the plugin. Neither does a run from a folder inside it when the repository's top is somewhere
# else (an installed copy of the plugin has no .git).
OWN_CHECKOUT=0
_plugin_at "$REPO_REAL" && OWN_CHECKOUT=1
if [[ $OWN_CHECKOUT -eq 0 ]]; then
  if _in_plugin "$REPO_REAL"; then
    _refuse "this repository lies inside the plugin's own folder (the folder that holds $SELF_FILE)."
  fi
  if _in_plugin "$START_REAL"; then
    _refuse "the current folder lies inside the plugin's own folder (the folder that holds $SELF_FILE), which is not the top of this repository. Run this installer from your project's folder."
  fi
fi

# The repository's own git folder, with every symlink followed: every write goes there.
_common="$(git rev-parse --git-common-dir 2>/dev/null || true)"
[[ -n "$_common" ]] || _refuse "git did not say where this repository's git folder is."
[[ "${_common:0:1}" == "/" ]] || _common="$REPO_REAL/$_common"
COMMON_REAL="$(cd -P "$_common" 2>/dev/null && pwd)" || { COMMON_REAL=""; _refuse "the repository's git folder ($_common) could not be read."; }
if _in_plugin "$COMMON_REAL" && ! [[ $OWN_CHECKOUT -eq 1 && "$COMMON_REAL" -ef "$REPO_REAL/.git" ]]; then
  _refuse "this checkout's repository keeps its git folder inside the plugin's own folder ($COMMON_REAL)."
fi
if [[ "${COMMON_REAL##*/}" == hooks ]]; then
  _refuse "the repository's git folder ($COMMON_REAL) is named hooks, and this installer never writes into a folder named hooks."
fi
GATE_DIR="$COMMON_REAL/$GATE_NAME"
GATE_HOOK="$GATE_DIR/pre-commit"
HOOKS_DIR="$COMMON_REAL/hooks"
HOST_PRE="$HOOKS_DIR/pre-commit"

_real_path() { # _real_path <path, absolute or relative to the cwd>: prints the absolute path
               # with every symlink followed; the parts that do not exist yet are kept as written
  local out rest comp link hops=0
  if [[ "${1:0:1}" == "/" ]]; then out="/"; else out="$(pwd -P)"; fi
  rest="$1"
  while [[ -n "$rest" ]]; do
    comp="${rest%%/*}"
    if [[ "$comp" == "$rest" ]]; then rest=""; else rest="${rest#*/}"; fi
    case "$comp" in
      ''|.) continue ;;
      ..) out="${out%/*}"; [[ -n "$out" ]] || out="/"; continue ;;
    esac
    if [[ -L "${out%/}/$comp" ]]; then
      hops=$((hops + 1))
      [[ $hops -le 40 ]] || return 1
      link="$(readlink "${out%/}/$comp")" || return 1
      if [[ "${link:0:1}" == "/" ]]; then out="/"; fi
      rest="$link${rest:+/$rest}"
    else
      out="${out%/}/$comp"
    fi
  done
  printf '%s\n' "$out"
}

# A Temper hook carries "# Temper native pre-commit hook" as its second line; every version does,
# including the installs made when the scripts lived under the old scripts folder name.
TEMPER_HOOK_LINE="Temper native pre-commit hook"
_is_temper_hook() { # _is_temper_hook <file>
  [[ -f "$1" && "$(sed -n 2p "$1" 2>/dev/null)" == "# $TEMPER_HOOK_LINE"* ]]
}
_is_current_hook() { # _is_current_hook <file>: the file is exactly the hook this installer writes now
  _is_temper_hook "$1" && [[ "$(cat "$1" 2>/dev/null)" == "$(_hook_body)" ]]
}

_stale_lines() { # _stale_lines <hook file>: when that Temper hook carries another CLI path than
                 # this plugin's, prints lines that say so. A plugin upgrade moves that path, and
                 # when the old folder is gone the hook's checks fail open without a word.
  local embedded
  _is_temper_hook "$1" || return 0
  embedded="$(sed -n 's/^TEMPER_CLI=//p' "$1" 2>/dev/null | head -1 || true)"
  if [[ -z "$embedded" ]]; then
    # An install from before 9.6.5 embedded the scripts folder instead of each path.
    embedded="$(sed -n 's/^TEMPER_HOOKS_DIR="\${TEMPER_HOOKS_DIR:-\(.*\)}"$/\1/p' "$1" 2>/dev/null | head -1 || true)"
  fi
  [[ -n "$embedded" && "$embedded" != "$Q_TEMPER_CLI" ]] || return 0
  echo "Warning: the Temper hook $1 points at a stale plugin path:"
  echo "  embedded: $embedded"
  echo "  current:  $TEMPER_CLI"
  # The %q form of a plain path only adds backslashes; without them it is the path.
  if [[ ! -e "${embedded//\\/}" ]]; then
    echo "  (That path does not exist, so the hook has been failing open: its gate checks did nothing.)"
  fi
}
_stale_note() { # _stale_note <hook file>: the lines of _stale_lines on stderr, before that hook is
                # written again with the current path
  local lines
  lines="$(_stale_lines "$1")"
  [[ -n "$lines" ]] || return 0
  printf '%s\n' "$lines" "  Writing the current path now." >&2
}

WROTE=0
_write_hook() { # _write_hook <folder> <file name>: writes the full hook to that file unless it
                # already is the current hook, and sets WROTE to 1 when it wrote. The new hook is
                # made by mktemp in that folder and moved over the file, so no existing file is
                # written through. Returns 1, writing nothing, when the file is a folder or the
                # write fails.
  local dest="$1/$2"
  WROTE=0
  [[ -d "$dest" ]] && return 1
  if [[ ! -L "$dest" ]] && _is_current_hook "$dest"; then
    return 0
  fi
  _stale_note "$dest"
  TMP_FILE="$(mktemp "$1/.$2.temper.XXXXXX" 2>/dev/null)" || { TMP_FILE=""; return 1; }
  if ! { _hook_body > "$TMP_FILE" && chmod "$HOOK_MODE" "$TMP_FILE" && mv -f "$TMP_FILE" "$dest"; } 2>/dev/null; then
    rm -f "$TMP_FILE"
    TMP_FILE=""
    return 1
  fi
  TMP_FILE=""
  WROTE=1
}

_keep_gate() { # writes the kept hook temper-gate/pre-commit in the repository's git folder, and
               # sets KEPT_HOOK and KEPT_CHANGED. Returns 1 with KEEP_ERR set, writing nothing
               # more, when the temper-gate folder is a symlink or not a folder, or the hook
               # cannot be written.
  if [[ -L "$GATE_DIR" ]]; then
    KEEP_ERR="$GATE_DIR is a symlink. This installer writes the hook only into a real folder there."
    return 1
  fi
  if [[ -e "$GATE_DIR" && ! -d "$GATE_DIR" ]]; then
    KEEP_ERR="$GATE_DIR is not a folder, so the hook cannot be kept in it."
    return 1
  fi
  if [[ ! -d "$GATE_DIR" ]] && ! mkdir "$GATE_DIR" 2>/dev/null; then
    KEEP_ERR="the folder $GATE_DIR could not be made."
    return 1
  fi
  if ! _write_hook "$GATE_DIR" pre-commit; then
    KEEP_ERR="the hook could not be written to $GATE_HOOK."
    return 1
  fi
  KEPT_CHANGED=$WROTE
  KEPT_HOOK="$GATE_HOOK"
}

_check_config() { # refuses unless the repository's config is a file of its git folder: git config
                  # writes through a symlink, so one that leads elsewhere would change another file
  local cfg="$COMMON_REAL/config" real
  real="$(_real_path "$cfg")" || _refuse "the repository's config ($cfg) could not be resolved (a symlink loop?)."
  if ! [[ "${real%/*}" -ef "$COMMON_REAL" ]]; then
    _refuse "the repository's config ($cfg) leads out of its git folder ($real), so this installer does not set core.hooksPath in it."
  fi
}

_set_hooks_path() { # points core.hooksPath at the temper-gate folder, in the repository's own config
  git config --local core.hooksPath "$GATE_DIR" 2>/dev/null \
    || _refuse "core.hooksPath could not be set to $GATE_DIR, so git would not run the hook kept there."
}

_uninstall_line() {
  echo "To uninstall: run 'git config --unset core.hooksPath' (when it points at the temper-gate folder), remove the Temper line from your own hook if you added one, and delete $GATE_DIR (and $COMMON_REAL/$KEEP_965_NAME, if Temper 9.6.5 left one)."
}

_installed() { # the line a run that set core.hooksPath prints
  echo "Installed Temper pre-commit hook -> $GATE_HOOK (core.hooksPath points at that folder, so every worktree of this repository runs it)."
}

_call_state() { # _call_state <hook file>: prints 'calls' when the file holds the call line, or
                # 'calls-965' when it holds the line of Temper 9.6.5, with no line before it that
                # starts (after spaces) with the word exit or exec; 'late' when such a line comes
                # first; and nothing when the file holds neither line
  [[ -f "$1" ]] || return 0
  CALL_LINE="$CALL_LINE" CALL_LINE_965="$CALL_LINE_965" awk '
    $0 == ENVIRON["CALL_LINE"] { print (stop ? "late" : "calls"); exit }
    $0 == ENVIRON["CALL_LINE_965"] { print (stop ? "late" : "calls-965"); exit }
    /^[ \t]*(exit|exec)([^A-Za-z0-9_]|$)/ { stop = 1 }
  ' "$1" 2>/dev/null || true
}

_is_call_only() { # _is_call_only <file>: the file holds a #! line and the call line and nothing else
                  # (blank lines aside), as the hint for a hook from an older Temper makes it, so git
                  # running it runs only the kept hook
  [[ -f "$1" ]] || return 1
  CALL_LINE="$CALL_LINE" awk '
    NR == 1 && /^#!/ { next }
    /^[ \t]*$/ { next }
    $0 == ENVIRON["CALL_LINE"] { n++; next }
    { bad = 1 }
    END { exit (n == 1 && !bad) ? 0 : 1 }
  ' "$1" 2>/dev/null
}

_config_has_line() { # _config_has_line <file>: 0 when a line of the file that is not a comment
                     # holds the call line (the text only: a setting there can still skip it)
  [[ -f "$1" ]] || return 1
  CALL_LINE="$CALL_LINE" awk 'index($0, ENVIRON["CALL_LINE"]) && $0 !~ /^[ \t]*#/ { f = 1 } END { exit !f }' "$1" 2>/dev/null
}

HOST_HUSKY=0
HOST_SOURCED=0
RUN_PRE=""
_hint() { # _hint <hook file>: the one-line hint for adding the call line by hand
  if _is_temper_hook "$1"; then
    echo "Hint: $1 is a hook from an older Temper. Replace all of its lines with two: #!/bin/sh and the line."
  elif [[ $HOST_HUSKY -eq 1 ]]; then
    echo "Hint: add the line to .husky/pre-commit. It holds no path of this machine, so it is safe to commit."
  elif grep -q 'File generated by pre-commit' "$1" 2>/dev/null; then
    # The framework splits a system hook's entry into words and runs it with no shell, so the
    # entry hands the line to sh. The line holds no single quote.
    echo "Hint: the pre-commit framework owns this hook. Add a local hook to .pre-commit-config.yaml (repo: local, language: system, pass_filenames: false, always_run: true) with this entry: sh -c '$CALL_LINE'"
  elif grep -qi 'lefthook' "$1" 2>/dev/null; then
    echo "Hint: lefthook writes this hook again. Add a pre-commit command to lefthook.yml that runs the line."
  else
    echo "Hint: add the line to your own pre-commit hook ($1), at its start or its end. It keeps your hook's own result. Create that file, executable, if it does not exist."
  fi
}

_host() { # _host <hook file> <reason>: git runs that hook, and the kept hook is written. When the
          # hook calls the Temper hook, says so and exits 0; otherwise refuses with the reason, the
          # call line and a hint. A hook from an older Temper that git runs there stays the gate
          # until it is replaced, so the refusal says so, with its stale path if it has one; this
          # installer does not write it.
  local stale state cfg
  state="$(_call_state "$1")"
  if [[ -z "$state" ]]; then
    # The pre-commit framework and lefthook write their own hook, and the line goes in their
    # config file at the repository's top: a config that holds it counts as calling the Temper hook.
    if grep -q 'File generated by pre-commit' "$1" 2>/dev/null && _config_has_line .pre-commit-config.yaml; then
      state="config"
      cfg=".pre-commit-config.yaml"
    elif grep -qi 'lefthook' "$1" 2>/dev/null; then
      for cfg in lefthook.yml .lefthook.yml lefthook.yaml .lefthook.yaml lefthook-local.yml; do
        _config_has_line "$cfg" && { state="config"; break; }
      done
    fi
  fi
  # Git runs a hook only when it is executable. In husky's _ folder git runs husky's own hook,
  # which runs .husky/pre-commit with sh: that hook must be there and executable instead.
  if [[ -n "$state" && "$state" != late && $HOST_SOURCED -eq 1 && ! -x "$RUN_PRE" ]]; then
    _refuse "git runs $RUN_PRE, husky's own hook, which is missing or not executable, so $1 does not run." "Hint: run npx husky (npm install runs it too, through husky's prepare script), then run this installer again."
  fi
  if [[ -n "$state" && "$state" != late && $HOST_SOURCED -ne 1 && ! -x "$1" ]]; then
    _refuse "the pre-commit hook $1 is not executable, so git does not run it, and the Temper hook with it." "Hint: run chmod +x $(printf '%q' "$1"), then run this installer again."
  fi
  case "$state" in
    calls|config)
      [[ -z "$WARNINGS" ]] || printf '%s' "$WARNINGS" >&2
      if [[ "$state" == config ]]; then
        echo "The pre-commit hook $1 runs the Temper hook ($KEPT_HOOK) through $cfg, and that hook is now current, so nothing else was written. (Only the text of $cfg was read: a stages or skip setting in it can still keep the line from running on a commit.)"
      else
        echo "The pre-commit hook $1 calls the Temper hook ($KEPT_HOOK), which is now current, so nothing else was written."
      fi
      _uninstall_line
      exit 0 ;;
    calls-965)
      if ! _write_hook "$COMMON_REAL" "$KEEP_965_NAME"; then
        _refuse "the pre-commit hook $1 calls the hook of Temper 9.6.5 ($COMMON_REAL/$KEEP_965_NAME), which could not be made current." "$(_hint "$1")"
      fi
      [[ -z "$WARNINGS" ]] || printf '%s' "$WARNINGS" >&2
      echo "The pre-commit hook $1 calls the Temper hook ($COMMON_REAL/$KEEP_965_NAME), which is now current, so nothing else was written."
      _uninstall_line
      exit 0 ;;
    late)
      _refuse "the Temper line in $1 comes after an exit or exec line, so it never runs. Move it above that line." "$(_hint "$1")" ;;
  esac
  if _is_temper_hook "$1"; then
    stale="$(_stale_lines "$1")"
    WARNINGS="${WARNINGS}Warning: $1 is a hook from an older Temper, and git runs it in place of the kept hook. This installer does not write it.
${stale:+$stale
}"
  fi
  _refuse "$2" "$(_hint "$1")"
}

_norm() { # _norm <core.hooksPath>: the value without a leading ./ and a trailing /
  local v="$1"
  while [[ "$v" == ./* ]]; do v="${v:2}"; done
  while [[ ${#v} -gt 1 && "$v" == */ ]]; do v="${v%/}"; done
  printf '%s' "$v"
}
_value_folder() { # _value_folder <core.hooksPath>: the folder git takes the value for, as written:
                  # ~ is the home folder, and a relative path starts at the repository's top (the
                  # current folder)
  local v
  v="$(_norm "$1")"
  case "$v" in
    "~") v="${HOME:-}" ;;
    "~/"*) v="${HOME:-}/${v:2}" ;;
  esac
  printf '%s' "${v:-.}"
}
_is_gate_value() { # _is_gate_value <core.hooksPath>: 0 when it names the temper-gate folder
  local p
  p="$(_value_folder "$1")"
  [[ "${p:0:1}" == "/" ]] || p="$REPO_REAL/$p"
  [[ "$p" == "$GATE_DIR" ]] && return 0
  [[ -d "$p" && -d "$GATE_DIR" && "$p" -ef "$GATE_DIR" ]]
}
_older_value() { # _older_value <core.hooksPath>: 0 when it is a value an older Temper wrote: the
                 # relative .git/hooks-temper (--global from 5.5.0 to 9.6.4) or
                 # .git/temper-git-hooks, an absolute folder ending in either (--global in 9.6.5
                 # wrote /.git/temper-git-hooks), or the temper-gate folder of where this
                 # repository used to be (an absolute folder ending in /temper-gate that is gone,
                 # or holds a Temper pre-commit)
  local v
  v="$(_norm "$1")"
  [[ "$v" == ".git/hooks-temper" || "$v" == ".git/temper-git-hooks" ]] && return 0
  [[ "${v:0:1}" == "/" ]] || return 1
  [[ "$v" == */.git/hooks-temper || "$v" == */.git/temper-git-hooks ]] && return 0
  if [[ "$v" == */"$GATE_NAME" ]]; then
    [[ -e "$v" ]] || return 0
    [[ -d "$v" ]] && { _is_temper_hook "$v/pre-commit" || _is_call_only "$v/pre-commit"; } && return 0
  fi
  return 1
}
_older_folder() { # _older_folder <older core.hooksPath>: the older folder in this repository: for a
                  # relative .git/<name>, that name in the repository's git folder; for an absolute
                  # value ending in /.git/hooks-temper or /.git/temper-git-hooks, the folder of that
                  # name in this repository's git folder when it is there (the value names another
                  # place after a move or a copy); otherwise the folder the value names
  local v
  v="$(_norm "$1")"
  if [[ "$v" == .git/* ]]; then
    printf '%s' "$COMMON_REAL/${v#.git/}"
    return 0
  fi
  case "$v" in
    */.git/hooks-temper|*/.git/temper-git-hooks)
      if [[ -d "$COMMON_REAL/${v##*/}" ]]; then
        printf '%s' "$COMMON_REAL/${v##*/}"
        return 0
      fi ;;
  esac
  printf '%s' "$v"
}
_scan() { # _scan <folder>: sets RUNNING, the hooks git runs from that folder (executable files
          # with git's hook names, other than a pre-commit from an older Temper or one that only
          # runs the kept hook), and SET_ASIDE,
          # one path per line, the pre-commit.bak.<timestamp> files an older installer made of a
          # hook of yours. Git does not run those, but moved back into the folder it would. The
          # files are only read.
  local name f
  RUNNING=""
  SET_ASIDE=""
  for name in $GIT_HOOK_NAMES; do
    [[ -f "$1/$name" && -x "$1/$name" ]] || continue
    [[ "$name" == pre-commit ]] && { _is_temper_hook "$1/$name" || _is_call_only "$1/$name"; } && continue
    RUNNING="${RUNNING:+$RUNNING }$name"
  done
  for f in "$1"/pre-commit.bak.*; do
    [[ -f "$f" ]] || continue
    case "${f##*/pre-commit.bak.}" in ''|*[!0-9]*) continue ;; esac
    _is_temper_hook "$f" && continue
    SET_ASIDE="$SET_ASIDE$f"$'\n'
  done
}
_scan_reason() { # _scan_reason <folder>: sets REASON, the FAIL reason for what _scan found there,
                 # and adds a warning for each hook an older installer set aside
  local names="" f how
  how="move it back to $1/pre-commit and add the line between the BEGIN and END lines below to it"
  if [[ " $RUNNING " == *" pre-commit "* ]]; then
    # A hook of yours is there now: moving the old one back would write over it.
    how="add its lines to $1/pre-commit, a hook git runs now (do not move it over that file), and add the line between the BEGIN and END lines below to that file"
  fi
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    names="${names:+$names }${f##*/}"
    WARNINGS="${WARNINGS}Warning: $f is a pre-commit hook that an older Temper installer set aside, and git does not run it. To run it again, $how.
"
  done <<< "$SET_ASIDE"
  if [[ -n "$RUNNING" ]]; then
    REASON="$1 holds hooks git would stop running if core.hooksPath pointed at Temper's folder: $RUNNING."
    [[ -z "$names" ]] || REASON="$REASON It also holds a hook an older Temper installer set aside ($names)."
  else
    REASON="$1 holds a hook an older Temper installer set aside ($names). Moved back, git would run it, but not once core.hooksPath pointed at Temper's folder."
  fi
}
_value_host() { # _value_host <core.hooksPath>: sets HOST, the hook of your own that git runs for
                # that folder (as written), and HOST_HUSKY. For husky's generated _ folder, that is
                # .husky/pre-commit, which husky's hook there runs.
  local folder parent
  folder="$(_value_folder "$1")"
  HOST_HUSKY=0
  if [[ "${folder##*/}" == "_" ]]; then
    if [[ "$folder" == */* ]]; then parent="${folder%/*}"; else parent="."; fi
    if [[ "${parent##*/}" == ".husky" ]]; then
      HOST="$parent/pre-commit"
      HOST_HUSKY=1
      # husky's hook in the _ folder runs that file with sh, so it needs no execute bit.
      HOST_SOURCED=1
      return 0
    fi
  fi
  [[ "${folder##*/}" == ".husky" ]] && HOST_HUSKY=1
  HOST="${folder%/}/pre-commit"
}

EXISTING_HOOKS_PATH="$(git config --get core.hooksPath 2>/dev/null || true)"

if [[ -z "$EXISTING_HOOKS_PATH" ]]; then
  # Git runs the hooks of its default folder. Setting core.hooksPath would stop every one of them,
  # so a hook there that git runs (other than a pre-commit from an older Temper) keeps it unset,
  # and so does a hook an older installer set aside as pre-commit.bak.<timestamp>.
  _scan "$HOOKS_DIR"
  if [[ -n "$RUNNING$SET_ASIDE" ]]; then
    _keep_gate || _refuse "$KEEP_ERR"
    _scan_reason "$HOOKS_DIR"
    _host "$HOST_PRE" "$REASON"
  fi
  _check_config
  _keep_gate || _refuse "$KEEP_ERR"
  _set_hooks_path
  _installed
  if _is_temper_hook "$HOST_PRE"; then
    echo "Note: git no longer runs $HOST_PRE, a hook from an older Temper; you can delete it." >&2
  elif _is_call_only "$HOST_PRE"; then
    echo "Note: git no longer runs $HOST_PRE, which only ran the kept hook; you can delete it." >&2
  fi
  _uninstall_line
  exit 0
fi

if _is_gate_value "$EXISTING_HOOKS_PATH"; then
  _keep_gate || _refuse "$KEEP_ERR"
  if [[ $KEPT_CHANGED -eq 1 ]]; then
    echo "The Temper pre-commit hook $GATE_HOOK was updated to the current plugin paths."
  else
    echo "The Temper pre-commit hook is already installed: $GATE_HOOK (core.hooksPath points at its folder)."
  fi
  _uninstall_line
  exit 0
fi

if _older_value "$EXISTING_HOOKS_PATH"; then
  # Git runs the hooks of that folder in place of its default folder. Other tools write theirs
  # there too (git lfs install writes into the folder core.hooksPath names), and pointing
  # core.hooksPath at the temper-gate folder would stop them, so a hook there that git runs
  # (other than Temper's own pre-commit) keeps the value as it is, as in the default folder.
  OLDER_DIR="$(_older_folder "$EXISTING_HOOKS_PATH")"
  _scan "$OLDER_DIR"
  if [[ -n "$RUNNING$SET_ASIDE" ]]; then
    _keep_gate || _refuse "$KEEP_ERR"
    if [[ "$OLDER_DIR" == */"$GATE_NAME" && -e "${OLDER_DIR%/*}/HEAD" ]]; then
      # The temper-gate folder of another repository, still there (this one is a copy of it): its
      # pre-commit is that repository's own kept hook, so nothing here may tell you to change it.
      NO_LINES=1
      OTHER_NAMES="$RUNNING"
      while IFS= read -r _f; do
        [[ -z "$_f" ]] || OTHER_NAMES="${OTHER_NAMES:+$OTHER_NAMES }${_f##*/}"
      done <<< "$SET_ASIDE"
      _refuse "core.hooksPath is set to '$EXISTING_HOOKS_PATH', the Temper folder of another repository (${OLDER_DIR%/*}), which also holds other hooks: $OTHER_NAMES." \
        "Hint: point core.hooksPath at this repository's own folder (git config --local core.hooksPath $(printf '%q' "$GATE_DIR")), then copy those hooks into it, or install them again with their tool (git lfs install --local writes into the folder core.hooksPath names)."
    fi
    if [[ "$(_norm "$EXISTING_HOOKS_PATH")" != "$OLDER_DIR" ]]; then
      # A relative value: git takes it from each worktree's top, where a linked worktree (or a
      # submodule) has a .git file, so it runs nothing there. An absolute value of another place:
      # the repository was moved or copied, and git runs nothing, or the other copy's hooks. The
      # folder in this repository's git folder, by its absolute path, is the one every worktree
      # here should run.
      _check_config
      git config --local core.hooksPath "$OLDER_DIR" 2>/dev/null \
        || _refuse "core.hooksPath could not be set to $OLDER_DIR, the older Temper folder of this repository."
      WARNINGS="${WARNINGS}Note: core.hooksPath held '$EXISTING_HOOKS_PATH'; it now holds $OLDER_DIR, the same older Temper folder in this repository's git folder by its absolute path, which every worktree reaches.
"
      EXISTING_HOOKS_PATH="$OLDER_DIR"
    fi
    _scan_reason "$OLDER_DIR"
    _host "$OLDER_DIR/pre-commit" "core.hooksPath is set to '$EXISTING_HOOKS_PATH', a folder an older Temper set. $REASON"
  fi
  _check_config
  _keep_gate || _refuse "$KEEP_ERR"
  _set_hooks_path
  _installed
  echo "Note: core.hooksPath held Temper's older folder ($EXISTING_HOOKS_PATH); it now points at $GATE_DIR." >&2
  _uninstall_line
  exit 0
fi

# Another folder (husky, lefthook, a team's folder): git runs its hooks, and this installer never
# writes there. Its pre-commit hook runs the kept hook through the call line.
_value_host "$EXISTING_HOOKS_PATH"
_keep_gate || _refuse "$KEEP_ERR"
RUN_PRE="$(_value_folder "$EXISTING_HOOKS_PATH")/pre-commit"
if [[ "$RUN_PRE" != "$HOST" ]] && _is_temper_hook "$RUN_PRE"; then
  # husky's _ folder: git runs its pre-commit, which an older Temper wrote over husky's own, so
  # .husky/pre-commit, and a line added to it, never runs.
  STALE="$(_stale_lines "$RUN_PRE")"
  WARNINGS="${WARNINGS}Warning: $RUN_PRE is a hook from an older Temper, and git runs it in place of husky's own hook, so $HOST does not run. This installer does not write it.
${STALE:+$STALE
}"
  _refuse "core.hooksPath is set to '$EXISTING_HOOKS_PATH', and git runs $RUN_PRE there, a hook from an older Temper in place of husky's." \
    "Hint: run npx husky, which writes husky's own hooks there again (or move the pre-commit.bak.<timestamp> file there back over it), then add the line to $HOST."
fi
_host "$HOST" "core.hooksPath is set to '$EXISTING_HOOKS_PATH', a folder that is not Temper's, and this installer never writes into it."
