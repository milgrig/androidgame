# T104: Layer 4 — Архитектура UI и механики «Взлом брелков»

> **Автор**: architect | **Дата**: 2026-02-28
> **Задача**: Спроектировать UI layout, трёхслотовый манёвр с анимацией, кнопку «Невзламываемый», data model и edge cases для Слоя 4
> **Зависимости**: T095 (каталог подгрупп — DONE), T103 (каталог нормальности — DONE), T096 (Layer 3 архитектура — DONE)
> **Refs**: redesign.md секция 3.5, layer_mode_controller.gd, subgroup_checker.gd

---

## 0. Executive Summary

Layer 4 (Red) — **«Взлом брелков»** — player tests whether each subgroup (keyring) from Layer 3 is normal or not via the **conjugation maneuver** ghg⁻¹. This is the most interactive layer yet: the player actively constructs test operations, observes animated results, forms hypotheses, and makes claims.

**Core mechanic**: Three-slot conjugation zone — player selects g (lockpick from G\H) and h (key from H), system auto-fills g⁻¹, player executes and observes whether result ∈ H.

**Two outcomes per keyring**:
1. **CRACKED** — player finds (g,h) where ghg⁻¹ ∉ H → red crack animation
2. **SEALED** — player tests enough pairs, all pass → claims "Unbreakable" → gold seal

**Pedagogical goal**: Teach that not all subgroups are equal — some are "structurally privileged" (normal), preparing for Layer 5 (quotient groups).

---

## 1. UI Layout — Three-Zone Split

### 1.1 Общая схема

```
┌──────────────────────────────────────────────────────────────────────┐
│  LevelNumberLabel: "Зал 5 · Слой 4: Взлом брелков"         [red]   │
├────────────────────┬───────────────────┬─────────────────────────────┤
│                    │                   │                             │
│  KEYRING ZONE      │  LOCKPICK ZONE    │  CRYSTAL + ROOM MAP ZONE    │
│  (25% ширины)      │  (20% ширины)     │  (55% ширины)               │
│                    │                   │                             │
│  ┌──────────┐      │  ┌──────────┐    │  ┌──────────────────────┐   │
│  │ Брелок H │ ←    │  │ Отмычка  │    │  │                      │   │
│  │ {e,r1,r2}│      │  │  g1      │    │  │  Кристаллы + рёбра   │   │
│  │ (3 ключа)│      │  │  g2      │    │  │  (animation zone)    │   │
│  └──────────┘      │  │  g3      │    │  │                      │   │
│  ┌──────────┐      │  │  g4      │    │  │  Анимация ghg⁻¹      │   │
│  │ Брелок H2│      │  │  ...     │    │  │  показывается здесь  │   │
│  │ (CRACKED)│ ✗    │  └──────────┘    │  │                      │   │
│  └──────────┘      │                   │  └──────────────────────┘   │
│  ┌──────────┐      │                   │  ┌──────────────────────┐   │
│  │ Брелок H3│      │                   │  │  Карта комнат        │   │
│  │ (SEALED) │ 🔒   │                   │  │  (room_map_panel)    │   │
│  └──────────┘      │                   │  └──────────────────────┘   │
│        ...         │                   │                             │
├────────────────────┴───────────────────┴─────────────────────────────┤
│  MANEUVER ZONE — Зона обходного манёвра                             │
│  ┌────────┐  ┌────────┐  ┌────────┐                                 │
│  │ g      │  │ h      │  │ g⁻¹    │  ← auto-filled                 │
│  │ (drop) │  │ (drop) │  │ (auto) │                                 │
│  └────────┘  └────────┘  └────────┘                                 │
│                                                                      │
│  [ВЫПОЛНИТЬ МАНЁВР]        Результат: ?         [НЕВЗЛАМЫВАЕМЫЙ]     │
│                                                                      │
│  Попыток: 3/10     Покрытие: h₁ ✓  h₂ ✓  h₃ ·         [red theme]  │
├──────────────────────────────────────────────────────────────────────┤
│  Брелки: Взломано 2 · Запечатано 1 · Осталось 4       Прогресс     │
└──────────────────────────────────────────────────────────────────────┘
```

### 1.2 Размеры и адаптивность

```gdscript
# Layer 4 layout ratios
const L4_KEYRING_ZONE_RATIO := 0.25      # 25% ширины — список брелков
const L4_LOCKPICK_ZONE_RATIO := 0.20     # 20% ширины — отмычки (G\H)
const L4_CRYSTAL_ZONE_RATIO := 0.55      # 55% ширины — кристаллы + анимация
const L4_MANEUVER_ZONE_HEIGHT := 140     # px — зона манёвра внизу
const L4_MANEUVER_SLOT_SIZE := 72        # px — размер одного слота
const L4_MANEUVER_SLOT_GAP := 24         # px — промежуток между слотами
const L4_RESULT_DISPLAY_SIZE := 80       # px — отображение результата
```

**Адаптивность по количеству брелков (не считая {e} и G):**

| Нетрив. брелков | Высота слота | Скролл | Примеры уровней |
|-----------------|-------------|--------|-----------------|
| 1-3             | 80 px       | Нет    | Z4, V4, Z6, Z8 |
| 4-6             | 65 px       | Нет    | D4, S3, D5, A4 |
| 7-10            | 50 px       | ScrollContainer | D6, S4 (filtered), D4×Z2 |

### 1.3 Godot-реализация (сцена-дерево)

```
HUD CanvasLayer
├── LevelNumberLabel                          ← существует, меняется текст
├── KeyringListFrame (Panel)                  ← НОВЫЙ: левая зона
│   ├── KeyringListTitle (Label): "Брелки"
│   ├── ScrollContainer
│   │   └── KeyringList (VBoxContainer)
│   │       ├── CrackableKeyringSlot_0        ← текущий тестируемый
│   │       ├── CrackableKeyringSlot_1        ← CRACKED / SEALED / пусто
│   │       └── ...
│   └── ProgressLabel: "Взломано: 2 · Запечатано: 1 · Осталось: 4"
├── LockpickFrame (Panel)                     ← НОВЫЙ: зона отмычек
│   ├── LockpickTitle (Label): "Отмычки (G \ H)"
│   ├── ScrollContainer
│   │   └── LockpickList (VBoxContainer)
│   │       ├── LockpickButton_0              ← g-ключи
│   │       └── ...
│   └── LockpickCount (Label): "6 отмычек"
├── CrystalFrame (Panel)                      ← существует, уменьшается
├── MapFrame (Panel)                          ← существует
├── ManeuverZone (PanelContainer)             ← НОВЫЙ: зона манёвра
│   ├── ManeuverTitle (Label): "Обходной манёвр"
│   ├── SlotsContainer (HBoxContainer)
│   │   ├── SlotG (ManeuverSlot)              ← drag target / tap select
│   │   ├── SlotLabel_1 (Label): "·"
│   │   ├── SlotH (ManeuverSlot)              ← drag target / tap select
│   │   ├── SlotLabel_2 (Label): "·"
│   │   └── SlotGInv (ManeuverSlot)           ← auto-filled (readonly)
│   ├── ExecuteButton (Button): "ВЫПОЛНИТЬ"
│   ├── ResultDisplay (Panel)                 ← показывает ghg⁻¹
│   ├── UnbreakableButton (Button)            ← появляется после threshold
│   └── CoverageIndicator (HBoxContainer)     ← h-покрытие
├── CounterLabel                              ← существует
└── HintLabel                                 ← существует
```

---

## 2. Зона брелков (KeyringListFrame) — CrackableKeyringSlot

### 2.1 Четыре состояния слота

