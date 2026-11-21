# Case file 89 (round 2 of the adversarial review, reviewer 1): the fixes of rules 1, 2, 3, 4 and 11 and of the upgrade,
# broken again. Each check fails on the code under review and names the rule it holds. Sourced by test-temper.sh; its
# helpers (setup, fresh, gpass, _base_known) are used here. Every assertion name starts with "round 2 reviewer 1:".
# A call that may fail stays inside $( ... ) or ends in || true, so the file always runs to its end.

# --- the helpers of this file ---
_repo89() { # a git repository under the run, on master: one source file, every file but the run's own in one commit
  rm -rf .git src; git init -q . 2>/dev/null; git checkout -q -B master 2>/dev/null
  git config user.email t@example.com; git config user.name T
  mkdir -p src; echo 'echo demo' > src/demo.sh; git add -A -- . ':(exclude).temper' ':(exclude).claude'; git commit -q -m base
}
_fixrun89() { # a fix run past its approval (rca_complete), on its branch fix/bug
  setup; rm -f .temper/groups.json .temper/view.json .temper/build-state.json; _repo89
  "$TEMPER" state init bug --command fix --feature "the totals drop a cent" >/dev/null 2>&1; _base_known
  mkdir -p .temper/specs/bug; printf '# RCA\n\n## Root cause\n\nThe rounding.\n' > .temper/specs/bug/rca.md
  git checkout -q -B fix/bug 2>/dev/null; "$TEMPER" state set branch fix/bug >/dev/null 2>&1
  gpass rca; "$TEMPER" state advance rca_complete fix >/dev/null 2>&1
}
_row89() { # _row89 <stage> <row name>: the pass of that row of the stage's verdict in gates.json, or none
  python3 -I - "$1" "$2" <<'PY'
import json, sys
try:
    g = json.load(open(".temper/gates.json")).get(sys.argv[1]) or {}
except (OSError, ValueError):
    g = {}
print(next((str(r.get("pass")) for r in g.get("requirements") or [] if r.get("name") == sys.argv[2]), "none"))
PY
}
_older89() { # the run state as an older Temper saved it: no digest of the approved file, no saved_by stamp
  python3 -I - <<'PY'
import json
p = ".temper/build-state.json"
d = json.load(open(p))
for k in ("intent_hash", "saved_by"):
    d.pop(k, None)
json.dump(d, open(p, "w"), indent=2)
PY
}

# --- round 2 reviewer 1: rule 8, a ledger with an open finding is never cleared, whatever the words of the call ---
# person_call.py reads the stage of `evidence clear` from the FIRST --stage of the call; cmd_evidence_clear clears the
# stage of the LAST one. `temper evidence clear --stage plan --stage review` passes the check (the plan ledger holds no
# open finding) and empties the review ledger with its open high finding.
fresh
"$TEMPER" evidence add --stage review --claim 'src/demo.sh:1 the demo prints nothing on error' --severity high --label PROVEN >/dev/null 2>&1
"$TEMPER" evidence clear --stage review >/dev/null 2>&1; _c89a=$?
"$TEMPER" evidence clear --stage plan --stage review >/dev/null 2>&1; _c89b=$?
_n89="$(python3 -c 'import json; print(len(json.load(open(".temper/evidence/review.json"))))' 2>/dev/null || echo none)"
assert_eq "round 2 reviewer 1: rule 8 a clear of a ledger with an open finding is refused, also when the call names --stage twice" \
  "plain=refused|twice=refused|rows=1" \
  "plain=$([[ $_c89a -ne 0 ]] && echo refused || echo taken)|twice=$([[ $_c89b -ne 0 ]] && echo refused || echo taken)|rows=$_n89"

