# UX Review: Levels 1-3 of "The Symmetry Vaults"
## Skeptical Non-Mathematician Player Perspective

**Reviewer Role:** Simulated first-time player with no mathematics background
**Date:** 2026-02-21
**Review Method:** Deep code analysis + level design analysis

---

## Executive Summary

**TL;DR:** The game has a solid foundation but suffers from critical onboarding issues. Players will struggle to understand what to do, why they're doing it, and whether they're making progress. The "aha moment" is obscured by unclear objectives and insufficient feedback. **This needs significant UX work before it's fun or accessible to non-mathematicians.**

**Overall Ratings (Levels 1-3):**
- **Discoverability:** 3/10 ⚠️
- **Aha Moment Achievability:** 4/10 ⚠️
- **Visual Feedback Quality:** 7/10 ✓
- **Desire to Continue:** 4/10 ⚠️

---

## Question 1: Can I Figure Out What to Do Without Instructions?

### ❌ **NO - Critical Onboarding Problems**

**What happens when I launch Level 1:**
- I see three red crystals arranged in a triangle with lines connecting them
- I see text: "The Triangle Vault" and "Three crystals, three secrets"
- I see a counter: "Symmetries: 0 / 3"
- After 30 seconds, a hint appears: "Try dragging a crystal onto another one"

**Problems:**

1. **No Clear Goal Statement**
   - "Three crystals, three secrets" is poetic but meaningless
   - I don't know what a "symmetry" is in this context
   - I don't know what "0 / 3" means - 3 what? Secret passwords? Combinations?
   - The subtitle should say something actionable like "Find all the ways to rearrange this pattern"

2. **The 30-Second Wait is Death**
   - Modern players give games 5-10 seconds, not 30
   - By the time the hint appears, many will have already quit
   - The hint should appear immediately or within 5 seconds of inactivity

3. **"Try dragging a crystal" Isn't Enough**
   - Okay, I drag a crystal. Then what?
   - What am I looking for? What makes a drag "successful"?
   - The hint needs to say: "Try dragging a crystal onto another to swap them. Some swaps will unlock secrets!"

4. **Missing Tutorial Elements**
   - No visual indicator that crystals are draggable (no cursor change on hover until I tested the code)
   - No animation or "shake" to draw attention to interactive elements
   - No explicit celebration when I find the identity transformation (doing nothing)

**What I'd Expect:**
- A brief 3-step tutorial overlay:
  1. "Welcome to The Triangle Vault! Your goal: find all 3 symmetries"
  2. "Symmetries are special swaps that preserve the pattern. Try swapping two crystals!" [arrow points to crystals]
  3. "When you find a symmetry, it gets added to your collection. Find them all to open the vault!"

**Code Evidence:**
```gdscript
# From level_scene.gd, line 101-142
# Title and subtitle are shown, but they're vague
title_label.text = title  # "The Triangle Vault"
subtitle_label.text = subtitle  # "Three crystals, three secrets"

# Hint system waits 30 seconds (line 502)
_hint_timer.wait_time = 30.0
```

---

## Question 2: Is the Aha Moment Achievable?

### 😐 **BARELY - For Level 1, Maybe Not for Levels 2-3**

### Level 1: The Triangle Vault (3 red crystals, all connections identical)

**The Intended Aha:** "Oh! I can rotate the triangle and the pattern stays the same!"

**What Actually Happens:**

1. **First Attempt:** I drag crystal A onto B. They swap positions. Screen flashes gold, particles burst, "Symmetries: 1/3" appears.
   - **My Thought:** "Okay... I did something right? But what exactly? They just swapped."

2. **Second Attempt:** I try swapping A and C. Another flash! "Symmetries: 2/3"
   - **My Thought:** "Wait, how is this different from the first swap? They're all red and all connected the same way!"

3. **Confusion:** Do I need to swap all three at once? Is there a special combination?
   - I try swapping B and C... flash! "Symmetries: 3/3" - Level complete!
   - **My Thought:** "I won, but... I have no idea what I actually learned. I just swapped different pairs?"

