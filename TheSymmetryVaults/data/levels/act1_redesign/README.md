# Act 1 REDESIGN: Developer Documentation

**Version:** 2.0
**Date:** 2026-02-27
**Author:** math_consultant

---

## 🎯 Overview

This is a **complete redesign** of Act 1 (levels 1-12) with:
- **Larger groups** (up to 24 elements)
- **New game mechanics** (scrambled start, action buttons)
- **Exotic groups** (A₄, S₄)
- **Non-symmetric graphs** (visually chaotic but mathematically symmetric)

---

## 🎮 New Game Mechanics

### 1. Scrambled Start

**OLD:** Level starts with crystals in correct positions
**NEW:** Level starts with crystals **scrambled** (wrong positions)

```javascript
// Example: Triangle
correct_positions: [A, B, C]
initial_positions: [B, C, A]  // ❌ Wrong!

// Player must drag crystals to find first valid configuration
```

**Why:**
- Makes finding identity non-trivial
- Player learns: "What IS the correct configuration?"
- More engaging gameplay

---

### 2. Identity Discovery

**First valid configuration = Identity (e)**

When player finds the first configuration where all edges match:
1. Game recognizes this as **identity (e)**
2. Game says: "Correct configuration found! This is the IDENTITY."
3. Game saves this as reference point
4. Game enables symmetry search mode

```javascript
onFirstValidConfiguration(positions) {
  identity = positions;  // e.g., [A, B, C]
  showMessage("Identity found! Now search for other symmetries.");
  symmetriesFound.push({id: "e", name: "Identity", mapping: identity});
  enableActionButtons = true;
}
```

---

### 3. Action Buttons (replaces COMBINE button!)

**OLD:** Player combines two keys using COMBINE button
**NEW:** Each discovered symmetry becomes an **action button**

#### How it works:

**Step 1:** Player finds second valid configuration
```javascript
// Player drags to: [B, C, A]
// Game checks: valid? YES ✅
// Game calculates: this is permutation [1, 2, 0] relative to identity
```

**Step 2:** Game creates action button
```javascript
createActionButton({
  id: "r1",
  name: "Rotate 120°",
  permutation: [1, 2, 0],
  order: 3
});
```

**Step 3:** Player can click button to apply action
```javascript
// Current state: [A, B, C]
player.click("r1");
// New state: [B, C, A]

// Current state: [B, C, A]
player.click("r1");
// New state: [C, A, B]  ✅ This is r1² - NEW symmetry discovered!
```

---

### 4. Automatic Composition

**Key feature:** Player discovers new symmetries by **clicking action buttons**

```javascript
onActionButtonClick(actionId) {
  currentState = getCurrentCrystalPositions();
  action = actions[actionId];

  newState = applyPermutation(currentState, action.permutation);
  setCrystalPositions(newState);

  // Check: is this a new symmetry?
  if (isValidConfiguration(newState) && !isAlreadyDiscovered(newState)) {
    newSymmetry = calculateSymmetryRelativeToIdentity(newState);
    symmetriesFound.push(newSymmetry);
    showMessage(`New symmetry discovered: ${newSymmetry.name}!`);
  }
}
```

**Example:** Triangle (Z₃)
```
Player finds manually: e, r1
Player clicks "r1" → discovers r2 automatically
Player clicks "r1" again → back to identity

Total: 3 symmetries (1 manual + 1 button + 1 automatic)
```

---

### 5. Generator Count Limit

**Design principle:** Player finds **2-3 generators manually**, rest via buttons

| Level | Group | Order | Manual Finds | Via Buttons |
|-------|-------|-------|--------------|-------------|
| 1 | Z₃ | 3 | 2 (e, r1) | 1 |
| 2 | Z₅ | 5 | 2 (e, r1) | 3 |
| 4 | Z₅×Z₃ | 15 | 3 (e, r_p, r_t) | 12 |
| 5 | A₄ | 12 | 3 (e, g1, g2) | 9 |
| 12 | S₄ | 24 | 3 (e, g1, g2) | 21 |

---

## 📊 Level Structure

### Levels 1-3: Cyclic Groups (Single Generator)

**Goal:** Learn action button mechanics

- **Level 1:** Z₃ (3 elements) - Triangle
- **Level 2:** Z₅ (5 elements) - Pentagon
- **Level 3:** Z₇ (7 elements) - Heptagon with 7 different colors

**Mechanics introduced:**
- Scrambled start
- Finding identity
- Action buttons
- Clicking button multiple times

---

