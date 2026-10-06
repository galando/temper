#!/usr/bin/env bash
#
# install.sh — wire the Temper guardrails pack into a NATIVE git pre-commit hook.
#
# Why a native git hook? Claude Code's settings.json has NO "PreCommit" event
# (PreToolUse/PostToolUse/Stop/... only — PreCommit is an open feature request).
# A settings.json block therefore CANNOT deterministically block `git commit`.
# The only deterministic commit gate — one that fires on a raw `git commit`
# regardless of whether the agent is involved — is a real git hook. This
# installer installs one into the repository's git hooks folder.
#
# The scripts themselves remain usable from both worlds:
#   - PreToolUse/PostToolUse blocks (settings-guardrails.json) — in-agent edits/writes
#   - native git pre-commit (this installer)      — the real commit gate
#
# Where it writes. The installer works on the repository that holds the current folder
# (it clears every GIT_* variable first, so GIT_DIR, GIT_WORK_TREE, GIT_CONFIG and the
# rest cannot move it), changes into its top folder and writes only to:
#   - by default .git/hooks/pre-commit;
#   - in a linked worktree or a submodule (where .git is a file), the hooks folder git
#     names for it (git rev-parse --git-path hooks), and only when that folder is the
#     hooks folder of the repository's own git folder (git rev-parse --git-common-dir)
#     and that git folder is not inside the plugin's folder. When that folder already
#     holds the current Temper hook, the installer says so and writes nothing;
#   - with --global (run in the main checkout), .git/temper-git-hooks/pre-commit, and it
#     sets core.hooksPath to the absolute path of that folder in the repository's own
#     config, so every linked worktree of the repository uses the same hook. --global
#     refuses when core.hooksPath is already set to another folder (replacing it would
#     switch the hooks in that folder off; the default mode installs into it instead), and
#     when .git/hooks/pre-commit holds a hook that is not Temper's (git skips .git/hooks
#     once core.hooksPath is set, so that hook would stop running);
#   - when core.hooksPath is already set (husky, lefthook, the pre-commit framework),
#     <that folder>/pre-commit, because git ignores .git/hooks then. The folder is
#     accepted when it lies inside the repository (a relative path, or an absolute one
#     inside the repository, which is turned relative) or inside the repository's own git
#     folder (the absolute folder --global sets), has no '..', and holds no JSON file (a
#     git hooks folder never does). For any other value the installer prints the lines to
#     add to your hook by hand and exits 1.
#
# It never writes over a pre-commit hook that is not Temper's, and never writes a file git
# tracks (husky v5 to v8 keep .husky/pre-commit in git, and so do teams with a .githooks
# folder). It then prints a FAIL line, the hook lines to add to your own hook between a
# BEGIN and an END line, and a one-line hint, and exits 1. The hook lines are plain sh, so
# they can run at the end of an sh hook such as husky's. A hook of your own that already
# holds the current lines is left as it is. An older Temper hook is replaced.
#
# Before it creates or writes anything, the installer follows every symlink in each path
# it will write and checks where that path really lands. A place in the repository's own
# git folder is accepted. A place equal to or inside the plugin's own folder is refused.
# Any other place outside the repository is refused. A repository that lies inside the
# plugin's folder is refused outright, and so is a run from a folder inside the plugin's
# folder when the repository's top is not the plugin's folder (an installed copy has no
# .git). Inside or equal is decided by folder identity (device and inode), not by how a
# path is spelled, so letter case and symlinks cannot hide the plugin's folder. So nothing
# is written into the plugin's folder, except into the .git folder of a checkout of the
# plugin itself (developing Temper on its own repository).
#
# The hook file is never written in place: the new hook is written to a new file in the
# hooks folder and then moved over pre-commit, so a pre-commit that is a symlink or a hard
# link to another file leaves that file as it was.
#
# Every refusal prints a FAIL line and the hook lines; none ends on a bare shell error.
#
# DEGRADATION CONTRACT: if the scripts are missing, or python3 is missing, the installed
# git hook skips the checks that need them (exit 0). Installing this never blocks a
# commit by itself.
#
# Usage:  bash scripts/guards/install.sh         # install into .git/hooks
#         bash scripts/guards/install.sh --global # install via core.hooksPath
set -euo pipefail

