"""
DEEP CRITIC EVALUATION - The Symmetry Vaults

Comprehensive evaluation with comparison to industry standards:
- The Witness (teaching through discovery)
- Baba Is You (mechanic clarity)
- Monument Valley (visual polish and progression)
"""

import sys
import json
import time
from pathlib import Path

# Add agent client to path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "TheSymmetryVaults" / "tests" / "agent"))
from agent_client import AgentClient, AgentClientError

GODOT_PATH = r"C:\Godot\Godot_v4.6.1-stable_win64_console.exe"
PROJECT_PATH = r"C:\Cursor\TayfaProject\AndroidGame\TheSymmetryVaults"


def safe_print(text):
    """Print with ASCII fallback."""
    try:
        print(text)
    except UnicodeEncodeError:
        print(text.encode('ascii', 'replace').decode('ascii'))


def analyze_single_level_deeply(client: AgentClient, level_id: str):
    """Deep analysis of a single level."""
    safe_print(f"\n{'='*70}")
    safe_print(f"DEEP ANALYSIS: {level_id}")
    safe_print(f"{'='*70}")

    analysis = {
        "level_id": level_id,
        "structure": {},
        "ui": {},
        "gameplay": {},
        "issues": [],
        "strengths": []
    }

    try:
        # Load level
        load_result = client.load_level(level_id)
        analysis["loaded"] = True

        # Get full state
        state = client.get_state()

        # STRUCTURE ANALYSIS
        crystals = state.get("crystals", [])
        edges = state.get("edges", [])
        level_meta = state.get("level", {})
        keyring = state.get("keyring", {})

        analysis["structure"] = {
            "crystal_count": len(crystals),
            "edge_count": len(edges),
            "total_symmetries": state.get("total_symmetries", 0),
            "group": level_meta.get("group_name", "?"),
            "title": level_meta.get("title", "?"),
            "subtitle": level_meta.get("subtitle", "")
        }

        safe_print(f"\nSTRUCTURE:")
        safe_print(f"  Crystals: {len(crystals)}")
        safe_print(f"  Edges: {len(edges)}")
        safe_print(f"  Group: {level_meta.get('group_name', '?')}")
        safe_print(f"  Expected symmetries: {state.get('total_symmetries', 0)}")

        # Check structure validity
        if len(edges) == 0 and len(crystals) > 1:
            analysis["issues"].append(f"No edges between {len(crystals)} crystals - graph disconnected?")

        # Check crystal properties
        if crystals:
            has_labels = all(c.get("label") for c in crystals)
            has_colors = all(c.get("color") for c in crystals)
            draggable_count = sum(1 for c in crystals if c.get("draggable"))

            analysis["structure"]["has_labels"] = has_labels
            analysis["structure"]["has_colors"] = has_colors
            analysis["structure"]["draggable_count"] = draggable_count

            if not has_labels:
                analysis["issues"].append("Crystals missing labels")
            if not has_colors:
                analysis["issues"].append("Crystals missing colors")

            safe_print(f"  Labels: {has_labels}, Colors: {has_colors}, Draggable: {draggable_count}/{len(crystals)}")

        # UI ANALYSIS
        tree = client.get_tree()
        labels = client.find_labels(tree)
        buttons = client.find_buttons(tree)

        # Russian text check
        russian_labels = []
        for label in labels:
            text = label.get("text", "")
            if text and any(ord(c) >= 0x0400 and ord(c) <= 0x04FF for c in text):
                russian_labels.append({"text": text[:50], "path": label.get("name", "?")})

        analysis["ui"] = {
            "label_count": len(labels),
            "button_count": len(buttons),
            "russian_labels": len(russian_labels),
            "button_texts": [b.get("text", "")[:30] for b in buttons[:5]]
        }

        safe_print(f"\nUI:")
        safe_print(f"  Labels: {len(labels)} ({len(russian_labels)} Russian)")
        safe_print(f"  Buttons: {len(buttons)}")

        if len(buttons) == 0:
            analysis["issues"].append("No buttons found - how does player interact?")

        # GAMEPLAY ANALYSIS (non-destructive)
        safe_print(f"\nGAMEPLAY TEST:")

        # Test 1: Identity permutation (should always be a symmetry)
        safe_print(f"  Testing identity permutation...")
        try:
            identity = list(range(len(crystals)))
            result = client.submit_permutation(identity)
            events = result.get("events", [])

            symmetry_found = any(e.get("type") == "symmetry_found" for e in events)
            analysis["gameplay"]["identity_is_symmetry"] = symmetry_found

            if symmetry_found:
                safe_print(f"    ✓ Identity recognized as symmetry")
                analysis["strengths"].append("Identity correctly recognized")
            else:
                safe_print(f"    ✗ Identity NOT recognized as symmetry!")
                analysis["issues"].append("Identity permutation not recognized - group theory bug?")

        except AgentClientError as e:
            safe_print(f"    Error: {e}")
            analysis["issues"].append(f"Identity test failed: {e}")

        # Test 2: Check keyring state
        keys = keyring.get("keys", {})
        found_count = sum(1 for k in keys.values() if k.get("found", False))
        analysis["gameplay"]["symmetries_found"] = found_count
        analysis["gameplay"]["symmetries_total"] = len(keys)

        safe_print(f"  Symmetries discovered: {found_count}/{len(keys)}")

    except AgentClientError as e:
        safe_print(f"ERROR: {e}")
        analysis["issues"].append(f"Critical error: {e}")
        analysis["loaded"] = False

    return analysis


