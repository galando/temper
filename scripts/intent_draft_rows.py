"""intent_draft_rows.py ACCEPTANCE_PY INTENT.md: the draft intent rows of the Intent gate, one JSON object per line.

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
if status != 'draft':
    d = ("skipped — intent is %s; this check applies to drafts only "
         "(a recorded acceptance is never revisited)") % status
    if status is None:
        # A missing or unknown Status header is reported by the gate's own status header
        # row; these rows say why they skipped instead of printing Python's None.
        d = ("skipped: no recognized Status header (draft, accepted or completed); this check "
             "applies to drafts only, and the status header requirement reports the missing header")
    for name in ('task context recorded', 'criteria why', 'target users action chain',
                 'criteria ids', 'criteria priority', 'criteria validate',
                 'open questions labeled', 'no duplicate question', 'header fields',
                 'no scenarios in draft', 'no soft words'):
        add(name, True, d)
    print("\n".join(json.dumps(r) for r in reqs))
    sys.exit(0)

def sec(name):
    return A.section_lines(lines, name)

def bullets_with_blocks(sec_lines):
    """Real (non-placeholder) bullets with their continuation blocks."""
    out, cur = [], None
    for l in sec_lines:
        if A.BULLET_RE.match(l):
            if cur: out.append(cur)
            content = A.strip_checkbox(l)
            cur = {'first': content, 'block': [l], 'placeholder': content.startswith('{')}
        elif cur is not None:
            cur['block'].append(l)
    if cur: out.append(cur)
    return [b for b in out if not b['placeholder']]

# --- task context recorded -------------------------------------------------
ctx = sec('Source Traceability')
ctx_lines = [l for l in ctx if re.match(r'^\s*-\s*(consulted|unavailable|none):', l, re.I)]
unaccounted = []
if ctx_lines:
    ctx_text = "\n".join(ctx_lines)
    tk = re.search(r'^\*\*Ticket:\*\*\s*(.+?)\s*$', "\n".join(lines), re.I | re.M)
    raw = A.blank_placeholders(tk.group(1)).strip() if tk else ''
    keys = re.findall(r'[A-Z][A-Z0-9]+-[0-9]+|#[0-9]+|![0-9]+', raw) if raw else []
    for k in keys:
        # whole-token match: no alnum may sit immediately before or after the
        # key — a recorded PROJ-12 must not satisfy a linked PROJ-1.
        if not re.search(r'(?<![A-Za-z0-9])' + re.escape(k) + r'(?![A-Za-z0-9])', ctx_text):
            unaccounted.append(k)
if not ctx_lines or unaccounted:
    if not ctx_lines:
        add('task context recorded', False,
            'no consulted/unavailable/none line under ## Source Traceability — record every linked source')
    else:
        add('task context recorded', False,
            'ticket key(s) never accounted for on a consulted/unavailable line: ' + ' | '.join(unaccounted))
else:
    add('task context recorded', True, '%d source line(s) recorded under Source Traceability' % len(ctx_lines))

# --- criteria family -------------------------------------------------------
crits = [c for c in A.parse_criteria(sec('Success Criteria')) if not c.get('placeholder')]

no_id = [c['first_line'][:40] for c in crits if not c.get('id')]
seen, dups = set(), []
for c in crits:
    if c.get('id') and c['id'] in seen and c['id'] not in dups:
        dups.append(c['id'])
    elif c.get('id'):
        seen.add(c['id'])
if no_id or dups:
    parts = (['duplicate id: ' + d for d in dups] + ['no AC-NN id: ' + s for s in no_id])
    add('criteria ids', False, ' | '.join(parts))
elif not crits:
    add('criteria ids', False, 'no real criteria found')
else:
    add('criteria ids', True, '%d criterion id(s), all unique' % len(crits))

def label(c):
    return c.get('id') or c['first_line'][:40]

no_prio = [label(c) for c in crits if not c.get('priority')]
add('criteria priority', not no_prio,
    'every criterion carries [required]/[optional]' if not no_prio
    else 'no [required]/[optional] on first line of: ' + ' | '.join(no_prio))

bad_v = [label(c) for c in crits if not c['has_validate'] or c['vtype'] not in A.VALIDATE_TYPES]
add('criteria validate', not bad_v,
    'every criterion has a Validate: type' if not bad_v
    else 'missing/unknown Validate: type on: ' + ' | '.join(bad_v))

no_why = [label(c) for c in crits if not c['why']]
add('criteria why', not no_why,
    'every criterion states the outcome or risk it serves' if not no_why
    else 'no Why: line with real text on: ' + ' | '.join(no_why))

# --- target users action chain --------------------------------------------
tusers = bullets_with_blocks(sec('Target Users'))
bad_u = [' '.join(b['block'])[:60] for b in tusers
         if not any(('→' in l or '->' in l) for l in b['block'])]
add('target users action chain', not bad_u,
    'every Target Users bullet is an action chain (user: does -> next)' if not bad_u
    else 'no action chain (→ or ->) on: ' + ' | '.join(bad_u))

# --- open questions --------------------------------------------------------
def norm_q(text):
    t = A.BULLET_RE.sub('', text)
    t = re.sub(r'^\s*\|', '', t)
    t = re.sub(r'^\s*(\[[^\]]*\]|Blocking:|Deferred:)', '', t, flags=re.I)
    t = t.replace('**', '').lower()
    t = re.sub(r'[^a-z0-9 ]', ' ', t)
    return [w for w in t.split()][:8]

oq = bullets_with_blocks(sec('Open Questions'))
unlabeled = [b['first'][:50] for b in oq
             if not re.search(r'\b(blocking|deferred)\b', ' '.join(b['block']), re.I)]
add('open questions labeled', not unlabeled,
    'every open question is labeled Blocking or Deferred' if not unlabeled
    else 'neither blocking nor deferred on: ' + ' | '.join(unlabeled))

dup_q = []
if oq:
    topics = []
    for l in sec('Decisions'):
        d = A.BULLET_RE.sub('', l)
        if '->' in d:
            topics.append(norm_q(d.split('->', 1)[0]))
    for b in oq:
        q = norm_q(b['first'])
        for t in topics:
            if not q or not t:
                continue
            shorter, longer = (q, t) if len(q) <= len(t) else (t, q)
            if len(shorter) >= 4 and longer[:len(shorter)] == shorter:
                dup_q.append(b['first'][:50])
                break
add('no duplicate question', not dup_q,
    'no open question re-asks something already decided' if not dup_q
    else 'already answered in ### Decisions: ' + ' | '.join(dup_q))

# --- header fields ---------------------------------------------------------
missing_h = []
# 9.8.0: Reviewer is optional. The person who accepts the intent at the gate is its approver (Accepted-by); a named
# reviewer is welcome but never required, so the Intent stage no longer asks for one (a question that looped runs).
for f in ('Author', 'Created'):
    hm = re.search(r'^\*\*' + f + r':\*\*\s*(.+?)\s*$', "\n".join(lines), re.I | re.M)
    val = A.blank_placeholders(hm.group(1)).strip() if hm else ''
    if not val:
        missing_h.append(f)
add('header fields', not missing_h,
    'Author and Created present' if not missing_h
    else 'missing, empty, or placeholder: ' + ' | '.join(missing_h))

# --- no scenarios in draft -------------------------------------------------
scen = A.scenario_lines(lines)
add('no scenarios in draft', not scen,
    'no Scenario: lines — Plan writes the scenarios' if not scen
    else 'Scenario: line(s) at ' + ' | '.join(str(n) for _, n in scen))

# --- no soft words ---------------------------------------------------------
# A criterion or constraint states what is required. should/may/might/possibly leave
# the reader to guess. A statement that carries a (source: ...) marker is exempt: the
# hedge word belongs to the originator, and ### Decisions records what it means.
SOFT_RE = re.compile(r'\b(should|may|might|possibly)\b', re.I)
META_RE = re.compile(r'^\s*(Why|Validate|Deferred|Blocking):', re.I)

def statements(sec_lines):
    """(label, statement text) per real bullet. The statement is the bullet line plus
    its wrapped continuation lines, up to the first Why:/Validate:/Deferred: line."""
    out, cur = [], None
    in_fence = False
    for l in sec_lines:
        if re.match(r'^\s*(`{3,}|~{3,})', l):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if A.BULLET_RE.match(l):
            if cur: out.append(cur)
            content = A.strip_checkbox(l)
            if content.startswith('{'):
                cur = None
                continue
            m = re.match(r'^(AC-\d+)\b', content)
            cur = {'label': m.group(1) if m else '"%s"' % content[:30], 'text': [content], 'open': True}
        elif cur is not None and cur['open']:
            if META_RE.match(l):
                cur['open'] = False
            elif l.strip():
                cur['text'].append(l.strip())
    if cur: out.append(cur)
    return [(c['label'], ' '.join(c['text'])) for c in out]

soft = []
for kind, sname in (('criterion', 'Success Criteria'), ('constraint', 'Constraints')):
    for lab, text in statements(sec(sname)):
        if re.search(r'\(source:', text, re.I):
            continue
        body = re.sub(r'`[^`]*`', ' ', text)
        words = []
        for w in SOFT_RE.findall(body):
            if w.lower() not in words:
                words.append(w.lower())
        if words:
            soft.append('%s %s uses %s' % (kind, lab, ', '.join(words)))
add('no soft words', not soft,
    'no should/may/might/possibly in a criterion or constraint without a (source: ...) marker' if not soft
    else 'soft word in: ' + ' | '.join(soft))

print("\n".join(json.dumps(r) for r in reqs))
