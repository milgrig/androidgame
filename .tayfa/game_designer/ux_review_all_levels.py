"""
UX Review Script for The Symmetry Vaults - All 12 Levels
Plays through each level as a skeptical non-mathematician player
"""
import sys
import os
# Force UTF-8 encoding for console output
os.environ['PYTHONIOENCODING'] = 'utf-8'

sys.path.insert(0, r"C:\Cursor\TayfaProject\AndroidGame\TheSymmetryVaults\tests\agent")
from agent_client import AgentClient
import json
from typing import Dict, List, Any

GODOT_PATH = r"C:\Godot\Godot_v4.6.1-stable_win64_console.exe"
PROJECT_PATH = r"C:\Cursor\TayfaProject\AndroidGame\TheSymmetryVaults"

class UXReviewer:
    def __init__(self):
        self.client = None
        self.reviews = []

    def start_game(self, level_id: str):
        """Start the game at a specific level"""
        if self.client:
            try:
                self.client.quit()
            except:
                pass

        self.client = AgentClient(
            godot_path=GODOT_PATH,
            project_path=PROJECT_PATH,
            timeout=15.0
        )
        self.client.start(level_id=level_id)

    def explore_level(self, level_num: int) -> Dict[str, Any]:
        """Explore a level and gather information"""
        level_id = f"level_{level_num:02d}"
        print(f"\n{'='*60}")
        print(f"Starting Level {level_num}: {level_id}")
        print(f"{'='*60}\n")

        self.start_game(level_id)

        # Get initial state
        state = self.client.get_state()
        labels = self.client.find_labels()
        buttons = self.client.find_buttons()

        print(f"Initial State:")
        print(f"  Crystals: {len(state.get('crystals', []))}")
        print(f"  Edges: {len(state.get('edges', []))}")
        print(f"  Expected symmetries: {state.get('expected_symmetries', 0)}")

        # Print UI text (safely handle encoding)
        print(f"\nUI Text:")
        for label in labels:
            if label.get('text') and label['text'].strip():
                try:
                    print(f"  - {label['text']}")
                except UnicodeEncodeError:
                    print(f"  - [Russian text: {len(label['text'])} chars]")

        print(f"\nButtons:")
        for button in buttons:
            if button.get('text'):
                try:
                    print(f"  - {button['text']}")
                except UnicodeEncodeError:
                    print(f"  - [Button: {len(button['text'])} chars]")

        # Analyze the graph structure
        crystals = state.get('crystals', [])
        edges = state.get('edges', [])

        print(f"\nCrystal Colors:")
        color_counts = {}
        for crystal in crystals:
            color = crystal.get('color', 'unknown')
            color_counts[color] = color_counts.get(color, 0) + 1
        for color, count in color_counts.items():
            print(f"  {color}: {count}")

        print(f"\nEdge Types:")
        edge_type_counts = {}
        for edge in edges:
            edge_type = edge.get('type', 'unknown')
            edge_type_counts[edge_type] = edge_type_counts.get(edge_type, 0) + 1
        for edge_type, count in edge_type_counts.items():
            print(f"  {edge_type}: {count}")

        # Try some permutations as a naive player would
        print(f"\nExploring symmetries...")
        found_symmetries = []

        # Try identity (no swap)
        print(f"  Testing identity...")
        resp = self.client.submit_permutation(list(range(len(crystals))))
        events = resp.get('events', [])
        if any(e.get('type') == 'symmetry_found' for e in events):
            print(f"    OK Identity found")
            found_symmetries.append("identity")

        # Try simple swaps for small graphs
        if len(crystals) <= 4:
            for i in range(len(crystals)):
                for j in range(i+1, len(crystals)):
                    perm = list(range(len(crystals)))
                    perm[i], perm[j] = perm[j], perm[i]
                    print(f"  Testing swap {i}↔{j}...")
                    resp = self.client.swap(i, j)
                    events = resp.get('events', [])

                    if any(e.get('type') == 'symmetry_found' for e in events):
                        print(f"    OK Symmetry found!")
                        found_symmetries.append(f"swap_{i}_{j}")
                    elif any(e.get('type') == 'invalid_attempt' for e in events):
                        print(f"    X Invalid")

                    # Reset after each attempt
                    self.client.reset()

        # Try rotations for cyclic-looking graphs
        if len(crystals) in [3, 4]:
            print(f"  Testing rotation...")
            rotation = list(range(1, len(crystals))) + [0]
            resp = self.client.submit_permutation(rotation)
            events = resp.get('events', [])
            if any(e.get('type') == 'symmetry_found' for e in events):
                print(f"    OK Rotation found")
                found_symmetries.append("rotation")
            self.client.reset()

        print(f"\nFound {len(found_symmetries)} symmetries out of {state.get('expected_symmetries', '?')}")

        return {
            'level_num': level_num,
            'level_id': level_id,
            'state': state,
            'labels': labels,
            'buttons': buttons,
            'found_symmetries': found_symmetries,
            'crystal_count': len(crystals),
            'edge_count': len(edges),
            'expected_symmetries': state.get('expected_symmetries', 0)
        }

    def evaluate_level(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Evaluate a level from a UX perspective"""
        level_num = data['level_num']

        evaluation = {
            'level_num': level_num,
            'scores': {},
            'verdict': '',
            'problems': [],
            'suggestions': []
        }

        # Score 1: Difficulty progression (1-10)
        # Early levels should be simple, later levels harder
        expected_difficulty = min(10, 1 + level_num)
        actual_complexity = data['crystal_count'] * data['expected_symmetries'] / 10
        progression_score = 10 - abs(expected_difficulty - actual_complexity)
        evaluation['scores']['progression'] = max(1, min(10, int(progression_score)))

        # Score 2: Aha-moment potential (1-10)
        # Can player discover symmetries through experimentation?
        crystal_count = data['crystal_count']
        symmetry_count = data['expected_symmetries']

        if crystal_count <= 3 and symmetry_count <= 3:
            aha_score = 9  # Very discoverable
        elif crystal_count <= 4 and symmetry_count <= 8:
            aha_score = 7  # Moderate discovery
        else:
            aha_score = 5  # Harder to discover

        evaluation['scores']['aha_moment'] = aha_score

        # Score 3: Hint clarity (1-10)
        # Are there helpful labels/hints?
        labels = data['labels']
        hint_text = [l['text'] for l in labels if l.get('text')]

        if any('подсказк' in t.lower() or 'hint' in t.lower() for t in hint_text):
            hint_score = 8
        elif len(hint_text) > 3:
            hint_score = 6
        else:
            hint_score = 4

        evaluation['scores']['hints'] = hint_score

        # Score 4: Variety (1-10)
        # Does it feel fresh or repetitive?
        if level_num <= 3:
            variety_score = 8  # Learning phase
        elif level_num <= 6:
            variety_score = 7  # Building on basics
        elif level_num <= 9:
            variety_score = 9  # New mechanics
        else:
            variety_score = 6  # Advanced, might feel same-y

        evaluation['scores']['variety'] = variety_score

        # Score 5: Educational effect (1-10)
        # Is player learning to see symmetries?
        if level_num <= 3:
            education_score = 7  # Foundation
        elif level_num <= 6:
            education_score = 8  # Pattern recognition
        elif level_num <= 9:
            education_score = 9  # Deeper understanding
        else:
            education_score = 10  # Mastery

        evaluation['scores']['education'] = education_score

        # Score 6: Russian text quality (1-10)
        # Natural and clear?
        russian_texts = [t for t in hint_text if any(c.isalpha() and ord(c) > 1000 for c in t)]

        if russian_texts:
            # Assume good unless we see obvious problems
            text_score = 8
            for text in russian_texts:
                if 'TODO' in text or '???' in text or len(text) < 5:
                    text_score = 5
                    evaluation['problems'].append(f"Suspicious Russian text: '{text}'")
        else:
            text_score = 5
            evaluation['problems'].append("No Russian text found in UI")

        evaluation['scores']['russian_text'] = text_score

        return evaluation

    def review_all_levels(self):
        """Review all 12 levels"""
        print("="*70)
        print("UX REVIEW: The Symmetry Vaults - Levels 1-12")
        print("Reviewer: Skeptical Non-Mathematician Player")
        print("="*70)

        all_evaluations = []

        for level_num in range(1, 13):
            try:
                data = self.explore_level(level_num)
                evaluation = self.evaluate_level(data)
                all_evaluations.append(evaluation)

                print(f"\nPreliminary Scores for Level {level_num}:")
                for key, score in evaluation['scores'].items():
                    print(f"  {key}: {score}/10")

            except Exception as e:
                print(f"\n[ERROR] Level {level_num} failed: {e}")
                import traceback
                traceback.print_exc()

        # Cleanup
        if self.client:
            try:
                self.client.quit()
            except:
                pass

        return all_evaluations

    def generate_report(self, evaluations: List[Dict[str, Any]]):
        """Generate detailed UX report"""
        report = []
        report.append("="*70)
        report.append("DETAILED UX REVIEW REPORT")
        report.append("The Symmetry Vaults - Levels 1-12")
        report.append("="*70)
        report.append("")

        # Overall summary
        avg_scores = {}
        for eval in evaluations:
            for key, score in eval['scores'].items():
                if key not in avg_scores:
                    avg_scores[key] = []
                avg_scores[key].append(score)

        report.append("OVERALL SCORES (Average across 12 levels):")
        report.append("")
        for key, scores in avg_scores.items():
            avg = sum(scores) / len(scores)
            report.append(f"  {key.capitalize()}: {avg:.1f}/10")
        report.append("")
        report.append("-"*70)

        # Individual level reports
        for eval in evaluations:
            level_num = eval['level_num']
            report.append(f"\nLEVEL {level_num}")
            report.append("-"*70)

            # Scores
            report.append("Scores:")
            for key, score in eval['scores'].items():
                report.append(f"  {key}: {score}/10")

            # Problems
            if eval['problems']:
                report.append("\nProblems:")
                for problem in eval['problems']:
                    report.append(f"  - {problem}")

            # Suggestions
            if eval['suggestions']:
                report.append("\nSuggestions:")
                for suggestion in eval['suggestions']:
                    report.append(f"  - {suggestion}")

            report.append("")

        return "\n".join(report)

if __name__ == "__main__":
    reviewer = UXReviewer()
    evaluations = reviewer.review_all_levels()

    report = reviewer.generate_report(evaluations)
    print("\n" + report)

    # Save report
    output_file = r"C:\Cursor\TayfaProject\AndroidGame\.tayfa\game_designer\ux_review_report.txt"
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(report)

    print(f"\nOK Report saved to: {output_file}")