def compare_to_industry_standards(all_analyses):
    """Compare to The Witness, Baba Is You, Monument Valley."""
    safe_print("\n" + "="*70)
    safe_print("COMPARISON TO INDUSTRY STANDARDS")
    safe_print("="*70)

    comparison = {}

    # The Witness: Teaching through environmental clues
    safe_print("\n1. THE WITNESS (Teaching through discovery):")
    safe_print("   The Witness teaches rules implicitly through level design.")

    has_tutorial = any("tutorial" in a.get("structure", {}).get("title", "").lower() for a in all_analyses)
    has_progression = len(set(a.get("structure", {}).get("group", "") for a in all_analyses)) > 1

    if has_tutorial:
        safe_print("   ✓ Tutorial levels detected")
        comparison["witness_teaching"] = "GOOD"
    else:
        safe_print("   ? No explicit tutorial found")
        comparison["witness_teaching"] = "UNCLEAR"

    if has_progression:
        safe_print("   ✓ Multiple groups suggest progressive difficulty")
    else:
        safe_print("   ✗ Single group - no clear progression")

    # Baba Is You: Clarity of mechanics
    safe_print("\n2. BABA IS YOU (Mechanic clarity):")
    safe_print("   Baba rules are always visible and unambiguous.")

    total_issues = sum(len(a.get("issues", [])) for a in all_analyses)
    avg_issues = total_issues / max(len(all_analyses), 1)

    if avg_issues < 1:
        safe_print(f"   ✓ Clean mechanics (avg {avg_issues:.1f} issues per level)")
        comparison["baba_clarity"] = "EXCELLENT"
    elif avg_issues < 3:
        safe_print(f"   ~ Some ambiguity (avg {avg_issues:.1f} issues per level)")
        comparison["baba_clarity"] = "ACCEPTABLE"
    else:
        safe_print(f"   ✗ Confusing mechanics (avg {avg_issues:.1f} issues per level)")
        comparison["baba_clarity"] = "POOR"

    # Monument Valley: Polish and UX
    safe_print("\n3. MONUMENT VALLEY (Visual polish & UX):")
    safe_print("   Monument Valley has beautiful visuals and clear UI.")

    avg_labels = sum(a.get("ui", {}).get("label_count", 0) for a in all_analyses) / max(len(all_analyses), 1)
    avg_buttons = sum(a.get("ui", {}).get("button_count", 0) for a in all_analyses) / max(len(all_analyses), 1)
    has_localization = any(a.get("ui", {}).get("russian_labels", 0) > 0 for a in all_analyses)

    if avg_labels > 15:
        safe_print(f"   ✓ Rich UI (avg {avg_labels:.0f} labels per screen)")
    else:
        safe_print(f"   ~ Minimal UI (avg {avg_labels:.0f} labels per screen)")

    if has_localization:
        safe_print("   ✓ Localization present (Russian)")
        comparison["monument_polish"] = "GOOD"
    else:
        safe_print("   ✗ No localization detected")
        comparison["monument_polish"] = "BASIC"

    return comparison


