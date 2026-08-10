extends Node


func _left_click(main: Control, action_id: String) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	main._on_actor_input(click, action_id)


func _ready() -> void:
	GameState.level = 1
	GameState.current_map_id = "thunder_continent"
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

	var boss_action := "battle:thunder_boss_10"
	var boss_actor: TextureRect = main.interactive_actors[boss_action]
	var boss_texture := boss_actor.texture
	var boss_position := boss_actor.position
	var boss_size := boss_actor.size
	_left_click(main, boss_action)
	# v1.37 整改04：事件驱动轮询目标贴图（受击帧 2/12s 应用；不用固定 create_timer），带超时与明确失败原因。
	var hit_elapsed := 0.0
	while not (boss_actor.texture != null and boss_actor.texture.resource_path.ends_with("boss_hit_native.png")) and hit_elapsed < 1.0:
		await get_tree().create_timer(0.02).timeout
		hit_elapsed += 0.02
	assert(boss_actor.texture != null and boss_actor.texture.resource_path.ends_with("boss_hit_native.png"),
		"Boss hit frame did not apply (timeout %.2fs)" % hit_elapsed)
	assert(main.scene_battle_controller.native_hit_active, "native Boss hit segment did not start")
	assert(main.scene_battle_controller.last_target_hit_kind == "boss_native_shape", "generic Boss did not use shape133")
	assert(boss_actor.texture.get_width() == 123 and boss_actor.texture.get_height() == 148, "rasterized Boss hit frame dimensions are wrong")
	assert(boss_actor.position == boss_position + Vector2(0, -7), "Boss hit frame offset is wrong")
	assert(boss_actor.size == Vector2(123, 148), "Boss hit frame display size is wrong")
	main.scene_battle_controller.cancel_battle()
	assert(not main.scene_battle_controller.native_hit_active, "cancel battle left Boss hit state active")
	assert(boss_actor.texture == boss_texture and boss_actor.position == boss_position and boss_actor.size == boss_size, "cancel battle did not restore Boss standing art")

	GameState.current_map_id = "dream_swamp"
	main._apply_current_map()
	var normal_action := "battle:spider"
	var normal_actor: TextureRect = main.interactive_actors[normal_action]
	var normal_texture := normal_actor.texture
	var normal_position := normal_actor.position
	_left_click(main, normal_action)
	assert(main.scene_battle_controller.last_target_hit_kind == "normal_damage_only", "normal monster invented a non-native hit sprite animation")
	assert(not main.scene_battle_controller.native_hit_active, "normal monster incorrectly entered native Boss hit state")
	assert(normal_actor.texture == normal_texture and normal_actor.position == normal_position and normal_actor.rotation == 0.0, "normal monster changed art during its damage-only hit feedback")
	main.scene_battle_controller.cancel_battle()

	GameState.current_map_id = "dungeon"
	main._apply_current_map()
	var special_action := "battle:dungeon_boss"
	var special_actor: TextureRect = main.interactive_actors[special_action]
	_left_click(main, special_action)
	assert(bool(main.scene_battle_controller.session.monster.get("is_boss", false)), "dungeon test target is not data-classified as a Boss")
	assert(main.scene_battle_controller.last_target_hit_kind == "normal_damage_only", "special Boss incorrectly used the generic Boss clip hit shape")
	await get_tree().create_timer(0.28).timeout
	assert(main.scene_battle_controller.last_target_attack_kind == "normal_lunge", "special Boss incorrectly changed into generic Boss attack frames")

	# P2 拒签整改：退出前等待挂起协程恢复（全量负载下 2 帧不足，用定时等待保证取消/挂起协程完成）
	await get_tree().create_timer(0.3).timeout
	await get_tree().process_frame
	print("PASS rasterized shape133 Boss hit, normal damage-only feedback, and visual clip classification")
	get_tree().quit(0)
