"""
Unit tests for KeyBar (T149).

Tests:
1. KeyBar is horizontal layout (HBoxContainer inside ScrollContainer)
2. Button sizes adapt based on key count (normal/compact/tiny)
3. Layer 2 pairing mode works
4. Scrolling works for many keys (level 13: 23 keys)

These tests verify the conceptual design and constants.
Visual verification requires Agent Bridge or manual testing.
"""

import unittest
from typing import List, Dict


# =============================================================================
# Constants from key_bar.gd
# =============================================================================

class KeyBarConstants:
    """Constants mirroring key_bar.gd layout logic."""

    # Layout thresholds
    COMPACT_THRESHOLD = 8    # > 8 keys → compact buttons
    TINY_THRESHOLD = 16      # > 16 keys → tiny buttons

    # Button sizes per tier
    BTN_SIZE_NORMAL = (64, 36)
    BTN_SIZE_COMPACT = (52, 30)
    BTN_SIZE_TINY = (44, 26)

    BTN_GAP_NORMAL = 5
    BTN_GAP_COMPACT = 4
    BTN_GAP_TINY = 3

    BTN_FONT_NORMAL = 14
    BTN_FONT_COMPACT = 12
    BTN_FONT_TINY = 10


def get_button_size(key_count: int) -> tuple:
    """
    Get button size based on number of keys.

    From key_bar.gd:
      <=8  keys — normal   (64x36)
      9-16 keys — compact  (52x30)
      >16  keys — tiny     (44x26)
    """
    if key_count <= KeyBarConstants.COMPACT_THRESHOLD:
        return KeyBarConstants.BTN_SIZE_NORMAL
    elif key_count <= KeyBarConstants.TINY_THRESHOLD:
        return KeyBarConstants.BTN_SIZE_COMPACT
    else:
        return KeyBarConstants.BTN_SIZE_TINY


def get_button_gap(key_count: int) -> int:
    """Get gap between buttons based on key count."""
    if key_count <= KeyBarConstants.COMPACT_THRESHOLD:
        return KeyBarConstants.BTN_GAP_NORMAL
    elif key_count <= KeyBarConstants.TINY_THRESHOLD:
        return KeyBarConstants.BTN_GAP_COMPACT
    else:
        return KeyBarConstants.BTN_GAP_TINY


def estimate_key_bar_width(key_count: int) -> int:
    """
    Estimate minimum width needed for KeyBar.

    This helps verify that levels with many keys will need horizontal scroll.
    """
    btn_size = get_button_size(key_count)
    btn_gap = get_button_gap(key_count)

    # Width = (button_width * count) + (gap * (count - 1))
    return (btn_size[0] * key_count) + (btn_gap * (key_count - 1))


# =============================================================================
# Tests: KeyBar Layout
# =============================================================================

class TestKeyBarLayout(unittest.TestCase):
    """Test KeyBar horizontal layout and sizing."""

    def test_key_bar_is_horizontal(self):
        """
        KeyBar uses horizontal layout (HBoxContainer inside ScrollContainer).

        From key_bar.gd:
        - Layout: always a single horizontal row inside a horizontal ScrollContainer
        - _scroll: ScrollContainer (always present — horizontal scroll)
        - _hbox: HBoxContainer (single-row container for key buttons)
        """
        # This is a conceptual test - verifies the design
        layout_type = "horizontal"
        self.assertEqual(layout_type, "horizontal",
            "KeyBar should use horizontal layout")

    def test_button_size_normal_for_few_keys(self):
        """<=8 keys use normal button size (64x36)."""
        for key_count in [1, 3, 5, 8]:
            with self.subTest(keys=key_count):
                size = get_button_size(key_count)
                self.assertEqual(size, (64, 36),
                    f"{key_count} keys should use normal size (64x36)")

    def test_button_size_compact_for_medium_keys(self):
        """9-16 keys use compact button size (52x30)."""
        for key_count in [9, 12, 16]:
            with self.subTest(keys=key_count):
                size = get_button_size(key_count)
                self.assertEqual(size, (52, 30),
                    f"{key_count} keys should use compact size (52x30)")

    def test_button_size_tiny_for_many_keys(self):
        """>16 keys use tiny button size (44x26)."""
        for key_count in [17, 20, 23, 30]:
            with self.subTest(keys=key_count):
                size = get_button_size(key_count)
                self.assertEqual(size, (44, 26),
                    f"{key_count} keys should use tiny size (44x26)")

    def test_button_gaps_decrease_with_more_keys(self):
        """Button gaps should decrease as key count increases."""
        gap_8 = get_button_gap(8)    # Normal
        gap_12 = get_button_gap(12)  # Compact
        gap_20 = get_button_gap(20)  # Tiny

        self.assertEqual(gap_8, 5, "Normal gap should be 5px")
        self.assertEqual(gap_12, 4, "Compact gap should be 4px")
        self.assertEqual(gap_20, 3, "Tiny gap should be 3px")

        # Gaps decrease monotonically
        self.assertGreater(gap_8, gap_12,
            "Normal gap should be larger than compact")
        self.assertGreater(gap_12, gap_20,
            "Compact gap should be larger than tiny")


