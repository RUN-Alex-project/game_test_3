extends Node

# v1.35 整改03：完整动态矩阵 + 真实action路径 + 9项负向验证 + 边界 + gap + token。
# 每项完成声明对应实际断言和可核验状态差。

const REGISTRY_PATH := "res://docs/world_interaction_registry.json"
const MAPS_JSON_PATH := "res://data/maps.json"
const Support = preload("res://tests/helpers/world_interaction_test_support.gd")


func _load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "could not open " + path)
	var d: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return d


func _ready() -> void:
	var reg: Variant = _load_json(REGISTRY_PATH)
	var maps_json: Variant = _load_json(MAPS_JSON_PATH)

	# --- 1. 注册表结构 + token + gap ---
	assert(reg.has("maps") and reg["maps"].size() == 28, "registry must have 28 maps")
	var json_ids: Array = []
	for m in maps_json:
		json_ids.append(str(m["id"]))
	var token_errors: Array = Support.validate_tokens(reg)
	assert(token_errors.is_empty(), "token errors: " + str(token_errors.slice(0, 5)))
	var gap_errors: Array = Support.validate_gap_mapping(reg)
	assert(gap_errors.is_empty(), "gap errors: " + str(gap_errors.slice(0, 5)))

	# --- 2. 28图双向精确比较 ---
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

	for mid in json_ids:
		var gs0: Dictionary = Support.snapshot_game_state()
		Support.apply_fixture({})
		GameState.current_map_id = mid
		main._apply_current_map()
		await get_tree().process_frame
		var reg_map: Variant = null
		for m in reg["maps"]:
			if str(m["map_id"]) == mid:
				reg_map = m
				break
		assert(reg_map != null, "map not found: " + mid)
		assert(main.background.texture.resource_path == str(reg_map["background"]), "bg mismatch " + mid)
		var exp_e: Dictionary = Support.expected_entity_snapshot(reg_map)
		var act_e: Dictionary = Support.runtime_entity_snapshot(main)
		var e_errs: Array = Support.validate_entities(exp_e, act_e)
		assert(e_errs.is_empty(), "entity errors %s: %s" % [mid, str(e_errs.slice(0, 3))])
		var o_errs: Array = Support.validate_overlap(reg_map, act_e)
		assert(o_errs.is_empty(), "overlap %s: %s" % [mid, str(o_errs)])
		var x_errs: Array = Support.validate_exits(reg_map, main)
		assert(x_errs.is_empty(), "exit errors %s: %s" % [mid, str(x_errs)])
		Support.restore_game_state(gs0)
		Support.assert_game_state_restored(gs0)

	# --- 3. 动态矩阵（独立期望，数据驱动循环） ---
	var dyn: Array = reg.get("dynamic_scenarios", [])
	assert(dyn.size() >= 40, "need 40+ scenarios, got %d" % dyn.size())
	# 组覆盖断言
	var fuwa_c := 0; var pk_c := 0; var terr_c := 0; var fin_c := 0
	for s in dyn:
		var sid: String = str(s.get("scenario_id", ""))
		if "fuwa_messenger" in sid: fuwa_c += 1
		if sid.begins_with("pk_"): pk_c += 1
		if "territory" in sid: terr_c += 1
		if "demon_" in sid or "final" in sid: fin_c += 1
	assert(fuwa_c > 0 and pk_c > 0 and terr_c > 0 and fin_c > 0, "group coverage failed: fuwa=%d pk=%d terr=%d fin=%d" % [fuwa_c, pk_c, terr_c, fin_c])

	for s in dyn:
		var gs: Dictionary = Support.snapshot_game_state()
		Support.apply_fixture(s.get("fixture", {}))
		GameState.current_map_id = str(s.get("map_id", "cassano_city"))
		main._apply_current_map()
		await get_tree().process_frame
		# 查找注册表该图
		var dyn_reg_map: Variant = null
		for m in reg["maps"]:
			if str(m["map_id"]) == str(s.get("map_id", "")):
				dyn_reg_map = m
				break
		assert(dyn_reg_map != null, "dyn map not found: " + str(s.get("map_id", "")))
		# 使用独立scenario runner（不通过_condition_active推导）
		var dyn_errs: Array = Support.run_scenario(dyn_reg_map, s, main)
		assert(dyn_errs.is_empty(), "dyn %s: %s" % [str(s.get("scenario_id", "")), str(dyn_errs.slice(0, 3))])
		# 恢复并深度验证
		Support.restore_game_state(gs)
		Support.assert_game_state_restored(gs)

	# --- 4. 12类真实action路径 ---
	var gs_a: Dictionary = Support.snapshot_game_state()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	# 1. NPC对话
	Support.apply_fixture({})
	GameState.level = 30
	GameState.current_map_id = "cassano_city"
	main._apply_current_map()
	await get_tree().process_frame
	main._open_actor_dialogue("grocery")
	assert(main.dialogue_panel.visible, "NPC: dialogue not visible")
	assert(main.dialogue_panel.speaker_label.text == "杂货商", "NPC: wrong speaker")
	# 2. 商店（通过dialogue action）
	main._handle_dialogue_action("gold_buy")
	assert(main.gold_shop.visible, "shop: not visible")
	# 3. 仓库（通过dialogue action）
	main._handle_dialogue_action("warehouse")
	assert(main.warehouse_panel.visible, "warehouse: not visible")
	main.warehouse_panel.hide()
	# 4. 研究所
	main._handle_dialogue_action("research")
	assert(main.research_panel.visible, "research: not visible")
	main.research_panel.hide()
	# 5. 普通怪物
	GameState.current_map_id = "dream_swamp"
	main._apply_current_map()
	await get_tree().process_frame
	main._on_actor_input(click, "battle:spider")
	assert(main.scene_battle_controller.session != null, "monster: no session")
	assert(main.scene_battle_controller.active_monster_id == "spider", "monster: wrong ID")
	main.scene_battle_controller.cancel_battle()
	# 6. Boss
	GameState.current_map_id = "thunder_continent"
	main._apply_current_map()
	await get_tree().process_frame
	main._on_actor_input(click, "battle:thunder_boss_10")
	assert(main.scene_battle_controller.session != null, "boss: no session")
	assert(main.scene_battle_controller.active_monster_id == "thunder_boss_10", "boss: wrong ID")
	main.scene_battle_controller.cancel_battle()
	# 7. 领地报名官
	GameState.current_map_id = "cassano_city"
	main._apply_current_map()
	await get_tree().process_frame
	main._open_actor_dialogue("territory:cassano_city")
	assert(main.dialogue_panel.visible, "territory: dialogue not visible")
	# 8. 矿点（真实状态差：非空inventory槽位增加）
	GameState.current_map_id = "thunder_mine"
	GameState.level = 30
	main._apply_current_map()
	await get_tree().process_frame
	var mine_filled_before: int = 0
	for slot in GameState.inventory:
		if not slot.is_empty():
			mine_filled_before += 1
	main._on_actor_input(click, "mine:0")
	var mine_filled_after: int = 0
	for slot in GameState.inventory:
		if not slot.is_empty():
			mine_filled_after += 1
	assert(mine_filled_after > mine_filled_before, "mine: no item added (before=%d after=%d)" % [mine_filled_before, mine_filled_after])
	# 9. 抽奖箱（真实状态差）
	GameState.current_map_id = "lottery_room"
	GameState.magic_stones = 1000
	main._apply_current_map()
	await get_tree().process_frame
	var stones_b: int = GameState.magic_stones
	main._on_actor_input(click, "lottery:绿宝箱1")
	assert(GameState.magic_stones == stones_b - 28, "lottery: magic_stones not -28, got %d expected %d" % [GameState.magic_stones, stones_b - 28])
	# 10. 战魂箱 + 守卫battle
	GameState.war_soul_maze_active = true
	GameState.war_soul_guardian_revealed = false
	GameState.current_map_id = "war_soul_seal_maze"
	main._apply_current_map()
	await get_tree().process_frame
	main._on_actor_input(click, "war_soul_chest")
	assert(bool(GameState.war_soul_guardian_revealed), "war_soul: guardian not revealed")
	# 点击守卫进入battle
	main._on_actor_input(click, "battle:nameless_war_soul_keeper")
	assert(main.scene_battle_controller.session != null, "war_soul: guardian battle no session")
	assert(main.scene_battle_controller.active_monster_id == "nameless_war_soul_keeper", "war_soul: wrong guardian ID")
	main.scene_battle_controller.cancel_battle()
	# 11. 边缘出口
	Support.apply_fixture({})
	GameState.level = 30
	GameState.current_map_id = "cassano_city"
	main._apply_current_map()
	await get_tree().process_frame
	var left_btn: Button = main.direction_buttons["left"]
	left_btn.emit_signal("pressed")
	assert(GameState.current_map_id == "thunder_continent", "edge: did not travel")
	# 12. NPC传送
	GameState.current_map_id = "palace"
	main._apply_current_map()
	await get_tree().process_frame
	main._handle_dialogue_action("enter_lottery_room")
	assert(GameState.current_map_id == "lottery_room", "teleport: did not travel")
	Support.restore_game_state(gs_a)
	Support.assert_game_state_restored(gs_a)

	# --- 5. 全量action路由验证（真实dispatcher，精确route比较） ---
	var test_click := InputEventMouseButton.new()
	test_click.button_index = MOUSE_BUTTON_LEFT
	test_click.pressed = true
	# dialogue action由_handle_dialogue_action处理，单独清单+预期效果
	var dialogue_cases: Array = [
		{"action_id": "gold_buy", "expect": "gold_shop.visible and gold_shop.current_mode == 'buy'"},
		{"action_id": "gold_sell", "expect": "gold_shop.visible and gold_shop.current_mode == 'sell'"},
		{"action_id": "stone_buy", "expect": "stone_shop.visible and stone_shop.current_mode == 'buy'"},
		{"action_id": "stone_sell", "expect": "stone_shop.visible and stone_shop.current_mode == 'sell'"},
		{"action_id": "warehouse", "expect": "warehouse_panel.visible"},
		{"action_id": "pets", "expect": "pet_panel.visible"},
		{"action_id": "research", "expect": "research_panel.visible"},
		{"action_id": "enhancement", "expect": "enhancement_panel.visible"},
		{"action_id": "quests", "expect": "quest_panel.visible"},
		{"action_id": "enter_lottery_room", "expect": "current_map_id == 'lottery_room'"},
		{"action_id": "enter_dungeon", "expect": "current_map_id == 'dungeon'"},
	]
	# 声明式route期望表（不调用_world_action_route，不使用if/elif推导）
	var route_expectations: Dictionary = {
		"battle:": "battle",
		"mine:": "mine",
		"lottery:": "lottery",
		"war_soul_": "war_soul",
		"territory:": "territory",
	}
	# 收集所有world entity action及其预期route
	var world_action_cases: Array = []
	for m in reg["maps"]:
		for e in m["entities"]:
			var aid: String = str(e.get("action_id", ""))
			if aid == "" or aid.begins_with("decoration:"):
				continue
			# 跳过dialogue action
			var is_dialogue: bool = false
			for dc in dialogue_cases:
				if str(dc["action_id"]) == aid:
					is_dialogue = true
					break
			if is_dialogue:
				continue
			var expected_route: String = "npc_dialogue"
			for prefix: String in route_expectations:
				if aid.begins_with(prefix):
					expected_route = str(route_expectations[prefix])
					break
			world_action_cases.append({"action_id": aid, "expected_route": expected_route, "map_id": str(m["map_id"])})
	assert(world_action_cases.size() >= 100, "expected 100+ world actions, got %d" % world_action_cases.size())
	# 逐项调用真实dispatcher，用共用的validate_dispatch_result验证
	var routes_verified: Dictionary = {}
	for case in world_action_cases:
		var case_aid: String = str(case["action_id"])
		var case_route: String = str(case["expected_route"])
		var case_map: String = str(case["map_id"])
		var gs_route: Dictionary = Support.snapshot_game_state()
		Support.apply_fixture({})
		GameState.level = 30
		GameState.story_flags["king_rescued"] = true
		GameState.current_map_id = case_map
		main._apply_current_map()
		await get_tree().process_frame
		main.dialogue_panel.hide()
		var dispatch_result: Dictionary = main._dispatch_world_action(case_aid, test_click)
		var d_errors: Array = Support.validate_dispatch_result(dispatch_result, case_route, "OK", case_aid)
		assert(d_errors.is_empty(), "dispatch error for %s: %s" % [case_aid, str(d_errors)])
		routes_verified[case_route] = true
		Support.restore_game_state(gs_route)
		Support.assert_game_state_restored(gs_route)
	assert(routes_verified.has("battle"), "battle route not verified")
	assert(routes_verified.has("mine"), "mine route not verified")
	assert(routes_verified.has("lottery"), "lottery route not verified")
	assert(routes_verified.has("war_soul"), "war_soul route not verified")
	assert(routes_verified.has("territory"), "territory route not verified")
	assert(routes_verified.has("npc_dialogue"), "npc_dialogue route not verified")
	# dialogue action独立验证：逐项断言预期面板/模式/地图
	for dc in dialogue_cases:
		var da_id: String = str(dc["action_id"])
		var da_expect: String = str(dc["expect"])
		var gs_da: Dictionary = Support.snapshot_game_state()
		Support.apply_fixture({})
		GameState.level = 30
		GameState.current_map_id = "cassano_city"
		main._apply_current_map()
		await get_tree().process_frame
		main._handle_dialogue_action(da_id)
		# 逐项断言预期效果
		if da_id == "gold_buy":
			assert(main.gold_shop.visible and main.gold_shop.current_mode == "buy", "dialogue gold_buy: shop not visible or wrong mode")
		elif da_id == "gold_sell":
			assert(main.gold_shop.visible and main.gold_shop.current_mode == "sell", "dialogue gold_sell: shop not visible or wrong mode")
		elif da_id == "stone_buy":
			assert(main.stone_shop.visible and main.stone_shop.current_mode == "buy", "dialogue stone_buy: shop not visible or wrong mode")
		elif da_id == "stone_sell":
			assert(main.stone_shop.visible and main.stone_shop.current_mode == "sell", "dialogue stone_sell: shop not visible or wrong mode")
		elif da_id == "warehouse":
			assert(main.warehouse_panel.visible, "dialogue warehouse: panel not visible")
		elif da_id == "pets":
			assert(main.pet_panel.visible, "dialogue pets: panel not visible")
		elif da_id == "research":
			assert(main.research_panel.visible, "dialogue research: panel not visible")
		elif da_id == "enhancement":
			assert(main.enhancement_panel.visible, "dialogue enhancement: panel not visible")
		elif da_id == "quests":
			assert(main.quest_panel.visible, "dialogue quests: panel not visible")
		elif da_id == "enter_lottery_room":
			assert(GameState.current_map_id == "lottery_room", "dialogue enter_lottery_room: map not changed")
		elif da_id == "enter_dungeon":
			assert(GameState.current_map_id == "dungeon", "dialogue enter_dungeon: map not changed")
		Support.restore_game_state(gs_da)
		Support.assert_game_state_restored(gs_da)
	# C负向1: 篡改预期route -> 用同一validate_dispatch_result得到DISPATCH_ROUTE_MISMATCH
	var gs_cn1: Dictionary = Support.snapshot_game_state()
	Support.apply_fixture({})
	GameState.level = 30
	GameState.current_map_id = "cassano_city"
	main._apply_current_map()
	await get_tree().process_frame
	main.dialogue_panel.hide()
	var cn1_result: Dictionary = main._dispatch_world_action("grocery", test_click)
	var cn1_errors: Array = Support.validate_dispatch_result(cn1_result, "ZZZ_WRONG_ROUTE", "OK", "grocery")
	assert(Support.has_error_code(cn1_errors, "DISPATCH_ROUTE_MISMATCH"), "C-neg1: expected DISPATCH_ROUTE_MISMATCH, got: " + str(cn1_errors))
	Support.restore_game_state(gs_cn1)
	Support.assert_game_state_restored(gs_cn1)
	# C负向2: 篡改预期code -> 用同一validate_dispatch_result得到DISPATCH_CODE_MISMATCH
	var gs_cn2: Dictionary = Support.snapshot_game_state()
	Support.apply_fixture({})
	GameState.level = 30
	GameState.current_map_id = "cassano_city"
	main._apply_current_map()
	await get_tree().process_frame
	main.dialogue_panel.hide()
	var cn2_result: Dictionary = main._dispatch_world_action("grocery", test_click)
	var cn2_errors: Array = Support.validate_dispatch_result(cn2_result, "npc_dialogue", "ZZZ_WRONG_CODE", "grocery")
	assert(Support.has_error_code(cn2_errors, "DISPATCH_CODE_MISMATCH"), "C-neg2: expected DISPATCH_CODE_MISMATCH, got: " + str(cn2_errors))
	Support.restore_game_state(gs_cn2)
	Support.assert_game_state_restored(gs_cn2)

	# --- 5c. 检查点D：领地六图四态（24个状态） ---
	var territory_maps_d: Array = ["cassano_city","thunder_continent","desert","dream_swamp","ice_palace","avit_island"]
	var territory_config: Dictionary = {
		"cassano_city": {"challenger_id": "territory_cassano_guard", "required_level": 6, "rank_name": "王"},
		"thunder_continent": {"challenger_id": "territory_thunder_guard", "required_level": 1, "rank_name": "勋爵"},
		"desert": {"challenger_id": "territory_desert_guard", "required_level": 2, "rank_name": "子爵"},
		"dream_swamp": {"challenger_id": "territory_swamp_guard", "required_level": 3, "rank_name": "伯爵"},
		"ice_palace": {"challenger_id": "territory_ice_guard", "required_level": 4, "rank_name": "侯爵"},
		"avit_island": {"challenger_id": "territory_avit_guard", "required_level": 5, "rank_name": "公爵"},
	}
	var merit_for_level: Array = [0, 1000, 3000, 6000, 15000, 30000, 100000]
	var d_completed_cases: Array = []
	for tmap: String in territory_maps_d:
		var tcfg: Dictionary = territory_config[tmap]
		var challenger_id: String = str(tcfg["challenger_id"])
		var req_level: int = int(tcfg["required_level"])
		# --- 状态1: rank_low（D-01: 调真实begin_territory_challenge） ---
		var gs_d1: Dictionary = Support.snapshot_game_state()
		Support.apply_fixture({})
		GameState.level = 30
		GameState.nobility_merit = 0
		GameState.current_map_id = tmap
		main._apply_current_map()
		await get_tree().process_frame
		var d1_result: Dictionary = GameState.begin_territory_challenge(tmap)
		assert(not bool(d1_result.get("success", true)), "D rank_low %s: begin should fail" % tmap)
		assert(str(d1_result.get("reason", "")) == "rank_too_low", "D rank_low %s: expected rank_too_low, got %s" % [tmap, str(d1_result.get("reason",""))])
		assert(str(GameState.pending_territory_challenge) == "", "D rank_low %s: pending should be empty" % tmap)
		assert(not main.interactive_actors.has("battle:" + challenger_id), "D rank_low %s: challenger should not exist" % tmap)
		d_completed_cases.append(tmap + ":rank_low")
		Support.restore_game_state(gs_d1)
		Support.assert_game_state_restored(gs_d1)
		# --- 状态2: rank_ok ---
		var gs_d2: Dictionary = Support.snapshot_game_state()
		Support.apply_fixture({})
		GameState.level = 30
		GameState.nobility_merit = int(merit_for_level[req_level])
		GameState.current_day = 1
		GameState.current_map_id = tmap
		main._apply_current_map()
		await get_tree().process_frame
		var d2_status: Dictionary = GameState.territory_challenge_status(tmap)
		assert(bool(d2_status.get("available", false)), "D rank_ok %s: expected available, got %s" % [tmap, str(d2_status)])
		assert(not main.interactive_actors.has("battle:" + challenger_id), "D rank_ok %s: challenger should not exist yet" % tmap)
		d_completed_cases.append(tmap + ":rank_ok")
		Support.restore_game_state(gs_d2)
		Support.assert_game_state_restored(gs_d2)
		# --- 状态3: challenger_active（D-02: battle session锁定） ---
		var gs_d3: Dictionary = Support.snapshot_game_state()
		Support.apply_fixture({})
		GameState.level = 30
		GameState.nobility_merit = int(merit_for_level[req_level])
		GameState.current_day = 1
		GameState.player_current_hp = 999999
		GameState.current_map_id = tmap
		main._apply_current_map()
		await get_tree().process_frame
		if main.scene_battle_controller.is_active():
			main.scene_battle_controller.cancel_battle()
		await get_tree().process_frame
		main._start_territory_challenge(tmap)
		await get_tree().create_timer(0.15).timeout
		assert(str(GameState.pending_territory_challenge) == tmap, "D challenger_active %s: pending != map (pending=%s)" % [tmap, str(GameState.pending_territory_challenge)])
		var d3_action_id: String = "battle:" + challenger_id
		assert(main.interactive_actors.has(d3_action_id), "D challenger_active %s: challenger not in scene" % tmap)
		# D-02: battle session锁定正确challenger ID
		assert(main.scene_battle_controller.session != null, "D challenger_active %s: battle session not created" % tmap)
		assert(str(main.scene_battle_controller.active_monster_id) == challenger_id, "D challenger_active %s: wrong monster ID %s" % [tmap, str(main.scene_battle_controller.active_monster_id)])
		# 验证挑战者kind/action/asset/position/size
		var d3_actor: TextureRect = main.interactive_actors[d3_action_id]
		assert(str(d3_actor.get_meta("world_entity_kind", "")) == "monster", "D challenger_active %s: wrong kind" % tmap)
		assert(str(d3_actor.get_meta("world_action_id", "")) == d3_action_id, "D challenger_active %s: wrong action_id" % tmap)
		assert(d3_actor.texture.resource_path.ends_with("image_1072.png"), "D challenger_active %s: wrong asset" % tmap)
		assert(d3_actor.position == Vector2(535, 205), "D challenger_active %s: wrong position" % tmap)
		assert(d3_actor.size == Vector2(101, 132), "D challenger_active %s: wrong size" % tmap)
		d_completed_cases.append(tmap + ":challenger_active")
		# 结束battle session避免泄漏
		main.scene_battle_controller.cancel_battle()
		assert(main.scene_battle_controller.session == null, "D challenger_active %s: session not cleared after cancel" % tmap)
		Support.restore_game_state(gs_d3)
		Support.assert_game_state_restored(gs_d3)
		# --- 状态4: owned（D-03: 报名官显示已占领） ---
		var gs_d4: Dictionary = Support.snapshot_game_state()
		Support.apply_fixture({})
		GameState.level = 30
		GameState.nobility_merit = int(merit_for_level[req_level])
		GameState.current_day = 1
		GameState.player_current_hp = 999999
		GameState.current_map_id = tmap
		main._apply_current_map()
		await get_tree().process_frame
		if main.scene_battle_controller.is_active():
			main.scene_battle_controller.cancel_battle()
		main._start_territory_challenge(tmap)
		await get_tree().process_frame
		var d4_resolve: Dictionary = GameState.resolve_territory_challenge(challenger_id, true)
		assert(bool(d4_resolve.get("resolved", false)), "D owned %s: resolve failed" % tmap)
		assert(bool(d4_resolve.get("victory", false)), "D owned %s: not victory" % tmap)
		assert(str(GameState.owned_territory) == tmap, "D owned %s: owned_territory != map" % tmap)
		assert(str(GameState.pending_territory_challenge) == "", "D owned %s: pending not cleared" % tmap)
		main._apply_current_map()
		await get_tree().process_frame
		assert(not main.interactive_actors.has("battle:" + challenger_id), "D owned %s: challenger still in scene" % tmap)
		# D-03: 报名官对话反映已占领
		main._open_actor_dialogue("territory:" + tmap)
		assert(main.dialogue_panel.visible, "D owned %s: territory dialogue not visible" % tmap)
		assert("你现在正是这里的保护者" in main.dialogue_panel.body_label.text, "D owned %s: dialogue does not show owned status" % tmap)
		d_completed_cases.append(tmap + ":owned")
		Support.restore_game_state(gs_d4)
		Support.assert_game_state_restored(gs_d4)
	# D正向覆盖验证
	var d_coverage_errors: Array = Support.validate_territory_coverage(d_completed_cases, 24)
	assert(d_coverage_errors.is_empty(), "D coverage: " + str(d_coverage_errors))
	# D-04: HP变异负向 -> VALUE_MISMATCH:player_current_hp
	var d_neg_snap: Dictionary = Support.snapshot_game_state()
	var d_neg_hp: int = GameState.player_current_hp
	GameState.player_current_hp = d_neg_hp + 999
	var d_neg_diffs: Array = Support.game_state_restore_differences(d_neg_snap)
	assert(Support.has_error_code(d_neg_diffs, "VALUE_MISMATCH:player_current_hp"), "D-04: expected VALUE_MISMATCH:player_current_hp, got: " + str(d_neg_diffs))
	Support.restore_game_state(d_neg_snap)
	Support.assert_game_state_restored(d_neg_snap)
	# D-05: 负向覆盖 - 删除一个case -> TERRITORY_STATE_COVERAGE_MISSING
	var d_neg_cases: Array = d_completed_cases.duplicate()
	d_neg_cases.erase("cassano_city:owned")
	var d_neg_cov_errors: Array = Support.validate_territory_coverage(d_neg_cases, 24)
	assert(Support.has_error_code(d_neg_cov_errors, "TERRITORY_STATE_COVERAGE_MISSING"), "D-05: expected TERRITORY_STATE_COVERAGE_MISSING, got: " + str(d_neg_cov_errors))

	# --- 5d. 检查点E：出口metadata值比较 + 字段级gap映射 ---
	# E负向1: 篡改出口metadata值 -> EXIT_METADATA_VALUE_MISMATCH
	var gs_e1: Dictionary = Support.snapshot_game_state()
	Support.apply_fixture({})
	GameState.level = 30
	GameState.current_map_id = "cassano_city"
	main._apply_current_map()
	await get_tree().process_frame
	# 找到left出口并篡改required_level
	var e1_btn: Button = main.direction_buttons["left"]
	assert(e1_btn.visible, "E-neg1: left exit not visible")
	assert(e1_btn.has_meta("world_required_level"), "E-neg1: world_required_level not set")
	var e1_orig_level: int = int(e1_btn.get_meta("world_required_level"))
	e1_btn.set_meta("world_required_level", e1_orig_level + 999)
	var e1_errors: Array = Support.validate_exits(reg["maps"][0], main)
	assert(Support.has_error_code(e1_errors, "EXIT_METADATA_VALUE_MISMATCH:world_required_level"), "E-neg1: expected EXIT_METADATA_VALUE_MISMATCH:world_required_level, got: " + str(e1_errors))
	# 恢复
	e1_btn.set_meta("world_required_level", e1_orig_level)
	var e1_restored: Array = Support.validate_exits(reg["maps"][0], main)
	assert(e1_restored.is_empty(), "E-neg1: restore failed, errors: " + str(e1_restored))
	Support.restore_game_state(gs_e1)
	Support.assert_game_state_restored(gs_e1)
	# E-neg1b: 篡改direction metadata -> EXIT_METADATA_VALUE_MISMATCH:world_direction
	var gs_e1b: Dictionary = Support.snapshot_game_state()
	Support.apply_fixture({})
	GameState.level = 30
	GameState.current_map_id = "cassano_city"
	main._apply_current_map()
	await get_tree().process_frame
	var e1b_btn: Button = main.direction_buttons["left"]
	assert(e1b_btn.visible, "E-neg1b: left exit not visible")
	assert(e1b_btn.has_meta("world_direction"), "E-neg1b: world_direction not set")
	var e1b_orig_dir: String = str(e1b_btn.get_meta("world_direction"))
	e1b_btn.set_meta("world_direction", "ZZZ_WRONG_DIRECTION")
	var e1b_errors: Array = Support.validate_exits(reg["maps"][0], main)
	assert(Support.has_error_code(e1b_errors, "EXIT_METADATA_VALUE_MISMATCH:world_direction"), "E-neg1b: expected EXIT_METADATA_VALUE_MISMATCH:world_direction, got: " + str(e1b_errors))
	e1b_btn.set_meta("world_direction", e1b_orig_dir)
	var e1b_restored: Array = Support.validate_exits(reg["maps"][0], main)
	assert(e1b_restored.is_empty(), "E-neg1b: restore failed, errors: " + str(e1b_restored))
	Support.restore_game_state(gs_e1b)
	Support.assert_game_state_restored(gs_e1b)
	# E-neg2: 字段级gap未覆盖 -> GAP_FIELD_UNCOVERED
	var e2_reg: Dictionary = (reg as Dictionary).duplicate(true)
	var e2_gaps: Array = e2_reg.get("evidence_gaps", [])
	var e2_removed: bool = false
	for gi in range(e2_gaps.size()):
		var g: Dictionary = e2_gaps[gi]
		if str(g.get("map_id", "")) == "cassano_city" and "exit:" in str(g.get("object_ids", [""])[0]):
			e2_gaps.remove_at(gi)
			e2_removed = true
			break
	assert(e2_removed, "E-neg2: could not find exit gap to remove")
	e2_reg["evidence_gaps"] = e2_gaps
	var e2_errors: Array = Support.validate_gap_mapping(e2_reg)
	assert(Support.has_error_code(e2_errors, "GAP_FIELD_UNCOVERED"), "E-neg2: expected GAP_FIELD_UNCOVERED, got: " + str(e2_errors))
	# E-neg3: 向gaps加入虚假字段 -> GAP_FIELD_EXTRA
	var e3_reg: Dictionary = (reg as Dictionary).duplicate(true)
	var e3_gaps: Array = e3_reg.get("evidence_gaps", [])
	e3_gaps.append({"map_id": "cassano_city", "object_ids": ["exit:avit_island"], "field": "ZZZ_FAKE_FIELD", "missing": "fake", "command": "fake"})
	e3_reg["evidence_gaps"] = e3_gaps
	var e3_errors: Array = Support.validate_gap_mapping(e3_reg)
	assert(Support.has_error_code(e3_errors, "GAP_FIELD_EXTRA"), "E-neg3: expected GAP_FIELD_EXTRA, got: " + str(e3_errors))
	# E-neg4: 篡改registry runtime_availability_rule -> EXIT_RUNTIME_RULE_MISMATCH
	var e4_reg: Dictionary = (reg as Dictionary).duplicate(true)
	var e4_found: bool = false
	for m in e4_reg["maps"]:
		if str(m["map_id"]) == "cassano_city":
			for ex in m["exits"]:
				if str(ex.get("target_map_id", "")) == "thunder_continent":
					ex["runtime_availability_rule"] = "ZZZ_WRONG_RULE"
					e4_found = true
					break
			break
	assert(e4_found, "E-neg4: could not find target exit to tamper")
	var gs_e4: Dictionary = Support.snapshot_game_state()
	Support.apply_fixture({})
	GameState.level = 30
	GameState.current_map_id = "cassano_city"
	main._apply_current_map()
	await get_tree().process_frame
	var e4_reg_map: Variant = null
	for m in e4_reg["maps"]:
		if str(m["map_id"]) == "cassano_city":
			e4_reg_map = m
			break
	var e4_errors: Array = Support.validate_exits(e4_reg_map, main)
	assert(Support.has_error_code(e4_errors, "EXIT_RUNTIME_RULE_MISMATCH"), "E-neg4: expected EXIT_RUNTIME_RULE_MISMATCH, got: " + str(e4_errors))
	Support.restore_game_state(gs_e4)
	Support.assert_game_state_restored(gs_e4)
	# B-01: warehouse变异 -> VALUE_MISMATCH:warehouse
	var b_neg_snap: Dictionary = Support.snapshot_game_state()
	GameState.warehouse[0] = {"item_id": "NEGATIVE_WAREHOUSE_SENTINEL"}
	var b_neg_diffs: Array = Support.game_state_restore_differences(b_neg_snap)
	assert(Support.has_error_code(b_neg_diffs, "VALUE_MISMATCH:warehouse"), "B-01: expected VALUE_MISMATCH:warehouse, got: " + str(b_neg_diffs))
	Support.restore_game_state(b_neg_snap)
	Support.assert_game_state_restored(b_neg_snap)
	# B-02: 类型不匹配 -> TYPE_MISMATCH
	var type_test_before: Dictionary = {"test_val": 1}
	var type_test_after: Dictionary = {"test_val": "1"}
	var type_diffs: Array = Support._compare_snapshots(type_test_before, type_test_after)
	assert(Support.has_error_code(type_diffs, "TYPE_MISMATCH"), "B-02: expected TYPE_MISMATCH, got: " + str(type_diffs))

	# --- 6. 9项负向验证（内存变异） ---
	# 准备基准
	Support.apply_fixture({})
	GameState.level = 30
	GameState.current_map_id = "cassano_city"
	main._apply_current_map()
	await get_tree().process_frame
	var b_reg: Variant = null
	for m in reg["maps"]:
		if str(m["map_id"]) == "cassano_city":
			b_reg = m
			break
	var b_exp: Dictionary = Support.expected_entity_snapshot(b_reg)
	var b_act: Dictionary = Support.runtime_entity_snapshot(main)
	# 1. 从actual运行时快照删除实体 -> ENTITY_SET_MISSING
	var n1: Dictionary = b_act.duplicate(true)
	var n1_target: String = str(b_exp.keys()[0])
	assert(n1.has(n1_target), "neg1: mutation target %s not found in actual" % n1_target)
	n1.erase(n1_target)
	assert(not n1.has(n1_target), "neg1: mutation failed, target still present")
	assert(Support.has_error_code(Support.validate_entities(b_exp, n1), "ENTITY_SET_MISSING"), "neg1")
	# 2. 增加不应出现实体 -> ENTITY_SET_EXTRA
	var n2: Dictionary = b_act.duplicate(true)
	assert(not n2.has("ZZZ_FAKE"), "neg2: ZZZ_FAKE already exists before mutation")
	n2["ZZZ_FAKE"] = {"kind":"npc","action_id":"zzz","asset":"","position":[0,0],"size":[10,10],"mouse_filter":0,"y_bottom":10}
	assert(n2.has("ZZZ_FAKE"), "neg2: mutation failed, ZZZ_FAKE not added")
	assert(Support.has_error_code(Support.validate_entities(b_exp, n2), "ENTITY_SET_EXTRA"), "neg2")
	# 3. 修改kind -> ENTITY_KIND_MISMATCH
	var n3: Dictionary = b_exp.duplicate(true)
	var n3_target: String = str(b_exp.keys()[0])
	var n3_orig_kind: String = str(n3[n3_target]["kind"])
	n3[n3_target]["kind"] = "ZZZ_WRONG"
	assert(str(n3[n3_target]["kind"]) != n3_orig_kind, "neg3: mutation failed, kind unchanged")
	assert(Support.has_error_code(Support.validate_entities(n3, b_act), "ENTITY_KIND_MISMATCH"), "neg3")
	# 4. 出口direction -> EXIT_DIRECTION_MISMATCH
	var n4: Dictionary = (b_reg as Dictionary).duplicate(true)
	var n4_orig_dir: String = str((n4["exits"] as Array)[0]["direction"])
	(n4["exits"] as Array)[0]["direction"] = "ZZZ_WRONG"
	assert(str((n4["exits"] as Array)[0]["direction"]) != n4_orig_dir, "neg4: mutation failed, direction unchanged")
	assert(Support.has_error_code(Support.validate_exits(n4, main), "EXIT_DIRECTION_MISMATCH"), "neg4")
	# 5. 修改真实scenario expected_dynamic_present -> scenario runner失败
	# 复制palace_king_present scenario，添加不存在的期望实体
	var n5_scenario: Dictionary = {}
	for s in dyn:
		if str(s.get("scenario_id", "")) == "palace_king_present":
			n5_scenario = (s as Dictionary).duplicate(true)
			break
	assert(not n5_scenario.is_empty(), "neg5: palace_king_present scenario not found")
	(n5_scenario["expected_dynamic_present"] as Array).append("ZZZ_FAKE_ENTITY")
	var n5_palace_reg: Variant = null
	for m in reg["maps"]:
		if str(m["map_id"]) == "palace":
			n5_palace_reg = m
			break
	var gs_n5: Dictionary = Support.snapshot_game_state()
	Support.apply_fixture(n5_scenario.get("fixture", {}))
	GameState.current_map_id = "palace"
	main._apply_current_map()
	await get_tree().process_frame
	var n5_errs: Array = Support.run_scenario(n5_palace_reg, n5_scenario, main)
	assert(Support.has_error_code(n5_errs, "SCENARIO_PRESENT_NOT_IN_REGISTRY"), "neg5: expected SCENARIO_PRESENT_NOT_IN_REGISTRY but got: " + str(n5_errs.slice(0, 3)))
	Support.restore_game_state(gs_n5)
	# 6. 移除运行时装饰节点metadata -> 验证器失败
	# 使用palace（确定含装饰），先assert找到装饰，再移除metadata
	Support.apply_fixture({})
	GameState.level = 30
	GameState.current_map_id = "palace"
	main._apply_current_map()
	await get_tree().process_frame
	var n6_palace_reg: Variant = null
	for m in reg["maps"]:
		if str(m["map_id"]) == "palace":
			n6_palace_reg = m
			break
	var n6_pal_exp: Dictionary = Support.expected_always_entity_snapshot(n6_palace_reg)
	var n6_deco_node: Node = null
	for child in main.actor_layer.get_children():
		if child is TextureRect and child.has_meta("world_entity_kind") and str(child.get_meta("world_entity_kind")) == "decoration":
			n6_deco_node = child
			break
	assert(n6_deco_node != null, "neg6: no decoration node found in palace")
	var n6_saved_id: String = str(n6_deco_node.get_meta("world_entity_id"))
	n6_deco_node.remove_meta("world_entity_id")
	var n6_pal_act: Dictionary = Support.runtime_entity_snapshot(main)
	var n6_errs: Array = Support.validate_entities(n6_pal_exp, n6_pal_act)
	assert(Support.has_error_code(n6_errs, "ENTITY_SET_MISSING"), "neg6: expected ENTITY_SET_MISSING but got: " + str(n6_errs))
	# 恢复metadata并验证通过
	n6_deco_node.set_meta("world_entity_id", n6_saved_id)
	var n6_act_restored: Dictionary = Support.runtime_entity_snapshot(main)
	assert(Support.validate_entities(n6_pal_exp, n6_act_restored).is_empty(), "neg6: restore failed")
	# 7. 未知action传入真实dispatcher -> UNSUPPORTED_ACTION，不打开面板/不战斗/不改地图/不改资源
	var gs_n7_outer: Dictionary = Support.snapshot_game_state()
	Support.apply_fixture({})
	GameState.level = 30
	GameState.current_map_id = "cassano_city"
	main._apply_current_map()
	await get_tree().process_frame
	main.dialogue_panel.hide()
	# F-01: 在dispatch之前取得before_dispatch快照
	var gs_n7_before: Dictionary = Support.snapshot_game_state()
	var n7_result: Dictionary = main._dispatch_world_action("zzz_unknown_action", test_click)
	assert(str(n7_result.get("code", "")) == "UNSUPPORTED_ACTION", "neg7: expected UNSUPPORTED_ACTION, got: " + str(n7_result))
	assert(not main.dialogue_panel.visible, "neg7: dialogue opened for unknown action")
	assert(main.scene_battle_controller.session == null, "neg7: battle session created for unknown action")
	assert(GameState.current_map_id == "cassano_city", "neg7: map changed for unknown action")
	# F-01: 在restore之前断言dispatch没有改变任何GameState字段
	var n7_diffs: Array = Support.game_state_restore_differences(gs_n7_before)
	assert(n7_diffs.is_empty(), "neg7: unknown action changed GameState: " + str(n7_diffs))
	Support.restore_game_state(gs_n7_outer)
	Support.assert_game_state_restored(gs_n7_outer)
	# 8. 移除Boss exception -> OVERLAP_EXCEPTION_MISSING
	Support.apply_fixture({})
	GameState.level = 30
	GameState.current_map_id = "thunder_continent"
	main._apply_current_map()
	await get_tree().process_frame
	var t_reg: Variant = null
	for m in reg["maps"]:
		if str(m["map_id"]) == "thunder_continent":
			t_reg = m
			break
	var n8: Dictionary = (t_reg as Dictionary).duplicate(true)
	var n8_exception_removed: bool = false
	for e in n8["entities"]:
		if "native_overlap_exception" in e:
			e.erase("native_overlap_exception")
			n8_exception_removed = true
			break
	assert(n8_exception_removed, "neg8: mutation failed, no exception was removed")
	var n8a: Dictionary = Support.runtime_entity_snapshot(main)
	assert(Support.has_error_code(Support.validate_overlap(n8, n8a), "OVERLAP_EXCEPTION_MISSING"), "neg8")
	# 9. token不存在 -> EVIDENCE_TOKEN_MISS
	var n9: Dictionary = (reg as Dictionary).duplicate(true)
	var n9_token_mutated: bool = false
	for m in n9["maps"]:
		if str(m["map_id"]) == "cassano_city":
			var orig_tokens: Array = (m["entities"] as Array)[0].get("evidence_tokens", [])
			(m["entities"] as Array)[0]["evidence_tokens"] = ["ZZZ_NO_TOKEN"]
			n9_token_mutated = str((m["entities"] as Array)[0]["evidence_tokens"]) != str(orig_tokens)
			break
	assert(n9_token_mutated, "neg9: mutation failed, token not replaced")
	assert(Support.has_error_code(Support.validate_tokens(n9), "EVIDENCE_TOKEN_MISS"), "neg9")

	print("PASS checkpoint A+B+C+D+E+F: independent always, scenario partition, strict deep equality, real dispatcher, unknown action, 24 territory states, exit metadata value comparison, field-level gap mapping, 9 negative protections, 50-scene full regression")
	get_tree().quit(0)
