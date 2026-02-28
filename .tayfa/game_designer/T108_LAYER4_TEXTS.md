# Layer 4 Instruction Texts, Hints, and Pedagogical Flow
**Game Designer Deliverable — Task T108**
**Date:** 2026-02-28
**Author:** Game Designer (Skeptical UX Evaluator)
**Context:** Layer 4 introduces normal subgroups through the "keyring cracking" mechanic

---

## 0. Executive Summary

This document provides all player-facing texts for Layer 4 (Normal Subgroups) with the core metaphor: **"Some keyrings are unbreakable — they're immune to conjugation attacks."**

**Pedagogical goal:** Players discover that some subgroups have structural privilege (normality) through interactive testing, not abstract definition.

**Key insight:** Not all subgroups are equal. Some are "structurally protected" against conjugation — these are normal subgroups, the building blocks for quotient groups (Layer 5).

---

## 1. Instruction Panel Texts (Russian)

### 1.1 Panel Title
```
СЛОЙ 4: ВЗЛОМ БРЕЛКОВ
```

### 1.2 Goal Description (Main instruction label)
```
Проверь каждый брелок на прочность.
Некоторые можно взломать обходным манёвром, другие — невзламываемы.
```

**Alternative (more concise):**
```
Найди, какие брелки можно взломать, а какие — защищены.
```

### 1.3 Mechanic Explanation (First-time modal on Layer 4 entry)

**Title:**
```
НОВЫЙ СЛОЙ: ВЗЛОМ БРЕЛКОВ
```

**Body:**
```
Не все брелки одинаковы. Некоторые можно "взломать" —
найти пару ключей (g, h), где:

  g — отмычка (ключ ВНЕ брелка)
  h — ключ С брелка

Обходной манёвр:  g · h · g⁻¹

Если результат НЕ в брелке — взлом удался! ✗
Если все попытки дают результат В брелке — брелок невзламываемый 🔒

Невзламываемые брелки называются «нормальными подгруппами».
```

**Button:** `ПОНЯТНО`

### 1.4 Short Reminder (appears in ManeuverZone header)
```
Обходной манёвр: g · h · g⁻¹
```

### 1.5 Counter Label Format
```
Взломано: {cracked_count} · Запечатано: {sealed_count} · Осталось: {remaining_count}
```

**Example:**
```
Взломано: 2 · Запечатано: 1 · Осталось: 4
```

---

## 2. Echo Hint Progression (Three-tier system)

Each keyring gets a sequence of hints triggered by:
- **Hint 1:** After 3 attempts with no crack (if not normal) OR after 5 attempts (if normal)
- **Hint 2:** After 8 attempts
- **Hint 3:** After 15 attempts OR when player clicks "Need Help" button

### 2.1 General Hints (applicable to most keyrings)

#### Hint 1: Direction (Try different elements)
```
Попробуй взять g и h из разных частей группы —
один из вращений, другой из отражений.
```

**For abelian groups:**
```
В этой группе все элементы коммутируют.
Помни: если gh = hg, то g·h·g⁻¹ всегда даёт h.
```

#### Hint 2: Structure (What to look for)
```
Обрати внимание: какие элементы перестановочны (gh = hg),
а какие нет. Сопряжение «переставляет» элементы местами.
```

**For non-normal subgroups:**
```
Если g и h НЕ коммутируют (g·h ≠ h·g),
то g·h·g⁻¹ часто даёт что-то новое.
```

#### Hint 3: Solution strategy
**For non-normal (provide cracking witness):**
```
Подсказка: попробуй g = {witness_g}, h = {witness_h}.
Это покажет взлом.
```

**For normal (encourage claim):**
```
Ты проверил достаточно пар. Все результаты — в брелке.
Возможно, этот брелок невзламываемый? 🔒
```

### 2.2 Level-Specific Hints