```
PENDING (ожидает)           ACTIVE (тестируется)         CRACKED (взломан)          SEALED (запечатан)
┌─ ─ ─ ─ ─ ─ ─ ─ ┐       ┌────────────────────┐       ┌════════════════════┐       ┌════════════════════┐
│                  │       │ ● ● ●              │       ║ ● ● ●              ║       ║ ● ● ●              ║
│   Брелок #3      │       │ Брелок #2    ←     │       ║ Брелок #1    ✗     ║       ║ Брелок #3    🔒    ║
│   (ожидает)      │       │ {e, sh, sv}         │       ║ ВЗЛОМАН            ║       ║ НЕВЗЛАМЫВАЕМЫЙ     ║
│                  │       │ Попыток: 7          │       ║ g=r1, h=sh → sv   ║       ║ Печать ✓           ║
└─ ─ ─ ─ ─ ─ ─ ─ ┘       └────────────────────┘       └════════════════════┘       └════════════════════┘
  Пунктирная рамка          Красная тонкая рамка          Красная + crack           Золотая + glow
  Серый текст                Красный текст + ←            Красный BG + трещина       Золотой BG + свечение
```

### 2.2 Визуальные константы

```gdscript
# Layer 4 RED color scheme
const L4_RED := Color(0.90, 0.20, 0.15, 1.0)
const L4_RED_DIM := Color(0.65, 0.18, 0.12, 0.7)
const L4_RED_BG := Color(0.08, 0.02, 0.02, 0.8)
const L4_RED_BORDER := Color(0.55, 0.15, 0.10, 0.7)
const L4_RED_GLOW := Color(1.0, 0.25, 0.20, 0.9)
const L4_RED_CRACK := Color(1.0, 0.1, 0.05, 1.0)

# Re-use gold for SEALED state
const L4_SEAL_GOLD := Color(0.95, 0.80, 0.20, 1.0)
const L4_SEAL_GOLD_BG := Color(0.08, 0.07, 0.02, 0.95)
const L4_SEAL_GOLD_GLOW := Color(1.0, 0.90, 0.30, 0.9)

# Green for "in-keyring" result
const L4_IN_KEYRING := Color(0.3, 0.9, 0.4, 1.0)
```

### 2.3 Содержимое слота

Ключи внутри — **цветные точки** (circles), цвет из `RoomState.colors[key_idx]`. Консистентно с Layer 3 KeyringSlot.

```
┌──────────────────────────┐
│ ● ● ●                    │   ● = ключ в брелке (цвет комнаты)
│ Брелок #2    3 ключа      │   ACTIVE: красная рамка + ←
│ Попыток: 7                │   Число попыток показывается
└──────────────────────────┘
```

### 2.4 Тривиальные подгруппы

- **{e}** и **G (полная группа)** — **исключаются** из Layer 4 (всегда нормальные, тестировать нечего)
- Только нетривиальные собственные подгруппы тестируются
- Фильтрация из layer_3.subgroups: `is_trivial == false AND order < |G|`

### 2.5 API класса CrackableKeyringSlot

```gdscript
class_name CrackableKeyringSlot
extends PanelContainer

enum State { PENDING, ACTIVE, CRACKED, SEALED }

var slot_index: int = 0
var state: State = State.PENDING
var subgroup_elements: Array[String] = []   # sym_ids ключей в брелке H
var subgroup_order: int = 0
var is_normal: bool = false                 # ground truth (for backend validation)
var attempt_count: int = 0                  # сколько пар протестировано
var cracking_witness: Dictionary = {}       # {g, h, result} если CRACKED
var label_text: String = ""

signal slot_tapped(slot_index: int)         # player wants to test this keyring

func set_active() -> void                   # → ACTIVE
func set_cracked(witness: Dictionary) -> void  # → CRACKED, store witness
func set_sealed() -> void                   # → SEALED
func update_attempt_count(count: int) -> void
func get_elements() -> Array[String]
```

---

## 3. Зона отмычек (LockpickFrame)

### 3.1 Содержимое

Когда брелок H активен, зона отмычек показывает G \ H — все ключи полной группы, которых **нет** в H.

```
┌───────────────────┐
│  Отмычки (G \ H)  │
│                   │
│  ┌──────────┐     │
│  │ ● r1     │     │   ← tap для выбора в слот g
│  └──────────┘     │
│  ┌──────────┐     │
│  │ ● sh     │     │
│  └──────────┘     │
│  ┌──────────┐     │
│  │ ● sv     │     │
│  └──────────┘     │
│  ┌──────────┐     │
│  │ ● sd     │     │
│  └──────────┘     │
│                   │
│  4 отмычки        │
└───────────────────┘
```

### 3.2 Интеракция

- **Tap** на отмычку → заполняет SlotG в ManeuverZone
- **Drag** (опционально) → drag preview к SlotG
- Выбранная отмычка подсвечивается красным border
- Identity ключ **не включается** в отмычки (e ∈ H всегда)

### 3.3 API

```gdscript
class_name LockpickPanel
extends PanelContainer

signal lockpick_selected(sym_id: String)

var _lockpick_buttons: Array[Button] = []
var _selected_sym_id: String = ""

func populate(all_keys: Array[String], keyring_keys: Array[String], room_state: RoomState) -> void
func get_selected() -> String
func clear_selection() -> void
func highlight_used(sym_id: String) -> void   # подсветить протестированные
```

---

## 4. Зона обходного манёвра (ManeuverZone) — три слота

### 4.1 Layout трёх слотов

```
┌─────────────────────────────────────────────────────────────────────────┐
│  ОБХОДНОЙ МАНЁВР                                                        │
│                                                                         │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐                         │
│  │          │     │          │     │          │                         │
│  │    g     │  ·  │    h     │  ·  │   g⁻¹   │     = ???               │
│  │  (drop)  │     │  (drop)  │     │  (auto)  │                         │
│  │          │     │          │     │          │                         │
│  └──────────┘     └──────────┘     └──────────┘                         │
│  [отмычка]        [из брелка]      [авто]                               │
│                                                                         │
│               ┌──────────────────────────┐                              │
│               │   ВЫПОЛНИТЬ МАНЁВР       │                              │
│               └──────────────────────────┘                              │
│                                                                         │
│  Результат: ●r2 — В брелке ✓ (зелёное)  |  ●sv — НЕ в брелке ✗ (кр.) │
│                                                                         │
│  Покрытие h: [●✓] [●✓] [●·]   Попыток: 5/10                           │
│                                                                         │
│               ┌──────────────────────────┐                              │
│               │  НЕВЗЛАМЫВАЕМЫЙ 🔒       │  ← появляется после         │
│               └──────────────────────────┘    выполнения threshold      │
└─────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Три слота — ManeuverSlot

```gdscript
class_name ManeuverSlot
extends PanelContainer

enum SlotType { G_SLOT, H_SLOT, G_INV_SLOT }

var slot_type: SlotType
var sym_id: String = ""              # заполненный ключ
var is_filled: bool = false
var is_auto: bool = false            # G_INV_SLOT всегда auto

signal slot_filled(slot_type: SlotType, sym_id: String)
signal slot_cleared(slot_type: SlotType)

func fill(sym_id: String, color: Color, label: String) -> void
func clear() -> void
func set_auto_fill(sym_id: String, color: Color, label: String) -> void
```

### 4.3 Заполнение слотов — flow

```
1. Игрок tap на отмычку (LockpickPanel) → SlotG заполняется
   → SlotGInv автоматически заполняется (g⁻¹ уже известен из Layer 2)

2. Игрок tap на ключ из брелка (KeyringListFrame, active slot) → SlotH заполняется

3. Оба слота заполнены → кнопка ВЫПОЛНИТЬ активируется

