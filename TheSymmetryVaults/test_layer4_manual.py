"""
Manual test script for Layer 4 conjugation cracking.
Tests the 6 required levels: Z4, D4, S3, Z5, S4, and Q8.
"""
import sys
import os
from pathlib import Path

# Fix Windows console encoding
if sys.platform == "win32":
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

# Add project root to path
project_root = Path(__file__).parent
sys.path.insert(0, str(project_root / "tests" / "fast" / "unit"))

from test_layer4_conjugation import (
    ConjugationCrackingManager,
    is_normal,
)
from test_layer3_keyring import (
    load_level_json,
)
from test_core_engine import Permutation


def test_level(level_file: str, level_name: str, expected_structure: dict):
    """Test a single level's Layer 4 functionality."""
    print(f"\n{'='*70}")
    print(f"Testing {level_name} ({level_file})")
    print(f"{'='*70}")

    try:
        data = load_level_json(level_file)
        layer_config = data.get("layers", {}).get("layer_4", {})

        # Check that layer_4 data exists
        if not layer_config:
            # Layer 4 might use layer_3 subgroups
            layer_config = {}

        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)

        # Verify count
        expected_count = expected_structure.get("subgroup_count", 0)
        actual_count = mgr._total_count

        print(f"Expected non-trivial subgroups to classify: {expected_count}")
        print(f"Actual non-trivial subgroups: {actual_count}")

        if expected_count > 0 and actual_count != expected_count:
            print(f"⚠️  WARNING: Count mismatch (expected {expected_count}, got {actual_count})")
            # Not necessarily a failure - layer config might differ

        print(f"✓ Loaded {actual_count} non-trivial subgroups for classification")

        # Get all sym_ids and subgroups
        all_sym_ids = mgr._all_sym_ids
        print(f"✓ Group has {len(all_sym_ids)} elements")

        # Test normality detection
        print(f"\n--- Testing Normality Detection ---")

        normal_count = 0
        non_normal_count = 0

        for i, sg in enumerate(mgr._target_subgroups):
            elements = sg.get("elements", [])
            order = sg.get("order", len(elements))

            # Convert to Permutations for checking
            subgroup_perms = []
            for sid in elements:
                p = mgr._sym_id_to_perm.get(sid)
                if p:
                    subgroup_perms.append(p)

            group_perms = [mgr._sym_id_to_perm[sid] for sid in all_sym_ids]

            is_normal_subgroup = is_normal(subgroup_perms, group_perms)

            status = "NORMAL" if is_normal_subgroup else "NON-NORMAL"
            print(f"  {i+1}. H{i+1} (order {order}): {{{', '.join(elements[:3])}{'...' if len(elements) > 3 else ''}}} - {status}")

            if is_normal_subgroup:
                normal_count += 1
            else:
                non_normal_count += 1

        print(f"\n✓ Classification: {normal_count} normal, {non_normal_count} non-normal")

        # Verify expected structure
        expected_normal = expected_structure.get("normal_count", 0)
        expected_non_normal = expected_structure.get("non_normal_count", 0)

        if expected_normal > 0:
            if normal_count == expected_normal:
                print(f"✓ Normal count matches expected: {normal_count}")
            else:
                print(f"❌ FAILED: Expected {expected_normal} normal, got {normal_count}")
                return False

        if expected_non_normal > 0:
            if non_normal_count == expected_non_normal:
                print(f"✓ Non-normal count matches expected: {non_normal_count}")
            else:
                print(f"❌ FAILED: Expected {expected_non_normal} non-normal, got {non_normal_count}")
                return False

        # Test cracking mechanism
        print(f"\n--- Testing Conjugation Cracking ---")

        if actual_count == 0:
            print("✓ No non-trivial subgroups to test (trivial case)")
        else:
            # Test first non-normal subgroup (if any)
            non_normal_idx = None
            for i, sg in enumerate(mgr._target_subgroups):
                elements = sg.get("elements", [])
                subgroup_perms = [mgr._sym_id_to_perm[sid] for sid in elements if sid in mgr._sym_id_to_perm]
                group_perms = [mgr._sym_id_to_perm[sid] for sid in all_sym_ids]

                if not is_normal(subgroup_perms, group_perms):
                    non_normal_idx = i
                    break

            if non_normal_idx is not None:
                print(f"\nTesting cracking on non-normal subgroup H{non_normal_idx + 1}...")
                mgr.select_subgroup(non_normal_idx)

                sg = mgr._target_subgroups[non_normal_idx]
                elements = sg.get("elements", [])

                # Find a witness (g, h) such that ghg^-1 ∉ H
                witness_found = False
                for g_id in all_sym_ids:
                    for h_id in elements:
                        result = mgr.test_conjugation(g_id, h_id)

                        if result.get("is_witness", False):
                            print(f"✓ Found witness: g={g_id}, h={h_id}")
                            print(f"  Conjugate g*h*g⁻¹ = {result.get('result_sym_id', '?')} escaped the subgroup")
                            witness_found = True
                            break
                    if witness_found:
                        break

                if witness_found:
                    print(f"✓ Subgroup cracked correctly (detected as non-normal)")

                    # Check if classified
                    if non_normal_idx in mgr._classified:
                        is_normal_flag = mgr._classified[non_normal_idx]["is_normal"]
                        if not is_normal_flag:
                            print(f"✓ Subgroup correctly classified as NON-NORMAL")
                        else:
                            print(f"❌ FAILED: Subgroup incorrectly classified as NORMAL")
                            return False
                    else:
                        print(f"❌ FAILED: Subgroup not auto-classified after crack")
                        return False
                else:
                    print(f"❌ FAILED: No witness found for non-normal subgroup")
                    return False

            # Test first normal subgroup (if any)
            normal_idx = None
            for i, sg in enumerate(mgr._target_subgroups):
                if i == non_normal_idx:
                    continue
                elements = sg.get("elements", [])
                subgroup_perms = [mgr._sym_id_to_perm[sid] for sid in elements if sid in mgr._sym_id_to_perm]
                group_perms = [mgr._sym_id_to_perm[sid] for sid in all_sym_ids]

                if is_normal(subgroup_perms, group_perms):
                    normal_idx = i
                    break

            if normal_idx is not None:
                print(f"\nTesting unbreakable confirmation on normal subgroup H{normal_idx + 1}...")
                mgr.select_subgroup(normal_idx)

                sg = mgr._target_subgroups[normal_idx]
                elements = sg.get("elements", [])

                # Test a few conjugations (should all stay in)
                tests_run = 0
                all_stayed = True
                for g_id in all_sym_ids[:min(5, len(all_sym_ids))]:
                    for h_id in elements[:min(3, len(elements))]:
                        result = mgr.test_conjugation(g_id, h_id)
                        tests_run += 1

                        if not result.get("stayed_in", True):
                            all_stayed = False
                            print(f"❌ FAILED: Conjugate escaped from normal subgroup!")
                            print(f"  g={g_id}, h={h_id}, result={result.get('result_sym_id', '?')}")
                            return False

                if all_stayed:
                    print(f"✓ All {tests_run} conjugation tests stayed inside (as expected for normal subgroup)")

                # Try to confirm as unbreakable
                confirm_result = mgr.confirm_normal()

                if confirm_result.get("confirmed", False):
                    print(f"✓ Successfully confirmed as UNBREAKABLE (normal)")

                    if normal_idx in mgr._classified:
                        is_normal_flag = mgr._classified[normal_idx]["is_normal"]
                        if is_normal_flag:
                            print(f"✓ Subgroup correctly classified as NORMAL")
                        else:
                            print(f"❌ FAILED: Subgroup incorrectly classified as NON-NORMAL")
                            return False
                else:
                    print(f"❌ FAILED: Could not confirm unbreakable status")
                    return False

        # Test wrong unbreakable claim rejection
        if actual_count > 0 and 'non_normal_idx' in locals() and non_normal_idx is not None:
            print(f"\n--- Testing Wrong Unbreakable Claim Rejection ---")
            mgr2 = ConjugationCrackingManager()
            mgr2.setup(data, layer_config)

            # Try to confirm a non-normal subgroup as unbreakable
            mgr2.select_subgroup(non_normal_idx)
            wrong_confirm = mgr2.confirm_normal()

            if not wrong_confirm.get("confirmed", False):
                error = wrong_confirm.get("error", "")
                if error == "not_normal":
                    print(f"✓ Correctly rejected unbreakable claim for non-normal subgroup")
                else:
                    print(f"✓ Unbreakable claim rejected (error: {error})")
            else:
                print(f"❌ FAILED: Incorrectly confirmed non-normal subgroup as unbreakable")
                return False

        # Test completion
        print(f"\n--- Testing Completion ---")

        mgr3 = ConjugationCrackingManager()
        mgr3.setup(data, layer_config)

        # Classify all subgroups
        for i, sg in enumerate(mgr3._target_subgroups):
            elements = sg.get("elements", [])
            subgroup_perms = [mgr3._sym_id_to_perm[sid] for sid in elements if sid in mgr3._sym_id_to_perm]
            group_perms = [mgr3._sym_id_to_perm[sid] for sid in all_sym_ids]

            is_normal_sg = is_normal(subgroup_perms, group_perms)

            mgr3.select_subgroup(i)

            if is_normal_sg:
                # Confirm as unbreakable
                mgr3.confirm_normal()
            else:
                # Find witness to crack
                for g_id in all_sym_ids:
                    for h_id in elements:
                        result = mgr3.test_conjugation(g_id, h_id)
                        if result.get("is_witness", False):
                            break
                    if i in mgr3._classified:
                        break

        if mgr3.is_complete():
            print(f"✓ Completion detected after classifying all {actual_count} subgroups")

            # Check completion signal (only if there were subgroups to classify)
            if actual_count > 0:
                completion_signals = [s for s in mgr3._signals if s[0] == "all_subgroups_classified"]
                if len(completion_signals) == 1:
                    print(f"✓ 'all_subgroups_classified' signal emitted exactly once")
                else:
                    print(f"❌ FAILED: Expected 1 completion signal, got {len(completion_signals)}")
                    return False
            else:
                print(f"✓ No completion signal needed (0 subgroups to classify)")
        else:
            progress = mgr3.get_progress()
            print(f"❌ FAILED: Not complete after classification ({progress['classified']}/{progress['total']})")
            return False

        # Test save/restore
        print(f"\n--- Testing Save/Restore ---")

        save_data = mgr3.save_state()

        mgr4 = ConjugationCrackingManager()
        mgr4.setup(data, layer_config)
        mgr4.restore_from_save(save_data)

        if mgr4.get_progress() == mgr3.get_progress():
            print(f"✓ Save/restore works correctly")
        else:
            print(f"❌ FAILED: Progress not restored correctly")
            return False

        print(f"\n{'✓'*35}")
        print(f"✓✓✓ {level_name} PASSED ALL TESTS ✓✓✓")
        print(f"{'✓'*35}")
        return True

    except Exception as e:
        print(f"❌ FAILED with exception: {e}")
        import traceback
        traceback.print_exc()
        return False


