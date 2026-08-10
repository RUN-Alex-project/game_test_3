class_name WorldInteractionTestSupport
extends RefCounted

# v1.35 整改02 测试辅助：纯验证器，返回错误码列表（空=通过）。
# 负向验证在内存中变异快照，不修改磁盘文件。

# --- GameState 快照/恢复 ---
static func snapshot_game_state() -> Dictionary:
	return {
		"story_flags": GameState.story_flags.duplicate(true),
		"fuwa_event": GameState.fuwa_event.duplicate(true),
		"current_map_id": GameState.current_map_id,
		"current_day": GameState.current_day,
		"war_soul_maze_active": GameState.war_soul_maze_active,
		"war_soul_guardian_revealed": GameState.war_soul_guardian_revealed,
		"pk_race_active": GameState.pk_race_active,
		"last_pk_race_day": GameState.last_pk_race_day,
		"level": GameState.level,
		"magic_stones": GameState.magic_stones,
		"gold": GameState.gold,
		"military_merit": GameState.military_merit,
		"nobility_merit": GameState.nobility_merit,
		"player_current_hp": GameState.player_current_hp,
		"player_current_stamina": GameState.player_current_stamina,
		"inventory": GameState.inventory.duplicate(true),
		"demon_campaign": GameState.demon_campaign.duplicate(true),
		"owned_territory": GameState.owned_territory,
		"pending_territory_challenge": GameState.pending_territory_challenge,
		"last_territory_challenge_day": GameState.last_territory_challenge_day,
		"last_territory_reward_day": GameState.last_territory_reward_day,
		"completed_daily_tasks": GameState.completed_daily_tasks.duplicate(true),
		"warehouse": GameState.warehouse.duplicate(true),
	}

static func restore_game_state(snap: Dictionary) -> void:
	GameState.story_flags = snap.get("story_flags", {}).duplicate(true)
	GameState.fuwa_event = snap.get("fuwa_event", {}).duplicate(true)
	GameState.current_map_id = str(snap.get("current_map_id", "cassano_city"))
	GameState.current_day = int(snap.get("current_day", 1))
	GameState.war_soul_maze_active = bool(snap.get("war_soul_maze_active", false))
	GameState.war_soul_guardian_revealed = bool(snap.get("war_soul_guardian_revealed", false))
	GameState.pk_race_active = bool(snap.get("pk_race_active", false))
	GameState.last_pk_race_day = int(snap.get("last_pk_race_day", 0))
	GameState.level = int(snap.get("level", 1))
	GameState.magic_stones = int(snap.get("magic_stones", 99999999999))
	GameState.gold = int(snap.get("gold", 99999999999))
	GameState.military_merit = int(snap.get("military_merit", 0))
	GameState.nobility_merit = int(snap.get("nobility_merit", 0))
	GameState.player_current_hp = int(snap.get("player_current_hp", 550))
	GameState.player_current_stamina = int(snap.get("player_current_stamina", 110))
	GameState.inventory = snap.get("inventory", []).duplicate(true)
	GameState.warehouse = snap.get("warehouse", []).duplicate(true)
	GameState.demon_campaign = snap.get("demon_campaign", {}).duplicate(true)
	GameState.owned_territory = str(snap.get("owned_territory", ""))
	GameState.pending_territory_challenge = str(snap.get("pending_territory_challenge", ""))
	GameState.last_territory_challenge_day = int(snap.get("last_territory_challenge_day", 0))
	GameState.last_territory_reward_day = int(snap.get("last_territory_reward_day", 0))
	GameState.completed_daily_tasks = snap.get("completed_daily_tasks", {}).duplicate(true)

# --- 深度比较快照恢复 ---
static func game_state_restore_differences(before: Dictionary) -> Array:
	return _compare_snapshots(before, snapshot_game_state())

static func assert_game_state_restored(before: Dictionary) -> void:
	var differences: Array = game_state_restore_differences(before)
	assert(differences.is_empty(), "STATE_RESTORE_MISMATCH: " + str(differences))

static func _compare_snapshots(before: Dictionary, after: Dictionary) -> Array:
	var diffs: Array = []
	for key: String in before:
		if not after.has(key):
			diffs.append("MISSING_KEY:" + key)
			continue
		diffs.append_array(_compare_values(before[key], after[key], key))
	return diffs

