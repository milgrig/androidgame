"""
UX Review: World Map and Full Game Flow
Task T038 - Game Designer UX Review

Tests the complete flow:
1. Main Menu -> World Map -> Level -> Completion -> Return to Map

Evaluates:
- World map navigation and clarity
- Visual state communication (LOCKED/AVAILABLE/COMPLETED)
- Transitions between scenes
- Context preservation
- Echo hint system
- Overall player experience
"""

import sys
import os
import time
import json
from typing import Dict, List, Any

# Add agent bridge to path
sys.path.insert(0, "TheSymmetryVaults/tests/agent")
from agent_client import AgentClient

GODOT_PATH = r"C:\Godot\Godot_v4.6.1-stable_win64_console.exe"
PROJECT_PATH = r"C:\Cursor\TayfaProject\AndroidGame\TheSymmetryVaults"


class UXReviewer:
    """UX Reviewer for The Symmetry Vaults - World Map Edition"""

    def __init__(self):
        self.client = None
        self.findings = {
            "world_map": {},
            "transitions": {},
            "echo_hints": {},
            "overall": {},
            "scores": {}
        }
        self.session_log = []

    def log(self, message: str, category: str = "INFO"):
        """Log a message with timestamp"""
        entry = {
            "time": time.time(),
            "category": category,
            "message": message
        }
        self.session_log.append(entry)
        print(f"[{category}] {message}")

    def start_session(self):
        """Start the game session"""
        self.log("Starting UX Review Session", "SESSION")
        self.client = AgentClient(godot_path=GODOT_PATH, project_path=PROJECT_PATH, timeout=20.0)
        # Start without loading a level - we want to see the main menu first
        self.client.start(level_id=None)
        self.log("Game client started successfully", "SESSION")
        time.sleep(1)  # Let UI settle

    def inspect_main_menu(self) -> Dict:
        """Inspect the main menu"""
        self.log("=== INSPECTING MAIN MENU ===", "REVIEW")

        tree = self.client.get_tree()
        buttons = self.client.find_buttons(tree)
        labels = self.client.find_labels(tree)

        findings = {
            "buttons_found": len(buttons),
            "labels_found": len(labels),
            "buttons": [{"path": b["path"], "text": b.get("text", "")} for b in buttons],
            "labels": [{"path": l["path"], "text": l.get("text", "")} for l in labels],
            "clarity": None,
            "issues": []
        }

        # Check for world map button
        map_buttons = [b for b in buttons if "map" in b.get("text", "").lower()
                      or "world" in b.get("text", "").lower()
                      or "Map" in b.get("path", "")]

        if not map_buttons:
            findings["issues"].append("❌ No obvious 'World Map' or 'Map' button found in main menu")
            findings["clarity"] = "POOR"
        else:
            findings["clarity"] = "GOOD"
            findings["map_button"] = map_buttons[0]
            self.log(f"✓ Found map button: {map_buttons[0]}", "REVIEW")

        self.findings["transitions"]["main_menu"] = findings
        return findings

    def navigate_to_world_map(self):
        """Navigate from main menu to world map"""
        self.log("=== NAVIGATING TO WORLD MAP ===", "REVIEW")

        tree = self.client.get_tree()
        buttons = self.client.find_buttons(tree)

        # Try to find and press the map button
        map_buttons = [b for b in buttons if "map" in b.get("text", "").lower()
                      or "world" in b.get("text", "").lower()
                      or "Map" in b["path"]]

        if map_buttons:
            self.log(f"Pressing button: {map_buttons[0]['path']}", "ACTION")
            self.client.press_button(map_buttons[0]["path"])
            time.sleep(1.5)  # Wait for scene transition
            return True
        else:
            # Try to find any way to the map
            self.log("No map button found, checking available actions", "WARNING")
            actions = self.client.list_actions()
            self.log(f"Available actions: {json.dumps(actions, indent=2)}", "DEBUG")
            return False

    def inspect_world_map(self) -> Dict:
        """Deep inspection of the world map UX"""
        self.log("=== INSPECTING WORLD MAP ===", "REVIEW")

        tree = self.client.get_tree()
        buttons = self.client.find_buttons(tree)
        labels = self.client.find_labels(tree)

        findings = {
            "orientation": {},
            "navigation": {},
            "visual_states": {},
            "nonlinearity": {},
            "exploration_feeling": {},
            "issues": []
        }

        # 1. ORIENTATION - Can I understand where I am?
        self.log("--- Testing Orientation ---", "REVIEW")

        title_labels = [l for l in labels if "title" in l["path"].lower()
                       or "wing" in l["path"].lower()
                       or "vault" in l["path"].lower()]

        if not title_labels:
            findings["issues"].append("❌ No clear title/location indicator on map")
            findings["orientation"]["title_present"] = False
        else:
            findings["orientation"]["title_present"] = True
            findings["orientation"]["title_text"] = title_labels[0].get("text", "")
            self.log(f"✓ Found location indicator: '{title_labels[0].get('text', '')}'", "REVIEW")

        # 2. NAVIGATION - What halls can I see and interact with?
        self.log("--- Testing Hall Navigation ---", "REVIEW")

        hall_buttons = [b for b in buttons if "hall" in b["path"].lower()
                       or "level" in b["path"].lower()
                       or "HallButton" in b["path"]]

        findings["navigation"]["hall_buttons_count"] = len(hall_buttons)
        findings["navigation"]["hall_buttons"] = []

        if len(hall_buttons) == 0:
            findings["issues"].append("❌ No hall buttons found on world map")
        else:
            self.log(f"✓ Found {len(hall_buttons)} hall buttons", "REVIEW")

            # Check visual states
            locked_count = 0
            available_count = 0
            completed_count = 0

            for hall_btn in hall_buttons:
                btn_info = {
                    "path": hall_btn["path"],
                    "text": hall_btn.get("text", ""),
                    "disabled": hall_btn.get("disabled", False),
                    "visible": hall_btn.get("visible", True)
                }

                # Try to infer state from properties
                if hall_btn.get("disabled"):
                    btn_info["inferred_state"] = "LOCKED"
                    locked_count += 1
                elif "completed" in hall_btn.get("modulate", "").lower():
                    btn_info["inferred_state"] = "COMPLETED"
                    completed_count += 1
                else:
                    btn_info["inferred_state"] = "AVAILABLE"
                    available_count += 1

                findings["navigation"]["hall_buttons"].append(btn_info)

            findings["visual_states"]["locked_count"] = locked_count
            findings["visual_states"]["available_count"] = available_count
            findings["visual_states"]["completed_count"] = completed_count

            self.log(f"Hall states: {available_count} available, {locked_count} locked, {completed_count} completed", "REVIEW")

        # 3. NONLINEARITY - Can I choose different paths?
        self.log("--- Testing Nonlinearity ---", "REVIEW")

        clickable_halls = [b for b in hall_buttons if not b.get("disabled", False)]
        findings["nonlinearity"]["clickable_halls"] = len(clickable_halls)

        if len(clickable_halls) <= 1:
            findings["nonlinearity"]["choice_available"] = False
            findings["issues"].append("⚠️ Only one path available - no player choice (might be expected for first playthrough)")
        else:
            findings["nonlinearity"]["choice_available"] = True
            self.log(f"✓ Player has {len(clickable_halls)} halls to choose from", "REVIEW")

        # 4. EXPLORATION FEELING - Does it feel like a world?
        self.log("--- Testing Exploration Feeling ---", "REVIEW")

        # Look for visual elements that suggest a "world"
        visual_nodes = []

        def collect_visual_nodes(node, depth=0):
            if depth > 10:
                return
            node_type = node.get("class", "")
            if any(visual in node_type for visual in ["Sprite", "Polygon", "Line2D", "Path", "Visual"]):
                visual_nodes.append(node)
            for child in node.get("children", []):
                collect_visual_nodes(child, depth + 1)

        collect_visual_nodes(tree)
        findings["exploration_feeling"]["visual_elements_count"] = len(visual_nodes)

        if len(visual_nodes) < 10:
            findings["exploration_feeling"]["richness"] = "SPARSE"
            findings["issues"].append("⚠️ Map feels sparse - few visual elements to create world atmosphere")
        elif len(visual_nodes) < 30:
            findings["exploration_feeling"]["richness"] = "MODERATE"
        else:
            findings["exploration_feeling"]["richness"] = "RICH"
            self.log(f"✓ Map has rich visual atmosphere ({len(visual_nodes)} visual elements)", "REVIEW")

        self.findings["world_map"] = findings
        return findings

    def select_and_enter_hall(self, hall_index: int = 0) -> bool:
        """Select a hall and enter it"""
        self.log(f"=== ENTERING HALL (index {hall_index}) ===", "REVIEW")

        tree = self.client.get_tree()
        buttons = self.client.find_buttons(tree)
        hall_buttons = [b for b in buttons if "hall" in b["path"].lower()
                       or "level" in b["path"].lower()
                       or "HallButton" in b["path"]]

        clickable_halls = [b for b in hall_buttons if not b.get("disabled", False)]

        if hall_index >= len(clickable_halls):
            self.log(f"❌ Cannot enter hall {hall_index} - only {len(clickable_halls)} available", "ERROR")
            return False

        hall = clickable_halls[hall_index]
        self.log(f"Entering hall: {hall['path']}", "ACTION")
        self.client.press_button(hall["path"])
        time.sleep(2.0)  # Wait for level to load

        return True

    def play_level_and_complete(self) -> Dict:
        """Play through a level and complete it"""
        self.log("=== PLAYING LEVEL ===", "REVIEW")

        findings = {
            "level_loaded": False,
            "can_understand_goal": None,
            "echo_hints_present": False,
            "completion_clear": False,
            "issues": []
        }

        try:
            state = self.client.get_state()
            findings["level_loaded"] = True
            findings["level_id"] = state.get("level_id", "unknown")
            self.log(f"✓ Level loaded: {findings['level_id']}", "REVIEW")

            # Check if goal is clear
            tree = self.client.get_tree()
            labels = self.client.find_labels(tree)

            goal_labels = [l for l in labels if any(keyword in l.get("text", "").lower()
                          for keyword in ["find", "symmetr", "goal", "objective", "discover"])]

            if goal_labels:
                findings["can_understand_goal"] = "CLEAR"
                findings["goal_text"] = [l["text"] for l in goal_labels]
                self.log(f"✓ Goal is clear: {goal_labels[0].get('text', '')}", "REVIEW")
            else:
                findings["can_understand_goal"] = "UNCLEAR"
                findings["issues"].append("⚠️ No obvious goal/instruction text found")

            # Try to solve the level (simple approach for testing)
            n_crystals = len(state.get("crystals", []))
            self.log(f"Level has {n_crystals} crystals", "INFO")

            # Try identity permutation first
            identity = list(range(n_crystals))
            resp = self.client.submit_permutation(identity)
            time.sleep(0.5)

            # Try a simple swap
            if n_crystals >= 2:
                resp = self.client.swap(0, 1)
                time.sleep(0.5)

                # Check for echo hints
                labels_after = self.client.find_labels()
                hint_labels = [l for l in labels_after if any(keyword in l.get("text", "").lower()
                              for keyword in ["echo", "whisper", "hint", "try"])]

                if hint_labels:
                    findings["echo_hints_present"] = True
                    findings["hint_text"] = [l["text"] for l in hint_labels]
                    self.log(f"✓ Echo hints present: {hint_labels[0].get('text', '')}", "REVIEW")

            # Try to actually complete the level by finding symmetries
            # For a triangle (3 crystals), try rotations
            if n_crystals == 3:
                # Try rotation: 0->1, 1->2, 2->0
                resp = self.client.submit_permutation([1, 2, 0])
                time.sleep(0.5)

                # Try another rotation
                resp = self.client.submit_permutation([2, 0, 1])
                time.sleep(0.5)

            # Check if completed
            state_after = self.client.get_state()
            if state_after.get("completed", False):
                findings["completion_clear"] = True
                self.log("✓ Level completed!", "REVIEW")

                # Check for completion feedback
                time.sleep(1.0)
                labels_complete = self.client.find_labels()
                completion_labels = [l for l in labels_complete if any(keyword in l.get("text", "").lower()
                                    for keyword in ["complete", "solved", "unlocked", "victory", "success"])]

                if completion_labels:
                    findings["completion_feedback"] = [l["text"] for l in completion_labels]
                    self.log(f"✓ Completion feedback: {completion_labels[0].get('text', '')}", "REVIEW")
                else:
                    findings["issues"].append("⚠️ Level completed but no clear feedback shown")

        except Exception as e:
            self.log(f"❌ Error during level play: {e}", "ERROR")
            findings["error"] = str(e)

        self.findings["transitions"]["level_play"] = findings
        return findings

    def return_to_map(self) -> Dict:
        """Return to world map from level"""
        self.log("=== RETURNING TO MAP ===", "REVIEW")

        findings = {
            "return_button_found": False,
            "context_preserved": None,
            "transition_smooth": None,
            "issues": []
        }

        tree = self.client.get_tree()
        buttons = self.client.find_buttons(tree)

        # Look for back/return/map buttons
        return_buttons = [b for b in buttons if any(keyword in b.get("text", "").lower()
                         for keyword in ["back", "return", "map", "exit"])
                         or "Back" in b["path"] or "Return" in b["path"]]

        if not return_buttons:
            findings["issues"].append("❌ No clear 'return to map' button found")
            findings["return_button_found"] = False
        else:
            findings["return_button_found"] = True
            findings["return_button_text"] = return_buttons[0].get("text", "")
            self.log(f"✓ Found return button: {return_buttons[0]['path']}", "REVIEW")

            # Press it
            self.client.press_button(return_buttons[0]["path"])
            time.sleep(1.5)

            # Check if we're back on the map
            tree_after = self.client.get_tree()
            buttons_after = self.client.find_buttons(tree_after)

            hall_buttons = [b for b in buttons_after if "hall" in b["path"].lower()
                           or "HallButton" in b["path"]]

            if hall_buttons:
                findings["transition_smooth"] = True
                self.log("✓ Successfully returned to map", "REVIEW")

                # Check if completed hall is marked as completed
                completed_halls = [b for b in hall_buttons if "completed" in str(b).lower()]
                if completed_halls:
                    findings["context_preserved"] = True
                    self.log("✓ Completed hall is marked as completed", "REVIEW")
                else:
                    findings["context_preserved"] = False
                    findings["issues"].append("⚠️ Cannot verify if completed hall is marked differently")
            else:
                findings["transition_smooth"] = False
                findings["issues"].append("❌ Did not return to map (no hall buttons found)")

        self.findings["transitions"]["return_to_map"] = findings
        return findings

    def evaluate_echo_hints(self) -> Dict:
        """Evaluate the echo hint system specifically"""
        self.log("=== EVALUATING ECHO HINTS ===", "REVIEW")

        findings = {
            "annoyance_level": None,
            "helpfulness": None,
            "progression_visible": False,
            "issues": []
        }

        # This would require actually getting stuck and seeing hints
        # For now, base on what we observed during play
        level_play = self.findings["transitions"].get("level_play", {})

        if level_play.get("echo_hints_present"):
            findings["hints_observed"] = level_play.get("hint_text", [])

            # Check if hints are gentle (not annoying)
            hint_text = " ".join(findings["hints_observed"]).lower()
            if any(word in hint_text for word in ["try", "perhaps", "consider", "might"]):
                findings["annoyance_level"] = "LOW - uses gentle language"
            elif any(word in hint_text for word in ["you must", "do this", "wrong"]):
                findings["annoyance_level"] = "HIGH - too directive"
            else:
                findings["annoyance_level"] = "MEDIUM - neutral tone"

            # Check helpfulness
            if any(word in hint_text for word in ["symmetr", "pattern", "rotation", "reflection"]):
                findings["helpfulness"] = "HIGH - gives conceptual hints"
            else:
                findings["helpfulness"] = "UNCLEAR - need more testing"
        else:
            findings["issues"].append("⚠️ No echo hints observed during play")

        self.findings["echo_hints"] = findings
        return findings

    def generate_scores(self) -> Dict:
        """Generate 1-10 scores for each category"""
        self.log("=== GENERATING SCORES ===", "REVIEW")

        scores = {}

        # 1. WORLD MAP CLARITY (1-10)
        wm = self.findings.get("world_map", {})
        wm_score = 5  # baseline

        if wm.get("orientation", {}).get("title_present"):
            wm_score += 1
        if wm.get("navigation", {}).get("hall_buttons_count", 0) > 0:
            wm_score += 1
        if wm.get("visual_states", {}).get("locked_count", 0) > 0 or wm.get("visual_states", {}).get("completed_count", 0) > 0:
            wm_score += 1  # States are differentiated
        if wm.get("exploration_feeling", {}).get("richness") in ["MODERATE", "RICH"]:
            wm_score += 1

        issues_count = len(wm.get("issues", []))
        wm_score -= min(issues_count, 3)  # Penalize for issues

        scores["world_map_clarity"] = max(1, min(10, wm_score))

        # 2. TRANSITIONS SMOOTHNESS (1-10)
        trans = self.findings.get("transitions", {})
        trans_score = 5

        if trans.get("return_to_map", {}).get("return_button_found"):
            trans_score += 2
        if trans.get("return_to_map", {}).get("transition_smooth"):
            trans_score += 2
        if trans.get("return_to_map", {}).get("context_preserved"):
            trans_score += 1

        scores["transitions_smoothness"] = max(1, min(10, trans_score))

        # 3. NAVIGATION CLARITY (1-10)
        nav_score = 5

        if wm.get("navigation", {}).get("hall_buttons_count", 0) > 5:
            nav_score += 2
        if wm.get("nonlinearity", {}).get("choice_available"):
            nav_score += 2
        if not any("No hall buttons" in issue for issue in wm.get("issues", [])):
            nav_score += 1

        scores["navigation_clarity"] = max(1, min(10, nav_score))

        # 4. ECHO HINTS QUALITY (1-10)
        echo = self.findings.get("echo_hints", {})
        echo_score = 5

        if echo.get("annoyance_level") and "LOW" in echo["annoyance_level"]:
            echo_score += 2
        elif echo.get("annoyance_level") and "HIGH" in echo["annoyance_level"]:
            echo_score -= 2

        if echo.get("helpfulness") == "HIGH - gives conceptual hints":
            echo_score += 2

        scores["echo_hints_quality"] = max(1, min(10, echo_score))

        # 5. OVERALL EXPERIENCE (1-10)
        # Average of other scores with slight weight on transitions
        overall = (
            scores["world_map_clarity"] * 0.3 +
            scores["transitions_smoothness"] * 0.3 +
            scores["navigation_clarity"] * 0.25 +
            scores["echo_hints_quality"] * 0.15
        )
        scores["overall_experience"] = round(overall, 1)

        self.findings["scores"] = scores
        return scores

    def generate_recommendations(self) -> List[str]:
        """Generate specific recommendations"""
        recommendations = []

        wm = self.findings.get("world_map", {})
        trans = self.findings.get("transitions", {})
        echo = self.findings.get("echo_hints", {})

        # High priority recommendations
        if len(wm.get("issues", [])) > 0:
            for issue in wm["issues"]:
                if "❌" in issue:
                    recommendations.append(f"🔴 HIGH PRIORITY: {issue.replace('❌', '').strip()}")

        # Medium priority
        if wm.get("exploration_feeling", {}).get("richness") == "SPARSE":
            recommendations.append("🟡 MEDIUM: Add more visual elements to world map to create atmosphere of exploration")

        if not wm.get("nonlinearity", {}).get("choice_available"):
            recommendations.append("🟡 MEDIUM: Consider allowing 2-3 starting paths for player agency")

        if not trans.get("return_to_map", {}).get("context_preserved"):
            recommendations.append("🟡 MEDIUM: Ensure completed halls are visually distinct when returning to map")

        # Low priority / Polish
        if echo.get("annoyance_level") and "MEDIUM" in echo.get("annoyance_level", ""):
            recommendations.append("🟢 POLISH: Refine echo hint language to be more gentle and exploratory")

        # Positive reinforcement
        if self.findings["scores"].get("overall_experience", 0) >= 7:
            recommendations.append("✅ STRENGTH: Overall flow is solid - focus on polish and visual feedback")

        return recommendations

    def run_full_review(self):
        """Run the complete UX review flow"""
        try:
            # Start the game
            self.start_session()

            # 1. Inspect main menu
            self.inspect_main_menu()

            # 2. Navigate to world map
            # First check what scene we're in
            tree = self.client.get_tree()
            scene_name = tree.get("name", "")
            self.log(f"Current scene: {scene_name}", "INFO")

            # If not on map already, try to navigate
            if "map" not in scene_name.lower():
                nav_success = self.navigate_to_world_map()
                if not nav_success:
                    # Try loading a level directly, which might bring us through the map
                    self.log("Attempting alternative: load level directly", "INFO")
                    self.client.load_level("act1_level01")
                    time.sleep(1)

            # 3. Inspect world map (after navigation or if already there)
            # Re-check scene
            tree = self.client.get_tree()
            self.inspect_world_map()

            # 4. Select and enter a hall
            hall_entered = self.select_and_enter_hall(0)

            if hall_entered:
                # 5. Play level and complete it
                self.play_level_and_complete()

                # 6. Return to map
                self.return_to_map()

            # 7. Evaluate echo hints
            self.evaluate_echo_hints()

            # 8. Generate scores
            self.generate_scores()

            # 9. Generate recommendations
            recommendations = self.generate_recommendations()
            self.findings["recommendations"] = recommendations

        except Exception as e:
            self.log(f"❌ CRITICAL ERROR during review: {e}", "ERROR")
            import traceback
            self.log(traceback.format_exc(), "ERROR")
        finally:
            # Always quit
            if self.client:
                self.log("Shutting down game client", "SESSION")
                self.client.quit()

    def save_report(self, filepath: str):
        """Save the complete UX report"""
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write("# UX REVIEW: World Map and Game Flow\n")
            f.write("## Task T038 - Game Designer Review\n\n")
            f.write(f"**Review Date:** {time.strftime('%Y-%m-%d %H:%M:%S')}\n\n")

            # Scores
            f.write("## 📊 SCORES (1-10)\n\n")
            scores = self.findings.get("scores", {})
            for category, score in scores.items():
                f.write(f"- **{category.replace('_', ' ').title()}**: {score}/10\n")

            f.write("\n---\n\n")

            # Detailed findings
            f.write("## 🗺️ WORLD MAP EVALUATION\n\n")
            wm = self.findings.get("world_map", {})

            f.write("### Orientation\n")
            f.write(f"- Title Present: {wm.get('orientation', {}).get('title_present', 'Unknown')}\n")
            if wm.get('orientation', {}).get('title_text'):
                f.write(f"- Title Text: \"{wm['orientation']['title_text']}\"\n")

            f.write("\n### Navigation\n")
            f.write(f"- Hall Buttons Found: {wm.get('navigation', {}).get('hall_buttons_count', 0)}\n")

            f.write("\n### Visual States\n")
            vs = wm.get("visual_states", {})
            f.write(f"- Locked: {vs.get('locked_count', 0)}\n")
            f.write(f"- Available: {vs.get('available_count', 0)}\n")
            f.write(f"- Completed: {vs.get('completed_count', 0)}\n")

            f.write("\n### Nonlinearity\n")
            nl = wm.get("nonlinearity", {})
            f.write(f"- Player Choice Available: {nl.get('choice_available', False)}\n")
            f.write(f"- Clickable Halls: {nl.get('clickable_halls', 0)}\n")

            f.write("\n### Exploration Feeling\n")
            ef = wm.get("exploration_feeling", {})
            f.write(f"- Visual Richness: {ef.get('richness', 'Unknown')}\n")
            f.write(f"- Visual Elements Count: {ef.get('visual_elements_count', 0)}\n")

            if wm.get("issues"):
                f.write("\n### ⚠️ Issues Found\n")
                for issue in wm["issues"]:
                    f.write(f"- {issue}\n")

            f.write("\n---\n\n")

            # Transitions
            f.write("## 🔄 TRANSITIONS EVALUATION\n\n")
            trans = self.findings.get("transitions", {})

            if trans.get("level_play"):
                f.write("### Level Play\n")
                lp = trans["level_play"]
                f.write(f"- Level Loaded: {lp.get('level_loaded', False)}\n")
                f.write(f"- Goal Clarity: {lp.get('can_understand_goal', 'Unknown')}\n")
                f.write(f"- Echo Hints Present: {lp.get('echo_hints_present', False)}\n")
                f.write(f"- Completion Clear: {lp.get('completion_clear', False)}\n")

            if trans.get("return_to_map"):
                f.write("\n### Return to Map\n")
                rtm = trans["return_to_map"]
                f.write(f"- Return Button Found: {rtm.get('return_button_found', False)}\n")
                f.write(f"- Transition Smooth: {rtm.get('transition_smooth', 'Unknown')}\n")
                f.write(f"- Context Preserved: {rtm.get('context_preserved', 'Unknown')}\n")

            f.write("\n---\n\n")

            # Echo Hints
            f.write("## 💬 ECHO HINTS EVALUATION\n\n")
            echo = self.findings.get("echo_hints", {})
            f.write(f"- Annoyance Level: {echo.get('annoyance_level', 'Not tested')}\n")
            f.write(f"- Helpfulness: {echo.get('helpfulness', 'Not tested')}\n")
            f.write(f"- Progression Visible: {echo.get('progression_visible', False)}\n")

            if echo.get("hints_observed"):
                f.write("\n### Observed Hints\n")
                for hint in echo["hints_observed"]:
                    f.write(f"- \"{hint}\"\n")

            f.write("\n---\n\n")

            # Recommendations
            f.write("## 🎯 RECOMMENDATIONS\n\n")
            recommendations = self.findings.get("recommendations", [])
            if recommendations:
                for rec in recommendations:
                    f.write(f"{rec}\n\n")
            else:
                f.write("No specific recommendations generated.\n")

            f.write("\n---\n\n")

            # Overall Impression
            f.write("## 🎮 OVERALL IMPRESSION\n\n")
            overall_score = scores.get("overall_experience", 0)

            if overall_score >= 8:
                f.write("**EXCELLENT** - The world map and flow are solid. Polish and iterate on details.\n")
            elif overall_score >= 6:
                f.write("**GOOD** - The core experience works, but needs refinement in specific areas.\n")
            elif overall_score >= 4:
                f.write("**NEEDS WORK** - Several UX issues need addressing before this feels polished.\n")
            else:
                f.write("**CRITICAL ISSUES** - Major UX problems that will frustrate players.\n")

            f.write("\n### Would I keep playing?\n")
            if overall_score >= 7:
                f.write("✅ Yes - the flow is engaging and I want to explore more halls.\n")
            elif overall_score >= 5:
                f.write("⚠️ Maybe - some friction points might cause players to bounce.\n")
            else:
                f.write("❌ Unlikely - too many pain points that need fixing first.\n")

            f.write("\n### What would I change first?\n")
            if recommendations:
                high_priority = [r for r in recommendations if "HIGH PRIORITY" in r]
                if high_priority:
                    f.write(f"1. {high_priority[0].replace('🔴 HIGH PRIORITY:', '').strip()}\n")
                    if len(recommendations) > 1:
                        f.write(f"2. {recommendations[1].replace('🟡 MEDIUM:', '').replace('🔴 HIGH PRIORITY:', '').strip()}\n")
                else:
                    f.write(f"1. {recommendations[0].replace('🟡 MEDIUM:', '').strip()}\n")

            f.write("\n---\n\n")
            f.write("## 📋 RAW DATA\n\n")
            f.write("```json\n")
            f.write(json.dumps(self.findings, indent=2))
            f.write("\n```\n")


if __name__ == "__main__":
    print("="*60)
    print("UX REVIEW: World Map and Game Flow")
    print("Task T038 - Game Designer")
    print("="*60)
    print()

    reviewer = UXReviewer()
    reviewer.run_full_review()

    # Save report
    report_path = ".tayfa/game_designer/UX_REVIEW_T038_WORLD_MAP.md"
    reviewer.save_report(report_path)

    print()
    print("="*60)
    print(f"✅ Review complete! Report saved to:")
    print(f"   {report_path}")
    print("="*60)

    # Print summary
    scores = reviewer.findings.get("scores", {})
    print("\nQUICK SUMMARY:")
    print(f"  Overall Experience: {scores.get('overall_experience', 'N/A')}/10")
    print(f"  World Map Clarity: {scores.get('world_map_clarity', 'N/A')}/10")
    print(f"  Transitions: {scores.get('transitions_smoothness', 'N/A')}/10")
    print(f"  Navigation: {scores.get('navigation_clarity', 'N/A')}/10")
    print(f"  Echo Hints: {scores.get('echo_hints_quality', 'N/A')}/10")
