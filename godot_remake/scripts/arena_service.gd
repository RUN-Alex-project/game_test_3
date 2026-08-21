extends RefCounted

const RULES_PATH := "res://data/arena_rules.json"
const AdventurerServiceScript = preload("res://scripts/adventurer_service.gd")
const BattleSnapshotServiceScript = preload("res://scripts/battle_snapshot_service.gd")

## Mutation hooks for v1.45 negatives. Production stays in the signed-safe state.
const PRACTICE_AFFECTS_SCORE := false
const REQUIRE_SNAPSHOT_FIELDS := true
const REQUIRE_SESSION_TOKEN := true
const REQUIRE_KNOWN_OPPONENT := true
const REQUIRE_EXISTING_MATCH := true
const BLOCK_DUP_SETTLE := true
const WRITE_REPORT_DELTA := true

var rules: Dictionary = {}
var adventurer_service = AdventurerServiceScript.new()
var snapshot_service = BattleSnapshotServiceScript.new()


func _init() -> void:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	rules = parsed if parsed is Dictionary else {}


func _normalize_rankings(raw: Variant) -> Dictionary:
	var base := {
		"boards": {},
		"matches": [],
		"reports": [],
		"active_match_id": "",
		"session_token": 0,
		"player_ratings": {
			"explore_score": 0,
			"arena_score": 0,
			"merchant_reputation": 0,
			"territory_contribution": 0,
		},
		"visited_maps": {},
	}
	if not raw is Dictionary:
		return base
	var incoming: Dictionary = raw
	for key in ["boards", "player_ratings", "visited_maps"]:
		if incoming.get(key) is Dictionary:
			base[key] = (incoming[key] as Dictionary).duplicate(true)
	for key in ["matches", "reports"]:
		if incoming.get(key) is Array:
			base[key] = (incoming[key] as Array).duplicate(true)
	base["active_match_id"] = str(incoming.get("active_match_id", ""))
	base["session_token"] = int(incoming.get("session_token", 0))
	return base


func mode_rules(mode: String) -> Dictionary:
	var modes: Dictionary = rules.get("modes", {})
	var raw: Variant = modes.get(mode, {})
	return raw.duplicate(true) if raw is Dictionary else {}


func validate_rules() -> Array[String]:
	var errors: Array[String] = []
	if int(rules.get("min_score", 0)) < 0:
		errors.append("ERR_ARENA_SCORE_RANGE min")
	if int(rules.get("max_score", 0)) < int(rules.get("min_score", 0)):
		errors.append("ERR_ARENA_SCORE_RANGE max")
	for mode_id in ["practice", "challenge", "season"]:
		var mode: Dictionary = mode_rules(mode_id)
		if mode.is_empty():
			errors.append("ERR_ARENA_BAD_OPPONENT missing mode %s" % mode_id)
			continue
		if int(mode.get("score_win", 0)) < 0 or int(mode.get("relationship_delta", 0)) < 0:
			errors.append("ERR_ARENA_SCORE_RANGE %s" % mode_id)
	return errors


