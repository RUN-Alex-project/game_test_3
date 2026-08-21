extends RefCounted

const PATH := "res://data/element_consumables.json"
const REQUIRE_BATTLE_CTX := true
const SKIP_SAME_BATTLE := true
const SKIP_SAME_DAY := true
const REQUIRE_WHITELIST := true

var data: Dictionary = {}


func _init() -> void:
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	data = parsed if parsed is Dictionary else {}


func use(expansion: Dictionary, item_id: String, in_battle: bool, session_id: String, day: int, have_qty: int) -> Dictionary:
	var allowed: Array = data.get("whitelist", [])
	if REQUIRE_WHITELIST and not item_id in allowed:
		return {"success": false, "code": "ELEMENT_CONSUMABLE_CTX", "expansion": expansion, "consume": false}
	if REQUIRE_BATTLE_CTX and not in_battle:
		return {"success": false, "code": "ELEMENT_CONSUMABLE_CTX", "expansion": expansion, "consume": false}
	if have_qty < 1:
		return {"success": false, "code": "ELEMENT_CONSUMABLE_CTX", "expansion": expansion, "consume": false}
	var chapters: Dictionary = (expansion.get("chapters", {}) as Dictionary).duplicate(true)
	var row: Dictionary = (chapters.get("ice_element", {}) as Dictionary).duplicate(true)
	var cd: Dictionary = (row.get("consumable_cd", {}) as Dictionary).duplicate(true)
	var slot: Dictionary = (cd.get(item_id, {}) as Dictionary).duplicate(true)
	if SKIP_SAME_BATTLE and not session_id.is_empty() and str(slot.get("session", "")) == session_id:
		return {"success": false, "code": "ELEMENT_CONSUMABLE_CD", "expansion": expansion, "consume": false}
	if SKIP_SAME_DAY and int(slot.get("day", 0)) == day:
		return {"success": false, "code": "ELEMENT_CONSUMABLE_CD", "expansion": expansion, "consume": false}
	var items: Dictionary = data.get("items", {})
	var spec: Dictionary = items.get(item_id, {}) if items is Dictionary else {}
	slot["session"] = session_id
	slot["day"] = day
	cd[item_id] = slot
	row["consumable_cd"] = cd
	row["attacker_charge"] = str(spec.get("element", ""))
	var claims: Dictionary = (row.get("reward_claims", {}) as Dictionary).duplicate(true)
	chapters["ice_element"] = row
	var state: Dictionary = expansion.duplicate(true)
	state["chapters"] = chapters
	return {"success": true, "code": "OK", "expansion": state, "consume": true, "element": str(spec.get("element", "")), "claims": claims}