# cd prints the folder it changes to when CDPATH is set, which would spoil every folder this
# script works out with cd and pwd.
unset CDPATH

# Git reads GIT_* variables to reach another repository or config file (GIT_DIR,
# GIT_WORK_TREE, GIT_COMMON_DIR, GIT_CONFIG, GIT_CONFIG_PARAMETERS and more). The installer
# works on the repository that holds the current folder only, so every one of them is cleared.
while IFS= read -r _git_var; do
  unset "$_git_var" 2>/dev/null || true
done < <(compgen -e | grep '^GIT_' || true)
unset _git_var

# This script's own file, with every symlink followed (a link in a bin folder, or a chain of
# links), the same way the temper CLI finds itself; never an environment variable. The
# plugin folder is that file's folder, with every symlink followed, and the literal suffix
# /scripts/guards removed. The hook gets each path it runs written out in full, as literal
# text, at install time.
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
unset _self _hops _link_dir
PLUGIN_ROOT="${GUARD_SCRIPTS%/scripts/guards}"
TEMPER_CLI="$PLUGIN_ROOT/scripts/temper"
SECRETS_SCRIPT="$PLUGIN_ROOT/scripts/guards/block-secrets.sh"
TESTS_RAN_SCRIPT="$PLUGIN_ROOT/scripts/guards/verify-tests-ran.sh"
Q_TEMPER_CLI="$(printf '%q' "$TEMPER_CLI")"
Q_SECRETS_SCRIPT="$(printf '%q' "$SECRETS_SCRIPT")"
Q_TESTS_RAN_SCRIPT="$(printf '%q' "$TESTS_RAN_SCRIPT")"

MODE="local"
[[ "${1:-}" == "--global" ]] && MODE="global"

# The hook itself. Fail-open by design: a missing script => skipped; a detected secret or a
# red commit gate => exit 1 (block). The paths are literal text in the hook: no environment
# variable moves them, and the hook works none of them out at commit time. The lines are
# plain sh (no bash-only syntax), and safe under sh -e, so they also work when added at the
# end of an sh hook of your own (husky runs its hooks with sh -e).
_hook_body() {
  cat <<HOOK
#!/usr/bin/env bash
# Temper native pre-commit hook (installed by scripts/guards/install.sh).
# Fail-open: a missing script or a missing python3 never blocks. Only a detected violation blocks.
# The paths below were written in full at install time. A plugin upgrade moves them;
# re-run the installer then (it reports a stale path and writes the current one).
# These lines are plain sh as well, so they can also run at the end of a hook of your own.
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
# is part of the plugin: the CLI refuses to run there, so the gate is skipped. Each folder
# above the repository is compared with the plugin folder by identity (device and inode).
PLUGIN_DIR="\${TEMPER_CLI%/scripts/temper}"
REPO_DIR="\$(pwd -P)"
if [ -d "\$PLUGIN_DIR" ] && ! [ "\$REPO_DIR" -ef "\$PLUGIN_DIR" ]; then
  UP_DIR="\$REPO_DIR"
  while :; do
    case "\$UP_DIR" in /?*) ;; *) break ;; esac
    UP_DIR="\${UP_DIR%/*}"
    if [ "\${UP_DIR:-/}" -ef "\$PLUGIN_DIR" ]; then exit 0; fi
  done
fi
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

_print_lines() { # prints the hook lines between a BEGIN and an END line, on stderr
  echo "----- BEGIN Temper pre-commit hook lines -----" >&2
  _hook_body >&2
  echo "----- END Temper pre-commit hook lines -----" >&2
}

_refuse() { # _refuse <reason> [hint] -> prints the reason, the hook to add by hand and a
            # one-line hint, and exits 1
  echo "FAIL: $1" >&2
  echo "Nothing was written. To use the Temper commit gate, run the lines between the BEGIN" >&2
  echo "and END lines below from your pre-commit hook." >&2
  _print_lines
  echo "${2:-Hint: add the lines at the end of your own pre-commit hook, or point core.hooksPath at a folder inside this repository and run this installer again.}" >&2
  exit 1
}

# The plugin folder must be found, and its CLI must run: otherwise a hook written now
# would skip every check without a word.
if [[ $_self_is_link -eq 1 ]]; then
  _refuse "this installer is reached through too many symlinks (a loop?)."
