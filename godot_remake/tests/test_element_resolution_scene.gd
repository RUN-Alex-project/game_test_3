extends Node

const BattleSession = preload("res://scripts/battle_session.gd")

var _errors: Array = []


func _ready() -> void:
	_assert_rules()
	_assert_snapshot_battle()
	_assert_consumable()
	_assert_adjacent()
	_finish()


func _reset() -> void:
	GameState.expansion_state = GameState.expansion_state_service.default_enabled_state()
	GameState.current_day = 1
	GameState.gold = 10000
	GameState.player_current_hp = 550
	GameState._initialize_inventory()


func _assert_rules() -> void:
	_reset()
	var svc = GameState.expansion_state_service.element_resolution_service
	var fire_ice: Dictionary = svc.resolve({"base_damage": 100, "attacker_element": "fire", "defender_element": "ice", "resist": 0, "monster_id": "ice_lab_boss"})
	var ice_fire: Dictionary = svc.resolve({"base_damage": 100, "attacker_element": "ice", "defender_element": "fire", "resist": 0, "monster_id": "ice_lab_boss"})
	if int(fire_ice.get("final", 0)) <= int(ice_fire.get("final", 0)):
		_fail("ELEMENT_UNKNOWN", "affinity")
	var a: Dictionary = svc.resolve({"base_damage": 100, "attacker_element": "fire", "defender_element": "ice", "resist": 40, "field_id": "lab_field", "monster_id": "ice_lab_boss"})
	var b: Dictionary = svc.resolve({"base_damage": 100, "attacker_element": "fire", "defender_element": "ice", "resist": 40, "field_id": "lab_field", "monster_id": "ice_lab_boss"})
	if int(a.get("final", 0)) != int(b.get("final", 1)):
		_fail("ELEMENT_SNAPSHOT", "nondet")
	if str(a.get("rule_id", "")) != str(svc.format_report(a).get("rule_id", "-")):
		_fail("ELEMENT_REPORT", "mismatch")


func _assert_snapshot_battle() -> void:
	_reset()
	GameState.apply_ice_fixture("lab_trial")
	GameState.begin_ice_session("ice_lab_boss", "b1")
	var stats: Dictionary = GameState.get_player_stats()
	var sess = BattleSession.new("ice_lab_boss", stats, 7, {})
	var t1: Dictionary = sess.perform_turn(1.0, 1.0, 1.0, 1.0)
	var d1 := int(t1.get("player_damage", 0))
	GameState.current_day = 40
	GameState.talk_ice_npc("ice_shen", "after_start")
	GameState.ice_set_live_field("aurora_field")
	var t2: Dictionary = sess.perform_turn(1.0, 1.0, 1.0, 1.0)
	var d2 := int(t2.get("player_damage", 0))
	if d1 != d2:
		_fail("ELEMENT_SNAPSHOT", "%d!=%d" % [d1, d2])
	var base_sess = BattleSession.new("snow_cavalry", stats, 7, {})
	var n1: Dictionary = base_sess.perform_turn(1.0, 1.0, 1.0, 1.0)
	GameState.ice_set_live_field("aurora_field")
	var n2: Dictionary = base_sess.perform_turn(1.0, 1.0, 1.0, 1.0)
	if int(n1.get("player_damage", 0)) != int(n2.get("player_damage", 1)):
		_fail("ELEMENT_FIELD_LEAK", "normal")


func _assert_consumable() -> void:
	_reset()
	GameState.apply_ice_fixture("lab_trial")
	GameState.add_item("ember_vial", 2)
	var out: Dictionary = GameState.use_element_consumable("ember_vial")
	if str(out.get("code", "")) != "ELEMENT_CONSUMABLE_CTX":
		_fail("ELEMENT_CONSUMABLE_CD", "ctx %s" % str(out.get("code")))
	GameState.begin_ice_session("ice_lab_boss", "c1")
	var ok: Dictionary = GameState.use_element_consumable("ember_vial")
	if not bool(ok.get("success", false)):
		_fail("ELEMENT_CONSUMABLE_CD", "ok %s" % str(ok.get("code")))
	GameState.begin_ice_session("ice_lab_boss", "c2")
	var cd: Dictionary = GameState.use_element_consumable("ember_vial")
	if str(cd.get("code", "")) != "ELEMENT_CONSUMABLE_CD":
		_fail("ELEMENT_CONSUMABLE_CD", str(cd.get("code")))


func _assert_adjacent() -> void:
	var combat = preload("res://scripts/combat_service.gd").new(1)
	if int(combat.victory_rewards("snow_cavalry").military_merit) != 20000:
		_fail("ELEMENT_FIELD_LEAK", "merit")
	if int(combat.victory_rewards("snow_cavalry").experience) <= 0:
		_fail("ELEMENT_FIELD_LEAK", "exp")


func _fail(code: String, detail: String) -> void:
	_errors.append("%s %s" % [code, detail])


func _finish() -> void:
	if _errors.size() > 0:
		print("REGISTRY_FAIL: " + "; ".join(_errors))
		get_tree().quit(1)
		return
	print("PASS element_resolution: rules snapshot consumable adjacent")
	get_tree().quit(0)
