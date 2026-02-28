"""
Inject layer_4 data into all level JSON files.
Layer 4 = conjugation cracking / normal subgroup identification.

Uses the existing layer_3 subgroup data (which already has is_normal flags)
and the Cayley table (or permutation mappings) to compute conjugation witnesses.

Enhanced for T109: adds difficulty, auto_complete, min_attempts,
and conjugation_witnesses for non-normal subgroups.
"""
import json
import math
import os
import sys


# Difficulty classification from T103 normality summary
DIFFICULTY_MAP = {
    1: "trivial", 2: "trivial", 3: "trivial",
    4: "easy", 5: "medium", 6: "easy",
    7: "trivial", 8: "trivial", 9: "medium",
    10: "trivial", 11: "easy", 12: "medium",
    13: "hard", 14: "medium", 15: "medium",
    16: "trivial", 17: "easy", 18: "medium",
    19: "medium", 20: "hard", 21: "special",
    22: "medium", 23: "medium", 24: "hard",
}

# Trivial levels: prime order groups where all subgroups are trivial
TRIVIAL_LEVELS = {1, 2, 3, 7, 8, 10, 16}

# Filtered levels: use same filtered subgroup list as Layer 3
FILTERED_LEVELS = {13, 20, 24}  # S4, D6, D4xZ2


def compose_permutations(perm_a, perm_b):
    """Compose two permutations: result[i] = perm_a[perm_b[i]]."""
    return [perm_a[perm_b[i]] for i in range(len(perm_b))]


def build_cayley_table_from_automorphisms(automorphisms):
    """Build a complete Cayley table from permutation mappings.

    For each pair (f, g) of automorphisms, computes f∘g by composing
    their permutation mappings and looks up the result in the automorphism list.

    Returns (cayley_table, all_element_ids, identity_id).
    """
    # Build mapping from permutation tuple -> sym_id
    perm_to_id = {}
    for auto in automorphisms:
        sym_id = auto["id"]
        mapping = tuple(auto["mapping"])
        perm_to_id[mapping] = sym_id

    # Find identity: the one with mapping [0, 1, 2, ..., n-1]
    identity_id = None
    for auto in automorphisms:
        mapping = auto["mapping"]
        if mapping == list(range(len(mapping))):
            identity_id = auto["id"]
            break

    if identity_id is None:
        return {}, [], None

    all_ids = [auto["id"] for auto in automorphisms]
    id_to_perm = {auto["id"]: auto["mapping"] for auto in automorphisms}

    cayley_table = {}
    for a_auto in automorphisms:
        a_id = a_auto["id"]
        a_perm = a_auto["mapping"]
        cayley_table[a_id] = {}
        for b_auto in automorphisms:
            b_id = b_auto["id"]
            b_perm = b_auto["mapping"]
            result_perm = tuple(compose_permutations(a_perm, b_perm))
            result_id = perm_to_id.get(result_perm)
            if result_id is not None:
                cayley_table[a_id][b_id] = result_id

    return cayley_table, all_ids, identity_id


def find_identity(cayley_table, all_elements):
    """Find the identity element dynamically from a Cayley table.

    The identity e satisfies: cayley[e][x] == x for all x.
    """
    for candidate in all_elements:
        row = cayley_table.get(candidate, {})
        if all(row.get(x) == x for x in all_elements):
            return candidate
    return None


def compute_conjugation_witness(elements, cayley_table, all_elements, identity_id):
    """Find a conjugation witness (g, h) such that g·h·g⁻¹ ∉ H.

    Uses the Cayley table to compute:
      1. g⁻¹ for each g (via identity lookup)
      2. g·h·g⁻¹ = cayley[cayley[g][h]][g⁻¹]

    Returns dict {g, h, g_inv, result} or None if subgroup is normal.
    """
    element_set = set(elements)

    # Build inverse map from Cayley table using the actual identity
    inverse_map = {}
    for g in all_elements:
        for x in all_elements:
            if cayley_table.get(g, {}).get(x) == identity_id:
                inverse_map[g] = x
                break

    # Try all g ∉ H, h ∈ H (h ≠ identity)
    for g in all_elements:
        if g in element_set:
            continue  # g must be outside H
        if g == identity_id:
            continue  # identity conjugation is trivial

        g_inv = inverse_map.get(g)
        if g_inv is None:
            continue

        for h in elements:
            if h == identity_id:
                continue  # conjugating identity always gives identity

            # Compute g·h first
            gh = cayley_table.get(g, {}).get(h)
            if gh is None:
                continue

            # Compute (g·h)·g⁻¹
            result = cayley_table.get(gh, {}).get(g_inv)
            if result is None:
                continue

            if result not in element_set:
                return {
                    "g": g,
                    "h": h,
                    "g_inv": g_inv,
                    "result": result,
                }

    return None  # Normal subgroup — no witness exists


def compute_min_attempts(subgroup_elements, group_order):
    """Compute the minimum attempts threshold for the 'Unbreakable' claim.

    Rules from T104 architecture (section 6.1):
      - h_count = |H| - 1 (non-identity elements in H)
      - g_count = |G| - |H| (elements outside H = lockpicks)
      - total_possible = h_count * g_count
      - min_attempts = max(10, ceil(total_possible * 0.5))
      - If total_possible <= 6: must try all pairs
    """
    h_count = len(subgroup_elements) - 1  # exclude identity
    g_count = group_order - len(subgroup_elements)  # |G \ H|
    total_possible = h_count * g_count

    if total_possible <= 0:
        return 0

    if total_possible <= 6:
        return total_possible  # must try all pairs

    return max(10, math.ceil(total_possible * 0.5))


