extends Node


func _ready() -> void:
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

	assert(main.player_idle_frames.size() == 8, "native standing clip must contain eight timeline frames")
	assert(main.player_walk_frames.down.size() == 8, "native down clip must contain eight timeline frames")
	assert(main.player_walk_frames.up.size() == 8, "native up clip must contain eight timeline frames")
	assert(main.player_walk_frames.left.size() == 10, "native left clip must contain ten timeline frames")
	assert(main.player_walk_frames.right.size() == 10, "native right clip must contain ten timeline frames")
	assert(main.player.texture.resource_path.ends_with("image_0455.png"), "native standing frame A is not the initial pose")

	main._update_player_animation(Vector2.ZERO, 4.0 / 12.0 + 0.001)
	assert(main.player.texture.resource_path.ends_with("image_0457.png"), "native standing frame B did not start on frame five")
	main._update_player_animation(Vector2.ZERO, 4.0 / 12.0)
	assert(main.player.texture.resource_path.ends_with("image_0455.png"), "native standing clip did not loop after eight frames")

	main._update_player_animation(Vector2.DOWN, 0.0)
	assert(main.player.texture.resource_path.ends_with("image_0465.png"), "down clip uses the wrong first bitmap")
	main._update_player_animation(Vector2.DOWN, 4.0 / 12.0 + 0.001)
	assert(main.player.texture.resource_path.ends_with("image_0467.png"), "down clip uses the wrong second bitmap")

	main._update_player_animation(Vector2.UP, 0.0)
	assert(main.player.texture.resource_path.ends_with("image_0470.png"), "up clip uses the wrong first bitmap")
	main._update_player_animation(Vector2.UP, 4.0 / 12.0 + 0.001)
	assert(main.player.texture.resource_path.ends_with("image_0472.png"), "up clip uses the wrong second bitmap")

	main._update_player_animation(Vector2.LEFT, 0.0)
	assert(main.player.texture.resource_path.ends_with("image_0475.png"), "left clip uses the wrong first bitmap")
	main._update_player_animation(Vector2.LEFT, 4.0 / 12.0 + 0.001)
	assert(main.player.texture.resource_path.ends_with("image_0477.png"), "left transition frame is missing")
	main._update_player_animation(Vector2.LEFT, 1.0 / 12.0 + 0.001)
	assert(main.player.texture.resource_path.ends_with("image_0479.png"), "left stride frame is missing")

	main._update_player_animation(Vector2.RIGHT, 0.0)
	assert(main.player.texture.resource_path.ends_with("image_0482.png"), "right clip incorrectly mirrors the left bitmap")
	main._update_player_animation(Vector2.RIGHT, 4.0 / 12.0 + 0.001)
	assert(main.player.texture.resource_path.ends_with("image_0484.png"), "right transition frame is missing")
	main._update_player_animation(Vector2.RIGHT, 1.0 / 12.0 + 0.001)
	assert(main.player.texture.resource_path.ends_with("image_0486.png"), "right stride frame is missing")

	main._update_player_animation(Vector2.ZERO, 0.0)
	assert(main.player_animation_clip == "idle" and main.player.texture.resource_path.ends_with("image_0455.png"), "movement did not return to the native standing clip")
	assert(main.scene_battle_controller.player_actor == main.player, "scene battle controller does not share the animated world player")

	print("PASS native sprite523 standing and four-direction 12fps movement clips")
	get_tree().quit(0)
