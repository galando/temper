# Release 9.8.5 case file 21: sourced by test-temper.sh after temper-cases-20.sh; its helpers (nx, vw, fresh, gpass, gfail, labels, m_setup) are used here.

# --- 9.8.5: a filtered verify under a JaCoCo bundle rule fails the plan gate ("maven filtered verify", the last plan row) ---
_pom() { mkdir -p backend; printf '<project><build><plugins><plugin><artifactId>jacoco-maven-plugin</artifactId><executions><execution><goals><goal>check</goal></goals><configuration><rules><rule>%s<limits/></rule></rules></configuration></execution></executions></plugin></plugins></build></project>\n' "$1" > backend/pom.xml; }
_frow() { python3 -E -s "$REPO_ROOT/scripts/gate_rows.py" plan-rows .temper/specs/demo "$PWD" | tail -n 1 | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['name']+'|'+str(d['pass'])+'|'+d['detail'])"; }
_fcheck() { _frow | python3 -c "
import sys; n,p,d=sys.stdin.read().rstrip('\n').split('|',2)
print(n+'|'+p+'|'+'|'.join(str(w in d) for w in sys.argv[1:]))" "$@"; }
FILT='cd backend \&\& mvn -s settings.xml verify -Dtest=SomeTest -DskipITs'
fresh; f9_tasks > .temper/specs/demo/tasks.md
assert_eq "9.8.5: a plan with no Maven command passes the filtered row as skipped" "maven filtered verify|True|skipped: no Maven command" "$(_frow)"
_pom '<element>BUNDLE</element>'
sed -i "s/^\*\*Validate:\*\* \`true\`$/**Validate:** \`$FILT\`/" .temper/specs/demo/tasks.md
assert_eq "9.8.5: a filtered verify under a BUNDLE rule fails, naming Validate, pom, BUNDLE, test and the skip flag" \
  "maven filtered verify|False|True|True|True|True|True" "$(_fcheck 'G1 Validate' backend/pom.xml BUNDLE '`test`' -Djacoco.skip=true)"
_pom ''
assert_eq "9.8.5: a rule with no element counts as BUNDLE" "False" "$(_frow | cut -d'|' -f2)"
_pom '<element>CLASS</element>'
assert_eq "9.8.5: a CLASS rule is not a bundle rule" "True" "$(_frow | cut -d'|' -f2)"
_pom '<element>BUNDLE</element>'
sed -i 's/-Dtest=SomeTest/-Dit.test=X/' .temper/specs/demo/tasks.md
assert_eq "9.8.5: -Dit.test is a filter too" "False" "$(_frow | cut -d'|' -f2)"
sed -i 's/ -Dit.test=X -DskipITs/ -DskipITs -Djacoco.skip=true/' .temper/specs/demo/tasks.md
assert_eq "9.8.5: -Djacoco.skip=true passes the row" "True" "$(_frow | cut -d'|' -f2)"
sed -i 's/-Djacoco.skip=true/-Dtest=SomeTest/' .temper/specs/demo/tasks.md
rm backend/pom.xml; _pom '<other/>'; sed -i 's/<goal>check<\/goal>/<goal>report<\/goal>/' backend/pom.xml
assert_eq "9.8.5: a pom with no jacoco check goal passes" "True" "$(_frow | cut -d'|' -f2)"
_pom '<element>BUNDLE</element>'
sed -i "s/^\*\*Validate:\*\* .*$/**Validate:** \`true\`/; s/^\*\*Test:\*\* \`true\`$/**Test:** \`$FILT\`/" .temper/specs/demo/tasks.md
assert_eq "9.8.5: a task Test is checked the same way, named by its task" "False|True" "$(_frow | cut -d'|' -f2)|$(_fcheck 'G1 Task 1 Test' | grep -c True | sed 's/0/False/; s/1/True/')"
sed -i "s/^\*\*Test:\*\* .*$/**Test:** \`true\`/; s/^\*\*Integration:\*\* .*$/**Integration:** \`$FILT\`/" .temper/specs/demo/tasks.md
assert_eq "9.8.5: an Integration line is checked the same way" "False" "$(_frow | cut -d'|' -f2)"
sed -i "s/^\*\*Integration:\*\* .*$/**Integration:** \`true\`/" .temper/specs/demo/tasks.md
grep -q 'Test:' .temper/specs/demo/intent.md && sed -i "s/^\( *\)Test: .*/\1Test: $FILT/" .temper/specs/demo/intent.md
assert_eq "9.8.5: a scenario Test is checked the same way" "False" "$(_frow | cut -d'|' -f2)"
