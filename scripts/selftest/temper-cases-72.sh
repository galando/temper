# Case file 72 (WP28): two listed commands; the words of /temper:temper; the doors removed. A session lists two Temper
# commands, /temper:temper and /temper:fix. What the other nine did is a first word of /temper:temper (draft, status,
# report, init, pack) or gone (the five doors, with state init --enter, the keys enter and built_before, and walked).
# A first word is a word only in its documented form, so a request that starts with "status" starts a run; the hook
# pair that makes a session that captured a draft owe the intent gate (ADR 0005) follows the word draft.
# Sourced by test-temper.sh; its helpers (setup, fresh, nx) are used here. Token: w28. A call the CLI does not have yet
# stays inside $( ... ) or ends in || true, so the file always runs to its end.

# --- the helpers of this file ---
MARKER72="$REPO_ROOT/scripts/guards/stage-marker.sh"
# the hook manifest and the mod's test folder, named without a slash next to a folder name of the mod (the rule of
# scripts/validate-directory.sh for a script)
_HJ72="$(printf '%s/%s' hooks hooks.json)"; _TM72="$(printf '%s/%s' tests mod)"
_mark72() { # _mark72 <prompt>: the stage the marker records for that prompt in a fresh fixture, or "nothing"
  rm -f .temper/pending-stage.json
  python3 -I -c 'import json, sys; print(json.dumps({"prompt": sys.argv[1], "session_id": "s72"}))' "$1" | bash "$MARKER72"
  python3 -I -c 'import json; print(json.load(open(".temper/pending-stage.json")).get("stage", "?"))' 2>/dev/null || echo nothing
}
_hits72() { # _hits72 <lines>: "none", or the count and the first five lines, each cut at 120 characters, joined by ";"
  [[ -z "$1" ]] && { echo none; return 0; }
  printf '%d hits: %s\n' "$(printf '%s\n' "$1" | wc -l)" "$(printf '%s\n' "$1" | sed -n '1,5p' | cut -c1-120 | paste -sd';')"
}
_args72() { # the rows of the Arguments table of commands/temper.md as "first cell<TAB>whole row", one a line
  python3 -I - "$REPO_ROOT/commands/temper.md" <<'PY'
import sys
try:
    text = open(sys.argv[1], encoding="utf-8").read()
except OSError:
    text = ""
sec = text.split("## Arguments", 1)[1].split("\n## ", 1)[0] if "## Arguments" in text else ""
for l in sec.splitlines():
    if l.startswith("|") and l.count("|") >= 3 and not set(l) <= set("|-: "):
        print(l.split("|")[1].strip() + "\t" + l)
PY
}

# --- 1. two listed commands ---
assert_eq "w28 two listed commands: the manifest lists exactly ./commands/temper.md and ./commands/fix.md, and git tracks only those two under commands" \
  "manifest=./commands/fix.md,./commands/temper.md|count=2|tracked=commands/fix.md,commands/temper.md" \
  "$(python3 -I -c "
import json, sys
c = json.load(open(sys.argv[1])).get('commands') or []
print('manifest=%s|count=%d' % (','.join(sorted(c)), len(c)))" "$REPO_ROOT/.claude-plugin/plugin.json")|tracked=$(git -C "$REPO_ROOT" ls-files commands | LC_ALL=C sort | tr '\n' ',' | sed 's/,$//')"

# --- 2. the words have their pages ---
_rows72="$(_args72)"
_have72=""
for _w72 in status report draft init pack help; do
  printf '%s\n' "$_rows72" | cut -f1 | grep -qE "\`$_w72([^[:alnum:]_-]|$)" && _have72+="$_w72,"
done
assert_eq "w28 the words have their pages: the Arguments table of commands/temper.md has a row for status, report, draft, init, pack and help; reference/draft.md and reference/pack.md exist, reference/status.md does not" \
  "rows=status,report,draft,init,pack,help,|draft.md=yes|pack.md=yes|status.md=no" \
  "rows=$_have72|draft.md=$([[ -f "$REPO_ROOT/reference/draft.md" ]] && echo yes || echo no)|pack.md=$([[ -f "$REPO_ROOT/reference/pack.md" ]] && echo yes || echo no)|status.md=$([[ -e "$REPO_ROOT/reference/status.md" ]] && echo yes || echo no)"

