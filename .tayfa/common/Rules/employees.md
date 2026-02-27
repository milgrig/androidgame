# Employee List

## Registry

Source of truth: **`.tayfa/common/employees.json`**

- New employees: `python .tayfa/hr/create_employee.py <name>`
- View: `python .tayfa/common/employee_manager.py list`
- Remove: `python .tayfa/common/employee_manager.py remove <name>` (cannot remove boss/hr)

---

## boss

**Role**: Project manager, task coordinator.

**When to contact**: task done, serious questions, need new employee.

**Who can contact**: any employee.

---

## hr

**Role**: HR manager, employee and agent management.

**Capabilities**: create employees via `create_employee.py`, edit prompts.

**Who can contact**: only boss.

---

## analyst

**Role**: System analyst, requirements and task specification.

**Capabilities**: detail requirements, write user stories, acceptance criteria, decompose tasks.

**Task role**: Customer (details requirements for developer).

---

## developer

**Role**: Application developer.

**Capabilities**: implement features, fix bugs, refactor, write tests.

**Task role**: Developer (implements per spec).

---

## tester

**Role**: QA Engineer.

**Capabilities**: test functionality, verify acceptance criteria, document bugs.

**Task role**: Tester (verifies and accepts/returns).

---

## python_dev

**Role**: Senior Python Developer (Opus model).

**Capabilities**: architecture, core modules, complex integrations, optimization.

**Model**: Claude Opus — for complex architectural tasks.

**When NOT to use** (use developer): simple CRUD, field additions, typo fixes.

---

## junior_analyst

**Role**: Quick requirements structuring.

**Capabilities**: structure requirements into acceptance criteria (3-5 items), add test cases (2-3).

**Does NOT**: ask questions, research code, add own requirements.

**Model**: Claude Haiku — for fast template operations.

---

## architect

**Role**: Game Systems Architect (Opus model).

**Capabilities**: design technical architecture, choose technology stack, define module boundaries and data structures, plan for cross-platform.

**Task role**: Customer (defines architecture and technical specs for developers).

**Who can contact**: boss, developers.

---

## developer_game

**Role**: Core Game Developer (Opus model).

**Capabilities**: implement game engine, permutation/group theory engine, game loop, level mechanics, unit tests.

**Task role**: Developer (implements core game logic).

**Who can contact**: boss, architect, developer_ui, developer_game2, math_consultant.

---

## developer_game2

**Role**: Gameplay & Level Mechanics Developer (Opus model).

**Capabilities**: fix/validate level JSON data, implement player interactions (buttons, HUD, identity discovery), integration tests for gameplay, onboarding/tutorial game logic, gameplay bug fixes.

**Task role**: Developer (implements gameplay features and level fixes).

**Who can contact**: boss, architect, developer_game, developer_ui, math_consultant.

---

## developer_ui

**Role**: UI/UX & Visual Developer (Opus model).

**Capabilities**: render graphs and crystals, drag-and-drop, animations, particle effects, visual feedback, UI layouts.

**Task role**: Developer (implements visual layer).

**Who can contact**: boss, architect, developer_game.

---

## math_consultant

**Role**: Mathematical Consultant — Galois Theory Expert (Sonnet model).

**Capabilities**: define algebraic structures for levels, verify group operations, suggest graphs with desired automorphism groups, validate pedagogical progression.

**Task role**: Customer (specifies mathematical requirements for levels).

**Who can contact**: boss, developers.

---

## game_designer

**Role**: Game Designer — Skeptical UX Evaluator (Sonnet model).

**Capabilities**: evaluate fun factor, test difficulty curve, review onboarding, represent non-mathematician player perspective. **Skeptic by design** — questions whether the game is actually fun and accessible.

**Task role**: Customer or Tester (evaluates UX and gameplay).

**Who can contact**: boss.

---

## qa_tester

**Role**: QA Engineer (Sonnet model).

**Capabilities**: run and test the application, play through levels, test edge cases, document bugs with reproducible steps.

**Task role**: Tester (verifies by running, never by reading code).

**Who can contact**: boss, developers.

---

## critic

**Role**: Quality & Aesthetics Critic — The Harsh Judge (Sonnet model).

**Capabilities**: evaluate visual quality, judge if game is genuinely fun or just a tech demo, rate all aspects with scores, identify biggest weaknesses, counter team's optimism bias.

**Task role**: Tester (final quality gate).

**Who can contact**: boss.

---

## Task System

Each task has 3 roles: customer, developer, tester.

```bash
python .tayfa/common/task_manager.py list
python .tayfa/common/task_manager.py get T001
python .tayfa/common/task_manager.py result T001 "..."
python .tayfa/common/task_manager.py status T001 ...
```

See `.tayfa/common/Rules/teamwork.md` for details.
