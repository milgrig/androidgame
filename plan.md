# План: AI Accessibility Layer — «DOM для Godot»

## Идея

Как браузер показывает HTML и пользователь видит кнопки — так AgentBridge
**автоматически обходит дерево сцены Godot** и показывает агенту всё,
что есть на экране. Программист добавил кнопку → агент её видит и может нажать.
Ничего руками в мост добавлять не нужно.

---

## Архитектура

```
Claude Code (терминал)                    Godot 4.6 (headless)
     │                                         │
     │── пишет cmd.jsonl ──────────────────►    │  AgentBridge (autoload)
     │                                         │    ├── обходит дерево сцены
     │◄── читает resp.jsonl ───────────────    │    ├── находит все Label, Button, Crystal...
     │                                         │    ├── выполняет действия
     │   agent_client.py                       │    └── пишет ответ
     │   (обёртка)                             │
```

**Протокол:** файловый (cmd.jsonl → resp.jsonl). Надёжно на Windows,
GDScript не умеет stdin, задержка ~16мс — для пошаговой головоломки OK.

---

## Ключевой принцип: автоматический обход дерева

AgentBridge **не знает** заранее, какие кнопки или элементы есть.
Он обходит дерево сцены рекурсивно и сериализует всё, что находит:

```gdscript
# Псевдокод — сердце всей системы
func _serialize_node(node: Node) -> Dictionary:
    var result := {
        "name": node.name,
        "type": node.get_class(),           # "Button", "Label", "CrystalNode"...
        "path": str(node.get_path()),       # "/root/LevelScene/HUDLayer/ResetButton"
    }

    # Для каждого типа — релевантные свойства
    if node is BaseButton:
        result["text"] = node.text if node.has_method("get_text") else ""
        result["disabled"] = node.disabled
        result["visible"] = node.visible
        result["actions"] = ["press"]       # ← что можно сделать

    if node is Label:
        result["text"] = node.text
        result["visible"] = node.visible

    if node is CrystalNode:
        result["crystal_id"] = node.crystal_id
        result["color"] = node.get_crystal_color()
        result["label"] = node.label_text
        result["draggable"] = node.draggable
        result["position"] = [node.position.x, node.position.y]
        result["actions"] = ["swap_to"]     # ← можно перетащить на другой кристалл

    if node is EdgeRenderer:
        result["from"] = node.from_node_id
        result["to"] = node.to_node_id
        result["edge_type"] = node.edge_type

    # Рекурсивно обходим детей
    var children := []
    for child in node.get_children():
        children.append(_serialize_node(child))
    if not children.is_empty():
        result["children"] = children

    return result
```

Программист добавил `Button` с именем "CayleyButton" в HUD →
агент видит в ответе:
```json
{
  "name": "CayleyButton",
  "type": "Button",
  "path": "/root/LevelScene/HUDLayer/CayleyButton",
  "text": "Show Cayley Table",
  "disabled": false,
  "visible": true,
  "actions": ["press"]
}
```

---

## Команды протокола

### Базовые (обзор)
| Команда | Что делает |
|---------|-----------|
| `hello` | Хэндшейк: версия протокола, доступные команды |
| `get_tree` | **Полный DOM** — рекурсивный обход всего дерева сцены |
| `get_state` | Состояние игры: кристаллы, рёбра, keyring, arrangement |
| `list_actions` | Все доступные действия прямо сейчас |

### Действия
| Команда | Аргументы | Что делает |
|---------|-----------|-----------|
| `swap` | `{"from": 0, "to": 1}` | Перетащить кристалл (как игрок) |
| `submit_permutation` | `{"mapping": [1,2,0]}` | Подать перестановку напрямую |
| `press_button` | `{"path": "/root/.../CayleyButton"}` | Нажать любую кнопку по пути в дереве |
| `reset` | — | Сбросить расположение |
| `load_level` | `{"level_id": "act1_level01"}` | Загрузить уровень |

### Инспекция
| Команда | Что делает |
|---------|-----------|
| `get_node` | Подробная информация об одном узле по пути |
| `get_property` | Прочитать любое свойство любого узла |
| `get_signals` | Список сигналов узла и подключённых обработчиков |
| `get_events` | Очередь событий (сигналы, которые сработали) |

### Управление
| Команда | Что делает |
|---------|-----------|
| `list_levels` | Все доступные уровни |
| `quit` | Выход |

### Формат ответа
```json
{"ok": true, "id": 1, "data": {...}, "events": [...]}
{"ok": false, "id": 2, "error": "Crystal 5 not found", "code": "INVALID_ID"}
```

---

## Новые файлы

