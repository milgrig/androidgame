# План: Карта комнат внутри уровня

## Концепция

Кристаллы — механизм-сейф. Каждое валидное расположение кристаллов — это **комната**.
В каждой комнате лежит **ключ** — запомненная комбинация для быстрого возврата.
Ключ можно применить из любой комнаты (действие группы: `текущая_комната × ключ = комната_назначения`).
Количество комнат = порядок группы = количество ключей.

Все уровни сразу переходят на новый формат. Старый HUD удаляется.

---

## Новые файлы (3 шт.)

### 1. `src/game/room_state.gd` — Чистые данные комнат

**Класс:** `RoomState extends RefCounted`

Содержит:
- `group_order: int` — количество комнат
- `all_perms: Array[Permutation]` — все автоморфизмы (индекс 0 = тождество = Дом)
- `perm_names: Array[String]` — имена из JSON (`"Тождество"`, `"Поворот 120°"`, …)
- `cayley_table: Array[Array[int]]` — `cayley_table[a][b]` = индекс комнаты `compose(perm_a, perm_b)`
- `discovered: Array[bool]` — `discovered[i] = true` если комната открыта
- `current_room: int` — текущая комната
- `colors: Array[Color]` — уникальный цвет каждой комнаты (Дом = золотой `#c9a84c`)
- `transition_history: Array[Dictionary]` — `{from, to, key, time}`

Методы:
- `setup(level_data, rebase_inverse)` — инициализация из JSON. Считывает `symmetries.automorphisms`, ставит identity на индекс 0, строит таблицу Кэли
- `discover_room(idx) -> bool` — пометить открытой, вернуть `true` если новая
- `apply_key(key_idx) -> int` — `cayley_table[current_room][key_idx]`, обновляет `current_room`
- `get_destination(from, key) -> int` — чистый lookup без побочных эффектов
- `find_room_for_perm(perm, rebase_inverse) -> int` — найти индекс комнаты по перестановке
- `generate_colors(n) -> Array[Color]` — порт алгоритма из прототипа

Связь с `KeyRing`: `RoomState` НЕ заменяет `KeyRing`. Когда `KeyRing.add_key()` срабатывает, `LevelScene` вызывает `RoomState.discover_room()` для соответствующей комнаты. Индексы KeyRing (порядок находки) ≠ индексы RoomState (порядок в JSON).

---

### 2. `src/game/room_map_panel.gd` — Канвас карты (правая половина экрана)

**Класс:** `RoomMapPanel extends Node2D`

Сигналы:
- `room_hovered(room_idx: int)` — `-1` при уходе
- `room_clicked(room_idx: int)`

Данные:
- `room_state: RoomState` — ссылка (read-only)
- `map_positions: Array[Vector2]` — позиции узлов
- `fading_edges: Array[Dictionary]` — `{from, to, color, alpha, key}`
- `hover_key: int` — индекс ключа под курсором
- `hover_node: int` — индекс комнаты под курсором

Layout алгоритм (порт из прототипа `redesign_map/rooms-keys.html`):
1. BFS от комнаты 0 через все элементы — определить расстояния
2. Группировка по слоям (концентрические круги)
3. Дом в центре, каждый слой — дуга
4. 200 итераций force-directed relaxation (repulsion 800/d², attraction к целевому радиусу)
5. Комната 0 зафиксирована в центре

Отрисовка (`_draw()`):
1. Затухающие рёбра (квадратичные безье + стрелка, цвет ключа)
2. Hover-превью (все переходы ключа, alpha 0.2; пройденные — 0.35)
3. Узлы-квадраты (размер: 11px при N≤12, 9px при N≤16, 7px при N>16)
4. Номера комнат

Состояния узлов:
- Не найдена: пунктирный контур, alpha 0.12
- Найдена: заливка цветом комнаты (alpha 0.33)
- Текущая: полная яркость + glow
- Дом (0): символ `⌂`

