# Tasks: {Feature Name}

**Integration:** `{full suite command, run once after the last group}`

## Group G1: {title}
**Depends:** none
**Validate:** `{group level test command}`
**Context:**
What a builder of this group needs, in under 4096 bytes: the pack rules that apply to this
group in your own words (security rules always), the conventions to follow, the interfaces
the group must keep, and which code from earlier tasks the tests call for real.

### Task 1: {description}
**File:** `src/parser.py`, `tests/test_parser.py`
**Depends:** none
**Test:** `pytest tests/test_parser.py -q`
**Cases:**
- `parse("a,b")` returns `["a", "b"]`
- `parse("")` returns `[]`
- `parse('"a')` raises `ValueError("unclosed quote")`
**Traced to:** Scenario: "{scenario name}"
- [ ] done

### Task 2: {description}
**File:** `src/printer.py`, `tests/test_printer.py`
**Depends:** Task 1
**Test:** `pytest tests/test_printer.py -q`
**Cases:**
- one parsed item prints one line
- no items prints `nothing to report` and returns 0
**Traced to:** Scenario: "{name 1}", "{name 2}"
- [ ] done

## Group G2: {title}
**Depends:** G1
**Validate:** `{group level test command}`
**Context:**
Distilled rules and conventions for G2.

### Task 3: {description}
**File:** `src/main.py`, `tests/test_main.py`
**Depends:** none
**Test:** `pytest tests/test_main.py -q`
**Cases:**
- `main(["--help"])` prints the usage and returns 0
- an unknown flag prints the usage and returns 2
**Traced to:** Infrastructure: required by G1
- [ ] done
