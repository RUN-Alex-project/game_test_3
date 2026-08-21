extends RefCounted

const REWARD_PATH := "res://data/abyss_rewards.json"
const RelationshipServiceScript = preload("res://scripts/relationship_service.gd")
const MailServiceScript = preload("res://scripts/mail_service.gd")
const SKIP_EPILOGUE_DUP := true
const BLOCK_NEG_REWARD := true

var rewards: Dictionary = {}
var relationship_service = RelationshipServiceScript.new()
var mail_service = MailServiceScript.new()


func _init() -> void:
	var file := FileAccess.open(REWARD_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	rewards = parsed if parsed is Dictionary else {}


func validate_reward(spec: Dictionary) -> Dictionary:
	if BLOCK_NEG_REWARD and int(spec.get("gold", 0)) < 0:
		return {"success": false, "code": "FINALE_NEG_REWARD"}
	if BLOCK_NEG_REWARD and int(spec.get("qty", 0)) < 0:
		return {"success": false, "code": "FINALE_NEG_REWARD"}
	return {"success": true, "code": "OK"}


func commit(expansion: Dictionary, day: int, operation_id: String, allies: Array) -> Dictionary:
	var chapters: Dictionary = (expansion.get("chapters", {}) as Dictionary).duplicate(true)
	var row: Dictionary = (chapters.get("abyss_finale", {}) as Dictionary).duplicate(true)
	if SKIP_EPILOGUE_DUP and str(row.get("epilogue_status", "")) == "done":
		return {"success": false, "code": "FINALE_EPILOGUE_DUP", "expansion": expansion}
	if SKIP_EPILOGUE_DUP and str(row.get("stage", "")) != "epilogue_pending":
		return {"success": false, "code": "FINALE_EPILOGUE_DUP", "expansion": expansion}
	var spec: Dictionary = rewards.get("one_time", {})
	var gate: Dictionary = validate_reward(spec)
	if not bool(gate.get("success", false)):
		gate["expansion"] = expansion
		return gate
	var state: Dictionary = expansion.duplicate(true)
	for ally in allies:
		var rel: Dictionary = relationship_service.apply_relationship_reward(
			state, str(ally), int(rewards.get("relationship_delta", 5)), day, "rel:%s:%s" % [operation_id, str(ally)], "abyss_epilogue")
		if bool(rel.get("success", false)):
			state = rel.expansion
	var mail: Dictionary = mail_service.enqueue_settlement_mail(
		state, "npc_adv_he_ming", "abyss_finale", day,
		[{"item_id": str(spec.get("item_id", "rose")), "quantity": int(spec.get("qty", 1)), "source": "abyss_epilogue"}])
	if bool(mail.get("success", false)):
		state = mail.expansion
	var rankings: Dictionary = (state.get("rankings", {}) as Dictionary).duplicate(true)
	var ratings: Dictionary = (rankings.get("player_ratings", {}) as Dictionary).duplicate(true)
	ratings["explore_score"] = int(ratings.get("explore_score", 0)) + int(rewards.get("explore_score_delta", 1))
	rankings["player_ratings"] = ratings
	state["rankings"] = rankings
	chapters = (state.get("chapters", {}) as Dictionary).duplicate(true)
	row = (chapters.get("abyss_finale", {}) as Dictionary).duplicate(true)
	row["stage"] = "completed"
	row["epilogue_status"] = "done"
	row["one_time_reward_claimed"] = true
	var ops: Dictionary = (row.get("operation_ids", {}) as Dictionary).duplicate(true)
	ops[operation_id] = true
	row["operation_ids"] = ops
	var ledger: Array = (row.get("abyss_ledger", []) as Array).duplicate()
	ledger.append({"op": "epilogue", "id": operation_id})
	row["abyss_ledger"] = ledger
	chapters["abyss_finale"] = row
	state["chapters"] = chapters
	return {
		"success": true,
		"code": "OK",
		"expansion": state,
		"gold": int(spec.get("gold", 0)),
		"item_id": str(spec.get("item_id", "")),
		"qty": int(spec.get("qty", 1)),
		"write_game_won": true,
	}