static func _compare_values(bv: Variant, av: Variant, path: String) -> Array:
	var diffs: Array = []
	if bv is Dictionary:
		if not (av is Dictionary):
			diffs.append("TYPE_MISMATCH:" + path)
			return diffs
		if bv.size() != av.size():
			diffs.append("VALUE_MISMATCH:" + path + " (size before=%d after=%d)" % [bv.size(), av.size()])
			return diffs
		for key: String in bv:
			if not av.has(key):
				diffs.append("MISSING_KEY:" + path + "." + key)
				continue
			diffs.append_array(_compare_values(bv[key], av[key], path + "." + key))
	elif bv is Array:
		if not (av is Array):
			diffs.append("TYPE_MISMATCH:" + path)
			return diffs
		if bv.size() != av.size():
			diffs.append("VALUE_MISMATCH:" + path + " (size before=%d after=%d)" % [bv.size(), av.size()])
			return diffs
		for i in bv.size():
			diffs.append_array(_compare_values(bv[i], av[i], path + "[" + str(i) + "]"))
	else:
		# 标量：先比较typeof，再比较值
		if typeof(bv) != typeof(av):
			diffs.append("TYPE_MISMATCH:" + path + " before_type=" + str(typeof(bv)) + " after_type=" + str(typeof(av)))
		elif bv != av:
			diffs.append("VALUE_MISMATCH:" + path + " before=" + str(bv) + " after=" + str(av))
	return diffs

static func _dict_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key: String in a:
		if not b.has(key):
			return false
		if not _values_equal(a[key], b[key]):
			return false
	return true

static func _array_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not _values_equal(a[i], b[i]):
			return false
	return true

static func _values_equal(av: Variant, bv: Variant) -> bool:
	if av is Dictionary:
		return bv is Dictionary and _dict_equal(av, bv)
	elif av is Array:
		return bv is Array and _array_equal(av, bv)
	else:
		return typeof(av) == typeof(bv) and av == bv

# --- Fixture 应用 ---
static func apply_fixture(fixture: Variant) -> void:
	GameState.story_flags.clear()
	GameState.war_soul_maze_active = false
	GameState.war_soul_guardian_revealed = false
	GameState.pk_race_active = false
	GameState.fuwa_event = GameState.default_fuwa_event()
	GameState.level = 1
	GameState.magic_stones = 99999999999
	GameState.gold = 99999999999
	GameState.military_merit = 0
	GameState.nobility_merit = 0
	GameState.inventory.clear()
	for _i in GameState.INVENTORY_SIZE:
		GameState.inventory.append({})
	GameState.warehouse.clear()
	for _i in GameState.WAREHOUSE_SIZE:
		GameState.warehouse.append({})
	GameState.demon_campaign = {
		"assault_alive": true, "guard_alive": true, "mystery_alive": true,
		"totem_alive": true, "commander_alive": true, "energy_alive": true,
	}
	GameState.owned_territory = ""
	GameState.pending_territory_challenge = ""
	GameState.last_territory_challenge_day = 0
	GameState.last_territory_reward_day = 0
	GameState.last_pk_race_day = 0
	GameState.completed_daily_tasks.clear()
	if not fixture is Dictionary:
		return
	var fd: Dictionary = fixture
	for key: String in fd:
		var val: Variant = fd[key]
		if key.begins_with("story_flags."):
			GameState.story_flags[key.trim_prefix("story_flags.")] = val
		elif key.begins_with("fuwa_event."):
			GameState.fuwa_event[key.trim_prefix("fuwa_event.")] = val
		elif key == "war_soul_maze_active":
			GameState.war_soul_maze_active = bool(val)
		elif key == "war_soul_guardian_revealed":
			GameState.war_soul_guardian_revealed = bool(val)
		elif key == "pk_race_active":
			GameState.pk_race_active = bool(val)
		elif key == "last_pk_race_day":
			GameState.last_pk_race_day = int(val)
		elif key == "level":
			GameState.level = int(val)
		elif key == "magic_stones":
			GameState.magic_stones = int(val)
		elif key == "nobility_merit":
			GameState.nobility_merit = int(val)
		elif key == "owned_territory":
			GameState.owned_territory = str(val)
		elif key.begins_with("demon_campaign."):
			var dkey: String = key.trim_prefix("demon_campaign.")
			GameState.demon_campaign[dkey] = val