4. Игрок tap ВЫПОЛНИТЬ → вычисление + анимация + результат

Альтернативно:
- Tap на заполненный слот → очищает его
- Tap на другой ключ → заменяет текущий
```

### 4.4 Кнопка ВЫПОЛНИТЬ — состояния

```gdscript
# Кнопка ВЫПОЛНИТЬ
var execute_btn: Button

func _update_execute_state() -> void:
    var can_execute: bool = (
        _slot_g.is_filled and
        _slot_h.is_filled and
        _slot_g_inv.is_filled and   # always true if g filled
        not _animation_playing
    )
    execute_btn.disabled = not can_execute

    if can_execute:
        execute_btn.text = "ВЫПОЛНИТЬ МАНЁВР"
        _apply_button_style(execute_btn, L4_RED, L4_RED_BG)
    else:
        execute_btn.text = "Выберите g и h"
        _apply_button_style(execute_btn, L4_RED_DIM, Color(0.05, 0.02, 0.02, 0.5))
```

### 4.5 Tap-to-select для KeyBar интеграция

Layer 4 **не использует KeyBar напрямую**. Вместо этого ключи показываются в двух отдельных зонах:
- Ключи H → в KeyringListFrame (левая зона), тапаются для SlotH
- Ключи G\H → в LockpickPanel, тапаются для SlotG

Это позволяет визуально разделить «внутренние» и «внешние» ключи.

---

## 5. Анимация кристаллов — три фазы ghg⁻¹

### 5.1 Три фазы анимации

При нажатии ВЫПОЛНИТЬ, кристаллы показывают пошаговое вычисление:

```
Фаза 1: Применить g (0.6 сек)
   Кристаллы перемещаются по перестановке g
   Дуга подсвечивается КРАСНЫМ цветом
   Слот g пульсирует

Пауза (0.3 сек)

Фаза 2: Применить h (0.6 сек)
   Кристаллы перемещаются дальше по перестановке h
   Дуга подсвечивается ЗОЛОТЫМ цветом (ключ из брелка)
   Слот h пульсирует

Пауза (0.3 сек)

Фаза 3: Применить g⁻¹ (0.6 сек)
   Кристаллы перемещаются по перестановке g⁻¹
   Дуга подсвечивается КРАСНЫМ (обратный = та же отмычка)
   Слот g⁻¹ пульсирует

Пауза (0.3 сек)

Фаза 4: Результат (0.5 сек)
   Итоговая позиция кристаллов = перестановка ghg⁻¹
   Сравнение с элементами H:
     IN H → зелёное свечение на всех кристаллах
     NOT IN H → красная трещина (crack effect) на кристаллах

Сброс (0.4 сек)
   Кристаллы возвращаются в identity позиции
```

### 5.2 Реализация через SwapManager

```gdscript
## Runs the 3-phase conjugation animation on crystal nodes.
## g_perm, h_perm: Permutation objects for g and h
## g_inv_perm: automatically computed as g.inverse()
## Returns: the result permutation ghg⁻¹
func play_conjugation_animation(
    g_perm: Permutation,
    h_perm: Permutation,
    g_inv_perm: Permutation,
    level_scene,
    on_complete: Callable
) -> Permutation:
    var result_perm: Permutation = g_perm.compose(h_perm).compose(g_inv_perm)

    # Build animation sequence
    var tween: Tween = level_scene.create_tween()
    tween.set_parallel(false)  # sequential

    # Phase 1: apply g
    tween.tween_callback(_highlight_slot.bind("g"))
    tween.tween_callback(_animate_permutation.bind(g_perm, L4_RED, level_scene))
    tween.tween_interval(0.6)
    tween.tween_callback(_unhighlight_slot.bind("g"))
    tween.tween_interval(0.3)

    # Phase 2: apply h (on top of g, so net = gh)
    tween.tween_callback(_highlight_slot.bind("h"))
    var gh_perm := g_perm.compose(h_perm)
    tween.tween_callback(_animate_permutation.bind(gh_perm, L4_SEAL_GOLD, level_scene))
    tween.tween_interval(0.6)
    tween.tween_callback(_unhighlight_slot.bind("h"))
    tween.tween_interval(0.3)

    # Phase 3: apply g⁻¹ (net = ghg⁻¹)
    tween.tween_callback(_highlight_slot.bind("g_inv"))
    tween.tween_callback(_animate_permutation.bind(result_perm, L4_RED, level_scene))
    tween.tween_interval(0.6)
    tween.tween_callback(_unhighlight_slot.bind("g_inv"))
    tween.tween_interval(0.3)

    # Phase 4: show result
    tween.tween_callback(on_complete.bind(result_perm))

    return result_perm


## Animate crystals to the positions given by a permutation.
## Each crystal tweens from its current position to the target position.
func _animate_permutation(perm: Permutation, color: Color, level_scene) -> void:
    var sm: ShuffleManager = level_scene._shuffle_mgr
    var positions_map: Dictionary = sm.get_positions_map()

    for i in range(perm.size()):
        var crystal_id: int = sm.current_arrangement[i]
        var target_slot: int = perm.apply(i)  # where crystal goes
        if crystal_id in level_scene.crystals and target_slot in positions_map:
            var crystal: CrystalNode = level_scene.crystals[crystal_id]
            var target_pos: Vector2 = positions_map[target_slot]
            var tw: Tween = level_scene.create_tween()
            tw.tween_property(crystal, "position", target_pos, 0.5)\
                .set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
            # Color flash on the crystal during movement
            crystal.modulate = color
            tw.tween_property(crystal, "modulate", Color.WHITE, 0.3)
```

### 5.3 Результат — два визуальных исхода

**ghg⁻¹ ∈ H (в брелке):**
```
- Все кристаллы вспыхивают ЗЕЛЁНЫМ (L4_IN_KEYRING)
- Ключ-результат подсвечивается в левой зоне (брелок)
- Мягкий звук аккорда ↑
- Текст результата: "● r2 — в брелке ✓"
- Цвет текста: зелёный
```

**ghg⁻¹ ∉ H (не в брелке):**
```
- Все кристаллы вспыхивают КРАСНЫМ с crack-эффектом
- Crack-shader / particle burst на кристаллах
- Резкий звук треска
- Текст результата: "● sv — НЕ в брелке! ✗"
- Цвет текста: красный
- Брелок помечается CRACKED
- Shake-анимация на CrackableKeyringSlot
```

### 5.4 Crack-эффект (визуальные детали)

```gdscript
## Red crack feedback when ghg⁻¹ ∉ H
func play_crack_feedback(crystals: Dictionary, edges: Array) -> void:
    # 1. Flash all crystals red
    for crystal in crystals.values():
        var tw: Tween = crystal.create_tween()
        tw.tween_property(crystal, "modulate", L4_RED_CRACK, 0.1)
        tw.tween_property(crystal, "modulate", Color.WHITE, 0.8)

    # 2. Shake effect on the active keyring slot
    if _active_slot:
        var orig_pos: Vector2 = _active_slot.position
        var shake_tw: Tween = _active_slot.create_tween()
        shake_tw.tween_property(_active_slot, "position",
            orig_pos + Vector2(8, 0), 0.05)
        shake_tw.tween_property(_active_slot, "position",
            orig_pos - Vector2(8, 0), 0.05)
        shake_tw.tween_property(_active_slot, "position",
            orig_pos + Vector2(4, 0), 0.05)
        shake_tw.tween_property(_active_slot, "position",
            orig_pos, 0.05)

    # 3. Red particle burst (optional, from FeedbackFX)
    if _level_scene.feedback_fx:
        _level_scene.feedback_fx.play_crack_particles(
            _active_slot.global_position, L4_RED_CRACK)
