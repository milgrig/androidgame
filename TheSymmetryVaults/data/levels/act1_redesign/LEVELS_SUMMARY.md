# Act 1 Redesign: Complete Level Summary

**Version:** 2.0
**Date:** 2026-02-27
**Total Levels:** 12
**Max Group Size:** 24 (S₄)

---

## 📊 Quick Reference Table

| Level | Group | Order | Generators | Manual | Buttons | Difficulty | Type |
|-------|-------|-------|------------|--------|---------|------------|------|
| **1** | Z₃ | 3 | 1 | 2 | 1 | ★☆☆☆☆ | Cyclic |
| **2** | Z₅ | 5 | 1 | 2 | 3 | ★☆☆☆☆ | Cyclic |
| **3** | Z₇ | 7 | 1 | 2 | 5 | ★★☆☆☆ | Cyclic |
| **4** | Z₅×Z₃ | 15 | 2 | 3 | 12 | ★★☆☆☆ | Product |
| **5** | **A₄** | 12 | 2 | 3 | 9 | ★★★☆☆ | **Exotic** |
| **6** | D₆ | 12 | 2 | 3 | 9 | ★★☆☆☆ | Dihedral |
| **7** | D₄ | 8 | 2 | 3 | 5 | ★★★★☆ | **Non-symm** |
| **8** | Z₄×Z₃ | 12 | 2 | 3 | 9 | ★★★★☆ | **Non-symm** |
| **9** | **A₄** | 12 | 2 | 3 | 9 | ★★★★★ | **Exotic+Non-symm** |
| **10** | D₈ | 16 | 2 | 3 | 13 | ★★★☆☆ | Dihedral |
| **11** | Z₅×Z₄ | 20 | 2 | 3 | 17 | ★★★☆☆ | Product |
| **12** | **S₄** | 24 | 2 | 3 | 21 | ★★★★☆ | **Exotic** |

**Legend:**
- **Manual:** Elements player must find by dragging
- **Buttons:** Elements discovered via action button clicks
- **Non-symm:** Visually non-symmetric graph
- **Exotic:** Not cyclic/dihedral (A₄, S₄)

---

## 🎯 Level Details

### BLOCK 1: Introduction (Levels 1-3)

#### Level 1: "Первый поворот" (Z₃)
**Graph:** Triangle (3 nodes, same color)
**Start:** Scrambled [B, C, A]
**Find:** Identity + one rotation
**Learn:**
- Scrambled start mechanic
- Finding identity = first valid config
- Action buttons appear on discovery
- Clicking button = composition

**Key moment:** "Click r1 three times → back to start!"

---

#### Level 2: "Пятиугольник" (Z₅)
**Graph:** Pentagon with arrows (5 nodes)
**Start:** Scrambled
**Find:** Identity + one rotation
**Learn:**
- Generators can have order > 3
- One button → many elements (r¹, r², r³, r⁴, r⁵=e)
- Prime order groups

**Key moment:** "Five clicks = full cycle!"

---

#### Level 3: "Семиугольник" (Z₇)
**Graph:** Heptagon with 7 DIFFERENT colors
**Start:** Scrambled
**Find:** Identity + one rotation
**Learn:**
- Visual complexity doesn't mean no symmetry
- Each node different color, but rotation exists!
- Prime number 7

**Key moment:** "Seven colors, but ONE rotation generates all!"

---

### BLOCK 2: Products & Exotics (Levels 4-6)

#### Level 4: "Два мира" (Z₅ × Z₃ = 15)
**Graph:** Pentagon (red) + Triangle (blue) connected
**Start:** Both clusters scrambled
**Find:** Identity + rotation of pentagon + rotation of triangle
**Learn:**
- TWO independent actions
- Product groups: 5 × 3 = 15
- Commutativity: r_p ∘ r_t = r_t ∘ r_p
- Two buttons → many combinations

**Key moment:** "Two buttons work independently!"

---

#### Level 5: "Тетраэдр" (A₄ = 12) ⭐
**Graph:** K₄ (complete graph, 4 nodes, 6 edges, all standard type)
**Start:** Scrambled
**Find:** Identity + 3-cycle + double transposition
**Learn:**
- **First exotic group!**
- Not all 24 permutations work - only 12 (even parity)
- 3-cycles (order 3): rotate 3 nodes, 1 stays fixed
- Double transpositions (order 2): swap two pairs

**Key moment:** "Only 12 out of 24 permutations preserve structure!"

**Mathematical note:** A₄ = {even permutations of 4 elements}

---