fi
if [[ -z "$GUARD_SCRIPTS" || -z "$PLUGIN_ROOT" || "$PLUGIN_ROOT" == "$GUARD_SCRIPTS" ]]; then
  _refuse "this installer is not in a plugin's scripts/guards folder (${GUARD_SCRIPTS:-unknown}), so the hook would run nothing."
fi
if [[ ! -f "$TEMPER_CLI" || ! -x "$TEMPER_CLI" ]]; then
  _refuse "the temper CLI next to this installer ($TEMPER_CLI) is missing or not executable, so the hook would check nothing."
fi
# The plugin folder with every symlink followed, for the write checks below.
PLUGIN_REAL="$(cd -P "$PLUGIN_ROOT" 2>/dev/null && pwd)" || _refuse "the plugin folder ($PLUGIN_ROOT) could not be read."

_same_or_inside() { # _same_or_inside <absolute path> <folder>: 0 when the path, or a folder
                    # above it, is that folder. Compared by identity (device and inode), so
                    # letter case and symlinks cannot hide it.
  local p="$1"
  while :; do
    [[ -e "$p" && "$p" -ef "$2" ]] && return 0
    [[ "$p" == /?* ]] || return 1
    p="${p%/*}"
    p="${p:-/}"
  done
}

# Resolve the TARGET repo (where to install the git hook). This is the current
# working directory's git toplevel, NOT the repo that ships these scripts: a user runs
# this installer by its full path from their own project.
START_REAL="$(pwd -P)"
TARGET_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$TARGET_ROOT" ]]; then
  _refuse "not inside a git repository (the current folder is not in a work tree)." \
    "Hint: run this installer from the project where you want the pre-commit hook installed."
fi
cd "$TARGET_ROOT" 2>/dev/null || _refuse "the repository's top folder ($TARGET_ROOT) could not be entered."
REPO_REAL="$(pwd -P)"

# The plugin's own folder is a project only when it is the top of this git work tree
# (developing Temper on its own repository). A repository inside it gets nothing: every
# place in it is part of the plugin. Neither does a run from a folder inside it when the
# repository's top is somewhere else (an installed copy of the plugin has no .git).
if ! [[ "$REPO_REAL" -ef "$PLUGIN_REAL" ]]; then
  if _same_or_inside "$REPO_REAL" "$PLUGIN_REAL"; then
    _refuse "this repository lies inside the plugin's own folder ($PLUGIN_REAL)."
  fi
  if _same_or_inside "$START_REAL" "$PLUGIN_REAL"; then
    _refuse "the current folder lies inside the plugin's own folder ($PLUGIN_REAL), which is not the top of this repository. Run this installer from your project's folder."
  fi
fi

# The repository's own git folder, where every write is accepted: its .git folder when that
# is a real folder (a linked worktree or a submodule sets it further down).
GIT_OWN=""
if [[ -d .git && ! -L .git ]]; then
  GIT_OWN="$REPO_REAL/.git"
fi

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

_check_target() { # _check_target <path, relative to the repository top or absolute>: returns
                  # when that path, with every symlink followed, lands in a place this installer
                  # may write, and refuses (exit 1) otherwise
  local real
  real="$(_real_path "$1")" || _refuse "the path '$1' could not be resolved (a symlink loop?)."
  if [[ -n "$GIT_OWN" ]] && _same_or_inside "$real" "$GIT_OWN"; then
    return 0
  fi
  if _same_or_inside "$real" "$PLUGIN_REAL"; then
    _refuse "'$1' leads into the plugin's own folder ($real)."
  fi
  if ! _same_or_inside "$real" "$REPO_REAL"; then
    _refuse "'$1' leads outside this repository ($real)."
  fi
}

_common_git() { # sets COMMON_REAL: the repository's own git folder (git rev-parse
                # --git-common-dir) with every symlink followed. A git folder inside the
                # plugin's folder is refused, unless it is this checkout's own .git folder
                # (developing Temper on its own repository).
  local common
  common="$(git rev-parse --git-common-dir 2>/dev/null || true)"
  [[ -n "$common" ]] || _refuse "git did not say where this repository's git folder is."
  [[ "${common:0:1}" == "/" ]] || common="$REPO_REAL/$common"
  COMMON_REAL="$(cd -P "$common" 2>/dev/null && pwd)" || _refuse "the repository's git folder ($common) could not be read."
  if _same_or_inside "$COMMON_REAL" "$PLUGIN_REAL" && ! [[ -n "$GIT_OWN" && "$COMMON_REAL" -ef "$GIT_OWN" ]]; then
    _refuse "this checkout's repository keeps its git folder inside the plugin's own folder ($COMMON_REAL)."
  fi
}