```

---

## 6. Кнопка «НЕВЗЛАМЫВАЕМЫЙ» — threshold система

### 6.1 Когда кнопка появляется

Кнопка «НЕВЗЛАМЫВАЕМЫЙ» (Unbreakable) неактивна/скрыта по умолчанию. Активируется при выполнении **всех** условий:

```gdscript
## Thresholds for the Unbreakable button
func _check_unbreakable_threshold() -> bool:
    var h_count: int = _active_subgroup_elements.size()  # |H| не считая e
    var g_count: int = _lockpick_count                    # |G \ H|
    var total_possible: int = h_count * g_count           # total (g,h) pairs
    var min_attempts: int = 0
    var coverage_met: bool = false

    # Rule 1: Minimum 10 attempts OR 50% of all possible pairs
    min_attempts = maxi(10, ceili(total_possible * 0.5))
    # For very small groups, lower the threshold
    if total_possible <= 6:
        min_attempts = total_possible  # must try all pairs

    var attempts_met: bool = _attempt_count >= min_attempts

    # Rule 2: At least 1 pair tested with EACH h ∈ H (h ≠ e)
    var non_identity_h: Array[String] = _active_subgroup_elements.filter(
        func(s): return s != "e")
    coverage_met = true
    for h_sym in non_identity_h:
        if not _tested_h_elements.has(h_sym):
            coverage_met = false
            break

    # Rule 3: All tested pairs must have passed (ghg⁻¹ ∈ H)
    var all_passed: bool = _crack_found == false

    return attempts_met and coverage_met and all_passed
```

### 6.2 Threshold таблица по группам (T103 data)

| Уровень | Группа | |H| (макс нетрив.) | |G\H| | Всего пар | min_attempts | Примечание |
|---------|--------|-------------------|-------|-----------|-------------|-------------|
| 4       | Z4     | 2 ({e,r2})        | 2     | 4         | 4 (все)     | Маленькая группа |
| 5       | D4     | 4 ({e,r1,r2,r3})  | 4     | 16        | 10          | Типичный |
| 9       | S3     | 3 ({e,r1,r2})     | 3     | 9         | 9 (все)     | |
| 13      | S4     | 12 (A4)           | 12    | 144       | 72          | Boss fight! |
| 21      | Q8     | 4 (⟨i⟩)           | 4     | 16        | 10          | All normal! |

### 6.3 Кнопка — визуал и состояния

```
HIDDEN:     Кнопка невидима (не хватает попыток)
DISABLED:   Кнопка видна, но серая (попыток достаточно, но покрытие h неполное)
ENABLED:    Кнопка красная с пульсацией, готова к нажатию
```

```gdscript
## Unbreakable button styling
func _update_unbreakable_button() -> void:
    if _crack_found:
        # Keyring already cracked — hide button entirely
        _unbreakable_btn.visible = false
        return

    var threshold_met: bool = _check_unbreakable_threshold()

    if _attempt_count < 3:
        # Too few attempts — don't show yet
        _unbreakable_btn.visible = false
    elif not threshold_met:
        # Show but disabled — motivate player to try more
        _unbreakable_btn.visible = true
        _unbreakable_btn.disabled = true
        _unbreakable_btn.text = "Невзламываемый? (ещё %d попыток)" % (
            _min_attempts - _attempt_count)
        _apply_button_style(_unbreakable_btn, L4_RED_DIM,
            Color(0.05, 0.02, 0.02, 0.5))
    else:
        # Threshold met — enable!
        _unbreakable_btn.visible = true
        _unbreakable_btn.disabled = false
        _unbreakable_btn.text = "НЕВЗЛАМЫВАЕМЫЙ 🔒"
        _apply_button_style(_unbreakable_btn, L4_SEAL_GOLD,
            Color(0.08, 0.07, 0.02, 0.9))
        # Pulse animation
        var tw: Tween = _unbreakable_btn.create_tween().set_loops()
        tw.tween_property(_unbreakable_btn, "modulate",
            Color(1.2, 1.1, 0.8, 1.0), 0.8)
        tw.tween_property(_unbreakable_btn, "modulate",
            Color(1.0, 1.0, 1.0, 1.0), 0.8)
```

### 6.4 Нажатие «НЕВЗЛАМЫВАЕМЫЙ» — два исхода

**Правильное утверждение (is_normal == true):**

```gdscript
func _on_unbreakable_pressed() -> void:
    if _active_keyring_is_normal:
        # CORRECT! Award seal
        _active_slot.set_sealed()
        _sealed_count += 1

        # Gold celebration
        _play_seal_animation()

        # Show message
        _show_hint("Печать Невозможности! Этот брелок невзламываем.", L4_SEAL_GOLD)

        # Save and advance
        _save_progress()
        _advance_to_next_keyring()
    else:
        # WRONG! Show counterexample
        var witness: Dictionary = _find_counterexample()
        _show_counterexample(witness)
```

**Неправильное утверждение (is_normal == false):**

```
Экран:
  "Ой! Попробуй эту пару:"
  g = r1, h = sh
  → r1 · sh · r3 = sv ← не в брелке!

  (Автоматически заполняет слоты контрпримером и выполняет манёвр)
```

```gdscript
## Find a counterexample (g, h) where ghg⁻¹ ∉ H for a non-normal subgroup
func _find_counterexample() -> Dictionary:
    var subgroup_set: Array[String] = _active_subgroup_elements
    for g_sym in _lockpick_sym_ids:
        for h_sym in subgroup_set:
            if h_sym == "e":
                continue
            var g_perm: Permutation = _room_state.get_perm_by_id(g_sym)
            var h_perm: Permutation = _room_state.get_perm_by_id(h_sym)
            var g_inv: Permutation = g_perm.inverse()
            var result: Permutation = g_perm.compose(h_perm).compose(g_inv)
            var result_sym: String = _room_state.find_sym_id_for_perm(result)
            if not subgroup_set.has(result_sym):
                return {"g": g_sym, "h": h_sym, "result": result_sym,
                        "g_inv": _room_state.find_sym_id_for_perm(g_inv)}
    return {}  # should not happen for non-normal
```

### 6.5 Покрытие h — Coverage Indicator

Под слотами показывается набор цветных точек, по одной на каждый h ∈ H (кроме e):

```
Покрытие h: [●✓] [●✓] [●·] [●·]
            r1    r2    sh    sv
```

- **●✓** (зелёная рамка) = хотя бы одна пара с этим h протестирована
- **●·** (серая) = ещё не протестирован

Это даёт игроку подсказку: «нужно попробовать и этот ключ тоже».

---

## 7. Data Model

### 7.1 Level JSON — секция layer_4

Layer 4 **не требует** отдельной конфигурации — все данные берутся из `layers.layer_3.subgroups[*].is_normal`. Однако добавляется опциональная секция для override:

```json
{
  "layers": {
    "layer_4": {
      "enabled": true,
      "title": "Взлом брелков",
      "instruction": "Проверьте, какие брелки можно взломать обходным манёвром",
      "difficulty": "MEDIUM",

      "auto_complete_trivial": true,

      "subgroup_filter": null,

      "tutorial_mode": false,

      "custom_thresholds": null
    }
  }
}
```

**Поля:**
- `enabled`: boolean — можно ли играть Layer 4 на этом уровне
- `difficulty`: "TRIVIAL" | "EASY" | "MEDIUM" | "HARD" | "SPECIAL" — из T103
- `auto_complete_trivial`: bool — авто-пропуск для групп простого порядка
- `subgroup_filter`: null | Array[int] — если задан, тестировать только subgroups с этими индексами (для S4, D6, D4×Z2)
- `tutorial_mode`: bool — для Level 3 (Z2) как tutorial нормальности
- `custom_thresholds`: null | Dictionary — override min_attempts и coverage rules

### 7.2 Runtime data — ConjugationCrackingManager

```gdscript
class_name ConjugationCrackingManager
extends RefCounted

