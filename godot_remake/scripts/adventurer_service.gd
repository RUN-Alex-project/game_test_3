extends RefCounted

const ROSTER_PATH := "res://data/adventurers.json"
const FIRST_COHORT_COUNT := 12

var roster: Dictionary = {}
var order: Array[String] = []


func _init() -> void:
	var file := FileAccess.open(ROSTER_PATH, FileAccess.READ)
	if file == null:
		push_error("???????????")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		push_error("?????????")
		return
	for raw_entry: Variant in parsed:
		if not raw_entry is Dictionary:
			continue
		var adv_id := str(raw_entry.get("id", ""))
		if adv_id.is_empty():
			continue
		roster[adv_id] = raw_entry
		order.append(adv_id)


func all_ids() -> Array[String]:
	return order.duplicate()


func get_adventurer(adv_id: String) -> Dictionary:
	var raw: Variant = roster.get(adv_id, {})
	return raw.duplicate(true) if raw is Dictionary else {}


func default_runtime(_adv_id: String) -> Dictionary:
	return {
		"met": false,
		"gear_bonus": 0,
		"pet_power": 0,
		"explore_score": 0,
		"arena_score": 0,
		"merchant_reputation": 0,
		"territory_contribution": 0,
	}


func validate_roster() -> Array[String]:
	var errors: Array[String] = []
	if order.size() != FIRST_COHORT_COUNT:
		errors.append("ERR_ADV_COUNT count %d != %d" % [order.size(), FIRST_COHORT_COUNT])
	var item_ids := _load_id_set("res://data/items.json")
	var seen: Dictionary = {}
	for adv_id in order:
		if seen.has(adv_id):
			errors.append("ERR_DUP_ADV_ID duplicate id: %s" % adv_id)
		seen[adv_id] = true
		var entry: Dictionary = roster[adv_id]
		if str(entry.get("source_classification", "")) != "singleplayer_extension":
			errors.append("ERR_ADV_CLASS %s not singleplayer_extension" % adv_id)
		if _is_backup_id(adv_id):
			errors.append("ERR_BACKUP_IN_PROD backup id: %s" % adv_id)
		var profile: Variant = entry.get("relationship_profile", {})
		if not profile is Dictionary:
			errors.append("ERR_ADV_PROFILE %s missing relationship_profile" % adv_id)
			continue
		for pref in profile.get("gift_preferences", []):
			var pref_id := str(pref)
			if pref_id.is_empty():
				errors.append("ERR_GIFT_PREF_EMPTY %s" % adv_id)
			elif not item_ids.has(pref_id):
				errors.append("ERR_GIFT_PREF_UNKNOWN %s pref=%s" % [adv_id, pref_id])
		var ledger: Variant = entry.get("initial_ledger", {})
		if not ledger is Dictionary:
			errors.append("ERR_LEDGER_TYPE %s" % adv_id)
		else:
			if int(ledger.get("gold", 0)) < 0 or int(ledger.get("daily_budget", 0)) < 0:
				errors.append("ERR_NEG_BUDGET %s" % adv_id)
			var items: Variant = ledger.get("items", {})
			if items is Dictionary:
				for item_id in items.keys():
					if not item_ids.has(str(item_id)):
						errors.append("ERR_LEDGER_UNKNOWN_ITEM %s item=%s" % [adv_id, str(item_id)])
			elif items is Array and not items.is_empty():
				errors.append("ERR_LEDGER_TYPE items array %s" % adv_id)
	return errors


func _is_backup_id(adv_id: String) -> bool:
	return adv_id.begins_with("npc_adv_b") and adv_id.substr(9).is_valid_int()


func _load_id_set(path: String) -> Dictionary:
	var ids := {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ids
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Array:
		for raw_entry: Variant in parsed:
			if raw_entry is Dictionary:
				var entry_id := str(raw_entry.get("id", ""))
				if not entry_id.is_empty():
					ids[entry_id] = true
	return ids