### 1. `src/agent/agent_bridge.gd` — Autoload, сердце системы

**Ответственность:**
- Полирует cmd.jsonl каждый кадр (~60fps)
- Парсит команды, диспатчит на обработчики
- Обходит дерево сцены для `get_tree`
- Ловит сигналы LevelScene → event queue
- Пишет ответы в resp.jsonl

**Ключевые методы:**
```
_ready()                      — ищет --agent-mode в аргументах, активируется
_process(delta)               — poll cmd файл + flush events
_poll_command_file()          — читает cmd.jsonl если изменился
_dispatch(cmd, args) -> Dict  — роутер команд
_serialize_tree(root) -> Dict — рекурсивный обход дерева сцены
_serialize_node(node) -> Dict — сериализация одного узла по типу
_find_level_scene() -> Node   — находит LevelScene в дереве
_connect_level_signals()      — подключается к swap_performed, symmetry_found и т.д.
_on_signal(name, args)        — пушит событие в очередь
_write_response(data)         — пишет в resp.jsonl
```

**Обработчики команд:**
```
_cmd_hello()                  — версия, список команд
_cmd_get_tree()               — полный DOM
_cmd_get_state()              — игровое состояние
_cmd_swap(args)               — вызывает perform_swap_by_id на LevelScene
_cmd_submit_permutation(args) — напрямую подаёт перестановку
_cmd_press_button(args)       — находит кнопку по path, вызывает pressed.emit()
_cmd_reset()                  — сброс
_cmd_load_level(args)         — загрузка уровня
_cmd_list_actions()           — что сейчас можно делать
_cmd_get_node(args)           — подробно об одном узле
_cmd_get_events()             — drain event queue
_cmd_list_levels()            — все уровни
_cmd_quit()                   — выход
```

### 2. `src/agent/agent_protocol.gd` — Сериализация (RefCounted)

Чистые функции для JSON-сериализации:
```
serialize_crystal(crystal: CrystalNode) -> Dict
serialize_edge(edge: EdgeRenderer) -> Dict
serialize_keyring(kr: KeyRing) -> Dict
serialize_permutation(p: Permutation) -> Dict
serialize_node_generic(node: Node) -> Dict  — универсальный сериализатор
format_response(ok, data, events, id) -> String
parse_command(json_str) -> Dict
```

### 3. Модификация `src/game/level_scene.gd`

Добавить:
```gdscript
var agent_mode: bool = false

## Программный swap для AI-агента. Без drag-and-drop.
func perform_swap_by_id(from_id: int, to_id: int) -> Dictionary:
    if from_id == to_id:
        return {"result": "no_op", "reason": "same_crystal"}
    if not (from_id in crystals and to_id in crystals):
        return {"result": "error", "reason": "invalid_crystal_id"}
    _perform_swap(crystals[from_id], crystals[to_id])
    return {"result": "ok"}

## Программная подача произвольной перестановки
func submit_permutation(mapping: Array) -> Dictionary:
    var perm := Permutation.from_array(mapping)
    if not perm.is_valid():
        return {"result": "error", "reason": "invalid_permutation"}
    # Устанавливаем arrangement напрямую
    current_arrangement = mapping.duplicate()
    _validate_permutation(perm)
    return {"result": "ok"}
```

В `_perform_swap` — учёт agent_mode для нулевых анимаций:
```gdscript
var duration := 0.0 if agent_mode else 0.35
crystal_a.animate_to_position(pos_b, duration)
crystal_b.animate_to_position(pos_a, duration)
```

В `_validate_permutation` — мгновенный reset в agent_mode:
```gdscript
if agent_mode:
    _reset_arrangement()
else:
    var tween = create_tween()
    tween.tween_interval(0.5)
    tween.tween_callback(_reset_arrangement)
```

### 4. Модификация `project.godot`

Добавить autoload:
```ini
[autoload]
GameManager="*res://src/game/game_manager.gd"
AgentBridge="*res://src/agent/agent_bridge.gd"
```

### 5. `tests/agent/agent_client.py` — Python-обёртка

Запускает Godot как subprocess, оборачивает файловый протокол:
```python
class AgentClient:
    def start(level_id=None)         # запуск Godot headless
    def get_tree() -> dict           # полный DOM
    def get_state() -> dict          # игровое состояние
    def swap(from_id, to_id) -> dict
    def submit_permutation(mapping) -> dict
    def press_button(path) -> dict   # нажать кнопку по пути
    def reset() -> dict
    def load_level(level_id) -> dict
    def list_actions() -> list
    def get_events() -> list
    def quit()
```

### 6. `tests/agent/test_agent_plays.py` — Тесты «агент играет»