# Mechanism steps 1 to 4: the row of draft reads reference/draft.md, the row of pack reads reference/pack.md, and the row
# of init runs the three setup calls (temper config init, temper init, temper guards install).
_row72() { printf '%s\n' "$_rows72" | awk -F'\t' -v w="$1" '{ if (match($1, "`" w "([^A-Za-z0-9_-]|$)")) print $2 }'; }
assert_eq "w28 each new word's row says what it does: draft reads reference/draft.md, pack reads reference/pack.md, init runs config init, init and guards install" \
  "draft=yes|pack=yes|init=config init,temper init,guards install" \
  "draft=$(_row72 draft | grep -q 'reference/draft\.md' && echo yes || echo no)|pack=$(_row72 pack | grep -q 'reference/pack\.md' && echo yes || echo no)|init=$(_r="$(_row72 init)"; _o=""
    grep -q 'config init' <<<"$_r" && _o+="config init,"; grep -qE 'temper init([^[:alnum:]_-]|$)' <<<"$_r" && _o+="temper init,"
    grep -q 'guards install' <<<"$_r" && _o+="guards install"; echo "${_o:-none}")"

# Mechanism step 2: the page of draft is the body of the old intent command, without its reviewer question and without
# the Target Users probe (WP26 cut the section); a draft ends with temper gate intent and stays Status: draft.
assert_eq "w28 the draft page: reference/draft.md writes Status: draft, ends with temper gate intent, and asks no reviewer and no Target Users" \
  "status draft=yes|gate intent=yes|reviewer=no|target users=no" "$(python3 -I - "$REPO_ROOT/reference/draft.md" <<'PY'
import re, sys
try:
    t = open(sys.argv[1], encoding="utf-8").read()
except OSError:
    print("no reference/draft.md"); sys.exit(0)
yn = lambda b: "yes" if b else "no"
print("status draft=%s|gate intent=%s|reviewer=%s|target users=%s" % (
    yn(re.search(r"Status:\**\s*`?draft", t)), yn(re.search(r"temper gate intent\b", t)),
    yn(re.search(r"\*\*Reviewer:\*\*|who reviews the intent", t, re.I)), yn(re.search(r"target users", t, re.I))))
PY
)"

# --- 3. no page names a command that is gone ---
assert_eq "w28 no page names a command that is gone: no /temper:intent, plan, design, build, review, check, status, init or pack in commands, agents, reference, templates, packs, skills, scripts/guards, the hook manifest or README.md" \
  "none" "$(_hits72 "$(git -C "$REPO_ROOT" grep -nE '/temper:(intent|plan|design|build|review|check|status|init|pack)([^[:alnum:]_]|$)' \
    -- commands agents reference templates packs skills scripts/guards "$_HJ72" README.md 2>/dev/null)")"

# --- 4. no door ---
setup
rm -f .temper/build-state.json
_out72="$("$TEMPER" state init demo --enter build 2>&1)"; _rc72=$?
assert_eq "w28 no door: state init --enter build exits 1 with one line that says the doors are gone and that /temper:temper takes up the active run, and writes no run state; temper --help holds no --enter" \
  "exit=1|lines=1|door=yes|gone=yes|/temper:temper=yes|active run=yes|state=absent|help=no --enter" \
  "exit=$_rc72|lines=$(printf '%s\n' "$_out72" | grep -c .)|door=$(grep -qiE '\bdoors?\b' <<<"$_out72" && echo yes || echo no)|gone=$(grep -qiE '\b(gone|removed|no longer)\b' <<<"$_out72" && echo yes || echo no)|/temper:temper=$(grep -qF '/temper:temper' <<<"$_out72" && echo yes || echo no)|active run=$(grep -qi 'active run' <<<"$_out72" && echo yes || echo no)|state=$([[ -f .temper/build-state.json ]] && echo present || echo absent)|help=$("$TEMPER" --help 2>&1 | grep -q -e '--enter' && echo has --enter || echo no --enter)"

