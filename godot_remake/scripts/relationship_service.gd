extends RefCounted

const RULES_PATH := "res://data/relationship_rules.json"
const AdventurerServiceScript = preload("res://scripts/adventurer_service.gd")

var rules: Dictionary = {}
var adventurer_service = AdventurerServiceScript.new()


func _init() -> void:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null:
		push_error("????????")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	rules = parsed if parsed is Dictionary else {}


func default_runtime(adv_id: String) -> Dictionary:
	var profile: Dictionary = adventurer_service.get_adventurer(adv_id).get("relationship_profile", {})
	return {
		"value": int(profile.get("initial_value", 0)),
		"last_gift_day": 0,
		"history": [],
	}


func max_value() -> int:
	return int(rules.get("max_value", 1000))


func stage_for(points: int) -> Dictionary:
	var result := {}
	for raw_stage: Variant in rules.get("stages", []):
		if raw_stage is Dictionary and points >= int(raw_stage.get("threshold", 0)):
			result = raw_stage
	return result.duplicate(true) if result is Dictionary else {}


func next_stage(points: int) -> Dictionary:
	for raw_stage: Variant in rules.get("stages", []):
		if raw_stage is Dictionary and points < int(raw_stage.get("threshold", 0)):
			return raw_stage.duplicate(true)
	return {}


func gift_delta(adv_id: String, item_id: String) -> int:
	var base := int(rules.get("default_gift_delta", 1))
	var bonus := int(rules.get("preferred_gift_bonus", 0))
	var profile: Dictionary = adventurer_service.get_adventurer(adv_id).get("relationship_profile", {})
	var prefs: Array = profile.get("gift_preferences", [])
	if item_id in prefs:
		return base + bonus
	return base


func daily_limit(adv_id: String) -> int:
	var profile: Dictionary = adventurer_service.get_adventurer(adv_id).get("relationship_profile", {})
	return int(profile.get("daily_gift_limit", 1))


func apply_gift(expansion: Dictionary, adv_id: String, item_id: String, day: int, operation_id: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var relationships: Dictionary = state.get("relationships", {}).duplicate(true)
	if not relationships.has(adv_id):
		return {"success": false, "code": "ERR_UNKNOWN_ADV", "expansion": expansion}
	var rel: Dictionary = (relationships[adv_id] as Dictionary).duplicate(true)
	var history: Array = rel.get("history", []).duplicate()
	for raw_event: Variant in history:
		if raw_event is Dictionary and str(raw_event.get("operation_id", "")) == operation_id:
			return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	if int(rel.get("last_gift_day", 0)) == day:
		return {"success": false, "code": "ERR_GIFT_DAILY_LIMIT", "expansion": expansion}
	var before := int(rel.get("value", 0))
	var delta := gift_delta(adv_id, item_id)
	var after := clampi(before + delta, 0, max_value())
	rel["value"] = after
	rel["last_gift_day"] = day
	var adventurers: Dictionary = state.get("adventurers", {}).duplicate(true)
	var runtime: Dictionary = (adventurers.get(adv_id, {}) as Dictionary).duplicate(true)
	runtime["met"] = true
	adventurers[adv_id] = runtime
	history.append({
		"event_id": "gift:%s" % operation_id,
		"operation_id": operation_id,
		"day": day,
		"adventurer_id": adv_id,
		"delta": after - before,
		"before": before,
		"after": after,
		"reason": "gift:%s" % item_id,
		"source_type": "gift",
	})
	rel["history"] = history
	relationships[adv_id] = rel
	state["relationships"] = relationships
	state["adventurers"] = adventurers
	return {"success": true, "code": "OK", "expansion": state, "delta": after - before, "before": before, "after": after}


func apply_relationship_reward(expansion: Dictionary, adv_id: String, delta: int, day: int, operation_id: String, reason: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var relationships: Dictionary = state.get("relationships", {}).duplicate(true)
	if not relationships.has(adv_id):
		return {"success": false, "code": "ERR_UNKNOWN_ADV", "expansion": expansion}
	var rel: Dictionary = (relationships[adv_id] as Dictionary).duplicate(true)
	var history: Array = rel.get("history", []).duplicate()
	for raw_event: Variant in history:
		if raw_event is Dictionary and str(raw_event.get("operation_id", "")) == operation_id:
			return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	var before := int(rel.get("value", 0))
	var after := clampi(before + delta, 0, max_value())
	rel["value"] = after
	history.append({
		"event_id": "reward:%s" % operation_id,
		"operation_id": operation_id,
		"day": day,
		"adventurer_id": adv_id,
		"delta": after - before,
		"before": before,
		"after": after,
		"reason": reason,
		"source_type": "commission",
	})
	rel["history"] = history
	relationships[adv_id] = rel
	state["relationships"] = relationships
	return {"success": true, "code": "OK", "expansion": state, "before": before, "after": after}


func history_operation_ids_unique(expansion: Dictionary) -> bool:
	var seen: Dictionary = {}
	var relationships: Dictionary = expansion.get("relationships", {})
	for adv_id in relationships.keys():
		var rel: Variant = relationships[adv_id]
		if not rel is Dictionary:
			return false
		for raw_event: Variant in rel.get("history", []):
			if not raw_event is Dictionary:
				continue
			var op := str(raw_event.get("operation_id", ""))
			if op.is_empty():
				continue
			if seen.has(op):
				return false
			seen[op] = true
	return true


func validate_rules() -> Array[String]:
	var errors: Array[String] = []
	var stages: Variant = rules.get("stages", [])
	if not stages is Array or stages.size() < 2:
		errors.append("ERR_REL_STAGES ????")
		return errors
	var previous := -1
	for raw_stage: Variant in stages:
		if not raw_stage is Dictionary:
			errors.append("ERR_REL_STAGE_TYPE")
			continue
		var threshold := int(raw_stage.get("threshold", -1))
		if threshold <= previous and previous >= 0:
			errors.append("ERR_REL_THRESHOLD_ORDER not ascending: %d after %d" % [threshold, previous])
		if previous >= 0 and threshold < previous:
			errors.append("ERR_REL_THRESHOLD_ORDER not ascending: %d < %d" % [threshold, previous])
		previous = threshold
	return errors