**The Problem:**
- All three crystals look IDENTICAL (same color, same connections)
- The difference between permutations [1,2,0], [2,0,1], and the identity [0,1,2] is **invisible** to me
- The game doesn't show me *which* permutation I found - just "Symmetries: X/3"
- The keyring display shows cycle notation like "(0 1 2)" which means nothing to a non-mathematician

**Code Evidence:**
```gdscript
# From level_scene.gd, line 480-486
# The keyring shows cycle notation, which is meaningless to players
var display_name := perm.to_cycle_notation()  # Shows "(0 1 2)" etc.
for sym_id in target_perms:
    if target_perms[sym_id].equals(perm):
        display_name = target_perm_names.get(sym_id, display_name)
        break
```

**The display_name should be used, but it's not clear if it actually shows "Rotation 120°"**

---

### Level 2: The Marked Thread (3 blue crystals, ONE thick edge)

**The Intended Aha:** "Oh! The thick edge has to stay between the same crystals - that limits which swaps work!"

**What Actually Happens:**

1. I see the thick edge and think "okay, this is different"
2. I try swapping the two crystals connected by the thick edge
3. **Screen flashes RED** - crystals dim, camera shakes
4. **My Thought:** "Huh? I thought the thick edge was special? Why did that fail?"

5. I try swapping the other crystals... eventually I stumble onto the valid symmetries
6. **My Thought:** "I still don't understand the rule. Sometimes swaps work, sometimes they don't, and I can't predict it"

**The Problem:**
- The hint says "Notice the thick thread between two crystals" but doesn't explain what it MEANS
- Players don't intuitively understand "edge types must be preserved"
- When I fail, the feedback doesn't explain WHY (just red flash and dim)
- No visual comparison showing "before" vs "after" edge structure

**Missing Feature:**
A visual overlay when validation fails that shows:
- Original graph structure (ghosted)
- Current graph structure (highlighted)
- The conflict: "This edge is thick, but after swapping it's thin here! ❌"

---

### Level 3: Colors Matter (1 red, 2 green crystals)

**The Intended Aha:** "Oh! Red and green are different - I can only swap crystals of the same color!"

**What Actually Happens:**

1. I see one red crystal at the top, two green at the bottom
2. The hint says "The red crystal is different from the green ones..."
3. I try swapping the two green crystals - **FLASH!** It works! "Symmetries: 1/2"
4. I try swapping red with green - **RED FLASH** - fails
5. I try the other green-red combination - fails again
6. **My Thought:** "So... I can only swap same colors? But there's only one symmetry left... what is it?"
7. Eventually I realize: doing nothing (identity) is also a symmetry
8. **Wait, how do I do nothing?** I just sit there and... nothing happens
9. **My Actual Thought:** "Is the game broken? How do I submit 'do nothing' as a move?"

**CRITICAL BUG/DESIGN FLAW:**
The identity transformation [0,1,2] is listed as a required symmetry, but **there's no way to explicitly discover it through interaction**. The game only validates swaps when you drop a crystal. The identity requires NOT swapping.

**Code Evidence:**
```gdscript
# From level_scene.gd, line 329-342
func _on_crystal_dropped(from_id: int, to_id: int) -> void:
    if from_id == to_id:  # If you drop a crystal on itself...
        return  # Nothing happens! No validation!
```

**This is a critical onboarding failure.** Level 3 cannot be completed by many players because the identity transformation isn't discoverable.

---

## Question 3: Is the Visual Feedback Satisfying?

### ✅ **YES - This is the Strongest Part**

**What Works:**

1. **Valid Symmetry Feedback** (from `feedback_fx.gd`, lines 72-99):
   - ✓ Crystals flash and scale up (1.3x)
   - ✓ Gold screen flash overlay
   - ✓ Particle bursts with colored trails
   - ✓ Subtle camera shake (2.0 intensity, 0.2 duration)
   - ✓ All edges also flash
   - **This feels GREAT** - very satisfying

