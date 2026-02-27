# UX Review: New Levels & Layer 2 Flow
**Game Designer Review - Task T090**
**Date:** 2026-02-27
**Reviewer:** Game Designer (Skeptical UX Evaluator)

---

## Executive Summary

This review evaluates the Act 2 levels (levels 13-16) introducing subgroups and the new Layer 2 inverse key mechanic. Overall, the implementation demonstrates strong pedagogical design with a clear progression from visual to abstract thinking. However, several UX friction points could impede player flow, particularly in the Layer 2 transition and subgroup discovery mechanics.

**Key Findings:**
- ✅ Difficulty curve is well-paced with appropriate scaffolding
- ✅ Layer 2 green color scheme is visually distinct
- ⚠️ Layer 2 transition lacks tutorial guidance
- ⚠️ Inverse key mechanic is not immediately intuitive
- ❌ Subgroup discovery requires heavy reliance on trial-and-error

---

## Part 1: New Levels Review (Act 2, Levels 13-16)

### 1.1 Difficulty Curve Assessment

**Level 13 (S3 - First Inner Lock)** ⭐⭐⭐⭐
- **Pedagogical Goal:** Introduction to subgroups via obvious example (rotations within S3)
- **Difficulty:** Appropriate first step
- **Strengths:**
  - Players already know S3 from Level 9 (Act 1)
  - The rotation subgroup {e, r1, r2} is conceptually familiar
  - Single inner door reduces cognitive load
  - Clear pedagogical hint: "part of the keys forms a closed set"

- **Concerns:**
  - The term "inner door" appears without prior explanation
  - Win condition changes from "find all keys" to "identify subgroups" without explicit tutorial
  - Hints assume players understand closure property

**Recommendation:** Add a brief intro cutscene or dialog explaining "inner doors" as a new mechanic.

---

**Level 14 (D4 - Three Inner Locks)** ⭐⭐⭐⭐⭐
- **Pedagogical Goal:** Multiple subgroups of different orders within the same group
- **Difficulty:** Perfect escalation from Level 13
- **Strengths:**
  - THREE inner doors create compelling complexity
  - Nested structure (Z2_180 ⊂ Z4, Z2_180 ⊂ V4) is brilliant pedagogical design
  - Players must distinguish between Z4 (cyclic) and V4 (Klein) despite same order
  - D4 is familiar from Level 5, providing continuity

- **Concerns:**
  - Players may get overwhelmed by 8 keys + 3 doors
  - The distinction between normal and non-normal subgroups is mentioned in data but not explained to players
  - Echo hints are good but may arrive too late

**Recommendation:** Consider pre-highlighting the {e, r2} pair as a "warm-up" door (order 2 is simplest).

---

**Level 15 (Z2×Z3 - Two Worlds)** ⭐⭐⭐⭐⭐
- **Pedagogical Goal:** Visually obvious subgroup (cluster rotations)
- **Difficulty:** Excellent pacing - easier than Level 14 but conceptually rich
- **Strengths:**
  - Visual clustering makes subgroup OBVIOUS (thick edges preserve structure)
  - Two identical triangles → intuitive symmetry
  - Dual inner doors {rotations, swap} offer choice
  - Great example of "structure reveals subgroup"

- **Concerns:**
  - None significant - this is a model level

**Verdict:** Best-designed level in Act 2. Use this as template for future "visually obvious" subgroups.

---

**Level 16 (D4 - Hidden Subgroup)** ⭐⭐⭐⭐
- **Pedagogical Goal:** Force reliance on Cayley table instead of visual inspection
- **Difficulty:** Appropriate challenge, but frustration risk is HIGH
- **Strengths:**
  - Central fixed node brilliantly masks the structure
  - Forces players to engage with composition table
  - "strongly_encourage_cayley": true is a good design choice
  - Pedagogical contrast with Level 14 (same group, different presentation)

- **Concerns:**
  - Players may feel "cheated" that visual pattern doesn't work
  - Cayley table is complex (8×8) - requires scrolling/panning?
  - Hints say "don't use visuals" but don't teach HOW to read Cayley efficiently
  - Risk of trial-and-error fatigue

**Recommendation:**
1. Add a mini-tutorial on reading Cayley tables: "Look for closed blocks"
2. Consider highlighting closure violations in red when player attempts wrong subgroup
3. Add a "Cayley Inspector" tool that shows "What happens if I add this element to my current set?"

