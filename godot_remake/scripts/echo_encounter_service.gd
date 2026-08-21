extends RefCounted

const ENC_PATH := "res://data/abyss_echoes.json"
const REQUIRE_STAGE_FOR_BOSS := true
const REQUIRE_VICTORY := true
const REQUIRE_SESSION := true
const REQUIRE_ALIVE := true
const REJECT_UNKNOWN_ECHO := true
const BLOCK_DIRECT_GAME_WON := true

var bosses_by_id: Dictionary = {}


func _init() -> void:
	var file := FileAccess.open(ENC_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var data: Dictionary = parsed if parsed is Dictionary else {}
	for raw: Variant in data.get("encounters", []):
		if raw is Dictionary:
			bosses_by_id[str(raw.get("monster_id", ""))] = raw


func is_abyss_unit(monster_id: String) -> bool:
	return bosses_by_id.has(monster_id)


func visible(expansion: Dictionary, monster_id: String) -> bool:
	var chapters: Dictionary = expansion.get("chapters", {})
	var row: Dictionary = chapters.get("abyss_finale", {}) if chapters is Dictionary else {}
	var status := str((row.get("boss_status", {}) as Dictionary).get(monster_id, "hidden"))
	return status == "alive"


func allow_engage(expansion: Dictionary, monster_id: String) -> bool:
	if not bosses_by_id.has(monster_id):
		if REJECT_UNKNOWN_ECHO:
			return false
		return true
	if not REQUIRE_STAGE_FOR_BOSS:
		return true
	return visible(expansion, monster_id)


func settle(expansion: Dictionary, monster_id: String, victory: bool, session_id: String, player_dead: bool) -> Dictionary:
	if not bosses_by_id.has(monster_id):
		if REJECT_UNKNOWN_ECHO:
			return {"success": false, "code": "ABYSS_ECHO_UNKNOWN", "expansion": expansion}
		return {"success": false, "code": "ABYSS_ECHO_UNKNOWN", "expansion": expansion}
	var chapters: Dictionary = expansion.get("chapters", {})
	var row: Dictionary = chapters.get("abyss_finale", {}) if chapters is Dictionary else {}
	if REQUIRE_SESSION and str(row.get("active_session_id", "")) != session_id:
		return {"success": false, "code": "ABYSS_SESSION", "expansion": expansion}
	if REQUIRE_ALIVE and player_dead:
		return {"success": false, "code": "ABYSS_DEATH", "expansion": expansion, "grant_reward": false}
	if REQUIRE_VICTORY and not victory:
		return {"success": false, "code": "BATTLE_CANCEL_ADVANCE", "expansion": expansion, "grant_reward": false}
	if REQUIRE_STAGE_FOR_BOSS and not visible(expansion, monster_id):
		return {"success": false, "code": "ABYSS_PRECONDITION", "expansion": expansion}
	var spec: Dictionary = bosses_by_id[monster_id]
	return {"success": true, "code": "OK", "expansion": expansion, "monster_id": monster_id, "kind": str(spec.get("kind", "echo"))}
