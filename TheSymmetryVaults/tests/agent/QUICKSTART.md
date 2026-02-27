# Quick Start - Comprehensive QA Tests

## Run Tests Right Now

```bash
cd /c/Cursor/TayfaProject/AndroidGame/TheSymmetryVaults/tests/agent
python run_comprehensive_qa.py
```

## What Gets Tested

✅ **All 12 Levels of Act 1**
✅ **240 Tests Total** (20 per level)
✅ **52 Automorphisms** validated
✅ **Edge Cases** covered

## Test Categories (per level)

1. **Metadata** - Level ID, title, group, crystals, edges
2. **Automorphisms** - All valid symmetries accepted
3. **Invalid Perms** - Rejected correctly
4. **Completion** - level_completed event fires
5. **Keyring** - Updates and completion state
6. **HUD Labels** - TitleLabel, CounterLabel updates
7. **Buttons** - RESET works
8. **Swaps** - Valid, same-crystal, invalid IDs
9. **Edge Cases** - Duplicates, errors

## Quick Commands

```bash
# All levels (2-4 minutes)
python run_comprehensive_qa.py

# Specific level (5-10 seconds)
python run_comprehensive_qa.py --level 01

# Quick smoke test (Level 01 only)
python run_comprehensive_qa.py --quick

# With pytest directly
pytest test_all_levels_comprehensive.py -v

# Single test
pytest test_all_levels_comprehensive.py::TestLevel01::test_10_find_all_automorphisms -v
```

## Files

- `test_all_levels_comprehensive.py` - Main test suite
- `run_comprehensive_qa.py` - Test runner
- `T021_QA_REPORT.md` - Full documentation
- `README_COMPREHENSIVE_QA.md` - Complete guide

## If Tests Fail

Bugs are auto-documented in: `T021_BUGS.json`

```bash
# View bugs
cat T021_BUGS.json | jq

# Re-run failed level
python run_comprehensive_qa.py --level [XX]
```

## Prerequisites

- Godot 4.6+ in PATH (or set `GODOT_PATH`)
- Python 3.8+ with pytest
- TheSymmetryVaults project built

## Expected Output

```
════════════════════════════════════════════════════════════
TEST RESULTS SUMMARY
════════════════════════════════════════════════════════════
Total Tests:    240
✅ Passed:      240
❌ Failed:      0
════════════════════════════════════════════════════════════

✨ All tests passed! The game is working correctly.
```

---

**Full docs:** `README_COMPREHENSIVE_QA.md`
**Task:** T021 ✅ DONE