# --- 运行时实体快照 ---
static func runtime_entity_snapshot(main: Node) -> Dictionary:
	var snap: Dictionary = {}
	for child in main.actor_layer.get_children():
		if child is TextureRect and child.has_meta("world_entity_id"):
			var eid: String = str(child.get_meta("world_entity_id"))
			var tex_path: String = ""
			if child.texture != null:
				tex_path = child.texture.resource_path
			snap[eid] = {
				"kind": str(child.get_meta("world_entity_kind", "")),
				"action_id": str(child.get_meta("world_action_id", "")),
				"asset": tex_path,
				"position": [child.position.x, child.position.y],
				"size": [child.size.x, child.size.y],
				"mouse_filter": int(child.mouse_filter),
				"y_bottom": child.position.y + child.size.y,
			}
	return snap

# --- 期望always实体快照（只返回always实体，不读取GameState） ---
static func expected_always_entity_snapshot(reg_map: Variant) -> Dictionary:
	var snap: Dictionary = {}
	for e in reg_map["entities"]:
		var cond: String = str(e.get("appearance_condition", "always"))
		if cond == "always":
			var pos: Array = e["position"]
			var sz: Array = e["size"]
			snap[str(e["entity_id"])] = {
				"kind": str(e["kind"]),
				"action_id": str(e.get("action_id", "")),
				"asset": str(e.get("asset", "")),
				"position": [float(pos[0]), float(pos[1])],
				"size": [float(sz[0]), float(sz[1])],
			}
	return snap


# --- scenario分区验证（不读取GameState） ---
static func validate_scenario_partition(reg_map: Variant, scenario: Variant) -> Array:
	var errors: Array = []
	# 收集该地图所有非always实体ID
	var conditional_ids: Dictionary = {}
	for e in reg_map["entities"]:
		if str(e.get("appearance_condition", "always")) != "always":
			conditional_ids[str(e["entity_id"])] = true
	# 构建present/absent集合
	var present: Dictionary = {}
	for eid in scenario.get("expected_dynamic_present", []):
		present[str(eid)] = true
	var absent: Dictionary = {}
	for eid in scenario.get("expected_dynamic_absent", []):
		absent[str(eid)] = true
	# 检查交集为空
	for eid: String in present:
		if absent.has(eid):
			errors.append("SCENARIO_PARTITION_INTERSECT:" + eid)
	# 检查每个条件实体恰好出现在present或absent之一
	for eid: String in conditional_ids:
		if not present.has(eid) and not absent.has(eid):
			errors.append("SCENARIO_PARTITION_MISSING:" + eid)
		if present.has(eid) and absent.has(eid):
			errors.append("SCENARIO_PARTITION_BOTH:" + eid)
	# 检查present/absent中的ID都真实存在于该地图注册表
	var all_entity_ids: Dictionary = {}
	for e in reg_map["entities"]:
		all_entity_ids[str(e["entity_id"])] = true
	for eid: String in present:
		if not all_entity_ids.has(eid):
			errors.append("SCENARIO_PRESENT_NOT_IN_REGISTRY:" + eid)
	for eid: String in absent:
		if not all_entity_ids.has(eid):
			errors.append("SCENARIO_ABSENT_NOT_IN_REGISTRY:" + eid)
	return errors


# --- scenario runner（独立期望，不通过_condition_active推导） ---
static func run_scenario(reg_map: Variant, scenario: Variant, main: Node) -> Array:
	var errors: Array = []
	# 1. 验证scenario分区
	errors.append_array(validate_scenario_partition(reg_map, scenario))
	# 2. 构造期望 = always + expected_dynamic_present
	var expected: Dictionary = expected_always_entity_snapshot(reg_map)
	# 从注册表查找present实体的详情
	var all_ents: Dictionary = {}
	for e in reg_map["entities"]:
		all_ents[str(e["entity_id"])] = e
	for eid in scenario.get("expected_dynamic_present", []):
		var eid_str: String = str(eid)
		if all_ents.has(eid_str):
			var e_data: Variant = all_ents[eid_str]
			var pos: Array = e_data["position"]
			var sz: Array = e_data["size"]
			expected[eid_str] = {
				"kind": str(e_data["kind"]),
				"action_id": str(e_data.get("action_id", "")),
				"asset": str(e_data.get("asset", "")),
				"position": [float(pos[0]), float(pos[1])],
				"size": [float(sz[0]), float(sz[1])],
			}
	# 3. 运行时快照
	var actual: Dictionary = runtime_entity_snapshot(main)
	# 4. 双向集合+字段比较
	errors.append_array(validate_entities(expected, actual))
	# 5. absent逐个断言
	for eid in scenario.get("expected_dynamic_absent", []):
		if actual.has(str(eid)):
			errors.append("SCENARIO_ABSENT_BUT_PRESENT:" + str(eid))
	return errors