# Mechanism step 8 keeps the refusal of the two keys: a refused key costs nothing. Passes at the head.
fresh
assert_eq "w28 state set enter and state set built_before stay refused" "enter=refused|built_before=refused" \
  "enter=$("$TEMPER" state set enter build >/dev/null 2>&1 && echo set || echo refused)|built_before=$("$TEMPER" state set built_before abc1234 >/dev/null 2>&1 && echo set || echo refused)"

# Trap of the spec: a run that 9.8.4 or the base saved after it came through a door has enter in its state. The key is
# ignored from here: a stage before the door with no verdict runs its agent, and no question asks about a walked stage.
fresh
python3 -I -c "
import json
p = '.temper/build-state.json'
d = json.load(open(p)); d['enter'] = 'build'
json.dump(d, open(p, 'w'), indent=2)"
assert_eq "w28 a saved enter key is ignored: at Intent with no verdict, next launches the Intent agent and does not only check the stage" \
  "work|temper:temper-intent" \
  "$(nx "d.get('action')")|$(nx "','.join(a.get('type', '') for a in d.get('agents') or []) or 'no agent'")"
gpass intent
_how72() { nx "d.get('action') + ':' + str((d.get('ask') or {}).get('id'))"; }
_with72="$(_how72)"
python3 -I -c "
import json
p = '.temper/build-state.json'
d = json.load(open(p)); d.pop('enter', None)
json.dump(d, open(p, 'w'), indent=2)"
assert_eq "w28 a saved enter key is ignored: a passed Intent goes on as it does with no enter key, and never asks run.walked" \
  "$(_how72)" "$_with72"

# --- 5. the draft word owes its gate ---
setup
assert_eq "w28 the draft word owes its gate: /temper:temper draft an idea and /temper draft an idea mark the stage intent; /temper:temper add a thing and /temper:intent x mark nothing" \
  "draft=intent|short draft=intent|request=nothing|old command=nothing" \
  "draft=$(_mark72 '/temper:temper draft an idea')|short draft=$(_mark72 '/temper draft an idea')|request=$(_mark72 '/temper:temper add a thing')|old command=$(_mark72 '/temper:intent x')"
rm -f .temper/pending-stage.json

# --- 7. no scripted scenario or mod test enters through a door (search of scripts/e2e and the mod's tests) ---
assert_eq "w28 no scripted scenario or mod test enters through a door: no --enter in scripts/e2e or the mod's tests, and no run of a command that is gone" \
  "none" "$(_hits72 "$(git -C "$REPO_ROOT" grep -nE -e '--enter' -e "command: '(temper:)?(intent|plan|design|build|review|check|status|init|pack)'" \
    -- scripts/e2e "$_TM72" 2>/dev/null)")"

# --- 8. the validators, with the rows of mechanism step 7 ---
assert_eq "w28 the rows of validate-docs.sh: commands/temper.md must hold reference/draft.md and reference/pack.md and must not hold ## Entering at a stage or --enter, and no row reads a deleted page" \
  "draft=+|pack=+|entering=-|enter=-|deleted pages=none" "$(python3 -I - "$REPO_ROOT/scripts/validate-docs.sh" <<'PY'
import ast, re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"^ROWS = (\[.*?^\])", text, re.S | re.M)
rows = ast.literal_eval(m.group(1)) if m else []
def sign(needle):
    s = sorted({r[1] for r in rows if r[0] == "commands/temper.md" and needle in r[2].replace("\\", "")})
    return "".join(s) or "none"
gone = ["commands/%s.md" % c for c in ("intent", "plan", "design", "build", "review", "check", "status", "init", "pack")]
dead = sorted({r[0] for r in rows if r[0] in gone or r[0] == "reference/status.md"})
print("draft=%s|pack=%s|entering=%s|enter=%s|deleted pages=%s" % (
    sign("reference/draft.md"), sign("reference/pack.md"), sign("## Entering at a stage"), sign("--enter"),
    ",".join(dead) or "none"))
PY
)"
assert_eq "w28 validate-docs.sh and validate-plugin.sh pass" "docs=0|plugin=0" \
  "docs=$(bash "$REPO_ROOT/scripts/validate-docs.sh" >/dev/null 2>&1; echo $?)|plugin=$(bash "$REPO_ROOT/scripts/validate-plugin.sh" >/dev/null 2>&1; echo $?)"