# A Temper hook carries "# Temper native pre-commit hook" as its second line; every version
# does, including the installs made when the scripts lived under the old scripts folder name.
TEMPER_HOOK_LINE="Temper native pre-commit hook"
_is_temper_hook() { # _is_temper_hook <file>
  [[ -f "$1" && "$(sed -n 2p "$1" 2>/dev/null)" == "# $TEMPER_HOOK_LINE"* ]]
}
_is_current_hook() { # _is_current_hook <file>: the file is exactly the hook this installer writes now
  _is_temper_hook "$1" && [[ "$(cat "$1" 2>/dev/null)" == "$(_hook_body)" ]]
}
_holds_current_lines() { # _holds_current_lines <file>: the file runs the current hook lines
  [[ -f "$1" ]] && grep -qxF "TEMPER_CLI=$Q_TEMPER_CLI" "$1" 2>/dev/null
}

_hint() { # _hint <hook file>: the one-line hint for adding the hook lines by hand
  case "$HOOKS_FOLDER" in
    .husky|.husky/*)
      echo "Hint: husky runs .husky/pre-commit with sh, so add the lines at the end of that file (they are plain sh)."
      return ;;
  esac
  if grep -q 'File generated by pre-commit' "$1" 2>/dev/null; then
    echo "Hint: the pre-commit framework owns this hook, so save the lines as a script and run it from a local hook in .pre-commit-config.yaml (repo: local, language: system, pass_filenames: false, always_run: true)."
  else
    echo "Hint: add the lines at the end of your own pre-commit hook ($1)."
  fi
}

# Pick the hooks folder: relative to the repository root, or (linked worktree, submodule,
# a core.hooksPath in the repository's git folder) an absolute folder in the repository's
# own git folder.
HOOKS_FOLDER=""
EXISTING_HOOKS_PATH="$(git config --get core.hooksPath 2>/dev/null || true)"
GLOBAL_DIR=""
if [[ "$MODE" == "global" ]]; then
  [[ -d .git ]] || _refuse "this checkout's .git is not a folder (a linked worktree or a submodule). --global works in the main checkout." \
    "Hint: run this installer with --global in the main checkout, or without --global here."
  GLOBAL_DIR="$REPO_REAL/.git/temper-git-hooks"
  # Another value is a hooks folder in use (husky, lefthook): replacing it would switch its
  # hooks off. The default mode installs into that folder instead. Its own earlier value
  # (the relative one an earlier version wrote, or the absolute one) is fine.
  case "$EXISTING_HOOKS_PATH" in
    ""|.git/temper-git-hooks|"$GLOBAL_DIR") ;;
    *) _refuse "core.hooksPath is already set to '$EXISTING_HOOKS_PATH'. --global would replace it and switch the hooks in that folder off." \
         "Hint: run this installer without --global: it installs into that folder." ;;
  esac
  # Git skips .git/hooks once core.hooksPath is set, so a hook of the user's there would stop.
  if [[ -e .git/hooks/pre-commit ]] && ! _is_temper_hook .git/hooks/pre-commit; then
    _refuse ".git/hooks/pre-commit holds a pre-commit hook that is not Temper's. --global sets core.hooksPath, and git then skips .git/hooks, so that hook would stop running." \
      "$(_hint .git/hooks/pre-commit)"
  fi
  HOOKS_FOLDER=".git/temper-git-hooks"
  _check_target .git/config
elif [[ -n "$EXISTING_HOOKS_PATH" ]]; then
  # Respect an EXISTING core.hooksPath (husky, lefthook, the pre-commit framework all set
  # it): git ignores .git/hooks/ entirely when core.hooksPath is set, so a hook written
  # there would be inert and never block a commit.
  rel="$EXISTING_HOOKS_PATH"
  if [[ "${rel:0:1}" == "/" ]]; then
    # An absolute path is accepted inside the repository's own git folder (the folder
    # --global sets, which every worktree shares), as it is written; or inside this
    # repository, and then made relative.
    while [[ "${#rel}" -gt 1 && "${rel: -1}" == "/" ]]; do rel="${rel%/}"; done
    _common_git
    if HP_REAL="$(_real_path "$rel")" && _same_or_inside "$HP_REAL" "$COMMON_REAL"; then
      [[ "$rel" =~ [.][.] ]] && _refuse "core.hooksPath is set to '$EXISTING_HOOKS_PATH'; this installer writes only to a folder whose path has no '..'."
      GIT_OWN="$COMMON_REAL"
      HOOKS_FOLDER="$rel"
    else
      [[ "${rel#"$TARGET_ROOT"/}" != "$rel" ]] || _refuse "core.hooksPath is set to '$EXISTING_HOOKS_PATH', which is outside this repository and its git folder." \
        "Hint: add the lines at the end of the pre-commit hook in that folder yourself, or point core.hooksPath at a folder inside this repository and run this installer again."
      rel="${rel#"$TARGET_ROOT"/}"
    fi
  fi
  if [[ -z "$HOOKS_FOLDER" ]]; then
    while [[ "${rel:0:2}" == "./" ]]; do rel="${rel:2}"; done
    while [[ -n "$rel" && "${rel: -1}" == "/" ]]; do rel="${rel%/}"; done
    if ! [[ "$rel" =~ ^[A-Za-z0-9._][A-Za-z0-9._/-]*$ ]] || [[ "$rel" =~ [.][.] ]]; then
      _refuse "core.hooksPath is set to '$EXISTING_HOOKS_PATH'; this installer writes only to a folder inside this repository whose path has no '..', no '~' and no unusual characters."
    fi
    # Git takes a relative core.hooksPath from the top of each checkout. In a linked worktree
    # or a submodule .git is a file there, so a path through it names a folder that cannot
    # exist, and git runs no pre-commit hook in this checkout.
    if [[ ! -d .git ]] && [[ "$rel" == .git || "$rel" == .git/* ]]; then
      _refuse "core.hooksPath is set to the relative path '$EXISTING_HOOKS_PATH'. In this checkout .git is a file (a linked worktree or a submodule), so that folder cannot exist and git runs no pre-commit hook here." \
        "Hint: run this installer with --global in the main checkout: it sets core.hooksPath to an absolute folder that every worktree uses."
    fi
    HOOKS_FOLDER="$rel"
  fi
  echo "Note: core.hooksPath is set ($EXISTING_HOOKS_PATH), so the hook goes there, not into .git/hooks (which git would ignore)." >&2
elif [[ -d .git ]]; then
  HOOKS_FOLDER=".git/hooks"
else
  # A linked worktree or a submodule: .git is a file, and git keeps the hooks in the
  # repository's own git folder. Ask git where they go.
  HOOKS_GIT="$(git rev-parse --git-path hooks 2>/dev/null || true)"
  [[ -n "$HOOKS_GIT" ]] || _refuse "git did not say where this checkout's hooks go."
  [[ "${HOOKS_GIT:0:1}" == "/" ]] || HOOKS_GIT="$REPO_REAL/$HOOKS_GIT"
  _common_git
  if [[ "${HOOKS_GIT##*/}" != "hooks" ]] || ! [[ "${HOOKS_GIT%/*}" -ef "$COMMON_REAL" ]]; then
    _refuse "git's hooks folder for this checkout ($HOOKS_GIT) is not the hooks folder of the repository's own git folder ($COMMON_REAL)."
  fi
  GIT_OWN="$COMMON_REAL"
  HOOKS_FOLDER="$COMMON_REAL/hooks"
fi
PRECOMMIT="$HOOKS_FOLDER/pre-commit"

# A linked worktree or a submodule shares the repository's hooks: when they already hold the
# current hook, there is nothing to do.
if [[ ! -d .git && "${HOOKS_FOLDER:0:1}" == "/" ]] && _is_current_hook "$PRECOMMIT"; then
  echo "The Temper pre-commit hook is already installed for this worktree: $PRECOMMIT"
  echo "(git runs the repository's hooks in every worktree of it, so nothing was written)."
  exit 0
fi

# Where the folder really lands, checked before anything is created. (The hook file itself
# is never written in place: the new hook is moved over it, below.)
_check_target "$HOOKS_FOLDER"
mkdir -p "$HOOKS_FOLDER" 2>/dev/null || _refuse "the hooks folder '$HOOKS_FOLDER' could not be created."

# A git hooks folder holds hook scripts, never a JSON file. One that does may be a plugin's
# own hooks folder reached through a symlink or a core.hooksPath; refuse to write there.
while IFS= read -r -d '' entry; do
  if [[ "${entry%.json}" != "$entry" ]]; then
    _refuse "the hooks folder '$HOOKS_FOLDER' holds a JSON file, so it is not a plain git hooks folder."
  fi
done < <(find "$HOOKS_FOLDER/" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)

# Is the hook file one git tracks? Asked for the path as written and for its real place in
# the repository (the folder with every symlink followed), so a link cannot hide it.
TRACKED=0
if git --literal-pathspecs ls-files --error-unmatch -- "$PRECOMMIT" >/dev/null 2>&1; then
  TRACKED=1
elif PRECOMMIT_REAL="$(_real_path "$HOOKS_FOLDER")/pre-commit" \
     && [[ "${PRECOMMIT_REAL#"$REPO_REAL"/}" != "$PRECOMMIT_REAL" ]] \
     && git --literal-pathspecs ls-files --error-unmatch -- "${PRECOMMIT_REAL#"$REPO_REAL"/}" >/dev/null 2>&1; then
  TRACKED=1
fi

# husky v9 runs .husky/pre-commit from its own generated hook: lines added there count too.
LINES_FILE="$PRECOMMIT"
[[ "$HOOKS_FOLDER" == ".husky/_" ]] && LINES_FILE=".husky/pre-commit"

# Never write over a hook that is not Temper's, or over a file git tracks: print the lines
# instead. A Temper hook (from any earlier version) is replaced, below.
if [[ $TRACKED -eq 1 ]]; then
  if _is_current_hook "$PRECOMMIT" || _holds_current_lines "$PRECOMMIT"; then
    echo "The pre-commit hook $PRECOMMIT already runs the current Temper hook lines, so nothing was written."
    exit 0
  fi
  _refuse "$PRECOMMIT is tracked by git. This installer never writes a tracked file: a hook written there would carry this machine's paths into every clone." \
    "$(_hint "$PRECOMMIT")"
fi
if [[ -e "$PRECOMMIT" ]] && ! _is_temper_hook "$PRECOMMIT"; then
  if _holds_current_lines "$PRECOMMIT" || _holds_current_lines "$LINES_FILE"; then
    echo "The pre-commit hook $LINES_FILE already runs the current Temper hook lines, so nothing was written."
    exit 0
  fi
  REASON="$PRECOMMIT holds a pre-commit hook that is not Temper's, and this installer never writes over one."
  if grep -q '^TEMPER_CLI=' "$LINES_FILE" 2>/dev/null; then
    REASON="$REASON $LINES_FILE holds Temper hook lines with another plugin path: replace them with the lines below."
  fi
  _refuse "$REASON" "$(_hint "$PRECOMMIT")"
fi
if [[ "$HOOKS_FOLDER" == ".husky/_" ]] && _holds_current_lines "$LINES_FILE"; then
  echo "The pre-commit hook $LINES_FILE already runs the current Temper hook lines, so nothing was written."
  exit 0
fi

# Stale-path detection: a Temper hook carries the plugin paths embedded at ITS install
# time. A plugin upgrade moves that directory, and when the old folder is gone the hook's
# checks fail open SILENTLY. Report the mismatch; the hook written below always carries
# the CURRENT paths, so re-running this installer is the repair.
OLD_BACKUP_WARNINGS=""
if _is_temper_hook "$PRECOMMIT"; then
  EMBEDDED_PATH="$(sed -n 's/^TEMPER_CLI=//p' "$PRECOMMIT" 2>/dev/null | head -1 || true)"
  if [[ -z "$EMBEDDED_PATH" ]]; then
    # An install from before 9.6.5 embedded the scripts folder instead of each path.
    EMBEDDED_PATH="$(sed -n 's/^TEMPER_HOOKS_DIR="\${TEMPER_HOOKS_DIR:-\(.*\)}"$/\1/p' "$PRECOMMIT" 2>/dev/null | head -1 || true)"
  fi
  if [[ -n "$EMBEDDED_PATH" && "$EMBEDDED_PATH" != "$Q_TEMPER_CLI" ]]; then
    echo "Warning: installed pre-commit hook points at a stale plugin path:" >&2
    echo "  embedded: $EMBEDDED_PATH" >&2
    echo "  current:  $TEMPER_CLI" >&2
    # The %q form of a plain path only adds backslashes; without them it is the path.
    if [[ ! -e "${EMBEDDED_PATH//\\/}" ]]; then
      echo "  (That path does not exist, so the hook has been failing open: its gate checks did nothing.)" >&2
    fi
    echo "  Re-embedding the current path now." >&2
  fi
  # An older installer copied a hook that was not Temper's to pre-commit.bak.<timestamp> and
  # did not run it. Name each such copy and how to bring it back.
  for f in "$PRECOMMIT".bak.*; do
    if [[ -f "$f" ]] && ! _is_temper_hook "$f"; then
      OLD_BACKUP_WARNINGS="${OLD_BACKUP_WARNINGS}Warning: $f is a pre-commit hook that an older Temper installer set aside, and git does not run it.
"
    fi
  done
fi

# The new file is made in the hooks folder and moved into place, so no existing file is ever
# written through. Whatever is left of it on an early exit is removed.
TMP_HOOK=""
trap '[[ -z "$TMP_HOOK" ]] || rm -f "$TMP_HOOK"' EXIT
TMP_HOOK="$(mktemp "$HOOKS_FOLDER/.pre-commit.temper.XXXXXX" 2>/dev/null)" || _refuse "a new file could not be made in the hooks folder '$HOOKS_FOLDER'."
_hook_body > "$TMP_HOOK" || _refuse "the new hook could not be written in '$HOOKS_FOLDER'."
printf -v HOOK_MODE '%o' $(( 0777 & ~$(umask) ))
chmod "$HOOK_MODE" "$TMP_HOOK" 2>/dev/null || _refuse "the new hook in '$HOOKS_FOLDER' could not be made executable."
mv -f "$TMP_HOOK" "$PRECOMMIT" 2>/dev/null || _refuse "the new hook could not be moved to $PRECOMMIT."
TMP_HOOK=""

if [[ "$MODE" == "global" ]]; then
  git config --local core.hooksPath "$GLOBAL_DIR" 2>/dev/null \
    || _refuse "core.hooksPath could not be set to $GLOBAL_DIR, so git would not run the hook written there."
fi

# husky (v9) writes its generated hooks folder again whenever it sets its hooks up.
if [[ "${HOOKS_FOLDER##*/}" == "_" && -f "$HOOKS_FOLDER/h" ]]; then
  echo "Note: husky writes $HOOKS_FOLDER again when it sets up its hooks (for example on npm install); run this installer again after that." >&2