Затухание рёбер в `_process()`: `alpha *= 0.985`, удалять при `alpha < 0.01`.

Ввод: hit-test по квадратам узлов, emit `room_clicked`/`room_hovered`.

---

### 3. `src/game/key_bar.gd` — Панель ключей (низ экрана)

**Класс:** `KeyBar extends Control`

Сигналы:
- `key_pressed(key_idx: int)`
- `key_hovered(key_idx: int)` — `-1` при уходе

UI:
- `PanelContainer` с тёмным фоном в `hud_layer`
- `HFlowContainer` с кнопками-ключами
- Каждая кнопка: цветной квадратик + номер

Состояния кнопки:
- Не найдена: затемнена, некликабельна
- Найдена: цвет комнаты, кликабельна
- Текущая комната: золотая рамка

Масштаб:
- ≤12 ключей: одна строка
- 13–24: компактная сетка
- >24: прокрутка

Метод `rebuild(room_state)` — пересоздаёт все кнопки.

---

## Изменяемые файлы (2 шт.)

### 4. `src/game/level_scene.gd` — Перестройка под split-screen

Новые поля:
```gdscript
var _room_state := RoomState.new()
var _room_map: RoomMapPanel = null
var _key_bar: KeyBar = null
```

Изменения в `_setup_scene_structure()`:
- Убрать вызов `HudBuilder.build_hud()` (старый HUD)
- Создать split-layout:
  - Левая половина: crystal_container + edge_container + camera (ограничена crystal_rect)
  - Правая половина: RoomMapPanel
  - Низ: KeyBar в hud_layer
- Оставить минимальный HUD: заголовок уровня, счётчик, кнопки Reset/Check, room badge

Изменения в `_build_level()`:
- После `_validation_mgr.setup()`:
  ```
  _room_state.setup(level_data, _validation_mgr.rebase_inverse)
  _room_map.set_room_state(_room_state)
  _room_map.compute_layout()
  _key_bar.rebuild(_room_state)
  ```
- Передавать `crystal_rect.size` вместо `viewport.size` в `build_positions_map()`

Изменения в `_validate_permutation()` — после `r.get("is_new", false)`:
```gdscript
var room_idx := _room_state.find_room_for_perm(perm, _validation_mgr.rebase_inverse)
if room_idx >= 0:
    _room_state.discover_room(room_idx)
    _room_state.current_room = room_idx
    _room_map.highlight_room(room_idx)
    _key_bar.rebuild(_room_state)
    _update_room_badge(room_idx)
```

Новый метод `_on_key_bar_key_pressed(key_idx)`:
- `from = _room_state.current_room`
- `to = _room_state.apply_key(key_idx)`
- Записать переход в историю
- `_room_map.add_fading_edge(from, to, key_idx)`
- Применить перестановку к кристаллам (через `_shuffle_mgr` + анимация `_swap_mgr`)
- Если новая комната — `_room_state.discover_room(to)`
- Валидировать новое расположение

Новый метод `_on_key_bar_key_hovered(key_idx)`:
- `_room_map.set_hover_key(key_idx)`

Удаляемый код:
- Старые `RepeatButton`, `CombineButton`, `KeyRingLabel`, `KeyButtonsContainer` — заменяются `KeyBar`
- `_rebuild_key_buttons()`, `_update_repeat_button_text()`, `_on_repeat_pressed()` — функционал переезжает в `KeyBar` + `_on_key_bar_key_pressed`
- Combine mode пока убираем (в будущем можно вернуть через KeyBar: два последовательных клика)

Agent API: `perform_swap_by_id`, `submit_permutation`, `agent_reset`, `agent_check_current`, `agent_repeat_key` — оставляем без изменений.

---

### 5. `src/game/hud_builder.gd` — Новый метод `build_split_hud()`

