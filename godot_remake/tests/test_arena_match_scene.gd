extends Node

const LIN := "npc_adv_lin_xia"
const BattleSession = preload("res://scripts/battle_session.gd")

var _errors: Array = []


func _ready() -> void:
	if GameState == null:
		print("REGISTRY_FAIL: ERR_ARENA_NO_MATCH GameState missing")
		get_tree().quit(1)
		return
	_assert_illegal_and_no_match()
	_assert_practice()
	_assert_challenge_and_report()
	_assert_snapshot_freeze()
	_assert_bad_snapshot()
	_assert_dup_and_stale()
	_assert_season()
	_finish()


func _reset() -> void:
	GameState.expansion_state = GameState.expansion_state_service.default_enabled_state()
	GameState.current_day = 1
	GameState.refresh_rankings()


func _rel(adv_id: String) -> int:
	return int(GameState.expansion_state.get("relationships", {}).get(adv_id, {}).get("value", 0))


func _score() -> int:
	return int(GameState.expansion_state.get("rankings", {}).get("player_ratings", {}).get("arena_score", 0))


func _assert_illegal_and_no_match() -> void:
	_reset()
	var bad: Dictionary = GameState.begin_arena_match("zzz_no_such", "challenge", "bad_op")
	if bool(bad.get("success", false)):
		_fail("ERR_ARENA_BAD_OPPONENT", str(bad))
	var fake: Dictionary = GameState.settle_arena_match("match:none", true, "fake_settle")
	if bool(fake.get("success", false)):
		_fail("ERR_ARENA_NO_MATCH", str(fake))


func _assert_practice() -> void:
	_reset()
	var rel_before := _rel(LIN)
	var score_before := _score()
	var begun: Dictionary = GameState.begin_arena_match(LIN, "practice", "practice_1")
	if not bool(begun.get("success", false)):
		_fail("ERR_PRACTICE_SCORED", str(begun))
		return
	var settled: Dictionary = GameState.settle_arena_match(str(begun.get("match_id", "")), true, "practice_settle_1")
	if not bool(settled.get("success", false)):
		_fail("ERR_PRACTICE_SCORED", str(settled))
		return
	if int(settled.get("score_delta", -1)) != 0 or _score() != score_before:
		_fail("ERR_PRACTICE_SCORED", "practice changed score %s" % str(settled))
	if _rel(LIN) != rel_before:
		_fail("ERR_PRACTICE_SCORED", "practice changed relationship")


func _assert_challenge_and_report() -> void:
	_reset()
	var rel_before := _rel(LIN)
	var score_before := _score()
	var begun: Dictionary = GameState.begin_arena_match(LIN, "challenge", "challenge_1")
	if not bool(begun.get("success", false)):
		_fail("ERR_REPORT_MISMATCH", str(begun))
		return
	var settled: Dictionary = GameState.settle_arena_match(str(begun.get("match_id", "")), true, "challenge_settle_1")
	if not bool(settled.get("success", false)):
		_fail("ERR_REPORT_MISMATCH", str(settled))
		return
	if int(settled.get("score_delta", 0)) != 10 or _score() != score_before + 10:
		_fail("ERR_REPORT_MISMATCH", "challenge score %s now=%d" % [str(settled), _score()])
	if _rel(LIN) != rel_before + 2:
		_fail("ERR_REPORT_MISMATCH", "relationship %d" % _rel(LIN))
	var reports: Array = GameState.get_arena_reports()
	if reports.is_empty():
		_fail("ERR_REPORT_MISMATCH", "no report")
		return
	var report: Dictionary = reports[reports.size() - 1]
	if int(report.get("score_delta", -1)) != int(settled.get("score_delta", 0)):
		_fail("ERR_REPORT_MISMATCH", "report %s ledger %s" % [str(report.get("score_delta")), str(settled.get("score_delta"))])
	var replay: Dictionary = GameState.settle_arena_match(str(begun.get("match_id", "")), true, "challenge_settle_1")
	if not bool(replay.get("replayed", false)):
		_fail("ERR_ARENA_DUP_SETTLE", "same op not replayed")
	if _score() != score_before + 10:
		_fail("ERR_ARENA_DUP_SETTLE", "replay added score")