```python
class TestAgentPlaysLevel1:
    def test_agent_sees_all_crystals()
    def test_agent_sees_edges_with_types()
    def test_agent_sees_hud_labels()
    def test_swap_produces_events()
    def test_find_all_symmetries_and_complete()
    def test_hud_counter_updates_after_symmetry_found()
    def test_invalid_swap_produces_invalid_event()

class TestAgentSeesNewUI:
    """Если программист добавил кнопку — агент её видит"""
    def test_new_button_appears_in_tree()
    def test_agent_can_press_new_button()
```

### 7. `tests/agent/demo_agent_plays.py` — Демонстрация

Скрипт-пример: агент загружает уровень, смотрит состояние,
находит все симметрии, проходит уровень. Пригодится как документация.

---

## Пример сессии агента

```
Agent → {"cmd": "hello", "id": 1}
Game  ← {"ok": true, "id": 1, "data": {"version": "1.0", "commands": [...]}}

Agent → {"cmd": "load_level", "id": 2, "args": {"level_id": "act1_level01"}}
Game  ← {"ok": true, "id": 2, "data": {"level": "act1_level01", "loaded": true}}

Agent → {"cmd": "get_tree", "id": 3}
Game  ← {"ok": true, "id": 3, "data": {"tree": {
    "name": "root", "type": "Window", "children": [
      {"name": "LevelScene", "type": "LevelScene", "children": [
        {"name": "CrystalContainer", "children": [
          {"name": "Crystal_0", "type": "CrystalNode",
           "crystal_id": 0, "color": "red", "label": "A",
           "draggable": true, "actions": ["swap_to"]},
          {"name": "Crystal_1", ...},
          {"name": "Crystal_2", ...}
        ]},
        {"name": "EdgeContainer", "children": [
          {"name": "Edge_0_1", "type": "EdgeRenderer",
           "from": 0, "to": 1, "edge_type": "standard"},
          ...
        ]},
        {"name": "HUDLayer", "type": "CanvasLayer", "children": [
          {"name": "TitleLabel", "type": "Label",
           "text": "The Triangle Vault", "visible": true},
          {"name": "CounterLabel", "type": "Label",
           "text": "Symmetries: 0 / 3", "visible": true},
          {"name": "ResetButton", "type": "Button",
           "text": "Reset", "disabled": false, "actions": ["press"]}
        ]}
      ]}
    ]
  }}}

Agent → {"cmd": "swap", "id": 4, "args": {"from": 0, "to": 1}}
Game  ← {"ok": true, "id": 4, "data": {"result": "ok"},
          "events": [
            {"type": "swap_performed", "mapping": [1, 0, 2]},
            {"type": "invalid_attempt", "mapping": [1, 0, 2]}
          ]}

Agent → {"cmd": "submit_permutation", "id": 5, "args": {"mapping": [1, 2, 0]}}
Game  ← {"ok": true, "id": 5, "data": {"result": "ok"},
          "events": [
            {"type": "symmetry_found", "sym_id": "r1", "mapping": [1, 2, 0]}
          ]}

Agent → {"cmd": "get_state", "id": 6}
Game  ← {"ok": true, "id": 6, "data": {
    "arrangement": [0, 1, 2],
    "keyring": {"found_count": 1, "total": 3, "complete": false},
    ...
  }}
```

---

## Порядок реализации

### Фаза 1: Протокол и мост (GDScript)
1. Создать `src/agent/agent_protocol.gd` — сериализация
2. Создать `src/agent/agent_bridge.gd` — обход дерева, протокол, файловый I/O
3. Модифицировать `src/game/level_scene.gd` — agent_mode, perform_swap_by_id, submit_permutation
4. Модифицировать `project.godot` — autoload

### Фаза 2: Python-клиент
5. Создать `tests/agent/agent_client.py` — обёртка
6. Создать `tests/agent/demo_agent_plays.py` — демо

### Фаза 3: Тесты
7. Создать `tests/agent/test_agent_plays.py` — полные тесты

---

## Почему это работает как DOM

| HTML/Браузер | Godot/AgentBridge |
|---|---|
| `document.querySelectorAll('button')` | `get_tree` → фильтр по `type: "Button"` |
| `element.click()` | `press_button` с путём узла |
| `element.textContent` | `text` в сериализации Label |
| `element.disabled` | `disabled` в сериализации Button |
| DevTools Elements tab | `get_tree` — полное дерево |
| `addEventListener('click', ...)` | `get_events` — очередь сигналов |

**Главное:** программист никогда не должен обновлять мост.
Добавил узел в сцену → `get_tree` его покажет. Автоматически.
