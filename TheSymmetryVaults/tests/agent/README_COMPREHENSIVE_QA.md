# Comprehensive QA Test Suite - The Symmetry Vaults

This directory contains a comprehensive test suite for validating all 12 levels of Act 1 through the Agent Bridge.

## Files

- **`test_all_levels_comprehensive.py`** - Main test suite (240 tests across 12 levels)
- **`run_comprehensive_qa.py`** - Test runner with automatic bug documentation
- **`T021_QA_REPORT.md`** - Detailed QA report template
- **`T021_BUGS.json`** - Auto-generated bug report (created after test run)

## Quick Start

### Prerequisites

1. **Godot 4.6+** installed and in PATH (or set `GODOT_PATH` environment variable)
2. **Python 3.8+** with pytest installed
3. **TheSymmetryVaults** project built

Install dependencies:
```bash
pip install pytest
```

### Run All Tests

```bash
cd /c/Cursor/TayfaProject/AndroidGame/TheSymmetryVaults/tests/agent
python run_comprehensive_qa.py
```

### Run Specific Level

```bash
# Test Level 01 only
python run_comprehensive_qa.py --level 01

# Test Level 12 only
python run_comprehensive_qa.py --level 12
```

### Quick Smoke Test

```bash
# Only test Level 01 (fastest way to verify setup)
python run_comprehensive_qa.py --quick
```

## Using pytest Directly

### Run All Tests
```bash
pytest test_all_levels_comprehensive.py -v
```

### Run Specific Level
```bash
pytest test_all_levels_comprehensive.py::TestLevel01 -v
pytest test_all_levels_comprehensive.py::TestLevel05 -v
```

### Run Specific Test Category
```bash
# Test only automorphisms
pytest test_all_levels_comprehensive.py -k "test_10" -v

# Test only keyring functionality
pytest test_all_levels_comprehensive.py -k "test_40" -v

# Test only swap functionality
pytest test_all_levels_comprehensive.py -k "test_70" -v
```

### Run with Detailed Output
```bash
pytest test_all_levels_comprehensive.py -v -s --tb=short
```

## Test Structure

Each level gets tested with 20 tests:

### 1. Metadata Validation (6 tests)
- Level ID, title, group name
- Crystal count and colors
- Edge count
- Initial arrangement (identity)
- Total symmetries

### 2. Automorphism Testing (1 test)
- Submit all valid automorphisms
- Verify each triggers `symmetry_found` event

### 3. Invalid Permutations (1 test)
- Submit invalid permutations
- Verify `invalid_attempt` event

### 4. Level Completion (1 test)
- Find all symmetries
- Verify `level_completed` event

### 5. Keyring Validation (2 tests)
- Keyring updates correctly
- Keyring shows `complete=true` when done

### 6. HUD Labels (3 tests)
- Labels exist in scene tree
- TitleLabel shows correct title
- CounterLabel updates as symmetries found

### 7. Button Functionality (2 tests)
- RESET button exists
- RESET button restores identity arrangement

### 8. Swap Operations (3 tests)
- Valid crystal swaps work
- Swapping same crystal is no-op
- Invalid crystal IDs return errors

### 9. Edge Cases (2 tests)
- Duplicate submissions don't increase count
- Non-existent level loading errors correctly

## Understanding Test Results

### Successful Test Run
```
TestLevel01::test_01_level_metadata PASSED
TestLevel01::test_02_crystal_count PASSED
...
TestLevel12::test_81_load_nonexistent_level_errors PASSED

========== 240 passed in 120.5s ==========
```

### Failed Test Example
```
TestLevel03::test_10_find_all_automorphisms FAILED

AssertionError: Valid automorphism [0, 2, 1] not recognized as symmetry
Expected exactly 1 symmetry_found event, got 0
```

This indicates:
- **Level:** 03 (Colors Matter)
- **Issue:** Automorphism `[0, 2, 1]` not being recognized
- **Root cause:** Possibly color validation bug in SymmetryChecker

## Interpreting Bugs

Bugs are automatically documented in `T021_BUGS.json`:

```json
{
  "timestamp": "2026-02-26T10:30:45",
  "total": 240,
  "passed": 235,
  "failed": 5,
  "bugs": [
    {
      "test_class": "TestLevel03",
      "test_method": "test_10_find_all_automorphisms",
      "level": "03",
      "failure_output": "AssertionError: ..."
    }
  ]
}
```

## Common Issues

### Issue: "godot: command not found"
**Solution:** Set `GODOT_PATH` environment variable:
```bash
export GODOT_PATH="/path/to/godot"
python run_comprehensive_qa.py
```

### Issue: "No module named pytest"
**Solution:** Install pytest:
```bash
pip install pytest
```

### Issue: Tests timeout
**Solution:** Increase timeout in `run_comprehensive_qa.py` (default: 10 minutes)

### Issue: Godot process hangs
**Solution:**
```bash
# Kill any hanging Godot processes
pkill godot
# Re-run tests
python run_comprehensive_qa.py
```

## Test Development

### Adding New Tests

To add tests for a new level:

1. Add level spec to `LEVEL_SPECS` in `test_all_levels_comprehensive.py`
2. Create test class:
```python
class TestLevel13(LevelTestBase):
    level_id = "level_13"
```

All 20 base tests will automatically run for the new level.

### Adding Custom Tests

Add level-specific tests to the test class:

```python
class TestLevel13(LevelTestBase):
    level_id = "level_13"

    def test_90_custom_behavior(self):
        """Test something specific to Level 13."""
        state = self.client.get_state()
        # Custom assertions here
```

## Performance

- **Single Level:** ~5-10 seconds
- **All 12 Levels:** ~2-4 minutes
- **Bottleneck:** Godot startup time (~2-3 seconds per level)

Tests run **sequentially** (cannot be parallelized due to Godot instance conflicts).

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Comprehensive QA Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Install Godot
        run: |
          wget https://downloads.tuxfamily.org/godotengine/4.6/Godot_v4.6-stable_linux.x86_64.zip
          unzip Godot_v4.6-stable_linux.x86_64.zip
          export GODOT_PATH=./Godot_v4.6-stable_linux.x86_64
      - name: Install Python dependencies
        run: pip install pytest
      - name: Run QA tests
        run: cd TheSymmetryVaults/tests/agent && python run_comprehensive_qa.py
```

## Troubleshooting

### Enable Debug Output

```bash
# Full pytest output with no capture
pytest test_all_levels_comprehensive.py -v -s --capture=no

# Show local variables on failure
pytest test_all_levels_comprehensive.py -v -l
```

### Test Single Scenario

```python
# Run just one test method
pytest test_all_levels_comprehensive.py::TestLevel01::test_10_find_all_automorphisms -v -s
```

### Inspect Agent Bridge Communication

Check the protocol files (created in project root during test):
```bash
# Command sent to Godot
cat /c/Cursor/TayfaProject/AndroidGame/TheSymmetryVaults/agent_cmd.jsonl

# Response from Godot
cat /c/Cursor/TayfaProject/AndroidGame/TheSymmetryVaults/agent_resp.jsonl
```

## Support

For issues with the test suite:
1. Check `T021_QA_REPORT.md` for expected behavior
2. Review `T021_BUGS.json` for known issues
3. Run with `--verbose` for detailed output
4. Check Agent Bridge logs in Godot console

---

**Created for Task T021**
**QA Tester:** Claude Agent
**Last Updated:** 2026-02-26