def inject_layer4(filepath: str) -> bool:
    """Inject layer_4 data into a single level JSON file.
    Returns True if the file was modified."""
    with open(filepath, "r", encoding="utf-8") as f:
        data = json.load(f)

    meta = data.get("meta", {})
    level_num = meta.get("level", 0)
    group_name = meta.get("group_name", "?")
    group_order = meta.get("group_order", 0)

    automorphisms = data.get("symmetries", {}).get("automorphisms", [])
    if group_order == 0:
        group_order = len(automorphisms)

    layers = data.get("layers", {})
    layer_3 = layers.get("layer_3", {})
    subgroups = layer_3.get("subgroups", [])

    if not subgroups:
        print(f"  SKIP {os.path.basename(filepath)}: no layer_3 subgroups")
        return False

    # Get or compute Cayley table
    cayley_table = data.get("symmetries", {}).get("cayley_table", {})
    all_elements = list(cayley_table.keys()) if cayley_table else []
    identity_id = None
    computed_cayley = False

    if cayley_table and all_elements:
        # Cayley table exists — find identity dynamically
        identity_id = find_identity(cayley_table, all_elements)
    elif automorphisms:
        # No Cayley table — compute from permutation mappings
        cayley_table, all_elements, identity_id = (
            build_cayley_table_from_automorphisms(automorphisms)
        )
        computed_cayley = bool(cayley_table)

    # Difficulty from T103 catalog
    difficulty = DIFFICULTY_MAP.get(level_num, "medium")

    # Auto-complete for trivial levels (prime order groups)
    auto_complete = level_num in TRIVIAL_LEVELS

    # If layer_3 is filtered, only use the first subgroup_count subgroups
    is_filtered = layer_3.get("filtered", False)
    if is_filtered:
        subgroup_count = layer_3.get("subgroup_count", len(subgroups))
        subgroups = subgroups[:subgroup_count]

    # Filter non-trivial subgroups (order > 1 and order < group_order)
    non_trivial = []
    for sg in subgroups:
        order = sg.get("order", 0)
        is_trivial = sg.get("is_trivial", False)
        if is_trivial or order <= 1 or order >= group_order:
            continue

        is_normal = sg.get("is_normal", False)
        sg_elements = sg.get("elements", [])

        # Compute conjugation witness for non-normal subgroups
        witness = None
        if not is_normal and cayley_table and all_elements and identity_id:
            witness = compute_conjugation_witness(
                sg_elements, cayley_table, all_elements, identity_id
            )

        # Compute min_attempts threshold
        min_attempts = compute_min_attempts(sg_elements, group_order)

        entry = {
            "order": order,
            "elements": sg_elements,
            "generators": sg.get("generators", []),
            "is_normal": is_normal,
            "min_attempts": min_attempts,
            "conjugation_witness": witness,
        }
        non_trivial.append(entry)

    # Count normal vs non-normal
    normal_count = sum(1 for sg in non_trivial if sg["is_normal"])
    cracked_count = len(non_trivial) - normal_count

    # Build layer_4 config
    layer_4 = {
        "title": "Нормальные подгруппы",
        "instruction": (
            "Выберите подгруппу и проверьте: сохраняется ли она при сопряжении?\n"
            "Нажмите ключ g, затем ⊕ у ключа h из подгруппы.\n"
            "Система вычислит g·h·g⁻¹.\n\n"
            "Если результат выходит за пределы подгруппы — она взломана!"
        ),
        "subtitle": "Не все подгруппы равноценны — нормальные сохраняются при сопряжении",
        "difficulty": difficulty,
        "auto_complete": auto_complete,
        "classify_count": len(non_trivial),
        "normal_count": normal_count,
        "cracked_count": cracked_count,
        "subgroups": non_trivial,
    }

    layers["layer_4"] = layer_4
    data["layers"] = layers

    with open(filepath, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")

    # Build witness summary for logging
    witnesses_found = sum(
        1 for sg in non_trivial
        if sg.get("conjugation_witness") is not None
    )
    witness_info = ""
    if cracked_count > 0:
        witness_info = f", witnesses: {witnesses_found}/{cracked_count}"

    cayley_note = " [cayley computed]" if computed_cayley else ""
    print(f"  OK {os.path.basename(filepath)}: {group_name} [{difficulty}] — "
          f"{len(non_trivial)} subgroups to classify "
          f"({normal_count} normal, {cracked_count} non-normal{witness_info})"
          f"{' [auto_complete]' if auto_complete else ''}{cayley_note}")
    return True


def main():
    levels_dir = os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        "..", "data", "levels", "act1"
    )

    if not os.path.exists(levels_dir):
        print(f"ERROR: Levels directory not found: {levels_dir}")
        sys.exit(1)

    json_files = sorted(f for f in os.listdir(levels_dir) if f.endswith(".json"))
    print(f"Injecting layer_4 data into {len(json_files)} level files...\n")

    modified = 0
    for filename in json_files:
        filepath = os.path.join(levels_dir, filename)
        if inject_layer4(filepath):
            modified += 1

    print(f"\nDone: {modified}/{len(json_files)} files updated.")

    # Summary
    trivial_count = sum(1 for f in json_files
                        if int(f.replace("level_", "").replace(".json", ""))
                        in TRIVIAL_LEVELS)
    print(f"\nSummary:")
    print(f"  Trivial (auto_complete): {trivial_count} levels")
    print(f"  Filtered (HARD): {len(FILTERED_LEVELS)} levels")
    print(f"  Total modified: {modified}/{len(json_files)}")


if __name__ == "__main__":
    main()