## Data for one keyring under test
class KeyringTestData:
    var subgroup_index: int = 0
    var elements: Array[String] = []     # sym_ids
    var order: int = 0
    var is_normal: bool = false          # ground truth
    var status: String = "pending"       # "pending" | "active" | "cracked" | "sealed"
    var attempt_count: int = 0
    var tested_pairs: Array[Dictionary] = []  # [{g, h, result, in_H}]
    var tested_h_set: Dictionary = {}    # h_sym_id → true
    var cracking_witness: Dictionary = {} # {g, h, result} if cracked

signal keyring_cracked(keyring_index: int, witness: Dictionary)
signal keyring_sealed(keyring_index: int)
signal all_keyrings_tested()
signal conjugation_result(result: Dictionary)  # after each maneuver

var _room_state: RoomState = null
var _keyrings: Array[KeyringTestData] = []
var _active_keyring_idx: int = -1
var _cracked_count: int = 0
var _sealed_count: int = 0
var _total_testable: int = 0  # excludes {e} and G

## Setup from level_data and layer_3 subgroup info
func setup(level_data: Dictionary, room_state: RoomState) -> void:
    _room_state = room_state
    var l3_config: Dictionary = level_data.get("layers", {}).get("layer_3", {})
    var l4_config: Dictionary = level_data.get("layers", {}).get("layer_4", {})
    var subgroups: Array = l3_config.get("subgroups", [])
    var group_order: int = room_state.group_order
    var filter: Variant = l4_config.get("subgroup_filter", null)

    _keyrings.clear()
    var idx: int = 0
    for sg in subgroups:
        var order: int = sg.get("order", 0)
        var is_trivial: bool = sg.get("is_trivial", false)
        # Skip trivial ({e}) and full group
        if is_trivial or order == group_order:
            idx += 1
            continue
        # Apply filter if present
        if filter != null and not filter.has(idx):
            idx += 1
            continue

        var ktd := KeyringTestData.new()
        ktd.subgroup_index = idx
        ktd.elements = sg.get("elements", [])
        ktd.order = order
        ktd.is_normal = sg.get("is_normal", false)
        ktd.status = "pending"
        _keyrings.append(ktd)
        idx += 1

    _total_testable = _keyrings.size()
    if _total_testable > 0:
        _active_keyring_idx = 0
        _keyrings[0].status = "active"


## Execute conjugation maneuver: compute ghg⁻¹, check membership in H
func try_conjugation(g_sym_id: String, h_sym_id: String) -> Dictionary:
    var active: KeyringTestData = get_active_keyring()
    if active == null:
        return {"error": "no_active_keyring"}

    var g_perm: Permutation = _room_state.get_perm_by_id(g_sym_id)
    var h_perm: Permutation = _room_state.get_perm_by_id(h_sym_id)
    var g_inv: Permutation = g_perm.inverse()
    var result_perm: Permutation = g_perm.compose(h_perm).compose(g_inv)
    var result_sym_id: String = _room_state.find_sym_id_for_perm(result_perm)
    var in_H: bool = active.elements.has(result_sym_id)

    # Record attempt
    var pair: Dictionary = {
        "g": g_sym_id, "h": h_sym_id,
        "result": result_sym_id, "in_H": in_H
    }
    active.tested_pairs.append(pair)
    active.attempt_count += 1
    active.tested_h_set[h_sym_id] = true

    var result: Dictionary = {
        "g": g_sym_id, "h": h_sym_id,
        "g_inv": _room_state.find_sym_id_for_perm(g_inv),
        "result": result_sym_id,
        "result_perm": result_perm,
        "in_H": in_H,
        "attempt_count": active.attempt_count,
    }

    if not in_H:
        # CRACKED!
        active.status = "cracked"
        active.cracking_witness = pair
        _cracked_count += 1
        keyring_cracked.emit(_active_keyring_idx, pair)
    else:
        conjugation_result.emit(result)

    return result


## Claim current keyring is unbreakable
func claim_unbreakable() -> Dictionary:
    var active: KeyringTestData = get_active_keyring()
    if active == null:
        return {"success": false, "reason": "no_active_keyring"}

    if active.is_normal:
        # Correct claim!
        active.status = "sealed"
        _sealed_count += 1
        keyring_sealed.emit(_active_keyring_idx)
        return {"success": true, "correct": true}
    else:
        # Wrong claim — find counterexample
        var counter: Dictionary = _find_counterexample(active)
        return {"success": true, "correct": false, "counterexample": counter}


## Advance to next untested keyring
func advance_to_next_keyring() -> void:
    for i in range(_keyrings.size()):
        if _keyrings[i].status == "pending":
            _active_keyring_idx = i
            _keyrings[i].status = "active"
            return
    # All keyrings tested
    _active_keyring_idx = -1
    all_keyrings_tested.emit()


## Get active keyring data
func get_active_keyring() -> KeyringTestData:
    if _active_keyring_idx < 0 or _active_keyring_idx >= _keyrings.size():
        return null
    return _keyrings[_active_keyring_idx]


## Get lockpicks (G \ H) for active keyring
func get_lockpicks() -> Array[String]:
    var active: KeyringTestData = get_active_keyring()
    if active == null:
        return []
    var all_keys: Array[String] = _room_state.get_all_sym_ids()
    var result: Array[String] = []
    for k in all_keys:
        if not active.elements.has(k):
            result.append(k)
    return result


## Check threshold for Unbreakable button
func check_unbreakable_threshold() -> Dictionary:
    var active: KeyringTestData = get_active_keyring()
    if active == null:
        return {"met": false}

    var h_non_e: Array[String] = active.elements.filter(
        func(s): return s != "e")
    var lockpick_count: int = get_lockpicks().size()
    var total_pairs: int = h_non_e.size() * lockpick_count

    # min_attempts
    var min_attempts: int = maxi(10, ceili(total_pairs * 0.5))
    if total_pairs <= 6:
        min_attempts = total_pairs

    # coverage
    var coverage_count: int = 0
    for h_sym in h_non_e:
        if active.tested_h_set.has(h_sym):
            coverage_count += 1

    var attempts_met: bool = active.attempt_count >= min_attempts
    var coverage_met: bool = coverage_count == h_non_e.size()

    return {
        "met": attempts_met and coverage_met,
        "attempt_count": active.attempt_count,
        "min_attempts": min_attempts,
        "coverage_count": coverage_count,
        "coverage_total": h_non_e.size(),
        "total_pairs": total_pairs,
    }


## Progress info
func get_progress() -> Dictionary:
    return {
        "cracked": _cracked_count,
        "sealed": _sealed_count,
        "remaining": _total_testable - _cracked_count - _sealed_count,
        "total": _total_testable,
    }


func is_complete() -> bool:
    return (_cracked_count + _sealed_count) == _total_testable


## Find counterexample for wrong "unbreakable" claim
func _find_counterexample(ktd: KeyringTestData) -> Dictionary:
    for g_sym in get_lockpicks():
        for h_sym in ktd.elements:
            if h_sym == "e":
                continue
            var g_p: Permutation = _room_state.get_perm_by_id(g_sym)
            var h_p: Permutation = _room_state.get_perm_by_id(h_sym)
            var result_p: Permutation = g_p.compose(h_p).compose(g_p.inverse())
            var result_sym: String = _room_state.find_sym_id_for_perm(result_p)
            if not ktd.elements.has(result_sym):
                return {"g": g_sym, "h": h_sym, "result": result_sym}
    return {}