---

### 1.2 Group Introduction Pacing

**Progression Analysis:**

```
Act 1 Groups:
Level 1:  Z3 (order 3)
Level 5:  D4 (order 8)
Level 9:  S3 (order 6)
Level 12: D4 (order 8, generators emphasized)

Act 2 Groups:
Level 13: S3 (order 6, subgroups)
Level 14: D4 (order 8, subgroups)
Level 15: Z6 ≅ Z2×Z3 (order 6, visual clusters)
Level 16: D4 (order 8, hidden structure)
```

**Assessment:** ⭐⭐⭐⭐⭐

- Excellent reuse of familiar groups (S3, D4) in new contexts
- Players build on prior knowledge rather than constant novelty
- Z6 as Z2×Z3 product introduces new concept without overwhelming
- Order progression (6 → 8 → 6 → 8) maintains engagement without runaway complexity

**Concern:** The jump from order 8 to potentially higher orders (if Act 2 continues) could be steep. Consider adding order 12 (A4 or D6) before jumping to order 24+.

---

### 1.3 Graph Layout Visual Clarity

**Level-by-Level Evaluation:**

| Level | Graph Type | Clarity Rating | Notes |
|-------|-----------|---------------|-------|
| 13 | Triangle (S3) | ⭐⭐⭐⭐⭐ | Perfect - simple, symmetric |
| 14 | Square (D4) | ⭐⭐⭐⭐⭐ | Clean axes make reflections obvious |
| 15 | Two triangles | ⭐⭐⭐⭐⭐ | Thick edges clearly distinguish clusters |
| 16 | Star + center | ⭐⭐⭐⭐ | Intentionally confusing (good), but may frustrate |

**General Observations:**
- Node positioning is mathematically precise and visually balanced
- Color coding (same color per cluster in Level 15) is excellent
- Edge types (standard, thick, glowing, dashed) are semantically meaningful

**Concern:** Level 16's "dashed" edges on the outer square may be too subtle. Consider making them more visually distinct (e.g., animated shimmer).

---

## Part 2: Layer 2 UX Review

### 2.1 Inverse Key Mechanic Intuitiveness

**Initial Impression:** ⭐⭐⭐ (Moderate - requires learning curve)

**How it works:**
- Graph becomes read-only (no crystal dragging)
- New panel replaces room map: shows key ↔ inverse pairs
- Player selects a key, then chooses its inverse from candidate pool
- Correct pairing: green glow + composition feedback ("r1 ∘ r2 = e ✓")
- Wrong pairing: red shake + shows actual result ("r1 ∘ s01 = s02 — не тождество")

**Strengths:**
- Clear visual feedback (green/red, checkmarks)
- Composition display teaches group operation explicitly
- Self-inverse callout ("s ∘ s = e") highlights special cases
- Bidirectional pairing (A↔B auto-pairs B↔A) reduces busywork

**Weaknesses:**
1. **No explicit tutorial:** Players must infer mechanics from UI alone
2. **"Inverse" concept not pre-taught:** Layer 1 never mentions inverses explicitly
3. **Candidate pool is unsorted:** All keys appear together - no visual grouping by type
4. **No preview mechanism:** Player can't see "what would happen" before committing
5. **Error feedback is passive:** Red text explains what went wrong but doesn't suggest what to try

**Critical UX Gap:** First-time players will likely:
- Click randomly on inverse slot expecting drag-and-drop
- Not understand why composition matters
- Not realize they can use the graph preview when hovering candidates

**Recommendations:**

**High Priority:**
1. Add a 1-level "Layer 2 Tutorial" before Level 13:
   - Tiny group (Z2 or Z3)
   - Interactive callouts: "Select this key" → "Now find what undoes it"
   - Show composition visually on the graph

2. Add hover preview: When hovering a candidate, show:
   - Its permutation animating on the graph
   - Tentative composition result: "r1 ∘ ??? = ?"

3. Group candidates by type in the pool:
   - Rotations | Reflections (for D4)
   - Visual dividers between groups

**Medium Priority:**
4. Add a "Hint: Try composing" button that suggests combining selected key with each candidate
5. Make the instruction label more directive: "Найдите ключ, который при комбинации даёт Тождество"

---

### 2.2 Green Color Scheme Distinctiveness

**Assessment:** ⭐⭐⭐⭐⭐