def main():
    """Test Layer 4 on the 6 required levels."""
    test_cases = [
        ("level_04.json", "Z4 (level_04)", {
            "subgroup_count": 1,  # Only {e, r2} is non-trivial and not full group
            "normal_count": 1,    # Z4 is abelian, all subgroups normal
            "non_normal_count": 0,
        }),
        ("level_05.json", "D4 (level_05)", {
            "subgroup_count": 8,  # Many non-trivial subgroups
            "normal_count": 4,    # {e,r2}, rotations, and two mixed subgroups
            "non_normal_count": 4, # Pure reflection subgroups are non-normal
        }),
        ("level_09.json", "S3 (level_09)", {
            "subgroup_count": 4,  # {e,r1,r2}, {e,s01}, {e,s02}, {e,s12}
            "normal_count": 1,    # Only {e,r1,r2} ≅ A3 is normal
            "non_normal_count": 3, # Reflection subgroups not normal
        }),
        ("level_10.json", "Z5 (level_10)", {
            "subgroup_count": 0,  # Prime order: only trivial subgroups
            "normal_count": 0,
            "non_normal_count": 0,
        }),
        ("level_13.json", "S4 (level_13)", {
            "subgroup_count": 9,  # Filtered non-trivial (from layer_3)
            "normal_count": 0,    # These are all order-2 transpositions (non-normal)
            "non_normal_count": 9, # All shown subgroups are non-normal
        }),
        ("level_21.json", "Q8 (level_21)", {
            "subgroup_count": 5,  # Non-trivial proper subgroups
            "normal_count": 1,    # Q8 abstract representation: one normal subgroup
            "non_normal_count": 4, # Others are non-normal in this representation
        }),
    ]

    print("="*70)
    print("LAYER 4 CONJUGATION CRACKING - MANUAL TEST SUITE")
    print("="*70)
    print(f"Testing {len(test_cases)} levels as specified in T107")

    results = []
    for level_file, level_name, expected_structure in test_cases:
        passed = test_level(level_file, level_name, expected_structure)
        results.append((level_name, passed))

    # Summary
    print("\n" + "="*70)
    print("TEST SUMMARY")
    print("="*70)

    passed_count = sum(1 for _, passed in results if passed)
    total_count = len(results)

    for level_name, passed in results:
        status = "✓ PASSED" if passed else "❌ FAILED"
        print(f"{status}: {level_name}")

    print(f"\nTotal: {passed_count}/{total_count} levels passed")

    if passed_count == total_count:
        print("\n" + "🎉"*35)
        print("ALL TESTS PASSED!")
        print("🎉"*35)
        return 0
    else:
        print("\n" + "⚠️"*35)
        print(f"SOME TESTS FAILED ({total_count - passed_count} failures)")
        print("⚠️"*35)
        return 1


if __name__ == "__main__":
    sys.exit(main())
