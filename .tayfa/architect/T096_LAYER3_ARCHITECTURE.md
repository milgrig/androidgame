# T096: Layer 3 — Архитектура UI и механики сборки брелков

> **Автор**: architect | **Дата**: 2026-02-27
> **Задача**: Спроектировать split-screen layout, UI слотов, drag-and-drop, валидацию и data model для Слоя 3
> **Зависимости**: T095 (каталог подгрупп — DONE)

---

## 0. Расхождение T096 vs redesign.md — РЕШЕНИЕ

T096 описывает механику **«сборка брелков из ключей»** (drag keys into keyring slots).
redesign.md секция 3 описывает **«зона композиции»** (drag two keys → see result).

**Решение**: T096 — актуальная спецификация от product owner. redesign.md описывает *педагогическую цель* (понять замкнутость), но T096 конкретизирует *UX-механику* (собрать подгруппы). Авто-валидация проверяет замкнутость за игрока. Следуем T096.

---

## 1. Split-screen layout

### 1.1 Общая схема

```
┌──────────────────────────────────────────────────────────┐
│  LevelNumberLabel: "Зал 5 · Слой 3: Группы"    [gold]   │
├────────────────────┬─────────────────────────────────────┤
│                    │                                     │
│  KEYRING ZONE      │  CRYSTAL + ROOM MAP ZONE            │
│  (30% ширины)      │  (70% ширины)                       │
│                    │                                     │
│  ┌──────────┐      │  ┌─────────────────────────────┐    │
│  │ Брелок 1 │ ✓    │  │                             │    │
│  │ {e,r1,r2}│      │  │     Кристаллы + рёбра       │    │
│  └──────────┘      │  │     (read-only, как L2)      │    │
│  ┌──────────┐      │  │                             │    │
│  │ Брелок 2 │ ←    │  │                             │    │
│  │ {  ?  ?  }│      │  └─────────────────────────────┘    │
│  └──────────┘      │  ┌─────────────────────────────┐    │
│  ┌──────────┐      │  │     Карта комнат             │    │
│  │ Брелок 3 │      │  │     (room_map_panel)         │    │
│  │ (пусто)  │      │  │                             │    │
│  └──────────┘      │  └─────────────────────────────┘    │
│        ...         │                                     │
├────────────────────┴─────────────────────────────────────┤
│  KEY BAR — все ключи (источник для drag-копирования)     │
│  [e] [r1] [r2] [r3] [v] [h] [d1] [d2]                   │
│  Брелки: 1/5          Счётчик прогресса          [gold]  │
└──────────────────────────────────────────────────────────┘
```

### 1.2 Размеры и адаптивность

```gdscript
const L3_KEYRING_ZONE_RATIO := 0.30    # 30% ширины экрана
const L3_CRYSTAL_ZONE_RATIO := 0.70    # 70% ширины экрана
const L3_KEYRING_SLOT_HEIGHT := 80     # px, базовая высота одного слота
const L3_KEYRING_SLOT_MIN_H := 50      # px, минимум при >8 слотов
const L3_MAX_VISIBLE_SLOTS := 8        # видно без скролла
```

**Адаптивность по количеству брелков:**

| Брелков | Высота слота | Скролл | Примеры уровней |
|---------|-------------|--------|-----------------|
| 2-5     | 80 px       | Нет    | Z2, Z3, Z4, Z5, Z7 |
| 6-8     | 65 px       | Нет    | S3, D5, Z6, Z8 |
| 9-10    | 55 px       | Нет    | D4, A4 |
| 11+     | 50 px       | ScrollContainer | Q8(12), D6(10*), S4(10*) |

\* — с фильтрацией по рекомендации T095

### 1.3 Godot-реализация

Зона брелков — **новый UI-узел** `KeyringPanel` (VBoxContainer внутри ScrollContainer), добавляемый программно в `_setup_layer_3()`. Crystal zone и room map **не перестраиваются** — только сжимаются.

```
HUD CanvasLayer
├── LevelNumberLabel
├── KeyringFrame (Panel)              ← НОВЫЙ
│   ├── KeyringFrameTitle (Label): "Брелки"
│   ├── ScrollContainer
│   │   └── KeyringList (VBoxContainer)
│   │       ├── KeyringSlot_0
│   │       ├── KeyringSlot_1
│   │       └── ...
│   └── ProgressLabel: "Найдено: 2/10"
├── CrystalFrame (Panel)             ← существует, уменьшается
├── MapFrame (Panel)                 ← существует
├── KeyBarFrame (Panel)              ← существует
│   └── KeyBar
├── CounterLabel
└── HintLabel
```

