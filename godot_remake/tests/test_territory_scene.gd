extends Node

const WorldService = preload("res://scripts/world_service.gd")
const CombatService = preload("res://scripts/combat_service.gd")


func _ready() -> void:
	var world := WorldService.new()
	var combat := CombatService.new(7)
	# 主干链按原版 character 1071 箭头表修正：戈壁的入口是卡萨诺城的 bottom 捷径，
	# 不是雷鸣大陆；雷鸣大陆在原版没有通往戈壁的箭头。证据见
	# docs/evidence/native_map_links.json（frame 8 / frame 12 / frame 16）。
	assert(world.can_travel("cassano_city", "thunder_continent"), "Cassano does not lead to Thunder Continent")
	assert(world.can_travel("cassano_city", "desert"), "Cassano does not lead to the desert")
	assert(world.can_travel("desert", "dream_swamp"), "desert does not lead to Dream Swamp")
	assert(world.can_travel("dream_swamp", "ice_palace"), "Dream Swamp does not lead to Ice Palace")
	assert(world.can_travel("ice_palace", "avit_island"), "Ice Palace does not lead to Avit Island")
	assert(world.can_travel("avit_island", "volcano"), "Avit Island does not lead to the volcano")
	assert(world.can_travel("volcano", "abyss_maze"), "volcano does not lead to the Abyss Maze")
	assert(world.can_travel("ice_palace", "ice_border"), "Ice Palace does not lead to the snow border")
	# 原版双向捷径：戈壁/亚维特岛都直接退回卡萨诺城，领地图不能变成只进不出。
	assert(world.can_travel("desert", "cassano_city"), "desert lost the native shortcut back to Cassano")
	assert(world.can_travel("avit_island", "cassano_city"), "Avit Island lost the native shortcut back to Cassano")
	# 重制版自造、原版没有的边，删掉后不得复活。
	assert(not world.can_travel("thunder_continent", "desert"), "remake-only Thunder->desert edge came back")
	assert(not world.can_travel("palace", "ice_palace"), "remake-only palace->Ice Palace edge came back")
	assert(not world.can_travel("ice_palace", "palace"), "remake-only Ice Palace->palace edge came back")

	# 用户 2026-08-21 取消地图等级门槛：1 级即可进入全部战斗图，
	# 避免「练级要先有等级」的死锁。剧情/爵位/星期门槛不受影响，另有测试覆盖。
	GameState.level = 1
	for gated_map in ["thunder_continent", "desert", "dream_swamp", "ice_palace", "avit_island", "volcano", "abyss_maze"]:
		assert(GameState.map_entry_required_level(gated_map) == 1,
			"map level gate still present on %s" % gated_map)
		assert(GameState.can_enter_map(gated_map),
			"level-1 player cannot reach %s after level gates were removed" % gated_map)

	var boss_ids := ["thunder_boss_10", "desert_boss_20", "swamp_boss_30", "ice_boss_50", "avit_boss_70", "volcano_boss_90", "abyss_boss_100"]
	var boss_levels := [10, 20, 30, 50, 70, 90, 100]
	for index in boss_ids.size():
		var monster := combat.get_monster(boss_ids[index])
		assert(int(monster.get("level", 0)) == boss_levels[index], "original mainland boss level is incorrect")
		assert(int(combat.victory_rewards(boss_ids[index]).get("military_merit", 0)) == 10000, "mainland boss did not receive x10 military merit")
	var territory_guard_ids := [
		"territory_thunder_guard", "territory_desert_guard", "territory_swamp_guard",
		"territory_ice_guard", "territory_avit_guard", "territory_cassano_guard",
	]
	for guard_id: String in territory_guard_ids:
		assert(bool(combat.get_monster(guard_id).get("is_boss", false)), "SWF isBoss flag is missing: " + guard_id)

	GameState.current_day = 31
	GameState.current_map_id = "thunder_continent"
	GameState.owned_territory = ""
	GameState.pending_territory_challenge = ""
	GameState.last_territory_challenge_day = 0
	GameState.last_territory_reward_day = 0
	GameState.nobility_merit = 999
	assert(GameState.begin_territory_challenge("thunder_continent").reason == "rank_too_low", "territory rank requirement was ignored")
	GameState.nobility_merit = 1000
	var challenge := GameState.begin_territory_challenge("thunder_continent")
	assert(challenge.success and challenge.challenger_id == "territory_thunder_guard", "territory challenge did not start")
	assert(GameState.resolve_territory_challenge("territory_thunder_guard", false).resolved, "failed challenge was not settled")
	assert(GameState.owned_territory.is_empty(), "failed challenge granted territory ownership")
	assert(GameState.begin_territory_challenge("thunder_continent").reason == "already_challenged", "same-day challenge limit is missing")

	GameState.advance_day()
	assert(GameState.begin_territory_challenge("thunder_continent").success, "challenge did not reset on the next day")
	var victory := GameState.resolve_territory_challenge("territory_thunder_guard", true)
	assert(victory.victory and GameState.owned_territory == "thunder_continent", "victory did not grant territory ownership")
	var reward := GameState.claim_territory_reward("thunder_continent")
	assert(reward.success and reward.item_ids.size() == 5, "Thunder Continent daily reward is incomplete")
	assert(GameState.claim_territory_reward("thunder_continent").reason == "already_claimed", "territory reward can be claimed twice")

	GameState.current_day += 1
	GameState.current_map_id = "desert"
	GameState.nobility_merit = 3000
	assert(GameState.begin_territory_challenge("desert").success, "second territory challenge did not start")
	GameState.resolve_territory_challenge("territory_desert_guard", true)
	assert(GameState.owned_territory == "desert", "new territory did not replace the previous protected map")

	GameState.save_path = "user://test_territory_save.json"
	assert(GameState.save_game(), "territory save failed")
	GameState.owned_territory = ""
	GameState.last_territory_challenge_day = 0
	assert(GameState.load_game(), "territory load failed")
	assert(GameState.owned_territory == "desert" and GameState.last_territory_challenge_day == GameState.current_day, "territory save fields were not restored")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))
	GameState.save_path = GameState.SAVE_PATH

	GameState.current_map_id = "cassano_city"
	GameState.level = 100
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	assert(main.interactive_actors.has("territory:cassano_city"), "Cassano occupation officer is missing")
	main._travel_to("thunder_continent")
	await get_tree().process_frame
	assert(main.interactive_actors.has("battle:thunder_boss_10"), "Thunder Continent boss is missing from the scene")
	assert(main.interactive_actors.has("territory:thunder_continent"), "Thunder Continent occupation officer is missing")
	assert(not main.interactive_actors.has("battle:territory_thunder_guard"), "territory challenger is visible before selecting challenge")
	main._open_actor_dialogue("territory:thunder_continent")
	assert(main.dialogue_panel.visible and main.dialogue_panel.body_label.text.contains("唯一保护地"), "territory briefing did not open")

	GameState.current_day += 1
	GameState.last_territory_challenge_day = 0
	GameState.pending_territory_challenge = ""
	GameState.nobility_merit = 1000
	GameState.player_current_hp = int(GameState.get_player_stats().get("max_hp", 1))
	main._start_territory_challenge("thunder_continent")
	var transient_action := "battle:territory_thunder_guard"
	assert(GameState.pending_territory_challenge == "thunder_continent", "dialogue challenge did not start the territory session")
	assert(main.interactive_actors.has(transient_action), "territory challenger did not appear after selecting challenge")
	var challenger_actor: TextureRect = main.interactive_actors[transient_action]
	assert(challenger_actor.texture.resource_path.ends_with("image_1072.png") and challenger_actor.size.is_equal_approx(Vector2(101, 132)), "territory challenger does not use the SWF generic Boss clip")
	assert(main.scene_battle_controller.is_active() and main.scene_battle_controller.active_monster_id == "territory_thunder_guard", "territory challenger did not enter scene combat")
	main.scene_battle_controller.cancel_battle()
	main._on_scene_battle_finished("territory_thunder_guard", true)
	assert(not main.interactive_actors.has(transient_action), "resolved transient territory challenger remained on the map")

	# P2 拒签整改：退出前恢复帧，让被取消/挂起的协程状态完成（消除 GDScriptFunctionState 泄漏）
	await get_tree().process_frame
	await get_tree().process_frame
	print("PASS mainland map chain, native territory Boss transition, daily reward, and save v11")
	get_tree().quit(0)