```

### 7.3 Save state

```gdscript
## Save format for GameManager.set_layer_progress(hall_id, 4, dict)
func save_state() -> Dictionary:
    var keyrings_data: Array = []
    for ktd in _keyrings:
        keyrings_data.append({
            "subgroup_index": ktd.subgroup_index,
            "status": ktd.status,
            "attempt_count": ktd.attempt_count,
            "tested_pairs": ktd.tested_pairs,
            "tested_h_set": ktd.tested_h_set.keys(),
            "cracking_witness": ktd.cracking_witness,
        })
    return {
        "status": "completed" if is_complete() else "in_progress",
        "cracked_count": _cracked_count,
        "sealed_count": _sealed_count,
        "total_testable": _total_testable,
        "active_keyring_idx": _active_keyring_idx,
        "keyrings": keyrings_data,
    }


## Restore from save
func restore_from_save(data: Dictionary) -> void:
    _cracked_count = data.get("cracked_count", 0)
    _sealed_count = data.get("sealed_count", 0)
    _active_keyring_idx = data.get("active_keyring_idx", 0)

    var keyrings_data: Array = data.get("keyrings", [])
    for kd in keyrings_data:
        var sg_idx: int = kd.get("subgroup_index", -1)
        for ktd in _keyrings:
            if ktd.subgroup_index == sg_idx:
                ktd.status = kd.get("status", "pending")
                ktd.attempt_count = kd.get("attempt_count", 0)
                ktd.tested_pairs = kd.get("tested_pairs", [])
                var h_set_arr: Array = kd.get("tested_h_set", [])
                for h in h_set_arr:
                    ktd.tested_h_set[h] = true
                ktd.cracking_witness = kd.get("cracking_witness", {})
                break
```

---

## 8. Расширение LayerModeController

### 8.1 Enum и поля

```gdscript
enum LayerMode {
    LAYER_1,
    LAYER_2_INVERSE,
    LAYER_3_SUBGROUPS,
    LAYER_4_NORMAL,          # ← НОВЫЙ
    ## Future:
    ## LAYER_5_QUOTIENT,
}

# Новые поля
var conjugation_mgr: ConjugationCrackingManager = null
var _cracking_panel = null         # ConjugationCrackingPanel (main UI)
var _maneuver_zone = null          # ManeuverZone (three-slot)
var _lockpick_panel = null         # LockpickPanel
```

### 8.2 Setup

```gdscript
func _setup_layer_4(level_data: Dictionary, level_scene) -> void:
    _room_state = level_scene._room_state

    # 1. Disable crystal dragging (read-only graph, used for animation)
    for crystal in level_scene.crystals.values():
        if crystal is CrystalNode:
            crystal.set_draggable(false)

    # 2. Reset crystals to identity
    var sm: ShuffleManager = level_scene._shuffle_mgr
    sm.current_arrangement = sm.identity_arrangement.duplicate()
    level_scene._swap_mgr.apply_arrangement_to_crystals()

    # 3. All rooms discovered
    for i in range(_room_state.group_order):
        _room_state.discover_room(i)

    # 4. Hide KeyBar (replaced by Keyring + Lockpick zones)
    if level_scene._key_bar:
        level_scene._key_bar.visible = false

    # 5. Hide target preview and action buttons
    _hide_target_preview(level_scene)
    _hide_action_buttons(level_scene)

    # 6. Init ConjugationCrackingManager
    conjugation_mgr = ConjugationCrackingManager.new()
    conjugation_mgr.setup(level_data, _room_state)

    # 7. Connect signals
    conjugation_mgr.keyring_cracked.connect(_on_keyring_cracked)
    conjugation_mgr.keyring_sealed.connect(_on_keyring_sealed)
    conjugation_mgr.all_keyrings_tested.connect(_on_all_keyrings_tested)
    conjugation_mgr.conjugation_result.connect(_on_conjugation_result)

    # 8. Build UI panels
    _build_layer_4_ui(level_scene)

    # 9. Red theme
    _apply_layer_4_theme(level_scene)

    # 10. Update counter
    _update_layer_4_counter()

    # 11. Room map stays visible
    if level_scene._room_map:
        level_scene._room_map.home_visible = true
        level_scene._room_map.queue_redraw()

    # 12. Check for auto-complete (trivial / prime-order groups)
    var l4_config: Dictionary = level_data.get("layers", {}).get("layer_4", {})
    if l4_config.get("auto_complete_trivial", true):
        if conjugation_mgr.get_progress()["total"] == 0:
            _auto_complete_layer_4(level_scene)
            return

    # 13. Restore from save
    var saved: Dictionary = GameManager.get_layer_progress(_hall_id, 4)
    if saved.get("status") == "in_progress":
        conjugation_mgr.restore_from_save(saved)
        _restore_layer_4_ui(saved)

    # 14. Save initial state
    _save_layer_4_progress()
```

### 8.3 Тема (красная)

```gdscript
func _apply_layer_4_theme(level_scene) -> void:
    var hud = level_scene.hud_layer

    var lvl_label = hud.get_node_or_null("LevelNumberLabel")
    if lvl_label:
        lvl_label.text += "  ·  Слой 4: Взлом"
        lvl_label.add_theme_color_override("font_color", L4_RED_DIM)

    var map_frame = hud.get_node_or_null("MapFrame")
    if map_frame:
        var map_title = map_frame.get_node_or_null("MapFrameTitle")
        if map_title:
            map_title.text = "Карта комнат — Взлом"
            map_title.add_theme_color_override("font_color", L4_RED_DIM)

    var counter = hud.get_node_or_null("CounterLabel")
    if counter:
        counter.add_theme_color_override("font_color", L4_RED_DIM)
```

### 8.4 Signal handlers

```gdscript
func _on_keyring_cracked(keyring_idx: int, witness: Dictionary) -> void:
    if _level_scene == null:
        return

    # Update slot visual
    if _cracking_panel:
        _cracking_panel.set_slot_cracked(keyring_idx, witness)

    # Play crack feedback
    if _level_scene.feedback_fx:
        play_crack_feedback(_level_scene.crystals, _level_scene.edges)

    # Show hint
    _show_hint("Брелок взломан! Слабое место: g=%s, h=%s → %s ∉ H" % [
        witness["g"], witness["h"], witness["result"]
    ], L4_RED_CRACK)

    # Update counter and save
    _update_layer_4_counter()
    _save_layer_4_progress()

    # Auto-advance to next keyring after delay
    _level_scene.get_tree().create_timer(2.0).timeout.connect(
        _advance_to_next_keyring_with_ui)


func _on_keyring_sealed(keyring_idx: int) -> void:
    if _level_scene == null:
        return

    # Update slot visual
    if _cracking_panel:
        _cracking_panel.set_slot_sealed(keyring_idx)

    # Play seal animation (gold celebration)
    if _level_scene.feedback_fx:
        _level_scene.feedback_fx.play_completion_feedback(
            _level_scene.crystals.values(), _level_scene.edges)

    # Show hint
    _show_hint("Печать Невозможности! Невзламываемый брелок.", L4_SEAL_GOLD)

    # Update counter and save
    _update_layer_4_counter()
    _save_layer_4_progress()

    # Auto-advance to next keyring after delay
    _level_scene.get_tree().create_timer(2.0).timeout.connect(
        _advance_to_next_keyring_with_ui)


func _on_all_keyrings_tested() -> void:
    _on_layer_4_completed()


func _on_conjugation_result(result: Dictionary) -> void:
    # ghg⁻¹ ∈ H — update coverage display
    if _maneuver_zone:
        _maneuver_zone.update_coverage(conjugation_mgr.get_active_keyring())
        _maneuver_zone.update_unbreakable_button(
            conjugation_mgr.check_unbreakable_threshold())
    _save_layer_4_progress()