#### Level 4 (Z4) — First Layer 4 experience, all normal
**Hint 1:**
```
В циклических группах все подгруппы нормальны.
Проверь несколько пар — увидишь закономерность.
```

**Hint 2:**
```
Элементы Z4 коммутируют: g·h = h·g всегда.
Поэтому g·h·g⁻¹ = h — результат всегда в брелке!
```

**Hint 3:**
```
Все подгруппы этой группы невзламываемы.
Смело нажимай «НЕВЗЛАМЫВАЕМЫЙ» 🔒
```

---

#### Level 5 (D4) — First mixed example (some normal, some not)
**Hint 1 (for non-normal like {e, s01}):**
```
Попробуй взять вращение как отмычку (g),
и отражение с брелка (h).
```

**Hint 2:**
```
Вращения и отражения не коммутируют:
r1·s01 ≠ s01·r1. Это ключ к взлому.
```

**Hint 3 (cracking witness for {e, s01}):**
```
Подсказка: g = r1, h = s01.
Обходной манёвр даст s02 — это НЕ в брелке!
```

**Hint 1 (for normal like {e, r1, r2, r3}):**
```
Подгруппа вращений замкнута относительно сопряжения.
Попробуй несколько пар — все дадут вращение.
```

**Hint 2:**
```
Вращения образуют «ядро» группы D4.
Любой обходной манёвр возвращает вращение.
```

**Hint 3:**
```
Все вращения — в центре. Они коммутируют со всеми.
Брелок невзламываемый 🔒
```

---

#### Level 9 (S3) — Classic example with A3 normal
**Hint 1 (for non-normal like {e, sh}):**
```
Попробуй взять чётную перестановку (вращение) как отмычку,
и нечётную (отражение) с брелка.
```

**Hint 2:**
```
Сопряжение чётной и нечётной перестановки
может дать другую нечётную перестановку.
```

**Hint 3 (witness for {e, sh}):**
```
Подсказка: g = r1, h = sh.
Манёвр даст sv — не в брелке!
```

**Hint 1 (for normal A3 = {e, r1, r2}):**
```
Подгруппа вращений (чётные перестановки)
особенная в S3. Проверь разные пары.
```

**Hint 2:**
```
Чётные перестановки образуют знакопеременную группу A3.
Любое сопряжение чётной даёт чётную.
```

**Hint 3:**
```
Это классический пример: A3 ⊲ S3 (нормальная подгруппа).
Невзламываемый брелок 🔒
```

---

#### Level 21 (Q8) — All normal despite non-abelian (SPECIAL)
**Hint 1:**
```
Q8 — особая группа. Она некоммутативна (i·j ≠ j·i),
но посмотри, что происходит при сопряжении.
```

**Hint 2:**
```
В кватернионах сопряжение меняет знак: g·i·g⁻¹ = ±i.
Но ±i всё равно в подгруппе ⟨i⟩ = {e, i, i², i³}.
```

**Hint 3:**
```
Все подгруппы Q8 нормальны!
Это редкое свойство — такие группы называются «гамильтоновыми».
```

---

#### Level 13 (S4) — HARD boss fight, filtered subgroups
**Hint 1:**
```
S4 — большая и сложная. Проверяй методично:
попробуй разные типы перестановок.
```

**Hint 2:**
```
A4 (чётные перестановки) — нормальная.
Но подгруппы типа S3 внутри S4 — взламываемы.
```

**Hint 3:**
```
Сопряжение сохраняет тип цикла:
(12) сопряжена с (34), (123) сопряжена с (124).
Ищи подгруппы, которые НЕ замкнуты относительно сопряжения.
```

---

### 2.3 Abelian Group Auto-Hint (triggers after first successful test)

For groups where all subgroups are normal (Z4, V4, Z6, Z8):

```
Эта группа абелева — все элементы коммутируют.
В абелевых группах g·h·g⁻¹ = h всегда.
Поэтому ВСЕ брелки невзламываемы! 🔒
```

