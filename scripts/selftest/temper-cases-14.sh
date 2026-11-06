# Release 9.7.6: the fresh review of the plan (ask, auto, always, off; the launch mark; the files it read; the round limit; a lazy
# review), checkable contests, a reviewer that did not run, review findings answered the same way, and spec drift.
# Sourced by test-temper.sh after temper-cases-13.sh (helpers: nx, labels, gpass, gfail, setup, fresh_reviewed, assert_eq, assert_exit).

_fr_plan() { # a medium plan at the Plan stage whose only failing rows can be the fresh review's; $1: plan.fresh-review (default ask)
  setup
  [[ -n "${1:-}" ]] && printf 'plan:\n  fresh-review: %s\n' "$1" >> .claude/temper.config
  "$TEMPER" state init demo --feature "the demo thing" >/dev/null 2>&1
  gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
  "$TEMPER" state set complexity medium >/dev/null 2>&1
  cat > .temper/specs/demo/plan.md <<'EOF'
## Context Map
- use: intent.md - the accepted scope
- reviewed: auto - every source is current and on topic

## Blast Radius
- no external consumers

## Cross-Repo Search
- not available: no cross-repo search tool connected
EOF
}
_fr_n() { grep -c '^### Task' .temper/specs/demo/tasks.md; }
_fr_done() { # _fr_done <lens> [instance] [readiness count]
  local v=""; [[ "$1" == readiness ]] && v="--value ${3:-$(_fr_n)}"
  # shellcheck disable=SC2086
  "$TEMPER" evidence add --stage plan --phase fresh --exit 0 --label PROVEN --claim "fresh review completed: $1 ${2:-A}" $v >/dev/null 2>&1
}
_fr_para() { "$TEMPER" evidence add --stage plan --phase fresh --claim "paraphrase: ${1:-the demo runs twice and prints its output | a demo is one shell step run by the suite}" >/dev/null 2>&1; }
_fr_find() { "$TEMPER" evidence add --stage plan --phase fresh --severity "$1" --claim "$2" >/dev/null 2>&1; }
_fr_all() { _fr_done readiness; _fr_done zoom-out; _fr_done comprehension; _fr_para; }
_fr_row() { # _fr_row <row name> -> pass|detail of that plan gate row, or absent
  "$TEMPER" gate plan >/dev/null 2>&1
  python3 - "$1" <<'PY'
import json, sys
for r in json.load(open('.temper/gates.json'))['plan']['requirements']:
    if r['name'] == sys.argv[1]:
        print('%s|%s' % (r['pass'], r['detail'])); break
else:
    print('absent')
PY
}

# --- 1. ask (the default): the plan question offers it; it applies only once the person asks ---
_fr_plan
assert_exit "ask: a medium plan passes the plan gate when nobody asked for a fresh review" 0 "$TEMPER" gate plan
assert_eq "ask: the plan question offers Fresh review first after the two ways on (9.8.0: no Design below risk H)" "Stage by stage (Recommended)|Autonomous Build: run Build unattended|Fresh review first|More options" "$(labels)"
assert_eq "ask: the option asks for it; next then launches the reviewer, whose gate call follows it" "plan fresh request" \
  "$(nx "'|'.join(c.split('temper ', 1)[1] for c in d['ask']['options'][2]['calls'])")"
"$TEMPER" plan fresh request >/dev/null 2>&1
assert_eq "ask: once asked, the gate fails until the reviewer ran" "False|not run yet: the CLI launches it (temper plan fresh start)" "$(_fr_row 'fresh review ran')"
assert_eq "ask: next launches one reviewer with no context, on the brief's model, every lens, round 1 of 3, the launch marked first" \
  "work|temper:temper-plan-review|sonnet|1|1|plan fresh start" \
  "$(nx "a = d['agents'][0]; '|'.join([d['action'], a['type'], a['model'], str(int('Lenses: readiness, zoom-out, comprehension.' in a['prompt'])), str(int('Round: 1 of 3.' in a['prompt'])), a['before'][0].split('temper ', 1)[1]])")"