# --- 期望实体快照（always + 条件匹配） ---
static func expected_entity_snapshot(reg_map: Variant) -> Dictionary:
	var snap: Dictionary = {}
	var map_id: String = str(reg_map["map_id"])
	for e in reg_map["entities"]:
		var cond: String = str(e.get("appearance_condition", "always"))
		if cond == "always" or _condition_active(cond, map_id):
			var pos: Array = e["position"]
			var sz: Array = e["size"]
			snap[str(e["entity_id"])] = {
				"kind": str(e["kind"]),
				"action_id": str(e.get("action_id", "")),
				"asset": str(e.get("asset", "")),
				"position": [float(pos[0]), float(pos[1])],
				"size": [float(sz[0]), float(sz[1])],
			}
	return snap


static func _condition_active(cond: String, map_id: String) -> bool:
	if "king_rescued" in cond:
		return bool(GameState.story_flags.get("king_rescued", false))
	if "should_show_fuwa_messenger" in cond:
		return GameState.should_show_fuwa_messenger(map_id)
	if "pk_race_active" in cond:
		return GameState.pk_race_active
	if "war_soul_maze_active" in cond:
		return GameState.war_soul_maze_active
	if "war_soul_guardian_revealed" in cond:
		return GameState.war_soul_guardian_revealed
	if "war_soul_quest_available" in cond:
		return bool(GameState.story_flags.get("war_soul_quest_available", false)) and not bool(GameState.story_flags.get("war_soul_secret_unlocked", false))
	if "is_final_campaign_enemy_alive" in cond:
		var start: int = cond.find("\"")
		if start >= 0:
			var endc: int = cond.find("\"", start + 1)
			if endc > start:
				var enemy_id: String = cond.substr(start + 1, endc - start - 1)
				return GameState.is_final_campaign_enemy_alive(enemy_id)
	return false

# --- 实体验证器（返回错误码列表） ---
static func validate_entities(expected: Dictionary, actual: Dictionary) -> Array:
	var errors: Array = []
	for eid: String in expected:
		if not actual.has(eid):
			errors.append("ENTITY_SET_MISSING:" + eid)
	for eid: String in actual:
		if not expected.has(eid):
			errors.append("ENTITY_SET_EXTRA:" + eid)
	for eid: String in expected:
		if not actual.has(eid):
			continue
		var exp: Dictionary = expected[eid]
		var act: Dictionary = actual[eid]
		if str(exp["kind"]) != str(act["kind"]):
			errors.append("ENTITY_KIND_MISMATCH:" + eid + " exp=" + str(exp["kind"]) + " act=" + str(act["kind"]))
		if str(exp["action_id"]) != str(act["action_id"]):
			errors.append("ENTITY_ACTION_MISMATCH:" + eid)
		var exp_asset: String = str(exp["asset"])
		if exp_asset != "UNCONFIRMED" and exp_asset != str(act["asset"]):
			errors.append("ENTITY_ASSET_MISMATCH:" + eid)
		if not is_equal_approx(float(exp["position"][0]), float(act["position"][0])) or not is_equal_approx(float(exp["position"][1]), float(act["position"][1])):
			errors.append("ENTITY_POSITION_MISMATCH:" + eid)
		if not is_equal_approx(float(exp["size"][0]), float(act["size"][0])) or not is_equal_approx(float(exp["size"][1]), float(act["size"][1])):
			errors.append("ENTITY_SIZE_MISMATCH:" + eid)
		if str(exp["kind"]) == "decoration" and int(act.get("mouse_filter", 0)) != int(Control.MOUSE_FILTER_IGNORE):
			errors.append("DECORATION_MOUSE_FILTER:" + eid)
	return errors

