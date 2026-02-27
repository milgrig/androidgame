#!/usr/bin/env python3
"""
Генератор сложных уровней для The Symmetry Vaults

Поддерживает:
- Большие структурированные группы (S4, A4, D6, etc.)
- Хаотичные уровни с разными цветами и сложной топологией
- Автоматическая генерация автоморфизмов
- Настройка цветов кристаллов и типов рёбер
"""

import json
import math
from itertools import permutations, combinations
from typing import List, Dict, Tuple, Optional

# ============================================================================
# Доступные цвета и типы рёбер
# ============================================================================

COLORS = ["red", "blue", "green", "yellow", "purple", "orange", "cyan", "pink", "white", "black"]
EDGE_TYPES = ["standard", "glowing", "thick", "dashed"]

# ============================================================================
# Утилиты для генерации групп
# ============================================================================

def generate_symmetric_group(n: int) -> List[Dict]:
    """
    Генерирует все элементы симметрической группы S_n

    Args:
        n: порядок группы (количество элементов для перестановок)

    Returns:
        Список автоморфизмов в формате игры
    """
    automorphisms = []
    for i, perm in enumerate(permutations(range(n))):
        automorphisms.append({
            "id": f"perm_{i}",
            "mapping": list(perm),
            "name": f"Перестановка {i + 1}",
            "description": f"{perm}"
        })
    return automorphisms


def generate_alternating_group(n: int) -> List[Dict]:
    """
    Генерирует знакопеременную группу A_n (четные перестановки)

    Args:
        n: порядок (A_n содержит n!/2 элементов)

    Returns:
        Список автоморфизмов
    """
    def sign_of_permutation(perm):
        """Вычисляет знак перестановки"""
        n = len(perm)
        inversions = 0
        for i in range(n):
            for j in range(i + 1, n):
                if perm[i] > perm[j]:
                    inversions += 1
        return 1 if inversions % 2 == 0 else -1

    automorphisms = []
    for i, perm in enumerate(permutations(range(n))):
        if sign_of_permutation(perm) == 1:  # Только четные перестановки
            automorphisms.append({
                "id": f"even_perm_{len(automorphisms)}",
                "mapping": list(perm),
                "name": f"Четная перестановка {len(automorphisms) + 1}",
                "description": f"{perm}"
            })
    return automorphisms


def generate_dihedral_group(n: int) -> Tuple[List[Dict], List[int]]:
    """
    Генерирует диэдральную группу D_n (группу симметрий правильного n-угольника)

    Args:
        n: количество вершин многоугольника

    Returns:
        (automorphisms, positions) - автоморфизмы и позиции для рисования
    """
    automorphisms = []

    # Тождественный элемент
    automorphisms.append({
        "id": "e",
        "mapping": list(range(n)),
        "name": "Тождество",
        "description": "Всё остаётся на месте"
    })

    # Повороты
    for k in range(1, n):
        mapping = [(i + k) % n for i in range(n)]
        angle = 360 * k // n
        automorphisms.append({
            "id": f"r{k}",
            "mapping": mapping,
            "name": f"Поворот на {angle}°",
            "description": f"{k} шагов по часовой стрелке"
        })

    # Отражения
    for k in range(n):
        if n % 2 == 0:  # Четное количество вершин
            # Отражение через вершину и противоположную вершину
            if k < n // 2:
                mapping = [(k - i) % n for i in range(n)]
            else:
                mapping = [(k - i + n) % n for i in range(n)]
        else:  # Нечетное количество вершин
            # Отражение через вершину и середину противоположного ребра
            mapping = [(k - i + n) % n for i in range(n)]

        automorphisms.append({
            "id": f"s{k}",
            "mapping": mapping,
            "name": f"Отражение {k + 1}",
            "description": f"Отразить относительно оси {k}"
        })

    # Генерируем позиции для рисования (правильный многоугольник)
    center_x, center_y = 640, 360
    radius = 200
    positions = []
    for i in range(n):
        angle = 2 * math.pi * i / n - math.pi / 2  # Начинаем сверху
        x = center_x + radius * math.cos(angle)
        y = center_y + radius * math.sin(angle)
        positions.append([int(x), int(y)])

    return automorphisms, positions


