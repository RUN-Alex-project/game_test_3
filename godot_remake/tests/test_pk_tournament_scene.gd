extends Node

const CombatService = preload("res://scripts/combat_service.gd")
const WorldService = preload("res://scripts/world_service.gd")


func _ready() -> void:
	var world := WorldService.new()
	var arena_ids := ["pk_arena", "pk_arena_2", "pk_arena_3"]
	var champion_ids := ["pk_champion_60", "pk_champion_100", "pk_champion_130"]
	for index in arena_ids.size():
		var map_id: String = arena_ids[index]
		assert(world.get_map(map_id).background.ends_with("image_1294.jpg"), "PK arena background differs from the SWF: " + map_id)
		assert(world.encounters_for(map_id) == [champion_ids[index]], "PK arena has the wrong champion: " + map_id)
		assert(world.can_travel(map_id, "cassano_city"), "PK arena cannot return to Cassano: " + map_id)
	assert(not world.can_travel("palace", "pk_arena"), "PK arena became a normal palace exit")

	GameState.current_day = 5
	GameState.level = 60
	GameState.last_pk_race_day = 0
	GameState.pk_race_active = false
	assert(GameState.register_pk_race().reason == "not_saturday", "PK registration opened outside Saturday")

	GameState.current_day = 6
	var group_60 := GameState.register_pk_race()
	assert(group_60.success and group_60.map_id == "pk_arena", "level 60 was not assigned to arena one")
	assert(GameState.pk_race_active and GameState.current_map_id == "pk_arena", "PK registration did not activate the match")
	GameState.finish_pk_race(false)
	assert(not GameState.pk_race_active, "abandoned PK match stayed active")
	assert(GameState.register_pk_race().reason == "already_entered", "same-day PK registration was allowed twice")

	GameState.current_day = 13
	GameState.level = 61
	var group_100_low := GameState.register_pk_race()
	assert(group_100_low.success and group_100_low.map_id == "pk_arena_2", "level 61 was not assigned to arena two")
	GameState.finish_pk_race()
	GameState.current_day = 20
	GameState.level = 100
	assert(GameState.register_pk_race().map_id == "pk_arena_2", "level 100 was not assigned to arena two")
	GameState.finish_pk_race()
	GameState.current_day = 27
	GameState.level = 101
	assert(GameState.register_pk_race().map_id == "pk_arena_3", "level 101 was not assigned to arena three")

	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var expected_positions := [Vector2(539.7, 218.85), Vector2(479.7, 197.85), Vector2(403.6, 159.45)]
	for index in arena_ids.size():
		GameState.current_map_id = arena_ids[index]
		GameState.pk_race_active = true
		main._apply_current_map()
		assert(main.interactive_actors.size() == 1, "PK arena contains more than its own champion")
		var actor_id: String = "battle:" + str(champion_ids[index])
		assert(main.interactive_actors.has(actor_id), "PK champion actor is missing: " + champion_ids[index])
		var champion_actor: TextureRect = main.interactive_actors[actor_id]
		assert(champion_actor.position == expected_positions[index], "PK champion placement differs from the SWF")
		assert(champion_actor.size.is_equal_approx(Vector2(101, 132)), "PK champion does not use the native Boss standing bounds: %s" % champion_actor.size)
		assert(champion_actor.texture.resource_path.ends_with("image_1072.png"), "PK champion does not use the generic Boss standing bitmap")
		assert(main.scene_battle_controller._uses_native_boss_clip(champion_actor), "PK champion is excluded from native Boss attack/hit animation")
	GameState.pk_race_active = false
	main._apply_current_map()
	assert(main.interactive_actors.is_empty(), "finished PK champion remained on the map")

	var combat := CombatService.new(7)
	var expected_exp := [400000, 1500000, 2500000]
	var expected_stones := [27000, 56000, 82800]
	for index in champion_ids.size():
		assert(bool(combat.get_monster(champion_ids[index]).get("is_boss", false)), "SWF isBoss flag was not restored for PK champion")
		var rewards := combat.victory_rewards(champion_ids[index])
		assert(rewards.experience == expected_exp[index], "PK experience reward is incorrect")
		assert(rewards.magic_stones == expected_stones[index], "PK magic-stone reward is incorrect")
	var top_drops := combat.roll_drops("pk_champion_130", [0.0, 0.0, 0.0, 0.0])
	assert("plasma_potion" in top_drops and not "lava_potion" in top_drops, "top PK prize uses the wrong potion")
	assert("advanced_fighting_spirit" in top_drops and "enhanced_moon_box" in top_drops and "rose_bouquet_999" in top_drops, "top PK prize list is incomplete")

	GameState.current_day = 34
	GameState.level = 130
	GameState.last_pk_race_day = 0
	assert(GameState.register_pk_race().success, "save fixture could not enter the PK match")
	GameState.save_path = "user://test_pk_tournament_v18.json"
	assert(GameState.save_game(), "PK v18 save failed")
	GameState.current_map_id = "cassano_city"
	GameState.last_pk_race_day = 0
	GameState.pk_race_active = false
	assert(GameState.load_game(), "PK v18 save could not be loaded")
	assert(GameState.current_map_id == "pk_arena_3" and GameState.pk_race_active and GameState.last_pk_race_day == 34, "active PK match was not restored")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))

	print("PASS native three-group PK tournament, generic Boss clip, rewards, actors, and save v18")
	get_tree().quit(0)
