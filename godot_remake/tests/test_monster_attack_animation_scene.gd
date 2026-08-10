extends Node


func _left_click(main: Control, action_id: String) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	main._on_actor_input(click, action_id)


func _ready() -> void:
	GameState.level = 1
	GameState.current_map_id = "dream_swamp"
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

	var normal_action := "battle:spider"
	var normal_actor: TextureRect = main.interactive_actors[normal_action]
	var normal_position := normal_actor.position
	_left_click(main, normal_action)
	# 整改09：normal 攻击为离散帧（SWF sprite124 frame7 Move+HasMatrix 单帧位移，无补间证据）：
	# 帧0 offset(-5,0) 保持 1/12s -> 帧1 offset(0,0) 保持 1/12s -> once_restore。
	# 事件驱动轮询观察帧0 偏移出现（不依赖猜测 timer）。
	var lunged := false
	for i in range(300):
		if normal_actor.position == normal_position + Vector2(-5, 0):
			lunged = true
			break
		await get_tree().process_frame
	assert(lunged, "normal monster did not lunge 5px (discrete frame0 offset)")
	assert(main.scene_battle_controller.native_attack_active, "normal monster attack animation did not start")
	assert(main.scene_battle_controller.last_target_attack_kind == "normal_lunge", "normal monster did not use the native five-pixel lunge")
	# 事件驱动轮询观察回位（帧1 offset(0,0)），再观察 once_restore 结束（native_attack_active 清除）
	var returned := false
	for i in range(300):
		if normal_actor.position == normal_position:
			returned = true
			break
		await get_tree().process_frame
	assert(returned, "normal monster did not return to its exact standing position")
	var finished := false
	for i in range(300):
		if not main.scene_battle_controller.native_attack_active:
			finished = true
			break
		await get_tree().process_frame
	assert(finished, "normal monster attack animation did not finish")
	main.scene_battle_controller.cancel_battle()

	GameState.current_map_id = "thunder_continent"
	main._apply_current_map()
	var boss_action := "battle:thunder_boss_10"
	var boss_actor: TextureRect = main.interactive_actors[boss_action]
	var boss_position := boss_actor.position
	var boss_size := boss_actor.size
	var boss_texture := boss_actor.texture
	_left_click(main, boss_action)
	await get_tree().create_timer(0.39).timeout
	assert(main.scene_battle_controller.native_attack_active, "boss attack animation did not start")
	assert(main.scene_battle_controller.last_target_attack_kind == "boss_frames", "boss did not use its native attack frames")
	assert(boss_actor.position == boss_position + Vector2(-33, -42), "boss attack frame offset is not native")
	assert(boss_actor.size == Vector2(186, 173), "boss attack frame size is not native")
	assert(boss_actor.texture.resource_path.ends_with("image_0127.png") or boss_actor.texture.resource_path.ends_with("image_0129.png"), "boss attack bitmap is not one of the two native frames")
	await get_tree().create_timer(0.35).timeout
	assert(not main.scene_battle_controller.native_attack_active, "boss attack animation did not finish")
	assert(boss_actor.position == boss_position and boss_actor.size == boss_size and boss_actor.texture == boss_texture, "boss did not restore its exact standing art")

	main.scene_battle_controller.cancel_battle()
	_left_click(main, boss_action)
	await get_tree().create_timer(0.39).timeout
	assert(main.scene_battle_controller.native_attack_active, "boss cancel test did not reach the attack frame")
	main.scene_battle_controller.cancel_battle()
	assert(not main.scene_battle_controller.native_attack_active, "cancel battle left native attack state active")
	assert(boss_actor.position == boss_position and boss_actor.size == boss_size and boss_actor.texture == boss_texture, "cancel battle did not immediately restore standing art")

	# P2 拒签整改：退出前恢复帧，让被取消/挂起的协程状态完成（消除 GDScriptFunctionState 泄漏）
	await get_tree().process_frame
	await get_tree().process_frame
	print("PASS native normal-monster lunge, boss attack frames, and cancel restoration")
	get_tree().quit(0)
