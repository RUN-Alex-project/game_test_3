extends RefCounted

const DATA_PATH := "res://data/territory_economy.json"
const EVENTS_PATH := "res://data/territory_events.json"
const TerritoryServiceScript = preload("res://scripts/territory_service.gd")
const LedgerServiceScript = preload("res://scripts/territory_ledger_service.gd")
const AssignmentServiceScript = preload("res://scripts/assignment_service.gd")

## v1.47 negative hooks. Production stays true.
const REQUIRE_OWNED := true
const SKIP_SAME_DAY := true
const ENFORCE_STOCK_CAP := true
const BLOCK_DUP_EVENT := true
const USE_WORLD_SEED := true
const REQUIRE_BIDIRECTIONAL := true

var rules: Dictionary = {}
var spec_by_map: Dictionary = {}
var events_by_id: Dictionary = {}
var common_by_map: Dictionary = {}
var rare_by_map: Dictionary = {}
var territory_service = TerritoryServiceScript.new()
var ledger_service = LedgerServiceScript.new()
var assignment_service = AssignmentServiceScript.new()


func _init() -> void:
	rules = _read_dict(DATA_PATH)
	for raw_row: Variant in rules.get("territories", []):
		if not raw_row is Dictionary:
			continue
		var map_id := str(raw_row.get("map_id", ""))
		if map_id.is_empty():
			continue
		spec_by_map[map_id] = raw_row
	var events_root: Dictionary = _read_dict(EVENTS_PATH)
	for raw_row: Variant in events_root.get("events", []):
		if not raw_row is Dictionary:
			continue
		var event_id := str(raw_row.get("event_id", ""))
		var map_id := str(raw_row.get("map_id", ""))
		if event_id.is_empty() or map_id.is_empty():
			continue
		events_by_id[event_id] = raw_row
		var rarity := str(raw_row.get("rarity", "common"))
		if rarity == "rare":
			if not rare_by_map.has(map_id):
				rare_by_map[map_id] = []
			(rare_by_map[map_id] as Array).append(event_id)
		else:
			if not common_by_map.has(map_id):
				common_by_map[map_id] = []
			(common_by_map[map_id] as Array).append(event_id)


func default_row(map_id: String) -> Dictionary:
	var spec: Dictionary = spec_of(map_id)
	var resource_id := str(spec.get("resource_id", "gold"))
	return {
		"map_id": map_id,
		"governance_level": 0,
		"stocks": {resource_id: 0},
		"last_settlement_day": 0,
		"locked": false,
		"pending_event_id": "",
		"event_resolved": false,
		"last_event_day": 0,
		"event_cooldown_until": 0,
		"event_roll": 0,
		"processed_event_ops": [],
	}


func default_economy() -> Dictionary:
	var territories: Dictionary = {}
	for map_id in spec_by_map.keys():
		territories[str(map_id)] = default_row(str(map_id))
	return {
		"contribution": 0,
		"last_settlement_day": 0,
		"last_weekly_day": 0,
		"ledger": [],
		"territories": territories,
	}


func normalize(raw: Variant) -> Dictionary:
	var base: Dictionary = default_economy()
	if not raw is Dictionary:
		return base
	var incoming: Dictionary = raw
	for key in ["contribution", "last_settlement_day", "last_weekly_day"]:
		if incoming.has(key):
			base[key] = int(incoming.get(key, 0))
	if incoming.get("ledger") is Array:
		base["ledger"] = (incoming["ledger"] as Array).duplicate(true)
	var incoming_maps: Dictionary = {}
	if incoming.get("territories") is Dictionary:
		incoming_maps = incoming["territories"]
	var territories: Dictionary = base.get("territories", {})
	for map_id in spec_by_map.keys():
		var key := str(map_id)
		var row: Dictionary = default_row(key)
		var src: Variant = incoming_maps.get(key, {})
		if src is Dictionary:
			row["governance_level"] = int(src.get("governance_level", 0))
			row["last_settlement_day"] = int(src.get("last_settlement_day", 0))
			row["locked"] = bool(src.get("locked", false))
			row["pending_event_id"] = str(src.get("pending_event_id", ""))
			row["event_resolved"] = bool(src.get("event_resolved", false))
			row["last_event_day"] = int(src.get("last_event_day", 0))
			row["event_cooldown_until"] = int(src.get("event_cooldown_until", 0))
			row["event_roll"] = int(src.get("event_roll", 0))
			if src.get("stocks") is Dictionary:
				row["stocks"] = (src["stocks"] as Dictionary).duplicate(true)
			if src.get("processed_event_ops") is Array:
				row["processed_event_ops"] = (src["processed_event_ops"] as Array).duplicate(true)
		territories[key] = row
	base["territories"] = territories
	return base


