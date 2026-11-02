#!/usr/bin/env bash
# A live smoke of Temper with a real model: Claude Code runs headless with this plugin on a scratch project. It is OFF by default
# and never part of CI (no job sets a key or logs in): set TEMPER_E2E_LIVE=1 on a machine where Claude Code is already signed in.
# It reads no key, token or settings file; it only starts `claude` and looks at what it left.
#
#   TEMPER_E2E_LIVE=1 bash scripts/e2e/live-smoke.sh            the start check, then the fresh review check with the mod and without it
#   TEMPER_E2E_LIVE=1 bash scripts/e2e/live-smoke.sh start      only the start check (a run starts; plan mode, nothing is written)
#   TEMPER_E2E_LIVE=1 bash scripts/e2e/live-smoke.sh fresh      only the fresh review check
#
# The fresh review check (9.7.6). A scratch Python project gets an accepted intent for a medium change (limit failed logins), with
# the run already at Plan: a headless session cannot answer the Intent question. Then `claude -p "/temper:temper"` takes the run
# up: the Plan agent writes the plan, the CLI launches the fresh reviewer, and the session ends at the plan question it cannot
# answer. The check reads what the run left: plan.md and tasks.md, a completion row for each lens against the tasks.md as it is,
# the reader's paraphrase, the paraphrase in the plan question, and the `fresh` field of view.json. It runs twice: with the mod
# (the plugin as it loads) and without it (`--settings '{"disableAllHooks": true}'`, which stops every mod). Both must end in the
# same state. A model can word a plan differently each run, so it compares outcomes, never text.
#
# Permissions: the fresh check lets the session edit files and run commands without asking (acceptEdits, with Bash, Agent and the
# file tools allowed), inside a throwaway folder it deletes at the end. It costs real model calls: a Plan agent and a reviewer per
# leg. `plan.fresh-review: always` makes the reviewer run whatever tier the Plan agent records.
set -uo pipefail
if [[ "${TEMPER_E2E_LIVE:-}" != "1" ]]; then
  echo "live smoke is off (set TEMPER_E2E_LIVE=1 on a machine where Claude Code is signed in)"
  exit 0
fi
command -v claude >/dev/null 2>&1 || { echo "FAIL: claude is not installed" >&2; exit 1; }
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="${HERE%/scripts/e2e}"
TEMPER="$PLUGIN/scripts/temper"
WHAT="${1:-all}"
case "$WHAT" in all|start|fresh) ;; *) echo "FAIL: usage: live-smoke.sh [all|start|fresh]" >&2; exit 2 ;; esac
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
FAILED=0
fail() { echo "FAIL: $*"; FAILED=1; }

# ---- the start check: a run starts ----
if [[ "$WHAT" != "fresh" ]]; then
  d="$SCRATCH/start"; mkdir -p "$d"
  (cd "$d" && git init -q . && git checkout -q -B main && echo "# scratch" > README.md && git add -A && git -c user.email=e2e@example.com -c user.name=e2e commit -qm base)
  OUT="$(cd "$d" && timeout 600 claude -p "/temper:temper \"print hello\"" --plugin-dir "$PLUGIN" --permission-mode plan 2>&1)"; rc=$?
  echo "$OUT" | tail -20
  [[ -d "$d/.temper" ]] && echo "OK: start: the run left a .temper folder" || fail "start: no run was started (exit $rc)"
fi
[[ "$WHAT" == "start" ]] && exit "$FAILED"

# ---- the fresh review check ----
seed() { # seed <folder>: a small Python service, its config, and a run at Plan with an accepted medium intent
  local d="$1"
  mkdir -p "$d/src" "$d/unit" "$d/.claude"
  cd "$d" || return 1
  git init -q . && git checkout -q -B main
  : > src/__init__.py; : > unit/__init__.py
  printf '"""Time helpers. Tests patch now()."""\nimport time\n\n\ndef now():\n    return time.time()\n' > src/timeutil.py
  printf 'def login(request):\n    return {"status": 200} if request.get("password") == "secret" else {"status": 401}\n' > src/auth.py
  printf '"""Routes in ROUTES, middleware in MIDDLEWARE (run in order before the route)."""\nfrom src import auth\n\nMIDDLEWARE = []\nROUTES = {"POST /login": auth.login}\n\n\ndef handle(method, path, request):\n    for mw in MIDDLEWARE:\n        early = mw(method, path, request)\n        if early is not None:\n            return early\n    return ROUTES[f"{method} {path}"](request)\n' > src/app.py
  printf '__pycache__/\n' > .gitignore
  cp "$PLUGIN/templates/temper.config.default" .claude/temper.config
  printf '\nplan:\n  fresh-review: always\n' >> .claude/temper.config
  git add -A && git -c user.email=e2e@example.com -c user.name=e2e commit -qm base
  "$TEMPER" init >/dev/null 2>&1
  "$TEMPER" state init login-limit --feature 'Limit failed logins' >/dev/null || return 1
  mkdir -p .temper/specs/login-limit
  cat > .temper/specs/login-limit/intent.md <<'INTENT'
# Intent: Limit failed logins

**Author:** e2e <e2e@example.com>
**Reviewer:** e2e reviewer <rev@example.com>
**Status:** draft
**Created:** 2026-11-02
**Complexity:** medium

## Problem
Anyone can try passwords on POST /login without limit. Support wants brute force stopped without locking real users out for long.

### Success Criteria
- [ ] AC-01 [required]: after 3 failed logins for one username within 10 minutes, the next attempt is refused with status 423 and a Retry-After header in whole seconds
  Why: stops password guessing for one account
  Validate: scenario — a test drives src.app.handle
- [ ] AC-02 [required]: a successful login clears that username's failure count
  Why: a real user who finally types the right password is not locked out later
  Validate: scenario — a test drives src.app.handle

### Constraints
- One process, memory only: no Redis or other store (proposed)
- Use src/timeutil.now so tests control the clock (proposed)

### Scope and Non-goals
- In scope: POST /login
- Out of scope: other routes, an admin unlock
- Must keep working: a correct password logs in

### Target Users
- support engineer: sees a brute force attempt → it is stopped after 3 tries

### Open Questions

### Decisions

## Scenarios (BDD)

## Source Traceability
### Context Sources
- none: description only
INTENT
  local g; g="$("$TEMPER" gate intent 2>&1)" || { echo "$g"; return 1; }
  "$TEMPER" intent accept >/dev/null || return 1
  git add -A && git -c user.email=e2e@example.com -c user.name=e2e commit -qm "the accepted intent" >/dev/null
  "$TEMPER" state advance intent_complete plan >/dev/null || return 1
}