**Layer 2 Color Constants (from code):**
```gdscript
L2_GREEN := Color(0.2, 0.85, 0.4, 1.0)          # Bright emerald
L2_GREEN_DIM := Color(0.15, 0.55, 0.3, 0.7)     # Muted teal
L2_GREEN_BG := Color(0.02, 0.06, 0.03, 0.8)     # Deep forest
L2_GREEN_BORDER := Color(0.15, 0.45, 0.25, 0.7) # Sage outline
```

**Visual Impact:**
- Unmistakably distinct from Layer 1's blue/purple tones
- Conveys "second layer" through color shift
- Green = "growth/deeper understanding" thematically appropriate
- Borders, labels, and UI elements are consistently themed

**Strengths:**
- Level number label adds "· Слой 2: Обратные" suffix
- Map frame title changes to "Обратные ключи"
- Crystals get green-tinted modulate (0.7, 0.9, 0.75, 0.85) + idle pulse
- Counter updates to "Обратные: X / Y"

**Minor Concern:** Crystals in Layer 2 are dimmed (modulate 0.85 alpha) to signal "read-only" - but this could be interpreted as "inactive" or "disabled". Consider alternative signaling:
- Subtle green aura around crystals instead of dimming
- "Locked" icon overlay on first 2-3 crystals until player understands

---

### 2.3 Layer 1 → Layer 2 Transition Smoothness

**Assessment:** ⭐⭐ (Significant friction)

**Current Flow:**
1. Player completes Level 12 (or any 12 halls)
2. Wing 2 (Inner Locks) unlocks on map
3. Player clicks Level 13
4. **SUDDEN CHANGE:** Graph is read-only, new panel appears, no explanation

**What's Missing:**
- No "Welcome to Layer 2" dialog or cutscene
- No explanation of WHY the graph is now read-only
- No connection between "finding subgroups" (Level 13 goal) and "finding inverses" (Layer 2 mechanic)
- The pedagogical concept "every action can be undone" appears only in Layer 2 completion summary - should be introduced earlier

**Player Confusion Risk:**
- "Why can't I drag crystals anymore? Is the game broken?"
- "What does 'inverse' mean in this context?"
- "How does this relate to the 'inner doors' I need to open?"

**Critical Issue:** Layer 2 levels have TWO overlapping mechanics:
1. Layer 1 subgroup discovery (inner doors) - win condition for the LEVEL
2. Layer 2 inverse pairing - completion metric for the LAYER

This is confusing because:
- Level 13's JSON has `"win_condition": "inner_doors_only"` (Layer 1 logic)
- But Layer 2 is active, adding inverse pairing as a separate goal
- Unclear if player must do BOTH or EITHER

**Recommendation:**

**Option A: Explicit Tutorial Level**
- Create "Layer 2 Prologue" between Wing 1 and Wing 2
- Narrator/Echo voice: "The vault has deeper chambers. To enter, you must master a new skill..."
- Mini-level with Z3: Teaches inverse pairing in isolation
- After completion: "Now you can explore the Inner Locks"

**Option B: Gradual Introduction**
- Make Level 13 ONLY use Layer 1 mechanics (no inverse pairing yet)
- Add tooltip when player completes Level 13: "You've opened an inner door. Ready for the next layer?"
- Layer 2 activates on Level 14+

**Option C: Clearer Signaling (Minimal Change)**
- Add a one-time modal dialog on first Layer 2 level:
  - Title: "НОВЫЙ СЛОЙ: Обратные ключи"
  - Body: "Каждое действие можно отменить. Найдите для каждого ключа его обратный."
  - Button: "ПОНЯТНО"
- Make the inverse pairing panel slide in with animation (not instant spawn)

**Preferred:** Combination of A + C for best UX.

---

## Part 3: Specific Improvement Suggestions

### 3.1 Layer 2 Improvements

**Issue 1: Inverse Pairing Panel is Dense**
- Current layout crams pair slots + candidates into map area
- Scrolling is required for groups with >5 elements
- Candidate buttons are small (56×28px) - hard to tap on mobile

**Suggestion:**
- Make panel draggable/resizable OR
- Add collapse/expand toggle for candidate pool
- Increase button size to 64×36px for touch targets

---

**Issue 2: No Composition Visualization**
- Feedback shows text: "r1 ∘ r2 = e ✓"
- But graph doesn't visually show the composition happening

