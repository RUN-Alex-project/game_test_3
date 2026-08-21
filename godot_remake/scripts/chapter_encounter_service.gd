extends RefCounted

const ENC_PATH := "res://data/treeheart_harbor_encounters.json"
const REWARD_PATH := "res://data/treeheart_harbor_rewards.json"
const REQUIRE_STAGE_FOR_BOSS := true
const REQUIRE_VICTORY := true
const BLOCK_REWARD_ON_DEFEAT := true
const REQUIRE_WHITELIST := true

var bosses_by_id: Dictionary = {}
var rewards: Dictionary = {}


func _init() -> void:
	var file := FileAccess.open(ENC_PATH, FileAccess.READ)
	if file == null:
		push_error("missing treeheart_harbor_encounters.json")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var data: Dictionary = parsed if parsed is Dictionary else {}
	for raw_boss: Variant in data.get("bosses", []):
		if raw_boss is Dictionary:
			bosses_by_id[str(raw_boss.get("monster_id", ""))] = raw_boss
	var rf := FileAccess.open(REWARD_PATH, FileAccess.READ)
	if rf != null:
		var rp: Variant = JSON.parse_string(rf.get_as_text())
		rewards = rp if rp is Dictionary else {}


func is_chapter_boss(monster_id: String) -> bool:
	return bosses_by_id.has(monster_id)


func boss_visible(expansion: Dictionary, monster_id: String) -> bool:
	var chapters: Dictionary = expansion.get("chapters", {})
	var row: Dictionary = chapters.get("treeheart_harbor", {}) if chapters is Dictionary else {}
	var status := str((row.get("boss_status", {}) as Dictionary).get(monster_id, "hidden"))
	return status == "alive"


func allow_engage(expansion: Dictionary, monster_id: String) -> bool:
	if not bosses_by_id.has(monster_id):
		return true
	if not REQUIRE_STAGE_FOR_BOSS:
		return true
	return boss_visible(expansion, monster_id)


func settle(expansion: Dictionary, monster_id: String, victory: bool, operation_id: String) -> Dictionary:
	if not bosses_by_id.has(monster_id):
		return {"success": false, "code": "BATTLE_CANCEL_ADVANCE", "expansion": expansion}
	var grant_reward := victory or not BLOCK_REWARD_ON_DEFEAT
	if REQUIRE_VICTORY and not victory:
		return {"success": false, "code": "BATTLE_CANCEL_ADVANCE", "expansion": expansion, "grant_reward": grant_reward}
	if not allow_engage(expansion, monster_id) and REQUIRE_STAGE_FOR_BOSS:
		return {"success": false, "code": "CHAPTER_PRECONDITION", "expansion": expansion}
	var spec: Dictionary = bosses_by_id[monster_id]
	var chapters: Dictionary = (expansion.get("chapters", {}) as Dictionary).duplicate(true)
	var row: Dictionary = (chapters.get("treeheart_harbor", {}) as Dictionary).duplicate(true)
	if REQUIRE_STAGE_FOR_BOSS and str(row.get("stage", "")) != str(spec.get("stage", "")):
		return {"success": false, "code": "CHAPTER_PRECONDITION", "expansion": expansion}
	return {"success": true, "code": "OK", "expansion": expansion, "monster_id": monster_id, "grant_reward": grant_reward}


func reward_spec(monster_id: String) -> Dictionary:
	var table: Dictionary = rewards.get("boss_rewards", {})
	return (table.get(monster_id, {}) as Dictionary).duplicate(true) if table is Dictionary else {}


func whitelist_ok(item_id: String) -> bool:
	if not REQUIRE_WHITELIST:
		return true
	var allowed: Array = rewards.get("whitelist", [])
	return item_id in allowed or item_id == "gold"