leg() { # leg <name> [claude flags...]: seed, take the run up headless, print one outcome line "name|ok|..." on the last line
  local name="$1"; shift
  local d="$SCRATCH/$name"
  if ! (seed "$d") >"$SCRATCH/$name-seed.log" 2>&1; then
    cat "$SCRATCH/$name-seed.log"; fail "$name: the seed did not reach Plan"; echo "$name|seed"; return
  fi
  local out rc
  out="$(cd "$d" && timeout 1800 claude -p "/temper:temper" --plugin-dir "$PLUGIN" --permission-mode acceptEdits \
    --allowedTools Bash Read Write Edit Glob Grep Agent "$@" 2>&1)"; rc=$?
  echo "$out" | tail -15 | sed "s/^/  [$name] /"
  local spec=".temper/specs/login-limit"
  (cd "$d" && python3 -I - "$PLUGIN/scripts" "$spec" "$name" "$rc" <<'PY'
import json, os, subprocess, sys
scripts, spec, name, rc = sys.argv[1:5]
sys.path.insert(0, scripts)
import fresh_review
bad = []
for f in ("plan.md", "tasks.md"):
    if not os.path.isfile(os.path.join(spec, f)):
        bad.append("no %s (claude exited %s)" % (f, rc))
risk = json.load(open(".temper/build-state.json")).get("risk", "") if os.path.isfile(".temper/build-state.json") else ""
st = fresh_review.status(spec, ".temper/evidence/plan.json", "", "always", risk)
if st["missing"]:
    bad.append("not run on this tasks.md: %s" % ", ".join(st["missing"]))
if not st["paraphrase"]:
    bad.append("no paraphrase recorded")
nxt = json.loads(subprocess.run([os.path.join(scripts, "temper"), "next", "--json"], capture_output=True, text=True).stdout or "{}")
q = ((nxt.get("ask") or {}).get("question") or {}).get("question", "")
if nxt.get("stage") != "plan" or "A reader with no context took it as" not in q:
    bad.append("the plan question does not carry the paraphrase (next: %s %s)" % (nxt.get("action"), q[:120]))
view = json.load(open(".temper/view.json")) if os.path.isfile(".temper/view.json") else {}
if not isinstance(view.get("fresh"), dict) or not view["fresh"].get("paraphrase"):
    bad.append("view.json has no fresh review")
blockers = len(fresh_review.blockers(st))
for b in bad:
    print("FAIL: %s: %s" % (name, b))
print("  [%s] lenses run: %s; findings: %d (%d open blockers); paraphrase: %s" % (name, ", ".join(st["done"]) or "none", len(st["findings"]), blockers, st["paraphrase"][:160]))
print("%s|%s|%s" % (name, "ok" if not bad else "bad", ",".join(sorted(st["done"]))))
PY
  )
}

echo "--- the fresh review check, with the mod ---"
A="$(leg mod)"; echo "$A" | sed '$d'
echo "--- the fresh review check, without the mod (disableAllHooks) ---"
B="$(leg plain --settings '{"disableAllHooks": true}')"; echo "$B" | sed '$d'
grep -q '^FAIL' <<<"$A$B" && FAILED=1
a="$(tail -1 <<<"$A")"; b="$(tail -1 <<<"$B")"
if [[ "${a#*|}" == "ok|"* && "${a#*|}" == "${b#*|}" ]]; then
  echo "OK: fresh: with the mod and without it the run reached the plan question with the fresh review done (${a##*|})"
else
  fail "fresh: the two legs ended differently (mod: ${a#*|}; without: ${b#*|})"
fi
exit "$FAILED"
