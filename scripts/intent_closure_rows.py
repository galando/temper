"""intent_closure_rows.py ACCEPTANCE_PY INTENT.md: the rows "out of scope stated" and "open questions resolved" of the Intent gate.

Moved out of scripts/temper so it stays under the plugin directory's 256 KiB file limit. Standard library only.
"""
import importlib.util, json, os, re, sys
_spec = importlib.util.spec_from_file_location('acceptance', sys.argv[1])
A = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(A)
# the intent's status and Blocking questions, read as flow.py and gate_rows.py read them (next to acceptance.py)
_spec = importlib.util.spec_from_file_location('intent_parse', os.path.join(os.path.dirname(sys.argv[1]), 'intent_parse.py'))
IP = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(IP)

lines = open(sys.argv[2]).read().splitlines()
reqs = []
def add(name, ok, detail):
    reqs.append({'name': name, 'pass': ok, 'detail': detail})

status = IP.status("\n".join(lines))   # None: missing or unknown Status header

# Both requirements apply only while the intent is a draft: a recorded acceptance is never
# revisited, so an accepted or completed intent skips them with a PASS.
SKIP = ('skipped \u2014 intent is %s; this check applies to drafts only (a recorded acceptance is never revisited)' % status
        if status else
        'skipped: no recognized Status header (draft, accepted or completed); this check applies to drafts only, and the status header requirement reports the missing header')

# --- out of scope stated: a '- Out of scope:' bullet with non-placeholder text ----------
scope = A.section_lines(lines, 'Scope and Non-goals') or A.section_lines(lines, 'Scope')
found = False
for l in scope:
    om = re.match(r'^\s*-\s*Out of scope:\s*(.*?)\s*$', l, re.I)
    if om and re.search(r'[A-Za-z0-9]', A.blank_placeholders(om.group(1))):
        found = True
        break
if status != 'draft':   # explicitly draft only
    add('out of scope stated', True, SKIP)
else:
    add('out of scope stated', found,
        'Scope states what is out of scope' if found
        else 'no "- Out of scope:" bullet with real text under ### Scope and Non-goals')

# --- open questions resolved: a draft reports its Blocking questions (informational) -------
# Drafts legitimately carry Blocking questions (the shipped example does), so this never fails
# a draft; it names what is still open so the person answers it before accepting.
if status != 'draft':
    add('open questions resolved', True, SKIP)
else:
    blocking = [('Blocking: ' + q)[:60] for q in IP.blocking("\n".join(lines))]
    add('open questions resolved', True,
        'no Blocking question remains' if not blocking
        else '%d Blocking question(s) still open on the draft; answer them into ### Decisions before accepting: %s' % (len(blocking), ' | '.join(blocking)))
print("\n".join(json.dumps(r) for r in reqs))