assert_eq "ask: after the request the plan question no longer offers it" "0" "$(_fr_all >/dev/null; "$TEMPER" plan fresh start >/dev/null 2>&1; nx "sum(1 for o in d.get('ask', {}).get('options', []) if o['label'] == 'Fresh review first')")"
setup
assert_eq "ask: a simple plan is offered it too" "Fresh review first" "$("$TEMPER" state init demo >/dev/null 2>&1; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; nx "d['ask']['options'][2]['label']")"
assert_exit "state set fresh is refused: the fresh review's marks are the CLI's" 1 "$TEMPER" state set fresh.requested true

# --- 2. auto, always, off ---
_fr_plan auto
assert_eq "auto: a medium plan fails the plan gate until the fresh review ran" "False|not run yet: the CLI launches it (temper plan fresh start)" "$(_fr_row 'fresh review ran')"
assert_eq "auto: the plan question offers nothing to ask for" "0" "$(nx "sum(1 for o in (d.get('ask') or {}).get('options', []) if o['label'] == 'Fresh review first')")"
setup; printf 'plan:\n  fresh-review: auto\n' >> .claude/temper.config
assert_exit "auto: a simple plan passes with no fresh review" 0 "$TEMPER" gate plan
setup; printf 'plan:\n  fresh-review: always\n' >> .claude/temper.config
assert_exit "always: a simple plan needs it" 1 "$TEMPER" gate plan
_fr_plan off; "$TEMPER" plan fresh request >/dev/null 2>&1
assert_exit "off: never, even when asked" 0 "$TEMPER" gate plan

# --- 3. Only rows recorded after the CLI's launch mark count: the Plan agent cannot record the review itself ---
_fr_plan auto
_fr_all
assert_eq "launch mark: a full review recorded before any launch counts for nothing" "False|not run yet: the CLI launches it (temper plan fresh start)" "$(_fr_row 'fresh review ran')"
"$TEMPER" plan fresh start >/dev/null 2>&1
assert_eq "launch mark: rows recorded before the launch still do not count after it" \
  "False|not run: readiness A, zoom-out A, comprehension A; a reviewer that recorded no completion row did not review" "$(_fr_row 'fresh review ran')"
_fr_done readiness "" 0; _fr_done zoom-out; _fr_done comprehension; _fr_para "too short | yes"
assert_eq "lazy review: a readiness row that checked fewer tasks than tasks.md has is not run" \
  "False|not run: readiness A; a reviewer that recorded no completion row did not review; readiness A checked 0 task(s), tasks.md has $(_fr_n)" "$(_fr_row 'fresh review ran')"
assert_eq "lazy review: a paraphrase too short to compare with the intent fails" \
  "False|too short to compare with the intent (each part needs 6 words or more): too short | yes" "$(_fr_row "fresh reader's paraphrase")"
assert_eq "lazy review: the question offers to run the reviewer again, which clears the launch" "Run the fresh review again (Recommended)|plan fresh again" \
  "$(nx "o = d['ask']['options'][0]; o['label'] + '|' + o['calls'][0].split('temper ', 1)[1]")"
_fr_done readiness; _fr_para
assert_exit "launch mark: rows after it, with the task count and a real paraphrase, pass the plan gate" 0 "$TEMPER" gate plan
assert_eq "the plan question shows the reader's paraphrase" "1" \
  "$(nx "int('A reader with no context took it as: the demo runs twice and prints its output | a demo is one shell step run by the suite. Approve the plan' in d['ask']['question']['question'])")"
gfail plan "blast radius documented" "plan.md missing a Blast Radius section"
assert_eq "a plan question that failed on another row still carries the paraphrase" "1" \
  "$(nx "int('Plan: the check failed (blast radius documented: plan.md missing a Blast Radius section). A reader with no context took it as: the demo runs' in d['ask']['question']['question'])")"
"$TEMPER" gate plan >/dev/null 2>&1
assert_eq "a launched review that did not finish is asked about, never launched again by itself" "ask" \
  "$("$TEMPER" plan fresh again >/dev/null 2>&1; "$TEMPER" plan fresh start >/dev/null 2>&1; "$TEMPER" gate plan >/dev/null 2>&1; nx "d['action']")"

