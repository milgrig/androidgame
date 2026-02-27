# Testing Rules

## Mandatory Autotests

Autotests are **mandatory part of Definition of Done**. Task is not complete if:
- Code not covered by autotests (where applicable)
- Existing tests fail

---

## Test Classification

### Fast Tests

**Characteristic:** Don't require app launch, no UI interaction, don't disturb user.

| Type | Description | Examples |
|------|-------------|----------|
| Unit tests | Testing individual functions/classes | pytest, jest, vitest |
| Integration (no UI) | Testing module interaction | API tests, DB tests |
| Snapshot tests | Comparing output with reference | React snapshot testing |

**When to run:**
- ✅ On every commit (CI/CD)
- ✅ Before marking task as `done`
- ✅ During local development

**Command:** `npm test` / `pytest` / project-specific

---

### Slow Tests

**Characteristic:** Require app launch, capture mouse/keyboard, **disturb user**.

| Type | Description | Examples |
|------|-------------|----------|
| E2E (end-to-end) | Full user scenario | Playwright, Cypress, Selenium |
| UI autotests | Automation via interface | pyautogui, robot framework |
| Visual regression | Screenshot comparison | Percy, Chromatic |

**When to run:**
- ⚠️ On request (not automatically)
- ⚠️ Before release / sprint finalization
- ⚠️ Night (scheduled CI)
- ❌ NOT on every commit

**Important:** Slow tests **capture control** — warn the user!

```
⚠️ Warning: Running E2E tests.
Tests will take ~X minutes and control mouse/keyboard.
Do not touch the computer until completion.
```

---

## Project Test Structure

```
tests/
├── fast/                 # Fast tests
│   ├── unit/            # Unit tests
│   └── integration/     # Integration (no UI)
└── slow/                 # Slow tests
    ├── e2e/             # End-to-end
    └── visual/          # Visual regression
```

Or via markers/tags in test framework:
- `@fast` / `@slow`
- `pytest -m "not slow"` — fast only
- `pytest -m slow` — slow only

---

## When to Write Which Tests

### New Feature Development

| Stage | Test Type |
|-------|-----------|
| Development | Unit tests for logic |
| Integration | Integration tests |
| Before PR | All fast tests pass |
| Before release | E2E for critical path |

### Bug Fixing

1. Write test that reproduces bug (should fail)
2. Fix the bug
3. Test should pass

---

## Test Suite Management

### Adding New Tests

New tests are **added** to mandatory suite automatically — just put in `tests/fast/`.

### Changing/Removing Old Tests

Tests **can be removed or changed** if:
- Functionality removed from product
- Test was for deprecated behavior
- Test was incorrect (false positive/negative)

**Procedure:**
1. Create task "Test revision" with reasons
2. Get confirmation from qa_tester
3. Remove/change tests
4. Document in PR/commit

### Flaky Tests (unstable)

Tests that pass/fail randomly:
1. Mark `@flaky` or `@skip`
2. Create task to fix
3. Either fix or remove

**Cannot:** ignore flaky tests without documentation.

---

## Checklist for qa_tester

When checking task:

- [ ] Fast tests pass (`pytest tests/`)
- [ ] New code covered by tests (if applicable)
- [ ] Existing tests not broken
- [ ] If critical feature — E2E test exists
- [ ] **Game launches** without SCRIPT ERRORs
- [ ] **All new buttons pressed** via Agent Bridge `press_button`
- [ ] **Navigation works** between affected scenes

On sprint finalization:

- [ ] All fast tests pass
- [ ] **`test_full_flow.py` passes** (19/19 checks or more)
- [ ] Run slow tests (E2E)
- [ ] Visual regression (if exists)
- [ ] **Full navigation verified**: MainMenu ↔ MapScene ↔ LevelScene
- [ ] **Every button in the game** appears in `list_actions` and can be pressed

---

## CI/CD Integration