func begin_match(expansion: Dictionary, adv_id: String, mode: String, day: int, operation_id: String, player_snapshot: Dictionary, session_token: int) -> Dictionary:
	if REQUIRE_KNOWN_OPPONENT and not adventurer_service.roster.has(adv_id):
		return {"success": false, "code": "ERR_ARENA_BAD_OPPONENT", "expansion": expansion}
	var spec: Dictionary = mode_rules(mode)
	if spec.is_empty():
		return {"success": false, "code": "ERR_ARENA_BAD_OPPONENT", "expansion": expansion}
	var state: Dictionary = expansion.duplicate(true)
	var rankings: Dictionary = _normalize_rankings(state.get("rankings", {}))
	for raw_match: Variant in rankings.get("matches", []):
		if raw_match is Dictionary and str(raw_match.get("operation_id", "")) == operation_id:
			return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true, "match_id": str(raw_match.get("match_id", ""))}
	if str(rankings.get("active_match_id", "")) != "":
		return {"success": false, "code": "ERR_ARENA_BUSY", "expansion": expansion}
	var combat: Dictionary = snapshot_service.npc_combat(state, adv_id)
	if combat.is_empty():
		if REQUIRE_KNOWN_OPPONENT:
			return {"success": false, "code": "ERR_ARENA_BAD_SNAPSHOT", "expansion": expansion}
		combat = {
			"id": snapshot_service.monster_id_for(adv_id),
			"name": adv_id,
			"level": 1,
			"max_hp": 1,
			"attack": 1,
			"defense": 1,
			"combat_power": 1,
			"is_boss": true,
		}
	if REQUIRE_SNAPSHOT_FIELDS and int(combat.get("max_hp", 0)) <= 0:
		return {"success": false, "code": "ERR_ARENA_BAD_SNAPSHOT", "expansion": expansion}
	var match_id := "match:%s:%s:%s" % [mode, adv_id, operation_id]
	var match_row := {
		"match_id": match_id,
		"operation_id": operation_id,
		"day": day,
		"mode": mode,
		"player_snapshot": player_snapshot.duplicate(true),
		"opponent_snapshot": {
			"adventurer_id": adv_id,
			"monster_id": snapshot_service.monster_id_for(adv_id),
			"combat": combat,
		},
		"result": "",
		"score_delta": 0,
		"relationship_delta": 0,
		"settled": false,
		"abandoned": false,
		"session_token": session_token,
	}
	var matches: Array = rankings.get("matches", [])
	matches.append(match_row)
	rankings["matches"] = matches
	rankings["active_match_id"] = match_id
	rankings["session_token"] = session_token
	state["rankings"] = rankings
	return {"success": true, "code": "OK", "expansion": state, "match_id": match_id, "monster_id": str(combat.get("id", ""))}


func settle(expansion: Dictionary, match_id: String, victory: bool, session_token: int, operation_id: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var rankings: Dictionary = _normalize_rankings(state.get("rankings", {}))
	var found := -1
	for index in rankings.get("matches", []).size():
		var raw_match: Variant = rankings["matches"][index]
		if raw_match is Dictionary and str(raw_match.get("match_id", "")) == match_id:
			found = index
			break
	if found < 0:
		if REQUIRE_EXISTING_MATCH:
			return {"success": false, "code": "ERR_ARENA_NO_MATCH", "expansion": expansion}
		return {"success": true, "code": "OK", "expansion": expansion, "score_delta": 10, "relationship_delta": 0, "adventurer_id": "", "mode": "challenge"}
	var match_row: Dictionary = (rankings["matches"][found] as Dictionary).duplicate(true)
	if str(match_row.get("settle_operation_id", "")) == operation_id and bool(match_row.get("settled", false)):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true, "score_delta": 0}
	if BLOCK_DUP_SETTLE and bool(match_row.get("settled", false)):
		return {"success": false, "code": "ERR_ARENA_DUP_SETTLE", "expansion": expansion}
	if bool(match_row.get("abandoned", false)):
		return {"success": false, "code": "ERR_ARENA_STALE_SESSION", "expansion": expansion}
	if REQUIRE_SESSION_TOKEN and int(match_row.get("session_token", 0)) != session_token:
		return {"success": false, "code": "ERR_ARENA_STALE_SESSION", "expansion": expansion}
	if not victory:
		return {"success": false, "code": "ERR_ARENA_NOT_VICTORY", "expansion": expansion}
	var snap: Dictionary = match_row.get("opponent_snapshot", {})
	if REQUIRE_SNAPSHOT_FIELDS:
		var combat: Dictionary = snap.get("combat", {})
		if not combat is Dictionary or int(combat.get("max_hp", 0)) <= 0 or str(snap.get("adventurer_id", "")).is_empty():
			return {"success": false, "code": "ERR_ARENA_BAD_SNAPSHOT", "expansion": expansion}
	var spec: Dictionary = mode_rules(str(match_row.get("mode", "")))
	var score_delta := 0
	var rel_delta := 0
	var affects := bool(spec.get("affects_score", false))
	if str(match_row.get("mode", "")) == "practice" and PRACTICE_AFFECTS_SCORE:
		affects = true
	if affects:
		score_delta = int(spec.get("score_win", 0))
		if str(match_row.get("mode", "")) == "practice" and PRACTICE_AFFECTS_SCORE:
			score_delta = 10
		rel_delta = int(spec.get("relationship_delta", 0))
	if score_delta < int(rules.get("min_score", 0)) and score_delta != 0:
		return {"success": false, "code": "ERR_ARENA_SCORE_RANGE", "expansion": expansion}
	var player_ratings: Dictionary = rankings.get("player_ratings", {})
	if not player_ratings is Dictionary:
		player_ratings = {}
	var before_score := int(player_ratings.get("arena_score", 0))
	var after_score := clampi(before_score + score_delta, int(rules.get("min_score", 0)), int(rules.get("max_score", 9999)))
	player_ratings["arena_score"] = after_score
	rankings["player_ratings"] = player_ratings
	match_row["result"] = "win"
	match_row["score_delta"] = after_score - before_score
	match_row["relationship_delta"] = rel_delta
	match_row["settled"] = true
	match_row["settle_operation_id"] = operation_id
	rankings["matches"][found] = match_row
	rankings["active_match_id"] = ""
	var reports: Array = rankings.get("reports", [])
	var report_delta := int(match_row.get("score_delta", 0)) if WRITE_REPORT_DELTA else 0
	reports.append({
		"match_id": match_id,
		"mode": str(match_row.get("mode", "")),
		"opponent_id": str(snap.get("adventurer_id", "")),
		"result": "win",
		"score_delta": report_delta,
		"relationship_delta": rel_delta,
		"player_power": int(match_row.get("player_snapshot", {}).get("combat_power", 0)),
		"opponent_power": int(snap.get("combat", {}).get("combat_power", 0)),
		"day": int(match_row.get("day", 0)),
	})
	rankings["reports"] = reports
	state["rankings"] = rankings
	if bool(spec.get("records_schedule", false)):
		var season: Dictionary = {}
		if state.get("season") is Dictionary:
			season = (state["season"] as Dictionary).duplicate(true)
		var seed_state: Dictionary = {}
		if season.get("arena_seed_state") is Dictionary:
			seed_state = (season["arena_seed_state"] as Dictionary).duplicate(true)
		var schedule: Array = seed_state.get("matches", [])
		schedule.append({
			"match_id": match_id,
			"day": int(match_row.get("day", 0)),
			"opponent_id": str(snap.get("adventurer_id", "")),
			"result": "win",
		})
		seed_state["matches"] = schedule
		season["arena_seed_state"] = seed_state
		state["season"] = season
	return {
		"success": true,
		"code": "OK",
		"expansion": state,
		"score_delta": int(match_row.get("score_delta", 0)),
		"relationship_delta": rel_delta,
		"adventurer_id": str(snap.get("adventurer_id", "")),
		"mode": str(match_row.get("mode", "")),
	}