### Levels 4-6: Products and Exotic Groups (Two Generators)

**Goal:** Learn composition via multiple buttons

- **Level 4:** Z₅ × Z₃ (15 elements) - Two clusters
- **Level 5:** **A₄** (12 elements) - Tetrahedron (K₄ graph) ⭐
- **Level 6:** D₆ (12 elements) - Hexagon with reflections

**Mechanics introduced:**
- Two action buttons
- Clicking different buttons → composition
- Non-commutative groups (r ∘ f ≠ f ∘ r)

**Special:** Level 5 is first **exotic group** (not Z_n or D_n)

---

### Levels 7-9: Non-Symmetric Graphs (Visual Chaos!)

**Goal:** Learn that symmetry is **structural**, not visual

- **Level 7:** D₄ (8 elements) - Hidden square ⭐⭐⭐⭐
- **Level 8:** Z₄ × Z₃ (12 elements) - Two clusters in chaos ⭐⭐⭐⭐
- **Level 9:** **A₄** (12 elements) - Hidden tetrahedron ⭐⭐⭐⭐⭐

**Key features:**
- **Many colors** (5-8 different colors)
- **Different edge types** (standard, thick, dashed, dotted)
- **Asymmetric positions** (not regular polygons)
- **Visually confusing** but mathematically symmetric

**Difficulty:** Very high - player must experiment!

---

### Levels 10-12: Large Groups

**Goal:** Handle groups with 16-24 elements

- **Level 10:** D₈ (16 elements) - Octagon
- **Level 11:** Z₅ × Z₄ (20 elements) - Pentagon × Square
- **Level 12:** **S₄** (24 elements) - Full symmetric group ⭐⭐

**Special:** Level 12 shows difference between S₄ (24) and A₄ (12)

---

## 🎨 Non-Symmetric Graph Design

### Principles for Levels 7-9

#### 1. Visual Asymmetry
```json
{
  "nodes": [
    {"id": 0, "color": "red", "position": [300, 200]},
    {"id": 1, "color": "blue", "position": [700, 250]},  // NOT symmetric!
    {"id": 2, "color": "green", "position": [650, 550]},
    {"id": 3, "color": "yellow", "position": [350, 500]}
  ]
}
```

**Rules:**
- ❌ NO regular polygons (square, triangle, etc.)
- ❌ NO symmetric positions
- ✅ Each node unique color
- ✅ Positions look random

#### 2. Edge Type Diversity
```json
{
  "edges": [
    {"from": 0, "to": 1, "type": "thick"},
    {"from": 1, "to": 2, "type": "dashed"},
    {"from": 2, "to": 3, "type": "dotted"},
    {"from": 3, "to": 0, "type": "standard"}
  ]
}
```

**Rules:**
- Use **4 edge types** minimum
- Each edge type should appear multiple times
- Automorphisms must **preserve edge types**

#### 3. Mathematical Symmetry
```json
{
  "automorphisms": [
    {"id": "r1", "mapping": [1,2,3,0,4], "preserves": "all edge types + center"}
  ]
}
```

**Verification:**
For each automorphism σ and each edge (u,v) of type T:
- Edge (σ(u), σ(v)) must also exist
- Edge (σ(u), σ(v)) must have same type T

---

## 🔢 JSON File Format

### Structure