func _assert_snapshot_freeze() -> void:
	_reset()
	var begun: Dictionary = GameState.begin_arena_match(LIN, "challenge", "snap_1")
	var overlay: Dictionary = GameState.arena_combat_overlay(str(begun.get("monster_id", "")))
	var frozen := int(overlay.get("combat_power", 0))
	var state: Dictionary = GameState.expansion_state.duplicate(true)
	var adventurers: Dictionary = (state.get("adventurers", {}) as Dictionary).duplicate(true)
	var runtime: Dictionary = (adventurers.get(LIN, {}) as Dictionary).duplicate(true)
	runtime["gear_bonus"] = 999
	adventurers[LIN] = runtime
	state["adventurers"] = adventurers
	GameState.expansion_state = state
	var session = BattleSession.new(str(begun.get("monster_id", "")), GameState.get_player_stats())
	if int(session.monster.get("combat_power", -1)) != frozen:
		_fail("ERR_ARENA_BAD_SNAPSHOT", "live gear leaked into session %s frozen=%d" % [str(session.monster.get("combat_power")), frozen])
	GameState.abandon_active_arena_match("snap_cleanup")


func _assert_bad_snapshot() -> void:
	_reset()
	var begun: Dictionary = GameState.begin_arena_match(LIN, "challenge", "bad_snap_1")
	var state: Dictionary = GameState.expansion_state.duplicate(true)
	var rankings: Dictionary = (state.get("rankings", {}) as Dictionary).duplicate(true)
	var matches: Array = rankings.get("matches", []).duplicate(true)
	if not matches.is_empty() and matches[matches.size() - 1] is Dictionary:
		var match_row: Dictionary = (matches[matches.size() - 1] as Dictionary).duplicate(true)
		var snap: Dictionary = (match_row.get("opponent_snapshot", {}) as Dictionary).duplicate(true)
		var combat: Dictionary = (snap.get("combat", {}) as Dictionary).duplicate(true)
		combat["max_hp"] = 0
		snap["combat"] = combat
		match_row["opponent_snapshot"] = snap
		matches[matches.size() - 1] = match_row
		rankings["matches"] = matches
		state["rankings"] = rankings
		GameState.expansion_state = state
	var settled: Dictionary = GameState.settle_arena_match(str(begun.get("match_id", "")), true, "bad_snap_settle")
	if bool(settled.get("success", false)):
		_fail("ERR_ARENA_BAD_SNAPSHOT", "zero hp snapshot accepted")
	GameState.abandon_active_arena_match("bad_snap_cleanup")


func _assert_dup_and_stale() -> void:
	_reset()
	var begun: Dictionary = GameState.begin_arena_match(LIN, "challenge", "dup_1")
	var mid := str(begun.get("match_id", ""))
	var first: Dictionary = GameState.settle_arena_match(mid, true, "dup_settle_a")
	if not bool(first.get("success", false)):
		_fail("ERR_ARENA_DUP_SETTLE", str(first))
		return
	var score_after := _score()
	var second: Dictionary = GameState.settle_arena_match(mid, true, "dup_settle_b")
	if bool(second.get("success", false)):
		_fail("ERR_ARENA_DUP_SETTLE", "second settle accepted")
	if _score() != score_after:
		_fail("ERR_ARENA_DUP_SETTLE", "second settle added score")
	_reset()
	var begun2: Dictionary = GameState.begin_arena_match(LIN, "challenge", "stale_1")
	var stale: Dictionary = GameState.expansion_state_service.arena_service.settle(
		GameState.expansion_state, str(begun2.get("match_id", "")), true, 0, "stale_settle")
	if bool(stale.get("success", false)):
		_fail("ERR_ARENA_STALE_SESSION", str(stale))
	GameState.abandon_active_arena_match("stale_cleanup")


func _assert_season() -> void:
	_reset()
	var score_before := _score()
	var begun: Dictionary = GameState.begin_arena_match(LIN, "season", "season_1")
	var settled: Dictionary = GameState.settle_arena_match(str(begun.get("match_id", "")), true, "season_settle_1")
	if not bool(settled.get("success", false)):
		_fail("ERR_ARENA_NO_MATCH", str(settled))
		return
	if _score() != score_before:
		_fail("ERR_PRACTICE_SCORED", "season changed score")
	var schedule: Array = GameState.expansion_state.get("season", {}).get("arena_seed_state", {}).get("matches", [])
	if schedule.size() != 1:
		_fail("ERR_ARENA_NO_MATCH", "season schedule %d" % schedule.size())


func _fail(code: String, detail: String) -> void:
	_errors.append("%s %s" % [code, detail])


func _finish() -> void:
	if _errors.size() > 0:
		print("REGISTRY_FAIL: " + "; ".join(_errors))
		get_tree().quit(1)
		return
	print("PASS arena: practice no score, challenge +10/+2, snapshot freeze, dup/stale, season schedule")
	get_tree().quit(0)