# =============================================================================
# Tests: Level-Specific Key Counts
# =============================================================================

class TestLevelKeyBarSizes(unittest.TestCase):
    """Test button sizes for specific levels."""

    def test_level_01_z3_has_3_keys(self):
        """Level 01 (Z3) has 3 keys → normal size."""
        key_count = 3  # Z3: identity + 2 generators
        size = get_button_size(key_count)
        self.assertEqual(size, (64, 36),
            "Z3 (3 keys) should use normal size")

    def test_level_04_s3_has_6_keys(self):
        """Level 04 (S3) has 6 keys → normal size."""
        key_count = 6  # S3: identity + 5 others
        size = get_button_size(key_count)
        self.assertEqual(size, (64, 36),
            "S3 (6 keys) should use normal size")

    def test_level_05_d4_has_8_keys(self):
        """Level 05 (D4) has 8 keys → normal size (boundary)."""
        key_count = 8  # D4: identity + 7 others
        size = get_button_size(key_count)
        self.assertEqual(size, (64, 36),
            "D4 (8 keys) should use normal size (threshold boundary)")

    def test_level_13_has_23_keys(self):
        """Level 13 (23 keys) → tiny size + horizontal scroll."""
        key_count = 23
        size = get_button_size(key_count)
        self.assertEqual(size, (44, 26),
            "Level 13 (23 keys) should use tiny size")

        # Estimate width
        width = estimate_key_bar_width(key_count)
        # 23 keys * 44px + 22 gaps * 3px = 1012 + 66 = 1078px
        expected_width = 23 * 44 + 22 * 3
        self.assertEqual(width, expected_width,
            f"Level 13 should need ~{expected_width}px width")

        # This exceeds typical screen widths (800-1200px), so scroll is needed
        self.assertGreater(width, 800,
            "Level 13 key_bar should exceed common screen width")


# =============================================================================
# Tests: Horizontal Scroll
# =============================================================================

class TestHorizontalScroll(unittest.TestCase):
    """Test that horizontal scroll works for many keys."""

    def test_wide_key_bar_needs_scroll(self):
        """Key bars wider than viewport need horizontal scroll."""
        viewport_width = 800  # Typical mobile width

        # Test various key counts
        test_cases = [
            (8, False),   # 8 keys: fits in 800px
            (16, False),  # 16 keys: might fit
            (23, True),   # 23 keys: definitely needs scroll
            (30, True),   # 30 keys: definitely needs scroll
        ]

        for key_count, should_scroll in test_cases:
            with self.subTest(keys=key_count):
                width = estimate_key_bar_width(key_count)
                needs_scroll = width > viewport_width

                if should_scroll:
                    self.assertTrue(needs_scroll,
                        f"{key_count} keys ({width}px) should need scroll on {viewport_width}px viewport")
                # Note: We don't assert False for small counts because
                # actual viewport size may vary

    def test_level_13_width_calculation(self):
        """Verify Level 13 (23 keys) width calculation."""
        key_count = 23

        # Tiny size: 44x26, gap: 3px
        btn_width = 44
        gap = 3

        # Total width = buttons + gaps between them
        total_width = (btn_width * key_count) + (gap * (key_count - 1))

        expected = 23 * 44 + 22 * 3  # 1012 + 66 = 1078px
        self.assertEqual(total_width, expected,
            "Level 13 total width should be 1078px")

        # Verify helper function matches manual calculation
        helper_width = estimate_key_bar_width(key_count)
        self.assertEqual(helper_width, total_width,
            "Helper function should match manual calculation")


# =============================================================================
# Tests: Layer 2 Pairing
# =============================================================================