```yaml
# GitHub Actions example
on: [push, pull_request]

jobs:
  fast-tests:
    runs-on: ubuntu-latest
    steps:
      - run: npm test  # Fast tests on every push

  slow-tests:
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'  # Only on merge to main
    steps:
      - run: npm run test:e2e  # Slow tests
```

---

## Smoke Test — Game Must Launch (MANDATORY)

**The game must actually launch and be navigable.** This is non-negotiable.

Before ANY task is marked `done` or ANY sprint is finalized:

1. **Run `tests/agent/test_full_flow.py`** — must pass ALL checks
2. **Zero SCRIPT ERRORs** in Godot console output
3. **Full navigation verified**: MainMenu → MapScene → LevelScene → MapScene → MainMenu

```bash
cd TheSymmetryVaults
python tests/agent/test_full_flow.py
# Expected: ALL TESTS PASSED — GAME IS NAVIGABLE
```

**If `test_full_flow.py` fails → the build is BROKEN → sprint CANNOT be finalized.**

### What the Smoke Test Verifies

| Step | Check |
|------|-------|
| MainMenu loads | Scene tree contains MainMenu node |
| Buttons exist | Start, Settings, Exit buttons are visible and pressable |
| Start → Map | Press Start navigates to MapScene |
| Map has halls | 12 halls visible, at least 1 available |
| Level loads | `load_level` from MapScene works |
| Level state valid | Crystals present, keyring initialized, is shuffled |
| Gameplay works | `submit_permutation` returns `symmetry_found` event |
| Level has UI | Buttons present in level scene |
| Back to map | `navigate("map")` returns to MapScene |
| Back to menu | `navigate("main_menu")` returns to MainMenu |

---

## Button Press Rule — "Not Pressed = Not Tested"

**Every new button added to the game MUST be physically pressed via Agent Bridge.**

### Rules:

1. **New button → must be pressed in test.** If a task adds a button (UI, menu, HUD), QA MUST press it via `press_button` command and verify the result.
2. **Reading code is NOT testing.** Seeing `Button.new()` in GDScript does not mean the button works. It must be pressed.
3. **If QA didn't press it → not tested → task not done.**

### How to Press Buttons:

```python
# List all pressable buttons
actions = client._send_command("list_actions", {})
buttons = [a for a in actions["data"]["actions"] if a["action"] == "press_button"]

# Press a specific button
client._send_command("press_button", {"path": "/root/MainMenu/ButtonContainer/StartButton"})
```

### Checklist for Button Testing:

- [ ] All new buttons appear in `list_actions` response
- [ ] Each new button was pressed via `press_button` command
- [ ] After pressing — expected navigation/state change occurred
- [ ] Button text is correct (matches design spec)

---

## Agent Bridge Commands Reference

QA tester has these commands available via `client._send_command()`:

| Command | Args | Description |
|---------|------|-------------|
| `get_state` | — | Full game state (crystals, keyring, etc.) |
| `get_tree` | `root`, `max_depth` | Scene tree inspection |
| `list_actions` | — | All pressable buttons and actions |
| `press_button` | `path` | Press any BaseButton by node path |
| `load_level` | `level_id` | Load level (works from any scene) |
| `submit_permutation` | `mapping` | Submit crystal permutation |
| `swap` | `i`, `j` | Swap two crystals |
| `get_events` | — | Read event queue |
| `get_map_state` | — | Hall states, progression, available halls |
| `navigate` | `to` (`main_menu`/`map`/level_id) | Navigate between scenes |
| `quit` | — | Shutdown game (MANDATORY) |

---

## Definition of Done (tests)

Task is complete if:

✅ Fast tests pass
✅ New code covered by unit tests
✅ Existing tests not broken
✅ For critical changes — E2E test added/updated
✅ **Smoke test passes** (`test_full_flow.py` — ALL checks green)
✅ **All new buttons pressed** via Agent Bridge
✅ **Zero SCRIPT ERRORs** in Godot console