fi
# A new hook in a folder of the work tree that git does not ignore could be committed by
# mistake, with this machine's paths in it.
if [[ "${HOOKS_FOLDER:0:1}" != "/" && "$HOOKS_FOLDER" != .git && "$HOOKS_FOLDER" != .git/* ]] \
   && ! git check-ignore -q -- "$PRECOMMIT" 2>/dev/null; then
  echo "Note: git does not ignore $PRECOMMIT. Do not commit it: it holds this machine's paths." >&2
fi

if [[ -n "$OLD_BACKUP_WARNINGS" ]]; then
  printf '%s' "$OLD_BACKUP_WARNINGS" >&2
  echo "  To run it again, add the lines between the BEGIN and END lines below at its end, then move it back to $PRECOMMIT." >&2
  _print_lines
fi

if [[ "$MODE" == "global" ]]; then
  echo "Installed Temper pre-commit hook via core.hooksPath -> $GLOBAL_DIR (an absolute path, so every linked worktree of this repository uses it)"
elif [[ "${HOOKS_FOLDER:0:1}" == "/" ]]; then
  echo "Installed Temper pre-commit hook -> $PRECOMMIT (the repository's hooks folder, which git uses in every worktree)"
else
  echo "Installed Temper pre-commit hook -> $TARGET_ROOT/$PRECOMMIT"
fi
echo "To uninstall: delete $PRECOMMIT in this repository (and unset core.hooksPath if --global was used)."
