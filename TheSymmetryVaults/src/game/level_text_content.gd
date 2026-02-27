## LevelTextContent — Static text content for level UI.
##
## Contains all localized strings for:
## - Group name formatting
## - Learned notes
## - Instruction text
## - Generators text

class_name LevelTextContent
extends RefCounted


static func format_group_name(group_name: String, group_order: int) -> String:
	match group_name:
		"Z2": return "2 ключа — один обмен и обратно"
		"Z3": return "3 ключа — цикл кристаллов"
		"Z4": return "4 ключа — четыре поворота квадрата"
		"Z5": return "5 ключей — пятишаговый цикл"
		"Z6": return "6 ключей — шестишаговый цикл"
		"D4": return "8 ключей — повороты и отражения квадрата"
		"V4": return "4 ключа — каждое действие отменяет само себя"
		"S3": return "6 ключей — все перестановки трёх пар"
		_: return "%d ключей" % group_order


static func get_learned_note(meta: Dictionary) -> String:
	var group_name: String = meta.get("group_name", "")
	var level_num: int = meta.get("level", 0)
	match group_name:
		"Z2":
			if level_num == 3: return "Цвета ограничивают, какие кристаллы можно менять местами."
			if level_num == 7: return "Кривой путь тоже может скрывать закономерность!"
			if level_num == 8: return "Два одинаковых скопления можно полностью поменять местами."
			return "Один обмен — сделай дважды, и всё вернётся."
		"Z3": return "Три поворота образуют цикл: каждый ведёт к следующему."
		"Z4": return "Стрелки задают направление — можно только вращать, но не отражать."
		"D4":
			if level_num == 12: return "Понадобились два разных вида ходов (поворот И отражение), чтобы получить все 8 расстановок."
			return "Без стрелок появляются отражения — число ключей удваивается!"
		"V4": return "Каждое действие здесь отменяет само себя: сделай дважды — вернёшься."
		"S3": return "Шесть способов переставить три пары — порядок ходов важен!"
		"Z5": return "Одного хода достаточно, чтобы породить все остальные — просто повторяйте."
		"Z6": return "Не каждый ход может породить все остальные — некоторые слишком малы."
		_: return ""


static func get_instruction_text(meta: Dictionary, mechanics: Dictionary) -> Dictionary:
	var level_num: int = meta.get("level", 1)
	var has_cayley: bool = mechanics.get("show_cayley_button", false)
	var has_generators: bool = mechanics.get("show_generators_hint", false)
	var body: String = "Кристаллы перемешаны! Расположите их как на картинке-цели в углу.\n"
	body += "Перетащите один кристалл на другой, чтобы поменять их местами.\n"
	body += "Когда соберёте — нажмите ПРОВЕРИТЬ УЗОР. Но это лишь первый ключ..."
	var new_mechanic: String = ""
	match level_num:
		1: body += "\n\nПодсказка: соберите кристаллы как на маленькой картинке слева вверху, затем нажмите ПРОВЕРИТЬ УЗОР."
		2: new_mechanic = "НОВОЕ: Стрелки на нитях! Допустимое расположение должно сохранять направления стрелок."
		3: new_mechanic = "НОВОЕ: Разные цвета! Кристаллы могут оказаться только там, где подходит цвет."
		4: body += "\n\nПомните: стрелки должны указывать в ту же сторону после обмена."
		5: new_mechanic = "НОВОЕ: Кнопка СКОМБИНИРОВАТЬ! Найдя 2+ ключа, комбинируйте их для открытия новых."
		7: body += "\n\nЭтот граф выглядит неправильным — но присмотритесь к цветам."
		8: body += "\n\nДва отдельных скопления. Одинаковы ли они изнутри?"
		9: body += "\n\nТолстые связи объединяют кристаллы в пары. Можно ли поменять целые пары?"
		10: new_mechanic = "НОВОЕ: После решения вы увидите, какие ключи — мастер-ключи, минимальный набор, порождающий все остальные."
		_:
			if has_cayley and level_num > 5:
				body += "\n\nИспользуйте СКОМБИНИРОВАТЬ, чтобы создать новые расстановки из уже найденных."
			if has_generators and level_num > 10:
				body += "\n\nИщите мастер-ключи — минимум ходов, порождающих всё остальное."
	return {"body": body, "new_mechanic": new_mechanic}


static func get_generators_text(level_data: Dictionary, target_perm_names: Dictionary) -> String:
	var symmetries_data = level_data.get("symmetries", {})
	var generator_ids: Array = symmetries_data.get("generators", [])
	if generator_ids.is_empty(): return ""
	var gen_names: Array = []
	for gen_id in generator_ids:
		gen_names.append(target_perm_names.get(gen_id, gen_id))
	var names_str := ", ".join(gen_names)
	if generator_ids.size() == 1:
		return "Мастер-ключ: %s — повторяя его, можно получить все остальные ключи." % names_str
	else:
		return "Мастер-ключи: %s — комбинируя эти %d хода, можно получить все остальные." % [names_str, generator_ids.size()]