# --- 4. A blocker; Revise the plan; any of the three files edited makes the review stale ---
_fr_plan auto; "$TEMPER" plan fresh start >/dev/null 2>&1; _fr_all
_fr_find high "[readiness] Task 1: the case names no expected value"; _fr_find low "[zoom-out] a helper the code has"
assert_eq "an open high finding fails the blockers row and names it" "False|1 open: #5 [readiness] Task 1: the case names no expected value" "$(_fr_row 'no open plan blockers')"
assert_eq "the plan question offers Revise the plan first, and the plan's accept question" "Revise the plan (Recommended)|Accept a finding|More options|1" \
  "$(nx "'|'.join(o['label'] for o in d['ask']['options']) + '|' + str(int(d['ask']['accept']['options'][0]['calls'][0].endswith(\"evidence accept --stage plan --id 5 --reason '{reason}'\")))")"
"$TEMPER" state redo plan --reason "fresh review" >/dev/null 2>&1
assert_eq "after Revise the plan the Plan agent runs with the findings to answer" "temper:temper-plan|1" \
  "$(nx "a = d['agents'][0]; a['type'] + '|' + str(int('#5 [high] [readiness] Task 1' in a['prompt']))")"
for f in intent.md plan.md tasks.md; do
  cp ".temper/specs/demo/$f" "/tmp/fr-$$-$f"; echo "an edit" >> ".temper/specs/demo/$f"
  assert_eq "stale: an edit of $f after the launch makes the review stale" \
    "False|intent.md, plan.md or tasks.md changed after the fresh review; it runs again on the new text" "$(_fr_row 'fresh review ran')"
  cp "/tmp/fr-$$-$f" ".temper/specs/demo/$f"; rm -f "/tmp/fr-$$-$f"
done
echo "- an expected value" >> .temper/specs/demo/tasks.md
assert_eq "stale: a finding against the old files no longer counts" "True|0 open blockers" "$(_fr_row 'no open plan blockers')"
assert_eq "stale: the review is launched again by itself, round 2" "temper:temper-plan-review|1" "$(nx "a = d['agents'][0]; a['type'] + '|' + str(int('Round: 2 of 3.' in a['prompt']))")"

# --- 5. The round limit (plan.fresh-review-rounds) ---
_fr_plan auto; printf '  fresh-review-rounds: 2\n' >> .claude/temper.config
"$TEMPER" plan fresh start >/dev/null 2>&1; "$TEMPER" plan fresh again >/dev/null 2>&1; "$TEMPER" plan fresh start >/dev/null 2>&1
assert_exit "rounds: a third launch past a limit of 2 is refused" 1 "$TEMPER" plan fresh start
_fr_all; _fr_find high "[readiness] Task 1: still no expected value"; "$TEMPER" gate plan >/dev/null 2>&1
assert_eq "rounds: at the limit the question offers no revision, says so, and keeps the accept question" "Accept a finding|1" \
  "$(nx "d['ask']['options'][0]['label'] + '|' + str(int('ran 2 of 2 rounds (plan.fresh-review-rounds)' in d['ask']['question']['question']))")"
echo "an edit" >> .temper/specs/demo/tasks.md; "$TEMPER" gate plan >/dev/null 2>&1
assert_eq "rounds: a stale review at the limit is not launched again" "ask" "$(nx "d['action']")"

# --- 6. Risk H: two independent reviewers ---
_fr_plan auto; riskH; "$TEMPER" gate plan >/dev/null 2>&1
assert_eq "risk H: next launches A and B in one action; only the first marks the launch" "2|1|1|1|0" \
  "$(nx "a = d['agents']; '|'.join(map(str, [len(a), int('Instance: A.' in a[0]['prompt']), int('Instance: B.' in a[1]['prompt']), len(a[0].get('before', [])), len(a[1].get('before', []))]))")"
"$TEMPER" plan fresh start >/dev/null 2>&1; _fr_all
assert_eq "risk H: instance B is needed too" \
  "False|not run: readiness B, zoom-out B, comprehension B; a reviewer that recorded no completion row did not review" "$(_fr_row 'fresh review ran')"
printf '  fresh-review-twice: false\n' >> .claude/temper.config
assert_eq "risk H: plan.fresh-review-twice false needs A only" "True" "$(_fr_row 'fresh review ran' | cut -d'|' -f1)"

# --- 7. A contest cites and quotes what the reviewer could read; a comprehension finding is never contested ---
_fr_plan auto; mkdir -p src; printf 'alpha() {\n  echo "the alpha helper prints a"\n}\n' > src/a.sh
"$TEMPER" plan fresh start >/dev/null 2>&1; _fr_all
_fr_find high "[zoom-out] src/a.sh: a new helper where one exists"; _fr_find high "[comprehension] the word demo is not defined"
assert_exit "contest: no quote is refused" 1 "$TEMPER" evidence contest --stage plan --id 5 --cite src/a.sh:alpha --reason "it exists"
assert_eq "contest: a missing file is refused, and the refusal names escalate" "1" \
  "$("$TEMPER" evidence contest --stage plan --id 5 --cite src/nothing.sh --quote 'the alpha helper' --reason x 2>&1 | grep -c 'no file src/nothing.sh.*escalate')"
assert_exit "contest: a path outside the project is refused" 1 "$TEMPER" evidence contest --stage plan --id 5 --cite ../outside.sh --quote 'the alpha helper' --reason x
assert_exit "contest: a line the file does not have is refused" 1 "$TEMPER" evidence contest --stage plan --id 5 --cite src/a.sh:9 --quote 'the alpha helper' --reason x
assert_exit "contest: a quote not within 3 lines of the cited line is refused" 1 "$TEMPER" evidence contest --stage plan --id 5 --cite src/a.sh:3 --quote 'a quote that is not there' --reason x
assert_exit "contest: a symbol the file does not hold is refused" 1 "$TEMPER" evidence contest --stage plan --id 5 --cite src/a.sh:beta --quote 'the alpha helper' --reason x
assert_eq "contest: a comprehension finding is refused, contest and escalate alike" "1|1" \
  "$("$TEMPER" evidence contest --stage plan --id 6 --cite src/a.sh --quote 'the alpha helper prints a' --reason x 2>&1 | grep -c 'never contested or escalated')|$("$TEMPER" evidence escalate --stage plan --id 6 --reason x 2>&1 | grep -c 'never contested or escalated')"
assert_exit "contest: a citation with its quote is recorded" 0 "$TEMPER" evidence contest --stage plan --id 5 --cite src/a.sh:2 --quote 'the alpha helper prints a' --reason "alpha is the helper it names"
assert_eq "contest: the finding stays open and the gate names the citation" "False|1" \
  "$(_fr_row 'no open plan blockers' | cut -d'|' -f1)|$(_fr_row 'no open plan blockers' | grep -c '#5 \[zoom-out\] src/a.sh: a new helper where one exists (contested: src/a.sh:2)')"
assert_eq "contest: the accept question lists the contested finding first, with the citation and the quote as reasons" \
  "Accept finding 5|[contested] [zoom-out] src/a.sh: a new helper where one exists|Contested with evidence: src/a.sh:2|The quoted text answers it: the alpha helper prints a" \
  "$(nx "o = d['ask']['accept']['options'][0]; r = o['reason_question']['options']; '|'.join([o['label'], o['description'], r[0]['label'], r[1]['label']])")"
assert_exit "escalate: a reason is required" 1 "$TEMPER" evidence escalate --stage plan --id 5 --reason "  "
assert_exit "escalate: with a reason it is recorded" 0 "$TEMPER" evidence escalate --stage plan --id 5 --reason "the team agreed on this in the design meeting"
"$TEMPER" evidence accept --stage plan --id 5 --reason "the team agreed" >/dev/null 2>&1; "$TEMPER" evidence accept --stage plan --id 6 --reason "defined in the glossary" >/dev/null 2>&1
assert_exit "accept: the person's accept of both passes the plan gate" 0 "$TEMPER" gate plan
assert_exit "contest: an accepted finding cannot be contested" 1 "$TEMPER" evidence contest --stage plan --id 5 --cite src/a.sh:2 --quote 'the alpha helper prints a' --reason x

# --- 8. Review findings: the same answers, the same marks ---
"$TEMPER" evidence add --stage review --claim 'src/a.sh:2 echo is unquoted' --severity critical >/dev/null 2>&1
"$TEMPER" evidence add --stage review --claim 'src/a.sh:1 the name is vague' --severity critical >/dev/null 2>&1
assert_exit "review: a review finding is contested the same way" 0 "$TEMPER" evidence contest --stage review --id 2 --cite src/a.sh:1 --quote 'the alpha helper prints' --reason "alpha is the domain word"
assert_eq "review: a contested finding still blocks the review gate, and the gate names the citation" "1|1" \
  "$("$TEMPER" gate review >/dev/null 2>&1; echo $?)|$(python3 -c "import json; print(int('(contested: src/a.sh:1)' in json.load(open('.temper/gates.json'))['review']['requirements'][0]['detail']))")"

# --- 9. Spec drift: a finished spec against the tree as it is now; --run runs each scenario's test ---
setup; rm -rf .git; git init -q . 2>/dev/null; git config user.email t@example.com; git config user.name T
mkdir -p src unit; printf 'a\n' > src/a.sh; printf 'b\n' > src/b.sh; printf 'd\n' > src/demo.sh; printf 'exit 0\n' > unit/a_test.sh; printf 'exit 0\n' > unit/b_test.sh
cat > .temper/specs/demo/plan.md <<'EOF'
## Files to Create
| File | Purpose |
|------|---------|
| `src/a.sh` | a |
| `src/b.sh` | b |
EOF
python3 - <<'PY'
p = '.temper/specs/demo/intent.md'
s = open(p).read().replace('  Test: true', '  Test: bash unit/a_test.sh', 1).replace('  Test: true', '  Test: bash unit/b_test.sh', 1)
open(p, 'w').write(s)
PY
echo '{}' > .temper/specs/demo/gate-ledger.json
assert_eq "drift: a spec with no committed ledger is skipped" "[]" "$("$TEMPER" drift --json)"
git add -A >/dev/null 2>&1; git commit -qm "the finished run" >/dev/null 2>&1
assert_eq "drift: a spec the tree still matches has no drift, and its tests pass" "## demo|No drift detected" \
  "$("$TEMPER" drift --run | sed -n '3p;4p' | sed 's/ (since .*//' | paste -sd'|' -)"
printf 'echo "expected 423, got 401"; exit 1\n' > unit/b_test.sh; git add -A >/dev/null 2>&1; git commit -qm "a later change" >/dev/null 2>&1
assert_eq "drift: without --run a failing scenario test is not run" "0" "$("$TEMPER" drift --json | python3 -c "import json,sys; print(len(json.load(sys.stdin)[0]['failing']))")"
assert_eq "drift: --run names the scenario whose test fails now, with its last line" "second|1|expected 423, got 401" \
  "$("$TEMPER" drift --run --json | python3 -c "import json,sys; f=json.load(sys.stdin)[0]['failing'][0]; print('%s|%d|%s' % (f['scenario'], f['exit'], f['last']))")"
rm src/b.sh unit/a_test.sh; printf 'a2\n' > src/a.sh; git add -A >/dev/null 2>&1; git commit -qm "later work" >/dev/null 2>&1
assert_eq "drift: a missing planned file, a test that is gone and a file changed since are each named" \
  "src/b.sh|unit/a_test.sh|first|src/a.sh:1" \
  "$("$TEMPER" drift --json | python3 -c "import json,sys; r=json.load(sys.stdin)[0]; print('|'.join([r['missing'][0], r['tests_gone'][0]['file'], r['tests_gone'][0]['scenario'], '%s:%d' % (r['changed'][0]['file'], r['changed'][0]['commits'])]))")"
assert_exit "drift: it is information, never a failure" 0 "$TEMPER" drift --run

# --- 10. The plugin lists the brief, and the brief has no write tool ---
assert_eq "plugin.json lists the fresh reviewer's brief" "1" "$(grep -c '"./agents/plan-review.md"' "$REPO_ROOT/.claude-plugin/plugin.json")"
assert_eq "the fresh reviewer has no write tool" "tools: Read, Glob, Grep, Bash" "$(grep '^tools:' "$REPO_ROOT/agents/plan-review.md")"