# --- 边界验证器（700×512 + Boss例外） ---
static func validate_overlap(reg_map: Variant, actual: Dictionary) -> Array:
	var errors: Array = []
	# 收集注册表中所有实体的例外信息
	var exception_ids: Dictionary = {}
	for e in reg_map["entities"]:
		if e.has("native_overlap_exception"):
			exception_ids[str(e["entity_id"])] = e["native_overlap_exception"]
	for eid: String in actual:
		var act: Dictionary = actual[eid]
		if str(act.get("kind", "")) == "decoration":
			continue
		var y_bottom: float = float(act.get("y_bottom", 0.0))
		if y_bottom > 512.0:
			if not exception_ids.has(eid):
				errors.append("OVERLAP_EXCEPTION_MISSING:" + eid + " y_bottom=" + str(y_bottom))
		# 超出画布
		var px: float = float(act["position"][0])
		var py: float = float(act["position"][1])
		if px < 0.0 or py < 0.0 or px + float(act["size"][0]) > 700.0 or y_bottom > 550.0:
			errors.append("OVERLAP_BEYOND_CANVAS:" + eid)
	return errors

# --- 领地状态覆盖验证器 ---
static func validate_territory_coverage(completed_cases: Array, expected_count: int) -> Array:
	var errors: Array = []
	if completed_cases.size() != expected_count:
		errors.append("TERRITORY_STATE_COVERAGE_MISSING: expected %d cases, got %d" % [expected_count, completed_cases.size()])
	# 检查每图每态存在
	var expected_suffixes: Array = ["rank_low", "rank_ok", "challenger_active", "owned"]
	var territory_maps: Array = ["cassano_city", "thunder_continent", "desert", "dream_swamp", "ice_palace", "avit_island"]
	var case_set: Dictionary = {}
	for c: String in completed_cases:
		case_set[c] = true
	for tmap: String in territory_maps:
		for suffix: String in expected_suffixes:
			var case_id: String = tmap + ":" + suffix
			if not case_set.has(case_id):
				errors.append("TERRITORY_STATE_COVERAGE_MISSING:" + case_id)
	return errors