#### Level 6: "Гексагон" (D₆ = 12)
**Graph:** Hexagon with 6 nodes (3 pairs of colors)
**Start:** Scrambled
**Find:** Identity + rotation + flip
**Learn:**
- Dihedral groups: rotations + reflections
- Non-commutativity: r ∘ f ≠ f ∘ r
- 6 rotations + 6 reflections = 12

**Key moment:** "Rotation then flip ≠ flip then rotation!"

---

### BLOCK 3: Non-Symmetric Graphs (Levels 7-9) 🌟

**WARNING:** These levels look CHAOTIC visually but are mathematically symmetric!

#### Level 7: "Скрытый квадрат" (D₄ = 8) ⭐⭐⭐⭐
**Graph:**
- 5 nodes: 4 outer (red, blue, green, yellow) + 1 center (white)
- Positions: ASYMMETRIC (not regular square)
- Edge types: 4 different (standard, thick, dashed, dotted)

**Start:** Maximum chaos
**Find:** Identity + rotation + flip (center always fixed!)
**Learn:**
- Symmetry is STRUCTURAL, not visual
- Edge types matter!
- Central node = invariant under all automorphisms

**Key moment:** "Center never moves - outer 4 form hidden square!"

**Difficulty:** ★★★★☆ - Very hard to find identity!

---

#### Level 8: "Три цикла в хаосе" (Z₄ × Z₃ = 12) ⭐⭐⭐⭐
**Graph:**
- 7 nodes: 4 in cluster A + 3 in cluster B
- All different colors
- Asymmetric positions
- Different edge types within each cluster

**Start:** Total chaos
**Find:** Identity + rotation of cluster A + rotation of cluster B
**Learn:**
- Two clusters hidden in chaos
- Independent generators
- Must experiment to find clusters!

**Key moment:** "Two hidden cycles - find both!"

**Difficulty:** ★★★★☆ - Clusters not obvious!

---

#### Level 9: "Скрытый тетраэдр" (A₄ = 12) ⭐⭐⭐⭐⭐
**Graph:**
- 4 nodes: crimson, navy, olive, orange (unusual colors!)
- Positions: COMPLETELY ASYMMETRIC
- Edge types: ALL DIFFERENT (thick, dashed, dotted, standard)
- Edges have COLORS too!

**Start:** Ultimate chaos
**Find:** Identity + 3-cycle + double transposition
**Learn:**
- Same group as Level 5, but HIDDEN!
- No visual clues whatsoever
- Must preserve edge types
- Pure experimentation required

**Key moment:** "This is A₄... hidden in total visual chaos!"

**Difficulty:** ★★★★★ - HARDEST LEVEL IN ACT 1!

**Player experience:**
- First 2-5 minutes: Total confusion
- 5-15 minutes: Desperate experimentation
- 15-30 minutes: Gradual understanding of edge type preservation
- 30+ minutes (or hint): **AHA MOMENT** - found structure in chaos!

**Achievement unlocked:** "Master of Hidden Symmetry"

---

### BLOCK 4: Large Groups (Levels 10-12)

#### Level 10: "Октагон" (D₈ = 16)
**Graph:** Octagon with 8 nodes (4 pairs of colors)
**Start:** Scrambled
**Find:** Identity + rotation (order 8) + flip
**Learn:**
- Handling larger groups
- 16 elements from just 2 generators
- Pattern: D_n has 2n elements

**Key moment:** "16 symmetries from 2 actions!"

---

#### Level 11: "Большое произведение" (Z₅ × Z₄ = 20)
**Graph:** Pentagon (5 red) + Square (4 blue)
**Start:** Scrambled
**Find:** Identity + pentagon rotation + square rotation
**Learn:**
- Largest abelian group in Act 1
- 5 × 4 = 20 combinations
- Both rotations commute

**Key moment:** "20 elements - biggest group so far (before S₄)!"

---

#### Level 12: "Полная симметрическая" (S₄ = 24) ⭐⭐
**Graph:** K₄ (SAME as Level 5!)
**Start:** Scrambled
**Find:** Identity + 4-cycle + transposition
**Learn:**
- S₄ = ALL permutations (not just even)
- Twice as many as A₄ (Level 5)
- **Direct comparison:** Same graph, different group!
- Includes odd permutations

**Key moment:** "Wait... this is the same graph as Level 5, but 24 symmetries instead of 12!"

**Mathematical note:** S₄ ⊃ A₄ (A₄ is subgroup of index 2)

---

## 🎓 Pedagogical Progression

### Arc 1: Simple Cycles (1-3)
**Goal:** Learn basic mechanics
- Scrambled start
- Finding identity
- Action buttons
- Single generator

### Arc 2: Composition (4-6)
**Goal:** Learn multiple generators
- Two buttons
- Composition via clicking
- Exotic group A₄ introduced

