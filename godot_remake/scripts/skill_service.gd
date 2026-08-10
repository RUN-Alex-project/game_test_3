extends RefCounted

const DATABASE_PATH := "res://data/skills.json"

var skills: Dictionary = {}
var books: Dictionary = {}


func _init() -> void:
	var file := FileAccess.open(DATABASE_PATH, FileAccess.READ)
	if file == null:
		push_error("无法读取技能数据库")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		return
	for raw_skill: Variant in parsed:
		if not raw_skill is Dictionary:
			continue
		var skill_id := str(raw_skill.get("id", ""))
		skills[skill_id] = raw_skill
		for book_id: String in raw_skill.get("books", {}):
			books[book_id] = {"skill_id":skill_id, "rank":int(raw_skill.books[book_id])}


func normalize_learned(raw_learned: Dictionary) -> Dictionary:
	var result := {}
	for skill_id: String in skills:
		var rank := maxi(0, int(raw_learned.get(skill_id, 0)))
		if rank > 0:
			result[skill_id] = rank
	return result


func learn_result(learned: Dictionary, book_item_id: String) -> Dictionary:
	if not books.has(book_item_id):
		return {"success":false, "reason":"not_skill_book", "learned":normalize_learned(learned)}
	var result := normalize_learned(learned)
	var book: Dictionary = books[book_item_id]
	var skill_id := str(book.skill_id)
	var rank := int(book.rank)
	if int(result.get(skill_id, 0)) >= rank:
		return {"success":false, "reason":"already_learned", "learned":result}
	result[skill_id] = rank
	return {"success":true, "skill_id":skill_id, "rank":rank, "learned":result}


func combat_power_percent(learned: Dictionary) -> float:
	var rank := int(learned.get("fighting_spirit", 0))
	return float(skills.get("fighting_spirit", {}).get("combat_power_percent_by_rank", {}).get(str(rank), 0.0))


func active_damage_multiplier(learned: Dictionary, skill_id: String) -> float:
	if not skills.has(skill_id) or skills[skill_id].get("type", "") != "active":
		return 1.0
	var rank := int(learned.get(skill_id, 0))
	return float(skills[skill_id].get("damage_multiplier_by_rank", {}).get(str(rank), 1.0))


func learned_active_skills(learned: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for skill_id: String in skills:
		if skills[skill_id].get("type", "") == "active" and int(learned.get(skill_id, 0)) > 0:
			result.append(skill_id)
	return result


func unlock_relationship_skills(learned: Dictionary, affection: int) -> Dictionary:
	var result := normalize_learned(learned)
	for skill_id: String in skills:
		var definition: Dictionary = skills[skill_id]
		var unlocks: Dictionary = definition.get("affection_unlocks", {})
		for threshold_text: String in unlocks:
			if affection >= int(threshold_text):
				result[skill_id] = maxi(int(result.get(skill_id, 0)), int(unlocks[threshold_text]))
	return result


func utility_success_chance(learned: Dictionary, skill_id: String) -> float:
	if not skills.has(skill_id) or skills[skill_id].get("type", "") != "utility":
		return 0.0
	var rank := int(learned.get(skill_id, 0))
	return float(skills[skill_id].get("success_chance_by_rank", {}).get(str(rank), 0.0))


func utility_luck_bonus(learned: Dictionary, skill_id: String) -> int:
	if not skills.has(skill_id) or skills[skill_id].get("type", "") != "utility":
		return 0
	var rank := int(learned.get(skill_id, 0))
	return int(skills[skill_id].get("luck_bonus_by_rank", {}).get(str(rank), 0))
