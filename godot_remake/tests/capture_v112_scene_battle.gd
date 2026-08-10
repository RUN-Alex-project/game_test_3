extends Node


func _no_legacy_panel(root: Node) -> bool:
	for n in root.find_children("*", "", true, false):
		var s = n.get_script()
		if s != null and s is GDScript and (s.resource_path.ends_with("map_panel.gd") or s.resource_path.ends_with("battle_panel.gd")):
			return false
	return true


func _capture(path: String) -> void:
	for _frame in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	assert(image.get_width() == 700 and image.get_height() == 550, "capture viewport is not 700x550")
	assert(image.save_png(path) == OK, "failed to save v1.12 battle capture")


func _ready() -> void:
	GameState.current_map_id = "dream_swamp"
	GameState.level = 30
	GameState.learned_skills = {"flying_slash":1}
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	for _frame in 6:
		await get_tree().process_frame

	var left_click := InputEventMouseButton.new()
	left_click.button_index = MOUSE_BUTTON_LEFT
	left_click.pressed = true
	main._on_actor_input(left_click, "battle:spider")
	assert(_no_legacy_panel(main), "legacy battle panel appeared in capture")
	assert(main.scene_battle_controller.enemy_panel.visible, "native enemy HP strip is not visible")
	assert(main.scene_battle_controller.enemy_panel.size == Vector2(80, 8), "native enemy HP strip is not 80x8")
	var output_dir := ProjectSettings.globalize_path("res://tests/artifacts")
	DirAccess.make_dir_recursive_absolute(output_dir)
	await _capture(output_dir.path_join("scene_battle_native_click.png"))

	await get_tree().create_timer(0.35).timeout
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	main._on_actor_input(right_click, "battle:spider")
	assert(main.scene_battle_controller.last_attack_skill_id == "flying_slash", "capture quick skill did not start")
	await _capture(output_dir.path_join("scene_battle_native_skill.png"))
	print("PASS captured native click battle and quick skill HUD at 700x550")
	get_tree().quit(0)