```

### 8.5 Counter

```gdscript
func _update_layer_4_counter() -> void:
    if _level_scene == null or conjugation_mgr == null:
        return
    var cl = _level_scene.hud_layer.get_node_or_null("CounterLabel")
    if cl:
        var p: Dictionary = conjugation_mgr.get_progress()
        cl.text = "Взломано: %d · Запечатано: %d · Осталось: %d" % [
            p["cracked"], p["sealed"], p["remaining"]]
```

### 8.6 Completion summary

```gdscript
func _on_layer_4_completed() -> void:
    if _level_scene == null:
        return

    # Save as completed
    _save_layer_4_progress()

    # Play completion feedback
    if _level_scene.feedback_fx:
        _level_scene.feedback_fx.play_completion_feedback(
            _level_scene.crystals.values(), _level_scene.edges)

    # Update HUD
    var cl = _level_scene.hud_layer.get_node_or_null("CounterLabel")
    if cl:
        cl.text = "Все брелки проверены!"
        cl.add_theme_color_override("font_color", L4_RED)

    var hl = _level_scene.hud_layer.get_node_or_null("HintLabel")
    if hl:
        hl.text = "Нормальные подгруппы — ключ к факторгруппам"
        hl.add_theme_color_override("font_color", L4_SEAL_GOLD)

    # Show summary after delay
    _level_scene.get_tree().create_timer(1.5).timeout.connect(
        _show_layer_4_summary)

    # Emit
    layer_completed.emit(4, _hall_id)


func _show_layer_4_summary() -> void:
    if _level_scene == null:
        return

    var hud: CanvasLayer = _level_scene.hud_layer
    var panel: Panel = Panel.new()
    panel.name = "Layer4SummaryPanel"

    # ... (same pattern as Layer 2/3 summary panels)

    # Content: list all keyrings with their results
    # ✗ ВЗЛОМАН: {e, sh} — r1·sh·r3 = sv ∉ H
    # 🔒 ЗАПЕЧАТАН: {e, r1, r2, r3} — невзламываемый

    # ... red/gold theme, return-to-map + dismiss buttons ...
    # (follows exact same pattern as _show_layer_3_summary)
```

---

## 9. Edge Cases

### 9.1 TRIVIAL — Группы простого порядка (Z₂, Z₃, Z₅, Z₇)

**Проблема**: Единственные подгруппы — {e} и G. Обе тривиально нормальные. Нечего тестировать.

**Решение**: Auto-complete с пояснением.

```gdscript
func _auto_complete_layer_4(level_scene) -> void:
    # No testable keyrings — auto-complete
    GameManager.set_layer_progress(_hall_id, 4, {
        "status": "completed",
        "cracked_count": 0,
        "sealed_count": 0,
        "total_testable": 0,
        "auto_completed": true,
        "reason": "trivial_subgroups_only",
    })

    var hl = level_scene.hud_layer.get_node_or_null("HintLabel")
    if hl:
        hl.text = "Группа простого порядка — все подгруппы тривиальны"
        hl.add_theme_color_override("font_color", L4_RED_DIM)

    # Show auto-complete summary after short delay
    level_scene.get_tree().create_timer(1.0).timeout.connect(
        _show_trivial_summary)

    layer_completed.emit(4, _hall_id)
```

**Уровни**: 1, 2, 3, 7, 8, 10, 16

### 9.2 EASY — Абелевы группы (Z₄, V₄, Z₆, Z₈)

**Свойство**: Все подгруппы нормальны. Игрок всегда получает ghg⁻¹ ∈ H.

**Решение**: Играются нормально, но после первого теста показывается подсказка:

```
"Подсказка: В абелевых группах g·h·g⁻¹ = h всегда.
 Все брелки невзламываемы!"
```

Игрок может либо продолжить тестировать (для обучения), либо использовать кнопку «НЕВЗЛАМЫВАЕМЫЙ» на каждом.

**Дополнительная оптимизация**: Для abelian groups, threshold снижен до `min(3, |H|-1)` попыток (вместо 10), чтобы не томить игрока.

```gdscript
func _is_abelian_group() -> bool:
    # Check if all pairs commute (precomputed in level_data or runtime check)
    var all_syms: Array = _room_state.get_all_sym_ids()
    for a in all_syms:
        for b in all_syms:
            var pa: Permutation = _room_state.get_perm_by_id(a)
            var pb: Permutation = _room_state.get_perm_by_id(b)
            if not pa.compose(pb).equals(pb.compose(pa)):
                return false
    return true
```

**Уровни**: 4, 6, 11, 17

### 9.3 SPECIAL — Q₈ (все подгруппы нормальны, но группа неабелева)

**Уникальность**: Q₈ — **неабелева** (i·j ≠ j·i), но ВСЕ подгруппы нормальны!

**Gameplay flow**:
1. Игрок знает из Layer 3, что Q₈ неабелева (ключи не коммутируют)
2. Ожидает найти ненормальные подгруппы
3. Тестирует... все нормальны!
4. На каждом брелке жмёт «НЕВЗЛАМЫВАЕМЫЙ»
5. После последнего — **особое сообщение**:

```
┌──────────────────────────────────────────────┐
│  🏆 КВАТЕРНИОННЫЙ ПАРАДОКС!                 │
│                                              │
│  Несмотря на некоммутативность,              │
│  ВСЕ брелки невзламываемы.                   │
│                                              │
│  Такие группы называются                     │
│  «гамильтоновыми группами».                  │
│                                              │
│  Награда: Парадокс Кватернионов 🎭            │
└──────────────────────────────────────────────┘
```

**Реализация**: Проверка после завершения: если `sealed == total && !abelian`:

```gdscript
func _check_quaternion_paradox() -> bool:
    var p: Dictionary = conjugation_mgr.get_progress()
    return (p["sealed"] == p["total"] and
            p["cracked"] == 0 and
            not _is_abelian_group() and
            p["total"] > 0)
```

**Уровень**: 21

### 9.4 HARD — S₄ (30 подгрупп), D₆ (16), D₄×Z₂ (33)

**Проблема**: Слишком много подгрупп для комфортного тестирования.

**Решение**: Фильтрация (`subgroup_filter` в layer_4 config).

| Уровень | Группа | Всего SG | Тестируемых | Стратегия |
|---------|--------|----------|-------------|-----------|
| 13      | S4     | 30       | 8           | A4, 3×D4, 4×S3 (макс. собственные) |
| 20      | D6     | 16       | 8           | Z2, Z3, Z6, 3×D3, Z2×Z3 |
| 24      | D4×Z2  | 33       | 8           | Center, 4×maximal, 3×interesting |

**Config пример для S4**:
```json
{
  "layers": {
    "layer_4": {
      "enabled": true,
      "difficulty": "HARD",
      "subgroup_filter": [1, 5, 6, 7, 8, 9, 10, 11],
      "boss_fight": true
    }
  }
}
```

### 9.5 Abelian с единственной нетривиальной подгруппой

**Пример**: Z4 имеет только {e, r2} как нетривиальную собственную подгруппу.

**Gameplay**: Один брелок → один тест → НЕВЗЛАМЫВАЕМЫЙ → done.

Быстро, но педагогически полезно: «Вот как работает проверка нормальности.»

### 9.6 Выбор порядка тестирования

**Дефолт**: Брелки тестируются в порядке их порядка (order ascending). Мотивация: маленькие подгруппы проще для понимания.

**Свободный выбор**: Игрок может tap на любой PENDING слот, чтобы переключиться. Порядок не фиксирован.

```gdscript
func select_keyring(index: int) -> void:
    if index < 0 or index >= _keyrings.size():
        return
    if _keyrings[index].status != "pending":
        return  # already tested
    # Deactivate current
    var active: KeyringTestData = get_active_keyring()
    if active != null and active.status == "active":
        active.status = "pending"
    # Activate selected
    _active_keyring_idx = index
    _keyrings[index].status = "active"
