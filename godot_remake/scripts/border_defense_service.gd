extends RefCounted

const ENC_PATH := "res://data/border_encounters.json"
const REQUIRE_STAGE_FOR_UNIT := true
const REQUIRE_VICTORY := true
const BLOCK_REWARD_ON_DEFEAT := true
const REQUIRE_SESSION := true
const BLOCK_DUP_OP := true

var units_by_id: Dictionary = {}


func _init() -> void:
	var file := FileAccess.open(ENC_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var data: Dictionary = parsed if parsed is Dictionary else {}
	for raw in data.get("units", []):
		if raw is Dictionary:
			units_by_id[str(raw.get("monster_id", ""))] = raw


func is_border_unit(monster_id: String) -> bool:
	return units_by_id.has(monster_id)


func unit_kind(monster_id: String) -> String:
	return str(units_by_id.get(monster_id, {}).get("kind", ""))


func visible(expansion: Dictionary, monster_id: String) -> bool:
	if not units_by_id.has(monster_id):
		return false
	var spec: Dictionary = units_by_id[monster_id]
	var row: Dictionary = expansion.get("chapters", {}).get("south_border", {}) if expansion.get("chapters") is Dictionary else {}
	var stage := str(row.get("stage", "locked"))
	if str(spec.get("kind", "")) == "boss":
		return str((row.get("boss_status", {}) as Dictionary).get(monster_id, "hidden")) == "alive"
	return stage == str(spec.get("stage", ""))


func allow_engage(expansion: Dictionary, monster_id: String) -> bool:
	if not REQUIRE_STAGE_FOR_UNIT:
		return true
	return visible(expansion, monster_id)


func begin_session(expansion: Dictionary, monster_id: String, session_id: String) -> Dictionary:
	if not units_by_id.has(monster_id):
		return {"success": false, "code": "BORDER_PRECONDITION", "expansion": expansion}
	if not allow_engage(expansion, monster_id):
		return {"success": false, "code": "BORDER_PRECONDITION", "expansion": expansion}
	var chapters: Dictionary = (expansion.get("chapters", {}) as Dictionary).duplicate(true)
	var row: Dictionary = (chapters.get("south_border", {}) as Dictionary).duplicate(true)
	row["active_session_id"] = session_id
	row["active_monster_id"] = monster_id
	chapters["south_border"] = row
	var state: Dictionary = expansion.duplicate(true)
	state["chapters"] = chapters
	return {"success": true, "code": "OK", "expansion": state, "session_id": session_id}


func settle(expansion: Dictionary, monster_id: String, victory: bool, session_id: String) -> Dictionary:
	if not units_by_id.has(monster_id):
		return {"success": false, "code": "BATTLE_CANCEL_ADVANCE", "expansion": expansion}
	var row: Dictionary = expansion.get("chapters", {}).get("south_border", {}) if expansion.get("chapters") is Dictionary else {}
	if REQUIRE_SESSION and str(row.get("active_session_id", "")) != session_id:
		return {"success": false, "code": "BORDER_SESSION", "expansion": expansion}
	var grant := victory or not BLOCK_REWARD_ON_DEFEAT
	if REQUIRE_VICTORY and not victory:
		return {"success": false, "code": "BATTLE_CANCEL_ADVANCE", "expansion": expansion, "grant_reward": grant}
	if REQUIRE_STAGE_FOR_UNIT and str(row.get("stage", "")) != str(units_by_id[monster_id].get("stage", "")):
		return {"success": false, "code": "BORDER_PRECONDITION", "expansion": expansion}
	if BLOCK_DUP_OP and str(units_by_id[monster_id].get("kind", "")) == "defense":
		var ops: Array = row.get("defense_ops", [])
		if monster_id in ops:
			return {"success": false, "code": "BORDER_DEFENSE_DUP", "expansion": expansion}
	return {"success": true, "code": "OK", "expansion": expansion, "monster_id": monster_id, "kind": unit_kind(monster_id), "grant_reward": grant}