# --- 出口验证器（A-01: 全字段双向比较 + disabled + action_route） ---
static func validate_exits(reg_map: Variant, main: Node) -> Array:
	var errors: Array = []
	var runtime_exits: Dictionary = {}
	for dir_key in main.direction_buttons:
		var btn: Button = main.direction_buttons[dir_key]
		if btn.visible:
			runtime_exits[str(btn.target_map_id)] = {
				"direction": str(btn.native_direction),
				"target": str(btn.target_map_id),
				"position": [btn.position.x, btn.position.y],
				"size": [btn.size.x, btn.size.y],
				"locked": bool(btn.get("locked")),
			}
	var reg_exits: Dictionary = {}
	for ex in reg_map["exits"]:
		if str(ex.get("position", "UNCONFIRMED")) != "UNCONFIRMED":
			reg_exits[str(ex["target_map_id"])] = ex
	# 双向集合（不可进入出口也必须存在，只是 locked=true）
	for tgt: String in reg_exits:
		if not runtime_exits.has(tgt):
			errors.append("EXIT_SET_MISSING:" + tgt)
	for tgt: String in runtime_exits:
		if not reg_exits.has(tgt):
			errors.append("EXIT_SET_EXTRA:" + tgt)
	# 逐出口全字段比较 + metadata值比较（E-01/E-03: 预期值全部来自注册表）
	var reg_map_id: String = str(reg_map["map_id"])
	for tgt: String in reg_exits:
		if not runtime_exits.has(tgt):
			continue
		var exp_ex: Dictionary = reg_exits[tgt]
		var act_ex: Dictionary = runtime_exits[tgt]
		# direction: registry vs runtime
		var exp_direction: String = str(exp_ex.get("direction", ""))
		if exp_direction != str(act_ex["direction"]):
			errors.append("EXIT_DIRECTION_MISMATCH:" + tgt + " expected=" + exp_direction + " actual=" + str(act_ex["direction"]))
		var exp_pos: Array = exp_ex["position"]
		var act_pos: Array = act_ex["position"]
		if not is_equal_approx(float(exp_pos[0]), float(act_pos[0])) or not is_equal_approx(float(exp_pos[1]), float(act_pos[1])):
			errors.append("EXIT_POSITION_MISMATCH:" + tgt)
		var exp_sz: Array = exp_ex["size"]
		var act_sz: Array = act_ex["size"]
		if not is_equal_approx(float(exp_sz[0]), float(act_sz[0])) or not is_equal_approx(float(exp_sz[1]), float(act_sz[1])):
			errors.append("EXIT_SIZE_MISMATCH:" + tgt)
		# locked 比较（阻挡出口 locked=true 但仍可点击以显示原因）
		var expected_locked: bool = not bool(GameState.can_enter_map(tgt))
		if expected_locked != bool(act_ex.get("locked", false)):
			errors.append("EXIT_LOCKED_MISMATCH:" + tgt)
		# action_route: registry vs constant
		var exp_action_route: String = str(exp_ex.get("action_route", ""))
		if exp_action_route != "UNCONFIRMED" and exp_action_route != "edge_exit":
			errors.append("EXIT_ACTION_ROUTE_MISMATCH:" + tgt + " expected=" + exp_action_route)
	# 出口metadata值比较（预期值全部来自注册表）
	for dir_key in main.direction_buttons:
		var btn: Button = main.direction_buttons[dir_key]
		if not btn.visible:
			continue
		var btn_tgt: String = str(btn.target_map_id)
		# 找到该出口在注册表中的定义
		var btn_reg_ex: Dictionary = {}
		if reg_exits.has(btn_tgt):
			btn_reg_ex = reg_exits[btn_tgt]
		# entity_id: expected from registry target_map_id
		if not btn.has_meta("world_entity_id"):
			errors.append("EXIT_METADATA_MISSING:world_entity_id:" + btn_tgt)
		elif str(btn.get_meta("world_entity_id")) != "exit:" + btn_tgt:
			errors.append("EXIT_METADATA_VALUE_MISMATCH:world_entity_id:" + btn_tgt + " expected=exit:" + btn_tgt + " actual=" + str(btn.get_meta("world_entity_id")))
		# direction: E-01 - compare actual value against registry direction
		if not btn.has_meta("world_direction"):
			errors.append("EXIT_METADATA_MISSING:world_direction:" + btn_tgt)
		elif not btn_reg_ex.is_empty():
			var reg_direction: String = str(btn_reg_ex.get("direction", ""))
			if str(btn.get_meta("world_direction")) != reg_direction:
				errors.append("EXIT_METADATA_VALUE_MISMATCH:world_direction:" + btn_tgt + " expected=" + reg_direction + " actual=" + str(btn.get_meta("world_direction")))
		# current_map: E-03 - expected from reg_map.map_id
		if not btn.has_meta("world_current_map"):
			errors.append("EXIT_METADATA_MISSING:world_current_map:" + btn_tgt)
		elif str(btn.get_meta("world_current_map")) != reg_map_id:
			errors.append("EXIT_METADATA_VALUE_MISMATCH:world_current_map:" + btn_tgt + " expected=" + reg_map_id + " actual=" + str(btn.get_meta("world_current_map")))
		# target_map: expected from registry target_map_id
		if not btn.has_meta("world_target_map"):
			errors.append("EXIT_METADATA_MISSING:world_target_map:" + btn_tgt)
		elif str(btn.get_meta("world_target_map")) != btn_tgt:
			errors.append("EXIT_METADATA_VALUE_MISMATCH:world_target_map:" + btn_tgt)
		# action_route: E-03 - expected from registry action_route
		if not btn.has_meta("world_action_route"):
			errors.append("EXIT_METADATA_MISSING:world_action_route:" + btn_tgt)
		elif not btn_reg_ex.is_empty():
			var reg_action_route: String = str(btn_reg_ex.get("action_route", ""))
			if str(btn.get_meta("world_action_route")) != reg_action_route:
				errors.append("EXIT_METADATA_VALUE_MISMATCH:world_action_route:" + btn_tgt + " expected=" + reg_action_route + " actual=" + str(btn.get_meta("world_action_route")))
		# required_level: expected from registry runtime_required_level, cross-check GameState
		if not btn.has_meta("world_required_level"):
			errors.append("EXIT_METADATA_MISSING:world_required_level:" + btn_tgt)
		else:
			var meta_req_level: int = int(btn.get_meta("world_required_level"))
			var gs_req_level: int = GameState.map_entry_required_level(btn_tgt)
			if meta_req_level != gs_req_level:
				errors.append("EXIT_METADATA_VALUE_MISMATCH:world_required_level:" + btn_tgt + " metadata=" + str(meta_req_level) + " gamestate=" + str(gs_req_level))
			if not btn_reg_ex.is_empty():
				var reg_runtime_level: int = int(btn_reg_ex.get("runtime_required_level", 0))
				if meta_req_level != reg_runtime_level:
					errors.append("EXIT_METADATA_VALUE_MISMATCH:world_required_level_registry:" + btn_tgt + " metadata=" + str(meta_req_level) + " registry=" + str(reg_runtime_level))
		# runtime_availability_rule: registry vs GameState.map_entry_availability_rule
		if not btn_reg_ex.is_empty():
			var reg_rule: String = str(btn_reg_ex.get("runtime_availability_rule", ""))
			var gs_rule: String = GameState.map_entry_availability_rule(btn_tgt)
			if reg_rule != gs_rule:
				errors.append("EXIT_RUNTIME_RULE_MISMATCH:" + btn_tgt + " registry=" + reg_rule + " gamestate=" + gs_rule)
		# locked metadata: cross-check GameState（阻挡=true 但按钮可点击显示原因）
		var expected_locked_meta: bool = not bool(GameState.can_enter_map(btn_tgt))
		if not btn.has_meta("world_locked"):
			errors.append("EXIT_METADATA_MISSING:world_locked:" + btn_tgt)
		elif bool(btn.get_meta("world_locked")) != expected_locked_meta:
			errors.append("EXIT_METADATA_VALUE_MISMATCH:world_locked:" + btn_tgt + " expected=" + str(expected_locked_meta) + " actual=" + str(btn.get_meta("world_locked")))
	return errors

