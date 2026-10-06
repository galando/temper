#!/usr/bin/env bash
#
# verify-stage-gate.sh — Stop half of the standalone-stage gate guarantee.
#
# If stage-marker.sh recorded a pending stage for this session, refuse to let the
# session end (exit 2, reason on stderr) until .temper/gates.json carries a verdict
# for that stage. Any verdict satisfies it — PASS or FAIL — because what this enforces
# is that `temper gate <stage>` was actually invoked, not that it succeeded; a FAIL
# verdict is the interactive gate's problem, not this hook's. Appends one line per
# firing to .temper/stage-gate.log so a live run leaves a checkable trace.
#
# Every file it reads or writes is a fixed name in the project's .temper folder: the hook
# changes into the project folder first. A project folder that lies inside this plugin's
# own folder is skipped (exit 0): the hook never writes inside the plugin. The plugin folder
# itself is a project only when it is a git work tree whose top level is that folder
# (developing Temper on its own repository), so an installed copy is skipped too. Inside or
# equal is decided by identity (device and inode), not by comparing path text. A .temper
# folder or a marker file that is a symlink is skipped too, and so is a log file that is a
# symlink, because writing through it would land outside the project's .temper folder.
# The hook finds the plugin folder from its own file with every symlink followed, as the CLI
# does; reached from anywhere that is not a plugin's scripts/guards folder, it does nothing.
#
# Loop guard, two layers: after MAX_BLOCKS refusals (counted in the marker itself) the
# hook fails open — a model that cannot satisfy the gate (broken CLI, read-only disk)
# must not be trapped in an infinite stop loop. Independently, if the harness reports
# stop_hook_active with the marker's counter at 0 — meaning our own count never
# persisted — fail open rather than trust a counter that isn't counting.
#
# DEGRADATION CONTRACT:
#   - No marker file                        => exit 0 (nothing owed)
#   - Verdict present for the stage         => exit 0 (marker cleared — debt paid)
#   - python3 absent / marker unreadable    => exit 0 (fail-open, marker cleared)
#   - Verdict missing, blocks < MAX_BLOCKS  => exit 2 (BLOCK: the one fail-closed path)
#   - Verdict missing, blocks >= MAX_BLOCKS => exit 0 (fail-open, marker cleared)
set -uo pipefail
# An exported CDPATH makes `cd` print the folder it enters, which would double every folder
# worked out below with "$(cd ... && pwd)". It is never used here.
unset CDPATH

MAX_BLOCKS=2