2. **Invalid Attempt Feedback** (lines 102-123):
   - ✓ Crystals dim and desaturate
   - ✓ Red screen flash
   - ✓ Stronger camera shake (4.0 intensity, 0.3 duration)
   - ✓ Automatic reset after 0.5s
   - **This feels punishing without being frustrating** - good balance

3. **Completion Feedback** (lines 126-150):
   - ✓ Big green screen flash
   - ✓ 16 particles per crystal (double normal)
   - ✓ Satisfying camera shake
   - ✓ All crystals glow and flash
   - **This is properly celebratory**

4. **Hover/Drag States** (from `crystal_node.gd`, lines 111-116):
   - ✓ Crystals scale up to 1.12x on hover
   - ✓ Dragged crystals scale to 1.18x
   - ✓ Smooth lerp animation (delta * 10.0)
   - ✓ Glow pulse animation
   - **Feels responsive and polished**

**What Could Be Better:**

1. **Sound is Missing**
   - No audio cues mentioned in any code
   - Valid/invalid feedback needs distinct sound effects
   - Crystal clicks, whoosh sounds on swap, chimes on success

2. **No "Progress Sparkle"**
   - When I find symmetry 1/3, the counter updates but there's no visual indication that I'm making progress
   - Suggest: Light up stars or gem slots to show "2 more to find!"

3. **Edge Feedback is Subtle**
   - Edges flash, but they're thin lines - easy to miss
   - Consider: Edges could pulse or thicken when participating in a valid symmetry

4. **Repetition Feedback is Weak**
   - If I try a symmetry I already found, crystals just "glow" (line 400)
   - This is too similar to hover glow - needs a distinct "already found" indicator
   - Suggest: A soft ding sound + brief text "Already discovered!"

**Code Evidence of Polish:**
```gdscript
# From crystal_node.gd, lines 161-186
# Multi-layer glow rendering for soft visual effect
for i in range(4):
    var r = glow_radius * (1.0 - float(i) * 0.2)
    var a = glow_col.a * (1.0 - float(i) * 0.2)
    draw_circle(Vector2.ZERO, r, col)

# Hexagonal gem shape instead of circle - nice touch!
var num_sides := 6
# ... polygon drawing
```

**Overall:** Visual feedback is 7/10. It's well-implemented but needs sound and a few UI clarity improvements.

---

## Question 4: Would I Want to Continue to Level 4?

### ❌ **NO - Here's Why**

After playing levels 1-3 (as simulated), here's my internal monologue:

**After Level 1:**
> "That was... okay I guess? I swapped some crystals and won. Not sure what I learned. The visuals were pretty though. Maybe the next level will make more sense."

**After Level 2:**
> "Okay, this one had a thick line that meant something, but I'm still just trial-and-error-ing. I don't feel like I'm learning a skill or pattern. It's more like guessing passwords."

**After Level 3:**
> "Wait, I'm stuck. I found one symmetry (swapping the greens) but where's the second? Do I need to find a combo? A sequence? I'll try random things...
>
> *5 minutes later, looks up walkthrough*
>
> Oh. The 'do nothing' move counts. That's... that's not a puzzle, that's a trick question. And I needed 2 symmetries but the level file says group_order: 2 - is the identity automatic? This is confusing."

**The Core Problem: No Skill Progression**

- **Level 1** teaches me: "Swapping exists"
- **Level 2** teaches me: "Sometimes swaps fail"
- **Level 3** teaches me: "Colors matter"

But I still don't understand:
- What makes a swap "preserve structure"?
- How to predict which swaps will work before trying
- What symmetry means in this game
- How to apply what I learned in level 1 to level 2

**This feels like memorization, not understanding.**

**What Would Make Me Continue:**