# --- evidence gap 映射验证（E-04: 双向精确集合比较，无模糊子串） ---
static func validate_gap_mapping(reg: Variant) -> Array:
	var errors: Array = []
	var gaps: Array = reg.get("evidence_gaps", [])
	# 展开gap为 map_id|object_id|field 精确复合键
	var gap_field_keys: Dictionary = {}
	for g in gaps:
		var gmid: String = str(g.get("map_id", ""))
		var gfield: String = str(g.get("field", ""))
		for oid in g.get("object_ids", []):
			# 按/分割field，展开每个字段为精确键
			var fields: Array = gfield.split("/")
			for single_field: String in fields:
				single_field = single_field.strip_edges()
				if single_field.is_empty():
					continue
				var compound: String = gmid + "|" + str(oid) + "|" + single_field
				gap_field_keys[compound] = true
	# 构造所有evidence_gap对象的未确认字段复合键
	var unconfirmed_field_keys: Dictionary = {}
	for m in reg["maps"]:
		var mid: String = str(m["map_id"])
		for e in m["entities"]:
			if str(e.get("classification", "")) != "evidence_gap":
				continue
			var eid: String = str(e["entity_id"])
			var ev_status: Dictionary = e.get("evidence_status", {})
			for field_name: String in ev_status:
				if str(ev_status[field_name]) == "unconfirmed":
					var compound: String = mid + "|" + eid + "|" + field_name
					unconfirmed_field_keys[compound] = true
		for ex in m["exits"]:
			if str(ex.get("classification", "")) != "evidence_gap":
				continue
			var oid: String = "exit:" + str(ex.get("target_map_id", ""))
			var ex_status: Dictionary = ex.get("evidence_status", {})
			for field_name: String in ex_status:
				if str(ex_status[field_name]) == "unconfirmed":
					var compound: String = mid + "|" + oid + "|" + field_name
					unconfirmed_field_keys[compound] = true
	# 双向集合比较
	# 方向1: 未确认字段必须有对应gap
	for compound: String in unconfirmed_field_keys:
		if not gap_field_keys.has(compound):
			errors.append("GAP_FIELD_UNCOVERED:" + compound)
	# 方向2: gap必须对应一个真实未确认字段，不能有多余/过期gap
	for compound: String in gap_field_keys:
		if not unconfirmed_field_keys.has(compound):
			errors.append("GAP_FIELD_EXTRA:" + compound)
	return errors