**Button options:**
- `Продолжить проверку` (для обучения)
- `Пометить все невзламываемыми` (быстрый режим)

---

## 3. Unbreakable Confirmation & Wrong-Claim Feedback

### 3.1 Correct Claim (Normal Subgroup)

**Animation:** Gold seal appears, crystals glow gold, celebration particles

**Message (HintLabel):**
```
Печать Невозможности! Этот брелок невзламываем. 🔒
```

**Alternative (more dramatic):**
```
ЗАПЕЧАТАН! Обходной манёвр бессилен против этого брелка.
```

**Summary panel entry (when all done):**
```
🔒 ЗАПЕЧАТАН: {elements}
   Невзламываемая подгруппа (нормальная)
```

---

### 3.2 Wrong Claim (Non-Normal Subgroup)

**Title overlay:**
```
Ой! Этот брелок можно взломать.
```

**Counterexample display:**
```
Попробуй эту пару:
  g = {witness_g}  (отмычка)
  h = {witness_h}  (ключ с брелка)

Манёвр: {g} · {h} · {g}⁻¹ = {result}

Результат {result} НЕ в брелке — взлом удался! ✗
```

**Animation:** Auto-fills maneuver slots with witness, executes, shows red crack

**Button:** `ПОНЯТНО`

**Follow-up hint:**
```
Попробуй другие пары, чтобы лучше понять структуру.
```

---

## 4. Layer 4 Completion Summary

### 4.1 Standard Completion (mixed cracked/sealed)

**Title:**
```
СЛОЙ 4 ЗАВЕРШЁН: ВЗЛОМ БРЕЛКОВ
```

**Body:**
```
Ты проверил все брелки на прочность!

ВЗЛОМАНО: {cracked_count}
  Эти подгруппы не защищены от сопряжения.

ЗАПЕЧАТАНО: {sealed_count}
  Эти подгруппы — НОРМАЛЬНЫЕ.
  Они невосприимчивы к обходным манёврам.

───────────────────────────────────────

ГЛАВНЫЙ ВЫВОД:
Не все подгруппы равны. Нормальные подгруппы —
структурно привилегированы. Они будут ключом
к построению новых групп на следующем слое.
```

**Detailed list:**
```
Взломанные:
  ✗ {elements_1} — свидетель: {g}·{h}·{g}⁻¹ = {result} ∉ H
  ✗ {elements_2} — свидетель: ...

Невзламываемые (нормальные):
  🔒 {elements_3} — защищена от сопряжения
  🔒 {elements_4} — защищена от сопряжения
```

**Buttons:**
- `ВЕРНУТЬСЯ НА КАРТУ`
- `Продолжить играть` (if more layers available)

---

### 4.2 All Normal (Abelian groups or Q8)

**Title:**
```
СЛОЙ 4 ЗАВЕРШЁН: ВСЕ НЕВЗЛАМЫВАЕМЫ!
```

**Body (for abelian):**
```
Все {sealed_count} брелков оказались невзламываемыми!

Это особенность абелевых (коммутативных) групп:
в них g·h·g⁻¹ = h всегда, поэтому ВСЕ подгруппы нормальны.

───────────────────────────────────────

ВЫВОД:
В абелевых группах каждая подгруппа — нормальная.
Коммутативность = максимальная защита от сопряжения.
```

**Body (for Q8 — special message):**
```
Все {sealed_count} брелков оказались невзламываемыми!

🏆 КВАТЕРНИОННЫЙ ПАРАДОКС 🏆

Группа Q8 НЕКОММУТАТИВНА (i·j ≠ j·i),
но все её подгруппы — НОРМАЛЬНЫЕ!

Это редчайшее свойство. Такие группы называются
«гамильтоновыми» в честь Уильяма Гамильтона.

───────────────────────────────────────

ВЫВОД:
Нормальность ≠ коммутативность.
Существуют неабелевы группы, где всё нормально.
```

---