Заменяет `build_hud()`:
- Создаёт минимальный набор: заголовок уровня, счётчик комнат, кнопки Reset/Check, InstructionPanel, CompleteSummaryPanel, HintLabel, room badge
- НЕ создаёт: RepeatButton, CombineButton, KeyRingLabel, KeyButtonsContainer, GeneratorsPanel
- Room badge: цветной квадратик + имя комнаты внизу левой половины

---

## Порядок реализации

### Фаза 1: RoomState (чистые данные, без UI)
1. Создать `room_state.gd`
2. Реализовать `setup()`, `generate_colors()`, Cayley table
3. Реализовать `discover_room()`, `apply_key()`, `find_room_for_perm()`

### Фаза 2: RoomMapPanel (визуал карты)
4. Создать `room_map_panel.gd`
5. Реализовать `compute_layout()` (BFS + force-directed)
6. Реализовать `_draw()` — узлы-квадраты
7. Добавить затухающие рёбра (bezier + стрелка + decay)
8. Добавить hover-превью
9. Добавить input (hit-test, клик, hover)

### Фаза 3: KeyBar (UI панель ключей)
10. Создать `key_bar.gd`
11. Реализовать `rebuild()` — кнопки с цветами
12. Подключить сигналы hover/pressed

### Фаза 4: Интеграция в LevelScene
13. Обновить `hud_builder.gd` — добавить `build_split_hud()`
14. Обновить `_setup_scene_structure()` — split layout
15. Обновить `_build_level()` — инициализация RoomState + подключение компонентов
16. Обновить `_validate_permutation()` — открытие комнат при находке
17. Добавить `_on_key_bar_key_pressed()` — применение ключа
18. Удалить старый код RepeatButton/CombineButton/KeyRingLabel
19. Обновить `_on_level_complete()`, `_update_counter()`, инструкции

### Фаза 5: Тестирование
20. Прогнать существующие тесты (240+)
21. Ручная проверка на уровнях Z₃(3), D₄(8), S₃(6)

---

## Что НЕ трогаем

| Файл | Причина |
|------|---------|
| `src/core/permutation.gd` | Математическое ядро, без изменений |
| `src/core/graph_engine.gd` | Валидация автоморфизмов, без изменений |
| `src/core/key_ring.gd` | Продолжает трекать находки |
| `src/game/validation_manager.gd` | Продолжает валидировать |
| `src/game/shuffle_manager.gd` | Продолжает управлять расположением |
| `src/game/swap_manager.gd` | Продолжает анимировать свопы |
| `src/visual/crystal_node.gd` | Кристаллы не меняются |
| `src/visual/edge_renderer.gd` | Рёбра графа кристаллов не меняются |
| `src/visual/feedback_fx.gd` | Эффекты переиспользуются |
| `src/ui/map_scene.gd` | Мировая карта (между уровнями) — другая система |
| `src/core/hall_tree_data.gd` | Прогрессия уровней, без изменений |
| `src/core/hall_progression_engine.gd` | Прогрессия уровней, без изменений |

---

## Поток данных

```
Игрок тащит кристаллы → SwapManager.perform_swap()
    → ShuffleManager обновляет current_arrangement
    → ValidationManager.validate_permutation()
        → Совпало? KeyRing.add_key()
        → RoomState.discover_room(room_idx)
            → RoomMapPanel — новый узел на карте
            → KeyBar — новая кнопка
        → RoomState.current_room = room_idx
        → Room badge обновляется

Игрок жмёт ключ в KeyBar:
    → LevelScene._on_key_bar_key_pressed(key_idx)
        → RoomState.apply_key(key_idx) → комната назначения
        → ShuffleManager.apply_permutation(perm)
        → SwapManager — анимация перелёта кристаллов
        → RoomMapPanel.add_fading_edge(from, to, key_idx)
        → Если новая комната — discover_room()
        → ValidationManager.validate_permutation()

Игрок наводит на ключ в KeyBar:
    → RoomMapPanel.set_hover_key(key_idx)
    → _draw() показывает все переходы этого ключа
```
