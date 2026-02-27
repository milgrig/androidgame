"""
Inject layer_3 subgroup data into all act1 level JSON files.
Uses T095_subgroups_data.json as the source.
"""
import json
import os

def main():
    base = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(base)

    # Load subgroup catalog
    catalog_path = os.path.join(project_root, "..", ".tayfa", "math_consultant", "T095_subgroups_data.json")
    with open(catalog_path, "r", encoding="utf-8") as f:
        catalog = json.load(f)

    # Build lookup by level number
    catalog_by_level = {}
    for entry in catalog:
        catalog_by_level[entry["level"]] = entry

    # Filtering config for levels with too many subgroups
    FILTER_CONFIG = {
        13: {"filtered": True, "filter_strategy": "pedagogical_top10", "target_count": 10},
        20: {"filtered": True, "filter_strategy": "pedagogical_top10", "target_count": 10},
        # Level 21 (Q8): keep all 12 (pedagogically valuable)
        24: {"filtered": True, "filter_strategy": "pedagogical_top10", "target_count": 10},
    }

    levels_dir = os.path.join(project_root, "data", "levels", "act1")

    for i in range(1, 25):
        filename = f"level_{i:02d}.json"
        filepath = os.path.join(levels_dir, filename)

        if not os.path.exists(filepath):
            print(f"SKIP: {filename} not found")
            continue

        with open(filepath, "r", encoding="utf-8") as f:
            level_data = json.load(f)

        cat_entry = catalog_by_level.get(i)
        if cat_entry is None:
            print(f"SKIP: No catalog entry for level {i}")
            continue

        # Build layer_3 section
        subgroups = cat_entry["subgroups"]
        subgroup_count = cat_entry["subgroup_count"]

        layer_3 = {
            "title": "Группы — брелки",
            "instruction": "Соберите все брелки — наборы ключей, образующие группу",
            "subgroup_count": subgroup_count,
            "subgroups": subgroups,
            "filtered": False,
        }

        # Apply filtering for complex levels
        if i in FILTER_CONFIG:
            fc = FILTER_CONFIG[i]
            layer_3["filtered"] = True
            layer_3["full_subgroup_count"] = subgroup_count
            layer_3["subgroup_count"] = fc["target_count"]
            layer_3["filter_strategy"] = fc["filter_strategy"]

        # Ensure "layers" key exists
        if "layers" not in level_data:
            level_data["layers"] = {}

        level_data["layers"]["layer_3"] = layer_3

        # Write back
        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(level_data, f, ensure_ascii=False, indent=2)

        filtered_note = " (FILTERED)" if i in FILTER_CONFIG else ""
        print(f"OK: {filename} — {subgroup_count} subgroups{filtered_note}")

if __name__ == "__main__":
    main()