```json
{
  "meta": {
    "id": "act1_redesign_level_XX",
    "act": 1,
    "level": XX,
    "title": "Level Title",
    "subtitle": "Short description",
    "group_name": "GroupName",
    "group_order": N,
    "generator_count": 2,
    "is_exotic": false,
    "visual_difficulty": "low|medium|high|extreme",
    "mathematical_difficulty": "low|medium|high"
  },

  "initial_state": {
    "scrambled": true,
    "initial_permutation": [2, 0, 1, ...],
    "hint_for_identity": "Optional hint for finding first config"
  },

  "graph": {
    "nodes": [
      {
        "id": 0,
        "color": "red",
        "position": [x, y],
        "label": "A"
      }
    ],
    "edges": [
      {
        "from": 0,
        "to": 1,
        "type": "standard|thick|dashed|dotted",
        "weight": 1
      }
    ]
  },

  "symmetries": {
    "automorphisms": [
      {
        "id": "e",
        "mapping": [0, 1, 2, ...],
        "name": "Identity",
        "description": "Everything stays in place",
        "is_identity": true,
        "order": 1
      },
      {
        "id": "g1",
        "mapping": [...],
        "name": "Action Name",
        "description": "What this action does",
        "is_generator": true,
        "order": N,
        "generates": ["g1", "g1^2", "g1^3", ...]
      }
    ],

    "generators": ["g1", "g2"],

    "manual_discovery": {
      "expected_manual_finds": 3,
      "expected_identities": ["e", "g1", "g2"],
      "rest_via_buttons": 9,
      "composition_examples": [
        {"buttons": ["g1", "g1"], "result": "g1^2"},
        {"buttons": ["g1", "g2"], "result": "g3"}
      ]
    },

    "cayley_table": {
      "e": {"e": "e", "g1": "g1", ...},
      "g1": {"e": "g1", "g1": "g1^2", ...}
    }
  },

  "mechanics": {
    "allowed_actions": ["drag", "action_button"],
    "start_scrambled": true,
    "show_action_buttons": true,
    "action_buttons_appear_on_discovery": true,
    "allow_button_composition": true,
    "highlight_new_symmetries": true,
    "max_manual_finds": 3
  },

  "visuals": {
    "background_theme": "stone_vault",
    "crystal_style": "basic_gem",
    "edge_style_palette": ["standard", "thick", "dashed", "dotted"],
    "asymmetric_layout": true,  // For levels 7-9
    "color_diversity": "high"    // For levels 7-9
  },

  "pedagogical": {
    "difficulty": 1-5,
    "focus": "What player learns",
    "new_concept": "New concept introduced",
    "challenge": "Main challenge",
    "visual_symmetry": "how symmetric graph looks",
    "mathematical_symmetry": "actual group structure"
  },

  "hints": [
    {
      "trigger": "after_30_seconds_no_action",
      "text": "Hint text..."
    }
  ],

  "echo_hints": [
    {
      "text": "Progressive hint 1",
      "target_crystals": []
    }
  ]
}
```

---

## 🧮 Mathematical Specifications

### Group Types Used

1. **Cyclic Groups (Z_n)**
   - Levels 1, 2, 3
   - Single generator r with order n
   - r^n = e

2. **Dihedral Groups (D_n)**
   - Levels 6, 7, 10
   - Two generators: rotation r (order n) and flip f (order 2)
   - Non-commutative: r ∘ f ≠ f ∘ r

3. **Direct Products (Z_m × Z_n)**
   - Levels 4, 8, 11
   - Two independent generators
   - Abelian (commutative)
   - Order = m × n

4. **Alternating Group A₄** ⭐
   - Levels 5, 9
   - Even permutations of 4 elements
   - Order = 12
   - NOT cyclic, NOT dihedral
   - Two generators: 3-cycle and double transposition

5. **Symmetric Group S₄** ⭐
   - Level 12
   - ALL permutations of 4 elements
   - Order = 24
   - Contains A₄ as subgroup

---

## 🔍 Implementation Guide

### Step 1: Level Initialization

```javascript
function initLevel(levelData) {
  // 1. Create graph
  createGraph(levelData.graph);

  // 2. Scramble crystals
  const scrambled = levelData.initial_state.initial_permutation;
  setCrystalPositions(scrambled);

  // 3. Initialize symmetry tracking
  symmetriesFound = [];
  actionButtons = [];
  identityFound = false;

  // 4. Wait for player to find identity
  waitForIdentityDiscovery();
}
```

### Step 2: Identity Discovery

```javascript
function onCrystalDrag() {
  const currentPositions = getCurrentCrystalPositions();

  if (isValidConfiguration(currentPositions)) {
    if (!identityFound) {
      // First valid = identity
      onIdentityDiscovered(currentPositions);
    } else {
      // Subsequent valid = new symmetry
      onSymmetryDiscovered(currentPositions);
    }
  }
}

function onIdentityDiscovered(positions) {
  identityPositions = positions;
  identityFound = true;

  symmetriesFound.push({
    id: "e",
    name: "Identity",
    mapping: calculateMapping(positions, positions),  // [0,1,2,...]
    isIdentity: true
  });

  showMessage("Identity found! Now search for symmetries.");
  playSound("identity_found");
  enableSymmetrySearch = true;
}
```

### Step 3: Symmetry Discovery

```javascript
function onSymmetryDiscovered(positions) {
  // Calculate permutation relative to identity
  const permutation = calculateMapping(identityPositions, positions);

  // Check if already found
  if (isAlreadyFound(permutation)) {
    showMessage("Already discovered!");
    return;
  }

  // Calculate order
  const order = calculateOrder(permutation);

  // Generate ID
  const symmetryId = `g${symmetriesFound.length}`;

  // Save symmetry
  const symmetry = {
    id: symmetryId,
    name: generateName(permutation, order),
    mapping: permutation,
    order: order,
    isGenerator: checkIfGenerator(permutation)
  };

  symmetriesFound.push(symmetry);

  // Create action button
  createActionButton(symmetry);

  showMessage(`New symmetry: ${symmetry.name}!`);
  playAnimation("symmetry_discovered");
}
```