func spec_of(map_id: String) -> Dictionary:
	var raw: Variant = spec_by_map.get(map_id, {})
	return raw.duplicate(true) if raw is Dictionary else {}


func validate_data() -> Array[String]:
	var errors: Array[String] = []
	var prod: Dictionary = {}
	for map_id in territory_service.territories.keys():
		prod[str(map_id)] = true
	var data_ids: Dictionary = {}
	for map_id in spec_by_map.keys():
		data_ids[str(map_id)] = true
	if REQUIRE_BIDIRECTIONAL:
		for map_id in prod.keys():
			if not data_ids.has(str(map_id)):
				errors.append("TERRITORY_ID_MISMATCH missing data %s" % str(map_id))
		for map_id in data_ids.keys():
			if not prod.has(str(map_id)):
				errors.append("TERRITORY_ID_MISMATCH extra data %s" % str(map_id))
	for map_id in spec_by_map.keys():
		var spec: Dictionary = spec_of(str(map_id))
		if int(spec.get("base_output", 0)) < 0 or int(spec.get("stock_cap", 0)) < 1:
			errors.append("TERRITORY_STOCK_CAP %s" % str(map_id))
		if not common_by_map.has(str(map_id)) or not rare_by_map.has(str(map_id)):
			errors.append("TERRITORY_ID_MISMATCH events %s" % str(map_id))
	return errors


