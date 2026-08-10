extends RefCounted

const CONFIG_PATH := "res://data/ranks.json"

var config: Dictionary = {}


func _init() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("无法读取军衔与功勋配置")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	config = parsed if parsed is Dictionary else {}


func tier_for(category: String, points: int) -> Dictionary:
	var result: Dictionary = {}
	var tiers: Variant = config.get(category, [])
	if not tiers is Array:
		return result
	for raw_tier: Variant in tiers:
		if raw_tier is Dictionary and points >= int(raw_tier.get("threshold", 0)):
			result = raw_tier
	return result.duplicate(true)


func next_tier(category: String, points: int) -> Dictionary:
	var tiers: Variant = config.get(category, [])
	if not tiers is Array:
		return {}
	for raw_tier: Variant in tiers:
		if raw_tier is Dictionary and points < int(raw_tier.get("threshold", 0)):
			return raw_tier.duplicate(true)
	return {}


func combat_power_bonus(military_merit: int, nobility_merit: int) -> int:
	return int(tier_for("military", military_merit).get("combat_power", 0)) + int(tier_for("nobility", nobility_merit).get("combat_power", 0))


func donation_result(available_gold: int, requested_gold: int) -> Dictionary:
	var unit_cost := int(config.get("gold_per_nobility_merit", 750000))
	var safe_request := mini(maxi(0, requested_gold), maxi(0, available_gold))
	var merit := int(safe_request / unit_cost)
	return {"gold_cost":merit * unit_cost, "nobility_merit":merit}


func rose_affection(rose_count: int) -> int:
	return int(config.get("rose_affection", {}).get(str(rose_count), 0))


func daily_task(task_id: String) -> Dictionary:
	var tasks: Variant = config.get("daily_tasks", {})
	if not tasks is Dictionary:
		return {}
	var task: Variant = tasks.get(task_id, {})
	return task.duplicate(true) if task is Dictionary else {}