---

## 2. UI слотов брелков (KeyringSlot)

### 2.1 Три состояния

```
EMPTY (пусто)               FILLING (активный)            LOCKED (найден)
┌─ ─ ─ ─ ─ ─ ─ ─ ┐        ┌────────────────────┐        ┌════════════════════┐
│                  │        │ ● ● ·              │        ║ ● ● ●        ✓    ║
│   Брелок #3      │        │ Брелок #2    ←     │        ║ Брелок #1    🔒   ║
│   (перетащите    │        │ 2 ключа             │        ║ {e, r1, r2}        ║
│    ключи сюда)   │        │                    │        ║ Порядок: 3         ║
└─ ─ ─ ─ ─ ─ ─ ─ ┘        └────────────────────┘        └════════════════════┘
  Пунктирная рамка           Тонкая золотая рамка          Толстая золотая + glow
  Серый текст                Золотой текст + стрелка ←      Золотое свечение + 🔒
```

### 2.2 Визуальные константы

```gdscript
const L3_GOLD := Color(0.95, 0.80, 0.20, 1.0)
const L3_GOLD_DIM := Color(0.70, 0.60, 0.15, 0.7)
const L3_GOLD_BG := Color(0.06, 0.05, 0.02, 0.8)
const L3_GOLD_BORDER := Color(0.55, 0.45, 0.10, 0.7)
const L3_GOLD_GLOW := Color(1.0, 0.90, 0.30, 0.9)
const L3_LOCKED_BG := Color(0.08, 0.07, 0.02, 0.95)
```

### 2.3 Содержимое слота

Ключи внутри брелка — **цветные точки** (circles), цвет берётся из `RoomState.colors[key_idx]`. Консистентно с KeyBar и RoomMapPanel.

```
┌──────────────────────────┐
│ ● ● ●                    │   ● = добавленный ключ (цвет комнаты)
│ Брелок #2    3 ключа     │   Пустых заполнителей НЕТ — игрок
└──────────────────────────┘   не знает размер подгруппы заранее
```

### 2.4 Тривиальные vs нетривиальные

- **{e}** и **G** — **включаются** (требование T096)
- {e}: один тусклый кружок, подпись «Пустой брелок»
- G: все ключи, подпись «Полный набор»
- **Тривиальные**: бледнее (alpha 0.6), **нетривиальные**: яркие

### 2.5 API класса KeyringSlot

```gdscript
class_name KeyringSlot
extends PanelContainer

enum State { EMPTY, FILLING, LOCKED }

var slot_index: int = 0
var state: State = State.EMPTY
var keys: Array[String] = []          # sym_ids ключей в этом брелке
var is_trivial: bool = false

signal key_added(slot_index: int, sym_id: String)
signal key_removed(slot_index: int, sym_id: String)

func add_key(sym_id: String) -> void
func remove_key(sym_id: String) -> void
func lock() -> void                   # → LOCKED
func reset() -> void                  # Очистить (только для FILLING)
func get_key_set() -> Array[String]
func _can_drop_data(at_position, data) -> bool   # Godot DnD
func _drop_data(at_position, data) -> void
```

---

## 3. Drag-and-drop механика

### 3.1 Источник: KeyBar (копирование)

При drag ключа из KeyBar создаётся **копия** (drag preview), оригинал остаётся.

```gdscript
# В KeyBar — новый метод для Layer 3:
func _get_drag_data(at_position) -> Variant:
    if not _drag_copy_mode:
        return null  # Layer 1-2: drag не используется в KeyBar
    var key_idx := _get_key_at_position(at_position)
    if key_idx < 0:
        return null
    var sym_id := _room_state.perm_ids[key_idx]
    var preview := _create_drag_preview(key_idx)
    set_drag_preview(preview)
    return {"type": "key_copy", "sym_id": sym_id, "key_idx": key_idx}
```

### 3.2 Цель: активный KeyringSlot

Только **один слот активен** — первый с state == FILLING (или первый EMPTY). Выделен стрелкой `←`.