func validate_save(state: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var econ: Dictionary = normalize(state.get("territory_economy", {}))
	if int(econ.get("contribution", 0)) < 0:
		errors.append("SAVE_NEG_STOCK contribution")
	var territories: Dictionary = econ.get("territories", {})
	for map_id in territories.keys():
		var row: Variant = territories[map_id]
		if not row is Dictionary:
			continue
		var stocks: Variant = row.get("stocks", {})
		if stocks is Dictionary:
			for resource_id in stocks.keys():
				if int(stocks.get(resource_id, 0)) < 0:
					errors.append("SAVE_NEG_STOCK %s:%s" % [str(map_id), str(resource_id)])
	return errors


func mix(world_seed: int, day: int, system_id: String, entity_id: String, seq: int) -> int:
	return fnv1a32("%d|%d|%s|%s|%d" % [world_seed, day, system_id, entity_id, seq])


func fnv1a32(text: String) -> int:
	var h: int = 2166136261
	for byte_value in text.to_utf8_buffer():
		h = (h ^ int(byte_value)) & 0xFFFFFFFF
		h = (h * 16777619) & 0xFFFFFFFF
	return h


func output_qty(expansion: Dictionary, map_id: String, row: Dictionary) -> int:
	var spec: Dictionary = spec_of(map_id)
	var qty := int(spec.get("base_output", 0)) + clampi(int(row.get("governance_level", 0)), 0, 3)
	var asg: Dictionary = assignment_service.active_for_map(expansion, map_id)
	if asg.is_empty():
		return qty
	qty += int(spec.get("assignment_bonus", 1))
	if int(asg.get("relationship_snapshot", 0)) >= int(spec.get("relationship_threshold", 2)):
		qty += int(spec.get("relationship_bonus", 1))
	return qty


func settle_ended_day(expansion: Dictionary, ended_day: int, owned_map_id: String) -> Dictionary:
	if ended_day < 1:
		return {"success": false, "code": "TERRITORY_NOT_OWNED", "expansion": expansion}
	var state: Dictionary = expansion.duplicate(true)
	var econ: Dictionary = normalize(state.get("territory_economy", {}))
	if SKIP_SAME_DAY and int(econ.get("last_settlement_day", 0)) == ended_day:
		state["territory_economy"] = econ
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": state, "replayed": true, "produced": 0}
	var target := owned_map_id
	if target.is_empty():
		if REQUIRE_OWNED:
			state["territory_economy"] = econ
			return {"success": true, "code": "TERRITORY_NOT_OWNED", "expansion": state, "produced": 0}
		target = "cassano_city"
	if not spec_by_map.has(target):
		return {"success": false, "code": "TERRITORY_ID_MISMATCH", "expansion": expansion}
	var territories: Dictionary = (econ.get("territories", {}) as Dictionary).duplicate(true)
	var row: Dictionary = (territories.get(target, default_row(target)) as Dictionary).duplicate(true)
	var spec: Dictionary = spec_of(target)
	var resource_id := str(spec.get("resource_id", "gold"))
	var stocks: Dictionary = (row.get("stocks", {}) as Dictionary).duplicate(true)
	var before := int(stocks.get(resource_id, 0))
	var produced := 0
	var code := "OK"
	if bool(row.get("locked", false)):
		code = "TERRITORY_LOCKED"
	else:
		var qty := output_qty(state, target, row)
		var cap := int(spec.get("stock_cap", 0))
		var add := qty
		if ENFORCE_STOCK_CAP:
			var room := cap - before
			if room <= 0:
				add = 0
				code = "TERRITORY_STOCK_CAP"
			elif add > room:
				add = room
				code = "TERRITORY_STOCK_CAP"
		stocks[resource_id] = before + add
		produced = add
		econ["contribution"] = int(econ.get("contribution", 0)) + add
		row["stocks"] = stocks
		var ledger_payload := {
			"operation_id": "settle:%d:%s" % [ended_day, target],
			"day": ended_day,
			"reason": "daily_output",
			"map_id": target,
			"resource_id": resource_id,
			"qty_delta": add,
			"qty_before": before,
			"qty_after": before + add,
		}
		econ = ledger_service.append(econ, ledger_payload)
		_roll_event(state, row, target, ended_day)
	row["last_settlement_day"] = ended_day
	territories[target] = row
	econ["territories"] = territories
	econ["last_settlement_day"] = ended_day
	if not bool(row.get("locked", false)) and ended_day % 7 == 0 and int(econ.get("last_weekly_day", 0)) != ended_day:
		var contrib_before := int(econ.get("contribution", 0))
		econ["contribution"] = contrib_before + 1
		econ["last_weekly_day"] = ended_day
		econ = ledger_service.append(econ, {
			"operation_id": "weekly:%d:%s" % [ended_day, target],
			"day": ended_day,
			"reason": "weekly_bonus",
			"map_id": target,
			"resource_id": "contribution",
			"qty_delta": 1,
			"qty_before": contrib_before,
			"qty_after": contrib_before + 1,
		})
	state["territory_economy"] = econ
	return {"success": true, "code": code, "expansion": state, "produced": produced, "map_id": target}


func _roll_event(state: Dictionary, row: Dictionary, map_id: String, ended_day: int) -> void:
	if int(row.get("last_event_day", 0)) == ended_day and not str(row.get("pending_event_id", "")).is_empty():
		return
	if ended_day < int(row.get("event_cooldown_until", 0)):
		return
	var world_seed := 0
	if USE_WORLD_SEED:
		world_seed = int(state.get("world_seed", 0))
	var roll := mix(world_seed, ended_day, "territory_event", map_id, 0)
	row["event_roll"] = roll
	var rare_weight := int(rules.get("rare_weight", 10))
	var pool: Array = common_by_map.get(map_id, [])
	if (roll % 100) < rare_weight:
		pool = rare_by_map.get(map_id, pool)
	if pool.is_empty():
		return
	var event_id := str(pool[roll % pool.size()])
	row["pending_event_id"] = event_id
	row["event_resolved"] = false
	row["last_event_day"] = ended_day


func resolve_event(expansion: Dictionary, map_id: String, choice_id: String, day: int, player_gold: int, operation_id: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var econ: Dictionary = normalize(state.get("territory_economy", {}))
	var territories: Dictionary = (econ.get("territories", {}) as Dictionary).duplicate(true)
	if not territories.has(map_id):
		return {"success": false, "code": "TERRITORY_ID_MISMATCH", "expansion": expansion}
	var row: Dictionary = (territories[map_id] as Dictionary).duplicate(true)
	var event_id := str(row.get("pending_event_id", ""))
	if event_id.is_empty() or not events_by_id.has(event_id):
		return {"success": false, "code": "TERRITORY_DUP_EVENT", "expansion": expansion}
	var ops: Array = (row.get("processed_event_ops", []) as Array).duplicate()
	if operation_id in ops:
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true, "gold_cost": 0}
	if BLOCK_DUP_EVENT and bool(row.get("event_resolved", false)):
		return {"success": false, "code": "TERRITORY_DUP_EVENT", "expansion": expansion}
	var event_row: Dictionary = (events_by_id[event_id] as Dictionary).duplicate(true)
	var choice: Dictionary = {}
	for raw_choice: Variant in event_row.get("choices", []):
		if raw_choice is Dictionary and str(raw_choice.get("choice_id", "")) == choice_id:
			choice = raw_choice
			break
	if choice.is_empty():
		return {"success": false, "code": "TERRITORY_EVENT_FAIL", "expansion": expansion}
	var gold_cost := int(choice.get("gold_cost", 0))
	if player_gold < gold_cost:
		return {"success": false, "code": "TERRITORY_EVENT_FAIL", "expansion": expansion, "gold_cost": 0}
	var spec: Dictionary = spec_of(map_id)
	var resource_id := str(spec.get("resource_id", "gold"))
	var stocks: Dictionary = (row.get("stocks", {}) as Dictionary).duplicate(true)
	var before := int(stocks.get(resource_id, 0))
	var delta := int(choice.get("stock_delta", 0))
	stocks[resource_id] = before + delta
	row["stocks"] = stocks
	econ["contribution"] = int(econ.get("contribution", 0)) + int(choice.get("contribution_delta", 0))
	row["event_resolved"] = true
	row["event_cooldown_until"] = day + int(event_row.get("cooldown_days", 2))
	ops.append(operation_id)
	row["processed_event_ops"] = ops
	territories[map_id] = row
	econ["territories"] = territories
	econ = ledger_service.append(econ, {
		"operation_id": operation_id,
		"day": day,
		"reason": "event:%s" % event_id,
		"map_id": map_id,
		"resource_id": resource_id,
		"qty_delta": delta,
		"qty_before": before,
		"qty_after": before + delta,
		"related_id": event_id,
	})
	state["territory_economy"] = econ
	return {"success": true, "code": "OK", "expansion": state, "gold_cost": gold_cost, "event_id": event_id}


func upgrade_governance(expansion: Dictionary, map_id: String, operation_id: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var econ: Dictionary = normalize(state.get("territory_economy", {}))
	var territories: Dictionary = (econ.get("territories", {}) as Dictionary).duplicate(true)
	if not territories.has(map_id):
		return {"success": false, "code": "TERRITORY_ID_MISMATCH", "expansion": expansion}
	var row: Dictionary = (territories[map_id] as Dictionary).duplicate(true)
	var level := int(row.get("governance_level", 0))
	if level >= 3:
		return {"success": false, "code": "TERRITORY_LOCKED", "expansion": expansion}
	row["governance_level"] = level + 1
	territories[map_id] = row
	econ["territories"] = territories
	state["territory_economy"] = econ
	return {"success": true, "code": "OK", "expansion": state, "operation_id": operation_id, "gold_cost": 50}


func _read_dict(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