# This script's own file with every symlink followed (a link in a bin folder, or a chain of
# links), the way scripts/temper finds itself. Its folder, resolved, is HERE; the plugin folder
# is HERE with the literal suffix /scripts/guards removed. When that suffix is missing the hook
# is not in a plugin's scripts/guards folder and does nothing. Worked out once, before the hook
# changes into the project folder.
_self="${BASH_SOURCE[0]}"
_hops=0
while [[ -L "$_self" && $_hops -lt 40 ]]; do
  _link_dir="$(cd -P "$(dirname "$_self")" 2>/dev/null && pwd)" || exit 0
  _self="$(readlink "$_self")" || exit 0
  [[ "$_self" == /* ]] || _self="$_link_dir/$_self"
  _hops=$((_hops + 1))
done
HERE="$(cd -P "$(dirname "$_self")" 2>/dev/null && pwd)" || exit 0
ROOT="${HERE%/scripts/guards}"
[[ -n "$HERE" && "$ROOT" != "$HERE" ]] || exit 0
unset _self _hops _link_dir

_log() { # append-only trace in the project's .temper folder (the cwd); never fails the hook
  [[ ! -L .temper/stage-gate.log ]] || return 0
  printf '%s verify-stage-gate %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo -)" "$1" \
    >> .temper/stage-gate.log 2>/dev/null || true
}

_git_toplevel_is() { # _git_toplevel_is <folder> -> 0 when <folder> is a git work tree whose top
                      # level is <folder> itself (every GIT_* variable dropped first)
  local top
  top="$(
    while IFS= read -r v; do unset "$v"; done < <(compgen -e | grep '^GIT_')
    git -C "$1" rev-parse --show-toplevel 2>/dev/null
  )" || return 1
  [[ -n "$top" && "$top" -ef "$1" ]]
}

_under_folder() { # _under_folder <path> <folder> -> 0 when <path> is <folder> or lies inside it,
                  # decided by identity: each ancestor of the resolved path is compared with
                  # <folder> by device and inode ([[ -ef ]]), never by text, so another case on
                  # a file system that does not tell case apart, or a second mount, is seen
  local d
  d="$(cd -P "$1" 2>/dev/null && pwd)" || return 1
  while [[ -n "$d" ]]; do
    [[ "$d" -ef "$2" ]] && return 0
    [[ "$d" != "/" ]] || return 1
    d="${d%/*}"
    [[ -n "$d" ]] || d="/"
  done
  return 1
}

_project_dir() { # prints the resolved project folder; fails when it lies inside this plugin's
                 # folder, or is the plugin folder and that folder is not its own git
                 # repository (an installed copy)
  local proj
  proj="$(cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null && pwd -P)" || return 1
  if [[ "$proj" -ef "$ROOT" ]]; then
    _git_toplevel_is "$ROOT" || return 1
  elif _under_folder "$proj" "$ROOT"; then
    return 1
  fi
  printf '%s\n' "$proj"
}

_main() {
  local stdin_json=""
  stdin_json="$(cat 2>/dev/null || true)"
  local proj; proj="$(_project_dir)" || return 0
  cd "$proj" 2>/dev/null || return 0
  [[ ! -L .temper && ! -L .temper/pending-stage.json ]] || return 0
  [[ -f .temper/pending-stage.json ]] || return 0
  command -v python3 >/dev/null 2>&1 || { rm -f .temper/pending-stage.json 2>/dev/null; return 0; }

  # One python pass: read marker + gates.json + harness input, decide, update the
  # marker in place. Prints "CLEAR", "OPEN" (fail-open), or "BLOCK <stage>". The
  # program is an inline `python3 -c` string (single-quoted, so it must not contain a
  # single quote) and every input travels as argv, so the hook runs no other file.
  local decision
  decision=$(python3 -c '
import json, sys
marker_path, gates_path, max_blocks = sys.argv[1], sys.argv[2], int(sys.argv[3])
try:
    hook_input = json.loads(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[4] else {}
except Exception:
    hook_input = {}
try:
    m = json.load(open(marker_path))
    stage, blocks = m["stage"], int(m.get("blocks", 0))
    since = m.get("since", "")
except Exception:
    print("OPEN"); sys.exit(0)
try:
    g = json.load(open(gates_path)).get(stage, {})
    verdict, verdict_ts = g.get("verdict"), g.get("ts", "")
except Exception:
    verdict, verdict_ts = None, ""
# The verdict must postdate the marker: a verdict left behind by a previous run does
# not pay the debt of this session. ISO-8601 UTC strings compare lexicographically; if
# either timestamp is missing (old marker format, hand-edited gates.json), degrade to
# the weaker any-verdict check rather than blocking on unknowable state.
if verdict and (not since or not verdict_ts or verdict_ts >= since):
    print("CLEAR"); sys.exit(0)
if blocks >= max_blocks:
    print("OPEN"); sys.exit(0)
if hook_input.get("stop_hook_active") and blocks == 0:
    # The harness says a stop hook is already re-blocking this session, yet our own
    # counter never moved, so the marker is not persisting. Do not loop on a broken counter.
    print("OPEN"); sys.exit(0)
m["blocks"] = blocks + 1
json.dump(m, open(marker_path, "w"))
print(f"BLOCK {stage}")
' .temper/pending-stage.json .temper/gates.json "$MAX_BLOCKS" "$stdin_json" 2>/dev/null) || decision="OPEN"

  case "$decision" in
    CLEAR)
      _log "cleared (verdict recorded)"
      rm -f .temper/pending-stage.json 2>/dev/null
      return 0
      ;;
    BLOCK*)
      local stage="${decision#BLOCK }"
      _log "blocked stop (stage=$stage, no verdict)"
      # The CLI by its full path, quoted for the shell: the Bash tool has no `temper` on its
      # PATH, so a bare name would leave Claude guessing while this hook keeps blocking.
      local cli; cli="$(printf '%q' "$ROOT/scripts/temper")"
      printf '%s\n' >&2 \
        "temper: this session ran /temper:$stage but 'temper gate $stage' was never invoked, so" \
        "no verdict exists in .temper/gates.json and 'temper gate commit' cannot see that the" \
        "stage happened. Before finishing: record the stage's evidence as that stage's brief in" \
        "the plugin's agents folder specifies (for example '$cli state set complexity <tier>' for" \
        "plan, '$cli evidence add' for build, review and check), then run:" \
        "  $cli gate $stage --spec-path .temper/specs/<feature-slug>" \
        "A FAIL verdict is fine to finish on if the user chose to stop — the requirement is that" \
        "the gate ran, not that it passed."
      return 2
      ;;
    *)
      _log "fail-open (marker unreadable or block budget spent)"
      rm -f .temper/pending-stage.json 2>/dev/null
      return 0
      ;;
  esac
}

_main
exit $?