**Suggestion:**
- When player pairs correctly, animate BOTH permutations:
  1. Show key's permutation (crystals glow + virtual move)
  2. Show inverse's permutation (crystals glow + return to origin)
  3. Final state: all crystals back to original positions (identity)
- Duration: 2-3 seconds with clear "undo" visual language

---

**Issue 3: Self-Inverse Special Case Not Pre-Explained**
- Reflections are self-inverse (s∘s=e)
- Current feedback: "↻ Отражение по горизонтали — сам себе обратный! (s ∘ s = e)"
- But this appears AFTER player discovers it

**Suggestion:**
- Add a hint before first self-inverse level (probably D4 in Layer 2):
  - "Некоторые ключи — свои собственные обратные. Попробуйте отражения!"
- Visually distinguish self-inverse candidates (e.g., circular arrow icon on button)

---

**Issue 4: Identity Element Auto-Paired Without Explanation**
- Code: `if pair.is_identity: pair.paired = true; pair.revealed = true`
- Player sees "e ↔ e ✓" grayed out, pre-completed
- No explanation WHY

**Suggestion:**
- Add tooltip on identity pair: "Тождество — обратный самому себе (e ∘ e = e)"
- Make it clickable to show a brief explanation

---

### 3.2 Subgroup Discovery Improvements

**Issue 1: "Inner Doors" Mechanic Lacks Visual Signaling**
- JSON specifies `"inner_doors": [...]` but these aren't visible as distinct UI elements
- Unclear if doors exist in the 3D space or are abstract

**Suggestion:**
- If doors are visual: Make them more prominent (glow, particle effects)
- If doors are abstract: Show them as mini-panels on the HUD with:
  - Icon representing subgroup type (rotation, reflection, etc.)
  - Progress indicator: "Need 3 keys" → "2/3 found" → "Unlocked ✓"

---

**Issue 2: Subgroup Validation Feedback is Unclear**
- Current mechanism (inferred from Act 2 JSONs): Player tries a set of keys, system validates closure
- But HOW does player submit a subset for validation?

**Assumption Check:** Is there a "Check Subgroup" button? Or does the system auto-validate when player discovers certain keys?

**Suggestion (if manual check):**
- Add a "Subgroup Workspace" panel where player drags keys to test
- Real-time feedback: "Closure: ✓" / "Closure: ✗ (r1∘s01=s02 not in set)"
- Visual: Highlight missing elements in red

---

**Issue 3: Level 16's "Hidden Subgroup" May Cause Rage-Quit**
- Deliberately confusing design (good for advanced players)
- But no safety net for struggling players

**Suggestion:**
- Add a "Struggling?" hint after 5 minutes:
  - "Таблица Кэли показывает замкнутые блоки. Ищите элементы, которые всегда остаются внутри подмножества."
- Offer optional "Show me closure violations" mode (highlight non-closed attempts in real-time)

---

### 3.3 General UX Polish

**Issue 1: No Progress Indicator for Act 2**
- Hall tree shows 12/24 for Wing 1, but Wing 2 only has 4 levels currently
- Unclear if 4 levels = complete or if more are coming

**Suggestion:**
- Update hall_tree.json to show "4 / 12" for Wing 2 (if 12 is planned)
- Add "Слои: 1/5 завершено" indicator on map screen

---

**Issue 2: Layer 2 Completion Summary is Great But Arrives Late**
- Summary panel shows all pairs + insight message
- But no equivalent for Layer 1 completion

**Suggestion:**
- Add Layer 1 completion summary too:
  - "Слой 1 — Ключи завершён!"
  - Show resonances discovered, groups mastered, etc.
  - Creates symmetry between layers

---

**Issue 3: Resonances (Hall Connections) Not Yet Utilized**
- hall_tree.json defines resonances (e.g., Z3 ⊂ S3 between levels 1 & 9)
- But unclear if these appear in-game

**Suggestion:**
- When player completes both halls in a resonance, show a popup:
  - "РЕЗОНАНС ОБНАРУЖЕН"
  - "Level 1 (Z3) is a subgroup of Level 9 (S3)"
  - Reward: Unlock a new path or bonus insight

---

## Part 4: Summary Ratings

### 4.1 Difficulty Curve
⭐⭐⭐⭐⭐ **Excellent**

- Smooth escalation from simple (Level 13: S3 single door) to complex (Level 16: D4 hidden)
- Appropriate use of familiar groups as scaffolding
- Visual → abstract progression is pedagogically sound