def generate_cyclic_group(n: int) -> List[Dict]:
    """
    Генерирует циклическую группу Z_n

    Args:
        n: порядок группы

    Returns:
        Список автоморфизмов
    """
    automorphisms = []
    for k in range(n):
        mapping = [(i + k) % n for i in range(n)]
        automorphisms.append({
            "id": f"r{k}" if k > 0 else "e",
            "mapping": mapping,
            "name": "Тождество" if k == 0 else f"Сдвиг на {k}",
            "description": "Всё остаётся на месте" if k == 0 else f"{k} шагов циклического сдвига"
        })
    return automorphisms


# ============================================================================
# Генераторы уровней
# ============================================================================

class LevelGenerator:
    """Генератор уровней с различными параметрами"""

    def __init__(self, level_id: str, level_num: int, act: int = 1):
        self.level_id = level_id
        self.level_num = level_num
        self.act = act
        self.nodes = []
        self.edges = []
        self.automorphisms = []

    def create_big_structured_level(
        self,
        group_type: str = "S4",
        graph_type: str = "tetrahedron",
        title: str = "Большой зал",
        subtitle: str = "Много ключей"
    ) -> Dict:
        """
        Создать большой структурированный уровень

        Args:
            group_type: "S4", "A4", "D6", etc.
            graph_type: "tetrahedron", "cube", "octahedron", "complete"
            title: название уровня
            subtitle: подзаголовок
        """
        # Генерация графа в зависимости от типа
        if graph_type == "tetrahedron":
            self._create_tetrahedron()
        elif graph_type == "cube":
            self._create_cube()
        elif graph_type == "octahedron":
            self._create_octahedron()
        elif graph_type == "complete":
            self._create_complete_graph(4)

        # Генерация группы
        n = len(self.nodes)
        if group_type == "S4":
            self.automorphisms = generate_symmetric_group(4)
            group_name = "S4"
            group_order = 24
        elif group_type == "A4":
            self.automorphisms = generate_alternating_group(4)
            group_name = "A4"
            group_order = 12
        elif group_type == "S5":
            self.automorphisms = generate_symmetric_group(5)
            group_name = "S5"
            group_order = 120
        elif group_type == "D6":
            self.automorphisms, positions = generate_dihedral_group(6)
            # Обновить позиции узлов
            for i, node in enumerate(self.nodes):
                node["position"] = positions[i]
            group_name = "D6"
            group_order = 12
        else:
            raise ValueError(f"Unknown group type: {group_type}")

        return self._build_level_json(title, subtitle, group_name, group_order)

    def create_chaotic_level(
        self,
        num_nodes: int = 8,
        num_colors: int = 6,
        edge_variety: bool = True,
        group_type: str = "D4",
        title: str = "Хаотичный зал",
        subtitle: str = "Цвета запутывают"
    ) -> Dict:
        """
        Создать хаотичный уровень со многими цветами

        Args:
            num_nodes: количество узлов
            num_colors: количество различных цветов (узлы могут повторяться)
            edge_variety: использовать разные типы рёбер
            group_type: тип группы симметрий
            title: название
            subtitle: подзаголовок
        """
        # Создать узлы со случайными цветами (но с повторениями!)
        used_colors = COLORS[:num_colors]

        if group_type == "D4":
            self.automorphisms, positions = generate_dihedral_group(4)
            # Но цвета делаем хаотичными
            for i in range(4):
                color = used_colors[i % len(used_colors)]  # Повторяющиеся цвета!
                self.nodes.append({
                    "id": i,
                    "color": color,
                    "position": positions[i],
                    "label": chr(65 + i)  # A, B, C, D
                })

            # Рёбра с разными типами
            edge_configs = [
                (0, 1, "glowing" if edge_variety else "standard"),
                (1, 2, "standard"),
                (2, 3, "thick" if edge_variety else "standard"),
                (3, 0, "standard")
            ]

            for fr, to, etype in edge_configs:
                self.edges.append({
                    "from": fr,
                    "to": to,
                    "type": etype,
                    "weight": 1
                })

            group_name = "D4"
            group_order = 8

        elif group_type == "S3":
            # Два треугольника с повторяющимися цветами
            # Верхний треугольник
            positions_top = [[280, 200], [700, 160], [500, 340]]
            # Нижний треугольник
            positions_bottom = [[220, 480], [760, 440], [480, 560]]

            # Цвета: первый треугольник - красные, второй - повторение!
            colors_config = [
                used_colors[0], used_colors[0], used_colors[0],  # 3 красных
                used_colors[1], used_colors[1], used_colors[2]   # 2 синих, 1 зелёный
            ]

            for i in range(6):
                pos = positions_top[i] if i < 3 else positions_bottom[i - 3]
                self.nodes.append({
                    "id": i,
                    "color": colors_config[i],
                    "position": pos,
                    "label": chr(65 + i)
                })

            # Рёбра внутри треугольников
            self.edges.extend([
                {"from": 0, "to": 1, "type": "standard", "weight": 1},
                {"from": 1, "to": 2, "type": "standard", "weight": 1},
                {"from": 0, "to": 2, "type": "standard", "weight": 1},
                {"from": 3, "to": 4, "type": "standard", "weight": 1},
                {"from": 4, "to": 5, "type": "standard", "weight": 1},
                {"from": 3, "to": 5, "type": "standard", "weight": 1},
            ])

            # Связи между треугольниками (толстые!)
            if edge_variety:
                self.edges.extend([
                    {"from": 0, "to": 3, "type": "thick", "weight": 1},
                    {"from": 1, "to": 4, "type": "thick", "weight": 1},
                    {"from": 2, "to": 5, "type": "thick", "weight": 1},
                ])

            self.automorphisms = generate_symmetric_group(3)
            group_name = "S3"
            group_order = 6

        else:
            raise ValueError(f"Unknown group type for chaotic: {group_type}")

        return self._build_level_json(title, subtitle, group_name, group_order)

    # ========================================================================
    # Вспомогательные методы для создания графов
    # ========================================================================

    def _create_tetrahedron(self):
        """Создать граф тетраэдра (4 вершины, 6 рёбер)"""
        # Позиции в форме тетраэдра
        positions = [
            [640, 200],   # Верхняя
            [400, 500],   # Левая нижняя
            [880, 500],   # Правая нижняя
            [640, 650]    # Задняя нижняя
        ]

        colors = ["red", "blue", "green", "yellow"]

        for i in range(4):
            self.nodes.append({
                "id": i,
                "color": colors[i],
                "position": positions[i],
                "label": chr(65 + i)
            })

        # Полный граф на 4 вершинах
        for i in range(4):
            for j in range(i + 1, 4):
                self.edges.append({
                    "from": i,
                    "to": j,
                    "type": "glowing",
                    "weight": 1
                })

    def _create_cube(self):
        """Создать граф куба (8 вершин, 12 рёбер)"""
        # Позиции для куба (вид сверху с перспективой)
        positions = [
            [400, 200], [800, 200],  # Верхняя грань
            [800, 400], [400, 400],
            [350, 280], [850, 280],  # Нижняя грань (со смещением для перспективы)
            [850, 480], [350, 480]
        ]

        colors = ["red", "red", "blue", "blue", "green", "green", "yellow", "yellow"]

        for i in range(8):
            self.nodes.append({
                "id": i,
                "color": colors[i],
                "position": positions[i],
                "label": chr(65 + i)
            })

        # Рёбра куба
        edges_config = [
            # Верхняя грань
            (0, 1), (1, 2), (2, 3), (3, 0),
            # Нижняя грань
            (4, 5), (5, 6), (6, 7), (7, 4),
            # Вертикальные рёбра
            (0, 4), (1, 5), (2, 6), (3, 7)
        ]

        for fr, to in edges_config:
            self.edges.append({
                "from": fr,
                "to": to,
                "type": "standard",
                "weight": 1
            })

    def _create_octahedron(self):
        """Создать граф октаэдра (6 вершин, 12 рёбер)"""
        positions = [
            [640, 150],   # Верхняя
            [400, 300], [880, 300],  # Средний пояс (4 вершины)
            [400, 500], [880, 500],
            [640, 650]    # Нижняя
        ]

        colors = ["red", "blue", "blue", "green", "green", "yellow"]

        for i in range(6):
            self.nodes.append({
                "id": i,
                "color": colors[i],
                "position": positions[i],
                "label": chr(65 + i)
            })

        # Рёбра октаэдра
        edges_config = [
            # От верхней к поясу
            (0, 1), (0, 2), (0, 3), (0, 4),
            # Внутри пояса
            (1, 2), (2, 4), (4, 3), (3, 1),
            # От пояса к нижней
            (1, 5), (2, 5), (3, 5), (4, 5)
        ]

        for fr, to in edges_config:
            self.edges.append({
                "from": fr,
                "to": to,
                "type": "glowing",
                "weight": 1
            })

    def _create_complete_graph(self, n: int):
        """Создать полный граф на n вершинах"""
        # Расположить вершины по кругу
        center_x, center_y = 640, 360
        radius = 200

        for i in range(n):
            angle = 2 * math.pi * i / n - math.pi / 2
            x = center_x + radius * math.cos(angle)
            y = center_y + radius * math.sin(angle)

            self.nodes.append({
                "id": i,
                "color": COLORS[i % len(COLORS)],
                "position": [int(x), int(y)],
                "label": chr(65 + i)
            })

        # Все рёбра
        for i in range(n):
            for j in range(i + 1, n):
                self.edges.append({
                    "from": i,
                    "to": j,
                    "type": "standard",
                    "weight": 1
                })

    # ========================================================================
    # Построение JSON
    # ========================================================================

    def _build_level_json(self, title: str, subtitle: str, group_name: str, group_order: int) -> Dict:
        """Построить финальный JSON уровня"""
        return {
            "meta": {
                "id": self.level_id,
                "act": self.act,
                "level": self.level_num,
                "title": title,
                "subtitle": subtitle,
                "group_name": group_name,
                "group_order": group_order
            },
            "graph": {
                "nodes": self.nodes,
                "edges": self.edges
            },
            "symmetries": {
                "automorphisms": self.automorphisms,
                "generators": [],  # TODO: можно добавить автоопределение генераторов
                "cayley_table": {}  # TODO: можно добавить автогенерацию таблицы Кэли
            },
            "mechanics": {
                "allowed_actions": ["swap"],
                "show_cayley_button": True,
                "show_generators_hint": False,
                "inner_doors": [],
                "palette": None
            },
            "visuals": {
                "background_theme": "stone_vault",
                "ambient_particles": "dust_motes",
                "crystal_style": "basic_gem",
                "edge_style": "glowing"
            },
            "hints": [
                {
                    "trigger": "after_30_seconds_no_action",
                    "text": "Это сложный уровень. Попробуйте найти закономерности в структуре."
                }
            ],
            "echo_hints": []
        }