### 4.3 All Cracked (hypothetical, rare)

This shouldn't happen in practice (every non-trivial group has SOME normal subgroups), but for completeness:

**Title:**
```
СЛОЙ 4 ЗАВЕРШЁН: ВСЕ ВЗЛОМАНЫ
```

**Body:**
```
Все проверенные брелки оказались уязвимы к сопряжению.

Ни одна подгруппа не защищена от обходных манёвров.

───────────────────────────────────────

ВЫВОД:
Группы с малым количеством нормальных подгрупп
имеют «жёсткую» структуру — их сложно факторизовать.
```

---

## 5. Special Text for Q8 Level (Level 21)

### 5.1 Pre-Level Briefing (optional modal before entering)

**Title:**
```
ЗАЛ КВАТЕРНИОНОВ
```

**Body:**
```
Внимание: эта группа необычна.

Кватернионы (Q8) — некоммутативны:
  i · j = k
  j · i = -k  (не то же самое!)

Но что произойдёт при проверке брелков?
Проверь сам.
```

**Button:** `НАЧАТЬ`

---

### 5.2 After First Sealed Keyring (surprise hint)

```
Странно... Эта подгруппа невзламываема,
хотя группа некоммутативна.

Попробуй проверить остальные брелки.
```

---

### 5.3 After All Sealed (Paradox Achievement)

**Overlay animation:** Gold + purple particles, special sound

**Achievement Unlocked:**
```
🏆 ПАРАДОКС КВАТЕРНИОНОВ 🏆

Ты открыл гамильтонову группу:
некоммутативную, но со всеми нормальными подгруппами.

Это математическая редкость!
```

**Reward text:**
```
Награда: Печать Гамильтона
(используется в библиотеке храма)
```

---

## 6. Special Text for Prime-Order Auto-Complete Levels

For levels with only trivial subgroups ({e} and G), Layer 4 auto-completes.

### 6.1 Auto-Complete Modal

**Title:**
```
СЛОЙ 4: АВТОМАТИЧЕСКИ ЗАВЕРШЁН
```

**Body:**
```
Группа простого порядка (|G| = {prime_order})

Единственные подгруппы:
  • {e} — тождество
  • G — вся группа

Обе тривиально нормальны.
Нечего взламывать!

───────────────────────────────────────

ВЫВОД:
В группах простого порядка нет нетривиальных
собственных подгрупп. Слой 4 пропущен.
```

**Button:** `ПОНЯТНО`

---

**Affected levels:**
- Level 1 (Z3, order 3)
- Level 2 (Z2, order 2)
- Level 3 (Z5, order 5)
- Level 7 (Z7, order 7)
- Level 10 (Z11, order 11)

---

## 7. Button Labels & UI Strings

### 7.1 Maneuver Zone Buttons

**Execute button (enabled):**
```
ВЫПОЛНИТЬ МАНЁВР
```

**Execute button (disabled):**
```
Выберите g и h
```

**Unbreakable button (hidden state):**
```
(invisible)
```

**Unbreakable button (disabled, insufficient attempts):**
```
Невзламываемый? (ещё {remaining} попыток)
```

**Unbreakable button (disabled, coverage incomplete):**
```
Невзламываемый? (проверь все ключи)
```

**Unbreakable button (enabled, ready to claim):**
```
НЕВЗЛАМЫВАЕМЫЙ 🔒
```

---

### 7.2 Lockpick Panel

**Panel title:**
```
Отмычки (G \ H)
```

**Lockpick count label:**
```
{count} отмычек
```

