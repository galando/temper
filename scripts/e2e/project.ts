// The files a scripted Plan agent writes, and the project the scripted Build agents work in. Generated once from a run that
// passed `temper gate intent` and `temper gate plan`; the text is what the e2e checks the CLI against. WP26: in the shape
// Plan writes: a scenario is a name, one Then line, Covers and Test; tasks.md has no Traced to line; plan.md (written above
// the simple tier only) is a Context Map and a Blast Radius.
export const INTENT_SCENARIOS = "## Scenarios (BDD)\n\n#### Happy Path\n\n```gherkin\nScenario: CI JSON shape is stable across a run\n  Then each stage is one object with stage, verdict and requirements\n  Covers: AC-01\n  Test: python3 -m unittest unit.test_ci_shape\n```\n\n```gherkin\nScenario: Override rows name the approver\n  Then the override row names the approver\n  Covers: AC-02\n  Test: python3 -m unittest unit.test_ci_shape\n```\n\n```gherkin\nScenario: Same ledger gives the same bytes\n  Then both documents are byte for byte equal\n  Covers: AC-03\n  Test: python3 -m unittest unit.test_ci_bytes\n```\n\n"
export const PLAN_MD = "# Plan: CI report\n\n## Context Map\n\n- use: intent.md AC-01, AC-03 - the accepted scope\n- use: src/ (2 files) - where the report code goes\n- reviewed: pending\n\n## Blast Radius\n\nNothing outside the declared files reads the two new modules yet.\n"
export const TASKS_MD = "# Tasks: CI report\n\n**Integration:** `bash suite.sh`\n\n## Group G1: Shape\n**Depends:** none\n**Validate:** `python3 -m unittest unit.test_ci_shape`\n**Context:**\nPlain python, standard library only.\n\n### Task 1: Stage objects\n**File:** `src/ci_shape.py`, `unit/test_ci_shape.py`\n**Depends:** none\n**Test:** `python3 -m unittest unit.test_ci_shape`\n**Cases:**\n- a stage becomes an object with stage, verdict and requirements\n- a stage with no requirements keeps an empty requirements array\n- [ ] done\n\n## Group G2: Bytes\n**Depends:** G1\n**Validate:** `python3 -m unittest unit.test_ci_bytes`\n**Context:**\nPlain python, standard library only.\n\n### Task 2: Byte order\n**File:** `src/ci_bytes.py`, `unit/test_ci_bytes.py`\n**Depends:** none\n**Test:** `python3 -m unittest unit.test_ci_bytes`\n**Cases:**\n- the same ledger gives the same bytes twice\n- two stages are written in the order the ledger holds them\n- [ ] done\n"
// The whole suite, behind one script: each run appends a line to the file TEMPER_E2E_COUNT names (the floor's
// `suite_runs`), then runs the tests. The config's test and coverage commands and the Integration line of tasks.md name it.
export const SUITE = 'bash suite.sh'
export const SUITE_SH = '[ -n "${TEMPER_E2E_COUNT:-}" ] && echo suite >> "$TEMPER_E2E_COUNT"\nexec python3 -m unittest discover -s unit -t .\n'
export const BASE_FILES: Record<string, string> = {
  'README.md': '# scratch\n',
  'suite.sh': SUITE_SH,
  '.gitignore': '__pycache__/\n',
  'src/__init__.py': '',
  'unit/__init__.py': '',
}
export const SHAPE_TEST = `import unittest

from src.ci_shape import stage_object


class ShapeTest(unittest.TestCase):
    def test_a_stage_becomes_an_object(self):
        self.assertEqual(stage_object('build', 'PASS', [{'name': 'a', 'pass': True, 'detail': 'ok'}]),
                         {'stage': 'build', 'verdict': 'PASS', 'requirements': [{'name': 'a', 'pass': True, 'detail': 'ok'}]})

    def test_a_stage_with_no_requirements_keeps_an_empty_array(self):
        self.assertEqual(stage_object('plan', 'PASS', [])['requirements'], [])
`
export const SHAPE_STUB = 'def stage_object(stage, verdict, requirements):\n    raise NotImplementedError\n'
export const SHAPE_CODE = 'def stage_object(stage, verdict, requirements):\n    return {"stage": stage, "verdict": verdict, "requirements": list(requirements)}\n'
export const BYTES_TEST = `import unittest

from src.ci_bytes import document


class BytesTest(unittest.TestCase):
    def test_the_same_ledger_gives_the_same_bytes(self):
        ledger = [{'stage': 'build', 'verdict': 'PASS', 'requirements': []}]
        self.assertEqual(document(ledger), document(ledger))

    def test_stages_keep_the_ledger_order(self):
        ledger = [{'stage': 'b', 'verdict': 'PASS', 'requirements': []}, {'stage': 'a', 'verdict': 'FAIL', 'requirements': []}]
        self.assertTrue(document(ledger).index('"b"') < document(ledger).index('"a"'))
`
export const BYTES_STUB = 'def document(ledger):\n    raise NotImplementedError\n'
export const BYTES_CODE = 'import json\n\n\ndef document(ledger):\n    return json.dumps(ledger, sort_keys=True, separators=(",", ":"))\n'