```gdscript
# В KeyringSlot:
func _can_drop_data(_pos, data) -> bool:
    if state == State.LOCKED:
        return false
    if not data is Dictionary or data.get("type") != "key_copy":
        return false
    if keys.has(data["sym_id"]):
        return false  # дубликат ключа
    return true

func _drop_data(_pos, data) -> void:
    add_key(data["sym_id"])
    key_added.emit(slot_index, data["sym_id"])
```

### 3.3 Удаление ключа из брелка

1. **Tap** на ключ-точку внутри слота → ключ убирается (только FILLING)
2. **Drag out** — перетащить точку за пределы слота

### 3.4 Альтернативный ввод: tap-to-add (Android)

Для мобильных: tap ключ в KeyBar → добавляется в активный слот. Tap ключ-точку в слоте → убирается. Реализуется через `KeyBar.key_tapped` сигнал.

```gdscript
# В LevelScene, Layer 3 handler:
func _on_key_bar_key_pressed(key_idx: int) -> void:
    if _current_layer == 3:
        var sym_id := _room_state.perm_ids[key_idx]
        _layer_controller.on_key_tapped(sym_id)
        return
    # ... existing Layer 1/2 logic
```

---

## 4. Система валидации и feedback

### 4.1 Алгоритм авто-валидации

После каждого `key_added` / `key_removed`:

```gdscript
func _validate_current_slot(slot: KeyringSlot) -> void:
    var sym_ids: Array[String] = slot.get_key_set()
    if sym_ids.is_empty():
        return

    # sym_ids → Array[Permutation]
    var perms: Array[Permutation] = []
    for sid in sym_ids:
        perms.append(_room_state.get_perm_by_id(sid))

    # 1. Содержит identity?
    var has_identity := false
    for p in perms:
        if p.is_identity():
            has_identity = true
            break
    if not has_identity:
        return

    # 2. Замкнутость: ∀a,b ∈ set: a∘b ∈ set
    for a in perms:
        for b in perms:
            var ab := a.compose(b)
            var found := false
            for c in perms:
                if c.equals(ab):
                    found = true
                    break
            if not found:
                return

    # 3. Обратные: ∀a: a⁻¹ ∈ set
    for a in perms:
        var a_inv := a.inverse()
        var found := false
        for c in perms:
            if c.equals(a_inv):
                found = true
                break
        if not found:
            return

    # ✓ Это подгруппа! Новая или дубликат?
    var sig := SubgroupChecker._subgroup_signature(perms)
    if _found_signatures.has(sig):
        _show_duplicate_feedback(slot)
        return

    # НОВАЯ подгруппа!
    _found_signatures.append(sig)
    slot.lock()
    _on_subgroup_found(slot, perms)
```

### 4.2 Три типа feedback

| Ситуация | Визуал | Звук | Действие |
|----------|--------|------|----------|
| **Подгруппа найдена** | Золотое свечение на слоте, пульсация ключей | Мелодичный аккорд ↑ | Слот → LOCKED, next slot, counter++ |
| **Дубликат** | Оранжевый flash 1×, hint: «Этот брелок уже найден» | Мягкий тон | Ключи остаются, можно изменить |
| **Не подгруппа** | Ничего | Ничего | — |

### 4.3 Подсказки (Эхо)

Если **15+ действий** без нахождения подгруппы:
- **Шёпот**: «Попробуйте начать с одного ключа и его обратного»
- **Голос**: «Подгруппа порядка N ещё не найдена»
- **Видение**: Один ключ из ненайденной подгруппы подсвечивается золотым

---

## 5. Data model

### 5.1 Level JSON — секция layer_3

```json
{
  "layers": {
    "layer_3": {
      "title": "Группы — брелки",
      "instruction": "Соберите все брелки — наборы ключей, образующие группу",
      "subgroup_count": 10,
      "subgroups": [
        {
          "elements": ["e"],
          "order": 1,
          "is_trivial": true,
          "is_normal": true,
          "label": "Пустой брелок"
        },
        {
          "elements": ["e", "r2"],
          "order": 2,
          "is_trivial": false,
          "is_normal": true,
          "label": null
        }
      ],
      "filtered": false
    }
  }
}
```

Для проблемных уровней (13, 20, 24):