**Empty state (shouldn't happen):**
```
Нет доступных отмычек
```

---

### 7.3 Keyring List Panel

**Panel title:**
```
Брелки
```

**Progress label:**
```
Взломано: {cracked} · Запечатано: {sealed} · Осталось: {remaining}
```

**Keyring slot states:**

*PENDING:*
```
Брелок #{index}
(ожидает)
```

*ACTIVE:*
```
● ● ● ●
Брелок #{index}  ←
{order} ключей
Попыток: {attempt_count}
```

*CRACKED:*
```
● ● ●
Брелок #{index}  ✗
ВЗЛОМАН
g={g}, h={h} → {result}
```

*SEALED:*
```
● ● ●
Брелок #{index}  🔒
НЕВЗЛАМЫВАЕМЫЙ
Печать ✓
```

---

### 7.4 Coverage Indicator

**Label:**
```
Покрытие h:
```

**Visual:** Row of colored dots with checkmarks/empty

**Tooltip (on hover over dot):**
```
{key_name}: {tested ? "проверен ✓" : "не проверен"}
```

---

### 7.5 Result Display (after maneuver execution)

**Success (ghg⁻¹ ∈ H):**
```
● {result_label} — В брелке ✓
```
*Color: green*

**Crack (ghg⁻¹ ∉ H):**
```
● {result_label} — НЕ в брелке! ✗
```
*Color: red*

---

## 8. Pedagogical Flow & Timing

### 8.1 First Exposure (Level 4 or first Layer 4 encounter)

**Sequence:**
1. **Entry modal** (section 1.3) — explain mechanics
2. **First keyring auto-selected** — player sees active state
3. **Player selects g** — lockpick panel highlights
4. **Player selects h** — keyring panel highlights
5. **Player clicks EXECUTE** — animation plays (3 phases)
6. **Result displays** — green (in H) or red (crack)
7. **Hint 1 triggers** after 3-5 attempts
8. **Coverage indicator** updates in real-time
9. **Unbreakable button appears** when threshold met
10. **Player claims or cracks** — keyring resolved
11. **Next keyring activates** — repeat

**Critical timing:**
- Modal: 5-10 seconds read time, then dismiss
- Animation: 2.5 seconds (3 phases × 0.6s + pauses)
- Hint delay: 3 seconds after attempt before showing
- Celebration: 2 seconds before auto-advancing

---

### 8.2 Learning Curve Expectations

**Easy levels (Z4, V4):**
- All normal → quick "aha!" moment
- Abelian hint triggers → understanding deepens
- Expected time: 3-5 minutes per level

**Medium levels (D4, S3):**
- Mix of normal/non-normal
- Player experiments, discovers patterns
- Expected time: 5-10 minutes per level

**Hard levels (S4, D6):**
- Filtered subgroups (8 out of many)
- Requires strategic thinking
- Expected time: 10-15 minutes per level

**Special (Q8):**
- Surprise + paradox
- Pedagogical "wow" moment
- Expected time: 5-7 minutes + reflection

---

### 8.3 Frustration Mitigation

**Problem:** Player stuck after many attempts, no crack, won't claim unbreakable

**Solution:** Progressive hint system
- 3 attempts → Hint 1 (direction)
- 8 attempts → Hint 2 (structure)
- 15 attempts → Hint 3 (solution/encouragement)
- 20 attempts → "Need Help?" button appears

**"Need Help?" button action:**
- If non-normal: Auto-fill witness and execute
- If normal: Show detailed explanation + enable unbreakable button

---

**Problem:** Player claims unbreakable incorrectly (false positive)

**Solution:** Counterexample with explanation (section 3.2)
- Auto-demonstrates the crack
- Player sees WHY it's not normal
- Encourages deeper exploration

---

**Problem:** Player bored by repetitive testing in abelian groups

**Solution:** Abelian auto-hint (section 2.3)
- Triggers after first test
- Offers "mark all unbreakable" shortcut
- Preserves option to continue for learning

---

## 9. Accessibility & Clarity

### 9.1 Color-Blind Considerations

**Red/Green distinction:**
- ✅ Use BOTH color AND icons (✓ / ✗)
- ✅ Crack feedback includes shake animation (not just color)
- ✅ Seal feedback includes gold glow + particle effect

**Coverage indicator:**
- Use checkmark ✓ / dot · instead of color alone

---

### 9.2 Text Readability

**Font sizes:**
- Modal body: 18-20px
- Hint text: 16-18px
- Button labels: 16-18px (bold)
- Counter: 14-16px

**Contrast ratios:**
- Red text on dark BG: 7:1 minimum
- Gold text on dark BG: 7:1 minimum
- Green text on dark BG: 7:1 minimum

---

### 9.3 Tutorial Clarity

**First-time player checklist:**
- ✅ Explicit modal explains "what is conjugation"
- ✅ Visual feedback (animation) shows g·h·g⁻¹ step-by-step
- ✅ Hints guide toward solution without spoiling
- ✅ Counterexample teaches when wrong claim made
- ✅ Summary reinforces key insight

**No assumed knowledge:**
- "Conjugation" not used in UI text (only in summary)
- "Обходной манёвр" (detour maneuver) is intuitive metaphor
- "Отмычка" (lockpick) vs "ключ с брелка" (key from keyring) clear distinction

---

## 10. UX Review & Concerns

### 10.1 Strengths ⭐⭐⭐⭐⭐

1. **Metaphor is intuitive:** "Cracking" vs "Unbreakable" is clear
2. **Interactive discovery:** Player constructs tests, not passive observation
3. **Progressive hints:** Scaffolding prevents frustration
4. **Counterexample pedagogy:** Wrong claims become learning moments
5. **Q8 paradox:** Memorable "wow" moment ties abstract to concrete

---

### 10.2 Potential Friction Points ⚠️

**Concern 1: Three-slot maneuver is new interaction**
- Players haven't filled slots before (Layers 1-3 use different mechanics)
- **Mitigation:** Modal explicitly shows "select g, then h"
- **Recommendation:** Add visual pulse on empty slots to guide attention

**Concern 2: "Coverage threshold" may feel arbitrary**
- Why 10 attempts? Why test each h?
- **Mitigation:** Show coverage indicator with "you've tested these" checkmarks
- **Recommendation:** Tooltip on disabled Unbreakable button: "Проверь ещё 3 ключа"

**Concern 3: Auto-complete may feel unsatisfying**
- Players click Level 1, immediately get "auto-completed" modal
- **Mitigation:** Clear explanation of WHY (prime order → no nontrivial subgroups)
- **Recommendation:** Add "View group structure anyway" button for curious players

**Concern 4: Long testing sequences in hard levels (S4)**
- 8 filtered subgroups × 10 attempts each = 80+ interactions
- **Mitigation:** Hints arrive earlier (after 3/8/15 instead of 5/10/20)
- **Recommendation:** Allow player to select which keyring to test (not forced order)

---

### 10.3 Recommended Polish

**High Priority:**
1. **Visual pulse** on empty maneuver slots (first use)
2. **Tooltip** on disabled Unbreakable button (shows remaining requirements)
3. **"Skip abelian"** option in settings for experienced players
4. **Progress bar** in S4 (8 keyrings) to show overall completion

**Medium Priority:**
5. **Sound design:** Crack sound (sharp), seal sound (resonant), maneuver sound (sequence)
6. **Particle effects:** Red shards on crack, gold sparks on seal
7. **Hover preview:** Show result prediction when hovering candidate pairs

**Nice to Have:**
8. **Replay button** on summary to review crack witnesses
9. **Compare view:** Side-by-side normal vs non-normal subgroups
10. **Export to notebook:** Save discoveries for later reference

---

## 11. Cross-Layer Narrative Continuity

### 11.1 Connection to Layer 3 (Subgroups)

**Layer 3 taught:**
- Subgroups are "keyrings" — closed sets of keys
- Some keyrings control "wings" of the vault

**Layer 4 extends:**
- Not all keyrings are equal
- Some are "structurally protected" (normal)
- This protection will matter in Layer 5 (quotient groups)

**Bridge text (in Layer 4 intro modal):**
```
На Слое 3 ты собрал брелки (подгруппы).
Теперь проверь их на прочность.
```

---

### 11.2 Setup for Layer 5 (Quotient Groups)

**Layer 4 completion summary foreshadows:**
```
Невзламываемые (нормальные) подгруппы —
ключ к построению новых групп на следующем слое.
```

**Layer 5 opening (future):**
```
Помнишь невзламываемые брелки из Слоя 4?
Теперь используй их, чтобы «склеить» части зала
и создать новый, меньший зал.
```

---

### 11.3 Echo Voice Consistency

**Echo personality (established in Layers 1-3):**
- Mysterious but helpful
- Asks questions instead of lecturing
- Encourages experimentation

**Layer 4 Echo hints maintain voice:**
```
Попробуй взять g и h из разных частей группы...
Обрати внимание: какие элементы перестановочны...
Ты проверил достаточно пар — может, брелок невзламываемый?
```

**Avoid:**
- Lecturing tone: "Нормальная подгруппа определяется как..."
- Condescending: "Очевидно, что..."
- Over-explaining: "Как ты уже знаешь из алгебры..."

---

## 12. Localization Notes (Future)

**English equivalents for key terms:**
- Слой 4 → Layer 4
- Взлом брелков → Keyring Cracking
- Обходной манёвр → Detour Maneuver (or Conjugation Maneuver)
- Отмычка → Lockpick
- Невзламываемый → Unbreakable
- Печать Невозможности → Seal of Impossibility

**Metaphor adaptability:**
- "Cracking" works in most languages
- "Lockpick" vs "Key" distinction may need cultural adjustment
- Mathematical terms (conjugation, normal subgroup) keep standard translations

---

## 13. Testing Checklist

Before shipping Layer 4 texts, verify:

- [ ] Modal displays correctly on first entry
- [ ] Hints trigger at correct attempt counts
- [ ] Abelian auto-hint appears (Z4, V4, Z6)
- [ ] Q8 paradox achievement unlocks
- [ ] Counterexample animation plays smoothly
- [ ] Coverage indicator updates in real-time
- [ ] Unbreakable button states transition correctly
- [ ] Summary panel shows all keyrings with results
- [ ] Auto-complete modal appears for prime-order groups
- [ ] Text fits in UI panels (no overflow)
- [ ] Contrast ratios meet accessibility standards (7:1)
- [ ] All Russian text reviewed for grammar/clarity
- [ ] Button labels are action-oriented (not passive)
- [ ] No mathematical jargon in player-facing text
- [ ] Metaphors consistent across all hints

---

## 14. Final Pedagogical Insight

**What players should take away from Layer 4:**

> *"Some subgroups are special — they're immune to 'being moved around' by other elements. These normal subgroups have structural privilege. They're the ones we can use to build new groups from old ones."*

**NOT:**
> *"A subgroup H is normal in G if and only if gHg⁻¹ = H for all g ∈ G."*

**The difference:**
- First = intuition + motivation + connection to future (Layer 5)
- Second = definition without context (dry, unmemorable)

**Layer 4 texts prioritize:**
1. **Intuition** — "crackable" vs "unbreakable" is visceral
2. **Agency** — player actively tests, claims, discovers
3. **Surprise** — Q8 paradox, abelian "all normal" revelation
4. **Foreshadowing** — normal subgroups unlock quotient groups

This approach builds mathematical maturity through **experience**, not memorization.

---

*End of Document*

**Files Created:**
- `.tayfa/game_designer/T108_LAYER4_TEXTS.md`

**Next Steps:**
- Architect: Integrate texts into UI components (ManeuverZone, Modal, HintLabel)
- Programmer: Implement hint triggering logic in ConjugationCrackingManager
- Sound Designer: Create crack/seal/maneuver sound effects
- QA: Test hint sequence flow on all level types (abelian, non-abelian, Q8, prime-order)
