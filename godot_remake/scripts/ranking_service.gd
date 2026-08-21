extends RefCounted

const RULES_PATH := "res://data/ranking_rules.json"
const AdventurerServiceScript = preload("res://scripts/adventurer_service.gd")
const BattleSnapshotServiceScript = preload("res://scripts/battle_snapshot_service.gd")

## Mutation hook for v1.45 N9. Production stays true.
const USE_STABLE_ID_TIEBREAK := true

const REQUIRED_BOARDS := [
	"combat_power", "pet", "arena", "explore", "merchant_reputation", "territory_contribution",
]

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


func default_rankings() -> Dictionary:
	return {
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


func normalize(raw: Variant) -> Dictionary:
	var base: Dictionary = default_rankings()
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


func validate_rules() -> Array[String]:
	var errors: Array[String] = []
	var boards: Array = rules.get("boards", [])
	var seen: Dictionary = {}
	for raw_board: Variant in boards:
		if not raw_board is Dictionary:
			errors.append("ERR_RANK_BOARD_MISSING bad board")
			continue
		var board_id := str(raw_board.get("id", ""))
		if board_id.is_empty() or seen.has(board_id):
			errors.append("ERR_RANK_BOARD_MISSING dup %s" % board_id)
		seen[board_id] = true
	for board_id in REQUIRED_BOARDS:
		if not seen.has(board_id):
			errors.append("ERR_RANK_BOARD_MISSING %s" % board_id)
	return errors


func rebuild(expansion: Dictionary, player_row: Dictionary, day: int) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var rankings: Dictionary = normalize(state.get("rankings", {}))
	var rows: Array = []
	var player: Dictionary = player_row.duplicate(true)
	player["id"] = "player"
	player["stable_id"] = "player"
	rows.append(player)
	for adv_id in adventurer_service.all_ids():
		rows.append(snapshot_service.npc_ratings(state, adv_id))
	var boards_out: Dictionary = {}
	for raw_board: Variant in rules.get("boards", []):
		if not raw_board is Dictionary:
			continue
		var board_id := str(raw_board.get("id", ""))
		var previous: Dictionary = {}
		var old_board: Variant = rankings.get("boards", {}).get(board_id, {})
		if old_board is Dictionary:
			for raw_entry: Variant in old_board.get("entries", []):
				if raw_entry is Dictionary:
					previous[str(raw_entry.get("id", ""))] = int(raw_entry.get("rank", 0))
		var ranked: Array = _sort_rows(rows, str(raw_board.get("primary", "")), str(raw_board.get("secondary", "")))
		var entries: Array = []
		for index in ranked.size():
			var row: Dictionary = ranked[index]
			var entry_id := str(row.get("id", ""))
			var rank := index + 1
			var prev := int(previous.get(entry_id, 0))
			var reason := "new"
			if prev == rank:
				reason = "unchanged"
			elif prev == 0:
				reason = "new"
			elif prev > rank:
				reason = "value_up"
			else:
				reason = "value_down"
			if bool(raw_board.get("preview", false)):
				reason = str(raw_board.get("preview_reason", "preview"))
			entries.append({
				"id": entry_id,
				"rank": rank,
				"primary": int(row.get(str(raw_board.get("primary", "")), 0)),
				"secondary": int(row.get(str(raw_board.get("secondary", "")), 0)),
				"previous_rank": prev,
				"change_reason": reason,
			})
		boards_out[board_id] = {
			"id": board_id,
			"updated_day": day,
			"preview": bool(raw_board.get("preview", false)),
			"entries": entries,
		}
	rankings["boards"] = boards_out
	var player_ratings: Dictionary = rankings.get("player_ratings", {})
	if not player_ratings is Dictionary:
		player_ratings = {}
	player_ratings["arena_score"] = int(player.get("arena_score", 0))
	player_ratings["explore_score"] = int(player.get("explore_score", 0))
	player_ratings["merchant_reputation"] = int(player.get("merchant_reputation", 0))
	player_ratings["territory_contribution"] = int(player.get("territory_contribution", 0))
	rankings["player_ratings"] = player_ratings
	state["rankings"] = rankings
	return {"success": true, "expansion": state}


func _sort_rows(rows: Array, primary: String, secondary: String) -> Array:
	var copy: Array = []
	for raw_row: Variant in rows:
		if raw_row is Dictionary:
			copy.append(raw_row)
	copy.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := int(a.get(primary, 0))
		var pb := int(b.get(primary, 0))
		if pa != pb:
			return pa > pb
		var sa := int(a.get(secondary, 0))
		var sb := int(b.get(secondary, 0))
		if sa != sb:
			return sa > sb
		if USE_STABLE_ID_TIEBREAK:
			return str(a.get("stable_id", "")) < str(b.get("stable_id", ""))
		return str(a.get("id", "")) > str(b.get("id", ""))
	)
	return copy