```json
{
  "layers": {
    "layer_3": {
      "subgroup_count": 10,
      "filtered": true,
      "full_subgroup_count": 30,
      "filter_strategy": "pedagogical_top10"
    }
  }
}
```

### 5.2 Save state

```gdscript
# GameManager.set_layer_progress(hall_id, 3, dict)
{
    "status": "in_progress",       # или "completed"
    "found_subgroups": [           # сигнатуры найденных
        ["e"],
        ["e", "r1", "r2"],
    ],
    "found_count": 2,
    "total_count": 10,
    "active_slot_keys": ["e", "r1"],  # текущий слот (для resume)
}
```

### 5.3 KeyringAssemblyManager (новый)

Аналог `InversePairManager` для Слоя 2.

```gdscript
class_name KeyringAssemblyManager
extends RefCounted

signal subgroup_found(slot_index: int, elements: Array[String])
signal duplicate_subgroup(slot_index: int)
signal all_subgroups_found()

var _room_state: RoomState = null
var _target_subgroups: Array[Dictionary] = []
var _found_signatures: Array[String] = []
var _total_count: int = 0
var _active_slot_index: int = 0

func setup(level_data: Dictionary, layer_config: Dictionary) -> void
func add_key_to_active(sym_id: String) -> void
func remove_key_from_active(sym_id: String) -> void
func validate_current() -> Dictionary  # {is_subgroup, is_duplicate, is_new}
func get_progress() -> Dictionary      # {found, total}
func is_complete() -> bool
func get_found_subgroups() -> Array[Array]
func restore_from_save(save_data: Dictionary) -> void
```

### 5.4 Расширение LayerModeController

```gdscript
enum LayerMode {
    LAYER_1,
    LAYER_2_INVERSE,
    LAYER_3_GROUP,         # ← НОВЫЙ
}

# Новые поля
var keyring_assembly_mgr: KeyringAssemblyManager = null
var _keyring_panel = null

# Новые константы
const L3_GOLD := Color(0.95, 0.80, 0.20, 1.0)
const L3_GOLD_DIM := Color(0.70, 0.60, 0.15, 0.7)
const L3_GOLD_BG := Color(0.06, 0.05, 0.02, 0.8)

func _setup_layer_3(level_data: Dictionary, level_scene) -> void:
    _room_state = level_scene._room_state

    # 1. Disable crystal dragging (read-only)
    for crystal in level_scene.crystals.values():
        if crystal is CrystalNode:
            crystal.set_draggable(false)

    # 2. Reset to identity arrangement
    var sm := level_scene._shuffle_mgr
    sm.current_arrangement = sm.identity_arrangement.duplicate()
    level_scene._swap_mgr.apply_arrangement_to_crystals()

    # 3. All rooms discovered
    for i in range(_room_state.group_order):
        _room_state.discover_room(i)

    # 4. KeyBar: show all keys, enable drag-copy mode
    if level_scene._key_bar:
        level_scene._key_bar.home_visible = true
        level_scene._key_bar.rebuild(_room_state)
        level_scene._key_bar.enable_drag_copy_mode(true)

    # 5. Hide target preview / action buttons
    _hide_target_preview(level_scene)
    _hide_action_buttons(level_scene)

    # 6. Init KeyringAssemblyManager
    var cfg := level_data.get("layers", {}).get("layer_3", {})
    keyring_assembly_mgr = KeyringAssemblyManager.new()
    keyring_assembly_mgr.setup(level_data, cfg)

    # 7. Connect signals
    keyring_assembly_mgr.subgroup_found.connect(_on_subgroup_found)
    keyring_assembly_mgr.duplicate_subgroup.connect(_on_duplicate_subgroup)
    keyring_assembly_mgr.all_subgroups_found.connect(_on_all_subgroups_found)

    # 8. Build KeyringPanel UI
    _build_keyring_panel(level_scene, cfg)

    # 9. Gold theme
    _apply_layer_3_theme(level_scene)

    # 10. Counter
    _update_layer_3_counter()

    # 11. Resize crystal zone
    _resize_crystal_zone(level_scene, L3_KEYRING_ZONE_RATIO)

    # 12. Restore from save
    var saved := GameManager.get_layer_progress(_hall_id, 3)
    if saved.get("status") == "in_progress":
        keyring_assembly_mgr.restore_from_save(saved)
        _restore_keyring_ui(saved)

    # 13. Save initial state
    GameManager.set_layer_progress(_hall_id, 3, {"status": "in_progress"})
```