# ============================================================================
# Примеры использования
# ============================================================================

def main():
    """Generate example levels"""

    print("Level Generator for The Symmetry Vaults\n")

    # Example 1: Big structured (S4, tetrahedron)
    print("[1] Creating level: Tetrahedron (S4, 24 keys)...")
    gen1 = LevelGenerator("act1_level13", 13, act=1)
    level13 = gen1.create_big_structured_level(
        group_type="S4",
        graph_type="tetrahedron",
        title="Тетраэдральный зал",
        subtitle="Четыре вершины, двадцать четыре ключа"
    )

    output_path = "TheSymmetryVaults/data/levels/act1/level_13.json"
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(level13, f, ensure_ascii=False, indent=2)
    print(f"   [OK] Saved: {output_path}\n")

    # Example 2: Chaotic (D4, 8 nodes, 6 colors)
    print("[2] Creating level: Rainbow Chaos (D4, 8 keys, many colors)...")
    gen2 = LevelGenerator("act1_level14", 14, act=1)
    level14 = gen2.create_chaotic_level(
        num_nodes=8,
        num_colors=6,
        edge_variety=True,
        group_type="D4",
        title="Радужный лабиринт",
        subtitle="Цвета запутывают, но порядок есть"
    )

    output_path = "TheSymmetryVaults/data/levels/act1/level_14.json"
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(level14, f, ensure_ascii=False, indent=2)
    print(f"   [OK] Saved: {output_path}\n")

    # Example 3: Alternating group A4
    print("[3] Creating level: Alternating Group (A4, 12 keys)...")
    gen3 = LevelGenerator("act1_level15", 15, act=1)
    level15 = gen3.create_big_structured_level(
        group_type="A4",
        graph_type="tetrahedron",
        title="Зал четных перестановок",
        subtitle="Только половина ключей работает"
    )

    output_path = "TheSymmetryVaults/data/levels/act1/level_15.json"
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(level15, f, ensure_ascii=False, indent=2)
    print(f"   [OK] Saved: {output_path}\n")

    print("Done! Created 3 new levels.")
    print("\nNext steps:")
    print("   - Launch the game and test the levels")
    print("   - Modify parameters in the code for your custom levels")
    print("   - Add hints and text to the JSON files")


if __name__ == "__main__":
    main()