**Minor Gap:** No explicit bridge between "generators" (Level 12 emphasis) and "inverses" (Layer 2 focus). Consider adding a transitional level that connects these concepts.

---

### 4.2 Layer 2 Intuitiveness
⭐⭐⭐ **Needs Work**

- Mechanic is well-designed but **under-explained**
- Transition from Layer 1 is abrupt
- Feedback is good once engaged, but initial confusion is high

**Blockers:**
1. No tutorial/onboarding for Layer 2
2. Read-only graph is jarring without context
3. Composition concept not pre-taught

**Fixes:** Add tutorial level + modal explanation + hover previews.

---

### 4.3 Visual Distinctiveness
⭐⭐⭐⭐⭐ **Excellent**

- Green color scheme is unmistakable and thematically appropriate
- UI elements consistently themed
- Graph read-only state clearly signaled (dimming + pulse)

**Nitpick:** Dimmed crystals could use a positive visual (green aura) instead of just reduced alpha.

---

### 4.4 Graph Layouts
⭐⭐⭐⭐⭐ **Excellent**

- Clean, symmetric, mathematically precise
- Edge types meaningfully distinguish structure
- Level 15's clustering is masterful

**Concern:** Level 16's intentional confusion works but risks frustration. Add scaffolding.

---

## Part 5: Prioritized Action Items

### Must Fix (Blockers)
1. **Add Layer 2 tutorial level** (Z3 or Z4, explicit inverse pairing walkthrough)
2. **First-time modal dialog** on Layer 2 entry explaining mechanics
3. **Hover preview** in inverse pairing panel (show composition before committing)

### Should Fix (Quality)
4. **Subgroup discovery UI** - clarify how players submit/test subsets
5. **Cayley table helper** for Level 16 - teach how to spot closure
6. **Composition visualization** - animate permutations when pairing succeeds

### Nice to Have (Polish)
7. **Draggable/resizable panels** in Layer 2
8. **Layer 1 completion summary** (symmetry with Layer 2)
9. **Resonance popups** when related halls are completed
10. **Self-inverse pre-hint** before first D4 in Layer 2

---

## Conclusion

The new levels and Layer 2 mechanics demonstrate **excellent pedagogical design** with a clear progression from intuitive (Level 15's visual clusters) to abstract (Level 16's hidden subgroups). The difficulty curve is well-balanced, and the green color scheme successfully signals a new conceptual layer.

However, **the Layer 2 transition suffers from inadequate onboarding**. Players are expected to infer inverse pairing mechanics without explicit instruction, risking confusion and disengagement. The subgroup discovery mechanic (inner doors) is conceptually strong but implementation details remain unclear.

**Overall Grade: B+ (Very Good, with fixable gaps)**

**Recommendation:** Implement the three "Must Fix" items before wider release. Layer 2 has the potential to be a standout feature, but only if players understand what they're supposed to do.

---

## Appendix: Tested Flow Simulation

**Simulated Player Journey (New Player, No Instructions):**

1. ✅ Completes Wing 1 (12 halls) - familiar mechanics, smooth
2. ✅ Sees Wing 2 unlock - excited for new content
3. ❓ Clicks Level 13 - graph loads, looks normal
4. ❌ **Tries to drag crystal - nothing happens** - confusion starts
5. ❓ Notices new green panel on right - "Обратные ключи"
6. ❓ Sees pair slots with "???" - unclear what to do
7. ❌ **Clicks on inverse slot - nothing happens** - more confusion
8. 🤔 Reads instruction: "Выберите ключ, затем его обратный"
9. ✅ Clicks on a pair slot (left side) - highlights
10. ❓ Sees candidate pool - tries clicking "r1"
11. ❌ **Wrong answer: "r1 ∘ r1 = r2 — не тождество"** - learns composition matters
12. 💡 Realizes need to find key where composition = e
13. 🔄 Tries candidates randomly until success
14. ✅ Eventually completes all pairs - sees summary

**Friction Points:**
- Steps 4, 7 (expected drag-and-drop, didn't work)
- Step 11 (first failure teaches mechanic retroactively - not ideal)

**Ideal Flow (With Tutorial):**
- Tutorial level teaches steps 8-13 explicitly before Level 13
- First failure includes hint: "Не то! Попробуйте найти ключ, который 'отменяет' r1"

---

**End of Review**