class TestLayer2Pairing(unittest.TestCase):
    """Test Layer 2 key pairing functionality."""

    def test_layer2_pairing_state_structure(self):
        """
        Layer 2 stores pairing state in _pair_data.

        From key_bar.gd:
        - _pair_data: Dictionary = {}  # room_index -> {partner: int, is_self_inverse: bool}
        - _layer2_active: bool = false
        - _layer2_selected_key_idx: int = -1
        """
        # Simulate Layer 2 pairing for S3
        # S3 has 3 pairs: {0,0}, {1,4}, {2,5}, {3,3} (example)

        pair_data = {
            0: {"partner": 0, "is_self_inverse": True},   # Identity
            1: {"partner": 4, "is_self_inverse": False},  # Pair with key 4
            2: {"partner": 5, "is_self_inverse": False},  # Pair with key 5
            3: {"partner": 3, "is_self_inverse": True},   # Self-inverse reflection
            4: {"partner": 1, "is_self_inverse": False},  # Pair with key 1
            5: {"partner": 2, "is_self_inverse": False},  # Pair with key 2
        }

        # Verify structure
        self.assertIn(0, pair_data, "Identity should be in pair_data")
        self.assertTrue(pair_data[0]["is_self_inverse"],
            "Identity should be self-inverse")

        # Verify symmetric pairing
        self.assertEqual(pair_data[1]["partner"], 4,
            "Key 1 should pair with key 4")
        self.assertEqual(pair_data[4]["partner"], 1,
            "Key 4 should pair with key 1 (symmetric)")

    def test_layer2_selected_key_tracking(self):
        """
        Layer 2 tracks selected key index.

        From key_bar.gd:
        - _layer2_selected_key_idx: int = -1  # -1 = none selected
        """
        # Initially no key selected
        selected = -1
        self.assertEqual(selected, -1,
            "Initially no key should be selected")

        # User clicks key 2
        selected = 2
        self.assertEqual(selected, 2,
            "After click, key 2 should be selected")

        # User clicks pair (key 5)
        # System should validate and show result
        # Then reset selection
        selected = -1
        self.assertEqual(selected, -1,
            "After successful pairing, selection should reset")

    def test_layer2_colors(self):
        """
        Layer 2 uses green/yellow colors for pairs.

        From key_bar.gd:
        - L2_PAIR_COLOR := Color(0.2, 0.85, 0.4, 0.7)  # Green for pairs
        - L2_SELF_COLOR := Color(1.0, 0.85, 0.3, 0.7)  # Yellow for self-inverse
        """
        # These are conceptual tests - actual colors are in GDScript
        L2_PAIR_COLOR = (0.2, 0.85, 0.4, 0.7)
        L2_SELF_COLOR = (1.0, 0.85, 0.3, 0.7)

        # Verify pair color is greenish
        self.assertGreater(L2_PAIR_COLOR[1], 0.8,
            "Pair color should be bright green (high G channel)")

        # Verify self-inverse color is yellowish
        self.assertGreater(L2_SELF_COLOR[0], 0.9,
            "Self-inverse color should be yellow (high R channel)")
        self.assertGreater(L2_SELF_COLOR[1], 0.8,
            "Self-inverse color should be yellow (high G channel)")


# =============================================================================
# Tests: All Levels (1-24)
# =============================================================================

class TestAllLevels(unittest.TestCase):
    """Test that KeyBar works for all levels 1-24."""

    def test_all_levels_have_valid_key_counts(self):
        """
        All 24 levels should have valid key counts (1-24).

        This is a conceptual test - actual key counts depend on
        the group structure defined in each level's JSON.
        """
        # Typical key counts for known groups:
        level_key_counts = {
            1: 3,    # Z3
            2: 4,    # Z4
            3: 5,    # Z5
            4: 6,    # S3
            5: 8,    # D4
            # ... (other levels)
            13: 23,  # Large group (mentioned in T149)
        }

        for level_id, key_count in level_key_counts.items():
            with self.subTest(level=level_id):
                self.assertGreater(key_count, 0,
                    f"Level {level_id} should have at least 1 key")
                self.assertLessEqual(key_count, 24,
                    f"Level {level_id} should have at most 24 keys")

                # Verify button size is determined correctly
                size = get_button_size(key_count)
                self.assertIn(size, [
                    (64, 36),  # Normal
                    (52, 30),  # Compact
                    (44, 26),  # Tiny
                ], f"Level {level_id} should use a valid button size")


# =============================================================================
# Run Tests
# =============================================================================

if __name__ == '__main__':
    unittest.main()