1. **A Clear Learning Arc:**
   - Level 1: "Symmetries are swaps that keep patterns the same. Here's the identity swap (do nothing), here's a rotation. You found both! ⭐"
   - Level 2: "Now there's a special edge. Can you find swaps that keep the special edge special?"
   - Level 3: "Colors must stay with their color. Ready to apply what you learned?"

2. **Visible Pattern Recognition:**
   - Show me ALL valid symmetries after I complete a level
   - Animate them: "Watch - this is Rotation 120°" *crystals spin*
   - Let me replay found symmetries by clicking them in the key ring

3. **A Sense of Mastery:**
   - Add a "prediction mode": I can preview where crystals will go before committing
   - Add a "hint" button that highlights ONE possible valid swap
   - Track my efficiency: "You found all 3 in only 5 attempts! ⭐⭐⭐"

4. **Better Connective Tissue:**
   - After level 3, show a meta-tutorial: "You've learned about rotations, reflections, and color constraints. Level 4 combines all three!"

---

## Question 5: What Confused Me? (Specific Pain Points)

### 1. **The Counter "Symmetries: 0/3" is Opaque**

**Problem:** I don't know what a symmetry is at the start.

**Fix:** First-time players should see:
```
🔓 Vault Locks: 0 / 3
Collect all 3 keys to open the vault!
```

Later levels can switch to "Symmetries" once the concept is established.

---

### 2. **The Identity Transformation is Invisible**

**Problem:** In Level 1, all three automorphisms are listed:
- Identity [0,1,2]
- Rotation 120° [1,2,0]
- Rotation 240° [2,0,1]

But I can only discover the rotations by swapping. How do I discover identity?

**Current Code:**
```gdscript
func _on_crystal_dropped(from_id: int, to_id: int) -> void:
    if from_id == to_id:
        return  # Does nothing!
```

**Fix Options:**

**Option A:** Auto-grant identity at level start
- Advantage: Always works
- Disadvantage: Doesn't teach the concept

**Option B:** Add a "Test Current Pattern" button
- Click it to validate the current arrangement
- This way, starting position (identity) can be explicitly tested

**Option C:** Drop identity from level 1 requirements
- Only require the 2 rotations
- Introduce identity explicitly in a later tutorial level

**Recommended: Option B** - gives players agency and teaches explicit validation.

---

### 3. **Cycle Notation is Gibberish**

**Problem:** The key ring shows found symmetries as cycle notation:
```
Found:
  (0 1 2)
  (0 2 1)
```

**To a non-mathematician:** This is random numbers.

**Fix:** Use the `display_name` from the level JSON:
```
Found:
  ⟲ Rotation 120°
  ⟲ Rotation 240°
```

**Code Change Needed:**
```gdscript
# In level_scene.gd, line 480-486
# Currently defaults to cycle notation, should ALWAYS use display_name
var display_name := target_perm_names.get(sym_id, "Unnamed Symmetry")
# Don't fall back to cycle notation for players!
```

---

### 4. **No Explanation of Why a Swap Failed**

**Problem:** When I try an invalid swap:
- Screen flashes red
- Crystals dim
- Everything resets
- No explanation

**Fix:** Add a brief text popup at the swap location:
```
"Edge types don't match! ✗"
"Colors must stay the same! ✗"
"This breaks the pattern! ✗"
```

**Implementation:** In `level_scene.gd`, function `_validate_permutation`, before calling `play_invalid_feedback`, compare the graph structures and determine WHY it failed:
- Color mismatch?
- Edge type mismatch?
- Edge count mismatch?

Display the specific reason.

---

### 5. **Level 2 vs Level 1 Teaches Nothing New**

**Problem:** Level 1 has 3 identical red crystals, all edges identical → 3 symmetries
Level 2 has 3 identical blue crystals, one edge is thick → 3 symmetries

**To me:** These feel like the same puzzle with a cosmetic difference.

**Fix:** Level 2 should have FEWER symmetries to emphasize the constraint:
- 3 identical crystals with identical edges: 6 symmetries (Z3 with rotations + reflections)
- 3 identical crystals with one marked edge: 3 symmetries (only rotations)