```

---

## 10. Data Flow

```
┌─ Load Level JSON ──────────────────────────────┐
│ Extract layers.layer_3.subgroups[*]             │
│ Filter: is_trivial=false, order<|G|             │
│ Extract is_normal flags                         │
└─────────────────────────────────────────────┬───┘
                                               │
                          ┌────────────────────▼────────┐
                          │ ConjugationCrackingManager   │
                          │ ├─ _keyrings[]              │
                          │ ├─ _active_keyring_idx      │
                          │ ├─ try_conjugation(g,h)     │
                          │ ├─ claim_unbreakable()      │
                          │ └─ save_state()/restore()   │
                          └────────────────────┬────────┘
                                               │
     ┌────────────────┬────────────────────────┼──────────────┐
     │                │                        │              │
     ▼                ▼                        ▼              ▼
KeyringList      LockpickPanel          ManeuverZone     CrystalView
(left zone)      (center-left)          (bottom)         (right)
     │                │                        │              │
     │ tap slot       │ tap lockpick           │              │
     │ → select       │ → fill SlotG           │              │
     │   keyring      │ → auto-fill SlotGInv   │              │
     │                │                        │              │
     │ tap h-key ─────│───────────→ fill SlotH │              │
     │                │                        │              │
     │                │          ┌──────────────┘              │
     │                │          │ ВЫПОЛНИТЬ                   │
     │                │          │ pressed                     │
     │                │          ▼                             │
     │                │   ConjugationCrackingManager           │
     │                │   .try_conjugation(g, h)               │
     │                │          │                             │
     │                │          ├── ghg⁻¹ ∈ H                │
     │                │          │   → green glow ─────────────┤
     │                │          │   → update coverage         │
     │                │          │   → check threshold         │
     │                │          │                             │
     │                │          ├── ghg⁻¹ ∉ H                │
     │                │          │   → RED CRACK ──────────────┤
     │                │          │   → slot → CRACKED          │
     │                │          │   → advance_to_next         │
     │                │          │                             │
     │                │          └── НЕВЗЛАМЫВАЕМЫЙ pressed    │
     │                │              → claim_unbreakable()     │
     │                │              → correct → SEALED        │
     │                │              → wrong → counterexample  │
     │                │                                        │
     └────────────────┴───────────┬────────────────────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────┐
                    │ All keyrings tested?    │
                    │ cracked + sealed = total │
                    └─────────────┬───────────┘
                                  │ YES
                                  ▼
                    ┌─────────────────────────┐
                    │ LAYER 4 COMPLETED!      │
                    │ Summary:                │
                    │ - Взломано: N            │
                    │ - Запечатано: M          │
                    │                         │
                    │ [ВЕРНУТЬСЯ НА КАРТУ]     │
                    │ [Продолжить играть]      │
                    └─────────────────────────┘
```

---

## 11. Новые файлы и изменения

### 11.1 Новые файлы

| Файл | Назначение | Строк (оценка) |
|------|-----------|----------------|
| `src/core/conjugation_cracking_manager.gd` | Core logic: conjugation tests, thresholds, save/restore | ~280 |
| `src/ui/crackable_keyring_slot.gd` | Один слот брелка (4 состояния) | ~120 |
| `src/ui/lockpick_panel.gd` | Панель отмычек (G\H) | ~100 |
| `src/ui/maneuver_zone.gd` | Три слота + кнопки + coverage | ~200 |
| `src/ui/maneuver_slot.gd` | Один слот манёвра (g/h/g⁻¹) | ~60 |

### 11.2 Изменения в существующих файлах

| Файл | Что меняется |
|------|-------------|
| `layer_mode_controller.gd` | + LAYER_4_NORMAL, + _setup_layer_4(), + L4_RED constants, + signal handlers, + summary, + cleanup |
| `level_scene.gd` | + Layer 4 mode delegation (minimal, same pattern as L2/L3) |
| `map_scene.gd` | + красный индикатор на нодах для Layer 4 |
| `hall_progression_engine.gd` | + Layer 4 threshold (already has pattern) |
| `data/levels/*/level_*.json` | + секция layers.layer_4 (24 файла) |
| `feedback_fx.gd` | + play_crack_particles(), play_crack_feedback() |

### 11.3 НЕ меняется

- `permutation.gd` — compose(), inverse(), is_identity() уже есть
- `subgroup_checker.gd` — is_normal() используем для backend validation, без изменений
- `keyring_assembly_manager.gd` — Layer 3, не затрагивается
- `inverse_pair_manager.gd` — Layer 2, не затрагивается
- `graph_engine.gd` — не затрагивается

---

## 12. Порядок реализации

### Phase 1: Core Logic (2-3 дня)

1. **`ConjugationCrackingManager`** — pure logic, полностью тестируемый
   - setup(), try_conjugation(), claim_unbreakable()
   - Threshold checks, counterexample finder
   - save_state(), restore_from_save()

2. **Unit tests** — каждый метод manager'а
   - Z4 (all normal), S3 (3 crackable, 1 normal), D4 (mix)
   - Q8 (all normal despite non-abelian)
   - Threshold edge cases

### Phase 2: UI (3-4 дня)

3. **`CrackableKeyringSlot`** — 4 states visual
4. **`LockpickPanel`** — G\H key display
5. **`ManeuverSlot`** + **`ManeuverZone`** — three-slot + execute + coverage
6. **Layer 4 section in `LayerModeController`** — setup, theme, signals

### Phase 3: Animation & Polish (2-3 дня)

7. **Crystal conjugation animation** — 3-phase tween sequence
8. **Crack feedback** — red flash, shake, particles
9. **Seal feedback** — gold glow, celebration
10. **Unbreakable button** — pulse, threshold display, counterexample
11. **Summary panel** — Layer 4 completion (red/gold theme)

### Phase 4: Content & Testing (2-3 дня)

12. **Level JSON updates** — add layer_4 sections for all 24 levels
13. **Subgroup filters** — for S4, D6, D4×Z2
14. **Edge case testing** — trivial, abelian, Q8, boss fights
15. **Integration testing** — full play-through Layer 4

---

## 13. Открытые вопросы для boss

| # | Вопрос | Рекомендация | Влияние |
|---|--------|-------------|---------|
| 1 | **Auto-complete trivial?** Пропускать Layer 4 для Z₂/Z₃/Z₅/Z₇? | **Да** — показать пояснение и пропустить | UX |
| 2 | **Свободный порядок?** Игрок выбирает, какой брелок тестировать? | **Да** — tap на PENDING слот | UX flexibility |
| 3 | **Фильтрация S₄/D₆/D₄×Z₂**: тестировать 8 «интересных» или все? | **8 интересных** — подробности в T103 | Scope |
| 4 | **Abelian hint**: показывать ли подсказку «в абелевых всё нормально»? | **Да**, после первого теста | Pedagogy |
| 5 | **Q₈ achievement**: отдельное достижение «Кватернионный парадокс»? | **Да** — это педагогический момент | Narrative |
| 6 | **Counterexample auto-play**: при неправильном «невзламываемый», автоматически проигрывать контрпример? | **Да** — заполнить слоты и выполнить | UX clarity |
| 7 | **Map icon for Layer 4**: красная точка с ✗/🔒? | **Да** — аналогично Layer 2 (зелёная) и Layer 3 (золотая) | Map consistency |

---

*Конец документа.*