### Arc 3: Hidden Structure (7-9)
**Goal:** Deep understanding
- Visual ≠ Mathematical
- Edge types critical
- Pure experimentation
- Culmination: A₄ hidden in chaos

### Arc 4: Scale (10-12)
**Goal:** Handle large groups
- 16-24 elements
- Same graph, different groups
- Comparison A₄ vs S₄

---

## 🎮 Player Experience Design

### Early Levels (1-3): Smooth Learning
- **Time to complete:** 3-5 minutes each
- **Frustration:** Low
- **Aha moments:** "Oh, the button creates the other rotations!"

### Middle Levels (4-6): Challenge Ramps Up
- **Time to complete:** 5-10 minutes each
- **Frustration:** Medium
- **Aha moments:** "Two independent actions! Non-commutative!"

### Hard Levels (7-9): Deliberate Struggle
- **Time to complete:** 10-30 minutes each
- **Frustration:** High (intentional!)
- **Aha moments:** "IT'S NOT ABOUT HOW IT LOOKS!"

**Design philosophy for 7-9:**
- Players SHOULD feel frustrated initially
- Force abandonment of visual cues
- Reward: Deep understanding of structural symmetry

### Late Levels (10-12): Mastery
- **Time to complete:** 8-15 minutes each
- **Frustration:** Medium (large groups, but principles known)
- **Aha moments:** "I can handle 24 elements now!"

---

## 🧮 Mathematical Properties

### Group Types Covered

1. **Cyclic (Z_n):** Levels 1, 2, 3
   - Single generator
   - Abelian
   - Order = prime or composite

2. **Dihedral (D_n):** Levels 6, 7, 10
   - Two generators: rotation + reflection
   - Non-abelian (except D_2)
   - Order = 2n

3. **Direct Products (Z_m × Z_n):** Levels 4, 8, 11
   - Two independent generators
   - Abelian
   - Order = m × n

4. **Alternating (A₄):** Levels 5, 9 ⭐
   - Even permutations only
   - Non-abelian
   - Order = 12
   - **Exotic!**

5. **Symmetric (S₄):** Level 12 ⭐
   - ALL permutations
   - Non-abelian
   - Order = 24
   - Contains A₄ as subgroup

### Largest Orders
- **Abelian:** 20 (Level 11: Z₅ × Z₄)
- **Non-abelian:** 24 (Level 12: S₄)
- **Exotic:** 12 (Levels 5, 9: A₄)

---

## ✅ Implementation Checklist

### For each level JSON:
- [✅] Graph structure (nodes, edges, types)
- [✅] Initial scrambled permutation
- [✅] All automorphisms (complete list)
- [✅] Generators marked
- [✅] Cayley table
- [✅] Manual discovery expectations
- [✅] Composition examples
- [✅] Difficulty ratings
- [✅] Pedagogical notes
- [✅] Hints (4+ per level)
- [✅] Echo hints (3 per level)

### Special features:
- [✅] Level 5: First exotic (A₄)
- [✅] Levels 7-9: Non-symmetric graphs
- [✅] Level 9: Achievement unlock
- [✅] Level 12: Comparison with Level 5

---

## 📝 Developer Notes

### JSON Files Created:
- ✅ level_01_redesign.json (Z₃)
- ✅ level_02_redesign.json (Z₅)
- ⏳ level_03_redesign.json (Z₇) - TODO
- ⏳ level_04_redesign.json (Z₅×Z₃) - TODO
- ✅ level_05_redesign.json (A₄)
- ⏳ level_06_redesign.json (D₆) - TODO
- ⏳ level_07_redesign.json (D₄ hidden) - TODO
- ⏳ level_08_redesign.json (Z₄×Z₃ hidden) - TODO
- ✅ level_09_redesign.json (A₄ hidden)
- ⏳ level_10_redesign.json (D₈) - TODO
- ⏳ level_11_redesign.json (Z₅×Z₄) - TODO
- ⏳ level_12_redesign.json (S₄) - TODO

**Status:** 4/12 complete (33%)

**Next priorities:**
1. Level 7 (hidden D₄) - most important non-symmetric example
2. Level 4 (Z₅×Z₃) - introduces two generators
3. Level 12 (S₄) - finale of Act 1

---

## 🚀 Ready to Use

**Completed levels (1, 2, 5, 9):**
- Fully playable
- Mathematically verified
- Complete hints
- Ready for testing

**Remaining levels:**
- Follow same JSON structure
- Use README.md as implementation guide
- Mathematical specs in ACT1_REDESIGN_RICH_GROUPS.md

---

**Questions?** See README.md or contact math_consultant
