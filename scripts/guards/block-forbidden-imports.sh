#!/usr/bin/env bash
#
# block-forbidden-imports.sh — PostToolUse forbidden-import check.
#
# Checks edited files' import statements against a configurable denylist. The denylist
# DEFAULTS TO EMPTY => warn-only / no-op. Exit 2 ONLY on an explicit denylist match.
#
# Configure via the TEMPER_FORBIDDEN_IMPORTS env var (colon-separated), e.g.:
#   TEMPER_FORBIDDEN_IMPORTS="eval:child_process.exec"
# or set it in settings.json `env`.
#
# DEGRADATION CONTRACT:
#   - Explicit denylist match => exit 2 (BLOCK)
#   - No denylist / no match   => exit 0 (warn-only default; empty denylist = no-op)
#   - Internal error / missing => exit 0 (FAIL-OPEN)
set -uo pipefail

_main() {
  local denylist="${TEMPER_FORBIDDEN_IMPORTS:-}"
  # Empty denylist => warn-only default. No block.
  [[ -z "$denylist" ]] && return 0

  # Gather edited file paths. PostToolUse delivers the tool payload as JSON on stdin —
  # tool_input.file_path is the edited file (this was the wiring bug: the hook used to
  # read only CLAUDE_FILE_PATH, which hook events never set, so in-agent it scanned
  # nothing). CLAUDE_FILE_PATH is kept as a fallback; pre-commit uses staged files.
  local -a files=()
  if [[ ! -t 0 ]] && command -v python3 >/dev/null 2>&1; then
    local stdin_file
    stdin_file=$(python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('tool_input', {}).get('file_path', '') or '')
except Exception:
    print('')
" 2>/dev/null) || stdin_file=""
    [[ -n "$stdin_file" && -f "$stdin_file" ]] && files+=("$stdin_file")
  fi
  if [[ -n "${CLAUDE_FILE_PATH:-}" && -f "${CLAUDE_FILE_PATH}" ]]; then
    files+=("${CLAUDE_FILE_PATH}")
  fi
  if command -v git >/dev/null 2>&1; then
    local staged
    staged=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)
    if [[ -n "$staged" ]]; then
      while IFS= read -r f; do
        [[ -n "$f" && -f "$f" ]] && files+=("$f")
      done <<<"$staged"
    fi
  fi
  [[ ${#files[@]} -eq 0 ]] && return 0

  # Build alternation of denied names from the colon-separated list.
  local alt
  alt=$(echo "$denylist" | tr ':' '|')

  local f content hit
  for f in "${files[@]}"; do
    content=$(cat "$f" 2>/dev/null || true)
    [[ -z "$content" ]] && continue
    # Match common import forms containing a denied name as a token.
    # Covers static import/require/from/#include plus dynamic forms (__import__,
    # load, source, await import) so the denylist catches dynamic dispatch too.
    # Use a character-class boundary to avoid quoting issues with quotes/brackets.
    if hit=$(printf '%s' "$content" | grep -En "(^|[[:space:][:punct:]])(import|from|require|#include|__import__|load|source)[^a-zA-Z0-9]*(${alt})([^a-zA-Z0-9]|$)" 2>/dev/null | head -1); then
      if [[ -n "$hit" ]]; then
        echo "BLOCK: forbidden import detected in ${f}:" >&2
        echo "  ${hit}" >&2
        echo "Remove the import or clear it from TEMPER_FORBIDDEN_IMPORTS." >&2
        return 2
      fi
    fi
  done
  return 0
}

_main "$@"
