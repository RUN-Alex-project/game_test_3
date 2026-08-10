extends Node


func _no_legacy_panel(root: Node) -> bool:
	for n in root.find_children("*", "", true, false):
		var s = n.get_script()
		if s != null and s is GDScript and (s.resource_path.ends_with("map_panel.gd") or s.resource_path.ends_with("battle_panel.gd")):
			return false
	return true


func _ready() -> void:
	GameState.current_map_id = "dream_swamp"
	GameState.level = 30
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

	var actor: TextureRect = main.interactive_actors["battle:spider"]
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	main._on_actor_input(click, "battle:spider")

	assert(_no_legacy_panel(main), "direct monster click opened the legacy battle panel")
	assert(main.scene_battle_controller.session != null, "scene battle session did not start")
	assert(main.scene_battle_controller.active_monster_id == "spider", "wrong scene battle target")
	assert(main.scene_battle_controller.session.turn == 1, "first monster click must attack immediately")
	assert(main.scene_battle_controller.enemy_panel.visible, "enemy floating HP panel is missing")
	assert(main.scene_battle_controller.enemy_panel.size == Vector2(80, 8), "enemy HP strip does not match the native 80x8 HUD")
	for button: Button in main.direction_buttons.values():
		if button.visible:
			assert(button.disabled, "map exit remained active during combat")

	var player_position: Vector2 = main.player.position
	main._process(0.25)
	assert(main.player.position == player_position, "player movement was not locked during combat")
	await get_tree().create_timer(0.70).timeout

	GameState.learned_skills = {"flying_slash":1}
	var hp_before_skill := int(main.scene_battle_controller.session.monster_hp)
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	main._on_actor_input(right_click, "battle:spider")
	assert(main.scene_battle_controller.last_attack_skill_id == "flying_slash", "right click did not choose the learned active skill")
	assert(int(main.scene_battle_controller.session.monster_hp) < hp_before_skill, "right-click active skill did not damage the target")
	await get_tree().create_timer(0.70).timeout

	var locked_session = main.scene_battle_controller.session
	var locked_turn := int(locked_session.turn)
	main._on_actor_input(click, "battle:swamp_fanged_demon@1")
	assert(main.scene_battle_controller.session == locked_session, "clicking another monster replaced the active battle session")
	assert(main.scene_battle_controller.active_monster_id == "spider" and int(locked_session.turn) == locked_turn, "combat target lock did not hold")

	main.scene_battle_controller.session.monster_hp = 1
	main._on_actor_input(click, "battle:spider")
	await get_tree().create_timer(0.8).timeout
	assert(main.scene_battle_controller.session == null, "victory did not close the scene battle")
	assert(not main.scene_battle_controller.enemy_panel.visible, "enemy HP panel remained after victory")
	assert(actor.mouse_filter == Control.MOUSE_FILTER_IGNORE, "defeated monster stayed clickable during respawn")
	assert(not actor.visible, "native death removal left the defeated monster visible")
	await get_tree().create_timer(2.3).timeout
	assert(actor.mouse_filter == Control.MOUSE_FILTER_STOP, "monster did not respawn after scene victory")
	print("PASS native 80x8 scene combat HUD, left/right click attacks, target lock, rewards, and respawn")
	get_tree().quit(0)
