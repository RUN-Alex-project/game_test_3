extends Node

const STEP: float = 1.0 / 60.0
var main: Node = null

func _ready() -> void:
	for action in ["ui_left", "ui_right", "ui_up", "ui_down"]:
		assert(InputMap.has_action(action), "missing built-in action: " + action)
	assert(_action_has_key("ui_up", KEY_W), "ui_up not bound to W (WASD missing)")
	assert(_action_has_key("ui_left", KEY_A), "ui_left not bound to A (WASD missing)")
	assert(_action_has_key("ui_down", KEY_S), "ui_down not bound to S (WASD missing)")
	assert(_action_has_key("ui_right", KEY_D), "ui_right not bound to D (WASD missing)")
	assert(_action_has_key("ui_up", KEY_UP), "ui_up not bound to Up arrow")
	assert(_action_has_key("ui_left", KEY_LEFT), "ui_left not bound to Left arrow")
	assert(_action_has_key("ui_down", KEY_DOWN), "ui_down not bound to Down arrow")
	assert(_action_has_key("ui_right", KEY_RIGHT), "ui_right not bound to Right arrow")

	main = preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(not main.scene_battle_controller.is_active(), "battle active at startup blocks movement")

	# === P4: REAL engine loop (set_process stays true, real process_frame) ===
	# Proves the actual _process input loop moves the player, not just the math.
	main.player.position = Vector2(310, 270)
	await get_tree().process_frame
	var real_start: Vector2 = main.player.position
	Input.action_press("ui_right")
	for _i in 60:
		await get_tree().process_frame
	Input.action_release("ui_right")
	await get_tree().process_frame
	var real_after: Vector2 = main.player.position
	print("REAL_LOOP right: %s -> %s (dx=%.4f)" % [str(real_start), str(real_after), real_after.x - real_start.x])
	assert(real_after.x > real_start.x, "real engine loop: right input did not move player (dx=%.4f)" % (real_after.x - real_start.x))

	# real loop boundary: start near right edge, press right, must clamp
	var real_bound_right: float = 700.0 - main.player.size.x
	main.player.position = Vector2(real_bound_right - 2.0, 270)
	await get_tree().process_frame
	Input.action_press("ui_right")
	for _i in 60:
		await get_tree().process_frame
	Input.action_release("ui_right")
	await get_tree().process_frame
	var real_clamp_x: float = main.player.position.x
	print("REAL_LOOP boundary right: x=%.4f (max %.4f)" % [real_clamp_x, real_bound_right])
	assert(real_clamp_x <= real_bound_right + 0.01, "real loop: player exceeded right boundary: %s" % str(real_clamp_x))

	# Now switch to deterministic direct-_process calls for precise 4-direction + boundary coverage.
	main.set_process(false)
	main.player.position = Vector2(310, 270)

	var start: Vector2 = main.player.position
	_press("ui_right", 30)
	var after_right: Vector2 = main.player.position
	print("MOVE right: %s -> %s (dx=%.2f)" % [str(start), str(after_right), after_right.x - start.x])
	assert(after_right.x > start.x, "right input did not move player right")

	main.player.position = Vector2(310, 270)
	_press("ui_left", 30)
	var after_left: Vector2 = main.player.position
	print("MOVE left: 310 -> %s (dx=%.2f)" % [str(after_left), after_left.x - 310.0])
	assert(after_left.x < 310.0, "left input did not move player left")

	main.player.position = Vector2(310, 270)
	_press("ui_up", 30)
	var after_up: Vector2 = main.player.position
	print("MOVE up: 270 -> %s (dy=%.2f)" % [str(after_up), after_up.y - 270.0])
	assert(after_up.y < 270.0, "up input did not move player up")

	main.player.position = Vector2(310, 270)
	_press("ui_down", 30)
	var after_down: Vector2 = main.player.position
	print("MOVE down: 270 -> %s (dy=%.2f)" % [str(after_down), after_down.y - 270.0])
	assert(after_down.y > 270.0, "down input did not move player down")

	var bound_right: float = 700.0 - main.player.size.x
	main.player.position = Vector2(310, 270)
	_press("ui_right", 600)
	var max_x: float = main.player.position.x
	print("BOUNDARY right: x=%.2f (max %.2f)" % [max_x, bound_right])
	assert(max_x <= bound_right + 0.01 and max_x >= 0.0, "player right boundary clamp failed: %s" % str(max_x))

	main.player.position = Vector2(310, 270)
	_press("ui_left", 600)
	var min_x: float = main.player.position.x
	print("BOUNDARY left: x=%.2f (min 0)" % [min_x])
	assert(min_x >= 0.0 and min_x <= bound_right + 0.01, "player left boundary clamp failed: %s" % str(min_x))

	main.player.position = Vector2(310, 270)
	_press("ui_up", 600)
	var min_y: float = main.player.position.y
	print("BOUNDARY top: y=%.2f (min 72)" % [min_y])
	assert(min_y >= 72.0 - 0.01, "player top boundary clamp failed: %s" % str(min_y))

	var bound_bottom: float = 476.0 - main.player.size.y
	main.player.position = Vector2(310, 270)
	_press("ui_down", 600)
	var max_y: float = main.player.position.y
	print("BOUNDARY bottom: y=%.2f (max %.2f)" % [max_y, bound_bottom])
	assert(max_y <= bound_bottom + 0.01 and max_y >= 72.0, "player bottom boundary clamp failed: %s" % str(max_y))

	print("PASS player movement: WASD+arrows bound, 4-direction motion, 4 boundary clamps")
	get_tree().quit(0)

func _press(action: String, frames: int) -> void:
	Input.action_press(action)
	for _i in frames:
		main._process(STEP)
	Input.action_release(action)

func _action_has_key(action: String, keycode: int) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey and e.keycode == keycode:
			return true
	return false