func abandon(expansion: Dictionary, match_id: String, reason: String, session_token: int) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var rankings: Dictionary = _normalize_rankings(state.get("rankings", {}))
	var found := -1
	for index in rankings.get("matches", []).size():
		var raw_match: Variant = rankings["matches"][index]
		if raw_match is Dictionary and str(raw_match.get("match_id", "")) == match_id:
			found = index
			break
	if found < 0:
		return {"success": false, "code": "ERR_ARENA_NO_MATCH", "expansion": expansion}
	var match_row: Dictionary = (rankings["matches"][found] as Dictionary).duplicate(true)
	if bool(match_row.get("settled", false)) or bool(match_row.get("abandoned", false)):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	if REQUIRE_SESSION_TOKEN and int(match_row.get("session_token", 0)) != session_token:
		return {"success": false, "code": "ERR_ARENA_STALE_SESSION", "expansion": expansion}
	match_row["abandoned"] = true
	match_row["result"] = reason
	match_row["score_delta"] = 0
	rankings["matches"][found] = match_row
	rankings["active_match_id"] = ""
	state["rankings"] = rankings
	return {"success": true, "code": "OK", "expansion": state}


func overlay_for(expansion: Dictionary, monster_id: String) -> Dictionary:
	var rankings: Dictionary = _normalize_rankings(expansion.get("rankings", {}))
	var active := str(rankings.get("active_match_id", ""))
	if active.is_empty():
		return {}
	for raw_match: Variant in rankings.get("matches", []):
		if not raw_match is Dictionary:
			continue
		if str(raw_match.get("match_id", "")) != active:
			continue
		if bool(raw_match.get("abandoned", false)) or bool(raw_match.get("settled", false)):
			return {}
		var snap: Dictionary = raw_match.get("opponent_snapshot", {})
		if str(snap.get("monster_id", "")) != monster_id:
			return {}
		var combat: Variant = snap.get("combat", {})
		return combat.duplicate(true) if combat is Dictionary else {}
	return {}
