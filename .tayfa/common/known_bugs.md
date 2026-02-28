# Known Bugs & Lessons Learned

This file is auto-injected into every task prompt.
Agents MUST check this list before marking any task as done.
If you fixed a bug that is NOT listed here — **add it** following the format below.

---

## KB-001: Class Visibility / Parse Error on Startup (Autoload Deadlock)

**Symptom:** Game crashes on startup with `Could not find type 'ClassName' in the current scope`. GameManager fails to load as autoload → null reference everywhere.
**Root Cause:** Godot doesn't index `class_name` declarations until AFTER autoload scripts load. If an autoload script uses type hints referencing other classes, Godot can't resolve them yet → parse error → deadlock.
**Prevention:**
- NEVER use `class_name`-based type hints in autoload scripts
- Use `preload()` constants instead: `const MyClass = preload("res://src/core/my_class.gd")`
- After adding any new class, verify that `game_manager.gd` and other autoloads still parse
**Recurred:** 2+ times (S002, S003/S004)

## KB-002: Null Reference in UI Animation (_process crash)

**Symptom:** Black screen or menu not appearing. Error: `Invalid assignment of property 'modulate' on base object of type 'Nil'`
**Root Cause:** Animation code in `_process()` runs every frame and accesses UI node properties (modulate, position, visible) without null checks. If node creation failed or hasn't happened yet, variable is nil → crash on first frame.
**Prevention:**
- ALWAYS add `if node:` guard before accessing any UI node property in `_process()` or tween callbacks
- Pattern: `if _start_button: _start_button.modulate = Color(...)`
- This applies to ALL animated UI elements, not just buttons
**Recurred:** 3+ times (T037, T043, multiple levels)

## KB-003: Unicode Escape Sequences in GDScript 4.x

**Symptom:** Parse error when loading scene. `Invalid hexadecimal digit in unicode escape sequence`
**Root Cause:** GDScript 4.x does NOT support `\u{1F512}` escape sequences (that's Rust syntax). Only direct UTF-8 emoji characters work in string literals.
**Prevention:**
- Use direct emoji: `var lock = "🔒"` NOT `var lock = "\u{1F512}"`
- This applies to ALL Unicode characters above ASCII range
**Recurred:** 1 time (S003/S004), but easy to repeat

## KB-004: UI Component Declared Done But Not Created

**Symptom:** Component (e.g., TargetPreview) completely missing from scene tree despite task being marked "done". Feature invisible in ALL levels.
**Root Cause:** Developer wrote the component class but never added initialization call to the parent scene, or conditional logic prevented `add_child()` from executing.
**Prevention:**
- After creating any new UI component, verify it appears in the scene tree at runtime
- Check that `add_child()` is actually called (not just defined)
- Unit tests for component logic do NOT verify visual presence — must run the game
**Recurred:** 1+ times (T043/T052/T056)

## KB-005: Unit Tests Pass But Game Shows Black Screen

**Symptom:** All 500+ unit tests pass. User launches game — black screen.
**Root Cause:** Unit tests validate logic (math, data structures, algorithms) but do NOT test:
- Scene loading and resource paths
- Node tree construction and `_ready()` flow
- Visual rendering and camera setup
- Autoload initialization order
**Prevention:**
- Unit test passing is NECESSARY but NOT SUFFICIENT
- After any change to scenes, resources, or autoloads — MUST run the game via Agent Bridge
- If Agent Bridge is unavailable, at minimum verify all `preload()` / `load()` paths exist as files
**Recurred:** Multiple sprints — this is the #1 recurring pattern

---

<!--
FORMAT FOR NEW ENTRIES:

## KB-XXX: Short Title

**Symptom:** What the user sees
**Root Cause:** Why it happens
**Prevention:** Steps to avoid it
**Recurred:** How many times / which sprints
-->