# --- token 验证（A-03: 实体 + 出口 + overlap exception + implementation_source） ---
static func validate_tokens(reg: Variant) -> Array:
	var errors: Array = []
	var file_cache: Dictionary = {}
	for m in reg["maps"]:
		for e in m["entities"]:
			var es: String = str(e.get("evidence_source", ""))
			if es == "" or not FileAccess.file_exists(es):
				errors.append("EVIDENCE_SOURCE_MISSING:" + str(e.get("entity_id", "")))
				continue
			if not file_cache.has(es):
				var f := FileAccess.open(es, FileAccess.READ)
				if f == null:
					errors.append("EVIDENCE_SOURCE_UNREADABLE:" + str(e.get("entity_id", "")))
					continue
				file_cache[es] = f.get_as_text()
				f.close()
			var etext: String = file_cache[es]
			for tok in e.get("evidence_tokens", []):
				if str(tok) not in etext:
					errors.append("EVIDENCE_TOKEN_MISS:" + str(e.get("entity_id", "")) + ":" + str(tok))
			if str(e.get("classification", "")) == "native_confirmed":
				var impl_f: String = str(e.get("implementation_source", "")).split("#")[0].get_file()
				if es.get_file() == impl_f:
					errors.append("CIRCULAR_EVIDENCE:" + str(e.get("entity_id", "")))
			var impl_path: String = str(e.get("implementation_source", "")).split("#")[0]
			if not impl_path.is_empty() and not FileAccess.file_exists(impl_path):
				errors.append("IMPL_SOURCE_MISSING:" + str(e.get("entity_id", "")))
			if e.has("native_overlap_exception"):
				var exc: Dictionary = e["native_overlap_exception"]
				for tok in exc.get("evidence_tokens", []):
					if str(tok) not in etext:
						errors.append("OVERLAP_TOKEN_MISS:" + str(e.get("entity_id", "")) + ":" + str(tok))
		for ex in m["exits"]:
			var ex_es: String = str(ex.get("evidence_source", ""))
			if ex_es == "" or not FileAccess.file_exists(ex_es):
				errors.append("EVIDENCE_SOURCE_MISSING:exit:" + str(ex.get("target_map_id", "")))
				continue
			if not file_cache.has(ex_es):
				var ef := FileAccess.open(ex_es, FileAccess.READ)
				if ef == null:
					errors.append("EVIDENCE_SOURCE_UNREADABLE:exit:" + str(ex.get("target_map_id", "")))
					continue
				file_cache[ex_es] = ef.get_as_text()
				ef.close()
			var ex_etext: String = file_cache[ex_es]
			for tok in ex.get("evidence_tokens", []):
				if str(tok) not in ex_etext:
					errors.append("EVIDENCE_TOKEN_MISS:exit:" + str(ex.get("target_map_id", "")) + ":" + str(tok))
			var ex_impl: String = str(ex.get("implementation_source", "")).split("#")[0]
			if not ex_impl.is_empty() and not FileAccess.file_exists(ex_impl):
				errors.append("IMPL_SOURCE_MISSING:exit:" + str(ex.get("target_map_id", "")))
	return errors


# --- 错误码匹配 ---
static func has_error_code(errors: Array, code_prefix: String) -> bool:
	for e in errors:
		if str(e).begins_with(code_prefix):
			return true
	return false


# --- dispatch结果验证器（正向和负向共用同一函数） ---
static func validate_dispatch_result(actual: Dictionary, expected_route: String, expected_code: String, action_id: String) -> Array:
	var errors: Array = []
	var actual_route: String = str(actual.get("route", ""))
	var actual_code: String = str(actual.get("code", ""))
	if actual_route != expected_route:
		errors.append("DISPATCH_ROUTE_MISMATCH:" + action_id + " expected=" + expected_route + " actual=" + actual_route)
	if actual_code != expected_code:
		errors.append("DISPATCH_CODE_MISMATCH:" + action_id + " expected=" + expected_code + " actual=" + actual_code)
	return errors