def generate_final_verdict(all_analyses, comparison):
    """Generate harsh but fair final verdict."""
    safe_print("\n" + "="*70)
    safe_print("FINAL VERDICT")
    safe_print("="*70)

    # Collect all issues and strengths
    all_issues = []
    all_strengths = []
    for a in all_analyses:
        all_issues.extend(a.get("issues", []))
        all_strengths.extend(a.get("strengths", []))

    # SCORING
    scores = {}

    # 1. Data Structure (1-10)
    structure_score = 10
    if len(all_analyses) < 5:
        structure_score -= 3  # Too few levels
    disconnected_graphs = len([i for i in all_issues if "disconnected" in i.lower() or "no edges" in i.lower()])
    structure_score -= disconnected_graphs * 2
    structure_score = max(1, min(10, structure_score))

    scores["1_data_structure"] = {
        "score": structure_score,
        "reason": f"{len(all_analyses)} levels analyzed. Issues with graph connectivity: {disconnected_graphs}"
    }

    # 2. Game Feel (1-10)
    gamefeel_score = 8
    feedback_issues = len([i for i in all_issues if "not recognized" in i.lower() or "no feedback" in i.lower()])
    gamefeel_score -= feedback_issues * 2
    if all_strengths:
        gamefeel_score += 1
    gamefeel_score = max(1, min(10, gamefeel_score))

    scores["2_game_feel"] = {
        "score": gamefeel_score,
        "reason": f"Tested symmetry recognition. Feedback issues: {feedback_issues}"
    }

    # 3. Progression (1-10)
    groups = set(a.get("structure", {}).get("group", "") for a in all_analyses)
    groups.discard("")
    progression_score = min(10, 3 + len(groups))  # Base 3, +1 per group
    if len(all_analyses) < 8:
        progression_score -= 2

    scores["3_progression"] = {
        "score": progression_score,
        "reason": f"{len(all_analyses)} levels across {len(groups)} mathematical groups"
    }

    # 4. UI/Texts (1-10)
    ui_score = 5
    has_russian = any(a.get("ui", {}).get("russian_labels", 0) > 0 for a in all_analyses)
    has_buttons = any(a.get("ui", {}).get("button_count", 0) > 0 for a in all_analyses)
    ui_issues = len([i for i in all_issues if "button" in i.lower() or "label" in i.lower()])

    if has_russian:
        ui_score += 2
    if has_buttons:
        ui_score += 2
    ui_score -= ui_issues
    ui_score = max(1, min(10, ui_score))

    scores["4_ui_texts"] = {
        "score": ui_score,
        "reason": f"Russian text: {has_russian}, Buttons: {has_buttons}, UI issues: {ui_issues}"
    }

    # 5. Overall (1-10)
    avg_score = sum(s["score"] for s in scores.values()) / len(scores)
    critical_issues = len([i for i in all_issues if "critical" in i.lower() or "bug" in i.lower()])

    overall_score = int(avg_score)
    if critical_issues > 2:
        overall_score = min(overall_score, 5)

    scores["5_overall"] = {
        "score": overall_score,
        "reason": f"Average: {avg_score:.1f}. Critical issues: {critical_issues}. Ready for demo: {overall_score >= 7}"
    }

    # Print scores
    safe_print("\nSCORES:")
    for key, data in sorted(scores.items()):
        safe_print(f"  {key.replace('_', ' ').title()}: {data['score']}/10")
        safe_print(f"    -> {data['reason']}")

    # Top 5 weaknesses
    safe_print("\nTOP 5 WEAKNESSES:")
    unique_issues = list(set(all_issues))[:5]
    for i, issue in enumerate(unique_issues, 1):
        safe_print(f"  {i}. {issue}")

    # Top 3 strengths
    safe_print("\nTOP 3 STRENGTHS:")
    unique_strengths = list(set(all_strengths))[:3]
    for i, strength in enumerate(unique_strengths, 1):
        safe_print(f"  {i}. {strength}")

    if not unique_strengths:
        safe_print("  (No significant strengths identified)")

    return scores


def main():
    safe_print("="*70)
    safe_print("CRITIC AGENT - DEEP EVALUATION")
    safe_print("Playing The Symmetry Vaults for the FIRST TIME")
    safe_print("="*70)

    client = None
    all_analyses = []

    try:
        # Start game
        safe_print("\n[1/5] Launching Godot...")
        client = AgentClient(godot_path=GODOT_PATH, project_path=PROJECT_PATH, timeout=20.0)
        client.start()

        safe_print("[2/5] Discovering levels...")
        levels = client.list_levels()
        safe_print(f"  Found {len(levels)} levels")

        # Analyze first 5 levels from act1
        act1_levels = [l for l in levels if l.get("act") == "act1"][:5]

        safe_print(f"[3/5] Analyzing {len(act1_levels)} levels in detail...")

        for level_info in act1_levels:
            level_id = level_info.get("id")
            analysis = analyze_single_level_deeply(client, level_id)
            all_analyses.append(analysis)

        safe_print("\n[4/5] Comparing to industry standards...")
        comparison = compare_to_industry_standards(all_analyses)

        safe_print("\n[5/5] Generating final verdict...")
        scores = generate_final_verdict(all_analyses, comparison)

        # Save detailed report
        report_data = {
            "analyses": all_analyses,
            "comparison": comparison,
            "scores": scores,
            "timestamp": time.time()
        }

        output_path = Path(__file__).parent / "deep_evaluation.json"
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(report_data, f, indent=2, ensure_ascii=False)

        safe_print(f"\n\nDetailed report saved: {output_path}")

    except Exception as e:
        safe_print(f"\nCRITICAL ERROR: {e}")
        import traceback
        traceback.print_exc()

    finally:
        if client:
            safe_print("\n[Cleanup] Shutting down...")
            client.quit()

    return all_analyses


if __name__ == "__main__":
    main()