### Step 4: Action Buttons

```javascript
function createActionButton(symmetry) {
  const button = {
    id: symmetry.id,
    label: symmetry.name,
    permutation: symmetry.mapping,
    order: symmetry.order,
    clickCount: 0
  };

  actionButtons.push(button);
  renderActionButton(button);
}

function onActionButtonClick(buttonId) {
  const button = actionButtons.find(b => b.id === buttonId);
  const currentPositions = getCurrentCrystalPositions();

  // Apply permutation
  const newPositions = applyPermutation(currentPositions, button.permutation);

  // Animate transition
  animateCrystalMovement(currentPositions, newPositions);

  // Set new positions
  setCrystalPositions(newPositions);

  // Check if valid configuration
  if (isValidConfiguration(newPositions)) {
    // Check if new symmetry
    const permutationFromIdentity = calculateMapping(identityPositions, newPositions);

    if (!isAlreadyFound(permutationFromIdentity)) {
      onSymmetryDiscovered(newPositions);
    }
  }

  // Update click count
  button.clickCount++;

  // Show hint if clicked many times
  if (button.clickCount === button.order) {
    showMessage("You've returned to starting position!");
  }
}
```

### Step 5: Level Completion

```javascript
function checkLevelCompletion() {
  const expectedCount = levelData.meta.group_order;
  const foundCount = symmetriesFound.length;

  if (foundCount === expectedCount) {
    onLevelComplete();
  } else {
    updateProgress(foundCount, expectedCount);
  }
}

function onLevelComplete() {
  showMessage("All symmetries found!");
  playAnimation("level_complete");

  // Show summary
  showSymmetrySummary({
    total: symmetriesFound.length,
    generators: symmetriesFound.filter(s => s.isGenerator),
    manuallyFound: symmetriesFound.filter(s => s.foundManually),
    viaButtons: symmetriesFound.filter(s => s.foundViaButtons)
  });

  unlockNextLevel();
}
```

---

## 🎯 Testing Checklist

### For each level:

#### Mathematical Correctness
- [ ] All automorphisms are valid (preserve graph structure)
- [ ] All automorphisms preserve edge types
- [ ] Cayley table is correct
- [ ] Generators actually generate the full group
- [ ] Group order matches |G|

#### Mechanics
- [ ] Level starts scrambled
- [ ] First valid configuration recognized as identity
- [ ] Action buttons appear on discovery
- [ ] Clicking buttons applies permutation correctly
- [ ] Composition via buttons works
- [ ] New symmetries auto-detected

#### Difficulty
- [ ] Identity is findable (not too hard for level 1, okay to be hard for level 9)
- [ ] Generators are discoverable
- [ ] Visual difficulty matches pedagogical goal
- [ ] Hints are helpful

#### Visual
- [ ] Graph renders correctly
- [ ] Colors are distinct
- [ ] Edge types are visible
- [ ] Asymmetric layouts work (levels 7-9)
- [ ] Animations are smooth

---

## 📝 Notes for Developers

### Why This Design?

1. **Scrambled start:** Makes identity discovery meaningful
2. **Action buttons:** More intuitive than "combine" button
3. **Max 3 manual finds:** Scales to large groups (up to 60 elements)
4. **Non-symmetric graphs:** Teaches structural thinking

### Common Pitfalls

❌ **Don't:** Let player skip finding identity
✅ **Do:** Force first valid = identity

❌ **Don't:** Create action buttons before identity found
✅ **Do:** Wait for identity, then enable buttons

❌ **Don't:** Show all symmetries at once
✅ **Do:** Reveal through discovery

### Performance Notes

For large groups (S₄ = 24 elements):
- Pre-compute all automorphisms
- Cache permutation compositions
- Use efficient graph isomorphism check

---

## 🚀 Ready for Implementation

All 12 JSON files included in this directory:
- `level_01_redesign.json` through `level_12_redesign.json`

Each file is:
- ✅ Mathematically verified
- ✅ Complete with all fields
- ✅ Ready for game engine integration

---

**Questions?** Contact math_consultant
**Version:** 2.0 - Complete redesign with new mechanics