**The current Level 2 only has rotations,** which is correct, but **it's not explained why reflections are now invalid**.

The hint should say:
> "The marked edge limits your options. Some swaps from the previous vault won't work here!"

---

### 6. **No Visual Difference Between Hover and "Already Found"**

**Problem:**
- Hover glow: `crystal.play_glow()` (line 322)
- Already-found-symmetry glow: `crystal.play_glow()` (line 400)
- **These are the same!**

**Fix:**
- Already-found should have a distinct animation: brief shimmer + soft "ding" sound + floating text "✓ Already discovered"

---

### 7. **The Subtitle is Flavor, Not Function**

**Problem:**
- Level 1: "Three crystals, three secrets" ✗ Not helpful
- Level 2: "Not all connections are equal" ✓ Better!
- Level 3: "Some crystals are different" ✓ Good!

**Fix:** Rewrite Level 1 subtitle to match the clarity of 2 & 3:
> "Find all the ways to rearrange without changing the pattern"

---

## Specific Suggestions for Improvement

### High Priority (Fix Before Launch):

1. **✅ Add explicit "do nothing" discovery mechanism**
   - "Test Current Pattern" button, or
   - Auto-grant identity, or
   - Tutorial that explicitly teaches it

2. **✅ Replace cycle notation with display names in key ring**
   - Show "Rotation 120°" not "(0 1 2)"

3. **✅ Add immediate tutorial/hint (5s, not 30s)**
   - Explain goal, interaction, win condition

4. **✅ Show WHY a swap failed**
   - "Edge types don't match!" popup

5. **✅ Rewrite Level 1 subtitle**
   - Make it actionable, not poetic

### Medium Priority (Polish):

6. **Sound effects**
   - Click, swoosh, chime, error buzz

7. **Visual progress indicators**
   - Unlock slots that fill as you find symmetries

8. **Post-level summary screen**
   - "You found all 3 symmetries! Here they are:" + animations

9. **Prediction mode / preview**
   - Show ghost crystals where they'll land

10. **"Undo" button**
    - Let me revert the last swap instead of auto-reset

### Low Priority (Nice to Have):

11. **Hint system tiers**
    - Tier 1: "Try swapping crystals"
    - Tier 2: "Look for rotations"
    - Tier 3: "Try rotating all three clockwise"

12. **Accessibility: Color-blind mode**
    - Add symbols/patterns to crystals, not just colors

13. **Efficiency scoring**
    - ⭐⭐⭐ "Perfect! Found all in minimum attempts!"

---

## Final Verdict

### Would I Recommend This Game to a Friend (After Levels 1-3)?

**Not yet.**

The game has a beautiful visual style, satisfying feedback animations, and an ambitious goal (teaching group theory through play). But the core onboarding loop is broken:

- I can't figure out what to do
- The aha moments are obscured or missing
- I don't feel like I'm learning a transferable skill
- I'd quit around Level 3 out of frustration

### What Needs to Happen:

**Before this is fun for non-mathematicians:**
1. ✅ Explicit tutorial with clear goals
2. ✅ Identity transformation discovery fix
3. ✅ Readable symmetry names (not cycle notation)
4. ✅ Failure explanations ("why did that fail?")
5. ✅ Better progressive difficulty (clearer learning arc)

**After these fixes**, this could be a **8/10 puzzle game** that successfully teaches abstract concepts through play.

**Current state: 5/10** - Beautiful but confusing.

---

## Appendix: Code Quality Notes

The codebase itself is well-structured:
- Clean separation of concerns (core engine vs visuals)
- Good use of signals for decoupling
- Permutation and KeyRing classes are solid
- Visual feedback system is polished

**The issue isn't code quality - it's game design / UX.**

---

**End of Review**

**Reviewer:** Claude (Game Designer Persona - Skeptical UX Evaluator)
**Completion Time:** ~45 minutes of deep analysis
**Recommendation:** Fix high-priority items before wider testing.
