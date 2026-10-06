#!/usr/bin/env bash
#
# block-secrets.sh — PreToolUse / pre-commit secret detector.
#
# Deterministic, non-model: blocks a commit/edit when a known secret pattern is matched.
#
# DEGRADATION CONTRACT (non-negotiable):
#   - Detected secret pattern  => exit 2  (BLOCK — the one fail-closed path)
#   - No match                 => exit 0  (pass)
#   - Internal error / missing => exit 0  (FAIL-OPEN. A script bug or missing input must
#                                          never block a commit. Only a *detected* secret
#                                          blocks.)
#
# Inputs. Two ways to run it:
#   - As an in-agent hook (a PreToolUse tool call as JSON on stdin), it scans only the text
#     the call adds: a Write's content, an Edit's new_string, each MultiEdit new_string, a
#     notebook cell's new source and a Bash command. It never reads staged files or the
#     file being edited, so a secret already in the tree does not refuse every later call
#     (the call that unstages it, or an Edit that takes it out, among them). Without
#     python3 the call cannot be split up, so it passes; the commit hook still scans.
#   - As the git pre-commit hook (the installed hook passes --staged; a run with no JSON
#     on stdin counts the same), it scans the staged files: the content in git's index
#     (git show ":<path>"), which is what the commit records, not the copy in the work
#     tree. Names are read NUL-separated, so no file name is quoted or skipped. Without
#     --staged it also scans the file named by $CLAUDE_FILE_PATH and any plain text on stdin.
# A block names where the match is: the staged file, the file, standard input or the text
# the tool call adds.
# Absence of input => exit 0.
set -uo pipefail

# Fail-open wrapper: any unhandled error exits 0, never 2.
_main() {
  # High-precision patterns. Conservative: favor false-negatives over false-positives.
  # A broad pattern that blocks legitimate commits is a developer-workflow DoS.
  local -a patterns=(
    'AKIA[0-9A-Z]{16}'                       # AWS access key ID
    'gh[ps]_[0-9A-Za-z]{36}'                 # GitHub token (pat/secret)
    '-----BEGIN [A-Z ]*PRIVATE KEY-----'     # private key header
    # Live API keys: vendor-specific formats only (H-1). A bare sk-[20+] catches
    # documentation/fixture strings and is a DX DoS. Anthropic live keys are
    # sk-ant-...{50,}; OpenAI live keys are sk-[A-Za-z0-9]{48} (legacy) /
    # sk-proj-... Newer OpenAI keys carry sk-proj- / sk-svcacct- prefixes.
    'sk-ant-[A-Za-z0-9_-]{50,}'              # Anthropic live API key
    'sk-proj-[A-Za-z0-9_-]{40,}'             # OpenAI project API key
    'sk-svcacct-[A-Za-z0-9_-]{40,}'          # OpenAI service-account key
    'sk-[A-Za-z0-9]{48}'                     # OpenAI legacy live API key (exact length)
  )

  local staged_only=0
  [[ "${1:-}" == "--staged" ]] && staged_only=1

  # stdin: an in-agent hook's tool call (JSON), or nothing at all from git.
  local input=""
  if [[ $staged_only -eq 0 && ! -t 0 ]]; then
    input=$(cat 2>/dev/null || true)
  fi

  # Gather the text to scan.
  local text=""
  local hook_mode=0
  if [[ $staged_only -eq 0 && "$input" =~ ^[[:space:]]*\{ ]]; then
    # An in-agent hook: scan only what this call adds.
    command -v python3 >/dev/null 2>&1 || return 0
    local added rc
    added=$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    call = json.load(sys.stdin)
except Exception:
    sys.exit(3)
if not isinstance(call, dict):
    sys.exit(3)
tool_input = call.get("tool_input")
if not isinstance(tool_input, dict):
    sys.exit(0)
parts = []
for key in ("content", "new_string", "new_source", "command"):
    value = tool_input.get(key)
    if isinstance(value, str):
        parts.append(value)
edits = tool_input.get("edits")
if isinstance(edits, list):
    for edit in edits:
        if isinstance(edit, dict) and isinstance(edit.get("new_string"), str):
            parts.append(edit["new_string"])
sys.stdout.write("\n".join(parts))
' 2>/dev/null)
    rc=$?
    if [[ $rc -eq 0 ]]; then
      hook_mode=1
      text="$added"
    elif [[ $rc -ne 3 ]]; then
      return 0   # python3 failed: fail open
    fi
    # rc 3: not a JSON tool call after all, so it is scanned as plain text below.
  fi

  local joined
  joined=$(IFS='|'; echo "${patterns[*]}")
  _first_match() { # reads stdin and prints the first match of a pattern ('' for none). grep -E
                   # for the alternation, -o for the matched token, -a so a binary file is
                   # still read as text, and the C locale so the ranges are plain ASCII.
    LC_ALL=C grep -aEo -e "$joined" 2>/dev/null | head -1
  }
  _block() { # _block <match> <where>
    echo "BLOCK: detected likely secret pattern: '$1' in $2" >&2
    echo "Refusing commit/edit. Remove the secret or place it in an env var / secrets store." >&2
  }

  local match
  if [[ $hook_mode -eq 1 ]]; then
    match=$(printf '%s' "$text" | _first_match || true)
    if [[ -n "$match" ]]; then _block "$match" "the text this tool call adds"; return 2; fi
    return 0
  fi

  if [[ $staged_only -eq 0 ]]; then
    if [[ -n "${CLAUDE_FILE_PATH:-}" && -f "${CLAUDE_FILE_PATH}" ]]; then
      match=$(_first_match < "${CLAUDE_FILE_PATH}" || true)
      if [[ -n "$match" ]]; then _block "$match" "the file '${CLAUDE_FILE_PATH}'"; return 2; fi
    fi
    if [[ -n "$input" ]]; then
      match=$(printf '%s' "$input" | _first_match || true)
      if [[ -n "$match" ]]; then _block "$match" "standard input"; return 2; fi
    fi
  fi

  # Staged files (pre-commit): the staged content, read from the index one file at a time,
  # so a block names the file. Best-effort; git failures are ignored.
  command -v git >/dev/null 2>&1 || return 0
  local f
  while IFS= read -r -d '' f; do
    match=$(git show ":$f" 2>/dev/null | _first_match || true)
    if [[ -n "$match" ]]; then _block "$match" "the staged copy of '$f'"; return 2; fi
  done < <(git diff --cached --name-only -z --diff-filter=ACMR 2>/dev/null || true)
  return 0
}

_main "$@"
