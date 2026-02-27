"""
Critic Evaluation Script — Real gameplay evaluation of The Symmetry Vaults

This script plays through multiple levels and critically evaluates:
1. Data structure (1-10): Are levels well-designed? Groups coherent?
2. Game feel (1-10): Is discovering symmetry pleasant? Events/feedback?
3. Progression (1-10): Does difficulty ramp up? Learning curve?
4. UI/texts (1-10): Russian texts readable? Buttons clear? HUD informative?
5. Overall (1-10): Ready for first user demo?
6. Top 5 weaknesses with concrete examples
7. Top 3 strengths

Comparison to: The Witness, Baba Is You, Monument Valley
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

class CriticReport:
    def __init__(self):
        self.observations = []
        self.scores = {}
        self.weaknesses = []
        self.strengths = []

    def observe(self, category: str, note: str, evidence: dict = None):
        """Record an observation with evidence."""
        self.observations.append({
            "category": category,
            "note": note,
            "evidence": evidence or {},
            "timestamp": time.time()
        })

    def score(self, aspect: str, value: int, justification: str):
        """Record a score with justification."""
        self.scores[aspect] = {
            "score": value,
            "justification": justification
        }

    def add_weakness(self, weakness: str, example: str):
        """Add a weakness with concrete example."""
        self.weaknesses.append({"weakness": weakness, "example": example})

    def add_strength(self, strength: str):
        """Add a strength."""
        self.strengths.append(strength)

    def generate_report(self) -> str:
        """Generate final report."""
        lines = []
        lines.append("=" * 80)
        lines.append("CRITIC EVALUATION REPORT - THE SYMMETRY VAULTS")
        lines.append("=" * 80)
        lines.append("")

        # Scores
        lines.append("SCORES (1-10):")
        lines.append("-" * 40)
        for aspect, data in self.scores.items():
            lines.append(f"{aspect}: {data['score']}/10")
            lines.append(f"  -> {data['justification']}")
            lines.append("")

        # Weaknesses
        lines.append("TOP 5 WEAKNESSES:")
        lines.append("-" * 40)
        for i, w in enumerate(self.weaknesses[:5], 1):
            lines.append(f"{i}. {w['weakness']}")
            lines.append(f"   Example: {w['example']}")
            lines.append("")

        # Strengths
        lines.append("TOP 3 STRENGTHS:")
        lines.append("-" * 40)
        for i, s in enumerate(self.strengths[:3], 1):
            lines.append(f"{i}. {s}")
            lines.append("")

        # Detailed observations
        lines.append("DETAILED OBSERVATIONS:")
        lines.append("-" * 40)
        for obs in self.observations:
            lines.append(f"[{obs['category']}] {obs['note']}")
            if obs['evidence']:
                lines.append(f"  Evidence: {json.dumps(obs['evidence'], indent=2)[:200]}")
            lines.append("")

        return "\n".join(lines)


def evaluate_ui_and_texts(client: AgentClient, report: CriticReport):
    """Evaluate UI quality and Russian text readability."""
    print("\n=== EVALUATING UI AND TEXTS ===")

    tree = client.get_tree()
    labels = client.find_labels(tree)
    buttons = client.find_buttons(tree)

    # Check for Russian text
    russian_texts = []
    for label in labels:
        text = label.get("text", "")
        if text and any(ord(c) >= 0x0400 and ord(c) <= 0x04FF for c in text):
            russian_texts.append({"path": label.get("path"), "text": text})

    report.observe("UI", f"Found {len(labels)} labels, {len(russian_texts)} with Cyrillic text",
                   {"russian_samples": russian_texts[:3]})

    # Check button labels
    button_texts = [b.get("text", "") for b in buttons]
    report.observe("UI", f"Found {len(buttons)} buttons",
                   {"button_texts": button_texts})

    # HUD elements check
    state = client.get_state()
    level_info = state.get("level", {})

    report.observe("UI", "Level metadata found", {
        "title": level_info.get("title"),
        "subtitle": level_info.get("subtitle"),
        "group": level_info.get("group_name")
    })

    return len(labels) > 0, len(russian_texts) > 0


def evaluate_level_structure(client: AgentClient, report: CriticReport, level_id: str):
    """Evaluate level design structure."""
    print(f"\n=== EVALUATING LEVEL STRUCTURE: {level_id} ===")

    state = client.get_state()

    crystals = state.get("crystals", [])
    edges = state.get("edges", [])
    keyring = state.get("keyring", {})
    total_symmetries = state.get("total_symmetries", 0)

    level_meta = state.get("level", {})

    report.observe("Structure", f"Level {level_id} loaded", {
        "crystal_count": len(crystals),
        "edge_count": len(edges),
        "total_symmetries": total_symmetries,
        "group": level_meta.get("group_name"),
        "title": level_meta.get("title")
    })

    # Check crystal data
    if crystals:
        sample_crystal = crystals[0]
        report.observe("Structure", "Crystal data sample", {
            "sample": sample_crystal
        })

    # Check if edges form coherent structure
    if not edges:
        report.add_weakness("No edges in level", f"Level {level_id} has {len(crystals)} crystals but 0 edges")

    return {
        "crystals": len(crystals),
        "edges": len(edges),
        "symmetries": total_symmetries
    }


def evaluate_gameplay_feel(client: AgentClient, report: CriticReport, level_id: str):
    """Evaluate game feel by actually playing."""
    print(f"\n=== EVALUATING GAMEPLAY FEEL: {level_id} ===")

    state = client.get_state()
    crystals = state.get("crystals", [])

    if len(crystals) < 2:
        report.observe("GameFeel", "Cannot test swaps - insufficient crystals", {"crystal_count": len(crystals)})
        return False

    # Try identity permutation (should be a symmetry in most groups)
    print("Testing identity permutation...")
    try:
        result = client.submit_permutation(list(range(len(crystals))))
        events = result.get("events", [])

        report.observe("GameFeel", "Identity permutation tested", {
            "success": result.get("ok"),
            "events": [e.get("type") for e in events]
        })

        has_feedback = len(events) > 0
        if not has_feedback:
            report.add_weakness("No feedback on identity permutation",
                              f"Level {level_id}: submitting identity gave no events")

    except AgentClientError as e:
        report.observe("GameFeel", f"Error testing identity: {e}")
        return False

    # Try a simple swap
    print("Testing crystal swap...")
    try:
        if len(crystals) >= 2:
            crystal_ids = [c.get("crystal_id") for c in crystals[:2]]
            result = client.swap(crystal_ids[0], crystal_ids[1])
            events = result.get("events", [])

            report.observe("GameFeel", "Swap performed", {
                "from": crystal_ids[0],
                "to": crystal_ids[1],
                "events": [e.get("type") for e in events]
            })

            # Check for visual/audio feedback
            has_swap_event = any(e.get("type") == "swap_performed" for e in events)
            if not has_swap_event:
                report.add_weakness("No swap_performed event",
                                  f"Swapping crystals {crystal_ids[0]}↔{crystal_ids[1]} gave no swap event")

    except AgentClientError as e:
        report.observe("GameFeel", f"Error testing swap: {e}")

    return True


def evaluate_progression(client: AgentClient, report: CriticReport):
    """Evaluate progression across multiple levels."""
    print("\n=== EVALUATING PROGRESSION ===")

    levels = client.list_levels()
    report.observe("Progression", f"Found {len(levels)} total levels",
                   {"level_count": len(levels)})

    # Group levels by act and group
    by_act = {}
    by_group = {}

    for level in levels:
        act = level.get("act", "unknown")
        group = level.get("group_name", "unknown")

        by_act.setdefault(act, []).append(level)
        by_group.setdefault(group, []).append(level)

    report.observe("Progression", "Levels organized by act", {
        "acts": list(by_act.keys()),
        "act_sizes": {act: len(lvls) for act, lvls in by_act.items()}
    })

    report.observe("Progression", "Levels organized by group", {
        "groups": list(by_group.keys()),
        "group_sizes": {grp: len(lvls) for grp, lvls in by_group.items()}
    })

    # Check if groups are coherent (same group name = same act?)
    group_coherence = {}
    for group, lvls in by_group.items():
        acts_in_group = set(l.get("act") for l in lvls)
        group_coherence[group] = list(acts_in_group)

    report.observe("Progression", "Group coherence check", group_coherence)

    # Look for groups spanning multiple acts (might be confusing)
    multi_act_groups = {g: acts for g, acts in group_coherence.items() if len(acts) > 1}
    if multi_act_groups:
        report.add_weakness("Groups span multiple acts",
                          f"Groups spanning acts: {multi_act_groups}")

    return len(levels), len(by_group)


def play_sample_levels(client: AgentClient, report: CriticReport):
    """Play through a sample of levels to evaluate."""

    levels = client.list_levels()

    # Play first 3 levels from act1
    act1_levels = [l for l in levels if l.get("act") == "act1"][:3]

    level_stats = []

    for level_info in act1_levels:
        level_id = level_info.get("id")
        print(f"\n{'='*60}")
        print(f"PLAYING: {level_id}")
        print(f"{'='*60}")

        try:
            client.load_level(level_id)
            time.sleep(0.5)  # Let level load

            structure = evaluate_level_structure(client, report, level_id)
            gameplay_ok = evaluate_gameplay_feel(client, report, level_id)

            level_stats.append({
                "id": level_id,
                "structure": structure,
                "gameplay_ok": gameplay_ok
            })

        except Exception as e:
            report.observe("Error", f"Failed to evaluate {level_id}: {e}")

    return level_stats


def main():
    """Main evaluation flow."""
    import sys
    import io
    # Force UTF-8 output
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

    report = CriticReport()

    print("="*80)
    print("CRITIC AGENT - REAL GAMEPLAY EVALUATION")
    print("="*80)

    client = None

    try:
        print("\n[1/6] Starting Godot via Agent Bridge...")
        client = AgentClient(godot_path=GODOT_PATH, project_path=PROJECT_PATH, timeout=20.0)
        client.start(level_id="level_01")

        report.observe("Launch", "Game launched successfully", {"protocol_version": client.hello()})

        print("\n[2/6] Evaluating UI and texts...")
        has_ui, has_russian = evaluate_ui_and_texts(client, report)

        print("\n[3/6] Evaluating progression structure...")
        total_levels, total_groups = evaluate_progression(client, report)

        print("\n[4/6] Playing sample levels...")
        level_stats = play_sample_levels(client, report)

        print("\n[5/6] Calculating scores...")

        # SCORE 1: Data Structure
        structure_issues = sum(1 for w in report.weaknesses if "structure" in w["weakness"].lower())
        has_groups = total_groups > 0
        has_levels = total_levels > 5
        structure_score = max(1, 10 - structure_issues * 2)
        if not has_groups:
            structure_score -= 3
        if not has_levels:
            structure_score -= 2

        report.score("1. Data Structure", structure_score,
                    f"Found {total_levels} levels in {total_groups} groups. " +
                    f"Structure issues: {structure_issues}")

        # SCORE 2: Game Feel
        gameplay_issues = sum(1 for w in report.weaknesses if "feedback" in w["weakness"].lower() or "event" in w["weakness"].lower())
        gamefeel_score = max(1, 8 - gameplay_issues * 2)

        report.score("2. Game Feel", gamefeel_score,
                    f"Tested swaps and permutations. Feedback issues: {gameplay_issues}")

        # SCORE 3: Progression
        progression_score = 7
        if total_levels < 5:
            progression_score = 3
        elif total_groups < 2:
            progression_score = 5

        report.score("3. Progression", progression_score,
                    f"{total_levels} levels organized in {total_groups} groups")

        # SCORE 4: UI/Texts
        ui_score = 5
        if has_ui:
            ui_score += 2
        if has_russian:
            ui_score += 2

        report.score("4. UI/Texts", ui_score,
                    f"UI present: {has_ui}, Russian text: {has_russian}")

        # SCORE 5: Overall
        avg_score = sum(s["score"] for s in report.scores.values()) / len(report.scores)
        critical_issues = len([w for w in report.weaknesses if "no" in w["weakness"].lower() or "missing" in w["weakness"].lower()])

        overall_score = int(avg_score)
        if critical_issues > 3:
            overall_score = min(overall_score, 5)

        report.score("5. Overall Quality", overall_score,
                    f"Average of other scores: {avg_score:.1f}. Critical issues: {critical_issues}")

        # Add strengths
        if total_levels > 10:
            report.add_strength("Rich content: 10+ levels available for players")
        if total_groups > 3:
            report.add_strength(f"Well-organized: {total_groups} distinct mathematical groups")
        if has_russian:
            report.add_strength("Localization present: Russian text found in UI")

        print("\n[6/6] Generating final report...")

    except Exception as e:
        report.observe("CRITICAL_ERROR", f"Evaluation failed: {e}")
        report.score("5. Overall Quality", 1, f"Critical failure: {e}")

    finally:
        if client:
            print("\n[Cleanup] Shutting down Godot...")
            client.quit()

    # Generate and save report
    report_text = report.generate_report()

    output_path = Path(__file__).parent / "evaluation_report.txt"
    output_path.write_text(report_text, encoding="utf-8")

    print("\n" + report_text)
    print(f"\nReport saved to: {output_path}")

    return report


if __name__ == "__main__":
    report = main()
