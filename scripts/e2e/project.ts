// The files a scripted Plan agent writes, and the project the scripted Build agents work in. Generated once from a run that
// passed `temper gate intent` and `temper gate plan`; the text is what the e2e checks the CLI against.
export const INTENT_SCENARIOS = "## Scenarios (BDD)\n\n#### Happy Path\n\n```gherkin\nScenario: CI JSON shape is stable across a run\n  Given a run with two stages\n  When the CI report is built\n  Then each stage is one object with stage, verdict and requirements\n  Note: unit\n  Covers: AC-01\n  Test: python3 -m unittest unit.test_ci_shape\n```\n\n```gherkin\nScenario: Override rows name the approver\n  Given a run with one override\n  When the CI report is built\n  Then the override row names the approver\n  Note: manual\n  Covers: AC-02\n  Test: python3 -m unittest unit.test_ci_shape\n```\n\n```gherkin\nScenario: Same ledger gives the same bytes\n  Given one ledger\n  When the CI report is built twice\n  Then both documents are byte for byte equal\n  Note: unit\n  Covers: AC-03\n  Test: python3 -m unittest unit.test_ci_bytes\n```\n\n"
export const PLAN_MD = "# Plan: CI report\n\n## Context Map\n\n- use: intent.md AC-01, AC-03 - the accepted scope\n- use: src/ (2 files) - where the report code goes\n- reviewed: auto - every source is current and on topic\n\n## Architecture\n\nA small module builds the report; a second one fixes its byte order.\n\n## Blast Radius\n\nTwo new modules and their tests. Nothing else reads them yet.\n\n## Cross-Repo Search\n\n- not available: no cross-repo search tool is connected, so local tools were used.\n\n## Files to Create\n\n| File | Purpose | Traced to |\n|------|---------|-----------|\n| src/ci_shape.py | builds the stage objects | CI JSON shape is stable across a run |\n| unit/test_ci_shape.py | tests the shape | CI JSON shape is stable across a run |\n| src/ci_bytes.py | writes the document in a fixed order | Same ledger gives the same bytes |\n| unit/test_ci_bytes.py | tests the byte order | Same ledger gives the same bytes |\n\n## Files to Modify\n\n| File | Change | Traced to |\n|------|--------|-----------|\n"
export const TASKS_MD = "# Tasks: CI report\n\n**Integration:** `python3 -m unittest discover -s unit -t .`\n\n## Group G1: Shape\n**Depends:** none\n**Validate:** `python3 -m unittest unit.test_ci_shape`\n**Context:**\nPlain python, standard library only.\n\n### Task 1: Stage objects\n**File:** `src/ci_shape.py`, `unit/test_ci_shape.py`\n**Depends:** none\n**Test:** `python3 -m unittest unit.test_ci_shape`\n**Cases:**\n- a stage becomes an object with stage, verdict and requirements\n- a stage with no requirements keeps an empty requirements array\n**Traced to:** Scenario: \"CI JSON shape is stable across a run\"\n- [ ] done\n\n## Group G2: Bytes\n**Depends:** G1\n**Validate:** `python3 -m unittest unit.test_ci_bytes`\n**Context:**\nPlain python, standard library only.\n\n### Task 2: Byte order\n**File:** `src/ci_bytes.py`, `unit/test_ci_bytes.py`\n**Depends:** none\n**Test:** `python3 -m unittest unit.test_ci_bytes`\n**Cases:**\n- the same ledger gives the same bytes twice\n- two stages are written in the order the ledger holds them\n**Traced to:** Scenario: \"Same ledger gives the same bytes\"\n- [ ] done\n"
export const BASE_FILES: Record<string, string> = {
  'README.md': '# scratch\n',
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