---

## 6. Completion flow

### 6.1 Все подгруппы найдены

```gdscript
func _on_all_subgroups_found() -> void:
    GameManager.set_layer_progress(_hall_id, 3, {
        "status": "completed",
        "found_count": keyring_assembly_mgr.get_progress()["found"],
        "total_count": keyring_assembly_mgr.get_progress()["total"],
        "found_subgroups": keyring_assembly_mgr.get_found_subgroups(),
    })

    if _level_scene.feedback_fx:
        _level_scene.feedback_fx.play_completion_feedback(
            _level_scene.crystals.values(), _level_scene.edges)

    var cl := _level_scene.hud_layer.get_node_or_null("CounterLabel")
    if cl:
        cl.text = "Все брелки собраны!"
        cl.add_theme_color_override("font_color", L3_GOLD)

    _level_scene.get_tree().create_timer(1.5).timeout.connect(_show_layer_3_summary)
    layer_completed.emit(3, _hall_id)
```

### 6.2 Summary panel

Аналогичен Layer 2: золотая тема, список найденных брелков с элементами, кнопка «ВЕРНУТЬСЯ НА КАРТУ».

---

## 7. Фильтрация для сложных уровней

По рекомендации T095:

| Уровень | Группа | Всего | Показываем | Стратегия |
|---------|--------|-------|-----------|-----------|
| 13      | S4     | 30    | **10**    | {e}, A4, V4, 3×D4, 3×S3, S4 |
| 20      | D6     | 16    | **10**    | {e}, Z2, Z3, Z6, 3×D3, Z2×Z3, D6 |
| 21      | Q8     | 12    | **12**    | Все (педагогическая ценность Q8) |
| 24      | D4×Z2  | 33    | **10**    | {e}, центр, maximal(×4), interesting(×3), full |
| Остальные | —   | 2-10  | **все**   | Без фильтрации |

---

## 8. Новые файлы и изменения

### 8.1 Новые файлы

| Файл | Назначение |
|------|-----------|
| `src/core/keyring_assembly_manager.gd` | Логика сборки брелков |
| `src/ui/keyring_panel.gd` | Панель со списком слотов |
| `src/ui/keyring_slot.gd` | Один слот брелка |

### 8.2 Изменения в существующих

| Файл | Что меняется |
|------|-------------|
| `layer_mode_controller.gd` | + LAYER_3_GROUP, + _setup_layer_3(), + gold theme |
| `key_bar.gd` | + enable_drag_copy_mode(), + _get_drag_data() |
| `level_scene.gd` | + обработка Layer 3 tap, + resize crystal zone |
| `map_scene.gd` | + золотой индикатор на нодах для Layer 3 |
| `data/levels/act1/level_*.json` | + секция layers.layer_3 |

### 8.3 НЕ меняется

- `permutation.gd` — всё нужное уже есть
- `subgroup_checker.gd` — используем as-is
- `graph_engine.gd`, `hall_progression_engine.gd` — Layer 3 threshold уже есть

---

## 9. Data flow

```
KeyBar (все ключи)
    │ drag/tap → copy sym_id
    ▼
KeyringSlot (активный)
    │ key_added / key_removed
    ▼
KeyringAssemblyManager
    │ validate():
    │   has identity? → closed? → has inverses? → is new?
    │
    ├── subgroup_found → slot.lock(), gold glow, next slot, counter++
    ├── duplicate      → orange flash, hint
    └── not subgroup   → (nothing)
    │
    ▼
all_subgroups_found?
    │
    ▼
GameManager.set_layer_progress() → completion summary → layer_completed.emit(3)
```

---

## 10. Открытые вопросы для boss

1. **Фильтрация**: принимаем «10 интересных» для уровней 13, 20, 24?
2. **Тривиальные {e} и G**: подтверждаем включение? (Z2/Z3/Z5/Z7 пройдутся за секунды)
3. **Tap-to-add + drag**: реализуем оба сразу или сначала tap-only (проще)?
4. **Completionist mode** («найди все 30»): делаем в S011 или бэклог?

---

*Конец документа.*
